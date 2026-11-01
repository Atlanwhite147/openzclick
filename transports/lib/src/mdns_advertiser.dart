/// Service announcement on the local network (mDNS/DNS-SD).
///
/// This file contains **no** native implementation: the `transports` package may
/// only depend on `openzclick_core`, `meta` and `test`. A real announcement needs
/// a platform API (see [PlatformMdnsAdvertiser]) that the application has to
/// wire.
///
/// What is actually shipped here:
/// * the [MdnsAdvertiser] contract every implementation must follow;
/// * the service description [MdnsService] and the [MdnsTxt] helper that builds
///   and validates TXT records;
/// * [InMemoryMdnsAdvertiser], a test implementation recording announcements in
///   memory, used by the tests without any network;
/// * [NoopMdnsAdvertiser], which announces nothing but lets the TCP server run
///   without discovery;
/// * [PlatformMdnsAdvertiser], an explicit skeleton raising
///   [UnimplementedError]: it does not pretend to work.
library;

import 'dart:collection';

/// Description of a service to announce.
class MdnsService {
  /// Builds a service description.
  ///
  /// Throws [ArgumentError] when the instance name is empty, when the service
  /// type is not shaped like `_name._tcp` or `_name._udp`, or when the port is
  /// out of range.
  MdnsService({
    required this.instanceName,
    required this.serviceType,
    required this.port,
    Map<String, String> txt = const <String, String>{},
  }) : txt = UnmodifiableMapView<String, String>(Map<String, String>.of(txt)) {
    if (instanceName.trim().isEmpty) {
      throw ArgumentError.value(
          instanceName, 'instanceName', 'must not be empty');
    }
    if (!_serviceTypePattern.hasMatch(serviceType)) {
      throw ArgumentError.value(
        serviceType,
        'serviceType',
        'expected shape: _name._tcp or _name._udp',
      );
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'must be 1..65535');
    }
  }

  static final RegExp _serviceTypePattern =
      RegExp(r'^_[A-Za-z0-9-]{1,15}\.(_tcp|_udp)$');

  /// Human readable instance name, unique on the local network.
  final String instanceName;

  /// Service type, for example `_openbikecontrol._tcp`.
  final String serviceType;

  /// TCP port of the server to connect to.
  final int port;

  /// TXT records of the announcement, unmodifiable.
  final Map<String, String> txt;

  @override
  String toString() => 'MdnsService($instanceName, $serviceType, port $port, '
      'txt: $txt)';
}

/// Building and validation of the announcement TXT records.
///
/// The keys and their contents follow the OpenBikeControl mDNS specification:
/// `version`, `id`, `name`, `service-uuids`, `manufacturer` and `model`. A TXT
/// record fits in 255 bytes overall, key and value included.
abstract final class MdnsTxt {
  /// Protocol version exposed in the TXT record, key `version`.
  static const String versionKey = 'version';

  /// Current application protocol version.
  static const String currentVersion = '1';

  /// Human readable name of the bridge, key `name`.
  static const String nameKey = 'name';

  /// Unique device identifier, key `id`. Derived from the advertised name, so
  /// that one bridge keeps a stable identifier across restarts.
  static const String idKey = 'id';

  /// Service UUIDs the device exposes, key `service-uuids`.
  static const String serviceUuidsKey = 'service-uuids';

  /// OpenBikeControl GATT service UUID, the only one announced today.
  static const String serviceUuid = 'd273f680-d548-419d-b9d1-fa0472345229';

  /// Manufacturer of the device, key `manufacturer`.
  static const String manufacturerKey = 'manufacturer';

  /// Manufacturer announced by the bridge.
  static const String manufacturer = 'openzclick';

  /// Model of the device, key `model`.
  static const String modelKey = 'model';

  /// Model announced by the bridge.
  static const String model = 'bridge';

  /// Maximum length of a TXT value, in bytes.
  static const int maxValueLength = 255;

  /// Assembles the TXT records of a bridge announcement.
  ///
  /// [id] defaults to a stable digest of [name], so that one configuration
  /// always produces the same announcement.
  static Map<String, String> build({
    required String name,
    String? id,
    String version = currentVersion,
    String manufacturer = MdnsTxt.manufacturer,
    String model = MdnsTxt.model,
  }) {
    return <String, String>{
      versionKey: version,
      idKey: id ?? deviceId(name),
      nameKey: name,
      serviceUuidsKey: serviceUuid,
      manufacturerKey: manufacturer,
      modelKey: model,
    };
  }

  /// Stable identifier of a bridge, derived from its advertised [name].
  static String deviceId(String name) {
    int hash = 0x811c9dc5;
    for (final int byte in name.codeUnits) {
      hash = (hash ^ byte) & 0xFFFFFFFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Longest TXT key accepted.
  ///
  /// RFC 6763 recommends nine characters at most, but the OpenBikeControl
  /// specification names two longer keys, `service-uuids` and `manufacturer`,
  /// and interoperability wins over the recommendation.
  static const int maxKeyLength = 16;

  /// Checks that a set of records can be announced.
  ///
  /// Throws [ArgumentError] when a key is empty or longer than
  /// [maxKeyLength], or when a value exceeds [maxValueLength] bytes.
  static void validate(Map<String, String> txt) {
    txt.forEach((String key, String value) {
      if (key.isEmpty) {
        throw ArgumentError('empty TXT key');
      }
      if (key.length > maxKeyLength) {
        throw ArgumentError.value(
            key, 'key', 'TXT key of at most $maxKeyLength characters');
      }
      for (final int unit in value.codeUnits) {
        if (unit > 0x7F) {
          throw ArgumentError.value(
            value,
            'value',
            'TXT values must be ASCII (key $key)',
          );
        }
      }
      if (value.length > maxValueLength) {
        throw ArgumentError.value(
          value.length,
          'value',
          'TXT value of at most $maxValueLength bytes (key $key)',
        );
      }
    });
  }
}

/// mDNS announcement contract.
///
/// An implementation announces one service at a time: [register] replaces the
/// previous announcement, [unregister] removes it. Both methods are idempotent.
abstract interface class MdnsAdvertiser {
  /// Publishes [service] on the local network.
  Future<void> register(MdnsService service);

  /// Removes the current announcement, no effect when there is none.
  Future<void> unregister();
}

/// Test implementation: announcements stay in memory.
///
/// No packet is emitted on the network. Used to verify that a transport
/// announces the right name, port and TXT records.
class InMemoryMdnsAdvertiser implements MdnsAdvertiser {
  final List<MdnsService> _history = <MdnsService>[];
  MdnsService? _current;

  /// Current announcement, `null` when no service is announced.
  MdnsService? get current => _current;

  /// True when a service is announced.
  bool get isAdvertising => _current != null;

  /// Every announcement recorded since creation, in order.
  List<MdnsService> get history => List<MdnsService>.unmodifiable(_history);

  /// Number of successful [register] calls.
  int get registerCount => _history.length;

  @override
  Future<void> register(MdnsService service) async {
    MdnsTxt.validate(service.txt);
    _history.add(service);
    _current = service;
  }

  @override
  Future<void> unregister() async {
    _current = null;
  }
}

/// Neutral implementation: announces nothing.
///
/// Used as the default so that the TCP server stays usable without discovery
/// (connection by known address). No lying: [isAdvertising] stays false and no
/// mDNS packet is emitted.
class NoopMdnsAdvertiser implements MdnsAdvertiser {
  MdnsService? _current;

  /// True when [register] was called without [unregister] since.
  bool get isAdvertising => _current != null;

  @override
  Future<void> register(MdnsService service) async {
    MdnsTxt.validate(service.txt);
    _current = service;
  }

  @override
  Future<void> unregister() async {
    _current = null;
  }
}

/// Skeleton of the native announcement, deliberately not implemented.
///
/// What still has to be wired, per platform, with a service discovery plugin
/// (none is allowed as a dependency of this package):
///
/// * Android: `NsdManager` (`android.net.nsd`), `registerService` with the
///   `_openbikecontrol._tcp` type, the TCP server port and the TXT attributes;
/// * iOS/macOS: `NWListener` with `NWListener.Service`, or `NetService` in
///   publish mode;
/// * Linux: an `avahi-daemon` client over DBus (`org.freedesktop.Avahi`);
/// * Windows: the `DnsServiceRegister` API of the DNS discovery service.
///
/// Until that wiring exists, any attempt to announce raises
/// [UnimplementedError]: the transport stays usable as plain TCP, but no client
/// can discover the service.
class PlatformMdnsAdvertiser implements MdnsAdvertiser {
  /// Creates an unwired native advertiser.
  const PlatformMdnsAdvertiser({this.platformHint});

  /// Targeted platform, used in the error message (`android`, `ios`, `linux`,
  /// `windows`). Purely informative.
  final String? platformHint;

  @override
  Future<void> register(MdnsService service) async {
    throw UnimplementedError(
      'native mDNS announcement not wired'
      '${platformHint == null ? '' : ' for $platformHint'}: bind '
      'MdnsAdvertiser to the platform discovery API '
      '(NsdManager, NWListener, Avahi DBus or DnsServiceRegister)',
    );
  }

  @override
  Future<void> unregister() async {
    // Nothing was announced: nothing to remove.
  }
}

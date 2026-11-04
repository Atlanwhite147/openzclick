/// A snapshot of a controller link, written to be pasted into an issue.
///
/// Most of the bridge is written on a machine with no Bluetooth radio, so most
/// rules run against a fake controller. What closes that gap is not a description of a
/// dropout — descriptions arrive incomplete and unreproducible — but the raw
/// material: which services and characteristics the device actually exposes,
/// what its firmware calls itself, and the last frames it sent before going
/// quiet.
///
/// This file holds the shape of that material and the text it becomes. It is
/// deliberately free of any Bluetooth dependency: a report is built from plain
/// values, so the formatting is tested on the host and the same text is produced
/// on every platform.
library;

import 'bluetooth_uuid.dart';

/// Where a frame went.
enum FrameDirection {
  /// Received from the controller.
  inbound,

  /// Written to the controller.
  outbound,
}

/// One frame, as it appeared on the wire.
class FrameRecord {
  /// Creates a record.
  const FrameRecord({
    required this.elapsed,
    required this.characteristic,
    required this.direction,
    required this.bytes,
  });

  /// Time since the link was established.
  ///
  /// Relative on purpose: an absolute clock in the report tells a reader nothing
  /// and leaks when and where the rider was, which is not needed to debug a
  /// handshake.
  final Duration elapsed;

  /// Characteristic the frame travelled on, in canonical form.
  final String characteristic;

  /// Whether the controller sent it or the bridge wrote it.
  final FrameDirection direction;

  /// Bytes, exactly as they were exchanged.
  final List<int> bytes;
}

/// A characteristic as the device describes it.
class GattCharacteristicInfo {
  /// Creates a description.
  const GattCharacteristicInfo({
    required this.uuid,
    required this.properties,
    this.notifying = false,
  });

  /// Canonical UUID.
  final String uuid;

  /// Flags the device advertises, already spelled out (`read`, `notify`...).
  final List<String> properties;

  /// True when notifications were enabled on this characteristic.
  final bool notifying;
}

/// A service as the device describes it.
class GattServiceInfo {
  /// Creates a description.
  const GattServiceInfo({required this.uuid, required this.characteristics});

  /// Canonical UUID.
  final String uuid;

  /// Characteristics discovered under it.
  final List<GattCharacteristicInfo> characteristics;
}

/// Strings read from the Device Information service, when the device has one.
class DeviceInformation {
  /// Creates the set.
  const DeviceInformation({
    this.manufacturer,
    this.model,
    this.serial,
    this.firmware,
    this.hardware,
  });

  /// Manufacturer name (`0x2A29`).
  final String? manufacturer;

  /// Model number (`0x2A24`).
  final String? model;

  /// Serial number (`0x2A25`).
  final String? serial;

  /// Firmware revision (`0x2A26`), the one field a bug report is useless without.
  final String? firmware;

  /// Hardware revision (`0x2A27`).
  final String? hardware;

  /// True when at least one field was read.
  bool get isEmpty =>
      manufacturer == null &&
      model == null &&
      serial == null &&
      firmware == null &&
      hardware == null;
}

/// Everything an issue needs to be reproducible.
class DeviceReport {
  /// Creates a report.
  const DeviceReport({
    required this.generatedAt,
    required this.appVersion,
    required this.host,
    this.deviceName,
    this.deviceId,
    this.status,
    this.encrypted,
    this.needsUnlock,
    this.batteryPercent,
    this.error,
    this.information = const DeviceInformation(),
    this.services = const <GattServiceInfo>[],
    this.frames = const <FrameRecord>[],
  });

  /// When the report was taken.
  final DateTime generatedAt;

  /// Version of the application that produced it.
  final String appVersion;

  /// Host name, from [Capabilities.hostName] on the calling side.
  final String host;

  /// Advertised name, often the only way to tell a v1 from a v2.
  final String? deviceName;

  /// Platform identifier, which differs from the name.
  final String? deviceId;

  /// Last link status, in the code's own words.
  final String? status;

  /// Whether the session ended up encrypted.
  final bool? encrypted;

  /// Whether the controller stayed silent after the handshake.
  final bool? needsUnlock;

  /// Battery level, when the device reports one.
  final int? batteryPercent;

  /// Last error, verbatim.
  final String? error;

  /// Device Information strings.
  final DeviceInformation information;

  /// Discovered services, in the order the platform returned them.
  final List<GattServiceInfo> services;

  /// Frames exchanged, oldest first.
  final List<FrameRecord> frames;

  /// Renders the report as plain text.
  ///
  /// Plain text, not JSON: it is read by a human first and pasted into a thread
  /// second, and a wall of JSON gets skimmed. Anything a parser needs is still
  /// there, one fact per line.
  String render() {
    final StringBuffer out = StringBuffer();
    out.writeln('openzclick device report');
    out.writeln('  taken    ${_iso(generatedAt)}');
    out.writeln('  version  $appVersion');
    out.writeln('  host     $host');

    out.writeln('controller');
    out.writeln('  name     ${deviceName ?? 'unknown'}');
    out.writeln('  id       ${deviceId ?? 'unknown'}');
    if (status != null) out.writeln('  status   $status');
    if (encrypted != null) {
      out.writeln('  session  ${encrypted! ? 'encrypted' : 'plain'}');
    }
    if (needsUnlock == true) {
      out.writeln('  unlock   silent after the handshake');
    }
    if (batteryPercent != null) out.writeln('  battery  $batteryPercent %');
    if (error != null && error!.isNotEmpty) out.writeln('  error    $error');

    if (!information.isEmpty) {
      out.writeln('device information');
      _field(out, 'manufacturer', information.manufacturer);
      _field(out, 'model', information.model);
      _field(out, 'serial', information.serial);
      _field(out, 'firmware', information.firmware);
      _field(out, 'hardware', information.hardware);
    } else {
      out.writeln('device information');
      out.writeln('  none: the controller exposes no 0x180a service');
    }

    out.writeln('gatt tree (${services.length} services)');
    if (services.isEmpty) {
      out.writeln('  none discovered');
    }
    // Every identifier is reduced to its canonical form, because the same
    // service comes back as `fc82` under WinRT and as the full 128-bit string on
    // Android and iOS: a report a maintainer cannot compare across hosts is a
    // report they have to decode first.
    for (final GattServiceInfo service in services) {
      out.writeln('  service ${canonicalUuid(service.uuid)}');
      for (final GattCharacteristicInfo c in service.characteristics) {
        final String flags = c.properties.isEmpty
            ? ''
            : ' [${c.properties.join(', ')}]';
        final String notifying = c.notifying ? ' notifying' : '';
        out.writeln(
          '    characteristic ${canonicalUuid(c.uuid)}$flags$notifying',
        );
      }
    }

    out.writeln('frames (${frames.length}, oldest first)');
    if (frames.isEmpty) {
      out.writeln('  none: the link exchanged nothing');
    }
    for (final FrameRecord frame in frames) {
      final String arrow = frame.direction == FrameDirection.inbound
          ? '<-'
          : '->';
      out.writeln(
        '  ${_elapsed(frame.elapsed)} $arrow '
        '${canonicalUuid(frame.characteristic)} ${_hex(frame.bytes)}',
      );
    }
    return out.toString();
  }

  static void _field(StringBuffer out, String label, String? value) {
    if (value == null || value.isEmpty) return;
    out.writeln('  ${label.padRight(12)} $value');
  }

  /// Milliseconds with three digits, which is the resolution handshakes need.
  static String _elapsed(Duration d) {
    final int ms = d.inMilliseconds;
    final String sign = ms < 0 ? '-' : '+';
    final int abs = ms.abs();
    final String secs = (abs ~/ 1000).toString().padLeft(4, '0');
    final String millis = (abs % 1000).toString().padLeft(3, '0');
    return '$sign$secs.$millis';
  }

  static String _hex(List<int> bytes) =>
      bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  static String _iso(DateTime t) =>
      '${t.toUtc().toIso8601String().split('.').first}Z';
}

/// Keeps the last [capacity] frames of a link.
///
/// A dropout is explained by what came just before it, not by the whole ride: a
/// ring buffer keeps the report short enough to paste in a thread and still
/// holds the moment that matters.
class FrameRing {
  /// Creates a ring holding at most [capacity] frames.
  FrameRing({this.capacity = 40})
    : assert(capacity > 0, 'a ring that holds nothing reports nothing');

  /// Maximum number of frames kept.
  final int capacity;

  final List<FrameRecord> _frames = <FrameRecord>[];

  /// Frames currently held, oldest first.
  List<FrameRecord> get frames => List<FrameRecord>.unmodifiable(_frames);

  /// Adds [frame], dropping the oldest beyond [capacity].
  void add(FrameRecord frame) {
    _frames.add(frame);
    if (_frames.length > capacity) {
      _frames.removeRange(0, _frames.length - capacity);
    }
  }

  /// Forgets everything, on each new link.
  void clear() => _frames.clear();
}

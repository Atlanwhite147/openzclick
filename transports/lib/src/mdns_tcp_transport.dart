/// Network transport: TCP server advertised on the local network over mDNS.
///
/// This is the classic bridge mode: the bridge opens a TCP server, advertises it
/// in DNS-SD under the `_openbikecontrol._tcp` type with its TXT records, and the
/// target application connects to it. The bridge pushes button state (`0x01`)
/// and device status (`0x02`); the application sends back haptic commands
/// (`0x03`) and its information (`0x04`).
///
/// Everything is functional except the native mDNS announcement, which depends
/// on a platform API and remains to be wired (see `mdns_advertiser.dart`).
/// Without a platform advertiser, the TCP server still accepts incoming
/// connections by address and port.
library;

import 'dart:async';
import 'dart:io';

import 'events.dart';
import 'mdns_advertiser.dart';
import 'tcp_server.dart';
import 'transport.dart';
import 'package:openzclick_core/openzclick_core.dart';

/// TCP transport advertised over mDNS.
class MdnsTcpTransport extends ManagedTransport {
  /// Creates the transport.
  ///
  /// [keymap] binds protocol button identifiers to actions: without a table,
  /// received frames are published raw ([TransportMessageReceived]) but no
  /// action is produced, and [emit] refuses to work (no action to button
  /// mapping).
  ///
  /// [advertiser] receives the mDNS announcement; by default
  /// [NoopMdnsAdvertiser], that is no announcement at all. Passing
  /// [PlatformMdnsAdvertiser] throws [UnimplementedError] at start until the
  /// native wiring exists: the neutral default avoids an application believing
  /// it advertises while nothing is published.
  ///
  /// [autoRelease] sets the delay after which a press sent by [emit] is
  /// released automatically, so that no button stays stuck on the application
  /// side. `null` disables it: the caller must then call [release].
  MdnsTcpTransport({
    this.keymap,
    this.instanceName = 'openzclick',
    MdnsAdvertiser? advertiser,
    InternetAddress? bindAddress,
    this.port = 0,
    this.autoRelease = const Duration(milliseconds: 60),
    this.deviceBattery = DeviceStatusMessage.unknownBattery,
    this.deviceConnected = true,
  })  : advertiser = advertiser ?? NoopMdnsAdvertiser(),
        bindAddress = bindAddress ?? InternetAddress.anyIPv4;

  /// DNS-SD service type advertised by the bridge.
  static const String serviceType = '_openbikecontrol._tcp';

  /// Button to action table used to translate received frames.
  final Keymap? keymap;

  /// Instance name advertised on the local network.
  final String instanceName;

  /// mDNS advertiser.
  final MdnsAdvertiser advertiser;

  /// Listening address of the TCP server.
  final InternetAddress bindAddress;

  /// Requested port; `0` for an ephemeral port chosen by the system.
  final int port;

  /// Automatic release delay for presses, `null` to disable it.
  final Duration? autoRelease;

  /// Battery level published by [publishStatus].
  final int deviceBattery;

  /// Connection state published by [publishStatus].
  final bool deviceConnected;

  FramedTcpServer? _server;
  StreamSubscription<ServerEvent>? _subscription;
  final Set<Timer> _releaseTimers = <Timer>{};
  AppInfo? _remoteAppInfo;
  DeviceStatus? _remoteStatus;

  @override
  String get id => 'mdns_tcp';

  /// Effective TCP port, `0` before [start].
  int get listeningPort => _server?.listeningPort ?? 0;

  /// Identifiers of the currently connected clients.
  List<String> get peerIds => _server?.peerIds ?? const <String>[];

  /// Last application information received, `null` when none.
  AppInfo? get remoteAppInfo => _remoteAppInfo;

  /// Last device status received from a client, `null` when none.
  DeviceStatus? get remoteStatus => _remoteStatus;

  /// True when an mDNS announcement is actually in progress.
  bool get isAdvertising => switch (advertiser) {
        final InMemoryMdnsAdvertiser a => a.isAdvertising,
        final NoopMdnsAdvertiser a => a.isAdvertising,
        _ => isRunning,
      };

  @override
  Future<void> onStart() async {
    final FramedTcpServer server = FramedTcpServer(
      bindAddress: bindAddress,
      port: port,
    );
    _server = server;
    _subscription = server.events.listen(_onServerEvent);
    try {
      await server.start();
      await advertiser.register(
        MdnsService(
          instanceName: instanceName,
          serviceType: serviceType,
          port: server.listeningPort,
          txt: MdnsTxt.build(
            name: instanceName,
            supportedButtons: keymap?.bindings.keys.toList() ?? const <int>[],
          ),
        ),
      );
    } catch (_) {
      // No half-started transport: give the port and the announcement back.
      await _subscription?.cancel();
      _subscription = null;
      await server.dispose();
      _server = null;
      await advertiser.unregister();
      rethrow;
    }
  }

  @override
  Future<void> onStop() async {
    for (final Timer timer in _releaseTimers) {
      timer.cancel();
    }
    _releaseTimers.clear();
    await advertiser.unregister();
    final FramedTcpServer? server = _server;
    _server = null;
    // Disposing the server first publishes the disconnection of every client;
    // the subscription is only released afterwards.
    await server?.dispose();
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Publishes the button state matching [action] to every client.
  ///
  /// Sends a press (value `1`) then, when [autoRelease] is set, a release after
  /// that delay. Throws [StateError] when the transport is stopped,
  /// [ArgumentError] when [keymap] binds no button to [action]. When no client
  /// is connected nothing is sent and a [TransportError] is published.
  @override
  Future<void> emit(Action action) async {
    if (!isRunning) {
      throw StateError(
          'transport $id stopped: start() is required before emit()');
    }
    final int buttonId = _buttonIdFor(action);
    await _sendButton(buttonId, 1);
    final Duration? delay = autoRelease;
    if (delay != null) {
      late final Timer timer;
      timer = Timer(delay, () {
        _releaseTimers.remove(timer);
        if (isRunning) {
          unawaited(_sendButton(buttonId, 0));
        }
      });
      _releaseTimers.add(timer);
    }
  }

  /// Explicitly releases [action] to the clients.
  ///
  /// Useful when [autoRelease] is `null` or when the press must last.
  Future<void> release(Action action) async {
    if (!isRunning) {
      throw StateError(
          'transport $id stopped: start() is required before release()');
    }
    await _sendButton(_buttonIdFor(action), 0);
  }

  /// Publishes the device status (`0x02`) to every client.
  Future<void> publishStatus({int? battery, bool? connected}) async {
    if (!isRunning) {
      throw StateError(
        'transport $id stopped: start() is required before publishStatus()',
      );
    }
    await _sendFrame(
      DeviceStatusMessage(
        battery: battery ?? deviceBattery,
        connected: connected ?? deviceConnected,
      ).encode(),
    );
  }

  /// Sends the raw [frame] to every connected client.
  Future<void> sendFrame(List<int> frame) async {
    if (!isRunning) {
      throw StateError(
          'transport $id stopped: start() is required before sendFrame()');
    }
    await _sendFrame(frame);
  }

  Future<void> _sendFrame(List<int> frame) async {
    final FramedTcpServer? server = _server;
    if (server == null) {
      return;
    }
    if (server.peerCount == 0) {
      publishError('no client connected: frame not sent');
      return;
    }
    await server.broadcast(frame);
  }

  Future<void> _sendButton(int buttonId, int value) async {
    await _sendFrame(ButtonStateMessage(<int, int>{buttonId: value}).encode());
  }

  int _buttonIdFor(Action action) {
    final Keymap? table = keymap;
    if (table == null) {
      throw ArgumentError(
        'no binding table: cannot translate ${action.name} into a button '
        'identifier',
      );
    }
    final List<int> candidates = table.bindings.entries
        .where((MapEntry<int, Action> entry) => entry.value == action)
        .map((MapEntry<int, Action> entry) => entry.key)
        .toList()
      ..sort();
    if (candidates.isEmpty) {
      throw ArgumentError(
        'action ${action.name} is not bound to any button in the table',
      );
    }
    return candidates.first;
  }

  void _onServerEvent(ServerEvent event) {
    switch (event) {
      case PeerConnected(:final String peerId, :final String label):
        publish(TransportConnected(
          transportId: id,
          peerId: peerId,
          label: label,
        ));
      case PeerDisconnected(:final String peerId, :final String? reason):
        publish(TransportDisconnected(
          transportId: id,
          peerId: peerId,
          reason: reason,
        ));
      case PeerMessage(:final String peerId, :final ObcMessage message):
        _onPeerMessage(peerId, message);
      case PeerFault(
          :final String peerId,
          :final String message,
          :final Object? cause,
        ):
        publishError(message, peerId: peerId, cause: cause);
    }
  }

  void _onPeerMessage(String peerId, ObcMessage message) {
    switch (message) {
      case ButtonState(:final Map<int, int> buttons):
        final Keymap? table = keymap;
        if (table != null) {
          for (final MapEntry<int, int> entry in buttons.entries) {
            // A zero value is a release: it triggers nothing.
            if (entry.value == 0) {
              continue;
            }
            final Action action = table.actionFor(entry.key);
            if (action == Action.none) {
              continue;
            }
            publish(TransportActionReceived(
              transportId: id,
              action: action,
              peerId: peerId,
              value: entry.value,
            ));
          }
        }
      case DeviceStatus status:
        _remoteStatus = status;
      case AppInfo info:
        _remoteAppInfo = info;
      case HapticCommand():
        break;
    }
    publish(TransportMessageReceived(
      transportId: id,
      message: message,
      peerId: peerId,
    ));
  }
}

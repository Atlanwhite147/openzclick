/// Headless bridge used to check the browser console by hand.
///
/// Starts the console relay alone, on a fixed port, keeps a gear engine, and
/// prints every action a page sends. Nothing else: no Bluetooth, no mDNS, no
/// training application. It exists so that `docs/console.md` can be verified
/// without a controller.
///
/// ```bash
/// dart run tool/console_bridge.dart 47124 abcd
/// ```
///
/// Every [tick] the bridge shifts up on its own and publishes the new state, which
/// is how the other direction is checked: a page left open must follow the gear
/// of the bridge without being touched.
library;

import 'dart:async';
import 'dart:io';

import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';

Future<void> main(List<String> arguments) async {
  final int port = arguments.isEmpty ? 47124 : int.parse(arguments[0]);
  final String token = arguments.length > 1
      ? arguments[1]
      : WebSocketRelayTransport.generateToken();
  final Duration tick = arguments.length > 2
      ? Duration(seconds: int.parse(arguments[2]))
      : Duration.zero;
  GearEngine engine = GearEngine(profile: GearProfile.road12, initialGear: 5);
  final WebSocketRelayTransport relay = WebSocketRelayTransport(
    port: port,
    token: token,
  );

  Future<void> publishState(String lastAction) => relay.publishState(
        <String, Object?>{
          'profileId': engine.profile.id,
          'gearIndex': engine.gearIndex,
          'gearCount': engine.gearCount,
          'gearNumber': engine.gearNumber,
          'mode': engine.mode.name,
          'lastAction': lastAction,
        },
      );

  relay.events.listen((TransportEvent event) {
    switch (event) {
      case TransportActionReceived(:final Action action, :final String? peerId):
        stdout.writeln('action ${action.name} from ${peerId ?? 'local'}');
        // The bridge applies what the console sends, exactly as it would for a
        // controller press, then tells every console where it landed.
        switch (action) {
          case Action.shiftUp:
            engine.shiftUp();
          case Action.shiftDown:
            engine.shiftDown();
          default:
            break;
        }
        unawaited(publishState(action.label));
      case TransportConnected(:final String peerId, :final String? label):
        stdout.writeln('console $peerId connected from ${label ?? 'unknown'}');
      case TransportDisconnected(:final String peerId):
        stdout.writeln('console $peerId left');
      case TransportError(:final String message):
        stdout.writeln('error: $message');
      case TransportMessageReceived():
      case TransportGradeUpdate():
        break;
    }
  });

  await relay.start();
  stdout.writeln('console: ws://127.0.0.1:$port/console?token=$token');
  await publishState('none');
  stdout.writeln('ready');

  if (tick > Duration.zero) {
    Timer.periodic(tick, (_) {
      engine.shiftUp();
      stdout.writeln('tick: gear ${engine.gearNumber}');
      unawaited(publishState('bridge tick'));
    });
  }

  await ProcessSignal.sigint.watch().first;
  await relay.dispose();
}

// Starts the network publication and prints what happens, so that the link can
// be checked from another machine without a phone.
//
//   dart run tool/net_probe.dart [port]
//
// Then discover the service with any mDNS browser, or connect a TCP client to
// the printed port and send an OpenBikeControl frame.

import 'dart:async';
import 'dart:io';

import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';

Future<void> main(List<String> args) async {
  final int port = args.isEmpty ? 47123 : int.parse(args.first);

  final MdnsTcpTransport transport = MdnsTcpTransport(
    instanceName: 'openzclick',
    port: port,
    advertiser: DartMdnsAdvertiser(),
    keymap: Keymap.defaults('openzclick'),
  );

  transport.events.listen((TransportEvent event) {
    switch (event) {
      case TransportConnected(:final String peerId):
        stdout.writeln('connected: $peerId');
      case TransportDisconnected(:final String peerId):
        stdout.writeln('disconnected: $peerId');
      case TransportActionReceived(:final Action action):
        stdout.writeln('action received: ${action.label}');
      case TransportMessageReceived(:final ObcMessage message):
        stdout.writeln('message received: $message');
      case TransportError(:final String message):
        stdout.writeln('error: $message');
      case TransportGradeUpdate():
        break;
    }
  });

  await transport.start();
  stdout.writeln('listening on ${transport.listeningPort}, announcing _openbikecontrol._tcp');

  // Demonstrates the outgoing direction: two gear changes, then a direction.
  Timer.periodic(const Duration(seconds: 4), (Timer timer) async {
    if (timer.tick > 2) {
      timer.cancel();
      return;
    }
    final Action action = <Action>[
      Action.shiftUp,
      Action.shiftDown,
      Action.steerLeft,
    ][timer.tick - 1];
    stdout.writeln('publishing ${action.label}');
    await transport.emit(action);
  });

  await Future<void>.delayed(const Duration(seconds: 20));
  await transport.stop();
  stdout.writeln('stopped');
  exit(0);
}

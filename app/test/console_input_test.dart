import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick/net/publisher_port.dart';
import 'package:openzclick/state/app_state.dart';

/// A publication that counts what reaches it, standing in for the bridge.
///
/// [consoleActions] is what a console sends to the bridge: the relay turns it
/// into an action, and this fake does the same without a socket.
class FakeBridgeConsole implements PublisherPort {
  final StreamController<Action> actions = StreamController<Action>.broadcast();

  final List<Action> published = <Action>[];
  String? lastProfileId;
  int? lastGearIndex;

  @override
  void Function()? onChanged;

  @override
  bool running = false;

  @override
  bool advertise = false;

  @override
  int port = 0;

  @override
  int? listeningPort;

  @override
  String? address;

  @override
  int peers = 0;

  @override
  String? error;

  bool consoleConnected = false;

  String? consoleAddress;

  String? consoleError;

  @override
  Stream<Action> get consoleActions => actions.stream;

  @override
  int get consoles => 0;

  @override
  int? get consolePort => null;

  @override
  String get consoleToken => '';

  @override
  String? consoleUrl(String host) => null;

  @override
  Future<void> start() async {
    running = true;
    onChanged?.call();
  }

  @override
  Future<void> stop() async {
    running = false;
    onChanged?.call();
  }

  @override
  Future<void> publish(Action action) async => published.add(action);

  @override
  Future<void> publishConsoleState({
    required String profileId,
    required int gearIndex,
    required int gearCount,
    required String mode,
    required String lastAction,
  }) async {
    lastProfileId = profileId;
    lastGearIndex = gearIndex;
  }

  @override
  Future<void> dispose() async {
    await actions.close();
  }
}

void main() {
  test('an action typed in a console shifts the bridge gear', () async {
    final FakeBridgeConsole bridge = FakeBridgeConsole();
    final AppState state = AppState(publisher: bridge);
    addTearDown(state.dispose);

    bridge.actions.add(Action.shiftUp);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(state.engine.gearIndex, 6, reason: 'the bridge starts on gear 6');
    expect(bridge.published, contains(Action.shiftUp));
    expect(
      bridge.lastGearIndex,
      6,
      reason: 'the consoles display the new gear',
    );
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick/net/publisher_port.dart';
import 'package:openzclick/state/app_state.dart';

/// A publication that is also a console, standing in for the browser build.
///
/// It keeps the two directions separate on purpose: [consoleActions] is what the
/// page sends to the bridge, [bridgeStates] is what the bridge sends back.
class FakeBridgeConsole implements PublisherPort, ConsoleClient {
  final StreamController<Action> actions = StreamController<Action>.broadcast();
  final StreamController<Map<String, Object?>> states =
      StreamController<Map<String, Object?>>.broadcast();

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

  @override
  bool consoleConnected = false;

  @override
  String? consoleAddress;

  @override
  String? consoleError;

  @override
  Stream<Action> get consoleActions => actions.stream;

  @override
  Stream<Map<String, Object?>> get bridgeStates => states.stream;

  @override
  int get consoles => consoleConnected ? 1 : 0;

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
  Future<void> connectConsole(String host, String code) async {
    consoleConnected = true;
    consoleAddress = 'ws://$host';
    onChanged?.call();
  }

  @override
  Future<void> disconnectConsole() async {
    consoleConnected = false;
    consoleAddress = null;
    onChanged?.call();
  }

  @override
  Future<void> dispose() async {
    await actions.close();
    await states.close();
  }
}

void main() {
  test('an action typed in a console shifts the bridge gear', () async {
    final FakeBridgeConsole bridge = FakeBridgeConsole();
    final AppState state = AppState(publisher: bridge);
    addTearDown(state.dispose);

    bridge.actions.add(Action.shiftUp);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(state.engine.gearIndex, 6, reason: 'the page starts on gear 6');
    expect(bridge.published, contains(Action.shiftUp));
    expect(
      bridge.lastGearIndex,
      6,
      reason: 'the consoles display the new gear',
    );
  });

  test('the gear of the bridge wins over the one of the page', () async {
    final FakeBridgeConsole bridge = FakeBridgeConsole();
    final AppState state = AppState(publisher: bridge);
    addTearDown(state.dispose);

    bridge.states.add(<String, Object?>{
      'type': 'state',
      'profileId': GearProfile.road12.id,
      'gearIndex': 9,
      'gearCount': 12,
      'mode': RidingMode.erg.name,
      'lastAction': 'Shift up',
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(state.engine.gearIndex, 9);
    expect(state.engine.mode, RidingMode.erg);
  });

  test('a state without a gear index is ignored', () async {
    final FakeBridgeConsole bridge = FakeBridgeConsole();
    final AppState state = AppState(publisher: bridge);
    addTearDown(state.dispose);
    final int before = state.engine.gearIndex;

    bridge.states.add(<String, Object?>{'type': 'state', 'lastAction': 'x'});
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(state.engine.gearIndex, before);
  });

  test('a native bridge is not a console and offers none', () {
    final AppState state = AppState();
    addTearDown(state.dispose);
    expect(state.consoleClient, isNull);
  });
}

/// Tests for the local injection transport and its in-memory injector.
library;

import 'package:openzclick_transports/src/openzclick_transports.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

import 'socket_client.dart';

/// Injector that always fails, to check error propagation.
class FailingKeyInjector implements KeyInjector {
  @override
  Future<void> pressKey(String key) async {
    throw StateError('no graphical session');
  }

  @override
  Future<void> tapAt(double x, double y) async {
    throw StateError('no graphical session');
  }
}

void main() {
  group('LocalInjectionTransport', () {
    late MemoryKeyInjector injector;
    late LocalInjectionTransport transport;
    late EventLog<TransportEvent> log;

    setUp(() async {
      injector = MemoryKeyInjector();
      transport = LocalInjectionTransport(
        injector: injector,
        targets: <Action, InjectionTarget>{
          Action.shiftUp: const KeyTarget('arrow up'),
          Action.confirm: const KeyTarget('Return'),
          Action.menu: const PointTarget(120, 64),
        },
      );
      log = EventLog<TransportEvent>(transport.events);
      await transport.start();
    });

    tearDown(() async {
      await log.cancel();
      await transport.dispose();
    });

    test('injects the key bound to the action', () async {
      await transport.emit(Action.shiftUp);

      expect(injector.inputs, hasLength(1));
      expect((injector.inputs.single as InjectedKey).key, 'arrow up');

      final TransportActionReceived action =
          await log.next<TransportActionReceived>();
      expect(action.action, Action.shiftUp);
      expect(action.peerId, isNull);
      expect(action.transportId, 'local');
    });

    test('injects a tap at the bound coordinates', () async {
      await transport.emit(Action.menu);

      final InjectedTap tap = injector.inputs.single as InjectedTap;
      expect(tap.x, 120);
      expect(tap.y, 64);
    });

    test('keeps the injection order', () async {
      await transport.emit(Action.shiftUp);
      await transport.emit(Action.confirm);
      await transport.emit(Action.menu);

      expect(
        injector.inputs.map((InjectedInput input) => input.toString()),
        <String>[
          'InjectedKey(arrow up)',
          'InjectedKey(Return)',
          'InjectedTap(120.0, 64.0)'
        ],
      );
    });

    test('refuses an action without target', () async {
      await expectLater(
        transport.emit(Action.steerLeft),
        throwsA(isA<ArgumentError>()),
      );
      expect(injector.inputs, isEmpty);
    });

    test('refuses to inject before start', () async {
      final LocalInjectionTransport idle = LocalInjectionTransport(
        injector: MemoryKeyInjector(),
        targets: <Action, InjectionTarget>{
          Action.shiftUp: const KeyTarget('arrow up'),
        },
      );
      await expectLater(idle.emit(Action.shiftUp), throwsA(isA<StateError>()));
      await idle.dispose();
    });

    test('publishes an error and rethrows when the injector fails', () async {
      final LocalInjectionTransport broken = LocalInjectionTransport(
        injector: FailingKeyInjector(),
        targets: <Action, InjectionTarget>{
          Action.shiftUp: const KeyTarget('arrow up'),
        },
      );
      final EventLog<TransportEvent> brokenLog =
          EventLog<TransportEvent>(broken.events);
      await broken.start();

      await expectLater(
        broken.emit(Action.shiftUp),
        throwsA(isA<StateError>()),
      );

      final TransportError error = await brokenLog.next<TransportError>();
      expect(error.message, contains('shiftUp'));
      expect(error.cause, isA<StateError>());

      await brokenLog.cancel();
      await broken.dispose();
    });

    test('is idempotent on start and stop', () async {
      await transport.start();
      expect(transport.isRunning, isTrue);
      await transport.stop();
      expect(transport.isRunning, isFalse);
      await transport.stop();
      expect(transport.isRunning, isFalse);
    });
  });

  group('MemoryKeyInjector', () {
    test('records and clears inputs', () async {
      final MemoryKeyInjector injector = MemoryKeyInjector();
      await injector.pressKey('a');
      await injector.tapAt(1, 2);

      expect(injector.inputs, hasLength(2));
      injector.clear();
      expect(injector.inputs, isEmpty);
      // The exposed list is a copy: mutating it does not affect the injector.
      expect(() => injector.inputs.add(const InjectedKey('b')),
          throwsUnsupportedError);
    });
  });
}

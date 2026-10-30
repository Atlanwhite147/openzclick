import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';
import 'package:openzclick/net/injection_publisher.dart';

void main() {
  late MemoryKeyInjector injector;
  late InjectionPublisher publisher;

  setUp(() {
    injector = MemoryKeyInjector();
    publisher = InjectionPublisher(injector: injector);
  });

  test('does nothing while stopped', () async {
    await publisher.publish(Action.shiftUp);
    expect(injector.inputs, isEmpty);
    expect(publisher.running, isFalse);
  });

  test('taps the configured position of an action', () async {
    await publisher.start();
    await publisher.publish(Action.shiftUp);
    final InjectedTap tap = injector.inputs.single as InjectedTap;
    expect(tap.x, InjectionPublisher.defaultPositions[Action.shiftUp]![0]);
    expect(tap.y, InjectionPublisher.defaultPositions[Action.shiftUp]![1]);
  });

  test('uses an updated position', () async {
    await publisher.start();
    publisher.setPosition(Action.steerLeft, 0.25, 0.75);
    await publisher.publish(Action.steerLeft);
    final InjectedTap tap = injector.inputs.single as InjectedTap;
    expect(tap.x, 0.25);
    expect(tap.y, 0.75);
  });

  test('clamps positions outside the screen', () async {
    publisher.setPosition(Action.shiftDown, 1.4, -0.2);
    expect(publisher.positions[Action.shiftDown], <double>[1.0, 0.0]);
  });

  test('reports an injector failure without throwing', () async {
    final InjectionPublisher failing = InjectionPublisher(
      injector: UnsupportedInjector(),
    );
    await failing.start();
    await failing.publish(Action.shiftUp);
    expect(failing.error, contains('tap injection'));
  });

  test('sends keys when built for a desktop host', () async {
    final MemoryKeyInjector keyboard = MemoryKeyInjector();
    final InjectionPublisher keys = InjectionPublisher(
      injector: keyboard,
      keys: InjectionPublisher.defaultKeys,
    );
    await keys.start();
    await keys.publish(Action.shiftUp);
    await keys.publish(Action.steerLeft);
    expect(keys.usesKeys, isTrue);
    expect(
      keyboard.inputs.whereType<InjectedKey>().map((InjectedKey k) => k.key),
      <String>['i', 'Left'],
    );
  });

  test('a platform without injector is not supported', () {
    expect(
      InjectionPublisher(injector: UnsupportedInjector()).supported,
      isFalse,
    );
    expect(InjectionPublisher(injector: MemoryKeyInjector()).supported, isTrue);
  });
}

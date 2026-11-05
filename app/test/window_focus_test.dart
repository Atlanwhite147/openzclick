import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/net/injection_publisher.dart';
import 'package:openzclick/net/window_focus.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';

/// Remembers what it was asked, and answers with a fixed result.
class _FakeFocuser implements WindowFocuser {
  _FakeFocuser({required this.granted});

  final bool granted;
  final List<String> asked = <String>[];

  @override
  Future<bool> focusWindow(String match) async {
    asked.add(match);
    return granted;
  }
}

void main() {
  group('windowTitleMatches', () {
    test('a fragment matches, whatever the case', () {
      expect(windowTitleMatches('MyWhooshHD', 'mywhoosh'), isTrue);
      expect(windowTitleMatches('MyWhoosh - Free ride', 'MyWhoosh'), isTrue);
      expect(windowTitleMatches('MYWHOOSH', 'Whoosh'), isTrue);
    });

    test('an empty target never matches', () {
      // A blank setting must not pull a random window forward.
      expect(windowTitleMatches('MyWhoosh', ''), isFalse);
      expect(windowTitleMatches('MyWhoosh', '   '), isFalse);
    });

    test('a different window does not match', () {
      expect(windowTitleMatches('Notepad', 'MyWhoosh'), isFalse);
      expect(windowTitleMatches('', 'MyWhoosh'), isFalse);
    });
  });

  group('injecting into a named window', () {
    test('a key is not typed when the target window is missing', () async {
      final MemoryKeyInjector keyboard = MemoryKeyInjector();
      final _FakeFocuser focuser = _FakeFocuser(granted: false);
      final InjectionPublisher publisher = InjectionPublisher(
        injector: keyboard,
        keys: InjectionPublisher.defaultKeys,
        focuser: focuser,
      );
      publisher.focusWindow = 'MyWhoosh';
      await publisher.start();
      addTearDown(publisher.stop);

      await publisher.publish(Action.shiftUp);

      // Typing into whatever happens to have the focus is worse than a shift
      // that does not happen: the rider would see a gear that did nothing, or
      // an `i` in a chat window.
      expect(keyboard.inputs, isEmpty);
      expect(focuser.asked, <String>['MyWhoosh']);
      expect(publisher.error, contains('no window matching "MyWhoosh"'));
    });

    test('the window is raised, then the key is typed', () async {
      final MemoryKeyInjector keyboard = MemoryKeyInjector();
      final _FakeFocuser focuser = _FakeFocuser(granted: true);
      final InjectionPublisher publisher = InjectionPublisher(
        injector: keyboard,
        keys: InjectionPublisher.defaultKeys,
        focuser: focuser,
      );
      publisher.focusWindow = 'MyWhoosh';
      await publisher.start();
      addTearDown(publisher.stop);

      await publisher.publish(Action.shiftUp);

      expect(focuser.asked, <String>['MyWhoosh']);
      expect(
        keyboard.inputs.whereType<InjectedKey>().map((InjectedKey k) => k.key),
        <String>['k'],
        reason: 'shift up is `k` in MyWhoosh',
      );
      expect(publisher.error, isNull);
    });

    test('no target means the plain keyboard behaviour', () async {
      final MemoryKeyInjector keyboard = MemoryKeyInjector();
      final _FakeFocuser focuser = _FakeFocuser(granted: false);
      final InjectionPublisher publisher = InjectionPublisher(
        injector: keyboard,
        keys: InjectionPublisher.defaultKeys,
        focuser: focuser,
      );
      await publisher.start();
      addTearDown(publisher.stop);

      await publisher.publish(Action.shiftDown);

      expect(focuser.asked, isEmpty, reason: 'nothing to raise');
      expect(
        keyboard.inputs.whereType<InjectedKey>().map((InjectedKey k) => k.key),
        <String>['i'],
      );
    });

    test('a host without a focuser keeps working', () async {
      final MemoryKeyInjector keyboard = MemoryKeyInjector();
      final InjectionPublisher publisher = InjectionPublisher(
        injector: keyboard,
        keys: InjectionPublisher.defaultKeys,
      );
      publisher.focusWindow = 'MyWhoosh';
      await publisher.start();
      addTearDown(publisher.stop);

      await publisher.publish(Action.shiftUp);

      expect(keyboard.inputs, isNotEmpty);
      expect(publisher.error, isNull);
    });
  });
}

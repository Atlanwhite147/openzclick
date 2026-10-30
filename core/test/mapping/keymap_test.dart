import 'package:openzclick_core/src/mapping/action.dart';
import 'package:openzclick_core/src/mapping/keymap.dart';
import 'package:test/test.dart';

void main() {
  group('ButtonBinding', () {
    test('structural equality', () {
      const a = ButtonBinding(buttonId: 0x01, action: Action.shiftUp);
      const b = ButtonBinding(buttonId: 0x01, action: Action.shiftUp);
      const c = ButtonBinding(
          buttonId: 0x01, action: Action.shiftUp, analogAction: 3);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('analogAction is optional', () {
      expect(
          const ButtonBinding(buttonId: 0x1B, action: Action.steerLeft)
              .analogAction,
          isNull);
      expect(
        const ButtonBinding(
                buttonId: 0x1B, action: Action.steerLeft, analogAction: 1)
            .analogAction,
        1,
      );
    });
  });

  group('Keymap', () {
    test('actionFor returns the mapped action or none', () {
      final Keymap keymap = Keymap(
        appId: 'target-a',
        bindings: const <int, Action>{
          0x01: Action.shiftUp,
          0x14: Action.confirm
        },
      );
      expect(keymap.appId, 'target-a');
      expect(keymap.actionFor(0x01), Action.shiftUp);
      expect(keymap.actionFor(0x14), Action.confirm);
      expect(keymap.actionFor(0x7F), Action.none);
    });

    test('empty table: everything falls back to none', () {
      final Keymap keymap = Keymap.empty('target-a');
      expect(keymap.actionFor(0x01), Action.none);
      expect(keymap.bindings, isEmpty);
      expect(keymap.isBound(0x01), isFalse);
    });

    test('defaults covers every action except none', () {
      final Keymap keymap = Keymap.defaults('target-a');
      final Set<Action> mapped = keymap.bindings.values.toSet();
      expect(mapped,
          containsAll(Action.values.where((Action a) => a != Action.none)));
      expect(mapped.contains(Action.none), isFalse);
      expect(keymap.actionFor(0x01), Action.shiftUp);
      expect(keymap.actionFor(0x02), Action.shiftDown);
      expect(keymap.actionFor(0x18), Action.steerLeft);
      expect(keymap.actionFor(0x19), Action.steerRight);
      expect(keymap.actionFor(0x44), Action.toggleHud);
    });

    test('overrides replace or disable a button', () {
      final Keymap keymap = Keymap.defaults(
        'target-a',
        overrides: const <int, Action>{
          0x01: Action.shiftDown,
          0x14: Action.none
        },
      );
      expect(keymap.actionFor(0x01), Action.shiftDown);
      expect(keymap.actionFor(0x14), Action.none);
      expect(keymap.actionFor(0x02), Action.shiftDown);
    });

    test('fromBindings: the last binding wins', () {
      final Keymap keymap =
          Keymap.fromBindings('target-a', const <ButtonBinding>[
        ButtonBinding(buttonId: 0x01, action: Action.shiftUp),
        ButtonBinding(buttonId: 0x01, action: Action.menu),
        ButtonBinding(buttonId: 0x10, action: Action.navigateUp),
      ]);
      expect(keymap.actionFor(0x01), Action.menu);
      expect(keymap.actionFor(0x10), Action.navigateUp);
    });

    test('mappings are immutable', () {
      final Keymap keymap = Keymap.defaults('target-a');
      expect(() => keymap.bindings[0x01] = Action.menu, throwsUnsupportedError);
    });

    test('buttonIds and bindingList are sorted', () {
      final Keymap keymap = Keymap(
        appId: 'target-a',
        bindings: const <int, Action>{
          0x14: Action.confirm,
          0x01: Action.shiftUp
        },
      );
      expect(keymap.buttonIds, <int>[0x01, 0x14]);
      expect(
        keymap.bindingList,
        <ButtonBinding>[
          const ButtonBinding(buttonId: 0x01, action: Action.shiftUp),
          const ButtonBinding(buttonId: 0x14, action: Action.confirm),
        ],
      );
    });

    test('withOverrides does not modify the original table', () {
      final Keymap original = Keymap.defaults('target-a');
      final Keymap modified =
          original.withOverrides(const <int, Action>{0x01: Action.menu});
      expect(modified.actionFor(0x01), Action.menu);
      expect(original.actionFor(0x01), Action.shiftUp);
      expect(modified.appId, original.appId);
    });

    test('rejects an empty app identifier', () {
      expect(() => Keymap(appId: ' ', bindings: const <int, Action>{}),
          throwsArgumentError);
      expect(() => Keymap.empty(''), throwsArgumentError);
    });
  });
}

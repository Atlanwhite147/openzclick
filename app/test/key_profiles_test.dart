import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/net/injection_publisher.dart';
import 'package:openzclick/net/key_profiles.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';

void main() {
  group('shipped profiles', () {
    test(
      'every profile binds at least the two shifts, and nothing unknown',
      () {
        for (final KeyProfile profile in builtInKeyProfiles) {
          expect(
            profile.keys.containsKey(Action.shiftUp),
            isTrue,
            reason: '${profile.id} cannot shift up',
          );
          expect(
            profile.keys.containsKey(Action.shiftDown),
            isTrue,
            reason: '${profile.id} cannot shift down',
          );
          for (final String key in profile.keys.values) {
            expect(key.trim(), isNotEmpty, reason: profile.id);
          }
          expect(profile.shiftsPerPress, inInclusiveRange(1, 3));
        }
      },
    );

    test('every shipped binding names the page it was read from', () {
      // A table nobody can check is a table that will be wrong by the next
      // release: the source is shown under the selector for exactly that reason.
      for (final KeyProfile profile in builtInKeyProfiles) {
        if (profile.id == 'custom') continue;
        expect(profile.source, startsWith('https://'), reason: profile.id);
        expect(profile.windowHint, isNotEmpty, reason: profile.id);
      }
    });

    test('the three documented applications disagree on purpose', () {
      // The whole point of the table: `i`/`k` are MyWhoosh, `,`/`.` are Rouvy.
      final KeyProfile mywhoosh = keyProfileById('mywhoosh');
      final KeyProfile rouvy = keyProfileById('rouvy');
      expect(mywhoosh.keys[Action.shiftUp], 'k');
      expect(mywhoosh.keys[Action.shiftDown], 'i');
      expect(rouvy.keys[Action.shiftUp], '.');
      expect(rouvy.keys[Action.shiftDown], ',');
    });

    test('an unknown identifier falls back to the first profile', () {
      expect(keyProfileById('nope').id, builtInKeyProfiles.first.id);
      expect(keyProfileById(null).id, builtInKeyProfiles.first.id);
    });

    test('the multiplier is clamped to one press, three presses', () {
      expect(
        keyProfileById('mywhoosh').withShiftsPerPress(0).shiftsPerPress,
        1,
      );
      expect(
        keyProfileById('mywhoosh').withShiftsPerPress(9).shiftsPerPress,
        3,
      );
      expect(
        keyProfileById('mywhoosh').withShiftsPerPress(2).shiftsPerPress,
        2,
      );
    });
  });

  group('a profile drives the injection', () {
    test('one press sends one key', () async {
      final MemoryKeyInjector keyboard = MemoryKeyInjector();
      final KeyProfile rouvy = keyProfileById('rouvy');
      final InjectionPublisher publisher = InjectionPublisher(
        injector: keyboard,
        keys: rouvy.keys,
      );
      await publisher.start();
      addTearDown(publisher.stop);

      await publisher.publish(Action.shiftUp, repeat: rouvy.shiftsPerPress);

      expect(
        keyboard.inputs.whereType<InjectedKey>().map((InjectedKey k) => k.key),
        <String>['.'],
      );
    });

    test('the multiplier sends the same key several times', () async {
      final MemoryKeyInjector keyboard = MemoryKeyInjector();
      final KeyProfile rouvy = keyProfileById('rouvy').withShiftsPerPress(3);
      final InjectionPublisher publisher = InjectionPublisher(
        injector: keyboard,
        keys: rouvy.keys,
      );
      await publisher.start();
      addTearDown(publisher.stop);

      await publisher.publish(Action.shiftDown, repeat: rouvy.shiftsPerPress);

      expect(
        keyboard.inputs.whereType<InjectedKey>().map((InjectedKey k) => k.key),
        <String>[',', ',', ','],
      );
    });

    test(
      'switching profile switches the key, and rebuilds the backend',
      () async {
        final MemoryKeyInjector keyboard = MemoryKeyInjector();
        final InjectionPublisher publisher = InjectionPublisher(
          injector: keyboard,
          keys: keyProfileById('mywhoosh').keys,
        );
        await publisher.start();
        addTearDown(publisher.stop);
        await publisher.publish(Action.shiftUp);

        publisher.keys = keyProfileById('biketerra').keys;
        await publisher.publish(Action.shiftUp);

        expect(
          keyboard.inputs.whereType<InjectedKey>().map(
            (InjectedKey k) => k.key,
          ),
          <String>['k', 'w'],
        );
      },
    );
  });
}

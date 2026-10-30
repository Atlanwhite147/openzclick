import 'package:openzclick_core/src/shifting/gear_engine.dart';
import 'package:openzclick_core/src/shifting/gear_profile.dart';
import 'package:openzclick_core/src/shifting/gear_ratio.dart';
import 'package:test/test.dart';

GearProfile _profile({bool withChainring = true, int count = 3}) => GearProfile(
      id: 'test',
      label: 'Test',
      gears: List<GearRatio>.generate(
        count,
        (int index) => GearRatio(0.5 + index * 0.5),
        growable: false,
      ),
      bigChainringFactor: withChainring ? const GearRatio(1.5) : null,
    );

void main() {
  group('GearEngine - selection', () {
    test('default initial state', () {
      final engine = GearEngine(profile: GearProfile.road12);
      expect(engine.gearIndex, 0);
      expect(engine.gearNumber, 1);
      expect(engine.gearCount, 12);
      expect(engine.mode, RidingMode.sim);
      expect(engine.atLowest, isTrue);
      expect(engine.atHighest, isFalse);
      expect(engine.currentRatio, same(GearProfile.road12.gears.first));
    });

    test('initialGear is clamped to the valid range', () {
      expect(GearEngine(profile: GearProfile.road12, initialGear: 99).gearIndex,
          11);
      expect(GearEngine(profile: GearProfile.road12, initialGear: -5).gearIndex,
          0);
      expect(
          GearEngine(profile: GearProfile.road12, initialGear: 4).gearIndex, 4);
    });

    test('shiftUp / shiftDown move and report the change', () {
      final engine = GearEngine(profile: GearProfile.road12);
      expect(engine.shiftUp(), isTrue);
      expect(engine.gearIndex, 1);
      expect(engine.shiftUp(), isTrue);
      expect(engine.gearIndex, 2);
      expect(engine.shiftDown(), isTrue);
      expect(engine.gearIndex, 1);
    });

    test('shiftUp saturates at the top and shiftDown at the bottom', () {
      final engine = GearEngine(profile: GearProfile.road12, initialGear: 11);
      expect(engine.atHighest, isTrue);
      expect(engine.shiftUp(), isFalse);
      expect(engine.gearIndex, 11);

      expect(engine.setGear(0), isTrue);
      expect(engine.atLowest, isTrue);
      expect(engine.shiftDown(), isFalse);
      expect(engine.gearIndex, 0);
    });

    test('setGear clamps and returns true only when the index changes', () {
      final engine = GearEngine(profile: GearProfile.road12);
      expect(engine.setGear(5), isTrue);
      expect(engine.gearIndex, 5);
      expect(engine.setGear(5), isFalse);
      expect(engine.setGear(50), isTrue);
      expect(engine.gearIndex, 11);
      expect(engine.setGear(-3), isTrue);
      expect(engine.gearIndex, 0);
      expect(engine.setGear(-3), isFalse);
    });

    test('current ratio follows the cog index', () {
      final engine = GearEngine(profile: GearProfile.road12, initialGear: 3);
      expect(engine.currentRatio.ratio, GearProfile.road12.gears[3].ratio);
    });
  });

  group('GearEngine - virtual chainring', () {
    test('multiplies the ratio without changing the cog index', () {
      final engine = GearEngine(profile: GearProfile.road12, initialGear: 2);
      final double before = engine.currentRatio.ratio;

      engine.toggleChainring();
      expect(engine.bigChainringActive, isTrue);
      expect(engine.gearIndex, 2);
      expect(engine.currentRatio.ratio, closeTo(before * 1.35, 1e-12));

      engine.toggleChainring();
      expect(engine.bigChainringActive, isFalse);
      expect(engine.gearIndex, 2);
      expect(engine.currentRatio.ratio, closeTo(before, 1e-12));
    });

    test('no effect if the profile has no virtual chainring', () {
      final engine = GearEngine(profile: _profile(withChainring: false));
      engine.toggleChainring();
      expect(engine.bigChainringActive, isFalse);
      expect(engine.currentRatio.ratio, 0.5);
    });
  });

  group('GearEngine - mode', () {
    test('setMode changes the riding mode', () {
      final engine = GearEngine(profile: GearProfile.road12);
      expect(engine.mode, RidingMode.sim);
      engine.setMode(RidingMode.erg);
      expect(engine.mode, RidingMode.erg);
    });

    test('default ERG target and +/-5 W clamping between 50 and 1000 W', () {
      final engine = GearEngine(profile: GearProfile.road12);
      expect(engine.ergTargetWatts, defaultErgWatts);

      expect(engine.bumpErg(ergStepWatts), defaultErgWatts + 5);
      expect(engine.bumpErg(-ergStepWatts), defaultErgWatts);

      for (int i = 0; i < 400; i++) {
        engine.bumpErg(-ergStepWatts);
      }
      expect(engine.ergTargetWatts, minErgWatts);

      for (int i = 0; i < 400; i++) {
        engine.bumpErg(ergStepWatts);
      }
      expect(engine.ergTargetWatts, maxErgWatts);
    });

    test('in ERG the returned resistance is the current target', () {
      final engine =
          GearEngine(profile: GearProfile.road12, mode: RidingMode.erg);
      engine.bumpErg(45);
      expect(engine.ergTargetWatts, 245);
      expect(
        engine.targetResistance(
            gradePercent: 12, riderWeightKg: 80, speedKmh: 30),
        245.0,
      );
    });
  });

  group('GearEngine - simulated resistance', () {
    test('grows with grade', () {
      final engine = GearEngine(profile: GearProfile.road12, initialGear: 6);
      double previous = -1;
      for (final double grade in <double>[0, 2, 4, 6, 8, 12]) {
        final double resistance = engine.targetResistance(
            gradePercent: grade, riderWeightKg: 75, speedKmh: 25);
        expect(resistance, greaterThan(previous), reason: 'grade $grade %');
        previous = resistance;
      }
    });

    test('grows with the ratio at constant grade and speed', () {
      final engine = GearEngine(profile: GearProfile.road12);
      double previous = -1;
      for (final int gear in <int>[0, 3, 6, 9, 11]) {
        engine.setGear(gear);
        final double resistance = engine.targetResistance(
          gradePercent: 5,
          riderWeightKg: 75,
          speedKmh: 25,
        );
        expect(resistance, greaterThan(previous), reason: 'cog $gear');
        previous = resistance;
      }
    });

    test('the virtual chainring increases the resistance', () {
      final engine = GearEngine(profile: GearProfile.road12, initialGear: 6);
      const double grade = 5;
      const double weight = 75;
      const double speed = 25;
      final double without = engine.targetResistance(
        gradePercent: grade,
        riderWeightKg: weight,
        speedKmh: speed,
      );
      engine.toggleChainring();
      final double with1 = engine.targetResistance(
        gradePercent: grade,
        riderWeightKg: weight,
        speedKmh: speed,
      );
      expect(with1, greaterThan(without));
    });

    test('grows with speed', () {
      final engine = GearEngine(profile: GearProfile.road12, initialGear: 6);
      final double slow = engine.targetResistance(
        gradePercent: 3,
        riderWeightKg: 75,
        speedKmh: 10,
      );
      final double fast = engine.targetResistance(
        gradePercent: 3,
        riderWeightKg: 75,
        speedKmh: 35,
      );
      expect(fast, greaterThan(slow));
    });

    test('stays finite and bounded between 0 and 1500 W', () {
      final engine = GearEngine(profile: GearProfile.road12);
      for (final int gear in <int>[0, 5, 11]) {
        engine.setGear(gear);
        for (final double grade in <double>[-25, -5, 0, 15, 25]) {
          for (final double speed in <double>[0, 15, 60, 120]) {
            final double resistance = engine.targetResistance(
              gradePercent: grade,
              riderWeightKg: 250,
              speedKmh: speed,
            );
            expect(resistance.isFinite, isTrue);
            expect(resistance, inInclusiveRange(0, maxResistanceWatts));
          }
        }
      }
    });

    test('extreme case: clamped to 1500 W', () {
      final engine = GearEngine(profile: GearProfile.road12, initialGear: 11);
      expect(
        engine.targetResistance(
            gradePercent: 25, riderWeightKg: 250, speedKmh: 120),
        maxResistanceWatts,
      );
    });

    test('descent: never a negative value', () {
      final engine = GearEngine(profile: GearProfile.road12, initialGear: 6);
      for (final double grade in <double>[-3, -8, -15, -25]) {
        final double resistance = engine.targetResistance(
          gradePercent: grade,
          riderWeightKg: 75,
          speedKmh: 45,
        );
        expect(resistance, greaterThanOrEqualTo(0), reason: 'grade $grade %');
        expect(resistance.isFinite, isTrue);
      }
      expect(
        engine.targetResistance(
            gradePercent: -20, riderWeightKg: 75, speedKmh: 60),
        0,
      );
    });

    test('non-finite inputs are replaced by a neutral value', () {
      final engine = GearEngine(profile: GearProfile.road12, initialGear: 6);
      final double resistance = engine.targetResistance(
        gradePercent: double.nan,
        riderWeightKg: double.nan,
        speedKmh: double.infinity,
      );
      expect(resistance.isFinite, isTrue);
      expect(resistance, 0);
    });

    test('zero speed: zero power', () {
      final engine = GearEngine(profile: GearProfile.road12, initialGear: 6);
      expect(
        engine.targetResistance(
            gradePercent: 10, riderWeightKg: 75, speedKmh: 0),
        0,
      );
    });
  });
}

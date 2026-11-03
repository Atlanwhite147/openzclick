import 'dart:async';

import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';
import 'package:test/test.dart';

/// A trainer that acknowledges a frame after a delay, the way a KICKR does
/// (59 to 238 ms measured, 138 ms on average).
class SimulatedTrainer {
  SimulatedTrainer({this.acknowledgement = const Duration(milliseconds: 60)});

  /// How long the machine takes to apply a frame.
  final Duration acknowledgement;

  /// Every frame received, in order.
  final List<List<int>> frames = <List<int>>[];

  /// Wheel sizes the machine is working from, in order.
  final List<double> circumferences = <double>[];

  bool unlocked = false;

  /// Applies [frame], waiting the acknowledged delay, as a real trainer does.
  Future<void> write(List<int> frame) async {
    frames.add(frame);
    await Future<void>.delayed(acknowledgement);
    if (frame.length == 3 && frame[0] == 0x20 && frame[1] == 0xee) {
      unlocked = true;
      return;
    }
    final double? millimeters = WahooWheelCircumference.decode(frame);
    if (millimeters != null) circumferences.add(millimeters);
  }
}

PhysicalSetup parkedIn({int chainring = 34, int cog = 19}) =>
    PhysicalSetup.defaultSetup.parkedOn(chainring: chainring, cog: cog);

void main() {
  group('GearCircumferenceDriver', () {
    test('refuses an unfinished setup rather than guessing the parked gear',
        () {
      // Guessing is the mistake ParkedGear exists to prevent: the whole ladder
      // would be off by the ratio of the assumed gear to the real one, with no
      // visible symptom.
      expect(
        () => GearCircumferenceDriver(
          engine: GearEngine(profile: GearProfile.road12),
          setup: PhysicalSetup.defaultSetup,
        ),
        throwsArgumentError,
      );
    });

    test('sends a wheel size that grows with the gear', () {
      final GearEngine engine = GearEngine(profile: GearProfile.road12);
      final GearCircumferenceDriver driver = GearCircumferenceDriver(
        engine: engine,
        setup: parkedIn(),
      );

      final double easiest = driver.circumferenceForGear(0)!;
      final double middle = driver.circumferenceForGear(6)!;
      final double hardest = driver.circumferenceForGear(11)!;
      expect(easiest, lessThan(middle));
      expect(middle, lessThan(hardest));
    });

    test('writes the frame the trainer expects', () async {
      final SimulatedTrainer trainer = SimulatedTrainer();
      final GearEngine engine = GearEngine(profile: GearProfile.road12);
      engine.shiftUp();
      final GearCircumferenceDriver driver = GearCircumferenceDriver(
        engine: engine,
        setup: parkedIn(),
      );

      final GearApplyResult result =
          await driver.applyGear(1, write: trainer.write);

      expect(result, GearApplyResult.applied);
      expect(trainer.frames, hasLength(1));
      final double? sent =
          WahooWheelCircumference.decode(trainer.frames.single);
      expect(sent, isNotNull);
      expect(sent, closeTo(driver.circumferenceForGear(1)!, 0.05));
    });

    test('applies one gear at a time and drops the ones asked for meanwhile',
        () async {
      // A KICKR takes 59 to 238 ms to acknowledge. Sending gear 2 while gear 1
      // is in flight loses one of them, and the rider then sits in a gear the
      // screen does not show. Dropping the intermediate gear is the honest
      // behaviour: the caller re-sends the last one.
      final SimulatedTrainer trainer = SimulatedTrainer(
        acknowledgement: const Duration(milliseconds: 80),
      );
      final GearEngine engine = GearEngine(profile: GearProfile.road12);
      final GearCircumferenceDriver driver = GearCircumferenceDriver(
        engine: engine,
        setup: parkedIn(),
      );

      final Future<GearApplyResult> first =
          driver.applyGear(3, write: trainer.write);
      // Two more shifts arrive while the first is still being applied.
      final GearApplyResult second =
          await driver.applyGear(4, write: trainer.write);
      final GearApplyResult third =
          await driver.applyGear(5, write: trainer.write);
      expect(await first, GearApplyResult.applied);
      expect(second, GearApplyResult.droppedWhileBusy);
      expect(third, GearApplyResult.droppedWhileBusy);

      // Only the first gear reached the trainer, exactly once.
      expect(trainer.frames, hasLength(1));
      expect(
        WahooWheelCircumference.decode(trainer.frames.single),
        closeTo(driver.circumferenceForGear(3)!, 0.05),
      );

      // And the gear asked for last is applied once the trainer is free.
      final GearApplyResult retry =
          await driver.applyGear(5, write: trainer.write);
      expect(retry, GearApplyResult.applied);
      expect(driver.appliedGearIndex, 5);
    });

    test('unlocks the trainer first when it has just been connected', () async {
      // A KICKR silently ignores wheels until it is unlocked, and "ignored"
      // looks exactly like a wrong wheel size on the rider's legs.
      final SimulatedTrainer trainer = SimulatedTrainer();
      final GearCircumferenceDriver driver = GearCircumferenceDriver(
        engine: GearEngine(profile: GearProfile.road12),
        setup: parkedIn(),
      );

      await driver.applyGear(2, write: trainer.write, reconnected: true);

      expect(trainer.frames.first, <int>[0x20, 0xee, 0xfc]);
      expect(trainer.unlocked, isTrue);
      expect(trainer.circumferences, hasLength(1));
    });

    test('does not unlock twice in a session', () async {
      final SimulatedTrainer trainer = SimulatedTrainer();
      final GearCircumferenceDriver driver = GearCircumferenceDriver(
        engine: GearEngine(profile: GearProfile.road12),
        setup: parkedIn(),
      );
      await driver.applyGear(2, write: trainer.write, reconnected: true);
      await driver.applyGear(3, write: trainer.write);
      expect(
        trainer.frames.where((List<int> f) => f.first == 0x20),
        hasLength(1),
      );
    });

    test('refuses while the application holds ergometer control', () async {
      // A target power and a gear contradict each other; the machine follows
      // whichever came last and the rider cannot tell which.
      final SimulatedTrainer trainer = SimulatedTrainer();
      final GearCircumferenceDriver driver = GearCircumferenceDriver(
        engine: GearEngine(profile: GearProfile.road12),
        setup: parkedIn(),
      );
      final GearApplyResult result = await driver.applyGear(
        4,
        write: trainer.write,
        ergometerMode: true,
      );
      expect(result, GearApplyResult.refusedErgometerMode);
      expect(trainer.frames, isEmpty);
      expect(driver.lastResult, GearApplyResult.refusedErgometerMode);
    });

    test('reports a gear it cannot express instead of sending a wrong one',
        () async {
      // Parked in the big ring on the smallest cog, the easy gears need a wheel
      // so small that a training application draws a rider who has stopped.
      final SimulatedTrainer trainer = SimulatedTrainer();
      final GearCircumferenceDriver driver = GearCircumferenceDriver(
        engine: GearEngine(profile: GearProfile.road12),
        setup: parkedIn(chainring: 50, cog: 11),
      );
      expect(driver.circumferenceForGear(0), isNull);
      final GearApplyResult result =
          await driver.applyGear(0, write: trainer.write);
      expect(result, GearApplyResult.unsupportedGear);
      expect(trainer.frames, isEmpty);
    });

    test('follows a wheel size the riding application imposes', () async {
      // The application sets the wheel whenever it likes, including mid-ride,
      // and the ladder has to be rebuilt around it or the gear on screen stops
      // matching the gear under the rider.
      final GearEngine engine = GearEngine(profile: GearProfile.road12);
      final GearCircumferenceDriver driver = GearCircumferenceDriver(
        engine: engine,
        setup: parkedIn(),
      );
      final double before = driver.circumferenceForGear(6)!;

      expect(driver.adoptApplicationCircumference(2326), isTrue);
      final double after = driver.circumferenceForGear(6)!;

      expect(after / before,
          closeTo(2326 / referenceCircumferenceMillimeters, 1e-9));
    });

    test('ignores a wheel size no bicycle has, keeping the ladder working', () {
      // Values outside the window are a misreading of the standard, not a
      // bicycle. Refusing keeps every gear usable instead of rebuilding around
      // a number that means nothing.
      final GearCircumferenceDriver driver = GearCircumferenceDriver(
        engine: GearEngine(profile: GearProfile.road12),
        setup: parkedIn(),
      );
      expect(driver.adoptApplicationCircumference(1200), isFalse);
      expect(driver.adoptApplicationCircumference(3000), isFalse);
      expect(
        driver.neutralCircumferenceMillimeters,
        referenceCircumferenceMillimeters,
      );
    });

    test('is not busy once a frame has been acknowledged', () async {
      final SimulatedTrainer trainer = SimulatedTrainer();
      final GearCircumferenceDriver driver = GearCircumferenceDriver(
        engine: GearEngine(profile: GearProfile.road12),
        setup: parkedIn(),
      );
      expect(driver.isBusy, isFalse);
      await driver.applyGear(2, write: trainer.write);
      expect(driver.isBusy, isFalse);
      expect(driver.lastResult, GearApplyResult.applied);
    });

    test('clears the busy flag even when the write fails', () async {
      // A transport can fail; leaving the flag set would lock the ladder for
      // the rest of the ride with no way out but a restart.
      final GearCircumferenceDriver driver = GearCircumferenceDriver(
        engine: GearEngine(profile: GearProfile.road12),
        setup: parkedIn(),
      );
      await expectLater(
        driver.applyGear(2, write: (List<int> _) async {
          throw StateError('link lost');
        }),
        throwsStateError,
      );
      expect(driver.isBusy, isFalse);
    });
  });
}

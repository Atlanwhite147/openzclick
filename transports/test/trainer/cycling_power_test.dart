import 'package:openzclick_transports/openzclick_transports.dart';
import 'package:test/test.dart';

void main() {
  group('CyclingPowerCodec', () {
    test('sends power and crank revolutions in one frame', () {
      // The frame an application reads: flags, power, revolutions, event time.
      // Without the revolution field the application shows watts and no legs,
      // which is the whole reason this service is published.
      final List<int> frame = CyclingPowerCodec.measurement(
        const CyclingPowerMeasurement(
          powerWatts: 245,
          cumulativeCrankRevolutions: 1250,
          lastCrankEventTime: 40960,
        ),
      );
      expect(frame.length, 8);
      // Bit 5 set: crank revolution data present.
      expect(frame.sublist(0, 2), <int>[0x20, 0x00]);
      expect(frame.sublist(2, 4), <int>[245, 0]);
      expect(frame.sublist(4, 6), <int>[0xe2, 0x04]);
      expect(frame.sublist(6, 8), <int>[0x00, 0xa0]);
    });

    test('carries a negative power, because a signed 16-bit field allows it',
        () {
      final List<int> frame = CyclingPowerCodec.measurement(
        const CyclingPowerMeasurement(
          powerWatts: -20,
          cumulativeCrankRevolutions: 0,
          lastCrankEventTime: 0,
        ),
      );
      expect(frame.sublist(2, 4), <int>[0xec, 0xff]);
    });

    test('refuses a power outside the field instead of clamping it', () {
      expect(
        () => CyclingPowerCodec.measurement(
          const CyclingPowerMeasurement(
            powerWatts: 40000,
            cumulativeCrankRevolutions: 0,
            lastCrankEventTime: 0,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('reads back what it wrote', () {
      const CyclingPowerMeasurement original = CyclingPowerMeasurement(
        powerWatts: 312,
        cumulativeCrankRevolutions: 700,
        lastCrankEventTime: 12345,
      );
      final CyclingPowerMeasurement? decoded =
          CyclingPowerCodec.decodeMeasurement(
              CyclingPowerCodec.measurement(original));
      expect(decoded?.powerWatts, 312);
      expect(decoded?.cumulativeCrankRevolutions, 700);
      expect(decoded?.lastCrankEventTime, 12345);
    });

    test('advertises no feature it does not have', () {
      // Zero means "nothing beyond the mandatory": no offset compensation, no
      // extreme values, no accumulated energy.
      expect(CyclingPowerCodec.feature(), <int>[0, 0, 0, 0]);
      expect(
        CyclingPowerCodec.sensorLocationValue(),
        <int>[CyclingPowerSensorLocation.bottomBracket],
      );
    });

    test('names the service and its characteristics', () {
      expect(CyclingPowerUuids.service, '00001818-0000-1000-8000-00805f9b34fb');
      expect(CyclingPowerUuids.measurement,
          '00002a63-0000-1000-8000-00805f9b34fb');
    });
  });

  group('cadence computed by the receiver', () {
    test('is the cadence that was fed in', () {
      // 90 rpm for four seconds: six revolutions in 4096 ticks.
      const CyclingPowerMeasurement before = CyclingPowerMeasurement(
        powerWatts: 200,
        cumulativeCrankRevolutions: 100,
        lastCrankEventTime: 0,
      );
      const CyclingPowerMeasurement after = CyclingPowerMeasurement(
        powerWatts: 200,
        cumulativeCrankRevolutions: 106,
        lastCrankEventTime: 4096,
      );
      expect(after.cadenceRpmSince(before), closeTo(90, 0.001));
    });

    test('survives the wrap of the 16-bit counters', () {
      // The counters wrap mid-ride on every long session; a decoder that treats
      // the wrap as a jump back in time shows a cadence of zero.
      const CyclingPowerMeasurement before = CyclingPowerMeasurement(
        powerWatts: 200,
        cumulativeCrankRevolutions: 65535,
        lastCrankEventTime: 65500,
      );
      const CyclingPowerMeasurement after = CyclingPowerMeasurement(
        powerWatts: 200,
        cumulativeCrankRevolutions: 2,
        lastCrankEventTime: 1020,
      );
      // 3 revolutions in (65536 - 65500 + 1020) = 1056 ticks = 1.031 s = 174 rpm
      expect(after.cadenceRpmSince(before), closeTo(174.5, 0.5));
    });

    test('is zero when no time passed', () {
      const CyclingPowerMeasurement same = CyclingPowerMeasurement(
        powerWatts: 200,
        cumulativeCrankRevolutions: 10,
        lastCrankEventTime: 500,
      );
      expect(same.cadenceRpmSince(same), 0);
    });
  });

  group('CrankRevolutionClock', () {
    test('counts revolutions from a cadence and a duration', () {
      final CrankRevolutionClock clock = CrankRevolutionClock();
      clock.advance(
        elapsed: const Duration(seconds: 1),
        cadenceRpm: 60,
      );
      expect(clock.cumulativeCrankRevolutions, 1);
      expect(clock.lastCrankEventTime, 1024);
    });

    test('keeps the fraction of a revolution between two short advances', () {
      // A 100 ms publishing rate at 90 rpm is about 0.15 revolutions per frame.
      // A clock that rounded down every frame would report zero revolutions
      // forever; this one carries the fraction, so twenty frames at 90 rpm give
      // 2 whole revolutions and 0.99 of the next, not zero.
      final CrankRevolutionClock clock = CrankRevolutionClock();
      for (int i = 0; i < 20; i++) {
        clock.advance(
            elapsed: const Duration(milliseconds: 100), cadenceRpm: 90);
      }
      // 20 x 102 ticks = 1.992 s, and 1.992 s at 90 rpm is 2.988 revolutions.
      expect(clock.cumulativeCrankRevolutions, 2);
      expect(clock.lastCrankEventTime, 2040);

      // One more frame completes the third revolution, which is only possible
      // because the fraction survived the previous ones.
      clock.advance(elapsed: const Duration(milliseconds: 100), cadenceRpm: 90);
      expect(clock.cumulativeCrankRevolutions, 3);
    });

    test('advances time but not revolutions when the rider stops', () {
      // Time must advance, or the receiver divides by zero ticks and shows the
      // last cadence forever.
      final CrankRevolutionClock clock = CrankRevolutionClock();
      clock.advance(elapsed: const Duration(seconds: 1), cadenceRpm: 30);
      final int revolutions = clock.cumulativeCrankRevolutions;
      clock.advance(elapsed: const Duration(seconds: 1), cadenceRpm: 0);
      expect(clock.cumulativeCrankRevolutions, revolutions);
      expect(clock.lastCrankEventTime, 2048);
    });

    test('wraps its counters at 16 bits', () {
      final CrankRevolutionClock clock = CrankRevolutionClock();
      for (int i = 0; i < 120; i++) {
        clock.advance(elapsed: const Duration(seconds: 1), cadenceRpm: 600);
      }
      expect(clock.cumulativeCrankRevolutions, lessThanOrEqualTo(0xffff));
      expect(clock.lastCrankEventTime, lessThanOrEqualTo(0xffff));
    });

    test('refuses a zero elapsed duration', () {
      final CrankRevolutionClock clock = CrankRevolutionClock();
      expect(
        () => clock.advance(elapsed: Duration.zero, cadenceRpm: 90),
        throwsArgumentError,
      );
    });
  });
}

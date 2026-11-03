import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

/// What the rider's legs actually multiply: the parked gear ratio times the
/// wheel size the trainer was told about.
double feelAt(double circumference, ParkedGear parked) =>
    parked.ratio * circumference;

void main() {
  final PhysicalSetup road = PhysicalSetup.defaultSetup;

  group('effectiveCircumference', () {
    test('cancels the parked gear, so the gear shown is the gear felt', () {
      // The bike sits in 50/15, the hardest sensible place to leave it.
      final ParkedGear parked = ParkedGear(chainringTeeth: 50, cogTeeth: 15);

      // Asking for the neutral gear must give back exactly the neutral feel,
      // whatever the bike is parked in.
      final double kept = WheelCircumferenceScaler.effectiveCircumference(
        neutralCircumference: referenceCircumferenceMillimeters,
        parked: parked,
        selectedRatio: 1,
      )!;
      expect(
        feelAt(kept, parked),
        closeTo(referenceCircumferenceMillimeters, 0.001),
      );
    });

    test('a harder gear gives a larger wheel, an easier gear a smaller one',
        () {
      final ParkedGear parked = ParkedGear(chainringTeeth: 34, cogTeeth: 19);
      final double easy = WheelCircumferenceScaler.effectiveCircumference(
        neutralCircumference: referenceCircumferenceMillimeters,
        parked: parked,
        selectedRatio: 0.45,
      )!;
      final double hard = WheelCircumferenceScaler.effectiveCircumference(
        neutralCircumference: referenceCircumferenceMillimeters,
        parked: parked,
        selectedRatio: 3.2,
      )!;
      expect(easy, lessThan(hard));
      expect(easy, greaterThan(0));
      // The span is exactly the span of the profile: the ratio of the two
      // wheel sizes is the ratio of the two gears.
      expect(hard / easy, closeTo(3.2 / 0.45, 1e-9));
    });

    test('the same gear feels the same whatever the bike is parked in', () {
      // This is the property the whole type exists for: the parked gear moves
      // the wheel size, never the feeling.
      final List<ParkedGear> parkings = <ParkedGear>[
        ParkedGear(chainringTeeth: 34, cogTeeth: 34),
        ParkedGear(chainringTeeth: 34, cogTeeth: 19),
        ParkedGear(chainringTeeth: 50, cogTeeth: 15),
      ];
      final List<double> feels = <double>[];
      for (final ParkedGear parked in parkings) {
        final double circumference =
            WheelCircumferenceScaler.effectiveCircumference(
          neutralCircumference: referenceCircumferenceMillimeters,
          parked: parked,
          selectedRatio: 1.4,
        )!;
        feels.add(feelAt(circumference, parked));
      }
      for (final double feel in feels) {
        expect(feel, closeTo(feels.first, 1e-6));
      }
    });

    test('refuses a gear the command cannot express instead of clamping it',
        () {
      // Parked in the small ring on the largest cog, a hard gear needs a wheel
      // larger than a 16-bit tenth-of-a-millimetre value holds: 2105 / 1.0 x
      // 3.2 = 6736 mm against a ceiling of 6553.5. Clamping would silently hand
      // the rider a gear nobody asked for.
      final ParkedGear easyParking =
          ParkedGear(chainringTeeth: 34, cogTeeth: 34);
      final double? tooHard = WheelCircumferenceScaler.effectiveCircumference(
        neutralCircumference: referenceCircumferenceMillimeters,
        parked: easyParking,
        selectedRatio: 3.2,
      );
      expect(tooHard, isNull);
    });

    test('refuses a wheel so small the application would draw a stopped rider',
        () {
      // Parked in the big ring on the smallest cog, the neutral gear needs a
      // wheel of 2105 / 4.545 = 463 mm. The trainer accepts it, but a training
      // application draws almost no speed and shows a rider who has stopped.
      final ParkedGear hardParking =
          ParkedGear(chainringTeeth: 50, cogTeeth: 11);
      final double? tooEasy = WheelCircumferenceScaler.effectiveCircumference(
        neutralCircumference: referenceCircumferenceMillimeters,
        parked: hardParking,
        selectedRatio: 1,
      );
      expect(tooEasy, isNull);
    });

    test('treats a non-finite or non-positive input as unbuildable', () {
      final ParkedGear parked = ParkedGear(chainringTeeth: 34, cogTeeth: 19);
      for (final double bad in <double>[
        0,
        -1,
        double.nan,
        double.infinity,
      ]) {
        expect(
          WheelCircumferenceScaler.effectiveCircumference(
            neutralCircumference: bad,
            parked: parked,
            selectedRatio: 1,
          ),
          isNull,
        );
        expect(
          WheelCircumferenceScaler.effectiveCircumference(
            neutralCircumference: referenceCircumferenceMillimeters,
            parked: parked,
            selectedRatio: bad,
          ),
          isNull,
        );
      }
    });
  });

  group('the mistake this type prevents', () {
    test('assuming the starting gear puts the whole ladder 90 % too hard', () {
      // Parked in the big ring on the smallest cog, which is 50/11 = 4.55 while
      // a ladder assumes the bike sits somewhere around 2.4, the rider works
      // this much harder for every gear number on screen. The step sizes stay
      // right, which is why the error is invisible: shifting feels fine and the
      // gears are simply not the ones displayed. Measured on a real setup.
      final ParkedGear actual = ParkedGear(chainringTeeth: 50, cogTeeth: 11);
      const double assumedRatio = 2.4;
      expect(actual.ratio / assumedRatio, closeTo(1.894, 0.01));
    });

    test('and a quiet parking spot makes it 39 % too easy instead', () {
      // The same wrong assumption, with the bike left in the big ring on a
      // middle cog. The error changes sign and size, which is why no fixed
      // assumption can work and the rider has to be asked where the chain is.
      final ParkedGear actual = ParkedGear(chainringTeeth: 50, cogTeeth: 15);
      expect(actual.ratio / 2.4, closeTo(1.389, 0.01));
    });
  });

  group('PhysicalSetup', () {
    test('is incomplete until the rider says where the chain is', () {
      expect(road.isComplete, isFalse);
      expect(road.parkedGear, isNull);
      expect(road.parkedOn(chainring: 34, cog: 19).isComplete, isTrue);
    });

    test('rejects a parked gear the bike does not have', () {
      final PhysicalSetup wrong = PhysicalSetup(
        chainringTeeth: const <int>[50, 34],
        cogTeeth: const <int>[11, 12],
        parkedChainringTeeth: 39,
        parkedCogTeeth: 11,
      );
      expect(wrong.parkedGear, isNull, reason: 'no 39 tooth ring on this bike');
    });

    test('names the parked gear the way a rider says it', () {
      expect(ParkedGear(chainringTeeth: 50, cogTeeth: 15).name, '50/15');
      expect(
        ParkedGear(chainringTeeth: 50, cogTeeth: 15).ratio,
        closeTo(3.3333, 0.0001),
      );
    });

    test('recommends the quietest gear that still reaches every gear', () {
      final ParkedGear? recommended =
          road.recommendParkedGear(GearProfile.road12);
      expect(recommended, isNotNull);
      final GearProfile road12 = GearProfile.road12;

      // It must work: every gear of the profile builds from it.
      expect(road.keepsLadderReachable(road12, recommended!), isTrue);

      // And no quieter gear would, or the recommendation is not the quietest.
      for (final int ring in road.chainringTeeth) {
        for (final int cog in road.cogTeeth) {
          final ParkedGear candidate =
              ParkedGear(chainringTeeth: ring, cogTeeth: cog);
          if (candidate.ratio >= recommended.ratio) continue;
          expect(
            road.keepsLadderReachable(road12, candidate),
            isFalse,
            reason: '${candidate.name} is quieter and still works',
          );
        }
      }
    });

    test('a ladder too wide for the command has no recommendation', () {
      // A profile reaching past what a 16-bit tenth-of-a-millimetre wheel size
      // can express cannot be built anywhere, at any parked gear.
      final GearProfile absurd = GearProfile(
        id: 'absurd',
        label: 'Absurd 2 gears',
        gears: <GearRatio>[const GearRatio(0.5), const GearRatio(40)],
      );
      expect(road.recommendParkedGear(absurd), isNull);
    });
  });

  group('the window a training application may impose', () {
    test('covers real bicycle wheels and nothing else', () {
      expect(
        WheelCircumferenceScaler.isSupportedRidingAppCircumference(1900),
        isTrue,
        reason: '650b',
      );
      expect(
        WheelCircumferenceScaler.isSupportedRidingAppCircumference(2105),
        isTrue,
        reason: '700x25',
      );
      expect(
        WheelCircumferenceScaler.isSupportedRidingAppCircumference(2326),
        isTrue,
        reason: '29er',
      );
      expect(
        WheelCircumferenceScaler.isSupportedRidingAppCircumference(1700),
        isFalse,
      );
      expect(
        WheelCircumferenceScaler.isSupportedRidingAppCircumference(2500),
        isFalse,
      );
      expect(
        WheelCircumferenceScaler.isSupportedRidingAppCircumference(double.nan),
        isFalse,
      );
    });

    test('a command carries tenths of a millimetre, so 2105.04 arrives as 2105',
        () {
      expect(WheelCircumferenceScaler.asSent(2105.04), 2105.0);
      expect(WheelCircumferenceScaler.asSent(2105.06), closeTo(2105.1, 1e-9));
    });

    test('the widest span a profile may have still fits at the largest wheel',
        () {
      // 6553.5 mm / 2400 mm: a profile reaching past this cannot be built when
      // an application sets the largest wheel size it is allowed to set.
      final double span = WheelCircumferenceScaler.widestSupportedSpan;
      expect(span, closeTo(6553.5 / 2400, 1e-9));
      expect(span * maxRidingAppCircumferenceMillimeters,
          closeTo(maxCircumferenceMillimeters, 1e-6));
    });
  });
}

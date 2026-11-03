/// The gear the bike sits in while it is on the trainer, and the wheel size the
/// trainer is told about.
///
/// A bike on a trainer never shifts: it is parked in one gear for the whole
/// ride. What the rider's legs feel is
///
///     feel  =  parked gear ratio  ×  the wheel size the trainer works from
///
/// The bridge only controls the second half. So it has to be told the first,
/// because the two halves trade off exactly: a big ring with the smallest cog
/// multiplies a wheel size the bridge would otherwise read as an easy gear by
/// 4.55, and a ladder built on the silent assumption that the bike sits in the
/// starting gear is then ninety per cent too hard with no visible symptom.
/// The step sizes stay right, because the scaling is relative; only the
/// position of the whole ladder moves, which is why this never looks like a
/// bug on its own.
///
/// The consequence is worth stating: once the parked gear is known, the ladder
/// is anchored by it, so the roller can be left in whichever gear is quietest
/// rather than whichever gear happens to suit the numbers.
library;

import 'gear_profile.dart';
import 'gear_ratio.dart';

/// The largest wheel circumference a trainer command can express, in
/// millimetres.
///
/// This is the only hard limit involved, and it comes from the encoding (a
/// 16-bit value in tenths of a millimetre), not from any trainer refusing a
/// value: a KICKR V5 was probed across the whole span and acknowledged
/// everything from 0.1 mm to 6553.5 mm.
const double maxCircumferenceMillimeters = 6553.5;

/// The wheel sizes a training application may impose, in millimetres.
///
/// A riding application sets the wheel size of its trainer whenever it likes,
/// and the bridge then has to rebuild every gear around that value or the gear
/// on screen stops matching the gear under the rider. This window covers every
/// real bicycle wheel, from a 650b at 1900 mm to a 29er at 2326 mm, with room
/// either side because riders type these numbers by hand.
///
/// It is a product decision about bicycles, not a measurement: there is nothing
/// left to measure, since the trainer takes anything. Its width is bounded by
/// one real thing, checked by [widestSupportedSpan].
const double minRidingAppCircumferenceMillimeters = 1800;

/// Upper end of the window a training application may impose, in millimetres.
const double maxRidingAppCircumferenceMillimeters = 2400;

/// Wheel size the trainer is left at, and the size every gear is scaled from
/// when neither the rider nor the application supplied one, in millimetres.
///
/// 2105 mm is the documented circumference of a 700x25 road wheel.
const double referenceCircumferenceMillimeters = 2105;

/// Smallest wheel size a gear may produce, in millimetres.
///
/// The trainer accepts smaller values, but it then reports almost no speed and
/// a training application draws a rider who has stopped. This is a choice about
/// what looks right on screen, not a limit of the hardware.
const double minEffectiveCircumferenceMillimeters = 500;

/// A gear a bike can be left in: a chainring and a cog, named in teeth.
class ParkedGear {
  /// Creates a parked gear; both tooth counts must be positive.
  ParkedGear({required this.chainringTeeth, required this.cogTeeth})
      : assert(chainringTeeth > 0, 'A chainring has teeth'),
        assert(cogTeeth > 0, 'A cog has teeth');

  /// Teeth on the chainring the chain is on.
  final int chainringTeeth;

  /// Teeth on the cog the chain is on.
  final int cogTeeth;

  /// How much the parked gear multiplies the wheel size.
  double get ratio => chainringTeeth / cogTeeth;

  /// The way a rider says it out loud: "fifty, fifteen" for `50/15`.
  String get name => '$chainringTeeth/$cogTeeth';

  @override
  bool operator ==(Object other) =>
      other is ParkedGear &&
      other.chainringTeeth == chainringTeeth &&
      other.cogTeeth == cogTeeth;

  @override
  int get hashCode => Object.hash(chainringTeeth, cogTeeth);

  @override
  String toString() => 'ParkedGear($name, ratio ${ratio.toStringAsFixed(2)})';
}

/// What is physically bolted to the bike, as opposed to the gearing the rider
/// asked the bridge to simulate.
///
/// The two are unrelated on purpose: a single-sprocket Zwift Cog with a
/// twelve-speed groupset simulated on top is a common and perfectly sensible
/// indoor setup.
class PhysicalSetup {
  /// Creates a setup from tooth counts.
  ///
  /// [chainringTeeth] is ordered largest first, the way a groupset is named;
  /// [cogTeeth] smallest first. A single cog means a single sprocket such as a
  /// Zwift Cog. Pass [parkedChainringTeeth] and [parkedCogTeeth] once the rider
  /// has confirmed where the chain actually is.
  PhysicalSetup({
    required List<int> chainringTeeth,
    required List<int> cogTeeth,
    this.parkedChainringTeeth,
    this.parkedCogTeeth,
  })  : assert(chainringTeeth.isNotEmpty, 'A bike has at least one chainring'),
        assert(cogTeeth.isNotEmpty, 'A bike has at least one cog'),
        chainringTeeth = List<int>.unmodifiable(chainringTeeth),
        cogTeeth = List<int>.unmodifiable(cogTeeth);

  /// Chainring tooth counts, largest first.
  final List<int> chainringTeeth;

  /// Cog tooth counts, smallest first.
  final List<int> cogTeeth;

  /// Chainring the chain is parked on, `null` until the rider confirms it.
  final int? parkedChainringTeeth;

  /// Cog the chain is parked on, `null` until the rider confirms it.
  final int? parkedCogTeeth;

  /// The parked gear, or `null` while the setup is incomplete.
  ParkedGear? get parkedGear {
    final int? ring = parkedChainringTeeth;
    final int? cog = parkedCogTeeth;
    if (ring == null || cog == null) return null;
    if (!chainringTeeth.contains(ring) || !cogTeeth.contains(cog)) return null;
    return ParkedGear(chainringTeeth: ring, cogTeeth: cog);
  }

  /// True once the rider has said where the chain is.
  ///
  /// Setup is not finished until they have, because guessing it corrupts every
  /// gear in a way that looks like nothing at all.
  bool get isComplete => parkedGear != null;

  /// A compact road bike with an 11-34 cassette, the setup most riders own.
  static PhysicalSetup get defaultSetup => PhysicalSetup(
        chainringTeeth: const <int>[50, 34],
        cogTeeth: const <int>[11, 12, 13, 14, 15, 17, 19, 21, 24, 27, 30, 34],
      );

  /// The single sprocket a Zwift Cog replaces a cassette with.
  static const List<int> zwiftCogTeeth = <int>[14];

  /// Returns a copy parked on [chainring] and [cog].
  PhysicalSetup parkedOn({required int chainring, required int cog}) =>
      PhysicalSetup(
        chainringTeeth: chainringTeeth,
        cogTeeth: cogTeeth,
        parkedChainringTeeth: chainring,
        parkedCogTeeth: cog,
      );

  /// The quietest gear that still keeps every gear of [profile] reachable.
  ///
  /// Indoors the trainer is the loudest thing in the room, and its flywheel
  /// speed follows the parked ratio: a middle cog on the small ring runs at
  /// about half the flywheel speed of the big ring on the smallest cog. Since
  /// the bridge compensates for whatever the rider confirms, the parked gear can
  /// be chosen for quiet alone, and this is that choice.
  ///
  /// Returns `null` when no combination fits, which happens only with a gearing
  /// too wide for the command or a wheel size outside the supported window.
  /// Refusing is the honest answer: a ladder that cannot be built must be
  /// reported at setup, not discovered mid-ride.
  ParkedGear? recommendParkedGear(
    GearProfile profile, {
    double neutralCircumference = referenceCircumferenceMillimeters,
  }) {
    if (!neutralCircumference.isFinite || neutralCircumference <= 0) {
      return null;
    }
    ParkedGear? best;
    for (final int ring in chainringTeeth) {
      for (final int cog in cogTeeth) {
        final ParkedGear candidate =
            ParkedGear(chainringTeeth: ring, cogTeeth: cog);
        if (!keepsLadderReachable(profile, candidate,
            neutralCircumference: neutralCircumference)) {
          continue;
        }
        // Lower ratio means a slower flywheel, which is what "quiet" means.
        if (best == null || candidate.ratio < best.ratio) best = candidate;
      }
    }
    return best;
  }

  /// True when every gear of [profile] can be produced from [parked].
  bool keepsLadderReachable(
    GearProfile profile,
    ParkedGear parked, {
    double neutralCircumference = referenceCircumferenceMillimeters,
  }) {
    for (final GearRatio gear in profile.gears) {
      final double? circumference =
          WheelCircumferenceScaler.effectiveCircumference(
        neutralCircumference: neutralCircumference,
        parked: parked,
        selectedRatio: gear.ratio,
      );
      if (circumference == null) return false;
    }
    return true;
  }

  @override
  String toString() => 'PhysicalSetup(${chainringTeeth.join('/')}x'
      '${cogTeeth.first}-${cogTeeth.last}, parked ${parkedGear?.name ?? 'unknown'})';
}

/// The wheel size to hand the trainer for a given gear.
///
/// The trainer works out its brake force from the distance one pedal stroke
/// covers, so a smaller wheel makes every gear easier without touching the
/// terrain the training application sends. That is the whole trick: the
/// application keeps the hills, the bridge keeps the multiplication, and
/// neither has to know about the other.
abstract final class WheelCircumferenceScaler {
  /// Wheel size that makes [selectedRatio] feel like itself when the bike is
  /// parked in [parked], in millimetres.
  ///
  /// Returns `null` when the result would fall outside what a trainer command
  /// can express, or below the size at which a training application still
  /// draws a rider who is moving. Returning `null` rather than a clamped value
  /// keeps the caller from publishing a gear the rider did not ask for.
  static double? effectiveCircumference({
    required double neutralCircumference,
    required ParkedGear parked,
    required double selectedRatio,
  }) {
    if (!neutralCircumference.isFinite || neutralCircumference <= 0) {
      return null;
    }
    if (!selectedRatio.isFinite || selectedRatio <= 0) return null;
    final double parkedRatio = parked.ratio;
    if (!parkedRatio.isFinite || parkedRatio <= 0) return null;

    // Divided by the parked ratio on purpose: feel is what the legs multiply,
    // so cancelling the parked gear is what makes the gear on screen the gear
    // under the rider.
    final double circumference =
        neutralCircumference / parkedRatio * selectedRatio;
    if (!circumference.isFinite) return null;
    if (circumference > maxCircumferenceMillimeters) return null;
    if (circumference < minEffectiveCircumferenceMillimeters) return null;
    return circumference;
  }

  /// Wheel size rounded to the tenth of a millimetre a trainer command carries.
  static double asSent(double millimeters) =>
      (millimeters / 0.1).roundToDouble() * 0.1;

  /// True when a training application may impose [millimeters].
  static bool isSupportedRidingAppCircumference(double millimeters) =>
      millimeters.isFinite &&
      millimeters >= minRidingAppCircumferenceMillimeters &&
      millimeters <= maxRidingAppCircumferenceMillimeters;

  /// How many times easier than harder the widest gear span can be, at the
  /// largest wheel size a training application may impose.
  ///
  /// This is the real ceiling on a profile: past it, the hardest gear of the
  /// span no longer fits in what a trainer command can express, and a profile
  /// wider than this cannot be built at all.
  static double get widestSupportedSpan =>
      maxCircumferenceMillimeters / maxRidingAppCircumferenceMillimeters;
}

/// Transmission profile: an ordered list of ratios and, optionally, a virtual
/// chainring that multiplies the current ratio without changing cogs.
///
/// The built-in profiles follow the contract's normalisation constraint: all
/// ratios lie between `0.45` and `3.2`.
library;

import 'dart:math' as math;

import 'gear_ratio.dart';

/// Maximum number of gears allowed in a profile.
const int maxGearCount = 30;

/// Minimum number of gears allowed in a profile.
const int minGearCount = 1;

/// Virtual gear profile.
class GearProfile {
  /// Stable identifier, used for serialisation and tests.
  final String id;

  /// Human-readable label (French) meant for the UI.
  final String label;

  /// Gears ordered from the smallest to the largest development.
  ///
  /// The list is unmodifiable and holds between [minGearCount] and
  /// [maxGearCount] elements.
  final List<GearRatio> gears;

  /// Virtual chainring factor, or `null` if the profile offers none.
  ///
  /// When enabled, the current ratio is multiplied by this factor without
  /// changing the cog index.
  final GearRatio? bigChainringFactor;

  /// Builds a profile while validating its invariants.
  ///
  /// Throws [ArgumentError] if the identifier is empty, if the gear count
  /// falls outside the allowed range, if a ratio is not finite, or if the
  /// chainring factor is not strictly positive.
  GearProfile({
    required this.id,
    required this.label,
    required List<GearRatio> gears,
    this.bigChainringFactor,
  }) : gears = List<GearRatio>.unmodifiable(gears) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Profile id must not be empty');
    }
    if (this.gears.length < minGearCount || this.gears.length > maxGearCount) {
      throw ArgumentError.value(
        this.gears.length,
        'gears',
        'A profile must hold between $minGearCount and $maxGearCount gears',
      );
    }
    for (final gear in this.gears) {
      if (!gear.ratio.isFinite || gear.ratio <= 0) {
        throw ArgumentError.value(gear.ratio, 'gears', 'Every ratio must be finite and strictly positive');
      }
    }
    final factor = bigChainringFactor;
    if (factor != null && (!factor.ratio.isFinite || factor.ratio <= 0)) {
      throw ArgumentError.value(factor.ratio, 'bigChainringFactor', 'Chainring factor must be finite and positive');
    }
  }

  /// Number of gears in the profile.
  int get gearCount => gears.length;

  /// True if the profile offers a virtual chainring.
  bool get hasBigChainring => bigChainringFactor != null;

  /// First ratio (the easiest).
  GearRatio get lowest => gears.first;

  /// Last ratio (the hardest).
  GearRatio get highest => gears.last;

  /// Built-in profiles, in display order.
  static List<GearProfile> get builtin => List<GearProfile>.unmodifiable(_builtin);

  /// Looks up a built-in profile by identifier; `null` if unknown.
  static GearProfile? byId(String id) {
    for (final profile in _builtin) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  /// "Road" profile with 12 evenly spaced gears, from 0.45 to 3.20.
  static GearProfile get road12 => _builtin[0];

  /// "Climb" profile with 24 closely spaced gears, oriented towards climbing.
  static GearProfile get hillClimb24 => _builtin[1];

  /// "Flat" profile with 8 gears, oriented towards speed.
  static GearProfile get flat8 => _builtin[2];

  static final List<GearProfile> _builtin = <GearProfile>[
    GearProfile(
      id: 'road-12',
      label: 'Road 12 gears',
      gears: _progression(0.45, 3.2, 12),
      bigChainringFactor: const GearRatio(1.35),
    ),
    GearProfile(
      id: 'hill-24',
      label: 'Hill 24 gears',
      gears: _progression(0.45, 2.6, 24),
      bigChainringFactor: const GearRatio(1.2),
    ),
    GearProfile(
      id: 'flat-8',
      label: 'Flat 8 gears',
      gears: _progression(0.9, 3.2, 8),
      bigChainringFactor: const GearRatio(1.4),
    ),
  ];

  @override
  String toString() => 'GearProfile($id, $gearCount gears)';
}

/// Builds a geometric progression of [count] ratios between [lowest] and
/// [highest], which yields constant relative steps between gears.
List<GearRatio> _progression(double lowest, double highest, int count) {
  if (count < 1) {
    throw ArgumentError.value(count, 'count', 'At least one gear is required');
  }
  if (count == 1) return <GearRatio>[GearRatio(lowest)];
  final double logStep = (math.log(highest) - math.log(lowest)) / (count - 1);
  return List<GearRatio>.generate(
    count,
    (index) => GearRatio(_round(math.exp(math.log(lowest) + logStep * index), 3)),
    growable: false,
  );
}

/// Rounds to [decimals] decimals to keep the tables stable and readable.
double _round(double value, int decimals) {
  final double factor = math.pow(10, decimals).toDouble();
  return (value * factor).roundToDouble() / factor;
}

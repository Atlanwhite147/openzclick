/// Virtual shifting engine: tracks the cog index, the virtual chainring, the
/// riding mode and the resistance to send to the trainer.
///
/// No I/O, no clock: the engine is purely functional and reproducible, which
/// makes it testable without hardware.
library;

import 'dart:math' as math;

import 'gear_profile.dart';
import 'gear_ratio.dart';

/// Trainer riding mode.
enum RidingMode {
  /// Route simulation: resistance depends on grade, weight, speed and the
  /// engaged gear ratio.
  sim,

  /// Imposed power: the trainer holds a target in watts that the buttons
  /// change in 5 W steps.
  erg,
}

/// Maximum resistance returned by the engine, in simulated watts.
const double maxResistanceWatts = 1500.0;

/// Maximum grade taken into account, in percent (beyond this the value is
/// clamped: above 25 % the model no longer makes physical sense).
const double maxGradePercent = 25.0;

/// Lowest accepted rider weight, in kilograms.
const double minRiderWeightKg = 20.0;

/// Highest accepted rider weight, in kilograms.
const double maxRiderWeightKg = 250.0;

/// Maximum speed taken into account, in km/h.
const double maxSpeedKmh = 120.0;

/// Minimum ERG target, in watts.
const int minErgWatts = 50;

/// Maximum ERG target, in watts.
const int maxErgWatts = 1000;

/// ERG target adjustment step, in watts.
const int ergStepWatts = 5;

/// ERG target applied on startup.
const int defaultErgWatts = 200;

// Physical model constants (rider + road bike).
const double _gravity = 9.80665; // m/s2
const double _airDensity = 1.225; // kg/m3
const double _dragArea = 0.32; // m2, CdA product
const double _rollingCoefficient = 0.005;
const double _drivetrainEfficiency = 0.97;

/// State of the virtual shifting engine.
class GearEngine {
  /// Transmission profile in use (immutable).
  final GearProfile profile;

  int _gearIndex;
  bool _bigChainring = false;
  RidingMode _mode;
  int _ergWatts = defaultErgWatts;

  /// Creates an engine for [profile].
  ///
  /// [initialGear] is a 0-based index clamped to the profile's valid range;
  /// [mode] defaults to [RidingMode.sim].
  GearEngine({
    required this.profile,
    int initialGear = 0,
    RidingMode mode = RidingMode.sim,
  })  : _gearIndex = initialGear.clamp(0, profile.gearCount - 1).toInt(),
        _mode = mode;

  /// Current cog index, 0-based, 0 = smallest development.
  int get gearIndex => _gearIndex;

  /// Displayable cog number, 1-based.
  int get gearNumber => _gearIndex + 1;

  /// Number of gears in the profile.
  int get gearCount => profile.gearCount;

  /// Current riding mode.
  RidingMode get mode => _mode;

  /// True if the virtual chainring is engaged.
  bool get bigChainringActive => _bigChainring;

  /// Effective ratio: the cog ratio, multiplied by the virtual chainring when
  /// it is engaged. The cog index is never changed by the chainring.
  GearRatio get currentRatio {
    final GearRatio base = profile.gears[_gearIndex];
    final GearRatio? factor = profile.bigChainringFactor;
    if (!_bigChainring || factor == null) return base;
    return base.scaledBy(factor.ratio);
  }

  /// True if the smallest development is engaged.
  bool get atLowest => _gearIndex == 0;

  /// True if the largest development is engaged.
  bool get atHighest => _gearIndex == gearCount - 1;

  /// Shifts up one gear (larger development).
  ///
  /// Returns `true` if the index changed, `false` if the largest development
  /// is already engaged.
  bool shiftUp() {
    if (atHighest) return false;
    _gearIndex++;
    return true;
  }

  /// Shifts down one gear (smaller development).
  ///
  /// Returns `true` if the index changed, `false` if the smallest development
  /// is already engaged.
  bool shiftDown() {
    if (atLowest) return false;
    _gearIndex--;
    return true;
  }

  /// Selects a cog directly.
  ///
  /// [index] is clamped to the profile's valid range; returns `true` if the
  /// effective index changed.
  bool setGear(int index) {
    final int target = index.clamp(0, gearCount - 1).toInt();
    if (target == _gearIndex) return false;
    _gearIndex = target;
    return true;
  }

  /// Toggles the virtual chainring.
  ///
  /// No effect if the profile does not declare a virtual chainring.
  void toggleChainring() {
    if (!profile.hasBigChainring) return;
    _bigChainring = !_bigChainring;
  }

  /// Changes the riding mode; no effect if the mode is unchanged.
  void setMode(RidingMode mode) {
    _mode = mode;
  }

  /// Current power target in ERG mode, in watts.
  int get ergTargetWatts => _ergWatts;

  /// Shifts the ERG target by [deltaWatts] (typically +/-5 W) and returns the
  /// new value, bounded between [minErgWatts] and [maxErgWatts].
  ///
  /// The value is remembered even in SIM mode: it is applied as is when
  /// switching to ERG.
  int bumpErg(int deltaWatts) {
    _ergWatts = (_ergWatts + deltaWatts).clamp(minErgWatts, maxErgWatts).toInt();
    return _ergWatts;
  }

  /// Resistance to apply to the trainer, in simulated watts.
  ///
  /// In [RidingMode.sim] mode, power grows with grade, weight, speed and the
  /// engaged ratio (virtual chainring included); it is bounded to
  /// `[0, 1500]` W. A negative grade (descent) can cancel the resistance but
  /// never returns a negative value.
  ///
  /// In [RidingMode.erg] mode, the returned value is the current ERG target,
  /// that is, the power the trainer must hold.
  ///
  /// Non-finite inputs (`NaN`, infinity) are replaced by a neutral value, and
  /// out-of-range inputs are clamped.
  double targetResistance({
    required double gradePercent,
    required double riderWeightKg,
    required double speedKmh,
  }) {
    if (_mode == RidingMode.erg) return _ergWatts.toDouble();

    final double grade = _sanitize(gradePercent, 0, -maxGradePercent, maxGradePercent);
    final double weight = _sanitize(riderWeightKg, 75, minRiderWeightKg, maxRiderWeightKg);
    final double speed = _sanitize(speedKmh, 0, 0, maxSpeedKmh) / 3.6;

    final double slope = math.atan(grade / 100);
    final double gravityForce = weight * _gravity * math.sin(slope);
    final double rollingForce = _rollingCoefficient * weight * _gravity * math.cos(slope);
    final double aeroForce = 0.5 * _airDensity * _dragArea * speed * speed;
    final double totalForce = gravityForce + rollingForce + aeroForce;

    // Mechanical power at the wheel, corrected for drivetrain efficiency,
    // then scaled by the engaged relative gear ratio.
    final double mechanicalPower = totalForce * speed / _drivetrainEfficiency;
    final double simulatedPower = mechanicalPower * currentRatio.ratio;

    if (!simulatedPower.isFinite) return maxResistanceWatts;
    return simulatedPower.clamp(0, maxResistanceWatts).toDouble();
  }

  @override
  String toString() => 'GearEngine(${profile.id}, gear ${gearIndex + 1}/$gearCount, '
      'ratio ${currentRatio.ratio.toStringAsFixed(3)}, mode ${mode.name})';
}

/// Clamps [value] into `[min, max]` and replaces a non-finite value with
/// [fallback].
double _sanitize(double value, double fallback, double min, double max) {
  if (!value.isFinite) return fallback;
  return value.clamp(min, max).toDouble();
}

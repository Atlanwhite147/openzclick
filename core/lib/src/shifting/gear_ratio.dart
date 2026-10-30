/// Relative development of a gear.
///
/// The ratio is a unitless value, normalised around `1.0`: `1.0` corresponds to
/// a "neutral" development, `0.45` to the smallest usable chainring/cog
/// combination and `3.2` to the largest. It depends on no wheel dimension and
/// no metric development: the shifting engine only deals with relative ratios.
class GearRatio implements Comparable<GearRatio> {
  /// Ratio value, strictly positive and finite.
  final double ratio;

  /// Creates a relative ratio.
  ///
  /// [ratio] must be strictly positive: zero, a negative value or `NaN`
  /// violate the shifting engine's invariant.
  const GearRatio(this.ratio) : assert(ratio > 0, 'A ratio must be strictly positive');

  /// Applies a multiplicative factor (the virtual chainring, for example).
  GearRatio scaledBy(double factor) => GearRatio(ratio * factor);

  @override
  int compareTo(GearRatio other) => ratio.compareTo(other.ratio);

  @override
  bool operator ==(Object other) => other is GearRatio && other.ratio == ratio;

  @override
  int get hashCode => ratio.hashCode;

  @override
  String toString() => 'GearRatio(${ratio.toStringAsFixed(3)})';
}

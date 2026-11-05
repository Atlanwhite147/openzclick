/// Battery level of a controller, turned into the one thing a rider can act on:
/// a warning that appears when it matters and disappears when it is over.
///
/// The controller reports `0..100`, and `0xFF` for "no idea yet". A raw number on
/// a screen does not make anyone charge a pod; a warning that fires once per
/// crossing does, provided it does not repeat on every frame — which is what a
/// naive `if (percent < 20) warn()` does, once per notification, dozens of times
/// a minute.
///
/// Pure logic, no timer: the caller feeds every sample it sees, and gets one
/// notice back.
library;

/// What a battery sample means for the rider.
enum BatteryNotice {
  /// Nothing to say: the level is known and comfortable, or unknown.
  none,

  /// Low enough to charge before the next ride.
  low,

  /// Low enough that the pod may stop before the end of this one.
  critical,

  /// Back above the low threshold, on a fresh charge or a replaced cell.
  recovered,
}

/// Follows one controller's battery and emits a notice per threshold crossing.
class BatteryWatch {
  /// Creates a watch.
  ///
  /// Thresholds are in percent. [recoverAt] must be above [lowAt], so that a cell
  /// hovering around the low mark does not produce a warning at every frame: it
  /// has to climb clear of it.
  BatteryWatch({this.lowAt = 20, this.criticalAt = 8, this.recoverAt = 30}) {
    if (criticalAt >= lowAt) {
      throw ArgumentError('criticalAt must be below lowAt');
    }
    if (recoverAt <= lowAt) {
      throw ArgumentError('recoverAt must be above lowAt');
    }
  }

  /// Level at or below which the rider should charge before the next ride.
  final int lowAt;

  /// Level at or below which the ride may not finish.
  final int criticalAt;

  /// Level at or above which the warning clears.
  final int recoverAt;

  /// Last known level, null while unknown.
  int? percent;

  /// Where the rider stands right now.
  BatteryNotice notice = BatteryNotice.none;

  /// True while a warning is in force.
  bool get warns =>
      notice == BatteryNotice.low || notice == BatteryNotice.critical;

  /// Feeds one sample, `null` or a value outside `0..100` meaning unknown.
  ///
  /// Unknown samples keep the previous state: a pod that stops reporting is not a
  /// pod that recovered.
  BatteryNotice observe(int? sample) {
    if (sample == null || sample < 0 || sample > 100) return BatteryNotice.none;
    percent = sample;
    if (sample <= criticalAt) {
      if (notice == BatteryNotice.critical) return BatteryNotice.none;
      notice = BatteryNotice.critical;
      return BatteryNotice.critical;
    }
    if (sample <= lowAt) {
      // Already under the low mark, whatever the mark was reached from: one
      // warning per crossing, not one per frame.
      if (notice == BatteryNotice.low || notice == BatteryNotice.critical) {
        return BatteryNotice.none;
      }
      notice = BatteryNotice.low;
      return BatteryNotice.low;
    }
    if (sample >= recoverAt && warns) {
      notice = BatteryNotice.none;
      return BatteryNotice.recovered;
    }
    return BatteryNotice.none;
  }

  /// Forgets everything, for a controller that was disconnected.
  void reset() {
    percent = null;
    notice = BatteryNotice.none;
  }
}

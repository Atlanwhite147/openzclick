/// Driving a real trainer through a gear ladder by wheel circumference.
///
/// The bridge sends one number per gear: the wheel size the trainer should
/// believe it is being driven by. Everything the rider feels follows from it, so
/// this file is where the whole ladder meets the machine, and where three
/// rules that are invisible when broken live:
///
/// * **One gear at a time, acknowledgement in between.** A trainer applies a
///   circumference command in tens to hundreds of milliseconds. Sending gear 5
///   while gear 4 is still being applied loses one of them, and the rider then
///   sits in a gear the screen does not show. Measured acknowledgements on a
///   KICKR ran 59 to 238 ms, so this is a real window, not a theoretical one.
/// * **Refuse rather than clamp.** A gear that does not fit the command is
///   reported, never rounded into something the rider did not ask for.
/// * **Never while the application holds ergometer control.** A target power
///   and a gear are contradictory instructions; the machine follows whichever
///   arrived last and the rider cannot tell which.
library;

import 'package:openzclick_core/openzclick_core.dart';

import 'wahoo_wheel_circumference.dart';

/// What went wrong when a gear was applied, if anything.
enum GearApplyResult {
  /// The frame was written and acknowledged.
  applied,

  /// A frame is already in flight; this gear was dropped on purpose.
  droppedWhileBusy,

  /// The gear cannot be expressed as a wheel size inside the support window.
  unsupportedGear,

  /// The riding application holds ergometer control, so a gear means nothing.
  refusedErgometerMode,
}

/// Turns the current gear of a [GearEngine] into trainer frames.
///
/// Holds no Bluetooth: the caller supplies the write function, which keeps the
/// ordering rules testable without hardware and lets the same logic drive a
/// simulated trainer in tests.
class GearCircumferenceDriver {
  /// Creates a driver for [engine], parked in [setup].
  ///
  /// [setup] must be complete: an unfinished setup has no parked gear, and
  /// guessing one is the mistake [ParkedGear] exists to prevent.
  GearCircumferenceDriver({
    required this.engine,
    required PhysicalSetup setup,
  }) : _setup = setup {
    final ParkedGear? parked = setup.parkedGear;
    if (parked == null) {
      throw ArgumentError.value(
        setup,
        'setup',
        'the parked gear must be confirmed before a ladder can be built',
      );
    }
  }

  /// Gear engine whose selection is published to the trainer.
  final GearEngine engine;

  final PhysicalSetup _setup;

  /// The wheel size the trainer is currently working from, in millimetres.
  ///
  /// Starts at the neutral reference and follows every circumference command a
  /// riding application imposes, because the ladder is rebuilt around whatever
  /// value is in force.
  double neutralCircumferenceMillimeters = referenceCircumferenceMillimeters;

  bool _sending = false;
  int _appliedGearIndex = 0;
  GearApplyResult? _lastResult;

  /// The physical setup in force, and the parked gear it implies.
  PhysicalSetup get setup => _setup;

  /// True while a frame is in flight.
  bool get isBusy => _sending;

  /// Result of the most recent attempt, `null` before the first one.
  GearApplyResult? get lastResult => _lastResult;

  /// Wheel size the current gear needs, in millimetres, or `null` when the gear
  /// cannot be expressed.
  double? get currentCircumference => circumferenceForGear(engine.gearIndex);

  /// Wheel size gear [index] needs, in millimetres.
  ///
  /// Returns `null` rather than a clamped value when the result would not fit
  /// the command or would be so small that a training application draws a rider
  /// who has stopped.
  double? circumferenceForGear(int index) {
    final ParkedGear? parked = _setup.parkedGear;
    if (parked == null) return null;
    final List<GearRatio> gears = engine.profile.gears;
    if (index < 0 || index >= gears.length) return null;
    return WheelCircumferenceScaler.effectiveCircumference(
      neutralCircumference: neutralCircumferenceMillimeters,
      parked: parked,
      selectedRatio: gears[index].ratio,
    );
  }

  /// Adopts a wheel size imposed by the riding application.
  ///
  /// The application may set this whenever it likes, including mid-ride, and
  /// the ladder has to follow. A value outside the supported window is ignored
  /// and reported as `false`: the previous wheel size stays in force, so the
  /// gears keep working instead of silently rebuilding around a number no
  /// bicycle has.
  bool adoptApplicationCircumference(double millimeters) {
    if (!WheelCircumferenceScaler.isSupportedRidingAppCircumference(
        millimeters)) {
      return false;
    }
    neutralCircumferenceMillimeters = millimeters;
    return true;
  }

  /// Frames to send for gear [index], in order.
  ///
  /// Empty when the gear cannot be applied, with [lastResult] saying why. The
  /// unlock frame is prepended when [reconnected], because a trainer that has
  /// just been connected ignores circumference commands until it is unlocked
  /// and the symptom is indistinguishable from a wrong wheel size.
  List<List<int>> framesForGear(int index, {bool reconnected = false}) {
    final double? circumference = circumferenceForGear(index);
    if (circumference == null) {
      _lastResult = GearApplyResult.unsupportedGear;
      return const <List<int>>[];
    }
    final double rounded = WheelCircumferenceScaler.asSent(circumference);
    if (!WahooWheelCircumference.isSendable(rounded)) {
      _lastResult = GearApplyResult.unsupportedGear;
      return const <List<int>>[];
    }
    _appliedGearIndex = index;
    _lastResult = GearApplyResult.applied;
    return <List<int>>[
      if (reconnected) WahooUuids.unlockFrame,
      WahooWheelCircumference.setFrame(rounded),
    ];
  }

  /// Applies gear [index] by writing each frame through [write] and waiting for
  /// its acknowledgement.
  ///
  /// Refuses while another gear is still being applied instead of queueing it:
  /// a queue would let the rider shift five times in a second and arrive at the
  /// right gear a minute later, which feels broken. Dropping the intermediate
  /// gears and applying the last one is what the caller should do, and the
  /// result says the drop happened.
  Future<GearApplyResult> applyGear(
    int index, {
    required Future<void> Function(List<int> frame) write,
    bool ergometerMode = false,
    bool reconnected = false,
  }) async {
    if (ergometerMode) {
      _lastResult = GearApplyResult.refusedErgometerMode;
      return GearApplyResult.refusedErgometerMode;
    }
    if (_sending) {
      _lastResult = GearApplyResult.droppedWhileBusy;
      return GearApplyResult.droppedWhileBusy;
    }
    final List<List<int>> frames =
        framesForGear(index, reconnected: reconnected);
    if (frames.isEmpty) return GearApplyResult.unsupportedGear;

    _sending = true;
    try {
      for (final List<int> frame in frames) {
        await write(frame);
      }
      _lastResult = GearApplyResult.applied;
      return GearApplyResult.applied;
    } finally {
      _sending = false;
    }
  }

  /// Index of the gear most recently applied, for the diagnostics screen.
  int get appliedGearIndex => _appliedGearIndex;
}

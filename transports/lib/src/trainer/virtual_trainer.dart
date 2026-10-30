/// The bridge acting as a smart trainer.
///
/// Two applications never share one Bluetooth trainer, and iOS forbids injecting
/// input into another application. The way out is to become the trainer: the
/// bridge holds the real machine, applies the resistance of the selected gear,
/// and presents itself to the training application as an ordinary FTMS trainer.
/// The application then needs to know nothing about gears.
///
/// This file contains the decision logic only, no Bluetooth: it turns control
/// point requests from the application into the exact frame to write on the
/// real trainer, so that the behaviour can be tested against a simulated
/// machine.
library;

import 'package:openzclick_core/openzclick_core.dart';

import 'ftms.dart';

/// What the bridge must do after receiving a request from the application.
class TrainerOutcome {
  /// Builds an outcome.
  const TrainerOutcome({
    this.response,
    this.toTrainer,
    this.resistancePercent,
    this.targetPowerWatts,
    this.simulation,
    this.note = '',
  });

  /// Control point response to send back to the application, null when the
  /// request produces no response.
  final List<int>? response;

  /// Frame to write on the real trainer's control point, null when nothing has
  /// to change on the machine.
  final List<int>? toTrainer;

  /// Resistance the bridge decided to apply, in percent, for the record.
  final double? resistancePercent;

  /// Target power requested in ergometer mode, in watts.
  final int? targetPowerWatts;

  /// Simulation parameters currently in force.
  final SimulationParameters? simulation;

  /// Human readable summary, used by the diagnostic screen and the tests.
  final String note;

  @override
  String toString() =>
      'TrainerOutcome($note, resistance: $resistancePercent %, power: $targetPowerWatts W)';
}

/// Virtual smart trainer driven by the gear engine.
///
/// Modes:
/// * **simulation** - the application sends a grade and the bridge translates
///   the gear into a resistance level for the real trainer;
/// * **ergometer** - the application sends a target power, which is forwarded
///   unchanged, because a fixed power makes the gear meaningless.
class VirtualTrainer {
  /// Creates the virtual trainer.
  ///
  /// [riderWeightKg] feeds the simulation, [trainerMaxWatts] is the power the
  /// real machine can resist at the current speed when its brake is fully
  /// closed. That last value is a property of the machine and of the speed: the
  /// default suits a direct drive trainer around 30 km/h and will need
  /// calibration on other hardware.
  VirtualTrainer({
    required this.engine,
    this.riderWeightKg = 75,
    this.trainerMaxWatts = 1200,
    this.initialSpeedKmh = 25,
  });

  /// Gear engine shared with the rest of the application.
  final GearEngine engine;

  /// Rider weight used by the simulation.
  final double riderWeightKg;

  /// Power the real trainer can resist at full brake, at the current speed.
  final double trainerMaxWatts;

  /// Speed used until the machine reports one.
  final double initialSpeedKmh;

  bool _hasControl = false;
  bool _running = false;

  /// Simulation parameters currently in force.
  SimulationParameters simulation = const SimulationParameters();

  /// Last speed reported by the machine, in km/h.
  double speedKmh = 0;

  /// Last power reported by the machine, in watts.
  int powerWatts = 0;

  /// Last resistance the bridge applied, in percent.
  double appliedResistancePercent = 0;

  /// True when the application holds control of the machine.
  bool get hasControl => _hasControl;

  /// True when the ride is running.
  bool get running => _running;

  /// Records what the real machine reports, so the simulation stays anchored to
  /// reality.
  void updateFromTrainer({double? speedKmh, int? powerWatts, int? cadenceRpm}) {
    if (speedKmh != null && speedKmh >= 0) this.speedKmh = speedKmh;
    if (powerWatts != null) this.powerWatts = powerWatts;
  }

  /// Handles a control point frame written by the application.
  TrainerOutcome handle(List<int> frame) {
    FtmsRequest request;
    try {
      request = FtmsCodec.decodeRequest(frame);
    } on ArgumentError {
      return TrainerOutcome(
        response: FtmsCodec.response(frame.first, FtmsResult.invalidParameter),
        note: 'malformed request',
      );
    }

    if (request is RequestControl) {
      _hasControl = true;
      return TrainerOutcome(
        response: FtmsCodec.response(
          FtmsOpcode.requestControl,
          FtmsResult.success,
        ),
        note: 'control granted',
      );
    }

    if (!_hasControl) {
      return TrainerOutcome(
        response: FtmsCodec.response(
          _opcodeOf(request),
          FtmsResult.controlNotPermitted,
        ),
        note: 'control not requested yet',
      );
    }

    switch (request) {
      case RequestControl():
        // Unreachable: handled above, kept for exhaustiveness.
        _hasControl = true;
        return TrainerOutcome(
          response: FtmsCodec.response(
            FtmsOpcode.requestControl,
            FtmsResult.success,
          ),
          note: 'control granted',
        );

      case StartOrResume():
        _running = true;
        return TrainerOutcome(
          response: FtmsCodec.response(
            FtmsOpcode.startResume,
            FtmsResult.success,
          ),
          note: 'started',
        );

      case StopOrPause():
        _running = false;
        return TrainerOutcome(
          response: FtmsCodec.response(
            FtmsOpcode.stopPause,
            FtmsResult.success,
          ),
          toTrainer: FtmsCodec.response(
            FtmsOpcode.stopPause,
            FtmsResult.success,
          ),
          note: request.stopped ? 'stopped' : 'paused',
        );

      case ResetMachine():
        simulation = const SimulationParameters();
        appliedResistancePercent = 0;
        return TrainerOutcome(
          response: FtmsCodec.response(FtmsOpcode.reset, FtmsResult.success),
          toTrainer: FtmsCodec.resistanceChanged(0),
          resistancePercent: 0,
          simulation: simulation,
          note: 'reset',
        );

      case SetSimulationParameters(:final SimulationParameters parameters):
        simulation = parameters;
        final double percent = _resistanceForGrade(parameters.gradePercent);
        appliedResistancePercent = percent;
        return TrainerOutcome(
          response: FtmsCodec.response(
            FtmsOpcode.setSimulationParameters,
            FtmsResult.success,
          ),
          toTrainer: FtmsCodec.resistanceChanged(percent),
          resistancePercent: percent,
          simulation: simulation,
          note: 'grade ${parameters.gradePercent.toStringAsFixed(1)} % '
              'gear ${engine.gearNumber}/${engine.gearCount}',
        );

      case SetTargetInclination(:final double percent):
        simulation = simulation.withGrade(percent);
        final double resistance = _resistanceForGrade(percent);
        appliedResistancePercent = resistance;
        return TrainerOutcome(
          response: FtmsCodec.response(
            FtmsOpcode.setTargetInclination,
            FtmsResult.success,
          ),
          toTrainer: FtmsCodec.resistanceChanged(resistance),
          resistancePercent: resistance,
          simulation: simulation,
          note: 'inclination ${percent.toStringAsFixed(1)} %',
        );

      case SetTargetResistance(:final double percent):
        appliedResistancePercent = percent;
        return TrainerOutcome(
          response: FtmsCodec.response(
            FtmsOpcode.setTargetResistance,
            FtmsResult.success,
          ),
          toTrainer: FtmsCodec.resistanceChanged(percent),
          resistancePercent: percent,
          note: 'resistance ${percent.toStringAsFixed(0)} %',
        );

      case SetTargetPower(:final int watts):
        return TrainerOutcome(
          response: FtmsCodec.response(
            FtmsOpcode.setTargetPower,
            FtmsResult.success,
          ),
          toTrainer: FtmsCodec.targetPowerChanged(watts),
          targetPowerWatts: watts,
          note: 'ergometer target $watts W',
        );

      case SetWheelCircumference(:final double millimetres):
        return TrainerOutcome(
          response: FtmsCodec.response(
            FtmsOpcode.setWheelCircumference,
            FtmsResult.success,
          ),
          note: 'wheel circumference ${millimetres.toStringAsFixed(1)} mm',
        );

      case UnsupportedRequest(:final int opcode):
        return TrainerOutcome(
          response: FtmsCodec.response(opcode, FtmsResult.notSupported),
          note: 'opcode 0x${opcode.toRadixString(16)} not supported',
        );
    }
  }

  /// Resistance level that reproduces the selected gear at the current speed.
  ///
  /// The physics come from the gear engine, which already accounts for gravity,
  /// rolling resistance, air drag, drivetrain efficiency and the gear ratio.
  /// The result is then expressed as a percentage of what the machine can
  /// resist at that speed, which is the only unit FTMS offers here.
  double _resistanceForGrade(double gradePercent) {
    final double speed = speedKmh > 1 ? speedKmh : initialSpeedKmh;
    final double watts = engine.targetResistance(
      gradePercent: gradePercent,
      riderWeightKg: riderWeightKg,
      speedKmh: speed,
    );
    if (!watts.isFinite || watts <= 0) return 0;
    final double percent = watts / trainerMaxWatts * 100;
    return percent.clamp(0, 100).toDouble();
  }

  static int _opcodeOf(FtmsRequest request) => switch (request) {
        RequestControl() => FtmsOpcode.requestControl,
        ResetMachine() => FtmsOpcode.reset,
        StartOrResume() => FtmsOpcode.startResume,
        StopOrPause() => FtmsOpcode.stopPause,
        SetTargetPower() => FtmsOpcode.setTargetPower,
        SetTargetResistance() => FtmsOpcode.setTargetResistance,
        SetTargetInclination() => FtmsOpcode.setTargetInclination,
        SetSimulationParameters() => FtmsOpcode.setSimulationParameters,
        SetWheelCircumference() => FtmsOpcode.setWheelCircumference,
        UnsupportedRequest(:final int opcode) => opcode,
      };
}

/// Fitness Machine Service (FTMS) protocol, decoded and encoded in pure Dart.
///
/// This is the vocabulary shared by every smart trainer and every training
/// application: the bridge speaks it twice, once towards the real trainer and
/// once towards the application it impersonates.
///
/// FTMS is little endian, unlike the controller protocol.
library;

import 'dart:typed_data';

/// Bluetooth identifiers of the Fitness Machine Service.
abstract final class FtmsUuids {
  /// Fitness Machine Service.
  static const String service = '00001826-0000-1000-8000-00805f9b34fb';

  /// Fitness Machine Feature.
  static const String feature = '00002acc-0000-1000-8000-00805f9b34fb';

  /// Fitness Machine Control Point (write, indicate).
  static const String controlPoint = '00002ad9-0000-1000-8000-00805f9b34fb';

  /// Fitness Machine Status (notify).
  static const String status = '00002ada-0000-1000-8000-00805f9b34fb';

  /// Indoor Bike Data (notify).
  static const String indoorBikeData = '00002ad2-0000-1000-8000-00805f9b34fb';

  /// Supported Resistance Level Range.
  static const String supportedResistanceRange =
      '00002ad6-0000-1000-8000-00805f9b34fb';

  /// Supported Power Range.
  static const String supportedPowerRange =
      '00002ad8-0000-1000-8000-00805f9b34fb';
}

/// Control point opcodes, as sent by the application.
abstract final class FtmsOpcode {
  /// Request control of the machine.
  static const int requestControl = 0x00;

  /// Reset the machine.
  static const int reset = 0x01;

  /// Target speed, in 0.01 km/h.
  static const int setTargetSpeed = 0x02;

  /// Target inclination, in 0.1 %.
  static const int setTargetInclination = 0x03;

  /// Target resistance level, in 0.1.
  static const int setTargetResistance = 0x04;

  /// Target power, in watts.
  static const int setTargetPower = 0x05;

  /// Start or resume.
  static const int startResume = 0x07;

  /// Stop or pause.
  static const int stopPause = 0x08;

  /// Indoor bike simulation parameters.
  static const int setSimulationParameters = 0x11;

  /// Wheel circumference, in 0.1 mm.
  static const int setWheelCircumference = 0x12;

  /// Prefix of every response.
  static const int response = 0x80;

  /// Equipment was started.
  static const int started = 0x04;

  /// Equipment was stopped.
  static const int stopped = 0x05;

  /// Resistance level changed.
  static const int resistanceChanged = 0x07;
}

/// Result codes carried by a control point response.
abstract final class FtmsResult {
  /// The request succeeded.
  static const int success = 0x01;

  /// The opcode is unknown or unsupported.
  static const int notSupported = 0x02;

  /// A parameter is out of range or missing.
  static const int invalidParameter = 0x03;

  /// The operation failed on the machine side.
  static const int failed = 0x04;

  /// The sender does not hold control.
  static const int controlNotPermitted = 0x05;
}

/// Indoor bike simulation parameters sent by the application.
///
/// Values are kept in their natural unit: grade in percent, wind in m/s.
class SimulationParameters {
  /// Builds a parameter set.
  const SimulationParameters({
    this.windSpeed = 0,
    this.gradePercent = 0,
    this.rollingResistance = 0.004,
    this.windResistance = 0.51,
  });

  /// Wind speed in metres per second, negative is headwind.
  final double windSpeed;

  /// Incline in percent, positive uphill.
  final double gradePercent;

  /// Rolling resistance coefficient.
  final double rollingResistance;

  /// Wind resistance coefficient, kg/m.
  final double windResistance;

  /// Copies the parameters with another grade.
  SimulationParameters withGrade(double grade) => SimulationParameters(
        windSpeed: windSpeed,
        gradePercent: grade,
        rollingResistance: rollingResistance,
        windResistance: windResistance,
      );

  @override
  String toString() =>
      'SimulationParameters(grade: $gradePercent %, wind: $windSpeed m/s, '
      'crr: $rollingResistance, cw: $windResistance)';
}

/// A control point request sent by the application.
sealed class FtmsRequest {
  /// Builds a request.
  const FtmsRequest();
}

/// Request control.
class RequestControl extends FtmsRequest {
  /// Builds the request.
  const RequestControl();
}

/// Reset the machine.
class ResetMachine extends FtmsRequest {
  /// Builds the request.
  const ResetMachine();
}

/// Start or resume.
class StartOrResume extends FtmsRequest {
  /// Builds the request.
  const StartOrResume();
}

/// Stop or pause.
class StopOrPause extends FtmsRequest {
  /// Builds the request.
  ///
  /// [stopped] is true for a stop, false for a pause.
  const StopOrPause({required this.stopped});

  /// True when the application asked for a stop rather than a pause.
  final bool stopped;
}

/// Target power, used in ergometer mode.
class SetTargetPower extends FtmsRequest {
  /// Builds the request.
  const SetTargetPower(this.watts);

  /// Target power in watts.
  final int watts;
}

/// Target resistance level, in percent of the machine's maximum.
class SetTargetResistance extends FtmsRequest {
  /// Builds the request.
  const SetTargetResistance(this.percent);

  /// Resistance level, 0 to 100.
  final double percent;
}

/// Target inclination.
class SetTargetInclination extends FtmsRequest {
  /// Builds the request.
  const SetTargetInclination(this.percent);

  /// Grade in percent.
  final double percent;
}

/// Indoor bike simulation parameters.
class SetSimulationParameters extends FtmsRequest {
  /// Builds the request.
  const SetSimulationParameters(this.parameters);

  /// The parameters.
  final SimulationParameters parameters;
}

/// Wheel circumference.
class SetWheelCircumference extends FtmsRequest {
  /// Builds the request.
  const SetWheelCircumference(this.millimetres);

  /// Circumference in millimetres.
  final double millimetres;
}

/// A request the bridge does not implement.
class UnsupportedRequest extends FtmsRequest {
  /// Builds the request.
  const UnsupportedRequest(this.opcode);

  /// The opcode that was received.
  final int opcode;
}

/// Encodes and decodes FTMS frames.
abstract final class FtmsCodec {
  /// Bytes of the Fitness Machine Feature characteristic.
  ///
  /// [features] is the machine capability bitfield, [targets] the target
  /// setting support bitfield. A trainer that accepts resistance and simulation
  /// parameters advertises it here, and applications do check it.
  static List<int> feature({
    int features = 0x00000C00,
    int targets = 0x0000000C,
  }) {
    final ByteData data = ByteData(8)
      ..setUint32(0, features, Endian.little)
      ..setUint32(4, targets, Endian.little);
    return data.buffer.asUint8List();
  }

  /// Decodes the two bitfields of the feature characteristic.
  static ({int features, int targets}) decodeFeature(List<int> frame) {
    if (frame.length < 8) {
      throw ArgumentError.value(frame.length, 'frame', 'expected 8 bytes');
    }
    final ByteData data = ByteData.sublistView(Uint8List.fromList(frame));
    return (
      features: data.getUint32(0, Endian.little),
      targets: data.getUint32(4, Endian.little),
    );
  }

  /// Decodes a control point request.
  ///
  /// Throws [ArgumentError] when the frame is empty or truncated, which the
  /// caller turns into an [FtmsResult.invalidParameter] response.
  static FtmsRequest decodeRequest(List<int> frame) {
    if (frame.isEmpty) {
      throw ArgumentError.value(frame, 'frame', 'empty request');
    }
    final ByteData data = ByteData.sublistView(Uint8List.fromList(frame));
    final int opcode = data.getUint8(0);

    int need(int bytes) {
      if (data.lengthInBytes < bytes) {
        throw ArgumentError.value(frame, 'frame', 'truncated $opcode request');
      }
      return bytes;
    }

    switch (opcode) {
      case FtmsOpcode.requestControl:
        return const RequestControl();
      case FtmsOpcode.reset:
        return const ResetMachine();
      case FtmsOpcode.startResume:
        return const StartOrResume();
      case FtmsOpcode.stopPause:
        need(2);
        return StopOrPause(stopped: data.getUint8(1) == 0x01);
      case FtmsOpcode.setTargetPower:
        need(3);
        return SetTargetPower(data.getInt16(1, Endian.little));
      case FtmsOpcode.setTargetResistance:
        need(2);
        return SetTargetResistance(data.getUint8(1).toDouble());
      case FtmsOpcode.setTargetInclination:
        need(3);
        return SetTargetInclination(
          data.getInt16(1, Endian.little) / 10.0,
        );
      case FtmsOpcode.setWheelCircumference:
        need(3);
        return SetWheelCircumference(
          data.getUint16(1, Endian.little) / 10.0,
        );
      case FtmsOpcode.setSimulationParameters:
        need(7);
        return SetSimulationParameters(
          SimulationParameters(
            windSpeed: data.getInt16(1, Endian.little) / 1000.0,
            gradePercent: data.getInt16(3, Endian.little) / 100.0,
            rollingResistance: data.getUint8(5) / 10000.0,
            windResistance: data.getUint8(6) / 100.0,
          ),
        );
      default:
        return UnsupportedRequest(opcode);
    }
  }

  /// Builds a control point response.
  static List<int> response(int opcode, int result) => <int>[
        FtmsOpcode.response,
        opcode,
        result,
      ];

  /// Builds a "target resistance changed" indication towards the trainer.
  static List<int> resistanceChanged(double percent) => <int>[
        FtmsOpcode.resistanceChanged,
        percent.clamp(0, 100).round(),
      ];

  /// Builds a "target power changed" indication towards the trainer.
  static List<int> targetPowerChanged(int watts) {
    final ByteData data = ByteData(3)
      ..setUint8(0, 0x08)
      ..setInt16(1, watts, Endian.little);
    return data.buffer.asUint8List();
  }

  /// Builds a "simulation parameters changed" request towards the trainer.
  static List<int> simulationParameters(SimulationParameters parameters) {
    final ByteData data = ByteData(7)
      ..setUint8(0, FtmsOpcode.setSimulationParameters)
      ..setInt16(1, (parameters.windSpeed * 1000).round(), Endian.little)
      ..setInt16(3, (parameters.gradePercent * 100).round(), Endian.little)
      ..setUint8(5, (parameters.rollingResistance * 10000).round())
      ..setUint8(6, (parameters.windResistance * 100).round());
    return data.buffer.asUint8List();
  }

  /// Builds an Indoor Bike Data frame.
  ///
  /// Speed is in km/h, cadence in rpm, power in watts. Bit 0 of the flags is the
  /// "more data" marker: it stays clear while the instantaneous speed is sent,
  /// and is set when the speed field is omitted.
  ///
  /// The resistance field is voluntary in the specification and its unit (0.1,
  /// so a 0 to 25.5 range on one byte) cannot carry a percentage: the bridge
  /// therefore never publishes it, and applications read the resistance they
  /// apply themselves.
  static List<int> indoorBikeData({
    double? speedKmh,
    int? cadenceRpm,
    int? powerWatts,
  }) {
    int flags = 0;
    final List<int> body = <int>[];

    if (speedKmh == null) {
      flags |= 1 << 0; // more data: the speed field is not present
    } else {
      body.addAll(_uint16((speedKmh * 100).round()));
    }
    if (cadenceRpm != null) {
      flags |= 1 << 2;
      body.addAll(_uint16(cadenceRpm));
    }
    if (powerWatts != null) {
      flags |= 1 << 6;
      body.addAll(_int16(powerWatts));
    }

    return <int>[..._uint16(flags), ...body];
  }

  /// Decodes an Indoor Bike Data frame.
  static ({
    double? speedKmh,
    int? cadenceRpm,
    int? powerWatts,
    double? resistancePercent,
  }) decodeIndoorBikeData(List<int> frame) {
    if (frame.length < 2) {
      throw ArgumentError.value(frame, 'frame', 'expected at least 2 bytes');
    }
    final ByteData data = ByteData.sublistView(Uint8List.fromList(frame));
    final int flags = data.getUint16(0, Endian.little);
    int index = 2;

    double? speed;
    int? cadence;
    int? power;
    double? resistance;

    // Bit 0 clear means instantaneous speed is present.
    if (flags & (1 << 0) == 0) {
      if (index + 2 > data.lengthInBytes) {
        return (
          speedKmh: null,
          cadenceRpm: null,
          powerWatts: null,
          resistancePercent: null,
        );
      }
      speed = data.getUint16(index, Endian.little) / 100.0;
      index += 2;
    }
    if (flags & (1 << 1) != 0) index += 2; // average speed
    if (flags & (1 << 2) != 0) {
      if (index + 2 > data.lengthInBytes) {
        return (
          speedKmh: speed,
          cadenceRpm: null,
          powerWatts: null,
          resistancePercent: null,
        );
      }
      cadence = data.getUint16(index, Endian.little);
      index += 2;
    }
    if (flags & (1 << 3) != 0) index += 2; // average cadence
    if (flags & (1 << 4) != 0) index += 3; // total distance
    if (flags & (1 << 5) != 0) {
      if (index + 1 > data.lengthInBytes) {
        return (
          speedKmh: speed,
          cadenceRpm: cadence,
          powerWatts: null,
          resistancePercent: null,
        );
      }
      resistance = data.getUint8(index) / 10.0;
      index += 1;
    }
    if (flags & (1 << 6) != 0 && index + 2 <= data.lengthInBytes) {
      power = data.getInt16(index, Endian.little);
    }

    return (
      speedKmh: speed,
      cadenceRpm: cadence,
      powerWatts: power,
      resistancePercent: resistance
    );
  }

  static List<int> _uint16(int value) {
    final ByteData data = ByteData(2)
      ..setUint16(0, value.clamp(0, 0xFFFF), Endian.little);
    return data.buffer.asUint8List();
  }

  static List<int> _int16(int value) {
    final ByteData data = ByteData(2)
      ..setInt16(0, value.clamp(-32768, 32767), Endian.little);
    return data.buffer.asUint8List();
  }
}

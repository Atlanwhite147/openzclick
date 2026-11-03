/// Cycling Power service (0x1818), encoded and decoded in pure Dart.
///
/// A bridge that presents itself as an FTMS trainer is enough for Zwift, but
/// Windows applications also look for a plain cycling power meter and show
/// `0 W` and `0 rpm` when they do not find one. The service is small, its frames
/// are fixed layout, and publishing it makes the power and cadence the trainer
/// already reports visible to those applications.
///
/// The crank revolution field is what carries cadence: an application divides
/// the change in revolution count by the change in event time, so a bridge that
/// fills only the power field shows watts and no legs. Both fields are therefore
/// sent together, from the same clock.
library;

import 'dart:typed_data';

/// Bluetooth identifiers of the Cycling Power service.
abstract final class CyclingPowerUuids {
  /// Cycling Power service.
  static const String service = '00001818-0000-1000-8000-00805f9b34fb';

  /// Cycling Power Measurement (notify).
  static const String measurement = '00002a63-0000-1000-8000-00805f9b34fb';

  /// Cycling Power Feature (read).
  static const String feature = '00002a65-0000-1000-8000-00805f9b34fb';

  /// Sensor Location (read).
  static const String sensorLocation = '00002a5d-0000-1000-8000-00805f9b34fb';
}

/// Bit meanings of the Cycling Power Measurement flags field.
///
/// Only the two this bridge sets are named: naming flags it never sends would
/// suggest the encoder handles them.
abstract final class CyclingPowerFlags {
  /// Crank revolution data present (bit 5): cumulative revolutions and the time
  /// of the last crank event.
  static const int crankRevolutionData = 1 << 5;
}

/// Where a power meter is mounted, as the Sensor Location characteristic says.
abstract final class CyclingPowerSensorLocation {
  /// Bottom bracket, which is where a crank-based meter sits and the honest
  /// answer for a bridge repeating a trainer's power.
  static const int bottomBracket = 8;
}

/// One Cycling Power Measurement frame.
class CyclingPowerMeasurement {
  /// Builds a measurement.
  ///
  /// [cumulativeCrankRevolutions] wraps at 65536 and [lastCrankEventTime] at
  /// 65536/1024 s, exactly as the specification says; the receiver is expected
  /// to handle the wrap, so the sender does not have to.
  const CyclingPowerMeasurement({
    required this.powerWatts,
    required this.cumulativeCrankRevolutions,
    required this.lastCrankEventTime,
  });

  /// Instantaneous power, in watts.
  final int powerWatts;

  /// Crank revolutions since the sensor started, modulo 65536.
  final int cumulativeCrankRevolutions;

  /// Time of the last crank event, in 1/1024 s, modulo 65536.
  final int lastCrankEventTime;

  /// Cadence the receiver will compute from two successive frames.
  ///
  /// Kept as a helper rather than a field: it is derived, and sending a cadence
  /// directly would contradict the revolution counters.
  double cadenceRpmSince(CyclingPowerMeasurement previous) {
    int revolutions =
        cumulativeCrankRevolutions - previous.cumulativeCrankRevolutions;
    if (revolutions < 0) revolutions += 65536;
    int ticks = lastCrankEventTime - previous.lastCrankEventTime;
    if (ticks < 0) ticks += 65536;
    if (ticks == 0) return 0;
    // 1024 ticks per second, 60 seconds per minute.
    return revolutions * 60 * 1024 / ticks;
  }

  @override
  String toString() => 'CyclingPowerMeasurement($powerWatts W, '
      '$cumulativeCrankRevolutions rev @ $lastCrankEventTime)';
}

/// Encodes and decodes Cycling Power frames.
abstract final class CyclingPowerCodec {
  /// Builds a measurement frame carrying power and crank revolution data.
  ///
  /// Throws [ArgumentError] when power does not fit in the signed 16 bits the
  /// specification gives it, rather than clamping: a clamped power reading is a
  /// number the application believes.
  static List<int> measurement(CyclingPowerMeasurement value) {
    if (value.powerWatts < -32768 || value.powerWatts > 32767) {
      throw ArgumentError.value(
        value.powerWatts,
        'powerWatts',
        'instantaneous power is a signed 16-bit value',
      );
    }
    final ByteData data = ByteData(8)
      ..setUint16(0, CyclingPowerFlags.crankRevolutionData, Endian.little)
      ..setInt16(2, value.powerWatts, Endian.little)
      ..setUint16(4, value.cumulativeCrankRevolutions & 0xffff, Endian.little)
      ..setUint16(6, value.lastCrankEventTime & 0xffff, Endian.little);
    return data.buffer.asUint8List();
  }

  /// Reads a measurement frame built by [measurement].
  ///
  /// Returns `null` when the frame carries no crank revolution data, because
  /// such a frame has no cadence and this bridge always sends both fields
  /// together.
  static CyclingPowerMeasurement? decodeMeasurement(List<int> frame) {
    if (frame.length < 4) return null;
    final ByteData data = ByteData.sublistView(Uint8List.fromList(frame));
    final int flags = data.getUint16(0, Endian.little);
    int index = 2;
    final int power = data.getInt16(index, Endian.little);
    index += 2;
    if (flags & CyclingPowerFlags.crankRevolutionData == 0) {
      return CyclingPowerMeasurement(
        powerWatts: power,
        cumulativeCrankRevolutions: 0,
        lastCrankEventTime: 0,
      );
    }
    if (frame.length < index + 4) return null;
    return CyclingPowerMeasurement(
      powerWatts: power,
      cumulativeCrankRevolutions: data.getUint16(index, Endian.little),
      lastCrankEventTime: data.getUint16(index + 2, Endian.little),
    );
  }

  /// Builds the feature bitfield a bridge advertises.
  ///
  /// Zero means "nothing beyond the mandatory features": this bridge reports
  /// power and crank revolutions and claims no offset compensation, no extreme
  /// values and no accumulated energy, because it has none of them.
  static List<int> feature() => const <int>[0x00, 0x00, 0x00, 0x00];

  /// Builds the Sensor Location value.
  static List<int> sensorLocationValue() =>
      const <int>[CyclingPowerSensorLocation.bottomBracket];
}

/// Turns a cadence the trainer reports into the revolution counters a Cycling
/// Power receiver expects.
///
/// Keeping this clock here rather than inside a transport makes it testable
/// without Bluetooth, and keeps the wrap arithmetic in one place; the 16-bit
/// counters are the part that is easy to get wrong and impossible to see going
/// wrong on a short ride.
class CrankRevolutionClock {
  /// Creates a clock starting at zero revolutions at time zero.
  CrankRevolutionClock({this.ticksPerSecond = 1024});

  /// Ticks per second of the event time field, from the specification.
  final int ticksPerSecond;

  int _revolutions = 0;
  int _ticks = 0;
  double _partialRevolution = 0;

  /// Cumulative crank revolutions, modulo 65536.
  int get cumulativeCrankRevolutions => _revolutions & 0xffff;

  /// Time of the last crank event, in ticks, modulo 65536.
  int get lastCrankEventTime => _ticks & 0xffff;

  /// Advances the clock by [elapsed] at [cadenceRpm].
  ///
  /// A cadence of zero or less advances the time but not the revolutions: the
  /// receiver then computes a cadence of zero from the unchanged counters,
  /// which is what stopping looks like and is why time must still advance.
  CyclingPowerMeasurement advance({
    required Duration elapsed,
    required double cadenceRpm,
  }) {
    if (elapsed <= Duration.zero) {
      throw ArgumentError.value(elapsed, 'elapsed', 'must be positive');
    }
    final int ticks =
        (elapsed.inMicroseconds * ticksPerSecond / 1000000).round();
    _ticks += ticks;
    if (ticks <= 0) {
      throw StateError('an elapsed duration shorter than one tick is unusable');
    }
    if (cadenceRpm.isFinite && cadenceRpm > 0) {
      final double revolutions =
          cadenceRpm / 60 * (ticks / ticksPerSecond) + _partialRevolution;
      final int whole = revolutions.floor();
      _partialRevolution = revolutions - whole;
      _revolutions += whole;
    }
    return CyclingPowerMeasurement(
      powerWatts: 0,
      cumulativeCrankRevolutions: cumulativeCrankRevolutions,
      lastCrankEventTime: lastCrankEventTime,
    );
  }
}

/// Wheel circumference commands for a Wahoo KICKR, in pure Dart.
///
/// A KICKR is told the wheel size it should pretend to be driven by, and works
/// out its brake force from the distance one pedal stroke covers. That single
/// number is therefore the lever every gear on this bridge pulls: making it
/// smaller makes every gear easier without touching the terrain the training
/// application sends, and the application never learns that gears exist.
///
/// The frame layout comes from the protocol a KICKR accepts on its control
/// characteristic, not from any particular implementation: command `0x48`,
/// followed by the wheel size as a 16-bit little endian value in tenths of a
/// millimetre.
///
/// The unlock frame matters because a KICKR silently ignores writes until it
/// has been unlocked, and "the trainer ignores us" is indistinguishable from a
/// wrong wheel size on the rider's legs. Sending it once per connection is not
/// redundant: it is what makes the rest work.
library;

import 'dart:typed_data';

/// Bluetooth identifiers of a KICKR's control characteristic.
abstract final class WahooUuids {
  /// Characteristic that accepts the wheel circumference command and the
  /// unlock frame. It belongs to a Wahoo-specific service, not to FTMS.
  static const String controlCharacteristic =
      'a026e005-0a7d-4ab3-97fa-f1500f9feb8b';

  /// Frame that unlocks the control characteristic for the current connection.
  ///
  /// Constant by design: it carries no session key and no timestamp, so it can
  /// be sent as is on every reconnection.
  static const List<int> unlockFrame = <int>[0x20, 0xee, 0xfc];
}

/// Wheel circumference commands a KICKR understands.
abstract final class WahooWheelCircumference {
  /// Opcode that sets the wheel circumference.
  static const int setCircumferenceOpcode = 0x48;

  /// Smallest circumference a command can carry, in millimetres.
  ///
  /// One tenth of a millimetre is the encoding step, so the floor is one step
  /// rather than zero: a zero circumference would ask the trainer to divide by
  /// nothing.
  static const double minMillimeters = 0.1;

  /// Largest circumference a command can carry, in millimetres.
  ///
  /// A 16-bit value in tenths of a millimetre: 65535 / 10.
  static const double maxMillimeters = 6553.5;

  /// Builds the frame that sets the wheel circumference to [millimeters].
  ///
  /// The value is rounded to the tenth of a millimetre the encoding carries, so
  /// a caller may pass a computed circumference without rounding it first.
  ///
  /// Throws [ArgumentError] when [millimeters] does not fit in the command,
  /// rather than clamping: a clamped wheel size silently hands the rider a
  /// different gear from the one on screen, which is the exact failure this
  /// whole file exists to avoid.
  static List<int> setFrame(double millimeters) {
    if (!millimeters.isFinite) {
      throw ArgumentError.value(millimeters, 'millimeters', 'must be finite');
    }
    if (millimeters < minMillimeters || millimeters > maxMillimeters) {
      throw ArgumentError.value(
        millimeters,
        'millimeters',
        'a wheel circumference command carries '
            '$minMillimeters to $maxMillimeters mm',
      );
    }
    final int tenths = (millimeters * 10).round();
    if (tenths < 1 || tenths > 0xffff) {
      throw ArgumentError.value(
          millimeters, 'millimeters', 'does not fit in 16 bits of tenths');
    }
    final ByteData data = ByteData(3)
      ..setUint8(0, setCircumferenceOpcode)
      ..setUint16(1, tenths, Endian.little);
    return data.buffer.asUint8List();
  }

  /// True when [millimeters] can be sent as is.
  static bool isSendable(double millimeters) =>
      millimeters.isFinite &&
      millimeters >= minMillimeters &&
      millimeters <= maxMillimeters;

  /// Reads the wheel circumference back out of a frame built by [setFrame].
  ///
  /// Used by the diagnostics screen and by the tests: a bridge that cannot read
  /// its own commands cannot prove what it sent.
  static double? decode(List<int> frame) {
    if (frame.length < 3) return null;
    if (frame[0] != setCircumferenceOpcode) return null;
    final ByteData data = ByteData.sublistView(Uint8List.fromList(frame));
    return data.getUint16(1, Endian.little) / 10;
  }
}

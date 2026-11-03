import 'package:openzclick_transports/openzclick_transports.dart';
import 'package:test/test.dart';

void main() {
  group('WahooWheelCircumference.setFrame', () {
    test('carries the wheel size in tenths of a millimetre, little endian', () {
      // 2105.0 mm = 21050 tenths = 0x523A. On the wire: 48 | 3A 52.
      expect(
        WahooWheelCircumference.setFrame(2105.0),
        <int>[0x48, 0x3a, 0x52],
      );
    });

    test('rounds a computed circumference instead of refusing it', () {
      // The caller may hand over a computed value; the encoding carries tenths.
      expect(
          WahooWheelCircumference.setFrame(2105.04), <int>[0x48, 0x3a, 0x52]);
      expect(
          WahooWheelCircumference.setFrame(2105.06), <int>[0x48, 0x3b, 0x52]);
    });

    test('reaches the whole span the encoding allows', () {
      expect(WahooWheelCircumference.setFrame(0.1), <int>[0x48, 0x01, 0x00]);
      expect(WahooWheelCircumference.setFrame(6553.5), <int>[0x48, 0xff, 0xff]);
    });

    test('refuses a wheel size outside the command rather than clamping it',
        () {
      // Clamping is the failure this file exists to prevent: the rider would be
      // in a gear the screen does not show.
      for (final double bad in <double>[0, 0.05, 6553.6, 9000, -1]) {
        expect(
          () => WahooWheelCircumference.setFrame(bad),
          throwsArgumentError,
          reason: '$bad mm does not fit',
        );
      }
    });

    test('refuses a non-finite wheel size', () {
      expect(() => WahooWheelCircumference.setFrame(double.nan),
          throwsArgumentError);
      expect(() => WahooWheelCircumference.setFrame(double.infinity),
          throwsArgumentError);
    });

    test('reads back what it wrote', () {
      for (final double millimeters in <double>[500, 2105, 2326, 6553.5]) {
        expect(
          WahooWheelCircumference.decode(
              WahooWheelCircumference.setFrame(millimeters)),
          millimeters,
        );
      }
    });

    test('does not mistake another command for a wheel size', () {
      expect(WahooWheelCircumference.decode(<int>[0x49, 0x3a, 0x52]), isNull);
      expect(WahooWheelCircumference.decode(<int>[0x48, 0x3a]), isNull);
    });

    test('says whether a value can be sent', () {
      expect(WahooWheelCircumference.isSendable(2105), isTrue);
      expect(WahooWheelCircumference.isSendable(0), isFalse);
      expect(WahooWheelCircumference.isSendable(6553.6), isFalse);
      expect(WahooWheelCircumference.isSendable(double.nan), isFalse);
    });

    test('unlocks with a frame that carries no session state', () {
      // Sent on every reconnection, so it must not depend on anything.
      expect(WahooUuids.unlockFrame, <int>[0x20, 0xee, 0xfc]);
      expect(
        WahooUuids.controlCharacteristic,
        'a026e005-0a7d-4ab3-97fa-f1500f9feb8b',
      );
    });
  });
}

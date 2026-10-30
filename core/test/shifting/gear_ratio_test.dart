import 'package:openzclick_core/src/shifting/gear_ratio.dart';
import 'package:test/test.dart';

void main() {
  group('GearRatio', () {
    test('keeps the provided value', () {
      const ratio = GearRatio(1.75);
      expect(ratio.ratio, 1.75);
    });

    test('compares two ratios by value', () {
      const petit = GearRatio(0.5);
      const grand = GearRatio(2.4);
      expect(petit.compareTo(grand), lessThan(0));
      expect(grand.compareTo(petit), greaterThan(0));
      expect(petit.compareTo(const GearRatio(0.5)), 0);
      expect(<GearRatio>[grand, petit]..sort(), <GearRatio>[petit, grand]);
    });

    test('structural equality and hashCode', () {
      const a = GearRatio(1.2);
      const b = GearRatio(1.2);
      const c = GearRatio(1.3);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test(
        'scaledBy applies a multiplicative factor without altering the original',
        () {
      const base = GearRatio(1.0);
      final boosted = base.scaledBy(1.35);
      expect(boosted.ratio, closeTo(1.35, 1e-12));
      expect(base.ratio, 1.0);
    });

    test('rejects a zero or negative ratio', () {
      expect(() => GearRatio(0), throwsA(isA<AssertionError>()));
      expect(() => GearRatio(-1), throwsA(isA<AssertionError>()));
    });

    test('toString is readable and rounded', () {
      expect(const GearRatio(1.23456).toString(), 'GearRatio(1.235)');
    });
  });
}

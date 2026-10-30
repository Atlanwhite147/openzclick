import 'package:openzclick_core/src/shifting/gear_profile.dart';
import 'package:openzclick_core/src/shifting/gear_ratio.dart';
import 'package:test/test.dart';

List<GearRatio> _ratios(int count) => List<GearRatio>.generate(
    count, (int index) => GearRatio(1.0 + index * 0.05));

void main() {
  group('GearProfile', () {
    test('built-in profiles match the contract', () {
      final List<GearProfile> profiles = GearProfile.builtin;
      expect(profiles.map((GearProfile p) => p.id),
          <String>['road-12', 'hill-24', 'flat-8']);
      expect(GearProfile.road12.gearCount, 12);
      expect(GearProfile.hillClimb24.gearCount, 24);
      expect(GearProfile.flat8.gearCount, 8);
      expect(GearProfile.byId('road-12'), same(GearProfile.road12));
      expect(GearProfile.byId('unknown'), isNull);
    });

    test('built-in ratios stay normalised between 0.45 and 3.2', () {
      for (final GearProfile profile in GearProfile.builtin) {
        for (final GearRatio gear in profile.gears) {
          expect(gear.ratio, greaterThanOrEqualTo(0.45), reason: profile.id);
          expect(gear.ratio, lessThanOrEqualTo(3.2), reason: profile.id);
          expect(gear.ratio.isFinite, isTrue, reason: profile.id);
        }
      }
    });

    test('built-in ratios are strictly increasing', () {
      for (final GearProfile profile in GearProfile.builtin) {
        for (int index = 1; index < profile.gearCount; index++) {
          expect(
            profile.gears[index].ratio,
            greaterThan(profile.gears[index - 1].ratio),
            reason: '${profile.id} index $index',
          );
        }
      }
    });

    test('first and last ratios are exposed', () {
      final GearProfile profile = GearProfile.road12;
      expect(profile.lowest, same(profile.gears.first));
      expect(profile.highest, same(profile.gears.last));
    });

    test('virtual chainring declared on the built-in profiles', () {
      for (final GearProfile profile in GearProfile.builtin) {
        expect(profile.hasBigChainring, isTrue, reason: profile.id);
        expect(profile.bigChainringFactor!.ratio, greaterThan(1.0),
            reason: profile.id);
      }
    });

    test('gear list is unmodifiable', () {
      final GearProfile profile = GearProfile(
        id: 'test',
        label: 'Test',
        gears: _ratios(3),
      );
      expect(
          () => profile.gears.add(const GearRatio(9)), throwsUnsupportedError);
      expect(profile.gearCount, 3);
    });

    test('rejects an empty identifier', () {
      expect(
        () => GearProfile(id: '  ', label: 'Test', gears: _ratios(2)),
        throwsArgumentError,
      );
    });

    test('rejects an empty or too long gear list', () {
      expect(
        () =>
            GearProfile(id: 'vide', label: 'Vide', gears: const <GearRatio>[]),
        throwsArgumentError,
      );
      expect(
        () => GearProfile(
            id: 'trop', label: 'Trop', gears: _ratios(maxGearCount + 1)),
        throwsArgumentError,
      );
      expect(
        GearProfile(id: 'limite', label: 'Limite', gears: _ratios(maxGearCount))
            .gearCount,
        maxGearCount,
      );
    });

    test('rejects a non-finite ratio or an invalid chainring factor', () {
      expect(
        () => GearProfile(
          id: 'infini',
          label: 'Infini',
          gears: <GearRatio>[
            const GearRatio(1.0),
            const GearRatio(double.infinity)
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => GearProfile(
          id: 'facteur',
          label: 'Facteur',
          gears: _ratios(2),
          bigChainringFactor: const GearRatio(double.infinity),
        ),
        throwsArgumentError,
      );
    });
  });
}

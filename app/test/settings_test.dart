import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick/net/injection_publisher.dart';
import 'package:openzclick/settings/settings_store.dart';
import 'package:openzclick/state/app_state.dart';

void main() {
  test('restores the profile, the gear and the tap positions', () async {
    final MemorySettingsStore store = MemorySettingsStore();
    await store.save(
      const SettingsSnapshot(
        profileId: 'hill-24',
        gearIndex: 10,
        positions: <Action, List<double>>{
          Action.shiftUp: <double>[0.5, 0.6],
        },
        publishOnStart: false,
        injectOnStart: false,
      ),
    );

    final AppState state = AppState();
    await state.restore(store);
    expect(state.engine.profile.id, 'hill-24');
    expect(state.engine.gearIndex, 10);
    expect(state.injection.positions[Action.shiftUp], <double>[0.5, 0.6]);
    state.dispose();
  });

  test('persists a gear change', () async {
    final MemorySettingsStore store = MemorySettingsStore();
    final AppState state = AppState();
    await state.restore(store);
    state.shiftUp();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final SettingsSnapshot? saved = await store.load();
    expect(store.writes, greaterThan(0));
    expect(saved!.gearIndex, state.engine.gearIndex);
    expect(saved.profileId, state.engine.profile.id);
    state.dispose();
  });

  test('persists a tap position', () async {
    final MemorySettingsStore store = MemorySettingsStore();
    final AppState state = AppState();
    await state.restore(store);
    state.injection.setPosition(Action.steerLeft, 0.1, 0.9);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final SettingsSnapshot? saved = await store.load();
    expect(saved!.positions[Action.steerLeft], <double>[0.1, 0.9]);
    state.dispose();
  });

  test('restores where the chain was left on the bike', () async {
    // Setup is answered once. Asking again every launch is the same question
    // with the same answer; forgetting it moves every gear silently.
    final MemorySettingsStore store = MemorySettingsStore();
    await store.save(
      const SettingsSnapshot(
        profileId: 'road-12',
        gearIndex: 3,
        positions: <Action, List<double>>{},
        publishOnStart: false,
        injectOnStart: false,
        parkedChainringTeeth: 50,
        parkedCogTeeth: 17,
      ),
    );
    final AppState state = AppState();
    await state.restore(store);
    expect(state.physicalSetup.parkedGear, isNotNull);
    expect(state.physicalSetup.parkedGear!.name, '50/17');
    expect(state.currentWheelCircumference, isNotNull);
    state.dispose();
  });

  test('persists the parked gear once the rider chooses it', () async {
    final MemorySettingsStore store = MemorySettingsStore();
    final AppState state = AppState();
    await state.restore(store);
    expect(state.physicalSetup.isComplete, isFalse);

    state.setParkedGear(chainring: 34, cog: 21);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final SettingsSnapshot? saved = await store.load();
    expect(saved!.parkedChainringTeeth, 34);
    expect(saved.parkedCogTeeth, 21);
    expect(state.physicalSetup.isComplete, isTrue);
    state.dispose();
  });

  test('refuses a parked gear the bike does not have', () async {
    final AppState state = AppState();
    state.setParkedGear(chainring: 34, cog: 19);
    state.setParkedGear(chainring: 39, cog: 19);
    expect(state.physicalSetup.parkedChainringTeeth, 34);
    state.dispose();
  });

  test('a gear the setup cannot build has no wheel size to show', () async {
    // Parked in the big ring on the smallest cog, the easiest gear needs a
    // wheel so small that a training application would draw a stopped rider.
    final AppState state = AppState();
    state.setParkedGear(chainring: 50, cog: 11);
    state.engine = GearEngine(profile: GearProfile.road12, initialGear: 0);
    expect(state.currentWheelCircumference, isNull);
    state.dispose();
  });

  test('changing profile keeps the relative position', () async {
    final AppState state = AppState();
    state.engine = GearEngine(profile: GearProfile.road12, initialGear: 11);
    state.setProfile('flat-8');
    expect(state.engine.profile.id, 'flat-8');
    expect(state.engine.gearCount, 8);
    expect(state.engine.gearIndex, 7);
    state.dispose();
  });

  test('an unknown profile is ignored', () async {
    final AppState state = AppState();
    final String before = state.engine.profile.id;
    state.setProfile('nope-99');
    expect(state.engine.profile.id, before);
    state.dispose();
  });

  test('a snapshot without positions keeps the defaults', () async {
    final MemorySettingsStore store = MemorySettingsStore();
    await store.save(
      const SettingsSnapshot(
        profileId: 'road-12',
        gearIndex: 3,
        positions: <Action, List<double>>{},
        publishOnStart: false,
        injectOnStart: false,
      ),
    );
    final AppState state = AppState();
    await state.restore(store);
    expect(
      state.injection.positions[Action.shiftUp],
      InjectionPublisher.defaultPositions[Action.shiftUp],
    );
    state.dispose();
  });
}

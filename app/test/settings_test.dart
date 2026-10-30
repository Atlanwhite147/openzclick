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

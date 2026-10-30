/// Settings that survive a restart.
///
/// The application keeps very little: the gear profile, the current gear, the
/// tap positions and whether the two publishers were running. Everything else
/// is derived at runtime.
library;

import 'package:openzclick_core/openzclick_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Snapshot of what the application stores on disk.
class SettingsSnapshot {
  /// Builds a snapshot.
  const SettingsSnapshot({
    required this.profileId,
    required this.gearIndex,
    required this.positions,
    required this.publishOnStart,
    required this.injectOnStart,
  });

  /// Identifier of the gear profile.
  final String profileId;

  /// Zero-based gear index inside that profile.
  final int gearIndex;

  /// Relative tap positions per action.
  final Map<Action, List<double>> positions;

  /// Whether the network publication should resume on the next start.
  final bool publishOnStart;

  /// Whether the tap injection should resume on the next start.
  final bool injectOnStart;
}

/// Persistence port: the application depends on this, never on a plugin.
abstract interface class SettingsStore {
  /// Reads the stored snapshot, or null the first time.
  Future<SettingsSnapshot?> load();

  /// Writes [snapshot], replacing the previous one.
  Future<void> save(SettingsSnapshot snapshot);
}

/// Store backed by `shared_preferences`.
class PrefsSettingsStore implements SettingsStore {
  static const String _profileKey = 'openzclick.profile';
  static const String _gearKey = 'openzclick.gear';
  static const String _publishKey = 'openzclick.publish';
  static const String _injectKey = 'openzclick.inject';
  static const String _positionPrefix = 'openzclick.position.';

  @override
  Future<SettingsSnapshot?> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? profile = prefs.getString(_profileKey);
    if (profile == null) return null;

    final Map<Action, List<double>> positions = <Action, List<double>>{};
    for (final Action action in Action.values) {
      final String? raw = prefs.getString('$_positionPrefix${action.name}');
      if (raw == null) continue;
      final List<String> parts = raw.split(',');
      if (parts.length != 2) continue;
      final double? x = double.tryParse(parts[0]);
      final double? y = double.tryParse(parts[1]);
      if (x == null || y == null) continue;
      positions[action] = <double>[x, y];
    }

    return SettingsSnapshot(
      profileId: profile,
      gearIndex: prefs.getInt(_gearKey) ?? 0,
      positions: positions,
      publishOnStart: prefs.getBool(_publishKey) ?? false,
      injectOnStart: prefs.getBool(_injectKey) ?? false,
    );
  }

  @override
  Future<void> save(SettingsSnapshot snapshot) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, snapshot.profileId);
    await prefs.setInt(_gearKey, snapshot.gearIndex);
    await prefs.setBool(_publishKey, snapshot.publishOnStart);
    await prefs.setBool(_injectKey, snapshot.injectOnStart);
    for (final MapEntry<Action, List<double>> entry
        in snapshot.positions.entries) {
      await prefs.setString(
        '$_positionPrefix${entry.key.name}',
        '${entry.value[0]},${entry.value[1]}',
      );
    }
  }
}

/// Store kept in memory, used by the tests and by hosts without storage.
class MemorySettingsStore implements SettingsStore {
  /// Creates an empty store.
  MemorySettingsStore();

  SettingsSnapshot? _snapshot;

  /// Number of writes, so that a test can check that a change was persisted.
  int writes = 0;

  @override
  Future<SettingsSnapshot?> load() async => _snapshot;

  @override
  Future<void> save(SettingsSnapshot snapshot) async {
    _snapshot = snapshot;
    writes += 1;
  }
}

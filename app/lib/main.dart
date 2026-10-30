import 'dart:async';

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:openzclick_core/openzclick_core.dart';

import 'ble/controller_connection.dart';
import 'net/android_injection.dart';
import 'net/network_publisher.dart';
import 'settings/settings_store.dart';
import 'state/app_state.dart';

void main() => runApp(const OpenZclickApp());

/// Application root: dark theme, four sections.
class OpenZclickApp extends StatefulWidget {
  /// Creates the application.
  const OpenZclickApp({super.key});

  @override
  State<OpenZclickApp> createState() => _OpenZclickAppState();
}

class _OpenZclickAppState extends State<OpenZclickApp> {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    unawaited(_state.restore(PrefsSettingsStore()));
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'openzclick',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F6FED),
          brightness: Brightness.dark,
        ),
      ),
      home: HomeShell(state: _state),
    );
  }
}

/// Navigation shell holding the four sections.
class HomeShell extends StatefulWidget {
  /// Creates the shell for [state].
  const HomeShell({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<String> _titles = <String>[
    'Trainer',
    'Controllers',
    'Target',
    'Diagnostics',
  ];

  @override
  Widget build(BuildContext context) {
    final AppState state = widget.state;
    final List<Widget> pages = <Widget>[
      TrainerScreen(state: state),
      ControllersScreen(state: state),
      TargetScreen(state: state),
      DiagnosticsScreen(state: state),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) => setState(() => _index = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.fitness_center),
            label: 'Trainer',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_esports),
            label: 'Controllers',
          ),
          NavigationDestination(icon: Icon(Icons.lan), label: 'Target'),
          NavigationDestination(
            icon: Icon(Icons.terminal),
            label: 'Diagnostics',
          ),
        ],
      ),
    );
  }
}

/// Trainer section: gear state and resistance preview.
class TrainerScreen extends StatelessWidget {
  /// Creates the screen for [state].
  const TrainerScreen({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) {
        final GearEngine engine = state.engine;
        final double resistance = engine.targetResistance(
          gradePercent: 4,
          riderWeightKg: 72,
          speedKmh: 28,
        );
        final bool erg = engine.mode == RidingMode.erg;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _MetricCard(
              label: 'Gear',
              value: '${engine.gearNumber} / ${engine.gearCount}',
              hint: null,
              below: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: engine.profile.id,
                  isDense: true,
                  style: Theme.of(context).textTheme.bodySmall,
                  onChanged: (String? id) {
                    if (id != null) state.setProfile(id);
                  },
                  items: <DropdownMenuItem<String>>[
                    for (final GearProfile profile in GearProfile.builtin)
                      DropdownMenuItem<String>(
                        value: profile.id,
                        child: Text(profile.label),
                      ),
                  ],
                ),
              ),
            ),
            _MetricCard(
              label: 'Ratio',
              value: engine.currentRatio.ratio.toStringAsFixed(2),
              hint: engine.bigChainringActive
                  ? 'big chainring'
                  : 'small chainring',
            ),
            _MetricCard(
              label: 'Mode',
              value: erg ? 'ERG' : 'SIM',
              hint: erg
                  ? '${engine.ergTargetWatts} W target'
                  : '4 % grade at 28 km/h',
            ),
            if (!erg)
              _MetricCard(
                label: 'Resistance',
                value: '${resistance.toStringAsFixed(0)} W',
                hint: 'simulated power at this gear',
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: state.shiftUp,
                  icon: const Icon(Icons.add),
                  label: const Text('Shift up'),
                ),
                FilledButton.icon(
                  onPressed: state.shiftDown,
                  icon: const Icon(Icons.remove),
                  label: const Text('Shift down'),
                ),
                OutlinedButton(
                  onPressed: state.toggleChainring,
                  child: const Text('Chainring'),
                ),
                OutlinedButton(
                  onPressed: state.toggleMode,
                  child: const Text('Mode'),
                ),
                OutlinedButton(
                  onPressed: () => state.bumpErg(5),
                  child: const Text('+5 W'),
                ),
                OutlinedButton(
                  onPressed: () => state.bumpErg(-5),
                  child: const Text('-5 W'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Controllers section: Bluetooth discovery and connection.
class ControllersScreen extends StatelessWidget {
  /// Creates the screen for [state].
  const ControllersScreen({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) {
        final ControllerConnection link = state.controller;
        final bool busy =
            link.status == ControllerStatus.scanning ||
            link.status == ControllerStatus.connecting;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Card(
              child: ListTile(
                leading: Icon(
                  link.status == ControllerStatus.ready
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth,
                ),
                title: Text('Controller: ${link.status.name}'),
                subtitle: Text(
                  link.error ??
                      (link.status == ControllerStatus.ready
                          ? '${link.encrypted ? 'encrypted' : 'plain'} session'
                                '${link.batteryPercent == null ? '' : ' - battery ${link.batteryPercent} %'}'
                          : 'Two-button Bluetooth controller'),
                ),
                trailing: link.status == ControllerStatus.ready
                    ? TextButton(
                        onPressed: link.disconnect,
                        child: const Text('Disconnect'),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: busy ? null : link.scan,
              icon: const Icon(Icons.search),
              label: const Text('Scan for controllers'),
            ),
            const SizedBox(height: 8),
            for (final ScanResult result in link.found)
              ListTile(
                leading: const Icon(Icons.videogame_asset),
                title: Text(
                  result.device.platformName.isEmpty
                      ? result.device.remoteId.toString()
                      : result.device.platformName,
                ),
                subtitle: Text(result.device.remoteId.toString()),
                trailing: TextButton(
                  onPressed: busy ? null : () => link.connect(result.device),
                  child: const Text('Connect'),
                ),
              ),
            const Divider(height: 32),
            Text('Last buttons: ${state.lastButtons ?? 'none'}'),
            const SizedBox(height: 8),
            const Text(
              'Declarative definitions shipped with the core are listed in the '
              'Target tab. The controller link above is the live input path.',
            ),
          ],
        );
      },
    );
  }
}

/// Target section: network publication and the outgoing protocol.
class TargetScreen extends StatelessWidget {
  /// Creates the screen for [state].
  const TargetScreen({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) {
        final NetworkPublisher publisher = state.publisher;
        final List<MapEntry<int, Action>> entries =
            state.keymap.bindings.entries.toList()..sort(
              (MapEntry<int, Action> a, MapEntry<int, Action> b) =>
                  a.key.compareTo(b.key),
            );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Card(
              child: SwitchListTile(
                title: const Text('Publish on the network'),
                subtitle: Text(
                  publisher.error ??
                      (publisher.running
                          ? '${publisher.address ?? 'this device'}:${publisher.listeningPort}'
                                ' - ${publisher.peers} client(s)'
                                '${publisher.advertise ? ' - announced over mDNS' : ' - enter this address in the application'}'
                          : publisher.advertise
                          ? 'Announces the bridge over mDNS and accepts TCP'
                          : 'Accepts TCP on port ${publisher.port}, without mDNS'),
                ),
                value: publisher.running,
                onChanged: (_) => state.togglePublishing(),
              ),
            ),
            Card(
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    title: const Text('Tap the application controls'),
                    subtitle: Text(
                      state.injection.error ??
                          (state.injection.running
                              ? 'Taps are injected at the configured positions'
                              : 'For applications that only accept taps'),
                    ),
                    value: state.injection.running,
                    onChanged: state.injection.supported
                        ? (_) => state.toggleInjection()
                        : null,
                  ),
                  if (state.injection.running)
                    for (final Action action in <Action>[
                      Action.shiftUp,
                      Action.shiftDown,
                      Action.steerLeft,
                      Action.steerRight,
                    ])
                      ListTile(
                        dense: true,
                        title: Text(action.label),
                        trailing: Text(
                          state.injection.usesKeys
                              ? state.injection.keys![action] ?? '-'
                              : '${(state.injection.positions[action]![0] * 100).round()} %'
                                    ' / ${(state.injection.positions[action]![1] * 100).round()} %',
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        onTap: state.injection.usesKeys
                            ? null
                            : () => _editPosition(context, state, action),
                      ),
                  if (state.injection.supported)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextButton.icon(
                        onPressed: AndroidInjection.openSettings,
                        icon: const Icon(Icons.accessibility_new, size: 18),
                        label: const Text('Open accessibility settings'),
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              dense: true,
              title: const Text('Last action'),
              trailing: Text(state.lastAction.label),
            ),
            const Divider(height: 24),
            const Text('Send a direction'),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => state.sendDirection(Action.steerLeft),
                    child: const Text('Left'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => state.sendDirection(Action.steerRight),
                    child: const Text('Right'),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            const Text('Button mapping'),
            const SizedBox(height: 8),
            for (final MapEntry<int, Action> entry in entries)
              ListTile(
                dense: true,
                leading: Text(
                  '0x${entry.key.toRadixString(16).padLeft(2, '0')}',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                title: Text(entry.value.label),
              ),
          ],
        );
      },
    );
  }
}

/// Asks for the relative position of [action] and stores it.
Future<void> _editPosition(
  BuildContext context,
  AppState state,
  Action action,
) async {
  double x = state.injection.positions[action]![0];
  double y = state.injection.positions[action]![1];

  await showDialog<void>(
    context: context,
    builder: (BuildContext context) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) => AlertDialog(
        title: Text(action.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Horizontal ${(x * 100).round()} %'),
            Slider(
              value: x,
              onChanged: (double value) => setState(() => x = value),
            ),
            Text('Vertical ${(y * 100).round()} %'),
            Slider(
              value: y,
              onChanged: (double value) => setState(() => y = value),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              state.injection.setPosition(action, x, y);
              await state.injection.test(action);
            },
            child: const Text('Test'),
          ),
          FilledButton(
            onPressed: () {
              state.injection.setPosition(action, x, y);
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Diagnostics section: codec test bench and build facts.
class DiagnosticsScreen extends StatelessWidget {
  /// Creates the screen for [state].
  const DiagnosticsScreen({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FilledButton(
            onPressed: state.runCodecBench,
            child: const Text('Run codec test bench'),
          ),
          const SizedBox(height: 12),
          _MonoBlock(label: 'Encoded frame', value: state.lastFrame),
          _MonoBlock(label: 'Decoded back', value: state.lastDecoded),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.hint,
    this.below,
  });

  final String label;
  final String value;
  final String? hint;

  /// Optional control displayed under the value.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(label),
        subtitle: hint == null ? null : Text(hint!),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            ?below,
          ],
        ),
      ),
    );
  }
}

class _MonoBlock extends StatelessWidget {
  const _MonoBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(
            value.isEmpty ? '-' : value,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

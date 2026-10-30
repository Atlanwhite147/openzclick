import 'package:flutter/material.dart' hide Action;
import 'package:openzclick_core/openzclick_core.dart';

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
      const ControllersScreen(),
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
          NavigationDestination(icon: Icon(Icons.terminal), label: 'Diagnostics'),
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
              hint: engine.profile.label,
            ),
            _MetricCard(
              label: 'Ratio',
              value: engine.currentRatio.ratio.toStringAsFixed(2),
              hint: engine.bigChainringActive ? 'big chainring' : 'small chainring',
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
            const SizedBox(height: 12),
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

/// Controllers section: built-in device definitions.
class ControllersScreen extends StatelessWidget {
  /// Creates the screen.
  const ControllersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<DeviceDefinition> devices = DeviceRegistry.builtin;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: devices.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Declarative definitions shipped with the core. The BLE input '
              'backend is not wired yet: pairing arrives in milestone M1.',
            ),
          );
        }
        final DeviceDefinition device = devices[index - 1];
        return ListTile(
          leading: const Icon(Icons.videogame_asset),
          title: Text(device.name),
          subtitle: Text(
            '${device.id} - ${device.manufacturer} - '
            '${device.serviceUuids.length} service(s)',
          ),
        );
      },
    );
  }
}

/// Target section: keymap and the outgoing protocol.
class TargetScreen extends StatelessWidget {
  /// Creates the screen for [state].
  const TargetScreen({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final List<MapEntry<int, Action>> entries =
        state.keymap.bindings.entries.toList()
          ..sort(
            (MapEntry<int, Action> a, MapEntry<int, Action> b) =>
                a.key.compareTo(b.key),
          );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text(
          'Network transport is implemented in the transports package. '
          'Advertising stays off until you start it explicitly.',
        ),
        const SizedBox(height: 12),
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
  }
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
  const _MetricCard({required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(label),
        subtitle: hint == null ? null : Text(hint!),
        trailing: Text(value, style: Theme.of(context).textTheme.titleLarge),
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

import 'dart:async';

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'ble/controller_connection.dart';
import 'net/android_injection.dart';
import 'net/console_endpoint.dart';
import 'net/publisher.dart';
import 'platform/capabilities.dart';
import 'settings/settings_store.dart';
import 'state/app_state.dart';
import 'ui/mywhoosh_guide.dart';
import 'ui/parked_gear_card.dart';

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
    unawaited(_start());
  }

  /// Restores the settings, then dials the bridge a QR code pointed at.
  ///
  /// A scanned code opens the page with `?bridge=…&code=…`: nothing is typed, and
  /// the console connects before the rider sees the screen.
  Future<void> _start() async {
    await _state.restore(PrefsSettingsStore());
    final ({String host, String code})? target = ConsoleEndpoint.fromQuery(
      Uri.base.queryParameters,
    );
    if (target == null) return;
    await _state.connectConsole(target.host, target.code);
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
    'MyWhoosh',
    'Gears',
    'Controllers',
    'Network',
    'Diagnostics',
  ];

  @override
  Widget build(BuildContext context) {
    final AppState state = widget.state;
    final List<Widget> pages = <Widget>[
      MyWhooshGuideScreen(state: state),
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
          NavigationDestination(icon: Icon(Icons.play_circle), label: 'Start'),
          NavigationDestination(
            icon: Icon(Icons.fitness_center),
            label: 'Gears',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_esports),
            label: 'Controllers',
          ),
          NavigationDestination(icon: Icon(Icons.lan), label: 'Network'),
          NavigationDestination(
            icon: Icon(Icons.terminal),
            label: 'Diagnostics',
          ),
        ],
      ),
    );
  }
}

/// Landing screen: the four steps of a first ride, in order.
class MyWhooshGuideScreen extends StatelessWidget {
  /// Creates the screen for [state].
  const MyWhooshGuideScreen({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        MyWhooshGuideCard(state: state),
        const SizedBox(height: 8),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Not using MyWhoosh?',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                Text(
                  'Every training application that implements OpenBikeControl '
                  'works the same way: TrainingPeaks Virtual, Strappo, '
                  'icTrainer, Velotoss, Biketerra and Ride Cave. The other tabs '
                  'drive any application that only accepts taps or keys.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
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
            ParkedGearCard(state: state),
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
                  // Silence after the handshake is the one failure that no
                  // reconnection fixes: say what the rider must do instead of
                  // showing a connection that looks alive.
                  link.needsUnlock
                      ? 'No answer after the handshake: pair the controller '
                            'once in its official application, then reconnect'
                      : link.error ??
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
              'Network tab. The controller link above is the live input path.',
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
        final PublisherPort publisher = state.publisher;
        final List<MapEntry<int, Action>> entries =
            state.keymap.bindings.entries.toList()..sort(
              (MapEntry<int, Action> a, MapEntry<int, Action> b) =>
                  a.key.compareTo(b.key),
            );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (Capabilities.canPublish)
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
              )
            else
              const Card(
                child: ListTile(
                  leading: Icon(Icons.lan_outlined),
                  title: Text('Publish on the network: impossible here'),
                  subtitle: Text(
                    'A browser cannot open a listening socket or announce a '
                    'service, so a training application cannot discover this '
                    'page. Pairing the controller, the gears and the diagnostics '
                    'work; the console below drives the bridge running on your '
                    'network, and the bridge is what the application sees.',
                  ),
                ),
              ),
            // A page that owns sockets *is* the bridge: it has no relay to show.
            // A native host serves one, and a plain page dials one.
            if (Capabilities.isWeb && Capabilities.canPublish)
              const SizedBox.shrink()
            else if (Capabilities.canPublish)
              _BridgeConsoleCard(state: state)
            else
              _ConsoleClientCard(state: state),
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

/// Public address of the web edition, the one a QR code opens.
///
/// Hardcoded on purpose: a bridge has no way to discover the published page, and
/// a rider scanning a code must land on a page that exists.
const String webAppUrl = 'https://atlanwhite147.github.io/openzclick/';

/// Card of a native bridge: where a browser console has to dial.
///
/// The relay only exists while the publication runs, so the card reads the
/// publisher state and says what to do when nothing listens yet. A QR code saves
/// typing the address and the code on a phone: the page opens already connected.
class _BridgeConsoleCard extends StatelessWidget {
  const _BridgeConsoleCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) {
        final PublisherPort publisher = state.publisher;
        final String host = publisher.address ?? 'this-device';
        final int? consolePort = publisher.consolePort;
        final String code = publisher.consoleToken;
        final bool ready = consolePort != null && code.isNotEmpty;
        final String? link = ready
            ? ConsoleEndpoint.pageLink(
                page: webAppUrl,
                host: host,
                port: consolePort,
                code: code,
              )
            : null;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      publisher.consoles > 0
                          ? Icons.cast_connected
                          : Icons.cast,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Browser console',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (ready)
                      Text(code, style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  ready
                      ? 'Scan this code with a phone: the page opens and drives '
                            'this bridge. Or enter $host:$consolePort and '
                            'the code by hand.'
                      : 'Start the publication to let a browser drive this bridge',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (link != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Center(
                    child: QrImageView(
                      data: link,
                      size: 168,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    link,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ],
                if (publisher.consoles > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${publisher.consoles} console(s) connected',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Card of the browser build: dial the bridge running on the network.
///
/// This is the only route that works on an iPhone, where no browser exposes Web
/// Bluetooth: the buttons of this page reach the bridge over a WebSocket, and the
/// bridge publishes them to the training application.
class _ConsoleClientCard extends StatefulWidget {
  const _ConsoleClientCard({required this.state});

  final AppState state;

  @override
  State<_ConsoleClientCard> createState() => _ConsoleClientCardState();
}

class _ConsoleClientCardState extends State<_ConsoleClientCard> {
  final TextEditingController _host = TextEditingController();
  final TextEditingController _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _host.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    await widget.state.connectConsole(_host.text, _code.text);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    await widget.state.disconnectConsole();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ConsoleClient? client = widget.state.consoleClient;
    if (client == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: widget.state,
      builder: (BuildContext context, _) {
        final bool connected = client.consoleConnected;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      connected ? Icons.cast_connected : Icons.cast,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        connected
                            ? 'Console connected'
                            : 'Drive a bridge from this page',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  client.consoleError ??
                      (connected
                          ? client.consoleAddress ?? ''
                          : 'Start the publication in openzclick on the machine '
                                'where your training application runs, then '
                                'enter the address it displays.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!connected) ...<Widget>[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _host,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Bridge address',
                      hintText: '192.168.1.24',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _code,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Code shown by the bridge',
                      hintText: 'abcd',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _connect,
                    icon: const Icon(Icons.link),
                    label: const Text('Connect'),
                  ),
                ] else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy ? null : _disconnect,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                    ),
                  ),
              ],
            ),
          ),
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

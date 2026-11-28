import 'package:flutter/material.dart' hide Action;
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:openzclick_core/openzclick_core.dart';

import '../../ble/controller_connection.dart';
import '../../state/app_state.dart';
import '../design.dart';
import '../report_bug_button.dart';
import '../../platform/version.dart';

class ControllersScreen extends StatelessWidget {
  /// Creates the screen for [state].
  const ControllersScreen({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  /// What the state machine means in words a rider uses.
  ///
  /// `idle`, `scanning` and `ready` are names from the code; a novice reading
  /// "Controller: idle" has no way to know whether that is good or bad.
  static String _statusLabel(ControllerStatus status) => switch (status) {
    ControllerStatus.idle => 'Not connected yet',
    ControllerStatus.scanning => 'Looking for controllers...',
    ControllerStatus.connecting => 'Connecting...',
    ControllerStatus.ready => 'Connected',
    ControllerStatus.failed => 'Connection failed',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) {
        final ControllerConnection link = state.controller;
        final bool ready = link.status == ControllerStatus.ready;
        final bool busy =
            link.status == ControllerStatus.scanning ||
            link.status == ControllerStatus.connecting;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Card(
              child: ListTile(
                leading: Icon(
                  ready ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: ready ? Colors.green : null,
                ),
                title: Text(_statusLabel(link.status)),
                subtitle: Text(
                  // Silence after the handshake is the one failure that no
                  // reconnection fixes: say what the rider must do instead of
                  // showing a connection that looks alive.
                  link.needsUnlock
                      ? 'The controller connected but answers nothing. This is '
                            'the known Click v2 behaviour: pair it once in the '
                            'Zwift application, keep that application open '
                            'about three minutes, then come back here.'
                      : link.needsZwiftRefresh
                      ? 'The link dropped a few seconds after it came up. A '
                            'Click v2 asks Zwift for a fresh encryption '
                            'context about once a day, and stops sending '
                            'buttons when it lapses. Open the Zwift '
                            'application once, keep the controller connected '
                            'about thirty seconds, then come back: this window '
                            'reconnects on its own.'
                      : link.error ??
                            (ready
                                ? '${link.encrypted ? 'encrypted' : 'plain'} session'
                                      '${link.batteryPercent == null ? '' : ' - battery ${link.batteryPercent} %'}'
                                : 'Zwift Click or two-button Bluetooth '
                                      'controller, paired with the buttons below'),
                ),
                trailing: ready
                    ? TextButton(
                        onPressed: link.disconnect,
                        child: const Text('Disconnect'),
                      )
                    : null,
              ),
            ),
            if (state.batteryWarning != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: Icon(
                    Icons.battery_alert,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  title: Text(
                    state.batteryWarning!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: busy ? null : link.scan,
              icon: const Icon(Icons.search),
              label: Text(busy ? 'Looking...' : 'Scan for controllers'),
            ),
            const SizedBox(height: 8),
            if (link.found.isEmpty && !busy && !ready)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Press a button on the controller first: its light blinks for '
                  'about thirty seconds, and a scan only sees it while it '
                  'blinks. Then tap Scan.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (link.scanFoundNothing && !busy && !ready)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Nothing answered. The controller sleeps after a few seconds: '
                  'press a button again and scan once more. A Click v2 that was '
                  'never paired in Zwift stays silent until it has been.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
            for (final ScanResult result in link.found)
              ListTile(
                leading: const Icon(Icons.videogame_asset),
                title: Text(
                  result.device.platformName.isEmpty
                      ? result.device.remoteId.toString()
                      : result.device.platformName,
                ),
                // Two pods of a pair announce the same name, and only the left
                // one is locked to Zwift: the side is what tells a rider which
                // pod they are about to pair, and it comes from the
                // manufacturer data rather than from the label.
                subtitle: Text(
                  '${result.device.remoteId}\n'
                  '${controllerSideLabel(controllerSideFromAdvertisement(result.advertisementData.manufacturerData))}',
                ),
                trailing: TextButton(
                  onPressed: busy ? null : () => link.connect(result.device),
                  child: const Text('Connect'),
                ),
              ),
            const Divider(height: 32),
            Text('Last buttons: ${state.lastButtons ?? 'none'}'),
            const SizedBox(height: 10),
            // The pod's own colours, named: a rider holding the thing can tell
            // which button the application calls what, and the palette stops
            // being decoration.
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ButtonSwatch(
                  label: '+',
                  color: Tokens.orange,
                  meaning: 'harder',
                ),
                ButtonSwatch(label: 'B', color: Tokens.rose, meaning: 'easier'),
                ButtonSwatch(label: 'Y', color: Tokens.blue, meaning: 'top'),
                ButtonSwatch(label: 'A', color: Tokens.green, meaning: 'right'),
              ],
            ),
            // Asked for by the one person who could close the loop: the bridge
            // is written on a machine with no radio, so a dropout can only be
            // diagnosed from what a rider's device actually exposes. A
            // description of a dropout gets skimmed; a pasted blob gets read.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final String report = state.controller
                      .buildReport(appVersion)
                      .render();
                  await Clipboard.setData(ClipboardData(text: report));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Device report copied: paste it into a GitHub issue',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Copy device report'),
              ),
            ),
            // The same report, one press further: the issue page opens with it
            // filled in. Next to the copy button because they are the same
            // object, one for a thread and one for the tracker.
            Align(
              alignment: Alignment.centerLeft,
              child: ReportBugButton(state: state),
            ),
            const SizedBox(height: 4),
            Text(
              // Measured on the hardware, one button at a time: these two are
              // wired to the gears, the other three of the pod are not.
              'On a Click v2, the + button shifts up and B shifts down.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!ready) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'First time with a Zwift Click?',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'A Click v2 stays silent until it has been paired once in the '
                'Zwift application, and it drops again if that pairing is cut '
                'short. Pair it there, leave it open about three minutes, then '
                'come back. The v1 has no such step.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
    );
  }
}

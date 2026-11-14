import 'package:flutter/material.dart' hide Action;

import '../../net/publisher.dart';
import '../../platform/capabilities.dart';
import '../../state/app_state.dart';
import '../console_cards.dart';

import 'package:openzclick_core/openzclick_core.dart';

import '../../net/key_profiles.dart';
import '../../net/android_injection.dart';

class TargetScreen extends StatelessWidget {
  /// Creates the screen for [state].
  ///
  /// [onOpenGuide] goes back to the start screen, the only place that explains
  /// in order what to do; the card for a browser links to it rather than
  /// repeating four steps in the middle of a technical screen.
  const TargetScreen({required this.state, this.onOpenGuide, super.key});

  /// Shared application state.
  final AppState state;

  /// Jumps to the start screen, `null` when the host has no tab bar.
  final VoidCallback? onOpenGuide;

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
              Card(
                child: Column(
                  children: <Widget>[
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('This page cannot be found by MyWhoosh'),
                      subtitle: Text(
                        'A browser cannot listen on the network, so MyWhoosh '
                        'cannot discover it. Run the openzclick application on '
                        'a computer or an Android phone: it is the bridge, and '
                        'this page then drives it.',
                      ),
                    ),
                    if (onOpenGuide != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextButton.icon(
                          onPressed: onOpenGuide,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Show me the steps'),
                        ),
                      ),
                  ],
                ),
              ),
            // A page that owns sockets *is* the bridge: it has no relay to show.
            // A native host serves one, and a plain page dials one.
            if (Capabilities.isWeb && Capabilities.canPublish)
              const SizedBox.shrink()
            else if (Capabilities.canPublish)
              BridgeConsoleCard(state: state)
            else
              ConsoleClientCard(state: state),
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
                  if (state.injection.usesKeys)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Row(
                        children: <Widget>[
                          const Text('Application'),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: state.keyProfile.id,
                              items: <DropdownMenuItem<String>>[
                                for (final KeyProfile profile
                                    in builtInKeyProfiles)
                                  DropdownMenuItem<String>(
                                    value: profile.id,
                                    child: Text(profile.label),
                                  ),
                              ],
                              onChanged: (String? id) {
                                if (id != null) state.setKeyProfile(id);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Text('x'),
                          const SizedBox(width: 8),
                          DropdownButton<int>(
                            value: state.shiftsPerPress,
                            items: <DropdownMenuItem<int>>[
                              for (final int n in <int>[1, 2, 3])
                                DropdownMenuItem<int>(
                                  value: n,
                                  child: Text('$n'),
                                ),
                            ],
                            onChanged: (int? n) {
                              if (n != null) state.setShiftsPerPress(n);
                            },
                          ),
                        ],
                      ),
                    ),
                  if (state.injection.usesKeys)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          state.keyProfile.source.isEmpty
                              ? 'Gears on k and i, steering on the arrows.'
                              : 'From ${state.keyProfile.source}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  if (state.injection.usesKeys)
                    ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      childrenPadding: EdgeInsets.zero,
                      title: const Text('Adjust the keys'),
                      subtitle: Text(
                        state.hasKeyOverrides
                            ? 'Changed for ${state.keyProfile.label}'
                            : 'The shipped table, editable. Press Enter to '
                                  'apply a key.',
                      ),
                      children: <Widget>[
                        for (final Action action in <Action>[
                          Action.shiftUp,
                          Action.shiftDown,
                          Action.steerLeft,
                          Action.steerRight,
                        ])
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: TextFormField(
                              // The profile and the key are part of the identity:
                              // switching application must rebuild the field
                              // instead of keeping the previous text.
                              key: ValueKey<String>(
                                '${state.keyProfile.id}.${action.name}.'
                                '${state.effectiveKeys[action] ?? ''}',
                              ),
                              initialValue: state.effectiveKeys[action] ?? '',
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: action.label,
                                helperText:
                                    'Empty restores the shipped key for this '
                                    'application.',
                              ),
                              onFieldSubmitted: (String value) =>
                                  state.setKey(action, value),
                            ),
                          ),
                      ],
                    ),
                  if (state.injection.usesKeys)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: TextFormField(
                        initialValue: state.injection.focusWindow,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Type into this window only',
                          helperText:
                              'A fragment of the window title, MyWhoosh for '
                              'instance. Empty: the key goes to whichever '
                              'window has the focus.',
                        ),
                        onChanged: state.setFocusWindow,
                      ),
                    ),
                  if (state.injection.supported && !state.injection.usesKeys)
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
            const Divider(height: 24),
            // Kept, but folded away: this proves the codec works and is of no
            // use to a rider, so it must not be a fifth tab beside the gear.
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Protocol test bench'),
              subtitle: const Text(
                'Checks that a frame survives an encode and '
                'a decode',
              ),
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    onPressed: state.runCodecBench,
                    child: const Text('Run the test'),
                  ),
                ),
                const SizedBox(height: 12),
                MonoBlock(label: 'Encoded frame', value: state.lastFrame),
                MonoBlock(label: 'Decoded back', value: state.lastDecoded),
              ],
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

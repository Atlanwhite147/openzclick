/// The material a rider touches once, or never: how the bridge talks to an
/// application that does not speak the protocol, and a bench that proves the
/// codec still works.
///
/// Everything here used to sit inside the Network screen, between the switch
/// that starts the bridge and the list of buttons. A rider who came to start
/// the bridge had to scroll past tap positions and key tables to reach the one
/// thing that screen is for. The bridge stays on Network; the rest lives here,
/// one tab further away, and nothing was removed: hiding it was the point.
library;

import 'package:flutter/material.dart' hide Action;
import 'package:openzclick_core/openzclick_core.dart';

import '../../net/android_injection.dart';
import '../../net/key_profiles.dart';
import '../../state/app_state.dart';
import '../console_cards.dart';

/// Tap injection, key injection and the protocol test bench.
class AdvancedScreen extends StatelessWidget {
  /// Creates the screen for [state].
  const AdvancedScreen({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _InjectionCard(state: state),
          _ProtocolBench(state: state),
        ],
      ),
    );
  }
}

/// Keyboard or tap injection, the profile of the application being driven, and
/// the positions or keys each action lands on.
class _InjectionCard extends StatelessWidget {
  const _InjectionCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Card(
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
                        for (final KeyProfile profile in builtInKeyProfiles)
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
                        DropdownMenuItem<int>(value: n, child: Text('$n')),
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
                    : 'The shipped table, editable. Press Enter to apply a '
                          'key.',
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
                      'instance. Empty: the key goes to whichever window has '
                      'the focus.',
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
    );
  }
}

/// The codec bench, folded away.
///
/// Kept, and deliberately not deleted: it proves a frame survives an encode and
/// a decode, and that is the first thing to check when the pod goes quiet. It is
/// of no use to a rider, so it is not on any screen they cross while riding.
class _ProtocolBench extends StatelessWidget {
  const _ProtocolBench({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: const Text('Protocol test bench'),
        subtitle: const Text(
          'Checks that a frame survives an encode and a decode',
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
    );
  }
}

/// Dialog that sets where an action taps, in percent of the screen.
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

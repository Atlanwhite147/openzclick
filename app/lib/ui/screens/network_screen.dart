import 'package:flutter/material.dart' hide Action;

import '../../net/publisher.dart';
import '../../platform/capabilities.dart';
import '../../state/app_state.dart';
import '../console_cards.dart';

import 'package:openzclick_core/openzclick_core.dart';

/// The bridge: whether it publishes, what it announces, and what it last sent.
///
/// Tap injection, key tables and the codec bench used to sit here, between the
/// switch and the button list. They are settings a rider touches once, if ever,
/// and they pushed the one thing this screen exists for out of reach: they now
/// live on the Advanced screen.
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
            // The bridge serves its console itself; a host that cannot publish
            // is iOS without Apple's entitlement, and shows nothing here.
            if (Capabilities.canPublish)
              BridgeConsoleCard(state: state)
            else
              const SizedBox.shrink(),
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

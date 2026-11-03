import 'package:flutter/material.dart';

import '../net/publisher_port.dart';
import '../platform/capabilities.dart';
import '../state/app_state.dart';
import 'parked_gear_card.dart';

/// First thing a rider sees: what to do with MyWhoosh, in order.
///
/// The application used to assume the documentation had been read: a switch
/// labelled "Publish on the network" on a tab of its own, and no indication of
/// what to do inside the training application. This card states the four steps
/// and marks the two the application can observe, so someone who has never
/// installed anything can finish without leaving the screen.
class MyWhooshGuideCard extends StatelessWidget {
  /// Creates the guide for [state].
  ///
  /// [onOpenNetwork] jumps to the Network tab, `null` when the card is shown
  /// without a tab bar.
  const MyWhooshGuideCard({required this.state, this.onOpenNetwork, super.key});

  /// Shared application state.
  final AppState state;

  /// Jumps to the Network tab where a browser connects to a bridge.
  final VoidCallback? onOpenNetwork;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) {
        final PublisherPort publisher = state.publisher;
        if (!Capabilities.canPublish) {
          return _GuideElsewhere(state: state, onOpenNetwork: onOpenNetwork);
        }
        final bool running = publisher.running;
        final bool connected = publisher.peers > 0;
        final String? address = publisher.address;
        final int? port = publisher.listeningPort;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      connected ? Icons.check_circle : Icons.wifi_tethering,
                      color: connected ? Colors.green : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        connected
                            ? 'MyWhoosh is connected'
                            : 'Ride with MyWhoosh',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!state.physicalSetup.isComplete) ...<Widget>[
                  _ParkedGearNotice(state: state),
                ],
                _Step(
                  number: 1,
                  done: running,
                  title: 'Start the bridge',
                  detail: running
                      ? (publisher.advertise
                            ? 'Announced on your network as "openzclick".'
                            : 'Listening on ${address ?? 'this device'}:${port ?? publisher.port}.')
                      : 'It listens for MyWhoosh and sends it your shifts.',
                  action: running
                      ? null
                      : FilledButton(
                          onPressed: state.togglePublishing,
                          child: const Text('Start'),
                        ),
                ),
                if (publisher.error != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 40, bottom: 8),
                    child: Text(
                      publisher.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const _Step(
                  number: 2,
                  done: false,
                  title: 'Open MyWhoosh',
                  detail:
                      'On this machine or another one on the same Wi-Fi, '
                      'then open the device connection screen.',
                ),
                const _Step(
                  number: 3,
                  done: false,
                  title: 'Tap the OpenBikeControl icon, top right',
                  detail:
                      'MyWhoosh asks for confirmation: answer Yes. '
                      'The icon turns blue when the link is up.',
                ),
                _Step(
                  number: 4,
                  done: connected,
                  title: 'Ride',
                  detail: connected
                      ? 'Your two buttons now shift, and this screen follows.'
                      : 'Once connected, pressing a button here changes the '
                            'gear in MyWhoosh too.',
                ),
                if (running && !publisher.advertise && port != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SelectableText(
                      '${address ?? 'this device'}:$port',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                const Divider(height: 24),
                const _Troubleshooting(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The one setting that moves every gear, said before anything else.
///
/// A rider who starts riding with this unanswered finds the ride harder than
/// the gear number says and concludes the gears are broken. It appears on both
/// the bridge screen and the browser screen, because the browser build never
/// reaches the four steps and would otherwise never mention it.
class _ParkedGearNotice extends StatelessWidget {
  const _ParkedGearNotice({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.pedal_bike_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Before you start: leave the chain on a middle cog and set it '
                  'here. The gears are scaled from where the chain really is.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          // The box used to name the Gears tab and stop there, which sends a
          // novice hunting for a tab in the middle of a first-time setup.
          // Answering here removes the hop.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => askParkedGear(context, state),
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Answer now'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One numbered step, ticked when the application can observe it.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.done,
    required this.title,
    required this.detail,
    this.action,
  });

  final int number;
  final bool done;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 12,
            backgroundColor: done
                ? Colors.green
                : colors.surfaceContainerHighest,
            child: done
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text(
                    '$number',
                    style: TextStyle(fontSize: 12, color: colors.onSurface),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
                if (action != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: action,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What is left when the steps do not work, stated instead of hidden.
class _Troubleshooting extends StatelessWidget {
  const _Troubleshooting();

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: const Text('MyWhoosh does not find it'),
      children: <Widget>[
        for (final String line in const <String>[
          'Check both are on the same Wi-Fi, not one on Ethernet and the other '
              'on a guest network: MyWhoosh looks for the bridge with mDNS, '
              'which does not cross subnets.',
          'On Windows, MyWhoosh needs Bonjour (installed with iTunes or the '
              'Bonjour Print Services). Without it, mDNS discovery silently '
              'returns nothing.',
          'MyWhoosh on Android does not accept this connection over Wi-Fi; '
              'reported by several riders, so use a PC, a tablet on another '
              'platform, or MyWhoosh on Apple TV.',
          'A firewall asking about this application must be allowed on the '
              'private network, on the port shown above.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('•  '),
                Expanded(
                  child: Text(
                    line,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A plain page is not the bridge: say where the bridge has to run.
class _GuideElsewhere extends StatelessWidget {
  const _GuideElsewhere({required this.state, this.onOpenNetwork});

  final AppState state;
  final VoidCallback? onOpenNetwork;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.info_outline),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ride with MyWhoosh',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'MyWhoosh needs the openzclick application running on a computer '
              'or an Android phone: that application is the bridge it '
              'discovers. This page then drives that bridge from here, which is '
              'the only route that works on an iPhone.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Install openzclick where MyWhoosh runs, and press Start there.'
              '\n2. It shows a code. Scan it, or type the address it displays.',
              style: TextStyle(fontSize: 13),
            ),
            if (onOpenNetwork != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.icon(
                  onPressed: onOpenNetwork,
                  icon: const Icon(Icons.link),
                  label: const Text('Connect to my bridge'),
                ),
              ),
            if (!state.physicalSetup.isComplete)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _ParkedGearNotice(state: state),
              ),
            const SizedBox(height: 8),
            const Text(
              'Chrome on a computer can also run this page as an installed '
              'application, and start the bridge by itself.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

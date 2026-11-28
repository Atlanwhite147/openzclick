import 'package:flutter/material.dart' hide Action;
import 'package:qr_flutter/qr_flutter.dart';

import '../net/console_endpoint.dart';
import '../net/publisher.dart';
import '../state/app_state.dart';

class BridgeConsoleCard extends StatelessWidget {
  const BridgeConsoleCard({required this.state, super.key});

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
            ? ConsoleEndpoint.bridgePage(
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
                        'Phone console',
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
                      ? 'Scan this with a phone: the page opens here and drives '
                            'this bridge, no application to install. Or type '
                            '$host:$consolePort in any browser and enter the '
                            'code.'
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

/// Asks for the relative position of [action] and stores it.

class MonoBlock extends StatelessWidget {
  const MonoBlock({required this.label, required this.value, super.key});

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

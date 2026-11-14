import 'package:flutter/material.dart' hide Action;
import 'package:qr_flutter/qr_flutter.dart';

import '../net/console_endpoint.dart';
import '../net/publisher.dart';
import '../platform/capabilities.dart';
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

/// Card of the browser build: dial the bridge running on the network.
///
/// This is the only route that works on an iPhone, where no browser exposes Web
/// Bluetooth: the buttons of this page reach the bridge over a WebSocket, and the
/// bridge publishes them to the training application.
class ConsoleClientCard extends StatefulWidget {
  const ConsoleClientCard({required this.state, super.key});

  final AppState state;

  @override
  State<ConsoleClientCard> createState() => ConsoleClientCardState();
}

class ConsoleClientCardState extends State<ConsoleClientCard> {
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
                if (!connected && !Capabilities.canDialBridge) ...<Widget>[
                  // This page is served over https, and a browser refuses to
                  // open a ws:// socket from one. Nothing typed here can work,
                  // and the refusal used to be reported as a wrong code.
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This page is served over https, and a browser will '
                            'not let it reach a bridge on your network. Open the '
                            'address the bridge shows instead, which starts '
                            'with http://.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (!connected) ...<Widget>[
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

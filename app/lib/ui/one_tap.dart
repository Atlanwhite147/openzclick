/// One button, for the page.
///
/// The browser edition had the same shape as the native one: a guide, four tabs,
/// a controller screen, a network screen. On a page that is three screens of
/// configuration before a rider can turn a pedal, and every one of them exists
/// because the *native* host has choices to offer. A page has none: it either
/// came from a bridge — in which case it knows the address — or it cannot reach
/// one at all.
///
/// So the page gets one button. It asks the browser for a controller, dials the
/// bridge it was served by, and says in one sentence what stopped it if
/// something did. The tabs stay reachable underneath, folded away, because a
/// rider debugging a link still needs them.
library;

import 'package:flutter/material.dart';

import '../ble/controller_connection.dart';
import '../state/app_state.dart';
import 'design.dart';

/// The page's single action.
class OneTapRide extends StatefulWidget {
  /// Creates the card for [state].
  const OneTapRide({required this.state, this.onOpenDetails, super.key});

  /// Shared application state.
  final AppState state;

  /// Opens the tabs, for a rider who has to look at something.
  final VoidCallback? onOpenDetails;

  @override
  State<OneTapRide> createState() => _OneTapRideState();
}

class _OneTapRideState extends State<OneTapRide> {
  bool _busy = false;
  String? _message;

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final String? failure = await widget.state.startRiding();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (BuildContext context, Widget? _) {
        final AppState state = widget.state;
        final bool pod = state.controller.status == ControllerStatus.ready;
        final bool riding = pod && state.publisher.running;

        return Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Ride', style: Type.section(context)),
              const SizedBox(height: 10),
              Text(
                riding
                    ? 'Your buttons are live. MyWhoosh can shift.'
                    : 'One button: it takes the pod, finds the bridge this page '
                          'came from, and starts.',
                style: Theme.of(context).textTheme.bodyLarge!
                    .copyWith(color: Tokens.muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy || riding ? null : _start,
                  icon: Icon(
                    riding
                        ? Icons.check_circle
                        : _busy
                        ? Icons.hourglass_top
                        : Icons.play_arrow,
                  ),
                  label: Text(
                    riding
                        ? 'Riding'
                        : _busy
                        ? 'Starting...'
                        : 'Start riding',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Lamp(
                    on: pod,
                    label: pod ? 'Pod connected' : 'Pod not connected',
                  ),
                  const SizedBox(width: 16),
                  Lamp(
                    on: state.publisher.running,
                    label: state.publisher.running
                        ? 'Bridge linked'
                        : 'No bridge',
                    color: Tokens.blue,
                  ),
                ],
              ),
              if (_message != null) ...<Widget>[
                const SizedBox(height: 14),
                Text(
                  _message!,
                  style: Theme.of(context).textTheme.bodyMedium!
                      .copyWith(color: Tokens.rose, height: 1.4),
                ),
              ],
              if (widget.onOpenDetails != null) ...<Widget>[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: widget.onOpenDetails,
                    child: const Text('Everything else'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

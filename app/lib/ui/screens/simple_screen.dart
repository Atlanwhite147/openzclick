/// The whole simple interface: one screen, one button, one sentence of state.
///
/// A rider who is not a programmer wants three answers from this application,
/// in this order: is my controller awake, is MyWhoosh listening, and what do I
/// press. Everything else — the ladder, the ratio, the mode, the tap positions,
/// the bench — is a setting for a person who debugs a link, and lives behind the
/// Advanced switch.
///
/// The button is the only control whose label changes with the state, because
/// there is always exactly one thing left to do: pair, start, or nothing. A
/// screen of greyed out controls with a short sentence next to them is what this
/// screen replaces.
library;

import 'package:flutter/material.dart' hide Action;

import '../../ble/controller_connection.dart';
import '../../state/app_state.dart';
import '../design.dart';

/// Pair, start, ride, with the practical notes folded away.
class SimpleScreen extends StatelessWidget {
  /// Creates the screen for [state].
  const SimpleScreen({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  /// True while the pod is being looked for or connected to.
  static bool _busy(ControllerConnection link) =>
      link.status == ControllerStatus.scanning ||
      link.status == ControllerStatus.connecting;

  /// What the rider sees when the pod is silent after connecting.
  ///
  /// Kept verbatim from the Controllers screen: a Click v2 that answers nothing
  /// is the one failure no reconnection fixes, and it is worth the paragraph.
  static const String _clickHint =
      'The controller connected but answers nothing. Pair it once in the Zwift '
      'application, keep that application open about three minutes, then come '
      'back here.';

  /// Looks for a controller, and says what went wrong when nothing answered.
  static Future<void> _pair(BuildContext context, AppState state) async {
    final ControllerConnection link = state.controller;
    await link.scanAndConnect();
    if (!context.mounted) return;
    if (link.status == ControllerStatus.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            link.error ??
                'No controller answered. Press a button on the pod, then try '
                    'again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, Widget? _) {
        final ControllerConnection link = state.controller;
        final bool paired = link.status == ControllerStatus.ready;
        final bool bridge = state.publisher.running;
        final bool live = paired && bridge;
        final bool busy = _busy(link);
        final String? problem = state.publisher.error ?? link.error;
        final int? battery = link.batteryPercent;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            // One sentence, not four lamps: the rider only needs the first line
            // that is not true yet.
            Text(
              _headline(live: live, bridge: bridge, paired: paired),
              style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                color: Tokens.text,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _detail(live: live, bridge: bridge, paired: paired, busy: busy),
            ),
            if (problem != null && !live) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                problem,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: Tokens.alarm),
              ),
            ],
            if (link.needsUnlock) ...<Widget>[
              const SizedBox(height: 10),
              Text(_clickHint),
            ],
            const SizedBox(height: 22),
            // The one action. Its label says what the press will do, so a rider
            // never has to work out which state they are in first.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => _act(context, state, live, paired),
                icon: Icon(
                  live
                      ? Icons.check_circle
                      : busy
                      ? Icons.hourglass_top
                      : paired || bridge
                      ? Icons.play_arrow
                      : Icons.bluetooth_searching,
                ),
                label: Text(
                  live
                      ? 'Riding'
                      : busy
                      ? 'Connecting...'
                      : paired
                      ? 'Start riding'
                      : 'Pair controller',
                ),
              ),
            ),
            if (battery != null && paired) ...<Widget>[
              const SizedBox(height: 12),
              Lamp(
                on: true,
                label: 'Controller battery $battery %',
                color: battery <= 20 ? Tokens.alarm : Tokens.good,
              ),
            ],
            const SizedBox(height: 24),
            const Card(
              child: ListTile(
                leading: Icon(Icons.sensors),
                title: Text('Press + on the pod to wake it'),
                subtitle: Text(
                  'The pod sleeps after a minute. Its light blinks for about '
                  'thirty seconds: that is when it can be paired.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('How to ride with MyWhoosh'),
              children: <Widget>[
                const SizedBox(height: 4),
                const _Note('Start the bridge here, then open MyWhoosh.'),
                const _Note(
                  'Tap the OpenBikeControl icon in MyWhoosh, top right, and '
                  'answer Yes to the question.',
                ),
                const _Note(
                  'Wait for the line above to say MyWhoosh connected.',
                ),
                const _Note('Ride: the + button shifts up, B shifts down.'),
                const SizedBox(height: 4),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Nothing connects?'),
              children: <Widget>[
                const SizedBox(height: 4),
                const _Note(
                  'Press a button on the pod, then tap Pair controller again.',
                ),
                const _Note(
                  'Check that MyWhoosh is on the same Wi-Fi, not on a guest '
                  'network.',
                ),
                const _Note(
                  'On a phone, MyWhoosh does not accept this connection over '
                  'Wi-Fi: use MyWhoosh on a computer.',
                ),
                const SizedBox(height: 4),
              ],
            ),
          ],
        );
      },
    );
  }

  /// The one line that answers "can I ride".
  static String _headline({
    required bool live,
    required bool bridge,
    required bool paired,
  }) {
    if (live) return 'MyWhoosh connected';
    if (paired) return 'Waiting for MyWhoosh';
    if (bridge) return 'Controller not paired';
    return 'Ready when you are';
  }

  /// The line under it, saying what is left to do.
  static String _detail({
    required bool live,
    required bool bridge,
    required bool paired,
    required bool busy,
  }) {
    if (live) return 'Your two buttons shift. Ride.';
    if (paired) {
      return 'MyWhoosh is not listening yet. Tap Start riding to open the '
          'bridge, then connect MyWhoosh.';
    }
    if (bridge) {
      return 'MyWhoosh is listening. Tap Pair controller, then press a button '
          'on the pod.';
    }
    return 'Pair your controller, then start riding. It takes one press.';
  }

  /// Runs the single action the state leaves open.
  static Future<void> _act(
    BuildContext context,
    AppState state,
    bool live,
    bool paired,
  ) async {
    // Already riding: the press is a no-op rather than a stop. A rider reaching
    // for this button mid-ride means "is it still working", not "disconnect".
    if (live) return;
    if (!paired) {
      await _pair(context, state);
      return;
    }
    if (!state.publisher.running) await state.togglePublishing();
  }
}

/// One practical line, in the rider's words.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('•  '),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

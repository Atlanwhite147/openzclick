import 'package:flutter/material.dart' hide Action;

import '../../state/app_state.dart';
import '../mywhoosh_guide.dart';
import '../one_tap.dart';
import '../../platform/capabilities.dart';

class MyWhooshGuideScreen extends StatelessWidget {
  /// Creates the screen for [state].
  ///
  /// [onOpenNetwork] jumps to the Network tab, where a browser connects to a
  /// bridge. Without it the web build only describes what to do somewhere else
  /// and leaves the rider to find it.
  const MyWhooshGuideScreen({
    required this.state,
    this.onOpenNetwork,
    super.key,
  });

  /// Shared application state.
  final AppState state;

  /// Jumps to the Network tab, `null` when the host has no tab bar.
  final VoidCallback? onOpenNetwork;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // A page gets one button and nothing else in front of it: it either came
        // from a bridge, in which case it knows the address, or it cannot reach
        // one at all. The four steps stay, folded, for the rider who has to
        // debug something.
        if (Capabilities.isWeb) ...<Widget>[
          OneTapRide(state: state),
          const SizedBox(height: 4),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('The four steps'),
            children: <Widget>[
              MyWhooshGuideCard(state: state, onOpenNetwork: onOpenNetwork),
            ],
          ),
        ] else
          MyWhooshGuideCard(state: state, onOpenNetwork: onOpenNetwork),
        const SizedBox(height: 8),
        // The guide is shown once, so it has to be findable again: a rider who
        // skipped it to ride, then came back a week later, has no other door.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: state.replayOnboarding,
            icon: const Icon(Icons.replay, size: 18),
            label: const Text('Show the first-start guide again'),
          ),
        ),
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

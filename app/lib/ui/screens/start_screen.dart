import 'package:flutter/material.dart' hide Action;

import '../../state/app_state.dart';
import '../mywhoosh_guide.dart';

class MyWhooshGuideScreen extends StatelessWidget {
  /// Creates the screen for [state].
  ///
  /// [onOpenNetwork] jumps to the Network tab, where the bridge is started.
  /// Without it the guide only describes the steps and leaves the rider to find
  /// them.
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

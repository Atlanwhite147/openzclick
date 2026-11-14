import 'package:flutter/material.dart' hide Action;

import '../../state/app_state.dart';
import '../gear_panel.dart';
import '../parked_gear_card.dart';

class TrainerScreen extends StatelessWidget {
  /// Creates the screen for [state].
  const TrainerScreen({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          ParkedGearCard(state: state),
          GearPanel(state: state),
        ],
      ),
    );
  }
}

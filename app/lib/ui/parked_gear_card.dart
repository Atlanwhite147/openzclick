/// The question the rider answers once, and the wheel size that follows from it.
///
/// Everything the bridge does to a trainer is one number: the wheel size it
/// tells the machine to work from per gear. That number is built from the gear
/// on screen and from the gear the bike is physically left in, so this card asks
/// the second one. Skipping it does not fail loudly: the ladder simply moves,
/// by up to a factor of two, and the rider concludes the ride is hard.
library;

import 'package:flutter/material.dart';
import 'package:openzclick_core/openzclick_core.dart';

import '../state/app_state.dart';

/// Asks where the chain sits, and shows the wheel size that follows.
class ParkedGearCard extends StatelessWidget {
  /// Creates the card for [state].
  const ParkedGearCard({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) {
        final ThemeData theme = Theme.of(context);
        final PhysicalSetup setup = state.physicalSetup;
        final ParkedGear? parked = setup.parkedGear;
        final ParkedGear? recommended = state.recommendedParkedGear;
        final double? circumference = state.currentWheelCircumference;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      parked == null
                          ? Icons.pedal_bike_outlined
                          : Icons.check_circle,
                      color: parked == null
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        parked == null
                            ? 'Where is your chain?'
                            : 'Chain on ${parked.name}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  parked == null
                      ? 'Look down at your bike: which chainring and which cog '
                            'is the chain on? Leave it there for the whole ride '
                            'and shift with the controller instead.'
                      : 'The gears on screen are scaled from this. If the ride '
                            'feels much harder or easier than the gear number '
                            'suggests, this is the setting to change.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _ToothPicker(
                      label: 'Chainring',
                      options: setup.chainringTeeth,
                      value: setup.parkedChainringTeeth,
                      onChanged: (int? teeth) {
                        if (teeth == null) return;
                        state.setParkedGear(
                          chainring: teeth,
                          cog: setup.parkedCogTeeth ?? setup.cogTeeth.first,
                        );
                      },
                    ),
                    _ToothPicker(
                      label: 'Cog',
                      options: setup.cogTeeth,
                      value: setup.parkedCogTeeth,
                      onChanged: (int? teeth) {
                        if (teeth == null) return;
                        state.setParkedGear(
                          chainring:
                              setup.parkedChainringTeeth ??
                              setup.chainringTeeth.first,
                          cog: teeth,
                        );
                      },
                    ),
                  ],
                ),
                if (recommended != null && recommended != parked) ...<Widget>[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => state.setParkedGear(
                        chainring: recommended.chainringTeeth,
                        cog: recommended.cogTeeth,
                      ),
                      icon: const Icon(Icons.volume_off),
                      label: Text('Quietest: ${recommended.name}'),
                    ),
                  ),
                ],
                if (circumference != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Trainer wheel size right now: '
                    '${circumference.toStringAsFixed(1)} mm',
                    style: theme.textTheme.bodySmall,
                  ),
                ] else if (parked != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'This gear cannot be built from ${parked.name}: try the '
                    'quietest setting, or move the chain.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A small dropdown of tooth counts.
class _ToothPicker extends StatelessWidget {
  const _ToothPicker({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<int> options;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    // Copied before sorting: `options` comes from an immutable setup, and a
    // cascade on a conditional would sort it in place.
    final int? selected = value;
    final List<int> items = <int>[
      ...options,
      if (selected != null && !options.contains(selected)) selected,
    ]..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: value,
            hint: const Text('choose'),
            isDense: true,
            onChanged: onChanged,
            items: <DropdownMenuItem<int>>[
              for (final int teeth in items)
                DropdownMenuItem<int>(value: teeth, child: Text('$teeth T')),
            ],
          ),
        ),
      ],
    );
  }
}

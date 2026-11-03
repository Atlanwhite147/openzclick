/// The question the rider answers once, and the wheel size that follows from it.
///
/// Everything the bridge does to a trainer is one number: the wheel size it
/// tells the machine to work from per gear. That number is built from the gear
/// on screen and from the gear the bike is physically left in, so this asks the
/// second one. Skipping it does not fail loudly: the ladder simply moves, by up
/// to a factor of two, and the rider concludes the ride is hard.
///
/// The question is loud while it is unanswered and collapses to one line once
/// answered, because it is answered once per bike and never again. A card that
/// keeps the same size forever makes the most-changed control on the screen (the
/// shift buttons) scroll off a phone.
library;

import 'package:flutter/material.dart';
import 'package:openzclick_core/openzclick_core.dart';

import '../state/app_state.dart';

/// Asks where the chain sits, and shows the wheel size that follows.
class ParkedGearCard extends StatefulWidget {
  /// Creates the card for [state].
  const ParkedGearCard({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  @override
  State<ParkedGearCard> createState() => _ParkedGearCardState();
}

class _ParkedGearCardState extends State<ParkedGearCard> {
  /// True once the rider asked to change an already recorded answer.
  bool _reopened = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (BuildContext context, _) {
        final PhysicalSetup setup = widget.state.physicalSetup;
        final ParkedGear? parked = setup.parkedGear;
        // Answered and untouched: one line is enough.
        if (parked != null && !_reopened) {
          return _AnsweredLine(
            parked: parked,
            wheelMillimeters: widget.state.currentWheelCircumference,
            onChange: () => setState(() => _reopened = true),
          );
        }
        return _Question(
          state: widget.state,
          onDone: () => setState(() => _reopened = false),
        );
      },
    );
  }
}

/// One line stating what the bridge scales from, with a way back in.
class _AnsweredLine extends StatelessWidget {
  const _AnsweredLine({
    required this.parked,
    required this.wheelMillimeters,
    required this.onChange,
  });

  final ParkedGear parked;
  final double? wheelMillimeters;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double? wheel = wheelMillimeters;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.pedal_bike_outlined),
        title: Text('Chain on ${parked.name}'),
        subtitle: Text(
          wheel == null
              ? 'This gear cannot be built from ${parked.name}'
              : 'Gears scaled from this, wheel ${wheel.toStringAsFixed(0)} mm',
          style: wheel == null
              ? theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                )
              : theme.textTheme.bodySmall,
        ),
        trailing: TextButton(onPressed: onChange, child: const Text('Change')),
      ),
    );
  }
}

/// The full question, with the two pickers and the recommendation.
class _Question extends StatelessWidget {
  const _Question({required this.state, required this.onDone});

  final AppState state;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[ParkedGearPickers(state: state, onDone: onDone)],
        ),
      ),
    );
  }
}

/// Icon, question, two tooth pickers and the recommendation.
///
/// Shared between the Gears screen and the dialog the guide opens, so a rider
/// who lands on the start screen can answer without hunting for the right tab.
///
/// A half answer is held here rather than dropped: a rider who picks the
/// chainring first would otherwise see nothing happen, since the wheel size
/// cannot be built until both counts are known.
class ParkedGearPickers extends StatefulWidget {
  /// Creates the pickers for [state].
  const ParkedGearPickers({required this.state, this.onDone, super.key});

  /// Shared application state.
  final AppState state;

  /// Called after an answer is recorded, `null` when the pickers stay visible.
  final VoidCallback? onDone;

  @override
  State<ParkedGearPickers> createState() => _ParkedGearPickersState();
}

class _ParkedGearPickersState extends State<ParkedGearPickers> {
  int? _chainring;
  int? _cog;

  @override
  void initState() {
    super.initState();
    _chainring = widget.state.physicalSetup.parkedChainringTeeth;
    _cog = widget.state.physicalSetup.parkedCogTeeth;
  }

  /// Records the pair as soon as both halves are known.
  void _set({int? chainring, int? cog}) {
    setState(() {
      if (chainring != null) _chainring = chainring;
      if (cog != null) _cog = cog;
    });
    final int? ring = _chainring;
    final int? rear = _cog;
    if (ring == null || rear == null) return;
    widget.state.setParkedGear(chainring: ring, cog: rear);
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (BuildContext context, _) {
        final ThemeData theme = Theme.of(context);
        final PhysicalSetup setup = widget.state.physicalSetup;
        final ParkedGear? parked = setup.parkedGear;
        final ParkedGear? recommended = widget.state.recommendedParkedGear;
        final double? circumference = widget.state.currentWheelCircumference;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  parked == null
                      ? Icons.pedal_bike_outlined
                      : Icons.check_circle,
                  color: parked == null
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    parked == null
                        ? 'Where is your chain? (optional)'
                        : 'Chain on ${parked.name}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              parked == null
                  ? 'Look down at your bike: which chainring and which cog is '
                        'the chain on? Answering is only useful if the ride feels '
                        'too hard or too easy for the gear shown; MyWhoosh does '
                        'the shifting itself.'
                  : 'The gears on screen are scaled from this. If the ride feels '
                        'much harder or easier than the gear number suggests, '
                        'this is the setting to change.',
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
                  value: _chainring,
                  onChanged: (int? teeth) => _set(chainring: teeth),
                ),
                _ToothPicker(
                  label: 'Cog',
                  options: setup.cogTeeth,
                  value: _cog,
                  onChanged: (int? teeth) => _set(cog: teeth),
                ),
              ],
            ),
            if (recommended != null && recommended != parked) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _set(
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
        );
      },
    );
  }
}

/// Asks the parked-gear question in a dialog, from wherever the rider is.
///
/// Returns true when an answer was recorded. Used by the start screen, so the
/// warning there leads somewhere instead of pointing at another tab.
Future<bool> askParkedGear(BuildContext context, AppState state) async {
  if (state.physicalSetup.isComplete) return false;
  final bool? answered = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      // A rider who opened this by mistake has to be able to leave: answering
      // is one tap away, but being stuck in a dialog is not obvious to undo.
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Later'),
        ),
      ],
      content: SizedBox(
        width: 380,
        child: ParkedGearPickers(
          state: state,
          onDone: () => Navigator.of(context).pop(true),
        ),
      ),
    ),
  );
  return answered ?? false;
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

/// The two things a rider comes to this screen for: read the gear, change it.
///
/// The screen used to show six buttons of equal weight. Two of them are pressed
/// while riding; the other four are settings touched once and then never again,
/// and sitting beside the shift buttons they made the screen look like a control
/// panel for engineers. The readout and the two shift buttons are now the whole
/// first row, and the settings live behind one expander.
///
/// The shift buttons are disabled at the ends of the ladder instead of silently
/// doing nothing: a dead press reads as a broken application when the truth is
/// simply that the largest gear is engaged.
library;

import 'package:flutter/material.dart' hide Action;
import 'package:openzclick_core/openzclick_core.dart';

import '../state/app_state.dart';

/// Gear readout, the two shift buttons, and the settings behind them.
class GearPanel extends StatelessWidget {
  /// Creates the panel for [state].
  const GearPanel({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) {
        final ThemeData theme = Theme.of(context);
        final GearEngine engine = state.engine;
        final bool erg = engine.mode == RidingMode.erg;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Gear', style: theme.textTheme.labelMedium),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      '${engine.gearNumber}',
                      key: const Key('gear-number'),
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '/ ${engine.gearCount}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    _ModeBadge(erg: erg, ergWatts: engine.ergTargetWatts),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _ShiftButton(
                        label: 'Shift up',
                        icon: Icons.keyboard_arrow_up,
                        onPressed: engine.atHighest ? null : state.shiftUp,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ShiftButton(
                        label: 'Shift down',
                        icon: Icons.keyboard_arrow_down,
                        onPressed: engine.atLowest ? null : state.shiftDown,
                      ),
                    ),
                  ],
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('Gear set and riding mode'),
                  children: <Widget>[
                    _SettingRow(
                      label: 'Gear set',
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: engine.profile.id,
                          isDense: true,
                          style: theme.textTheme.bodyMedium,
                          onChanged: (String? id) {
                            if (id != null) state.setProfile(id);
                          },
                          items: <DropdownMenuItem<String>>[
                            for (final GearProfile profile
                                in GearProfile.builtin)
                              DropdownMenuItem<String>(
                                value: profile.id,
                                child: Text(profile.label),
                              ),
                          ],
                        ),
                      ),
                    ),
                    _SettingRow(
                      label: 'Ratio',
                      child: Text(
                        engine.currentRatio.ratio.toStringAsFixed(2),
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    _SettingRow(
                      label: 'Chainring',
                      child: Text(
                        engine.bigChainringActive ? 'big' : 'small',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    _SettingRow(
                      label: 'Mode',
                      child: Text(
                        erg ? 'ERG' : 'SIM',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    if (erg)
                      _SettingRow(
                        label: 'Target power',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '${engine.ergTargetWatts} W',
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                            IconButton(
                              onPressed: () => state.bumpErg(-5),
                              icon: const Icon(Icons.remove),
                              tooltip: '5 W less',
                            ),
                            IconButton(
                              onPressed: () => state.bumpErg(5),
                              icon: const Icon(Icons.add),
                              tooltip: '5 W more',
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        OutlinedButton(
                          onPressed: state.toggleChainring,
                          child: const Text('Change chainring'),
                        ),
                        OutlinedButton(
                          onPressed: state.toggleMode,
                          child: Text(erg ? 'Switch to SIM' : 'Switch to ERG'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Tall button, because it is pressed while riding and looked at for a moment.
class _ShiftButton extends StatelessWidget {
  const _ShiftButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(72),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[Icon(icon, size: 28), Text(label)],
      ),
    );
  }
}

/// Which mode the ladder is in, readable without opening anything.
class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.erg, required this.ergWatts});

  final bool erg;
  final int ergWatts;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        erg ? 'ERG $ergWatts W' : 'SIM',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

/// One labelled line inside the settings expander.
class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          child,
        ],
      ),
    );
  }
}

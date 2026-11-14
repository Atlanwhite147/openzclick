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
import 'design.dart';

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

        return Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text('Gear', style: Type.section(context))),
                  _ModeBadge(erg: erg, ergWatts: engine.ergTargetWatts),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    '${engine.gearNumber}',
                    key: const Key('gear-number'),
                    style: Type.readout(context),
                  ),
                  const SizedBox(width: 8),
                  Text('/ ${engine.gearCount}', style: Type.unit(context)),
                ],
              ),
              const SizedBox(height: 14),
              GearLadder(gear: engine.gearNumber, count: engine.gearCount),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Paddle(
                      label: 'Shift up',
                      icon: Icons.keyboard_arrow_up,
                      color: Tokens.orange,
                      onPressed: engine.atHighest ? null : state.shiftUp,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Paddle(
                      label: 'Shift down',
                      icon: Icons.keyboard_arrow_down,
                      color: Tokens.rose,
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
                          for (final GearProfile profile in GearProfile.builtin)
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
        );
      },
    );
  }
}

/// Tall button, because it is pressed while riding and looked at for a moment.
class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.erg, required this.ergWatts});

  final bool erg;
  final int ergWatts;

  @override
  Widget build(BuildContext context) {
    // The pod's top button is blue, and blue is this application's word for
    // information: which mode the ride is in, and what it targets.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Tokens.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        erg ? 'ERG $ergWatts W' : 'SIM',
        style: Theme.of(context).textTheme.labelMedium!
            .copyWith(color: Tokens.blue, fontWeight: FontWeight.w700),
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

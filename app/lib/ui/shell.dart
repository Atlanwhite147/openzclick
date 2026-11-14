import 'package:flutter/material.dart' hide Action;

import '../platform/capabilities.dart';
import '../state/app_state.dart';
import 'design.dart';
import 'onboarding.dart';
import 'screens/controllers_screen.dart';
import 'screens/gears_screen.dart';
import 'screens/network_screen.dart';
import 'screens/start_screen.dart';

class HomeShell extends StatefulWidget {
  /// Creates the shell for [state].
  const HomeShell({required this.state, super.key});

  /// Shared application state.
  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // Four destinations, not five. The test bench is a developer's tool: it sat
  // in the navigation bar next to the buttons a rider presses every ride, and
  // that alone made the application look like something to configure. It now
  // lives at the bottom of the Network tab, where the rest of the technical
  // material already was.
  static const List<String> _titles = <String>[
    'Start',
    'Gears',
    'Controllers',
    'Network',
  ];

  @override
  Widget build(BuildContext context) {
    final AppState state = widget.state;
    final List<Widget> pages = <Widget>[
      MyWhooshGuideScreen(
        state: state,
        onOpenNetwork: () => setState(() => _index = 3),
      ),
      TrainerScreen(state: state),
      ControllersScreen(state: state),
      TargetScreen(state: state, onOpenGuide: () => setState(() => _index = 0)),
    ];

    // The first-start guide takes the whole screen, once. It is not an overlay on
    // top of a half-configured application: a rider meeting the tabs before
    // knowing the order reads them as a settings app.
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, Widget? _) {
        if (!state.onboardingDone) {
          return OnboardingScreen(
            onDone: state.completeOnboarding,
            onOpenTab: (int tab) {
              // Going to the screen is answering the step: the guide closes and
              // the rider can bring it back from the first screen.
              state.completeOnboarding();
              setState(() => _index = tab);
            },
          );
        }
        return _shell(state, pages);
      },
    );
  }

  Widget _shell(AppState state, List<Widget> pages) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: <Widget>[
          _ReadinessChip(
            state: state,
            // The lamp states a problem; a rider should not have to guess which
            // tab fixes it. Tapping it goes there.
            onGoTo: (int tab) => setState(() => _index = tab),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) => setState(() => _index = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.play_circle), label: 'Start'),
          NavigationDestination(
            icon: Icon(Icons.fitness_center),
            label: 'Gears',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_esports),
            label: 'Controllers',
          ),
          NavigationDestination(icon: Icon(Icons.lan), label: 'Network'),
        ],
      ),
    );
  }
}

/// One word telling the rider whether the ride will work, on every screen.
///
/// Without this the answer to "why is nothing happening" lives on a tab the
/// rider has to guess.
///
/// The parked gear is deliberately not part of the verdict. On the route a
/// rider actually rides today, MyWhoosh does its own virtual shifting and the
/// bridge only forwards buttons, so a rider who has never seen the chain
/// question still shifts perfectly. Counting it here would leave them on "Not
/// ready" while everything worked, which is worse than saying nothing.
class _ReadinessChip extends StatelessWidget {
  const _ReadinessChip({required this.state, required this.onGoTo});

  final AppState state;

  /// Opens the section that would clear the lamp.
  final void Function(int tab) onGoTo;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) {
        final bool bridge = state.publisher.running;
        // Only load-bearing where the bridge drives the trainer itself; see
        // [Capabilities.drivesTrainerItself].
        final bool chain =
            !Capabilities.drivesTrainerItself || state.physicalSetup.isComplete;
        final bool ready = bridge && chain;
        final String label = ready
            ? 'Ready'
            : bridge
            ? 'Waiting for the chain'
            : 'Not ready';
        // The lamp is the one thing a rider reads before starting, so it is also
        // the shortest path to the fix: the bridge is started from Network, the
        // chain answered from Gears.
        final Widget lamp = Lamp(
          on: ready,
          color: ready ? Tokens.good : Tokens.alarm,
          label: label,
        );
        return Padding(
          padding: const EdgeInsets.only(right: 16),
          // A lamp, not a chip: this is a state, and a chip reads like a label
          // or a filter next to the tabs. It says the one thing a rider needs
          // before starting, in the same vocabulary on every screen.
          child: ready
              ? lamp
              : Tooltip(
                  message: bridge
                      ? 'Tap to answer the chain question'
                      : 'Tap to start the bridge',
                  child: InkWell(
                    onTap: () => onGoTo(bridge ? 1 : 3),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: lamp,
                    ),
                  ),
                ),
        );
      },
    );
  }
}

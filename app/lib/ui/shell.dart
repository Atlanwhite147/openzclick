import 'package:flutter/material.dart' hide Action;

import '../platform/capabilities.dart';
import '../settings/display_mode.dart';
import '../state/app_state.dart';
import 'design.dart';
import 'onboarding.dart';
import 'screens/advanced_screen.dart';
import 'screens/controllers_screen.dart';
import 'screens/gears_screen.dart';
import 'screens/network_screen.dart';
import 'screens/simple_screen.dart';
import 'screens/start_screen.dart';

/// The frame around every screen, and the switch between the two interfaces.
///
/// One application, two audiences. A rider who is not a programmer wants one
/// screen: pair, start, read the state, and a few practical notes. A rider who
/// debugs a link wants the ladder, the key tables and the bench. The old answer
/// was a tab bar where the settings outnumbered the ride, which made the whole
/// thing read as an application to configure; the choice is now explicit, in the
/// top bar, and remembered.
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

  // The five destinations of the advanced interface. The test bench is a
  // developer's tool: it sat in the navigation bar next to the buttons a rider
  // presses every ride, and that alone made the application look like something
  // to configure. It now lives on the Advanced tab, with the other things
  // touched once and never again.
  static const List<String> _titles = <String>[
    'Start',
    'Gears',
    'Controllers',
    'Network',
    'Advanced',
  ];

  @override
  Widget build(BuildContext context) {
    final AppState state = widget.state;

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
        return state.advanced ? _advanced(state) : _simple(state);
      },
    );
  }

  /// One screen, no tabs, the switch in the top bar.
  Widget _simple(AppState state) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('openzclick'),
        actions: <Widget>[
          _ModeSelector(
            mode: state.displayMode,
            onChanged: state.setDisplayMode,
          ),
        ],
      ),
      body: SimpleScreen(state: state),
    );
  }

  /// The full interface, unchanged, with the switch in the same place.
  Widget _advanced(AppState state) {
    // Clamped: the rider may have narrowed the bar from the simple screen while
    // this index pointed past the end of nothing.
    final int index = _index.clamp(0, _titles.length - 1);
    final List<Widget> pages = <Widget>[
      MyWhooshGuideScreen(
        state: state,
        onOpenNetwork: () => setState(() => _index = 3),
      ),
      TrainerScreen(state: state),
      ControllersScreen(state: state),
      TargetScreen(state: state, onOpenGuide: () => setState(() => _index = 0)),
      AdvancedScreen(state: state),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[index]),
        actions: <Widget>[
          _ReadinessChip(
            state: state,
            // The lamp states a problem; a rider should not have to guess which
            // tab fixes it. Tapping it goes there.
            onGoTo: (int tab) => setState(() => _index = tab),
          ),
          _ModeSelector(
            mode: state.displayMode,
            onChanged: state.setDisplayMode,
          ),
        ],
      ),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
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
          NavigationDestination(icon: Icon(Icons.tune), label: 'Advanced'),
        ],
      ),
    );
  }
}

/// The Simple / Advanced switch, in the top bar of both interfaces.
///
/// Deliberately not an icon: an icon asks a rider to know what it hides, and the
/// whole point of this switch is that the choice is explicit. Two words, the
/// active one on the raised background, the same place on every screen.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final DisplayMode mode;
  final void Function(DisplayMode) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SegmentedButton<DisplayMode>(
        key: const Key('display-mode'),
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStatePropertyAll<TextStyle>(
            Theme.of(context).textTheme.labelMedium!
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        segments: const <ButtonSegment<DisplayMode>>[
          ButtonSegment<DisplayMode>(
            value: DisplayMode.simple,
            label: Text('Simple'),
          ),
          ButtonSegment<DisplayMode>(
            value: DisplayMode.advanced,
            label: Text('Advanced'),
          ),
        ],
        selected: <DisplayMode>{mode},
        onSelectionChanged: (Set<DisplayMode> selection) =>
            onChanged(selection.first),
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
          padding: const EdgeInsets.only(right: 8),
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

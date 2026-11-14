/// The first-start guide: four steps, in the order a first ride actually goes.
///
/// It exists because the application asks for things in a specific order — a pod
/// pressed, a publication switched on, a popup confirmed in another application —
/// and a rider who meets those out of order sees a screen that looks broken. Each
/// step therefore says one thing, and offers to take the rider to the screen where
/// that thing happens.
///
/// It is shown once. A rider who skips it is not asked again on every launch, and
/// the first screen can bring it back.
library;

import 'package:flutter/material.dart';

import 'design.dart';

/// One step of the guide.
class OnboardingStep {
  /// Builds a step.
  const OnboardingStep({
    required this.title,
    required this.body,
    this.action,
    this.tab,
  });

  /// What to do, in the rider's words.
  final String title;

  /// Why, and what will happen.
  final String body;

  /// Label of the button that goes to [tab], if any.
  final String? action;

  /// Section the button opens.
  final int? tab;
}

/// The steps, in order.
const List<OnboardingStep> onboardingSteps = <OnboardingStep>[
  OnboardingStep(
    title: 'Wake the pod and connect it',
    body:
        'Press the + button on the right pod, then open Controllers and tap '
        'Connect. The list names the pod it found: the left one only works after '
        'a pairing in Zwift, the right one needs nothing.',
    action: 'Open Controllers',
    tab: 2,
  ),
  OnboardingStep(
    title: 'Announce the buttons on the network',
    body:
        'In Network, switch the publication on. The application becomes a '
        'controller that training apps can find on your Wi-Fi, under the name '
        'openzclick.',
    action: 'Open Network',
    tab: 3,
  ),
  OnboardingStep(
    title: 'Point MyWhoosh at it',
    body:
        'In MyWhoosh, open the connection screen and tap the OpenBikeControl '
        'icon in the top right. Answer Yes to the popup: without that answer '
        'MyWhoosh ignores every controller, which is its own rule.',
  ),
  OnboardingStep(
    title: 'Ride',
    body:
        'The two paddles on the Gears screen shift, and so do the pod buttons. '
        'The pod blinks and drops out for two seconds about once a minute: the '
        'application resets it to keep it alive, and it comes back by itself.',
  ),
];

/// The guide itself.
class OnboardingScreen extends StatefulWidget {
  /// Creates the guide.
  const OnboardingScreen({
    required this.onDone,
    this.onOpenTab,
    this.steps = onboardingSteps,
    super.key,
  });

  /// Called when the rider finishes or skips.
  final VoidCallback onDone;

  /// Opens a section of the application, for the steps that have one.
  final void Function(int tab)? onOpenTab;

  /// The steps to walk through.
  final List<OnboardingStep> steps;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _index = 0;

  bool get _last => _index == widget.steps.length - 1;

  void _next() {
    if (_last) {
      widget.onDone();
      return;
    }
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    final OnboardingStep step = widget.steps[_index];
    return Scaffold(
      backgroundColor: Tokens.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('First start', style: Type.section(context)),
                  ),
                  TextButton(
                    onPressed: widget.onDone,
                    child: const Text('Skip'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // The same ticks as the gear ladder: where you are, and how much is
              // left. One tick per step, the current one in the signal colour.
              Row(
                children: <Widget>[
                  for (int i = 0; i < widget.steps.length; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: i == widget.steps.length - 1 ? 0 : 6,
                        ),
                        child: Container(
                          key: i == _index
                              ? const Key('onboarding-tick-current')
                              : null,
                          height: i == _index ? 8 : 4,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? Tokens.signal
                                : i < _index
                                ? Tokens.muted.withValues(alpha: 0.55)
                                : Tokens.muted.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Column(
                  key: ValueKey<int>(_index),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      step.title,
                      style: Theme.of(context).textTheme.headlineSmall!
                          .copyWith(
                            color: Tokens.text,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      step.body,
                      style: Theme.of(context).textTheme.bodyLarge!
                          .copyWith(color: Tokens.muted, height: 1.45),
                    ),
                    if (step.tab != null &&
                        widget.onOpenTab != null) ...<Widget>[
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => widget.onOpenTab!(step.tab!),
                        child: Text(step.action!),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_last ? 'Start riding' : 'Next'),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'Step ${_index + 1} of ${widget.steps.length}',
                  style: Type.small(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

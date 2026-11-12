/// What keeps a controller link alive, and what may end it.
///
/// The watchdog answers "is this link still working?". This answers a different
/// question, the one that costs battery: "should this link exist at all right now?
/// " A pod left connected to a stopped application keeps its radio awake and
/// drains in a day or two; the same pod released after the application goes away
/// waits for the next ride.
///
/// Pure logic: the caller supplies the situation, and applies the directive.
library;

/// What the caller should do with the link.
enum LinkDirective {
  /// Leave it as it is.
  nothing,

  /// Open a link: an application is waiting and nothing is connected.
  connect,

  /// Close and reopen: the pod stopped acknowledging writes.
  reconnect,

  /// Close the link and let the pod sleep.
  release,
}

/// Everything the policy needs to know, gathered by the caller.
class LinkSituation {
  /// Builds a situation.
  const LinkSituation({
    required this.connected,
    required this.applicationPresent,
    this.sinceSessionEnd = Duration.zero,
    this.writeFailed = false,
    this.batteryCritical = false,
  });

  /// True while a link is up.
  final bool connected;

  /// True when something on this machine wants the buttons: a published
  /// application, or the window the keys are typed into.
  final bool applicationPresent;

  /// Time since the last application went away, zero while one is present.
  final Duration sinceSessionEnd;

  /// True when the pod stopped acknowledging writes.
  final bool writeFailed;

  /// True when the battery watch reports a critical level.
  final bool batteryCritical;
}

/// A directive and the sentence that explains it.
class LinkDecision {
  /// Builds a decision.
  const LinkDecision(this.directive, [this.reason = '']);

  /// What to do.
  final LinkDirective directive;

  /// Why, in one sentence, for the log and the interface.
  final String reason;

  @override
  String toString() => 'LinkDecision($directive, $reason)';
}

/// Decides what a link should do, given the situation.
class LinkPolicy {
  /// Creates a policy.
  ///
  /// [releaseAfter] is how long a link may stay open once nothing wants it. Ten
  /// minutes, because a rider stops for a mechanical, a phone call, a bottle: a
  /// link that dies in those minutes is a link that has to be woken by a button
  /// press at the worst moment. [releaseOnCriticalBattery] ends the link at once
  /// when the battery watch says the ride may not finish, since a pod that dies
  /// during the ride is worse than one that has to be woken.
  const LinkPolicy({
    this.releaseAfter = const Duration(minutes: 10),
    this.releaseOnCriticalBattery = false,
    this.restartAfter = const Duration(seconds: 50),
  });

  /// Idle time after which a link is released.
  final Duration releaseAfter;

  /// Whether a critical battery releases the link immediately.
  final bool releaseOnCriticalBattery;

  /// Age at which a healthy link is restarted rather than left to die.
  ///
  /// A Click v2 closes a plain session **57 to 62 s** after it opened, whatever
  /// is written to it: measured on the right pod on 2026-11-12 with a keepalive
  /// every three seconds, first as a bare `RideOn`, then as the activation frame
  /// `00 08 00`. Once it has closed, the pod is asleep and cannot be reached
  /// again without a button press — every attempt returned
  /// `device is not connected`. Restarting a few seconds early costs two or
  /// three seconds of link and never asks the rider for anything, which is the
  /// workaround `BikeControl` documents for the same pod.
  final Duration restartAfter;

  /// Whether a link that has lived [lived] should be restarted now.
  bool wantsRestart(Duration lived) => lived >= restartAfter;

  /// Decides what to do.
  LinkDecision decide(LinkSituation situation) {
    // A failed write is the only observable proof that the session ended, so it
    // outranks everything: the watchdog documents why silence does not.
    if (situation.connected && situation.writeFailed) {
      return const LinkDecision(
        LinkDirective.reconnect,
        'the controller stopped acknowledging writes',
      );
    }
    if (!situation.connected) {
      if (situation.applicationPresent) {
        return const LinkDecision(
          LinkDirective.connect,
          'an application is waiting for the buttons',
        );
      }
      return const LinkDecision(LinkDirective.nothing);
    }
    if (releaseOnCriticalBattery &&
        situation.batteryCritical &&
        !situation.applicationPresent) {
      return const LinkDecision(
        LinkDirective.release,
        'battery critical, nothing is using the buttons',
      );
    }
    if (!situation.applicationPresent &&
        situation.sinceSessionEnd >= releaseAfter) {
      return LinkDecision(
        LinkDirective.release,
        'no application for ${releaseAfter.inMinutes} minutes',
      );
    }
    return const LinkDecision(LinkDirective.nothing);
  }
}

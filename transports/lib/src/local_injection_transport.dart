/// Local transport: actions are injected straight into the graphical session of
/// the machine running the bridge.
///
/// It carries no bytes: [LocalInjectionTransport.emit] translates an action into
/// a key press or a tap, then calls the injector supplied by the application
/// ([KeyInjector], defined by the core). The bridge cannot inject by itself:
/// this file only contains the action to target routing, which keeps it testable
/// without a screen or a graphical session.
library;

import 'events.dart';
import 'transport.dart';
import 'package:openzclick_core/openzclick_core.dart';

/// Injection target bound to an action.
sealed class InjectionTarget {
  /// Builds a target.
  const InjectionTarget();
}

/// Keyboard target: press then release the [key].
class KeyTarget extends InjectionTarget {
  /// Builds a keyboard target.
  const KeyTarget(this.key);

  /// Key name as understood by the injector (`arrow up`, `space`, `a`...).
  final String key;

  @override
  String toString() => 'KeyTarget($key)';
}

/// Pointer target: tap at [x], [y] in the application coordinate space.
class PointTarget extends InjectionTarget {
  /// Builds a pointer target.
  const PointTarget(this.x, this.y);

  /// Tap abscissa.
  final double x;

  /// Tap ordinate.
  final double y;

  @override
  String toString() => 'PointTarget($x, $y)';
}

/// Local injection transport.
///
/// Unlike network transports it has no notion of peer: received actions are
/// published with a null `peerId`, so the diagnostic screen can show what was
/// injected.
class LocalInjectionTransport extends ManagedTransport {
  /// Creates the transport.
  ///
  /// [injector] is the real implementation (xdotool, mobile platform, window
  /// driving) supplied by the application. [targets] binds the actions to inject
  /// to their target; an action missing from the table throws [ArgumentError]
  /// when [emit] is called, rather than being silently ignored.
  LocalInjectionTransport({
    required this.injector,
    Map<Action, InjectionTarget> targets = const <Action, InjectionTarget>{},
  }) : targets = Map<Action, InjectionTarget>.unmodifiable(targets);

  /// Input injector supplied by the application.
  final KeyInjector injector;

  /// Action to injection target table.
  final Map<Action, InjectionTarget> targets;

  @override
  String get id => 'local';

  @override
  Future<void> onStart() async {
    // Nothing to open: the injector comes already built.
  }

  @override
  Future<void> onStop() async {
    // Nothing to close: the injector belongs to the application.
  }

  /// Injects [action].
  ///
  /// Throws [StateError] when the transport is stopped, [ArgumentError] when the
  /// action has no target. Injector errors are published as a [TransportError]
  /// and then rethrown.
  @override
  Future<void> emit(Action action) async {
    if (!isRunning) {
      throw StateError(
          'transport $id stopped: start() is required before emit()');
    }
    final InjectionTarget? target = targets[action];
    if (target == null) {
      throw ArgumentError(
        'action ${action.name} has no local injection target',
      );
    }
    try {
      switch (target) {
        case KeyTarget(:final String key):
          await injector.pressKey(key);
        case PointTarget(:final double x, :final double y):
          await injector.tapAt(x, y);
      }
    } catch (error) {
      publishError('injection of ${action.name} failed', cause: error);
      rethrow;
    }
    publish(TransportActionReceived(transportId: id, action: action));
  }
}

/// Input recorded by [MemoryKeyInjector].
sealed class InjectedInput {
  /// Builds an input.
  const InjectedInput();
}

/// Injected key press.
class InjectedKey extends InjectedInput {
  /// Builds a keyboard input.
  const InjectedKey(this.key);

  /// Key name.
  final String key;

  @override
  String toString() => 'InjectedKey($key)';
}

/// Injected tap.
class InjectedTap extends InjectedInput {
  /// Builds a pointer input.
  const InjectedTap(this.x, this.y);

  /// Abscissa.
  final double x;

  /// Ordinate.
  final double y;

  @override
  String toString() => 'InjectedTap($x, $y)';
}

/// In-memory injector: records inputs instead of producing them.
///
/// Used by the application test bench and by the tests: it shows what would have
/// been injected without depending on a graphical session.
class MemoryKeyInjector implements KeyInjector {
  final List<InjectedInput> _inputs = <InjectedInput>[];

  /// Recorded inputs, in order.
  List<InjectedInput> get inputs => List<InjectedInput>.unmodifiable(_inputs);

  /// Clears the history.
  void clear() => _inputs.clear();

  @override
  Future<void> tapAt(double x, double y) async {
    _inputs.add(InjectedTap(x, y));
  }

  @override
  Future<void> pressKey(String key) async {
    _inputs.add(InjectedKey(key));
  }
}

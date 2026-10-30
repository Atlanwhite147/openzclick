/// Button -> action lookup table, specific to a target app.
///
/// A `Keymap` is pure data: it knows neither the physical controller nor the
/// injection technique. It is built by the target app and consulted on every
/// press received by a transport.
library;

import '../protocol/button_ids.dart';
import 'action.dart';

/// Protocol button identifiers, duplicated here as private constants so the
/// mapping layer stays self-contained (no dependency on the protocol layer).

/// Elementary pairing between a hardware button and an action.
///
/// Used to describe a readable configuration before compacting it into a
/// [Keymap]. [analogAction] is reserved for analog buttons (value 2..255) for
/// which a different action can fire beyond a threshold; `null` when the
/// button is purely binary.
class ButtonBinding {
  /// Normalised button identifier (see protocol).
  final int buttonId;

  /// Action triggered by the press.
  final Action action;

  /// Optional action for the button's analog component.
  final int? analogAction;

  /// Creates a button -> action pairing.
  const ButtonBinding({
    required this.buttonId,
    required this.action,
    this.analogAction,
  });

  @override
  bool operator ==(Object other) =>
      other is ButtonBinding &&
      other.buttonId == buttonId &&
      other.action == action &&
      other.analogAction == analogAction;

  @override
  int get hashCode => Object.hash(buttonId, action, analogAction);

  @override
  String toString() =>
      'ButtonBinding(0x${buttonId.toRadixString(16)}, ${action.name})';
}

/// Button -> action mapping for a target app identified by [appId].
class Keymap {
  /// Target app identifier (e.g. "cible-a").
  final String appId;

  /// Immutable button -> action table. A missing button is unmapped.
  final Map<int, Action> bindings;

  /// Builds a table, validating the identifier and freezing the mappings.
  ///
  /// Throws [ArgumentError] if [appId] is empty.
  Keymap({required this.appId, required Map<int, Action> bindings})
      : bindings = Map<int, Action>.unmodifiable(bindings) {
    if (appId.trim().isEmpty) {
      throw ArgumentError.value(
          appId, 'appId', 'App identifier must not be empty');
    }
  }

  /// Empty table: every button falls back to [Action.none].
  factory Keymap.empty(String appId) =>
      Keymap(appId: appId, bindings: const <int, Action>{});

  /// Full default table, with targeted overrides.
  ///
  /// [overrides] replaces the default mappings button by button; an entry bound
  /// to [Action.none] disables the button.
  factory Keymap.defaults(String appId,
      {Map<int, Action> overrides = const <int, Action>{}}) {
    return Keymap(
      appId: appId,
      bindings: <int, Action>{..._defaultBindings, ...overrides},
    );
  }

  /// Builds a table from a list of explicit pairings.
  ///
  /// When [ButtonBinding.buttonId] is duplicated, the last entry wins.
  factory Keymap.fromBindings(String appId, Iterable<ButtonBinding> bindings) {
    final Map<int, Action> table = <int, Action>{};
    for (final binding in bindings) {
      table[binding.buttonId] = binding.action;
    }
    return Keymap(appId: appId, bindings: table);
  }

  /// Action bound to [buttonId], or [Action.none] if the button is not
  /// mapped.
  Action actionFor(int buttonId) => bindings[buttonId] ?? Action.none;

  /// True if the button is explicitly mapped.
  bool isBound(int buttonId) => bindings.containsKey(buttonId);

  /// Mapped buttons, sorted by ascending identifier.
  List<int> get buttonIds => bindings.keys.toList(growable: false)..sort();

  /// Pairings as a list, sorted by button identifier.
  List<ButtonBinding> get bindingList => <ButtonBinding>[
        for (final int id in buttonIds)
          ButtonBinding(buttonId: id, action: bindings[id]!),
      ];

  /// Copy with added or replaced mappings.
  Keymap withOverrides(Map<int, Action> overrides) =>
      Keymap(appId: appId, bindings: <int, Action>{...bindings, ...overrides});

  @override
  String toString() => 'Keymap($appId, ${bindings.length} buttons)';
}

const Map<int, Action> _defaultBindings = <int, Action>{
  ButtonIds.shiftUp: Action.shiftUp,
  ButtonIds.shiftDown: Action.shiftDown,
  ButtonIds.gearSet: Action.gearSet,
  ButtonIds.navigateUp: Action.navigateUp,
  ButtonIds.navigateDown: Action.navigateDown,
  ButtonIds.confirm: Action.confirm,
  ButtonIds.back: Action.back,
  ButtonIds.menu: Action.menu,
  ButtonIds.home: Action.home,
  ButtonIds.steerLeft: Action.steerLeft,
  ButtonIds.steerRight: Action.steerRight,
  ButtonIds.emote: Action.emote,
  ButtonIds.screenshot: Action.screenshot,
  ButtonIds.increaseDifficulty: Action.increaseDifficulty,
  ButtonIds.decreaseDifficulty: Action.decreaseDifficulty,
  ButtonIds.pause: Action.pause,
  ButtonIds.resume: Action.resume,
  ButtonIds.changeMode: Action.changeMode,
  ButtonIds.hudToggle: Action.toggleHud,
};

/// The keys a training application expects, per application.
///
/// A single global table is wrong for almost everyone: `i` and `k` are MyWhoosh,
/// `,` and `.` are Rouvy, `W` and `S` are Biketerra. Every project surveyed in
/// `docs/prior-art.md` ships such a table; this is the same idea, with the source
/// of each row named so a rider can check it.
///
/// Only applications whose shortcut page documents the gear keys are listed.
/// Zwift and TrainerRoad are absent on purpose: they expose no virtual-shifting
/// key, so there is nothing honest to put in a row for them.
library;

import 'package:openzclick_core/openzclick_core.dart';

/// One application's expectations.
class KeyProfile {
  /// Builds a profile.
  const KeyProfile({
    required this.id,
    required this.label,
    required this.keys,
    required this.source,
    this.shiftsPerPress = 1,
    this.windowHint = '',
  });

  /// Stable identifier, stored in the settings.
  final String id;

  /// Name shown to the rider.
  final String label;

  /// Key per action. An action missing here is not sent.
  final Map<Action, String> keys;

  /// Where the bindings come from, shown in the interface.
  ///
  /// A rider who sees a gear move the wrong way can open the page and check,
  /// instead of wondering whether the bridge is broken.
  final String source;

  /// Keys sent per button press, 1 to 3.
  ///
  /// Some applications have no gear ratio, only a ladder of gears: a rider who
  /// wants to cross three at once should not have to press three times.
  final int shiftsPerPress;

  /// Fragment of the window title, offered as a default for the focus field.
  final String windowHint;

  /// A copy with another number of shifts per press.
  KeyProfile withShiftsPerPress(int count) => KeyProfile(
    id: id,
    label: label,
    keys: keys,
    source: source,
    shiftsPerPress: count.clamp(1, 3),
    windowHint: windowHint,
  );
}

/// Applications whose shortcuts are documented, plus the bridge's own default.
const List<KeyProfile> builtInKeyProfiles = <KeyProfile>[
  KeyProfile(
    id: 'mywhoosh',
    label: 'MyWhoosh',
    // Two independent implementations send `K` for a harder gear and `I` for an
    // easier one: zwiftboard's shipped profile and ClickShift.
    keys: <Action, String>{
      Action.shiftUp: 'k',
      Action.shiftDown: 'i',
      Action.steerLeft: 'Left',
      Action.steerRight: 'Right',
    },
    source: 'https://mywhooshinfo.com/blog/mywhoosh-keyboard-shortcuts',
    windowHint: 'MyWhoosh',
  ),
  KeyProfile(
    id: 'rouvy',
    label: 'Rouvy',
    // The period shifts up, the comma shifts down; the arrows navigate.
    keys: <Action, String>{
      Action.shiftUp: '.',
      Action.shiftDown: ',',
      Action.steerLeft: 'Left',
      Action.steerRight: 'Right',
    },
    source: 'https://support.rouvy.com/hc/en-us/articles/47742964491665-Remote-controllers-and-control-mapping',
    windowHint: 'Rouvy',
  ),
  KeyProfile(
    id: 'biketerra',
    label: 'Biketerra',
    keys: <Action, String>{Action.shiftUp: 'w', Action.shiftDown: 's'},
    source: 'https://biketerra.com/help-center/virtual-shifting',
    windowHint: 'Biketerra',
  ),
  KeyProfile(
    id: 'custom',
    label: 'Any other application',
    keys: <Action, String>{
      Action.shiftUp: 'k',
      Action.shiftDown: 'i',
      Action.steerLeft: 'Left',
      Action.steerRight: 'Right',
    },
    source: '',
  ),
];

/// Profile with [id], or the first one when the identifier is unknown.
KeyProfile keyProfileById(String? id) {
  for (final KeyProfile profile in builtInKeyProfiles) {
    if (profile.id == id) return profile;
  }
  return builtInKeyProfiles.first;
}

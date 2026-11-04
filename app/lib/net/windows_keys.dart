/// Key names to Windows virtual-key codes.
///
/// The names are the ones the rest of the application already uses — X11 keysym
/// names such as `Left`, `Page_Up` and `i` — because they come from the key
/// bindings a rider can edit. Windows wants a number, and the conversion is the
/// only part of the Windows injector that can be tested without Windows, so it
/// lives here, away from the FFI calls.
///
/// [virtualKeyFor] returns `null` for a name it does not know instead of
/// guessing: a wrong virtual-key code presses a key nobody asked for, and the
/// rider would see a training application change gear by itself.
library;

/// Virtual-key code for [name], or `null` when the name is unknown.
///
/// Case matters only for the X11 modifier names (`Left` is an arrow, `left` is a
/// letter). Everything is trimmed first, because a binding typed by hand may
/// carry a stray space.
int? virtualKeyFor(String name) {
  final String key = name.trim();
  if (key.isEmpty) return null;

  final String lower = key.toLowerCase();
  // Single letters and digits first: they are the default bindings, and they
  // must not be confused with the named keys below.
  if (lower.length == 1) {
    final int code = lower.codeUnitAt(0);
    if (code >= 0x61 && code <= 0x7a) return 0x41 + (code - 0x61);
    if (code >= 0x30 && code <= 0x39) return 0x30 + (code - 0x30);
  }

  final int? named = _named[lower];
  if (named != null) return named;

  // Function keys, written either way.
  final RegExpMatch? fn = RegExp(r'^f([1-9]|1[0-2])$').firstMatch(lower);
  if (fn != null) return 0x70 + (int.parse(fn.group(1)!) - 1);

  return null;
}

/// Named keys, keyed by their lower-case name.
///
/// The X11 spelling is the reference: `Page_Up`, `BackSpace`, `bracketleft`.
const Map<String, int> _named = <String, int>{
  // Arrows and navigation.
  'left': 0x25,
  'up': 0x26,
  'right': 0x27,
  'down': 0x28,
  'home': 0x24,
  'end': 0x23,
  'page_up': 0x21,
  'page_down': 0x22,
  'prior': 0x21,
  'next': 0x22,
  'insert': 0x2D,
  'delete': 0x2E,

  // Editing.
  'return': 0x0D,
  'enter': 0x0D,
  'escape': 0x1B,
  'space': 0x20,
  'tab': 0x09,
  'backspace': 0x08,

  // Modifiers.
  'shift_l': 0xA0,
  'shift_r': 0xA1,
  'control_l': 0xA2,
  'control_r': 0xA3,
  'alt_l': 0xA4,
  'alt_r': 0xA5,

  // Punctuation, in the X11 names a binding may carry.
  'minus': 0xBD,
  'equal': 0xBB,
  'comma': 0xBC,
  'period': 0xBE,
  'slash': 0xBF,
  'semicolon': 0xBA,
  'apostrophe': 0xDE,
  'bracketleft': 0xDB,
  'bracketright': 0xDD,
  'backslash': 0xDC,
  'grave': 0xC0,

  // Numeric keypad, for riders who bind a numpad key.
  'kp_0': 0x60,
  'kp_1': 0x61,
  'kp_2': 0x62,
  'kp_3': 0x63,
  'kp_4': 0x64,
  'kp_5': 0x65,
  'kp_6': 0x66,
  'kp_7': 0x67,
  'kp_8': 0x68,
  'kp_9': 0x69,
};

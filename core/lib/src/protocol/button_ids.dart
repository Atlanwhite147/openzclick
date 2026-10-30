/// Table of normalized protocol button identifiers.
///
/// Values are normalized: whatever the originating controller, a raw byte is
/// translated into one of these identifiers by the `devices` layer, then
/// routed to an action by the `mapping` layer.
///
/// Ranges are deliberately grouped by function:
///
/// * `0x01`-`0x05`: shifting commands (derailleurs, chainrings, cassette);
/// * `0x10`-`0x1B`: UI navigation, steering and brake;
/// * `0x20`-`0x24`: social actions and capture;
/// * `0x30`-`0x38`: session control (difficulty, pause, lap, mode);
/// * `0x44`: display.
library;

/// Normalized button identifiers, one byte wide.
///
/// This class cannot be instantiated: it only holds constants and lookup
/// helpers.
abstract final class ButtonIds {
  // --- Shifting -----------------------------------------------------------

  /// Shift up (smaller sprocket).
  static const shiftUp = 0x01;

  /// Shift down (larger sprocket).
  static const shiftDown = 0x02;

  /// Direct gear selection, the analog value carrying the index.
  static const gearSet = 0x03;

  /// Direct chainring selection.
  static const chainringSet = 0x04;

  /// Direct cassette selection.
  static const cassetteSet = 0x05;

  // --- Navigation, steering, brake ----------------------------------------

  /// Move up within a list.
  static const navigateUp = 0x10;

  /// Move down within a list.
  static const navigateDown = 0x11;

  /// Move left.
  static const navigateLeft = 0x12;

  /// Move right.
  static const navigateRight = 0x13;

  /// Confirm the selected item.
  static const confirm = 0x14;

  /// Go back to the previous screen.
  static const back = 0x15;

  /// Open the menu.
  static const menu = 0x16;

  /// Go back to the home screen.
  static const home = 0x17;

  /// Steer left, analog value possible.
  static const steerLeft = 0x18;

  /// Steer right, analog value possible.
  static const steerRight = 0x19;

  /// Brake, analog value possible.
  static const brake = 0x1A;

  /// Absolute steering angle, carried by the analog value.
  static const steeringAngle = 0x1B;

  // --- Social and capture -------------------------------------------------

  /// Send an emote or a reaction.
  static const emote = 0x20;

  /// Take a screenshot.
  static const screenshot = 0x24;

  // --- Session control ----------------------------------------------------

  /// Increase difficulty.
  static const increaseDifficulty = 0x30;

  /// Decrease difficulty.
  static const decreaseDifficulty = 0x31;

  /// Skip to the next interval.
  static const skipInterval = 0x32;

  /// Pause.
  static const pause = 0x33;

  /// Resume after a pause.
  static const resume = 0x34;

  /// Record a lap.
  static const lap = 0x35;

  /// Change riding mode.
  static const changeMode = 0x38;

  // --- Display ------------------------------------------------------------

  /// Toggle the heads-up display.
  static const hudToggle = 0x44;

  /// Human-readable name of each identifier, in English (code identifiers).
  ///
  /// Used by diagnostic screens and wiring tests.
  static const Map<int, String> names = <int, String>{
    shiftUp: 'shiftUp',
    shiftDown: 'shiftDown',
    gearSet: 'gearSet',
    chainringSet: 'chainringSet',
    cassetteSet: 'cassetteSet',
    navigateUp: 'navigateUp',
    navigateDown: 'navigateDown',
    navigateLeft: 'navigateLeft',
    navigateRight: 'navigateRight',
    confirm: 'confirm',
    back: 'back',
    menu: 'menu',
    home: 'home',
    steerLeft: 'steerLeft',
    steerRight: 'steerRight',
    brake: 'brake',
    steeringAngle: 'steeringAngle',
    emote: 'emote',
    screenshot: 'screenshot',
    increaseDifficulty: 'increaseDifficulty',
    decreaseDifficulty: 'decreaseDifficulty',
    skipInterval: 'skipInterval',
    pause: 'pause',
    resume: 'resume',
    lap: 'lap',
    changeMode: 'changeMode',
    hudToggle: 'hudToggle',
  };

  /// All known identifiers, sorted by ascending value.
  static const List<int> all = <int>[
    shiftUp,
    shiftDown,
    gearSet,
    chainringSet,
    cassetteSet,
    navigateUp,
    navigateDown,
    navigateLeft,
    navigateRight,
    confirm,
    back,
    menu,
    home,
    steerLeft,
    steerRight,
    brake,
    steeringAngle,
    emote,
    screenshot,
    increaseDifficulty,
    decreaseDifficulty,
    skipInterval,
    pause,
    resume,
    lap,
    changeMode,
    hudToggle,
  ];

  /// Whether [id] is a known normalized identifier.
  static bool isKnown(int id) => names.containsKey(id);

  /// Returns the name of [id], or `null` if unknown.
  static String? nameOf(int id) => names[id];

  /// Whether [id] is a shifting command.
  static bool isShifting(int id) => id >= shiftUp && id <= cassetteSet;

  /// Whether [id] carries an analog value rather than a plain press:
  /// steering, brake and angle.
  static bool isAnalog(int id) =>
      id == steerLeft || id == steerRight || id == brake || id == steeringAngle;
}

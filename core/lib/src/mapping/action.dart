/// Normalised actions, independent of the controller and of the target app.
///
/// An action is the shared vocabulary between transports (which receive button
/// presses) and the application (which injects keys or taps). It carries no
/// hardware identifier: the button -> action mapping lives in [Keymap].
library;

/// High-level action triggered by a button or by the UI.
enum Action {
  /// Shifts to the larger development.
  shiftUp,

  /// Shifts to the smaller development.
  shiftDown,

  /// Selects a cog directly (hardware selection button).
  gearSet,

  /// Steers left.
  steerLeft,

  /// Steers right.
  steerRight,

  /// Moves up in a list or a menu.
  navigateUp,

  /// Moves down in a list or a menu.
  navigateDown,

  /// Confirms the selected item.
  confirm,

  /// Returns to the previous screen.
  back,

  /// Opens or closes the menu.
  menu,

  /// Goes back to the home screen.
  home,

  /// Triggers an emote.
  emote,

  /// Takes a screenshot.
  screenshot,

  /// Pauses.
  pause,

  /// Resumes after a pause.
  resume,

  /// Increases the difficulty.
  increaseDifficulty,

  /// Decreases the difficulty.
  decreaseDifficulty,

  /// Changes the riding mode.
  changeMode,

  /// Shows or hides the head-up display.
  toggleHud,

  /// No action: unmapped button or ignored press.
  none,
}

/// Human-readable label of an action, meant for display.
extension ActionLabel on Action {
  String get label {
    switch (this) {
      case Action.shiftUp:
        return 'Shift up';
      case Action.shiftDown:
        return 'Shift down';
      case Action.gearSet:
        return 'Select gear';
      case Action.steerLeft:
        return 'Left';
      case Action.steerRight:
        return 'Right';
      case Action.navigateUp:
        return 'Up';
      case Action.navigateDown:
        return 'Down';
      case Action.confirm:
        return 'Confirm';
      case Action.back:
        return 'Back';
      case Action.menu:
        return 'Menu';
      case Action.home:
        return 'Home';
      case Action.emote:
        return 'Emote';
      case Action.screenshot:
        return 'Screenshot';
      case Action.pause:
        return 'Pause';
      case Action.resume:
        return 'Resume';
      case Action.increaseDifficulty:
        return 'Difficulty +';
      case Action.decreaseDifficulty:
        return 'Difficulty -';
      case Action.changeMode:
        return 'Change mode';
      case Action.toggleHud:
        return 'Head-up display';
      case Action.none:
        return 'None';
    }
  }

  /// True for actions that make no sense when repeated in a burst
  /// (state toggle rather than increment).
  bool get isToggle =>
      this == Action.pause ||
      this == Action.resume ||
      this == Action.menu ||
      this == Action.home ||
      this == Action.toggleHud ||
      this == Action.screenshot ||
      this == Action.emote;
}

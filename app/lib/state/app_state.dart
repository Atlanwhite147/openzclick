import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openzclick_core/openzclick_core.dart';

import '../ble/controller_connection.dart';

/// Shared application state: one gear engine, one keymap, one controller link.
///
/// Widgets never touch protocol or hardware directly; they read this object
/// and call its methods.
class AppState extends ChangeNotifier {
  /// Gear engine used by the trainer screen and the test bench.
  final GearEngine engine;

  /// Keymap used by the target screen to display button bindings.
  final Keymap keymap;

  /// Bluetooth link to the physical controller.
  final ControllerConnection controller = ControllerConnection();

  /// Last protocol frame produced by the test bench, as a hex string.
  String lastFrame = '';

  /// Result of decoding that frame again, to show the round trip.
  String lastDecoded = '';

  /// Last button state received from the controller.
  ClickButtons? lastButtons;

  StreamSubscription<ClickButtons>? _buttonSubscription;

  /// Creates the state, optionally with a specific profile.
  AppState({GearProfile? profile})
      : engine = GearEngine(
          profile: profile ?? GearProfile.road12,
          initialGear: 5,
        ),
        keymap = Keymap.defaults('default') {
    controller.onChanged = notifyListeners;
    _buttonSubscription = controller.buttons.listen(handleButtons);
  }

  /// Applies a button state coming from the physical controller.
  ///
  /// Exposed for tests: the Bluetooth link feeds it through the stream.
  void handleButtons(ClickButtons buttons) {
    lastButtons = buttons;
    if (buttons.up && !buttons.down) shiftUp();
    if (buttons.down && !buttons.up) shiftDown();
    notifyListeners();
  }

  /// Shifts up.
  void shiftUp() {
    engine.shiftUp();
    notifyListeners();
  }

  /// Shifts down.
  void shiftDown() {
    engine.shiftDown();
    notifyListeners();
  }

  /// Toggles the virtual chainring.
  void toggleChainring() {
    engine.toggleChainring();
    notifyListeners();
  }

  /// Switches between simulation and ERG.
  void toggleMode() {
    engine.setMode(
      engine.mode == RidingMode.sim ? RidingMode.erg : RidingMode.sim,
    );
    notifyListeners();
  }

  /// Moves the ERG target by [watts].
  void bumpErg(int watts) {
    engine.bumpErg(watts);
    notifyListeners();
  }

  /// Encodes a two-button frame and decodes it back, for the test bench.
  void runCodecBench() {
    final ButtonStateMessage message = ButtonStateMessage(<int, int>{
      ButtonIds.shiftUp: 0x01,
      ButtonIds.shiftDown: 0x00,
    });
    final List<int> frame = message.encode();
    lastFrame = frame
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    final result = ObcCodec.tryDecode(frame);
    if (result == null) {
      lastDecoded = 'incomplete frame';
      return;
    }
    final ObcMessage decoded = result.message;
    lastDecoded = decoded is ButtonState
        ? 'button state: ${decoded.buttons}'
        : decoded.runtimeType.toString();
    notifyListeners();
  }

  @override
  void dispose() {
    controller.onChanged = null;
    _buttonSubscription?.cancel();
    controller.dispose();
    super.dispose();
  }
}

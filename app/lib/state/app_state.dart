import 'dart:async';

import 'package:flutter/material.dart' hide Action;
import 'package:openzclick_core/openzclick_core.dart';

import '../ble/controller_connection.dart';
import '../net/network_publisher.dart';

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

  /// Network publication towards a training application.
  final NetworkPublisher publisher = NetworkPublisher();

  /// Turns button states into gear changes and direction choices.
  late final ButtonGestureDetector gestures;

  /// Last action produced by the controller, for display.
  Action lastAction = Action.none;

  /// Last protocol frame produced by the test bench, as a hex string.
  String lastFrame = '';

  /// Result of decoding that frame again, to show the round trip.
  String lastDecoded = '';

  /// Last button state received from the controller.
  ClickButtons? lastButtons;

  StreamSubscription<ClickButtons>? _buttonSubscription;

  /// Creates the state, optionally with a specific profile.
  ///
  /// [doubleTapWindow] is forwarded to the gesture detector so that tests can
  /// shorten it.
  AppState({GearProfile? profile, Duration? doubleTapWindow})
      : engine = GearEngine(
          profile: profile ?? GearProfile.road12,
          initialGear: 5,
        ),
        keymap = Keymap.defaults('default') {
    controller.onChanged = notifyListeners;
    publisher.onChanged = notifyListeners;
    gestures = ButtonGestureDetector(
      onAction: _onAction,
      doubleTapWindow: doubleTapWindow ?? const Duration(milliseconds: 320),
    );
    _buttonSubscription = controller.buttons.listen(handleButtons);
  }

  /// Applies an action coming from the gesture detector.
  Future<void> _onAction(Action action) async {
    lastAction = action;
    switch (action) {
      case Action.shiftUp:
        shiftUp();
      case Action.shiftDown:
        shiftDown();
      case Action.steerLeft:
      case Action.steerRight:
        await publisher.publish(action);
        notifyListeners();
      default:
        notifyListeners();
    }
  }

  /// Applies a button state coming from the physical controller.
  ///
  /// Exposed for tests: the Bluetooth link feeds it through the stream.
  void handleButtons(ClickButtons buttons) {
    lastButtons = buttons;
    gestures.feed(buttons);
    notifyListeners();
  }

  /// Starts or stops the network publication.
  Future<void> togglePublishing() async {
    if (publisher.running) {
      await publisher.stop();
    } else {
      await publisher.start();
    }
    notifyListeners();
  }

  /// Shifts up.
  void shiftUp() {
    engine.shiftUp();
    unawaited(publisher.publish(Action.shiftUp));
    notifyListeners();
  }

  /// Shifts down.
  void shiftDown() {
    engine.shiftDown();
    unawaited(publisher.publish(Action.shiftDown));
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
    publisher.onChanged = null;
    gestures.dispose();
    publisher.dispose();
    _buttonSubscription?.cancel();
    controller.dispose();
    super.dispose();
  }
}

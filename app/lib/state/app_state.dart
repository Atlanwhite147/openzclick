import 'dart:async';

import 'package:flutter/material.dart' hide Action;
import 'package:openzclick_core/openzclick_core.dart';

import '../ble/controller_connection.dart';
import '../net/android_injection.dart';
import '../net/injection_publisher.dart';
import '../net/network_publisher.dart';
import '../settings/settings_store.dart';

/// Shared application state: one gear engine, one keymap, one controller link.
///
/// Widgets never touch protocol or hardware directly; they read this object
/// and call its methods.
class AppState extends ChangeNotifier {
  /// Gear engine used by the trainer screen and the test bench.
  ///
  /// Replaced when the rider changes profile, hence not final.
  GearEngine engine;

  /// Keymap used by the target screen to display button bindings.
  final Keymap keymap;

  /// Bluetooth link to the physical controller.
  final ControllerConnection controller = ControllerConnection();

  /// Network publication towards a training application.
  final NetworkPublisher publisher = NetworkPublisher();

  /// Local injection towards an application that only accepts taps.
  final InjectionPublisher injection = InjectionPublisher(
    injector:
        AndroidInjection.supported ? AndroidInjection() : UnsupportedInjector(),
    readiness: AndroidInjection.supported ? AndroidInjection.isReady : null,
  );

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

  /// Persistence port, null until [restore] is called.
  SettingsStore? store;

  Timer? _persistTimer;

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
    injection.onChanged = () {
      _persist();
      notifyListeners();
    };
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
        await injection.publish(action);
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

  /// Sends a direction choice, used by the diagnostics screen and by the
  /// double-tap gesture.
  Future<void> sendDirection(Action action) async {
    lastAction = action;
    await publisher.publish(action);
    await injection.publish(action);
    notifyListeners();
  }

  /// Starts or stops the local tap injection.
  Future<void> toggleInjection() async {
    if (injection.running) {
      await injection.stop();
    } else {
      await injection.start();
    }
    _persist();
    notifyListeners();
  }

  /// Starts or stops the network publication.
  Future<void> togglePublishing() async {
    if (publisher.running) {
      await publisher.stop();
    } else {
      await publisher.start();
    }
    _persist();
    notifyListeners();
  }

  /// Shifts up.
  void shiftUp() {
    engine.shiftUp();
    _persist();
    unawaited(publisher.publish(Action.shiftUp));
    unawaited(injection.publish(Action.shiftUp));
    notifyListeners();
  }

  /// Shifts down.
  void shiftDown() {
    engine.shiftDown();
    _persist();
    unawaited(publisher.publish(Action.shiftDown));
    unawaited(injection.publish(Action.shiftDown));
    notifyListeners();
  }

  /// Switches to another built-in profile, keeping the position in the block.
  void setProfile(String profileId) {
    final GearProfile? profile = GearProfile.byId(profileId);
    if (profile == null || profile.id == engine.profile.id) return;
    final double ratio = engine.gearCount > 1
        ? engine.gearIndex / (engine.gearCount - 1)
        : 0;
    engine = GearEngine(
      profile: profile,
      initialGear: (ratio * (profile.gearCount - 1)).round(),
      mode: engine.mode,
    );
    _persist();
    notifyListeners();
  }

  /// Switches between simulation and ergometer modes.
  void toggleMode() {
    engine.setMode(
      engine.mode == RidingMode.sim ? RidingMode.erg : RidingMode.sim,
    );
    _persist();
    notifyListeners();
  }

  /// Restores the stored settings, then optionally resumes publishing.
  Future<void> restore(SettingsStore settings) async {
    store = settings;
    final SettingsSnapshot? snapshot = await settings.load();
    if (snapshot == null) return;

    final GearProfile profile =
        GearProfile.byId(snapshot.profileId) ?? GearProfile.road12;
    engine = GearEngine(profile: profile, initialGear: snapshot.gearIndex);
    for (final MapEntry<Action, List<double>> entry in snapshot.positions.entries) {
      injection.setPosition(entry.key, entry.value[0], entry.value[1]);
    }
    if (snapshot.publishOnStart) await publisher.start();
    if (snapshot.injectOnStart) await injection.start();
    notifyListeners();
  }

  /// Writes the current settings, coalescing bursts of changes.
  void _persist() {
    final SettingsStore? settings = store;
    if (settings == null) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 250), () {
      settings.save(
        SettingsSnapshot(
          profileId: engine.profile.id,
          gearIndex: engine.gearIndex,
          positions: injection.positions,
          publishOnStart: publisher.running,
          injectOnStart: injection.running,
        ),
      );
    });
  }

  /// Toggles the virtual chainring.
  void toggleChainring() {
    engine.toggleChainring();
    notifyListeners();
  }

  /// Switches between simulation and ERG.
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
    injection.onChanged = null;
    injection.stop();
    gestures.dispose();
    publisher.dispose();
    _buttonSubscription?.cancel();
    controller.dispose();
    super.dispose();
  }
}

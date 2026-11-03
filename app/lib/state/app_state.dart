import 'dart:async';

import 'package:flutter/material.dart' hide Action;
import 'package:openzclick_core/openzclick_core.dart';

import '../ble/controller_connection.dart';
import '../net/android_injection.dart';
import '../net/desktop_injection.dart';
import '../net/injection_publisher.dart';
import '../net/publisher.dart';
import '../platform/capabilities.dart';
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

  /// Desktop backend for keyboard and pointer injection, null when the host has
  /// none (a browser, or Windows and macOS until a port exists).
  final DesktopInjection? _desktop = createDesktopInjection();

  /// Bluetooth link to the physical controller.
  final ControllerConnection controller = ControllerConnection();

  /// Publication towards a training application.
  ///
  /// iOS cannot announce a service without Apple's multicast entitlement, so
  /// the publisher only listens there and the address is shown to the user. A
  /// browser cannot publish at all: it becomes the console of a bridge instead.
  ///
  /// A caller may supply one, which is how the console paths are tested without
  /// a network.
  late final PublisherPort publisher =
      _publisherOverride ??
      createPublisher(advertise: Capabilities.canAnnounce);

  /// Local injection towards an application that only accepts taps.
  late final InjectionPublisher injection = InjectionPublisher(
    injector:
        _desktop?.injector ??
        (AndroidInjection.supported
            ? AndroidInjection()
            : UnsupportedInjector()),
    availability: _desktop?.availability,
    readiness: AndroidInjection.supported ? AndroidInjection.isReady : null,
    keys: _desktop == null ? null : InjectionPublisher.defaultKeys,
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

  /// What is physically bolted to the bike, and where the chain sits on it.
  ///
  /// Kept here rather than in a screen because every gear the bridge applies
  /// depends on it: a bridge that forgets the parked gear moves the whole ladder
  /// by a factor the rider cannot see.
  PhysicalSetup physicalSetup = PhysicalSetup.defaultSetup;

  Timer? _persistTimer;

  StreamSubscription<ClickButtons>? _buttonSubscription;
  StreamSubscription<Action>? _consoleSubscription;
  StreamSubscription<Map<String, Object?>>? _bridgeSubscription;

  /// Creates the state, optionally with a specific profile.
  ///
  /// [doubleTapWindow] is forwarded to the gesture detector so that tests can
  /// shorten it. [publisher] replaces the publication of the host, which is how
  /// the console paths are exercised without a bridge on the network.
  AppState({
    GearProfile? profile,
    Duration? doubleTapWindow,
    PublisherPort? publisher,
  }) : _publisherOverride = publisher,
       engine = GearEngine(
         profile: profile ?? GearProfile.road12,
         initialGear: 5,
       ),
       keymap = Keymap.defaults('default') {
    controller.onChanged = notifyListeners;
    // `this.` on purpose: inside the body, the constructor parameter of the same
    // name would otherwise shadow the field.
    this.publisher.onChanged = notifyListeners;
    injection.onChanged = () {
      _persist();
      notifyListeners();
    };
    gestures = ButtonGestureDetector(
      onAction: _onAction,
      doubleTapWindow: doubleTapWindow ?? const Duration(milliseconds: 320),
    );
    _buttonSubscription = controller.buttons.listen(handleButtons);

    // A console is an input like any other: its buttons take exactly the same
    // path as the ones of the physical controller.
    _consoleSubscription = this.publisher.consoleActions.listen(_onAction);
    final ConsoleClient? client = consoleClient;
    if (client != null) {
      // The other way round: this host is the console, so the bridge decides
      // the gear and the page follows, instead of drifting beside it.
      _bridgeSubscription = client.bridgeStates.listen(_onBridgeState);
    }
  }

  /// Publication supplied by a test, `null` on a real run.
  final PublisherPort? _publisherOverride;

  /// Applies a state published by the bridge this page is the console of.
  void _onBridgeState(Map<String, Object?> state) {
    final Object? rawGear = state['gearIndex'];
    if (rawGear is! int) return;
    final Object? rawProfile = state['profileId'];
    final GearProfile profile = rawProfile is String
        ? GearProfile.byId(rawProfile) ?? engine.profile
        : engine.profile;
    final Object? rawMode = state['mode'];
    final RidingMode mode = rawMode == RidingMode.erg.name
        ? RidingMode.erg
        : RidingMode.sim;
    if (profile.id == engine.profile.id &&
        rawGear == engine.gearIndex &&
        mode == engine.mode) {
      return;
    }
    engine = GearEngine(profile: profile, initialGear: rawGear, mode: mode);
    _persist();
    notifyListeners();
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
    _syncConsole(Action.shiftUp);
    unawaited(publisher.publish(Action.shiftUp));
    unawaited(injection.publish(Action.shiftUp));
    notifyListeners();
  }

  /// Shifts down.
  void shiftDown() {
    engine.shiftDown();
    _persist();
    _syncConsole(Action.shiftDown);
    unawaited(publisher.publish(Action.shiftDown));
    unawaited(injection.publish(Action.shiftDown));
    notifyListeners();
  }

  /// Publishes the gear state the browser consoles display.
  ///
  /// Called on every change that a page can show: a console left on a shelf must
  /// display the gear the bridge is really in, not the one it had when it
  /// connected.
  void _syncConsole(Action action) {
    unawaited(
      publisher.publishConsoleState(
        profileId: engine.profile.id,
        gearIndex: engine.gearIndex,
        gearCount: engine.gearCount,
        mode: engine.mode.name,
        lastAction: action.label,
      ),
    );
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
    _syncConsole(Action.none);
    notifyListeners();
  }

  /// Switches between simulation and ergometer modes.
  void toggleMode() {
    engine.setMode(
      engine.mode == RidingMode.sim ? RidingMode.erg : RidingMode.sim,
    );
    _persist();
    _syncConsole(Action.none);
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
    physicalSetup = PhysicalSetup(
      chainringTeeth: physicalSetup.chainringTeeth,
      cogTeeth: physicalSetup.cogTeeth,
      parkedChainringTeeth: snapshot.parkedChainringTeeth,
      parkedCogTeeth: snapshot.parkedCogTeeth,
    );
    for (final MapEntry<Action, List<double>> entry
        in snapshot.positions.entries) {
      injection.setPosition(entry.key, entry.value[0], entry.value[1]);
    }
    if (snapshot.publishOnStart) await publisher.start();
    if (snapshot.injectOnStart) await injection.start();
    _syncConsole(Action.none);
    notifyListeners();
  }

  /// Connects this page to a bridge, as its console.
  ///
  /// Only the browser build is a console: the native one serves consoles.
  Future<void> connectConsole(String host, String code) async {
    await consoleClient?.connectConsole(host, code);
    notifyListeners();
  }

  /// Closes the connection to the bridge.
  Future<void> disconnectConsole() async {
    await consoleClient?.disconnectConsole();
    notifyListeners();
  }

  /// The bridge this page is the console of, `null` on a native host.
  ConsoleClient? get consoleClient => switch (publisher) {
    final ConsoleClient client => client,
    _ => null,
  };

  /// Records where the chain sits on the bike.
  ///
  /// The single most consequential setting in the application: it moves every
  /// gear at once, by a factor of up to two, with no symptom other than the
  /// rider finding the ride harder or easier than the number on screen says.
  void setParkedGear({required int chainring, required int cog}) {
    final PhysicalSetup updated = physicalSetup.parkedOn(
      chainring: chainring,
      cog: cog,
    );
    if (!updated.isComplete) return;
    physicalSetup = updated;
    _persist();
    _syncConsole(Action.none);
    notifyListeners();
  }

  /// Wheel size the current gear asks the trainer for, in millimetres.
  ///
  /// `null` when setup is unfinished or the gear cannot be expressed, which the
  /// Network screen reports instead of showing a number nobody can use.
  double? get currentWheelCircumference {
    final ParkedGear? parked = physicalSetup.parkedGear;
    if (parked == null) return null;
    final List<GearRatio> gears = engine.profile.gears;
    if (engine.gearIndex < 0 || engine.gearIndex >= gears.length) return null;
    return WheelCircumferenceScaler.effectiveCircumference(
      neutralCircumference: referenceCircumferenceMillimeters,
      parked: parked,
      selectedRatio: gears[engine.gearIndex].ratio,
    );
  }

  /// The gear the setup recommends, given the profile in use.
  ParkedGear? get recommendedParkedGear =>
      physicalSetup.recommendParkedGear(engine.profile);

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
          parkedChainringTeeth: physicalSetup.parkedChainringTeeth,
          parkedCogTeeth: physicalSetup.parkedCogTeeth,
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
    _consoleSubscription?.cancel();
    _bridgeSubscription?.cancel();
    controller.dispose();
    super.dispose();
  }
}

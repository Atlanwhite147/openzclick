/// Home trainer proxy: the bridge relays the grade simulated by a home trainer
/// and sends it resistance setpoints.
///
/// The real link to a home trainer is a Bluetooth connection to the FTMS
/// service (Fitness Machine Service). That connection depends on a platform API,
/// hence a plugin, and this package may only depend on `openzclick_core`, `meta`
/// and `test`: the link is therefore an abstraction ([FtmsLink]) to be supplied
/// by the application.
///
/// What works here, and is tested: the proxy lifecycle, the grade relay as
/// [TransportGradeUpdate], and the translation of difficulty actions into
/// resistance setpoints. What remains to be wired: the native FTMS link itself -
/// without a link, [TrainerProxy.start] explicitly throws [UnimplementedError].
library;

import 'dart:async';

import 'events.dart';
import 'transport.dart';
import 'package:openzclick_core/openzclick_core.dart';

/// Link to an FTMS capable home trainer.
///
/// A real implementation relies on a platform Bluetooth API: subscription to the
/// grade/treadmill data characteristic, and writes to the fitness machine control
/// point for grade or target power.
abstract interface class FtmsLink {
  /// Opens the connection to the home trainer [deviceId].
  Future<void> connect(String deviceId);

  /// Closes the connection.
  Future<void> disconnect();

  /// True when the connection is open.
  bool get isConnected;

  /// Current grade in percent, positive uphill, as published by the home
  /// trainer.
  Stream<double> get gradePercent;

  /// Requests a target grade, in percent.
  Future<void> setTargetGrade(double percent);

  /// Requests a target power, in watts (`0` to cut resistance).
  Future<void> setTargetPower(int watts);
}

/// Home trainer proxy transport.
class TrainerProxy extends ManagedTransport {
  /// Creates the proxy.
  ///
  /// [link] is the FTMS link: `null` while no Bluetooth backend is wired, which
  /// makes [start] immediately explicit. [gradeStep] is the grade increment
  /// applied by the difficulty actions.
  TrainerProxy({
    this.link,
    this.deviceId = 'trainer',
    this.gradeStep = 0.5,
    this.initialGrade = 0,
  }) : assert(gradeStep > 0, 'gradeStep must be positive');

  /// FTMS link, `null` when not wired.
  final FtmsLink? link;

  /// Identifier of the home trainer to reach.
  final String deviceId;

  /// Grade increment, in percentage points, applied by the difficulty actions.
  final double gradeStep;

  /// Starting grade, before the first measurement of the home trainer.
  final double initialGrade;

  /// Peer identifier published for the home trainer.
  static const String trainerPeerId = 'trainer';

  /// Lowest grade the proxy will request, in percent.
  static const double minGrade = -40;

  /// Highest grade the proxy will request, in percent.
  static const double maxGrade = 40;

  StreamSubscription<double>? _gradeSubscription;
  double _grade = 0;
  int? _restorePower;
  int? _lastPower;
  int _ignoredActions = 0;

  @override
  String get id => 'proxy';

  /// Last known grade, in percent.
  double get gradePercent => _grade;

  /// Number of received actions the proxy cannot translate.
  int get ignoredActionCount => _ignoredActions;

  /// True when a link was supplied (not necessarily connected).
  bool get hasLink => link != null;

  @override
  Future<void> onStart() async {
    final FtmsLink? link = this.link;
    if (link == null) {
      throw UnimplementedError(
        'home trainer link not wired: supply an FtmsLink (FTMS through '
        'BluetoothGatt on Android, CoreBluetooth on iOS) to the constructor of '
        '$id before start()',
      );
    }
    _grade = initialGrade;
    await link.connect(deviceId);
    _gradeSubscription = link.gradePercent.listen(_onGrade);
    publish(
      TransportConnected(
        transportId: id,
        peerId: trainerPeerId,
        label: deviceId,
      ),
    );
  }

  @override
  Future<void> onStop() async {
    final bool wasRunning = isRunning;
    await _gradeSubscription?.cancel();
    _gradeSubscription = null;
    final FtmsLink? link = this.link;
    if (link != null && link.isConnected) {
      await link.disconnect();
    }
    if (wasRunning) {
      publish(TransportDisconnected(transportId: id, peerId: trainerPeerId));
    }
  }

  /// Applies [action] to the home trainer.
  ///
  /// * [Action.increaseDifficulty] and [Action.shiftUp]: grade + [gradeStep];
  /// * [Action.decreaseDifficulty] and [Action.shiftDown]: grade - [gradeStep];
  /// * [Action.pause]: target power set to `0`;
  /// * [Action.resume]: restores the previous target power when known.
  ///
  /// Other actions make no sense for a home trainer: they are ignored and
  /// counted in [ignoredActionCount].
  @override
  Future<void> emit(Action action) async {
    if (!isRunning) {
      throw StateError(
          'transport $id stopped: start() is required before emit()');
    }
    final FtmsLink? link = this.link;
    if (link == null || !link.isConnected) {
      throw StateError(
        'home trainer not connected: cannot apply ${action.name}',
      );
    }
    switch (action) {
      case Action.increaseDifficulty:
      case Action.shiftUp:
        await setGrade(_grade + gradeStep);
      case Action.decreaseDifficulty:
      case Action.shiftDown:
        await setGrade(_grade - gradeStep);
      case Action.pause:
        _restorePower = _lastPower;
        await link.setTargetPower(0);
      case Action.resume:
        final int? restore = _restorePower;
        if (restore != null) {
          await link.setTargetPower(restore);
        }
      case Action.gearSet:
      case Action.steerLeft:
      case Action.steerRight:
      case Action.navigateUp:
      case Action.navigateDown:
      case Action.confirm:
      case Action.back:
      case Action.menu:
      case Action.home:
      case Action.emote:
      case Action.screenshot:
      case Action.changeMode:
      case Action.toggleHud:
      case Action.none:
        _ignoredActions++;
    }
  }

  /// Requests [percent] to the home trainer and updates [gradePercent].
  ///
  /// The value is clamped to [minGrade]..[maxGrade].
  Future<void> setGrade(double percent) async {
    final FtmsLink? link = this.link;
    if (link == null) {
      throw StateError('no home trainer link');
    }
    _grade = percent.clamp(minGrade, maxGrade).toDouble();
    await link.setTargetGrade(_grade);
    publish(TransportGradeUpdate(transportId: id, gradePercent: _grade));
  }

  /// Requests the target power [watts] to the home trainer.
  Future<void> setTargetPower(int watts) async {
    final FtmsLink? link = this.link;
    if (link == null) {
      throw StateError('no home trainer link');
    }
    if (watts < 0) {
      throw ArgumentError.value(watts, 'watts', 'must be zero or positive');
    }
    _lastPower = watts;
    await link.setTargetPower(watts);
  }

  void _onGrade(double grade) {
    _grade = grade;
    publish(TransportGradeUpdate(transportId: id, gradePercent: grade));
  }
}

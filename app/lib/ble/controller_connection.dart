import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:openzclick_core/openzclick_core.dart';

import '../platform/capabilities.dart';

import 'bluetooth_uuid.dart';
import 'controller_error.dart';
import 'device_report.dart';

/// State of the connection to a physical controller.
enum ControllerStatus {
  /// Not connected.
  idle,

  /// Scanning for advertisments.
  scanning,

  /// Connecting and discovering services.
  connecting,

  /// Connected, handshake sent, frames expected.
  ready,

  /// Something went wrong; [ControllerConnection.error] holds the reason.
  failed,
}

/// A bridge between the Bluetooth stack and the core protocol.
///
/// The class owns one BLE connection at a time. It performs the encrypted
/// handshake, falls back to the plain one when the firmware ignores it,
/// decodes frames with [ControllerCodec] and republishes button states as a
/// stream of [ClickButtonMask].
///
/// The three characteristics of the controller do not do the same job, and
/// swapping two of them produces a link that connects and then stays silent:
///
/// | Characteristic | UUID suffix | Direction | Used for |
/// |---|---|---|---|
/// | async | `0002` | controller to host, notify | the button stream |
/// | syncRx | `0003` | host to controller, write | handshake and commands |
/// | syncTx | `0004` | controller to host, indicate | handshake reply and answers |
///
/// A controller that has never been paired in the official application may
/// answer nothing at all: [needsUnlock] is then set and the interface must say
/// so, because no amount of reconnecting will change it.
class ControllerConnection {
  /// Bluetooth device currently targeted, if any.
  BluetoothDevice? device;

  /// Last known status.
  ControllerStatus status = ControllerStatus.idle;

  /// Last error message, cleared on a successful connect.
  String? error;

  /// Battery level reported by the controller, if received.
  int? batteryPercent;

  /// True when the controller stayed completely silent after the handshake,
  /// which almost always means it must be paired once in the official
  /// application before it accepts any other host.
  bool needsUnlock = false;

  /// True when the last scan ended without a single controller.
  ///
  /// A scan that finds nothing used to go back to the initial screen without
  /// a word, which reads as "the button did nothing": say it instead.
  bool scanFoundNothing = false;

  /// Strings the controller gave about itself, read at connect.
  ///
  /// Firmware is the one field a bug report cannot do without: the same model
  /// behaves differently across revisions, and riders rarely know which they
  /// have.
  DeviceInformation information = const DeviceInformation();

  /// GATT tree as the platform reported it, for [buildReport].
  ///
  /// Distinct from the local `services` of a connection attempt: the tree
  /// outlives the attempt, because a link that fails is the one worth reporting.
  List<GattServiceInfo> gattTree = const <GattServiceInfo>[];

  final FrameRing _frames = FrameRing();

  /// What happened to the link itself, kept across reconnections.
  ///
  /// Not cleared with [_frames], on purpose: the failure worth diagnosing is a
  /// drop followed by a reconnection, so the report has to be able to say both
  /// "the link ended after 57 s" and what the next attempt did.
  final LinkLog _linkLog = LinkLog();

  /// Events of the link, oldest first, for [buildReport].
  List<LinkEvent> get linkEvents => _linkLog.events;

  DateTime? _connectedAt;

  final StreamController<ClickButtonMask> _buttons =
      StreamController<ClickButtonMask>.broadcast();

  /// True once the handshake completed with encryption enabled.
  bool encrypted = false;

  /// True while a restart of the controller is in flight, so two frames that
  /// both announce it stopped do not restart it twice.
  bool _resetting = false;

  /// How many arming frames this link has written, for the heartbeat line.
  int _armingWrites = 0;

  /// Ceiling on one write, see [_tryWrite].
  static const Duration _writeTimeout = Duration(seconds: 5);

  /// Which pod of a pair the link is on, when the advertising data said.
  ///
  /// Two pods announce the same name and only the left one is locked to Zwift,
  /// so a rider told "use the right pod" had no way to check which one the
  /// application had actually found.
  ControllerSide? side;

  final Map<String, ControllerSide?> _sides = <String, ControllerSide?>{};

  ControllerKeyPair? _keyPair;
  ControllerCrypto? _crypto;
  BluetoothCharacteristic? _writeTarget;
  final List<StreamSubscription<List<int>>> _frameSubscriptions =
      <StreamSubscription<List<int>>>[];
  Timer? _supervision;
  final ControllerLinkWatchdog _watchdog = ControllerLinkWatchdog();

  /// What the link should do about its own age, so a controller that closes a
  /// session on a timer is restarted before the rider notices.
  final LinkPolicy _policy = const LinkPolicy();

  /// True once the plain handshake was written on this link.
  ///
  /// The encrypted request and the plain one are not the same question: a
  /// Click v2 answers the encrypted one with a bare `RideOn` echo and then
  /// stays silent, while the plain handshake is what makes it stream its
  /// buttons. A single echo therefore says nothing about the session.
  bool _plainHandshakeSent = false;

  /// Whole seconds elapsed since the link came up.
  int _secondsSinceConnect = 0;
  bool _reconnecting = false;

  /// Delay between two reconnection attempts.
  ///
  /// Three seconds is the delay `pizero_bikecomputer` uses against the same
  /// pod. A Click v2 that drops is not broken, it is asleep: the next press
  /// wakes it, and the application only has to be asking when it does.
  static const Duration reconnectDelay = Duration(seconds: 3);

  /// True while the rider wants a link, false once they pressed Disconnect.
  bool _keepLinked = false;
  Timer? _retry;
  int _attempts = 0;

  /// True when the last link died too soon to be a normal end of session.
  ///
  /// A Click v2 expects a fresh encryption context from Zwift about once a
  /// day; once it lapses, the pod stops sending button events roughly a minute
  /// after the link comes up. The interface must say so, because no amount of
  /// reconnecting repairs it and the rider needs to open Zwift once.
  bool needsZwiftRefresh = false;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  final List<ScanResult> _found = <ScanResult>[];

  /// Button states, emitted on every change.
  Stream<ClickButtonMask> get buttons => _buttons.stream;

  /// Devices discovered during the last scan.
  List<ScanResult> get found => List<ScanResult>.unmodifiable(_found);

  /// Callback invoked whenever the status or the device list changes.
  void Function()? onChanged;

  void _notify() => onChanged?.call();

  /// Scans for controllers advertising the expected service.
  ///
  /// Stops by itself after [timeout]; results accumulate in [found].
  Future<void> scan({Duration timeout = const Duration(seconds: 8)}) async {
    await _scanSubscription?.cancel();
    _found.clear();
    scanFoundNothing = false;
    status = ControllerStatus.scanning;
    error = null;
    _notify();

    _scanSubscription = FlutterBluePlus.onScanResults.listen(
      (List<ScanResult> results) {
        for (final ScanResult result in results) {
          if (!_looksLikeController(result)) continue;
          _sides[result.device.remoteId.str] = controllerSideFromAdvertisement(
            result.advertisementData.manufacturerData,
          );
          if (_found.every(
            (ScanResult r) => r.device.remoteId != result.device.remoteId,
          )) {
            _found.add(result);
          }
        }
        _notify();
      },
      onError: (Object e) {
        status = ControllerStatus.failed;
        error = explainControllerError(
          e,
          isWeb: kIsWeb,
          secureContext: Capabilities.webBluetoothPossible,
        );
        _notify();
      },
    );

    try {
      await FlutterBluePlus.startScan(
        // Never filtered by service. A service filter only matches what the
        // device puts in its advertising packet, and a controller that omits
        // it is simply invisible: that is not a device worth hiding, it is the
        // one the rider is pressing. Filtering moves to
        // [_looksLikeController], which reads both the announced services and
        // the name.
        withServices: const <Guid>[],
        // A page only ever receives the services it names here, so a browser
        // that asked for the vendor service alone could never show the battery
        // or the firmware: measured on the right pod on 2026-11-12, where the
        // same controller answered `180a` and `180f` on Windows and the web
        // report read "the controller exposes no 0x180a service". The three are
        // asked together, and the vendor one stays first because it is the only
        // one a controller is guaranteed to have.
        webOptionalServices: kIsWeb
            ? ControllerUuids.requested.map(Guid.new).toList()
            : const <Guid>[],
        timeout: timeout,
      );
    } catch (e) {
      status = ControllerStatus.failed;
      error = explainControllerError(
        e,
        isWeb: kIsWeb,
        secureContext: Capabilities.webBluetoothPossible,
      );
      _notify();
      return;
    }

    await Future<void>.delayed(timeout);
    scanFoundNothing = _found.isEmpty;
    status = ControllerStatus.idle;
    _notify();
  }

  /// Asks the host for a controller and connects to the one that came back.
  ///
  /// On a page the browser's chooser already is the choice: the rider picks a
  /// device, and asking for a second tap on *Connect* is one tap too many. On a
  /// host that scans a list itself this would connect to the first device it
  /// saw, which is why it is only used where the chooser exists.
  Future<void> scanAndConnect({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await scan(timeout: timeout);
    if (_found.isEmpty) return;
    await connect(_found.first.device);
  }

  /// Whether [result] can be the controller this application drives.
  ///
  /// The advertised service is the reliable signal, but a device that keeps it
  /// out of its advertising packet is still a controller: the name covers that
  /// case, and a wrong candidate costs one failed connection, not a session.
  static bool _looksLikeController(ScanResult result) {
    for (final Guid service in result.advertisementData.serviceUuids) {
      if (sameUuid(service.toString(), ControllerUuids.service)) return true;
    }
    final String name = result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : result.device.platformName;
    final String lower = name.toLowerCase();
    return lower.contains('zwift') || lower.contains('click');
  }

  /// Discovers the services, retrying while the controller service is absent.
  ///
  /// A connection is not a service table: some hosts, Windows first, answer
  /// with whatever the cache held at that instant. The retries are cheap and
  /// the alternative is a connection that reports a missing channel on a
  /// controller that has all of them.
  Future<List<BluetoothService>> _discoverControllerServices(
    BluetoothDevice target,
  ) async {
    List<BluetoothService> services = <BluetoothService>[];
    for (int attempt = 1; attempt <= 3; attempt++) {
      services = await target.discoverServices();
      final bool found = services.any(
        (BluetoothService service) =>
            sameUuid(service.uuid.toString(), ControllerUuids.service),
      );
      if (found) return services;
      if (attempt < 3) {
        await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
      }
    }
    return services;
  }

  /// Connects to [target], discovers the service and performs the handshake.
  Future<void> connect(BluetoothDevice target) async {
    status = ControllerStatus.connecting;
    error = null;
    needsUnlock = false;
    needsZwiftRefresh = false;
    _keepLinked = true;
    _notify();
    device = target;
    side = _sides[target.remoteId.str];

    try {
      await FlutterBluePlus.stopScan();
      await target.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
      // A connection call that returns is not a link. Measured on Windows on
      // 2026-11-12: after the pod went to sleep, `connect()` came back without
      // an error, the report announced `connected` at +0000.000, and the very
      // next discovery failed with `device is not connected` — a line that reads
      // like a protocol fault and is only a pod that is not there.
      if (!target.isConnected) {
        throw StateError(
          'the connection was accepted but no link came up: the controller is '
          'asleep or out of range',
        );
      }
      // The clock starts at the connection, not at the end of discovery: a
      // report that dates the subscriptions before the link existed cannot be
      // read.
      _connectedAt = DateTime.now();
      _frames.clear();
      _event('connected');
      // Windows answers the first discovery after a connection with a partial
      // table: the vendor service arrives on the second or third call. Asking
      // once reported "channels are missing" on a controller that had them.
      final List<BluetoothService> services = await _discoverControllerServices(
        target,
      );
      _event('services discovered: ${services.length}');

      BluetoothCharacteristic? asyncChannel;
      BluetoothCharacteristic? writeTarget;
      BluetoothCharacteristic? syncReply;
      for (final BluetoothService service in services) {
        if (!sameUuid(service.uuid.toString(), ControllerUuids.service)) {
          continue;
        }
        for (final BluetoothCharacteristic characteristic
            in service.characteristics) {
          final String uuid = characteristic.uuid.toString();
          if (sameUuid(uuid, ControllerUuids.asyncChannel)) {
            asyncChannel = characteristic;
          }
          if (sameUuid(uuid, ControllerUuids.syncRx)) {
            writeTarget = characteristic;
          }
          if (sameUuid(uuid, ControllerUuids.syncTx)) {
            syncReply = characteristic;
          }
        }
      }

      if (asyncChannel == null || writeTarget == null) {
        final String seen = services
            .map((BluetoothService s) => canonicalUuid(s.uuid.toString()))
            .join(', ');
        throw StateError(
          'controller channels are missing (services seen: '
          '${seen.isEmpty ? 'none' : seen})',
        );
      }
      _writeTarget = writeTarget;

      // Kept before the handshake: a link that fails the handshake is exactly
      // the one whose report is worth reading, so the tree cannot depend on the
      // link succeeding.
      gattTree = _describe(services);
      information = await _readDeviceInformation(services);

      // Buttons arrive on the asynchronous channel, the handshake reply on the
      // synchronous one: listening to both is the difference between a link
      // that works and a link that connects and says nothing.
      await asyncChannel.setNotifyValue(true);
      _event(
        'notify on 0002: ${asyncChannel.isNotifying ? 'accepted' : 'refused'}',
      );
      _frameSubscriptions.add(
        asyncChannel.onValueReceived.listen(
          (List<int> frame) => _onFrame(frame, asyncChannel!),
        ),
      );
      if (syncReply != null) {
        final BluetoothCharacteristic reply = syncReply;
        await reply.setNotifyValue(true);
        _event('notify on 0004: ${reply.isNotifying ? 'accepted' : 'refused'}');
        _frameSubscriptions.add(
          reply.onValueReceived.listen(
            (List<int> frame) => _onFrame(frame, reply),
          ),
        );
      }
      // Rebuilt once the subscriptions exist, so the tree states what is
      // actually notifying rather than what was advertised before.
      gattTree = _describe(services);
      _connectionSubscription = target.connectionState.listen((
        BluetoothConnectionState state,
      ) {
        if (state == BluetoothConnectionState.disconnected &&
            status != ControllerStatus.idle) {
          _noteLinkEnd();
          status = ControllerStatus.idle;
          _notify();
          _scheduleReconnect();
        }
      });

      // Ask for an encrypted session first; some firmware only answers the
      // plain handshake, which the supervision below sends after a delay.
      _keyPair = ControllerCrypto.generateKeyPair();
      _crypto = null;
      encrypted = false;
      _plainHandshakeSent = false;
      _secondsSinceConnect = 0;
      _watchdog.onConnected();
      // Through [_write], so the handshake request lands in the report: a link
      // that never answers is diagnosed from exactly these bytes.
      await _write(
        ControllerHandshake.encryptedRequest(_keyPair!.publicKeyBytes),
      );

      _supervision?.cancel();
      _supervision = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _supervise(),
      );

      status = ControllerStatus.ready;
      _attempts = 0;
      _notify();
    } catch (e) {
      status = ControllerStatus.failed;
      error = explainControllerError(
        e,
        isWeb: kIsWeb,
        secureContext: Capabilities.webBluetoothPossible,
      );
      _notify();
    }
  }

  /// Feeds the watchdog and carries out what it asks for.
  void _supervise() {
    _secondsSinceConnect++;
    // Every ten seconds, one line saying what the loop believes. A loop that
    // stops writing while the status still says "connected" leaves a report
    // that cannot be read; this line is what distinguishes the two.
    if (_secondsSinceConnect % 10 == 0) {
      final Duration? age = _connectedAt == null
          ? null
          : DateTime.now().difference(_connectedAt!);
      _event(
        'supervising: ${age?.inSeconds ?? '-'} s link, '
        '$_armingWrites arming writes, resetting: $_resetting',
      );
    }
    final ControllerLinkAction? action = _watchdog.onElapsed(
      const Duration(seconds: 1),
    );
    switch (action) {
      case null:
        break;
      case ControllerLinkAction.sendPlainHandshake:
        unawaited(_startPlainSession());
      case ControllerLinkAction.needsUnlock:
        needsUnlock = true;
        _notify();
      case ControllerLinkAction.sendKeepalive:
        // `FF 04 00`, the frame that arms the session, rather than a bare
        // `RideOn`: a second marker looks like a new handshake, and a pod that
        // is already open does not need one. Only in a plain session — an
        // encrypted one answers frames by itself.
        if (_crypto == null) unawaited(_armSession());
    }

    // Restart the controller while it is still answering, not after it is gone:
    // a pod that has closed its session is asleep and refuses every connection.
    // The frame matters as much as the moment — `clickbridge`'s periodic reset
    // writes `0x18` first, and that is what makes the unit come back; a plain
    // disconnection and reconnection leaves it in the state it died in.
    if (_connectedAt != null &&
        _policy.wantsRestart(DateTime.now().difference(_connectedAt!))) {
      unawaited(_restartController('link age'));
      return;
    }

    // A Click v2 answers the encrypted request with a bare `RideOn` echo and
    // then waits for the rest of an exchange that will never come: it streams
    // its buttons only after the plain handshake. The watchdog cannot ask for
    // that fallback, because a frame did arrive and it reads a frame as an
    // answer; the criterion is the derived session, not the bytes.
    if (_crypto == null && !_plainHandshakeSent && _secondsSinceConnect >= 3) {
      unawaited(_startPlainSession());
    }
  }

  /// Opens a plain session: the `RideOn` marker, then the two frames that
  /// complete the activation.
  ///
  /// Measured on Windows by `zwiftboard` (MIT): a Click v2 streams its buttons
  /// only after the full exchange, and the plain handshake alone leaves it in a
  /// state where it answers for a while and then stops.
  Future<void> _startPlainSession() async {
    if (_plainHandshakeSent) return;
    _plainHandshakeSent = true;
    _watchdog.onPlainHandshakeSent();
    _event('opening the plain session');
    for (final List<int> frame in ControllerHandshake.activationSequence()) {
      final bool sent = await _tryWrite(frame);
      if (!sent) {
        // A failed write is the only observable sign that the session ended.
        _event('activation write failed: ${_hexOf(frame)}');
        _scheduleReconnect();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    // The opening is not finished at `RideOn 02 03`: the controller waits for
    // `FF 04 00` before it holds the session open.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final bool armed = await _tryWrite(ControllerHandshake.startAfterOpening);
    _event('plain session opened${armed ? '' : ', arming frame refused'}');
  }

  /// The bytes of [frame], for an event line.
  static String _hexOf(List<int> frame) =>
      frame.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  /// Arms the plain session with the frame the controller expects after the
  /// opening, and again when the watchdog asks for a keepalive.
  ///
  /// `clickbridge`, which has sessions lasting a whole ride on this firmware,
  /// sends `RideOn 02 03` and then `FF 04 00`; this application sent the opening
  /// alone and lost the link at 57-62 s, with a bare `RideOn` every three
  /// seconds failing to hold it.
  Future<void> _armSession() async {
    _armingWrites++;
    final bool sent = await _tryWrite(ControllerHandshake.startAfterOpening);
    if (sent) return;
    // A refused write is the disconnect signal this stack gives on time: the
    // `disconnected` event arrives late, or never. Measured on the right pod on
    // 2026-11-12: the first refusal came at +62 s and the first reconnection at
    // +98 s, because every failing keepalive re-armed the retry timer that the
    // previous one had already set. Reconnecting from here removes the wait.
    _event('arming write failed: ${error ?? 'no reason given'}');
    _noteLinkEnd();
    _connectedAt = null;
    await _attemptReconnect();
  }

  Future<void> _write(List<int> frame) async {
    await _tryWrite(frame);
  }

  /// Restarts a controller that has announced it stopped talking.
  ///
  /// The frame is `0x18` on the write characteristic, the one `clickbridge`
  /// sends before reconnecting. It is the only way back into a pod that has
  /// closed its session: such a pod is asleep and refuses every connection until
  /// a button wakes it, which is exactly what a rider must not have to do
  /// mid-ride.
  Future<void> _restartController(String reason) async {
    if (_resetting) return;
    _resetting = true;
    _event('controller stopped talking ($reason): restarting it');
    final bool reset = await _tryWrite(ControllerHandshake.reset);
    _event('reset frame ${reset ? 'accepted' : 'refused ($error)'}');
    await Future<void>.delayed(const Duration(seconds: 1));
    _connectedAt = null;
    _resetting = false;
    await _attemptReconnect();
  }

  /// Writes [frame], and says whether the link accepted it.
  ///
  /// The boolean is what the supervision acts on: a write the controller does
  /// not take is the only reliable sign that the session ended, since an idle
  /// controller is silent by design.
  Future<bool> _tryWrite(List<int> frame) async {
    _record(frame, FrameDirection.outbound, _writeTarget?.uuid.toString());
    try {
      // Bounded: a WinRT write to a device that has gone away can hang for ever,
      // and this loop is what carries the whole link. Measured on 2026-11-12: a
      // session that stopped being written at +23 s and reported nothing after
      // it, with the status still saying "connected".
      await _writeTarget?.write(frame).timeout(_writeTimeout);
      return true;
    } on TimeoutException {
      error = 'the write did not return within ${_writeTimeout.inSeconds} s';
      _notify();
      return false;
    } catch (e) {
      error = explainControllerError(
        e,
        isWeb: kIsWeb,
        secureContext: Capabilities.webBluetoothPossible,
      );
      _notify();
      return false;
    }
  }

  /// Notes how long the link lasted, for the one failure the rider must fix.
  void _noteLinkEnd() {
    final DateTime? start = _connectedAt;
    if (start == null) return;
    final Duration lived = DateTime.now().difference(start);
    _event(
      'link ended after ${lived.inSeconds} s, '
      '${_frames.frames.length} frames kept',
    );
    // A Click v2 that dies inside two minutes is telling the host that its
    // encryption context lapsed, not that the radio is bad: a healthy session
    // ends with the rider, hours later, or with a press on Disconnect.
    needsZwiftRefresh = lived < const Duration(seconds: 120);
  }

  /// Records one event of the link itself, stamped against the link's start.
  ///
  /// These are what a dropout is made of: the moment the subscriptions were
  /// accepted, the opening that was written, the second the session ended. The
  /// frames alone could not say why the Windows build lost its controller at
  /// ~57 s while the same code held it in a browser.
  void _event(String label) {
    final DateTime? start = _connectedAt;
    final Duration elapsed = start == null
        ? Duration.zero
        : DateTime.now().difference(start);
    _linkLog.add(LinkEvent(elapsed: elapsed, label: label));
  }

  /// Programmes the next attempt, without ever giving up.
  ///
  /// One attempt is not a policy. The pod sleeps, refuses one connection and
  /// takes the next; an application that stops after a single refusal hands the
  /// rider back to Scan and Connect in the middle of a ride.
  void _scheduleReconnect({Duration delay = reconnectDelay}) {
    if (!_keepLinked || device == null) return;
    _retry?.cancel();
    _retry = Timer(delay, () => unawaited(_attemptReconnect()));
  }

  Future<void> _attemptReconnect() async {
    final BluetoothDevice? target = device;
    if (!_keepLinked || target == null || _reconnecting) return;
    _reconnecting = true;
    _event('reconnect attempt ${_attempts + 1}');
    status = ControllerStatus.connecting;
    error = 'the controller stopped answering, reconnecting';
    _notify();
    try {
      await _clearLink();
      // A device object that has already seen a session end keeps a dead GATT
      // session on Windows: the reconnect then returns without a link and the
      // discovery fails with `device is not connected`, forever, on the same
      // object. Measured on the right pod on 2026-11-12, where the browser — a
      // fresh object each time — reconnected on its own while this path could
      // not. A handle rebuilt from the identifier carries no such history.
      final BluetoothDevice fresh = BluetoothDevice.fromId(target.remoteId.str);
      device = fresh;
      _event('rebuilt the device handle from ${target.remoteId}');
      await connect(fresh);
      if (status == ControllerStatus.ready) {
        _attempts = 0;
        _event('reconnected');
        return;
      }
      _attempts++;
      _event('reconnect refused: ${error ?? 'no answer'}');
      // Every third refusal, look for the pod instead of dialling an address
      // that no longer answers: a sleeping controller comes back through its
      // advertising, and a wake-up press is what puts it there.
      if (_attempts % 3 == 0) {
        _event('rescanning, three refusals in a row');
        await _rescan(target);
      }
    } catch (e) {
      _attempts++;
      _event('reconnect threw: $e');
    } finally {
      _reconnecting = false;
    }
    _scheduleReconnect();
  }

  /// Scans again and picks the controller out of what answered.
  Future<void> _rescan(BluetoothDevice previous) async {
    await scan(timeout: const Duration(seconds: 8));
    final String wanted = previous.remoteId.toString();
    for (final ScanResult result in _found) {
      if (result.device.remoteId.toString() == wanted) return;
    }
    if (_found.isNotEmpty) device = _found.first.device;
  }

  /// Appends [bytes] to the ring, timed from the moment the link was made.
  void _record(
    List<int> bytes,
    FrameDirection direction,
    String? characteristic,
  ) {
    final DateTime? start = _connectedAt;
    if (start == null) return;
    _frames.add(
      FrameRecord(
        elapsed: DateTime.now().difference(start),
        characteristic: characteristic ?? 'unknown',
        direction: direction,
        bytes: List<int>.unmodifiable(bytes),
      ),
    );
  }

  /// Turns what the platform returned into a comparable description.
  static List<GattServiceInfo> _describe(List<BluetoothService> services) {
    final List<GattServiceInfo> described = <GattServiceInfo>[];
    for (final BluetoothService service in services) {
      described.add(
        GattServiceInfo(
          uuid: service.uuid.toString(),
          characteristics: <GattCharacteristicInfo>[
            for (final BluetoothCharacteristic c in service.characteristics)
              GattCharacteristicInfo(
                uuid: c.uuid.toString(),
                properties: <String>[
                  if (c.properties.read) 'read',
                  if (c.properties.write) 'write',
                  if (c.properties.writeWithoutResponse) 'writeWithoutResponse',
                  if (c.properties.notify) 'notify',
                  if (c.properties.indicate) 'indicate',
                ],
                notifying: c.isNotifying,
              ),
          ],
        ),
      );
    }
    return List<GattServiceInfo>.unmodifiable(described);
  }

  /// Reads the Device Information service, field by field.
  ///
  /// Every read is guarded on its own: a device that exposes `0x180a` but
  /// refuses one characteristic must still give the other four. A missing
  /// firmware string is a gap in a report; an exception here would cost the
  /// whole report.
  static Future<DeviceInformation> _readDeviceInformation(
    List<BluetoothService> services,
  ) async {
    BluetoothService? info;
    for (final BluetoothService service in services) {
      if (sameUuid(service.uuid.toString(), '180a')) info = service;
    }
    if (info == null) return const DeviceInformation();

    Future<String?> read(String uuid) async {
      for (final BluetoothCharacteristic c in info!.characteristics) {
        if (!sameUuid(c.uuid.toString(), uuid)) continue;
        try {
          final List<int> value = await c.read();
          final String text = utf8.decode(value, allowMalformed: true);
          final String trimmed = text.replaceAll('\u0000', '').trim();
          return trimmed.isEmpty ? null : trimmed;
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    return DeviceInformation(
      manufacturer: await read('2a29'),
      model: await read('2a24'),
      serial: await read('2a25'),
      firmware: await read('2a26'),
      hardware: await read('2a27'),
    );
  }

  /// Builds the report a rider pastes into an issue.
  ///
  /// [appVersion] is passed in rather than read here: this class has no idea
  /// which build it runs in, and a version guessed wrong is worse than none.
  DeviceReport buildReport(String appVersion) {
    return DeviceReport(
      generatedAt: DateTime.now(),
      appVersion: appVersion,
      host: Capabilities.hostName,
      deviceName: device?.platformName,
      deviceId: device?.remoteId.toString(),
      side: side,
      status: status.name,
      // Nothing to claim about encryption before a link exists: the field is a
      // fact about a session, and "plain" over an idle application reads as one.
      encrypted: device == null ? null : encrypted,
      needsUnlock: needsUnlock,
      batteryPercent: batteryPercent,
      error: error,
      information: information,
      services: gattTree,
      frames: _frames.frames,
      events: _linkLog.events,
    );
  }

  void _onFrame(List<int> frame, BluetoothCharacteristic source) {
    // Recorded before any interpretation: a frame the parser does not recognise
    // is precisely what a maintainer needs to see.
    _record(frame, FrameDirection.inbound, source.uuid.toString());
    if (frame.isEmpty) return;

    // The controller announces its own end (`FF 05 00 EA 05` or `... FA 05`)
    // before it goes quiet, which is the one moment it can still be restarted
    // from here. Waiting for the stack to notice costs the rest of the ride: a
    // pod that has closed its session is asleep and refuses every connection.
    if (ControllerSignals.stopped(frame)) {
      unawaited(_restartController(_hexOf(frame)));
      return;
    }

    // Handshake acknowledgement: RideOn, optionally followed by a public key.
    if (frame.length >= ControllerHandshake.rideOn.length) {
      bool startsWithRideOn = true;
      for (int i = 0; i < ControllerHandshake.rideOn.length; i++) {
        if (frame[i] != ControllerHandshake.rideOn[i]) {
          startsWithRideOn = false;
          break;
        }
      }
      if (startsWithRideOn) {
        _watchdog.onFrame();
        final List<int>? deviceKey = ControllerHandshake.parseDevicePublicKey(
          frame,
        );
        if (deviceKey != null && _keyPair != null) {
          _crypto = ControllerCrypto.derive(
            devicePublicKeyBytes: deviceKey,
            localKeyPair: _keyPair!,
          );
          encrypted = true;
        }
        status = ControllerStatus.ready;
        _notify();
        return;
      }
    }

    _watchdog.onFrame();

    List<int> payload = frame;
    if (_crypto != null) {
      final List<int>? decrypted = _crypto!.decryptFrame(frame);
      if (decrypted == null) return;
      payload = decrypted;
    }

    final ControllerMessage? message = ControllerCodec.decode(payload);
    if (message is ClickMessage) {
      _buttons.add(message.buttons);
    } else if (message is BatteryMessage) {
      batteryPercent = message.percent;
      _notify();
    }
  }

  Future<void> _clearLink() async {
    _supervision?.cancel();
    _supervision = null;
    for (final StreamSubscription<List<int>> subscription
        in _frameSubscriptions) {
      await subscription.cancel();
    }
    _frameSubscriptions.clear();
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _crypto = null;
    _keyPair = null;
    _writeTarget = null;
    encrypted = false;
  }

  /// Closes the connection and releases the subscriptions.
  Future<void> disconnect() async {
    // The rider asked for this: stop the retry loop before it climbs back.
    _keepLinked = false;
    _retry?.cancel();
    _retry = null;
    _attempts = 0;
    needsZwiftRefresh = false;
    await _clearLink();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      await device?.disconnect();
    } catch (_) {
      // The device may already be gone; nothing to repair.
    }
    device = null;
    status = ControllerStatus.idle;
    batteryPercent = null;
    needsUnlock = false;
    _notify();
  }

  /// Releases every resource.
  Future<void> dispose() async {
    await disconnect();
    await _buttons.close();
  }
}

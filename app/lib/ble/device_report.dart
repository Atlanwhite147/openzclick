/// A snapshot of a controller link, written to be pasted into an issue.
///
/// Most of the bridge is written on a machine with no Bluetooth radio, so most
/// rules run against a fake controller. What closes that gap is not a description of a
/// dropout — descriptions arrive incomplete and unreproducible — but the raw
/// material: which services and characteristics the device actually exposes,
/// what its firmware calls itself, and the last frames it sent before going
/// quiet.
///
/// This file holds the shape of that material and the text it becomes. It is
/// deliberately free of any Bluetooth dependency: a report is built from plain
/// values, so the formatting is tested on the host and the same text is produced
/// on every platform.
library;

import 'package:openzclick_core/openzclick_core.dart';

import 'bluetooth_uuid.dart';

/// Where a frame went.
enum FrameDirection {
  /// Received from the controller.
  inbound,

  /// Written to the controller.
  outbound,
}

/// One event of the link itself, with the moment it happened.
///
/// Separate from a frame because a frame is what the controller said, and these
/// are what the host and the link did: a subscription accepted or refused, a
/// session opened in the plain form, a link that ended after fifty-seven
/// seconds. A dropout is explained by that sequence, not by the last bytes.
class LinkEvent {
  /// Creates an event.
  const LinkEvent({required this.elapsed, required this.label});

  /// Time since the link was established.
  final Duration elapsed;

  /// What happened, in the code's own words.
  final String label;

  @override
  String toString() => '[$elapsed] $label';
}

/// One frame, as it appeared on the wire.
class FrameRecord {
  /// Creates a record.
  const FrameRecord({
    required this.elapsed,
    required this.characteristic,
    required this.direction,
    required this.bytes,
    this.repeats = 1,
  });

  /// Time since the link was established.
  ///
  /// Relative on purpose: an absolute clock in the report tells a reader nothing
  /// and leaks when and where the rider was, which is not needed to debug a
  /// handshake.
  final Duration elapsed;

  /// Characteristic the frame travelled on, in canonical form.
  final String characteristic;

  /// Whether the controller sent it or the bridge wrote it.
  final FrameDirection direction;

  /// Bytes, exactly as they were exchanged.
  final List<int> bytes;

  /// How many times this frame arrived unchanged, this one included.
  ///
  /// A Click v2 streams its mask about ten times a second whether or not a
  /// button is involved, so forty raw frames cover four seconds of a ride. A
  /// report that keeps them cannot show what a rider did a minute ago; one that
  /// collapses a run of identical bytes covers minutes and still shows every
  /// change of state, which is the only part worth reading.
  final int repeats;

  /// Whether [other] carries the same bytes in the same direction on the same
  /// channel, which is what makes two frames one record.
  bool follows(FrameRecord other) {
    if (direction != other.direction) return false;
    if (characteristic != other.characteristic) return false;
    if (bytes.length != other.bytes.length) return false;
    for (int i = 0; i < bytes.length; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  /// This frame seen [count] times in total, timed from its first arrival.
  FrameRecord repeated(int count) => FrameRecord(
    elapsed: elapsed,
    characteristic: characteristic,
    direction: direction,
    bytes: bytes,
    repeats: count,
  );
}

/// A characteristic as the device describes it.
class GattCharacteristicInfo {
  /// Creates a description.
  const GattCharacteristicInfo({
    required this.uuid,
    required this.properties,
    this.notifying = false,
  });

  /// Canonical UUID.
  final String uuid;

  /// Flags the device advertises, already spelled out (`read`, `notify`...).
  final List<String> properties;

  /// True when notifications were enabled on this characteristic.
  final bool notifying;
}

/// A service as the device describes it.
class GattServiceInfo {
  /// Creates a description.
  const GattServiceInfo({required this.uuid, required this.characteristics});

  /// Canonical UUID.
  final String uuid;

  /// Characteristics discovered under it.
  final List<GattCharacteristicInfo> characteristics;
}

/// Strings read from the Device Information service, when the device has one.
class DeviceInformation {
  /// Creates the set.
  const DeviceInformation({
    this.manufacturer,
    this.model,
    this.serial,
    this.firmware,
    this.hardware,
  });

  /// Manufacturer name (`0x2A29`).
  final String? manufacturer;

  /// Model number (`0x2A24`).
  final String? model;

  /// Serial number (`0x2A25`).
  final String? serial;

  /// Firmware revision (`0x2A26`), the one field a bug report is useless without.
  final String? firmware;

  /// Hardware revision (`0x2A27`).
  final String? hardware;

  /// True when at least one field was read.
  bool get isEmpty =>
      manufacturer == null &&
      model == null &&
      serial == null &&
      firmware == null &&
      hardware == null;
}

/// Everything an issue needs to be reproducible.
class DeviceReport {
  /// Creates a report.
  const DeviceReport({
    required this.generatedAt,
    required this.appVersion,
    required this.host,
    this.deviceName,
    this.deviceId,
    this.side,
    this.status,
    this.encrypted,
    this.needsUnlock,
    this.batteryPercent,
    this.error,
    this.information = const DeviceInformation(),
    this.services = const <GattServiceInfo>[],
    this.frames = const <FrameRecord>[],
    this.events = const <LinkEvent>[],
  });

  /// When the report was taken.
  final DateTime generatedAt;

  /// Version of the application that produced it.
  final String appVersion;

  /// Host name, from [Capabilities.hostName] on the calling side.
  final String host;

  /// Advertised name, often the only way to tell a v1 from a v2.
  final String? deviceName;

  /// Platform identifier, which differs from the name.
  final String? deviceId;

  /// Which pod of a pair this is, when the advertising data said.
  ///
  /// Two pods answer to the same name, and only the left one is locked to
  /// Zwift: a report that cannot name the side leaves the reader unable to tell
  /// a protocol fault from the wrong pod in their hand.
  final ControllerSide? side;

  /// Last link status, in the code's own words.
  final String? status;

  /// Whether the session ended up encrypted.
  final bool? encrypted;

  /// Whether the controller stayed silent after the handshake.
  final bool? needsUnlock;

  /// Battery level, when the device reports one.
  final int? batteryPercent;

  /// Last error, verbatim.
  final String? error;

  /// Why no Device Information string was read, in the terms of the host that
  /// looked.
  ///
  /// The web build gets this wrong in a way that costs a maintainer an hour: a
  /// page only ever receives the services it named when it opened the link, so
  /// an absent `180a` says nothing about the controller. Reporting it as "the
  /// controller exposes no 0x180a service" sends the reader looking for a
  /// firmware difference that does not exist — measured with the right pod on
  /// 2026-11-12, where the same pod answered `180a` on Windows and appeared
  /// without it in the browser.
  String get missingInformationReason => host == 'web'
      ? '  none: the page did not ask for 0x180a, and Web Bluetooth returns only '
            'the services a page names'
      : '  none: no answer on 0x180a';

  /// Device Information strings.
  final DeviceInformation information;

  /// Discovered services, in the order the platform returned them.
  final List<GattServiceInfo> services;

  /// Frames exchanged, oldest first.
  final List<FrameRecord> frames;

  /// What happened to the link itself, oldest first.
  ///
  /// Frames say what the controller said; these say what the host and the link
  /// did around it, which is what a dropout is made of: when notifications were
  /// enabled, whether they were accepted, when the session opened in the plain
  /// form, when the link ended and how long it had lived. Measured need: the
  /// Windows build lost its controller at ~57 s and the report could only say
  /// `device is not connected`, with no way to tell a refused subscription from
  /// a link the pod closed.
  final List<LinkEvent> events;

  /// Renders the report as plain text.
  ///
  /// Plain text, not JSON: it is read by a human first and pasted into a thread
  /// second, and a wall of JSON gets skimmed. Anything a parser needs is still
  /// there, one fact per line.
  String render() {
    final StringBuffer out = StringBuffer();
    out.writeln('openzclick device report');
    out.writeln('  taken    ${_iso(generatedAt)}');
    out.writeln('  version  $appVersion');
    out.writeln('  host     $host');

    out.writeln('controller');
    out.writeln('  name     ${deviceName ?? 'unknown'}');
    out.writeln('  id       ${deviceId ?? 'unknown'}');
    if (status != null) out.writeln('  status   $status');
    if (encrypted != null) {
      out.writeln('  session  ${encrypted! ? 'encrypted' : 'plain'}');
    }
    if (needsUnlock == true) {
      out.writeln('  unlock   silent after the handshake');
    }
    if (side != null) out.writeln('  side     ${controllerSideLabel(side)}');
    if (batteryPercent != null) out.writeln('  battery  $batteryPercent %');
    if (error != null && error!.isNotEmpty) out.writeln('  error    $error');

    if (!information.isEmpty) {
      out.writeln('device information');
      _field(out, 'manufacturer', information.manufacturer);
      _field(out, 'model', information.model);
      _field(out, 'serial', information.serial);
      _field(out, 'firmware', information.firmware);
      _field(out, 'hardware', information.hardware);
    } else {
      out.writeln('device information');
      out.writeln(missingInformationReason);
    }

    out.writeln('gatt tree (${services.length} services)');
    if (services.isEmpty) {
      out.writeln('  none discovered');
    }
    // Every identifier is reduced to its canonical form, because the same
    // service comes back as `fc82` under WinRT and as the full 128-bit string on
    // Android and iOS: a report a maintainer cannot compare across hosts is a
    // report they have to decode first.
    for (final GattServiceInfo service in services) {
      out.writeln('  service ${canonicalUuid(service.uuid)}');
      for (final GattCharacteristicInfo c in service.characteristics) {
        final String flags = c.properties.isEmpty
            ? ''
            : ' [${c.properties.join(', ')}]';
        final String notifying = c.notifying ? ' notifying' : '';
        out.writeln(
          '    characteristic ${canonicalUuid(c.uuid)}$flags$notifying',
        );
      }
    }

    out.writeln('frames (${frames.length}, oldest first)');
    if (frames.isEmpty) {
      out.writeln('  none: the link exchanged nothing');
    }
    for (final FrameRecord frame in frames) {
      final String arrow = frame.direction == FrameDirection.inbound
          ? '<-'
          : '->';
      final String repeated = frame.repeats > 1 ? '  x${frame.repeats}' : '';
      out.writeln(
        '  ${_elapsed(frame.elapsed)} $arrow '
        '${canonicalUuid(frame.characteristic)} ${_hex(frame.bytes)}$repeated',
      );
    }

    out.writeln('link (${events.length}, oldest first)');
    if (events.isEmpty) {
      out.writeln('  none: nothing was recorded about the link itself');
    }
    for (final LinkEvent event in events) {
      out.writeln('  ${_elapsed(event.elapsed)} ${event.label}');
    }
    return out.toString();
  }

  static void _field(StringBuffer out, String label, String? value) {
    if (value == null || value.isEmpty) return;
    out.writeln('  ${label.padRight(12)} $value');
  }

  /// Milliseconds with three digits, which is the resolution handshakes need.
  static String _elapsed(Duration d) {
    final int ms = d.inMilliseconds;
    final String sign = ms < 0 ? '-' : '+';
    final int abs = ms.abs();
    final String secs = (abs ~/ 1000).toString().padLeft(4, '0');
    final String millis = (abs % 1000).toString().padLeft(3, '0');
    return '$sign$secs.$millis';
  }

  static String _hex(List<int> bytes) =>
      bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  static String _iso(DateTime t) =>
      '${t.toUtc().toIso8601String().split('.').first}Z';
}

/// Keeps the last [capacity] frames of a link.
///
/// A dropout is explained by what came just before it, not by the whole ride: a
/// ring buffer keeps the report short enough to paste in a thread and still
/// holds the moment that matters.
class FrameRing {
  /// Creates a ring holding at most [capacity] frames.
  FrameRing({this.capacity = 40})
    : assert(capacity > 0, 'a ring that holds nothing reports nothing');

  /// Maximum number of frames kept.
  final int capacity;

  final List<FrameRecord> _frames = <FrameRecord>[];

  /// Frames currently held, oldest first.
  List<FrameRecord> get frames => List<FrameRecord>.unmodifiable(_frames);

  /// Adds [frame], dropping the oldest beyond [capacity].
  ///
  /// A frame identical to the one before it does not take a new slot: its
  /// predecessor's repeat count is incremented instead. The controller streams
  /// its resting mask ten times a second, so without this the ring holds a few
  /// seconds of a ride and the presses a rider reports have already scrolled
  /// out by the time they copy the report.
  void add(FrameRecord frame) {
    final FrameRecord? last = _frames.isEmpty ? null : _frames.last;
    if (last != null && frame.follows(last)) {
      _frames[_frames.length - 1] = last.repeated(last.repeats + 1);
      return;
    }
    _frames.add(frame);
    if (_frames.length > capacity) {
      _frames.removeRange(0, _frames.length - capacity);
    }
  }

  /// Forgets everything, on each new link.
  void clear() => _frames.clear();
}

/// Keeps the last [capacity] events of a link, oldest first.
///
/// A ring, not a log: the interesting part of a dropout is the minute before it,
/// and an unbounded list would make the report too long to paste.
class LinkLog {
  /// Creates a log holding at most [capacity] events.
  LinkLog({this.capacity = 30})
    : assert(capacity > 0, 'a log that holds nothing reports nothing');

  /// Maximum number of events kept.
  final int capacity;

  final List<LinkEvent> _events = <LinkEvent>[];

  /// Events currently held, oldest first.
  List<LinkEvent> get events => List<LinkEvent>.unmodifiable(_events);

  /// Adds [event], dropping the oldest beyond [capacity].
  void add(LinkEvent event) {
    _events.add(event);
    if (_events.length > capacity) {
      _events.removeRange(0, _events.length - capacity);
    }
  }

  /// Forgets everything, on each new link.
  void clear() => _events.clear();
}

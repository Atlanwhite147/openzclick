import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/ble/device_report.dart';

DeviceReport report({
  DeviceInformation information = const DeviceInformation(),
  List<GattServiceInfo> services = const <GattServiceInfo>[],
  List<FrameRecord> frames = const <FrameRecord>[],
  String? deviceName = 'Zwift Click',
  String? status = 'ready',
  bool? encrypted = true,
  bool? needsUnlock = false,
  int? battery = 87,
  String? error,
}) {
  return DeviceReport(
    generatedAt: DateTime.utc(2026, 11, 4, 12, 30, 15),
    appVersion: '0.3.0+3',
    host: 'linux',
    deviceName: deviceName,
    deviceId: 'AA:BB:CC:DD:EE:FF',
    status: status,
    encrypted: encrypted,
    needsUnlock: needsUnlock,
    batteryPercent: battery,
    error: error,
    information: information,
    services: services,
    frames: frames,
  );
}

void main() {
  group('a report a maintainer can reproduce from', () {
    test('names the build, the host and the device', () {
      final String text = report().render();
      expect(text, contains('openzclick device report'));
      expect(text, contains('version  0.3.0+3'));
      expect(text, contains('host     linux'));
      expect(text, contains('Zwift Click'));
      expect(text, contains('AA:BB:CC:DD:EE:FF'));
      expect(text, contains('encrypted'));
      expect(text, contains('87 %'));
    });

    test('carries the firmware, the field a bug report cannot do without', () {
      // The same model behaves differently across revisions, and riders rarely
      // know which one they have.
      final String text = report(
        information: const DeviceInformation(
          manufacturer: 'Zwift',
          model: 'Click',
          firmware: '1.0.4',
        ),
      ).render();
      expect(text, contains('firmware     1.0.4'));
      expect(text, contains('manufacturer Zwift'));
    });

    test('says when the device has no Device Information service', () {
      // Silence would read as "the report is broken"; the absence is itself the
      // finding.
      expect(report().render(), contains('no answer on 0x180a'));
    });

    test('the browser is not blamed on the device it could not see', () {
      // Measured on the right pod: the same controller answered `180a` over
      // Windows and listed none in the browser, because a page only receives
      // the services it named. Reporting "the controller exposes no 0x180a"
      // sends a maintainer after a firmware difference that does not exist.
      final DeviceReport web = DeviceReport(
        generatedAt: DateTime.utc(2026, 11, 12, 12, 36, 28),
        appVersion: '0.3.0+3',
        host: 'web',
        deviceName: 'Zwift Click',
        status: 'ready',
      );
      final String text = web.render();
      expect(text, contains('the page did not ask for 0x180a'));
      expect(text, isNot(contains('the controller exposes no 0x180a')));
    });

    test('spells out the GATT tree, properties included', () {
      final String text = report(
        services: const <GattServiceInfo>[
          GattServiceInfo(
            uuid: '0000fc82-0000-1000-8000-00805f9b34fb',
            characteristics: <GattCharacteristicInfo>[
              GattCharacteristicInfo(
                uuid: '00000002-0000-1000-8000-00805f9b34fb',
                properties: <String>['read', 'notify'],
                notifying: true,
              ),
            ],
          ),
        ],
      ).render();
      expect(text, contains('service fc82'));
      expect(text, contains('characteristic 0002 [read, notify] notifying'));
    });

    test('reduces identifiers, so two hosts produce comparable lines', () {
      // Measured on a Click v2: WinRT reports the vendor service as `fc82`
      // while Android and iOS return the full 128-bit form. A report that cannot
      // be compared across hosts has to be decoded first.
      final String winrt = report(
        services: const <GattServiceInfo>[
          GattServiceInfo(uuid: 'fc82', characteristics: []),
        ],
      ).render();
      final String android = report(
        services: const <GattServiceInfo>[
          GattServiceInfo(
            uuid: '0000fc82-0000-1000-8000-00805f9b34fb',
            characteristics: [],
          ),
        ],
      ).render();
      expect(winrt, contains('service fc82'));
      expect(android, contains('service fc82'));
    });

    test('shows each frame with its direction and its time', () {
      final String text = report(
        // The caller's order is kept: [FrameRing] is what guarantees that the
        // frames arrive oldest first.
        frames: const <FrameRecord>[
          FrameRecord(
            elapsed: Duration(milliseconds: 41),
            characteristic: '00000001-0000-1000-8000-00805f9b34fb',
            direction: FrameDirection.outbound,
            bytes: <int>[0x52, 0x69],
          ),
          FrameRecord(
            elapsed: Duration(milliseconds: 312),
            characteristic: '00000002-0000-1000-8000-00805f9b34fb',
            direction: FrameDirection.inbound,
            bytes: <int>[0x1a, 0x02, 0x00],
          ),
        ],
      ).render();
      expect(text, contains('+0000.312 <- 0002 1a 02 00'));
      expect(text, contains('+0000.041 -> 0001 52 69'));
      // Oldest first: a dropout is explained by what came before it.
      expect(text.indexOf('+0000.041'), lessThan(text.indexOf('+0000.312')));
    });

    test('an empty link says so instead of showing a bare heading', () {
      final String text = report().render();
      expect(text, contains('gatt tree (0 services)'));
      expect(text, contains('frames (0, oldest first)'));
      expect(text, contains('the link exchanged nothing'));
    });

    test('the link events are the sequence a dropout is read from', () {
      // Measured on the Windows build on 2026-11-12: the report could only say
      // `device is not connected`, which cannot distinguish a refused
      // subscription from a link the pod closed. The events say which.
      final String text = DeviceReport(
        generatedAt: DateTime.utc(2026, 11, 12, 13, 17, 27),
        appVersion: '0.3.0+3',
        host: 'windows',
        deviceName: 'Zwift Click',
        status: 'ready',
        events: const <LinkEvent>[
          LinkEvent(elapsed: Duration.zero, label: 'connected'),
          LinkEvent(
            elapsed: Duration(milliseconds: 240),
            label: 'notify on 0002: refused',
          ),
          LinkEvent(
            elapsed: Duration(seconds: 57, milliseconds: 412),
            label: 'link ended after 57 s, 19 frames kept',
          ),
        ],
      ).render();
      expect(text, contains('link (3, oldest first)'));
      expect(text, contains('+0000.000 connected'));
      expect(text, contains('+0000.240 notify on 0002: refused'));
      expect(text, contains('+0057.412 link ended after 57 s'));
      expect(
        text.indexOf('notify on 0002'),
        lessThan(text.indexOf('link ended')),
        reason: 'oldest first, or the sequence reads backwards',
      );
    });

    test('a log with no events says so rather than showing a bare heading', () {
      expect(
        report().render(),
        contains('nothing was recorded about the link'),
      );
    });

    test('a device that stayed silent is flagged in words', () {
      final String text = report(needsUnlock: true, status: 'ready').render();
      expect(text, contains('unlock   silent after the handshake'));
    });

    test('the last error is kept verbatim', () {
      final String text = report(error: 'write failed: not permitted').render();
      expect(text, contains('write failed'));
    });
  });

  group('the frame ring keeps the moment that matters', () {
    test('keeps the newest frames and drops the oldest', () {
      // A dropout is explained by what came just before it, and a report short
      // enough to paste is one a maintainer actually reads.
      final FrameRing ring = FrameRing(capacity: 3);
      for (int i = 0; i < 5; i++) {
        ring.add(
          FrameRecord(
            elapsed: Duration(milliseconds: i),
            characteristic: '0002',
            direction: FrameDirection.inbound,
            bytes: <int>[i],
          ),
        );
      }
      expect(ring.frames.length, 3);
      expect(ring.frames.first.bytes.single, 2);
      expect(ring.frames.last.bytes.single, 4);
    });

    test('a new link starts empty, so one ride never explains another', () {
      final FrameRing ring = FrameRing(capacity: 3);
      ring.add(
        const FrameRecord(
          elapsed: Duration.zero,
          characteristic: '0002',
          direction: FrameDirection.inbound,
          bytes: <int>[1],
        ),
      );
      ring.clear();
      expect(ring.frames, isEmpty);
    });

    test('the exposed list cannot be modified from outside', () {
      final FrameRing ring = FrameRing();
      expect(
        () => ring.frames.add(
          const FrameRecord(
            elapsed: Duration.zero,
            characteristic: '0002',
            direction: FrameDirection.inbound,
            bytes: <int>[1],
          ),
        ),
        throwsUnsupportedError,
      );
    });

    // Measured: a Click v2 sends its resting mask `23 08 ff ff ff ff 0f` about
    // ten times a second. Forty raw slots hold four seconds, which is why a
    // rider's presses were gone by the time they copied the report.
    test('a frame repeated unchanged takes one slot, not forty', () {
      final FrameRing ring = FrameRing();
      const List<int> resting = <int>[0x23, 0x08, 0xff, 0xff, 0xff, 0xff, 0x0f];
      for (int i = 0; i < 40; i++) {
        ring.add(
          FrameRecord(
            elapsed: Duration(milliseconds: 100 * i),
            characteristic: '0002',
            direction: FrameDirection.inbound,
            bytes: resting,
          ),
        );
      }
      expect(ring.frames.length, 1);
      expect(ring.frames.single.repeats, 40);
      // Timed from the first arrival: the run started there.
      expect(ring.frames.single.elapsed, Duration.zero);
    });

    test('a press breaks the run and keeps its own time', () {
      final FrameRing ring = FrameRing();
      FrameRecord frame(int ms, List<int> bytes) => FrameRecord(
        elapsed: Duration(milliseconds: ms),
        characteristic: '0002',
        direction: FrameDirection.inbound,
        bytes: bytes,
      );
      const List<int> resting = <int>[0x23, 0x08, 0xff, 0xff, 0xff, 0xff, 0x0f];
      const List<int> plus = <int>[0x23, 0x08, 0xff, 0xdf, 0xff, 0xff, 0x0f];
      ring
        ..add(frame(0, resting))
        ..add(frame(100, resting))
        ..add(frame(200, plus))
        ..add(frame(300, plus))
        ..add(frame(400, resting));
      expect(ring.frames.length, 3);
      expect(ring.frames[0].repeats, 2);
      expect(ring.frames[1].bytes, plus);
      expect(ring.frames[1].repeats, 2);
      expect(ring.frames[1].elapsed, const Duration(milliseconds: 200));
      expect(ring.frames[2].repeats, 1);
    });

    test('the same bytes in two directions are two frames', () {
      final FrameRing ring = FrameRing();
      ring
        ..add(
          const FrameRecord(
            elapsed: Duration.zero,
            characteristic: '0003',
            direction: FrameDirection.outbound,
            bytes: <int>[0x52, 0x69],
          ),
        )
        ..add(
          const FrameRecord(
            elapsed: Duration(milliseconds: 90),
            characteristic: '0004',
            direction: FrameDirection.inbound,
            bytes: <int>[0x52, 0x69],
          ),
        );
      expect(ring.frames.length, 2);
    });
  });

  group('the report says what was collapsed', () {
    test('a run of identical frames is shown with its count', () {
      final String text = report(
        frames: const <FrameRecord>[
          FrameRecord(
            elapsed: Duration(milliseconds: 335),
            characteristic: '0002',
            direction: FrameDirection.inbound,
            bytes: <int>[0x23, 0x08, 0xff, 0xff, 0xff, 0xff, 0x0f],
            repeats: 31,
          ),
        ],
      ).render();
      expect(text, contains('+0000.335 <- 0002 23 08 ff ff ff ff 0f  x31'));
    });

    test('a single frame carries no count', () {
      final String text = report(
        frames: const <FrameRecord>[
          FrameRecord(
            elapsed: Duration(milliseconds: 12),
            characteristic: '0002',
            direction: FrameDirection.inbound,
            bytes: <int>[0x23, 0x08],
          ),
        ],
      ).render();
      expect(text, contains('+0000.012 <- 0002 23 08\n'));
    });
  });
}

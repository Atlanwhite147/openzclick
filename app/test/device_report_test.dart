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
      expect(report().render(), contains('no 0x180a'));
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
  });
}

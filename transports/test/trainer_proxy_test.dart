/// Tests for the home trainer proxy, driven by an in-memory FTMS link.
library;

import 'dart:async';

import 'package:openzclick_transports/src/openzclick_transports.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

import 'socket_client.dart';

/// FTMS link double: records commands, injects grades on demand.
class FakeFtmsLink implements FtmsLink {
  final StreamController<double> _grade = StreamController<double>.broadcast();

  final List<double> gradeSetpoints = <double>[];
  final List<int> powerSetpoints = <int>[];
  String? connectedDevice;
  bool disconnectCalled = false;

  @override
  Future<void> connect(String deviceId) async {
    connectedDevice = deviceId;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
    connectedDevice = null;
  }

  @override
  bool get isConnected => connectedDevice != null;

  @override
  Stream<double> get gradePercent => _grade.stream;

  @override
  Future<void> setTargetGrade(double percent) async {
    gradeSetpoints.add(percent);
  }

  @override
  Future<void> setTargetPower(int watts) async {
    powerSetpoints.add(watts);
  }

  void reportGrade(double grade) => _grade.add(grade);

  Future<void> close() => _grade.close();
}

void main() {
  group('TrainerProxy', () {
    late FakeFtmsLink link;
    late TrainerProxy proxy;
    late EventLog<TransportEvent> log;

    setUp(() async {
      link = FakeFtmsLink();
      proxy = TrainerProxy(link: link, deviceId: 'bike-1', gradeStep: 0.5);
      log = EventLog<TransportEvent>(proxy.events);
      await proxy.start();
    });

    tearDown(() async {
      await log.cancel();
      await proxy.dispose();
      await link.close();
    });

    test('fails explicitly when no FTMS link is wired', () async {
      final TrainerProxy unwired = TrainerProxy();
      expect(unwired.hasLink, isFalse);

      await expectLater(
        unwired.start(),
        throwsA(
          isA<UnimplementedError>().having(
            (UnimplementedError e) => e.message,
            'message',
            allOf(contains('FtmsLink'), contains('proxy')),
          ),
        ),
      );
      expect(unwired.isRunning, isFalse);
      await unwired.dispose();
    });

    test('connects to the trainer and reports it', () async {
      expect(proxy.isRunning, isTrue);
      expect(link.connectedDevice, 'bike-1');

      final TransportConnected connected = await log.next<TransportConnected>();
      expect(connected.peerId, TrainerProxy.trainerPeerId);
      expect(connected.label, 'bike-1');
      expect(connected.transportId, 'proxy');
    });

    test('relays the grade published by the trainer', () async {
      link.reportGrade(6.5);
      final TransportGradeUpdate update =
          await log.next<TransportGradeUpdate>();

      expect(update.gradePercent, 6.5);
      expect(proxy.gradePercent, 6.5);
      expect(update.transportId, 'proxy');
    });

    test('turns difficulty actions into grade setpoints', () async {
      await proxy.emit(Action.increaseDifficulty);
      expect(link.gradeSetpoints, <double>[0.5]);
      expect(proxy.gradePercent, 0.5);
      await log.next<TransportGradeUpdate>();

      await proxy.emit(Action.increaseDifficulty);
      await proxy.emit(Action.decreaseDifficulty);
      expect(link.gradeSetpoints, <double>[0.5, 1.0, 0.5]);

      await proxy.emit(Action.shiftUp);
      expect(link.gradeSetpoints.last, 1.0);
      await proxy.emit(Action.shiftDown);
      expect(link.gradeSetpoints.last, 0.5);
    });

    test('clamps the requested grade to the supported range', () async {
      await proxy.setGrade(120);
      expect(proxy.gradePercent, TrainerProxy.maxGrade);
      expect(link.gradeSetpoints.last, TrainerProxy.maxGrade);

      await proxy.setGrade(-120);
      expect(proxy.gradePercent, TrainerProxy.minGrade);
      expect(link.gradeSetpoints.last, TrainerProxy.minGrade);
    });

    test('cuts resistance on pause and restores it on resume', () async {
      await proxy.setTargetPower(180);
      expect(link.powerSetpoints, <int>[180]);

      await proxy.emit(Action.pause);
      expect(link.powerSetpoints.last, 0);

      await proxy.emit(Action.resume);
      expect(link.powerSetpoints.last, 180);
    });

    test('ignores actions that make no sense for a trainer', () async {
      await proxy.emit(Action.navigateUp);
      await proxy.emit(Action.emote);

      expect(proxy.ignoredActionCount, 2);
      expect(link.gradeSetpoints, isEmpty);
      expect(link.powerSetpoints, isEmpty);
    });

    test('stop disconnects and reports the disconnection', () async {
      await proxy.stop();

      expect(proxy.isRunning, isFalse);
      expect(link.disconnectCalled, isTrue);

      final TransportDisconnected gone =
          await log.next<TransportDisconnected>();
      expect(gone.peerId, TrainerProxy.trainerPeerId);
    });

    test('refuses actions when stopped or disconnected', () async {
      final TrainerProxy idle = TrainerProxy(link: FakeFtmsLink());
      await expectLater(
        idle.emit(Action.increaseDifficulty),
        throwsA(isA<StateError>()),
      );
      await idle.dispose();

      final FakeFtmsLink dead = FakeFtmsLink();
      final TrainerProxy stopped = TrainerProxy(link: dead);
      await stopped.start();
      await dead.disconnect();
      await expectLater(
        stopped.emit(Action.increaseDifficulty),
        throwsA(isA<StateError>()),
      );
      await stopped.dispose();
      await dead.close();
    });

    test('rejects a negative target power', () async {
      await expectLater(
          proxy.setTargetPower(-1), throwsA(isA<ArgumentError>()));
    });
  });
}

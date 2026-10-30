import 'dart:typed_data';

import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';
import 'package:test/test.dart';

/// Builds a control point frame, little endian, for the tests.
List<int> _frame(int opcode, List<int> body) => <int>[opcode, ...body];

void main() {
  group('FtmsCodec', () {
    test('round-trips the feature bitfields', () {
      final List<int> frame =
          FtmsCodec.feature(features: 0x1234, targets: 0x5678);
      final ({int features, int targets}) decoded =
          FtmsCodec.decodeFeature(frame);
      expect(decoded.features, 0x1234);
      expect(decoded.targets, 0x5678);
    });

    test('decodes simulation parameters', () {
      final ByteData body = ByteData(6)
        ..setInt16(0, -1500, Endian.little) // wind -1.5 m/s
        ..setInt16(2, 425, Endian.little) // grade 4.25 %
        ..setUint8(4, 40) // crr 0.0040
        ..setUint8(5, 51); // cw 0.51
      final FtmsRequest request = FtmsCodec.decodeRequest(
        _frame(FtmsOpcode.setSimulationParameters, body.buffer.asUint8List()),
      );
      final SetSimulationParameters simulation =
          request as SetSimulationParameters;
      expect(simulation.parameters.windSpeed, closeTo(-1.5, 1e-9));
      expect(simulation.parameters.gradePercent, closeTo(4.25, 1e-9));
      expect(simulation.parameters.rollingResistance, closeTo(0.004, 1e-9));
      expect(simulation.parameters.windResistance, closeTo(0.51, 1e-9));
    });

    test('rejects a truncated frame', () {
      expect(
        () => FtmsCodec.decodeRequest(
            <int>[FtmsOpcode.setSimulationParameters, 0, 0]),
        throwsArgumentError,
      );
    });

    test('reports an unknown opcode instead of throwing', () {
      expect(FtmsCodec.decodeRequest(<int>[0x7F]), isA<UnsupportedRequest>());
    });

    test('decodes a resistance field sent by a machine', () {
      // Flags: speed present (bit 0 clear), resistance present (bit 5).
      final List<int> frame = <int>[0x20, 0x00, 0x30, 0x0c, 0xb6];
      final ({
        double? speedKmh,
        int? cadenceRpm,
        int? powerWatts,
        double? resistancePercent,
      }) decoded = FtmsCodec.decodeIndoorBikeData(frame);
      expect(decoded.speedKmh, closeTo(31.2, 0.01));
      expect(decoded.resistancePercent, closeTo(18.2, 0.01));
    });

    test('every byte of an indoor bike data frame stays in range', () {
      final List<int> frame = FtmsCodec.indoorBikeData(
        speedKmh: 120.5,
        cadenceRpm: 300,
        powerWatts: 2000,
      );
      expect(frame.every((int b) => b >= 0 && b <= 255), isTrue);
    });

    test('round-trips indoor bike data', () {
      final List<int> frame = FtmsCodec.indoorBikeData(
        speedKmh: 32.45,
        cadenceRpm: 88,
        powerWatts: 210,
      );
      final ({
        double? speedKmh,
        int? cadenceRpm,
        int? powerWatts,
        double? resistancePercent,
      }) decoded = FtmsCodec.decodeIndoorBikeData(frame);
      expect(decoded.speedKmh, closeTo(32.45, 0.01));
      expect(decoded.cadenceRpm, 88);
      expect(decoded.powerWatts, 210);
    });
  });

  group('VirtualTrainer', () {
    late GearEngine engine;
    late VirtualTrainer trainer;

    setUp(() {
      engine = GearEngine(profile: GearProfile.road12, initialGear: 5);
      trainer = VirtualTrainer(engine: engine, trainerMaxWatts: 1200);
      trainer.updateFromTrainer(speedKmh: 30, powerWatts: 200);
    });

    List<int> simulationFrame(double grade) => FtmsCodec.simulationParameters(
          SimulationParameters(gradePercent: grade),
        );

    test('refuses requests before control is granted', () {
      final TrainerOutcome outcome = trainer.handle(simulationFrame(4));
      expect(outcome.toTrainer, isNull);
      expect(outcome.response, <int>[
        FtmsOpcode.response,
        FtmsOpcode.setSimulationParameters,
        FtmsResult.controlNotPermitted
      ]);
    });

    test('grants control then applies a resistance for the grade', () {
      trainer.handle(<int>[FtmsOpcode.requestControl]);
      expect(trainer.hasControl, isTrue);
      final TrainerOutcome outcome = trainer.handle(simulationFrame(4));
      expect(outcome.resistancePercent, isNotNull);
      expect(outcome.resistancePercent, greaterThan(0));
      expect(outcome.toTrainer, isNotNull);
      expect(outcome.toTrainer!.first, FtmsOpcode.resistanceChanged);
    });

    test('a harder gear asks for more resistance on the same grade', () {
      trainer.handle(<int>[FtmsOpcode.requestControl]);
      final double low = trainer.handle(simulationFrame(4)).resistancePercent!;
      engine.shiftUp();
      engine.shiftUp();
      final double high = trainer.handle(simulationFrame(4)).resistancePercent!;
      expect(high, greaterThan(low));
    });

    test('a steeper grade asks for more resistance at the same gear', () {
      trainer.handle(<int>[FtmsOpcode.requestControl]);
      final double flat = trainer.handle(simulationFrame(0)).resistancePercent!;
      final double climb =
          trainer.handle(simulationFrame(6)).resistancePercent!;
      expect(climb, greaterThan(flat));
    });

    test('forwards a target power unchanged in ergometer mode', () {
      trainer.handle(<int>[FtmsOpcode.requestControl]);
      final ByteData body = ByteData(2)..setInt16(0, 240, Endian.little);
      final TrainerOutcome outcome = trainer.handle(
        _frame(FtmsOpcode.setTargetPower, body.buffer.asUint8List()),
      );
      expect(outcome.targetPowerWatts, 240);
      expect(outcome.toTrainer, isNotNull);
      expect(outcome.toTrainer!.first, 0x08);
    });

    test('answers an unsupported opcode with not supported', () {
      trainer.handle(<int>[FtmsOpcode.requestControl]);
      final TrainerOutcome outcome = trainer.handle(<int>[0x06, 120]);
      expect(outcome.response,
          <int>[FtmsOpcode.response, 0x06, FtmsResult.notSupported]);
    });

    test('a malformed frame is reported as an invalid parameter', () {
      trainer.handle(<int>[FtmsOpcode.requestControl]);
      final TrainerOutcome outcome =
          trainer.handle(<int>[FtmsOpcode.setSimulationParameters]);
      expect(outcome.response![2], FtmsResult.invalidParameter);
    });

    test('start and stop change the running state', () {
      trainer.handle(<int>[FtmsOpcode.requestControl]);
      expect(trainer.handle(<int>[FtmsOpcode.startResume]).note, 'started');
      expect(trainer.running, isTrue);
      trainer.handle(<int>[FtmsOpcode.stopPause, 0x01]);
      expect(trainer.running, isFalse);
    });
  });
}

// Scripted ride against the virtual trainer, without any Bluetooth.
//
//   dart run tool/trainer_probe.dart
//
// It plays the role of a training application: it takes control, starts a
// ride, sends a grade, shifts, and prints what the bridge would write on the
// real trainer.

import 'dart:typed_data';

import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';

String hex(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

void main() {
  final GearEngine engine =
      GearEngine(profile: GearProfile.road12, initialGear: 5);
  final VirtualTrainer trainer =
      VirtualTrainer(engine: engine, trainerMaxWatts: 1200);
  trainer.updateFromTrainer(speedKmh: 30, powerWatts: 200);

  void send(String label, List<int> frame) {
    final TrainerOutcome outcome = trainer.handle(frame);
    print(
      '${label.padRight(34)} '
      'resistance=${(outcome.resistancePercent ?? 0).toStringAsFixed(1).padLeft(5)} % '
      'trainer=${outcome.toTrainer == null ? '-' : hex(outcome.toTrainer!)}',
    );
  }

  print('ride script');
  send('request control', <int>[FtmsOpcode.requestControl]);
  send('start', <int>[FtmsOpcode.startResume]);

  for (final double grade in <double>[0, 2, 4, 6]) {
    send(
      'grade ${grade.toStringAsFixed(0)} %, gear ${engine.gearNumber}',
      FtmsCodec.simulationParameters(SimulationParameters(gradePercent: grade)),
    );
  }

  for (int i = 0; i < 3; i++) {
    engine.shiftUp();
    send(
      'shift up, gear ${engine.gearNumber}',
      FtmsCodec.simulationParameters(
          const SimulationParameters(gradePercent: 4)),
    );
  }

  for (int i = 0; i < 2; i++) {
    engine.shiftDown();
    send(
      'shift down, gear ${engine.gearNumber}',
      FtmsCodec.simulationParameters(
          const SimulationParameters(gradePercent: 4)),
    );
  }

  final ByteData erg = ByteData(2)..setInt16(0, 240, Endian.little);
  send('ergometer 240 W',
      <int>[FtmsOpcode.setTargetPower, ...erg.buffer.asUint8List()]);
  send('stop', <int>[FtmsOpcode.stopPause, 0x01]);

  print('');
  print('indoor bike data published to the app:');
  final List<int> data = FtmsCodec.indoorBikeData(
    speedKmh: 31.2,
    cadenceRpm: 86,
    powerWatts: 214,
  );
  print('  ${hex(data)}');
  print('  decoded: ${FtmsCodec.decodeIndoorBikeData(data)}');
}

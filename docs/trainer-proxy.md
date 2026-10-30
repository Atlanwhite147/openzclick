# Trainer proxy

Two applications never share one Bluetooth trainer, and iOS refuses synthetic input. The way out is to become the trainer: the bridge holds the real machine, applies the resistance of the selected gear, and presents itself to the training application as an ordinary smart trainer.

```
Zwift Click ──BLE──► bridge ──BLE──► real trainer (resistance setpoint)
                       │
                       └──BLE──► training application (bridge looks like a trainer)
```

The application sees a normal machine whose resistance changes with the gear; it never learns that gears exist. That is why this path works in every application, including the ones with no virtual shifting at all, and why it is the only path available on iPhone: a Bluetooth peripheral needs no Apple entitlement.

## What is implemented

`transports/lib/src/trainer/ftms.dart` — the FTMS vocabulary, in pure Dart:

- identifiers of the service and of the characteristics used;
- control point opcodes, response codes, result codes;
- decoding of simulation parameters (grade, wind, rolling resistance, drag), target power, target resistance, wheel circumference;
- encoding of the responses and of the setpoints sent to the real trainer;
- Indoor Bike Data, with the flags that announce which fields follow.

`transports/lib/src/trainer/virtual_trainer.dart` — the decision logic:

| The application sends | The bridge answers | The real trainer receives |
|---|---|---|
| request control | success | nothing |
| simulation parameters (grade) | success | resistance level computed for the gear |
| target power (ergometer) | success | the same target power, unchanged |
| target resistance | success | the same resistance |
| start, stop, pause, reset | success | start, stop, reset |
| an unknown opcode | not supported | nothing |
| a malformed frame | invalid parameter | nothing |

## How the resistance is computed

The gear engine already models gravity, rolling resistance, air drag, drivetrain efficiency and the gear ratio. Given the grade sent by the application, the rider weight and the current speed, it returns the power the rider would have to produce in the selected gear. The bridge then expresses that as a percentage of what the trainer can resist at full brake, which is the only unit FTMS offers for this.

Consequence, stated plainly: the mapping depends on the machine. `trainerMaxWatts` defaults to 1200 W at 30 km/h, which suits a direct drive trainer; another trainer will need its own value. This is the one number to calibrate by feel, and the reason the diagnostic screen shows the applied resistance.

A scripted ride, printed by `dart run tool/trainer_probe.dart`:

```
grade 0 %, gear 6      resistance= 13.6 %  trainer=07 0e
grade 4 %, gear 6      resistance= 36.7 %  trainer=07 25
shift up, gear 7       resistance= 43.8 %  trainer=07 2c
shift up, gear 9       resistance= 62.6 %  trainer=07 3f
ergometer 240 W        resistance=  0.0 %  trainer=08 f0 00
```

## What remains

1. **FTMS client** over Bluetooth towards the real trainer: subscribe to Indoor Bike Data, write resistance and target power on its control point. Needs a Bluetooth central, which the application already uses for the controller.
2. **GATT server**: expose the FTMS service so the training application can pair the bridge. Kotlin on Android, CoreBluetooth on iPhone.
3. **Control loop**: feed the machine's speed and power back into `updateFromTrainer` on every notification, so the simulation stays anchored.

The first and third items are straightforward once a Bluetooth central is wired; the second is the platform-specific one, and it is what the roadmap calls the Bluetooth peripheral backend.

## Trying it without hardware

```bash
cd transports && dart run tool/trainer_probe.dart
cd transports && dart test test/trainer/ftms_test.dart
```

The tests play both roles: they build the frames an application would send and check the frames the bridge would write on the machine.

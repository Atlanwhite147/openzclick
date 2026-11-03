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

## The other way to set the resistance: wheel size

The percentage above has two drawbacks: it needs `trainerMaxWatts`, which is a property of the machine and of the speed, and it fights the grade the application is already sending. A second route avoids both, and it is the one the application now prefers.

A trainer computes its brake force from the distance one pedal stroke covers, so telling it a smaller wheel makes every gear easier without touching the grade. The bridge therefore sends one number per gear, and the terrain stays exactly as the application sent it.

```
feel  =  parked gear ratio  ×  wheel size the trainer works from
```

The bridge controls the second term only, so it must be told the first: **where the chain sits on the bike**. That is the question the Gears screen asks, and it is not cosmetic. A bike parked in 50/11 multiplies the wheel size by 4.55; a ladder built assuming a middle gear is then 89 % too hard with no symptom other than tired legs, because the step sizes stay right and only the position of the whole ladder moves. Leave the chain in a quiet place instead: the *Quietest* button picks the lowest ratio that still keeps every gear reachable, which is what keeps the flywheel slow and the room silent.

`core/lib/src/shifting/parked_gear.dart` holds the arithmetic and `transports/lib/src/trainer/wahoo_wheel_circumference.dart` the frame:

| Item | Value |
|---|---|
| Command | opcode `0x48`, then the wheel size as a 16-bit little endian value in tenths of a millimetre |
| Unlock | `20 EE FC`, once per connection, on characteristic `A026E005-0A7D-4AB3-97FA-F1500F9FEB8B` |
| Usable wheel window | 1800 to 2400 mm, the span a riding application may impose (650b to 29er, with room for hand-typed values) |
| Widest span a profile may reach | 6553.5 / 2400 = 2.73×, past which the hardest gear no longer fits the command |
| Acknowledgement | 59 to 238 ms measured on a KICKR, 138 ms on average |

Three rules follow from that measurement, and breaking any of them looks like a hardware fault:

- **One gear at a time.** A command in flight takes tens to hundreds of milliseconds. Sending the next gear meanwhile loses one of the two, and the rider sits in a gear the screen does not show. Shift again while busy and the request is dropped, not queued: a queue would let five quick shifts arrive a minute later.
- **Refuse rather than clamp.** A gear that does not fit is reported. A clamped wheel size is a gear the rider never asked for, silently.
- **Never in ergometer mode.** A target power and a gear contradict each other; the machine follows whichever arrived last.

The ladder is rebuilt around whatever wheel size the application imposes, which is how a ride keeps its hills while the gears stay put. A value outside the window is ignored rather than adopted: no bicycle has a 1200 mm wheel, so the value is a misreading, and keeping the previous one keeps every gear working.

## Cycling Power, so Windows applications show watts

An FTMS trainer is enough for Zwift, but some applications look for a plain power meter and display `0 W` and `0 rpm` without one. `transports/lib/src/trainer/cycling_power.dart` encodes the service (`0x1818`): instantaneous power plus crank revolution counters, from one clock. Both fields together, because an application derives cadence from the change in revolution count over the change in event time; power alone shows watts and no legs.

The counters wrap at 16 bits, which happens on every long ride, and the fractions of a revolution are carried rather than rounded, or a 100 ms publishing rate at 90 rpm reports no revolutions at all.

## Trying without hardware

```bash
cd transports && dart run tool/trainer_probe.dart
cd transports && dart test test/trainer/
```

The tests play both roles: they build the frames an application would send and check the frames the bridge would write on the machine.

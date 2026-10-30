# Contributing to openzclick

Thanks for taking the time to help. This project stays useful only if it keeps working with real controllers on real applications, so reports from hardware are as valuable as code.

## Before you start

- Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [CONTRACTS.md](CONTRACTS.md). They describe the three modules and the interfaces between them.
- Look for an existing issue before opening a new one.
- For anything larger than a bug fix, open an issue first so the design can be discussed before code is written.

## Ground rules

1. **The core stays pure.** `core/` must not import `dart:io`, Flutter or plugins. If a change needs I/O, it belongs in `transports/` behind an interface.
2. **No brand specific logic in the core.** Devices are described by definition files, applications by their protocol, never by `if (brand == ...)`.
3. **Everything is tested.** New behaviour comes with unit tests; a bug fix comes with a test that fails before and passes after.
4. **Additions stay honest.** Do not claim support for a device or an application that has not been exercised. The README status table says what was actually run.

## Development loop

```bash
cd core && dart pub get && dart test
cd ../transports && dart pub get && dart test
cd ../app && flutter pub get && flutter analyze && flutter test
```

The CI runs exactly these commands, plus `flutter build apk` and a macOS build of the iOS application, so a green local run is a good predictor.

## Reporting a controller that does not pair

Open a bug report and include:

- the controller model and firmware version;
- the platform and operating system version;
- the state shown in the **Controllers** screen (idle, scanning, connecting, ready, failed) and the exact error text;
- whether the session ends up `encrypted` or `plain`;
- the diagnostic log from the **Diagnostics** screen if a frame is decoded.

Never paste a pairing key, an API token or a personal identifier.

## Reporting an application that does not react

State the application, its version and platform. Run the network probe to separate the two halves of the chain:

```bash
cd transports && dart run tool/net_probe.dart 47123
```

If the probe is discovered and answers, the bridge is fine and the receiving side is the problem. If it is not discovered, the network is.

## Code style

- Dart formatting is enforced by `dart format`; run it before committing.
- Public API gets a doc comment that explains the behaviour, not the syntax.
- Commit messages follow `type(scope): summary`, for example `fix(android): request the multicast lock`.

## Pull requests

- One topic per pull request.
- Describe what was run to verify the change, with real output when possible.
- Update the README status table when behaviour changes.
- By submitting, you agree that your contribution is released under the MIT license.

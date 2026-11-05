# What to take from the others, and in what order

A plan, not a wish list. Fifteen neighbouring projects were surveyed in
[`prior-art.md`](prior-art.md); this file decides what enters openzclick, in what
order, and what is deliberately left outside.

## The filter

Something enters the plan only if all four hold:

1. **It closes a gap a rider feels**, not a gap a comparison table shows.
2. **It can be tested from here**: unit tests in plain Dart, and the Windows PC
   (Windows 11, KICKR CORE, Click v2) driven over SSH — the harness that already
   proved the injector and the console route.
3. **It keeps the promise**: MIT, no account, nothing to install on the rider's
   machine beyond this application.
4. **It does not duplicate the protocol.** Where OpenBikeControl already answers,
   the keyboard route is a fallback, not the plan.

## Where we stand

Already done, and therefore not a phase: OpenBikeControl publication over mDNS and
TCP, the console page a phone opens, local keyboard injection on Windows and
Linux, trainer gearing by wheel size, the device report, and the focus target that
types only into the training application. Four of the surveyed projects solve one
of those and stop.

## Phase 1 — Per-application key profiles, and a multiplier

*Sources: zwiftboard (per-profile maps), ClickShift (1–3 shifts per press),
OpenBridge (remap any button).*

Today `InjectionPublisher.defaultKeys` is one map for every application, and it is
wrong for most of them: `i`/`k` in MyWhoosh, `,`/`.` in Rouvy, `S`/`W` in Biketerra,
`-`/`=` in TrainingPeaks. Every surveyed project ships a table; ours ships one row.

- A profile is data: application name, key per action, shifts per press, whether a
  hold repeats. Const in `core`, so it is testable and translatable.
- Profiles shipped after reading the vendor's own shortcut page, with the source
  named next to each one — the tables in the wild disagree, as the `i`/`k`
  direction proved.
- The rider picks an application on the Network tab; the choice persists and is
  shown next to the switch.
- A keymap editor (already a "small contribution" in the roadmap) becomes the same
  screen, not a second one.

**Acceptance**: a test asserts that every shipped profile names a key for each
action it claims; on the PC, choosing Rouvy sends `,` and `.` and choosing
MyWhoosh sends `i` and `k`; the multiplier sends two presses for one button push.
**Effort**: one session. **Risk**: low, no hardware.

**State**: done. The table, the selector, the multiplier and the editor are in
(`app/lib/net/key_profiles.dart`, `app/test/key_profiles_test.dart`,
`app/test/key_editor_test.dart`). The editor keeps changes per application and an
empty field restores the shipped key; that is the "small contribution" the roadmap
listed, closed on the same screen instead of a second one.

## Phase 2 — Both pods, and the buttons the left one owns

*Sources: clickbridge (both units, left and right), click2whoosh (both units, kept
awake), zwiftboard (both connected, only the right one mapped).*

This is the largest functional gap. `ClickButtons` models two booleans, up and
down, and the connection holds one device. The left pod's arrows — steering,
which MyWhoosh reads over OpenBikeControl without any injection — are simply not
decoded here.

- `ClickButtons` becomes a button mask (the vendor bitmap, `0 = pressed`), which
  also settles an unmeasured risk: the two pods mirror each other's frames, so an
  action must fire on changed bits only, or one press counts twice.
- The link holds two devices, with the left one kept connected because that is what
  keeps the pair alive (zwiftboard: a lone right pod drops about 65 s after its
  last write).
- Steering actions reach the network publisher, so MyWhoosh steers with no
  synthetic input at all.

**Acceptance**: hardware session — an arrow press on the left pod turns the rider in
MyWhoosh; a press on the right pod moves the gear once, not twice; a two-minute
pause changes nothing.
**Effort**: two to three sessions, the first real BLE work of this project.
**Risk**: medium — the protocol is now documented by others, but the pair's
behaviour only shows on hardware.

## Phase 3 — Gestures the controller already has

*Sources: click2whoosh (click, double click, long press), clickbridge (explicitly
no repeat on hold).*

`ButtonGestureDetector` already distinguishes a tap from a double tap for
direction choices. It stops there.

- Long press and double press become configurable per button: U-turn, camera,
  minimal UI, screenshot, emote.
- The repeat question is decided per action, not globally: a gear never repeats, a
  steering key may.

**Acceptance**: a table of gestures produces the expected actions; on the PC, a long
press sends nothing until the threshold, a double press sends one action.
**Effort**: one session. **Risk**: low.

**State**: the engine is in (`core/lib/src/mapping/button_gestures.dart`: long
press, immediate and deferred modes, per-button bindings, tested against fake
durations). What remains is the interface that binds a long press to an action and
a measured run on hardware — the engine's behaviour is asserted, not felt.

## Phase 4 — Battery, sleep, and a link that lets go

*Sources: ClickShift (disconnects when the ride app quits so the pod can sleep),
click2whoosh (keeps the pod awake on demand, off otherwise), clickbridge (battery
level shown).*

The most common complaint about a Click is its battery, and this application holds
the link for as long as it runs.

- Battery level and firmware on the Controllers screen, from the frames already
  decoded.
- A rule the rider can read: connect when the riding application window exists,
  disconnect when it is gone, with a manual override.
- The pod is released rather than kept awake when nothing is being published.

**Acceptance**: with the ride application closed, no connection is held and the pod
sleeps; opening it reconnects without a click; battery reads the same value as the
official application.
**Effort**: one session. **Risk**: low, but it interacts with Phase 2's keepalive.

## Phase 5 — macOS injection, and Wine

*Sources: ClickShift and click2whoosh exist on macOS, so the platform is covered by
others; clickbridge proves Linux riders run MyWhoosh under Wine/Proton.*

- `CGEventPost` in one file behind the existing `KeyInjector`, with the
  accessibility permission requested and explained (`docs/injection.md` already
  describes the contract).
- A measured test of X11 injection into a Wine/Proton window: a reviewer of the
  Linux backend would ask, and nobody has.

**Acceptance**: on a Mac, a shift types `k` in TextEdit with the permission granted,
and a refused permission is reported, not silent; on Linux, a key reaches a Proton
game window.
**Effort**: one to two sessions, one of them on hardware this project does not own.
**Risk**: medium for the permission path, low for Wine.

## Phase 6 — The spare buttons

*Sources: swift-click (media keys), click2whoosh (volume, screenshots, emotes).*

Only after the above: the buttons not used for shifting become configurable to
media keys, volume, screenshot, minimal UI. Pure table work on top of Phase 1.

**Effort**: half a session. **Risk**: none.

## Deliberately outside

- **An ESP32 firmware.** `RideToWooshHID` reaches an iPad and an Apple TV, which no
  desktop-side helper can. But it is a second product with a hardware dependency and
  a build chain, and this project's promise is that there is nothing to buy. The
  right move is to link it in the README as the answer for those devices, which is
  already done.
- **A virtual gamepad through ViGEm.** Needs a signed kernel driver installed on the
  rider's machine, which breaks the same promise. Held in reserve in
  `docs/injection.md` if a training application turns out to ignore injected events.
- **A BLE peripheral on Windows.** The platform cannot be one; that is why the
  console route and the ESP32 projects exist.
- **A second mobile application.** The Android and iOS builds already are that
  application.

## Order, and why

1 → 2 is the real sequence: profiles make the keyboard route honest for the
applications that need it, then both pods make the protocol route complete for
MyWhoosh, which needs no keyboard at all. 3 and 4 are the difference between
"works" and "pleasant to own". 5 closes the last platform claim. 6 is sugar.

Every phase ends the same way: tests green, a measured line added to
`docs/injection.md` or `docs/controllers.md`, and a CHANGELOG entry that says what
was measured rather than what was intended.

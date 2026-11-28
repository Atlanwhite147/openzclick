/// Turns a Bluetooth failure into a sentence a rider can act on.
///
/// The raw text the Bluetooth plugin produces is written for whoever wrote the
/// plugin, not for a cyclist standing next to a bike:
///
/// ```
/// FlutterBluePlusException | scan | web-code: 0 | Null check operator used on a null value
/// ```
///
/// That message was what a rider saw after tapping *Choose a controller* on a
/// desktop without a Bluetooth radio. Nothing in it says what happened, and the
/// only reading available is "the application is broken", which is wrong: the
/// machine has no radio, and no amount of retrying changes it.
///
/// The mapping is pure so every branch is tested on the host. [fallback] is used
/// for anything not recognised: a failure nobody anticipated must still say
/// *something* rather than echo a stack trace at the rider.
library;

/// Sentence describing [error], and what to do about it.
///
/// [hasRadio] narrows the advice: a radio that was never found is not a radio
/// that is switched off.
String explainControllerError(Object? error, {bool hasRadio = true}) {
  final String raw = error?.toString() ?? '';

  // The plugin reports a missing adapter this way on some hosts.
  if (raw.contains('Null check operator') || raw.contains('is not available')) {
    return 'No Bluetooth radio was found on this device.';
  }
  // Before "turned off": a radio that does not exist is not a radio that is off,
  // and the advice differs. macOS also reports `off` for a host with no adapter,
  // which is why the sentence names both cases rather than guessing.
  if (raw.contains('unavailable') || raw.contains('no adapter')) {
    return 'This machine reports no Bluetooth. Check that the adapter exists and '
        'is not switched off, then try again.';
  }
  if (raw.contains('bluetoothadapter') || raw.contains('turned off')) {
    return 'Bluetooth is off. Turn it on, then try again.';
  }
  // CoreBluetooth's own wording, which reaches Dart when macOS refuses the
  // application or the radio: `bluetooth must be turned on. (unauthorized)` is
  // the one a Mac gives a bundle whose Bluetooth permission the user refused.
  if (raw.contains('not powered on') ||
      raw.contains('neauthorized') ||
      raw.contains('Not authorized')) {
    return 'macOS refused Bluetooth for this application. Install a build that '
        'declares why it needs Bluetooth, and allow it in System Settings > '
        'Privacy & Security > Bluetooth.';
  }
  if (raw.contains('notAuthorized') ||
      raw.contains('Not authorized') ||
      raw.contains('turned on. (unauthorized') ||
      raw.contains('permission')) {
    return 'Permission to use Bluetooth was refused. Allow it for this '
        'application, then try again.';
  }
  if (raw.contains('NotFound') || raw.contains('was cancelled')) {
    return 'No controller was chosen.';
  }
  if (raw.contains('already in progress')) {
    return 'A search is already running. Wait for it to finish.';
  }
  if (raw.contains('state changed') || raw.contains('disconnected')) {
    return 'The controller disconnected. Pair it again.';
  }
  if (!hasRadio) {
    return 'No Bluetooth radio was found on this device.';
  }
  if (raw.isEmpty) return 'The controller could not be reached.';
  // Nothing recognised: keep the original for a bug report, but lead with the
  // only sentence that is certainly true.
  return 'The controller could not be reached. ($raw)';
}

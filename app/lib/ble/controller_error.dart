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
/// [isWeb] and [hasRadio] narrow the advice: the same plugin error means
/// different things in a page and in a desktop build.
String explainControllerError(
  Object? error, {
  bool isWeb = false,
  bool hasRadio = true,
  bool secureContext = true,
}) {
  final String raw = error?.toString() ?? '';

  // No Web Bluetooth at all: the page is on plain http, or the browser does not
  // expose the API. Each has its own remedy, so they are separate cases.
  if (raw.contains('Null check operator') ||
      raw.contains('navigator.bluetooth') ||
      raw.contains('is not available')) {
    if (!isWeb) return 'No Bluetooth radio was found on this device.';
    if (!secureContext) {
      return 'This page cannot use Bluetooth: browsers only allow it over '
          'https, or over http://localhost.';
    }
    return 'This browser exposes no Bluetooth. Use Chrome or Edge, and check '
        'that the machine has a radio.';
  }
  if (raw.contains('bluetoothadapter') || raw.contains('turned off')) {
    return 'Bluetooth is off. Turn it on, then try again.';
  }
  if (raw.contains('notAuthorized') ||
      raw.contains('Not authorized') ||
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
  if (!hasRadio && !isWeb) {
    return 'No Bluetooth radio was found on this device.';
  }
  if (raw.isEmpty) return 'The controller could not be reached.';
  // Nothing recognised: keep the original for a bug report, but lead with the
  // only sentence that is certainly true.
  return 'The controller could not be reached. ($raw)';
}

/// Comparison of Bluetooth identifiers across hosts.
///
/// The same service is named three ways depending on who answers: the full
/// 128-bit string, the same string without its Bluetooth base suffix, or the
/// short 16-bit form. Windows reports SIG services short ("fc82") while
/// Android, iOS and the specification use the full form, so comparing the raw
/// strings finds nothing on a service that is right there: measured on a Click
/// v2, whose vendor service came back as `fc82` under WinRT.
library;

/// Bluetooth SIG base suffix shared by every 16-bit UUID.
const String bluetoothBaseSuffix = '-0000-1000-8000-00805f9b34fb';

/// Reduces [raw] to a form two hosts can compare.
///
/// Returns the four hexadecimal digits of a SIG UUID, and the lower-case
/// 128-bit form for anything else.
String canonicalUuid(String raw) {
  final String lower = raw.trim().toLowerCase();
  if (lower.length == 4) return lower;
  if (lower.endsWith(bluetoothBaseSuffix)) {
    final String head = lower.substring(
      0,
      lower.length - bluetoothBaseSuffix.length,
    );
    if (head.length == 4) return head;
    if (head.length == 8 && head.startsWith('0000')) {
      return head.substring(4);
    }
  }
  return lower;
}

/// Whether [a] and [b] name the same Bluetooth attribute.
bool sameUuid(String a, String b) => canonicalUuid(a) == canonicalUuid(b);

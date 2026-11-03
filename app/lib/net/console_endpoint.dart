/// Address a browser console dials, built from what a rider reads on screen.
///
/// Kept free of any browser API on purpose: the rule that turns
/// `192.168.1.24` and a four letter code into a URL is pure text handling, so it
/// is tested on the host rather than in a browser.
library;

/// Console endpoint of a bridge.
abstract final class ConsoleEndpoint {
  /// Port of the console relay, used when the rider types an address without
  /// one.
  static const int defaultPort = 47124;

  /// Path of the console endpoint on the bridge.
  static const String path = '/console';

  /// Builds the URL of the console for [host] and [code].
  ///
  /// [host] accepts a bare address (`192.168.1.24`), an address with a port
  /// (`192.168.1.24:47124`) or a full `ws://`/`wss://` URL, because a rider
  /// copies whatever the bridge displays. A URL that already carries the code is
  /// used as is.
  static String build(String host, String code) {
    final String trimmed = host.trim();
    final String cleanCode = code.trim();
    if (trimmed.startsWith('ws://') || trimmed.startsWith('wss://')) {
      if (trimmed.contains('token=')) return trimmed;
      return '$trimmed${trimmed.contains('?') ? '&' : '?'}token=$cleanCode';
    }
    final bool hasPort = RegExp(r':\d+$').hasMatch(trimmed);
    final String authority = hasPort ? trimmed : '$trimmed:$defaultPort';
    return 'ws://$authority$path?token=$cleanCode';
  }

  /// Address a QR code carries, so a phone opens the page already connected.
  ///
  /// [page] is the published page; [host] and [port] the console of the bridge.
  /// The rider scans, the page reads these two parameters and dials: nothing is
  /// typed, which is the whole point of the code.
  static String pageLink({
    required String page,
    required String host,
    required int port,
    required String code,
  }) {
    final String base = page.endsWith('/') ? page : '$page/';
    return '$base?bridge=${Uri.encodeQueryComponent('$host:$port')}'
        '&code=${Uri.encodeQueryComponent(code)}';
  }

  /// Reads the bridge coordinates out of a page URL.
  ///
  /// Returns `null` when the page was opened without them, which is the normal
  /// case for someone who types the address by hand.
  static ({String host, String code})? fromQuery(Map<String, String> query) {
    final String host = (query['bridge'] ?? query['host'] ?? '').trim();
    final String code = (query['code'] ?? query['token'] ?? '').trim();
    if (host.isEmpty || code.isEmpty) return null;
    return (host: host, code: code);
  }
}

import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/platform/capabilities.dart';

void main() {
  group('a page may only dial a bridge when the browser allows it', () {
    test('an https page may not, whatever it types', () {
      // The hosted page is https. A browser refuses a ws:// socket from it, so
      // the console form there could never work, and the failure used to be
      // reported as a wrong code.
      expect(
        Capabilities.canDialFrom(
          Uri.parse('https://atlanwhite147.github.io/openzclick/'),
          web: true,
        ),
        isFalse,
      );
    });

    test('the page the bridge serves may, because it is http', () {
      // Same origin as the socket, so nothing is mixed: this is the whole point
      // of the bridge serving its own page.
      expect(
        Capabilities.canDialFrom(
          Uri.parse('http://192.168.1.24:47124/'),
          web: true,
        ),
        isTrue,
      );
    });

    test('a native host dials without asking anyone', () {
      expect(
        Capabilities.canDialFrom(Uri.parse('file:///x'), web: false),
        isTrue,
      );
    });
  });
}

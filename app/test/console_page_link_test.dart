import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/net/console_endpoint.dart';

void main() {
  test('a scanned code carries the bridge and the console port', () {
    expect(
      ConsoleEndpoint.pageLink(
        page: 'https://atlanwhite147.github.io/openzclick/',
        host: '192.168.1.24',
        port: 47124,
        code: 'abcd',
      ),
      'https://atlanwhite147.github.io/openzclick/'
      '?bridge=192.168.1.24%3A47124&code=abcd',
    );
  });

  test('a page without a trailing slash still gets one', () {
    expect(
      ConsoleEndpoint.pageLink(
        page: 'https://example.org/openzclick',
        host: 'box.local',
        port: 47124,
        code: 'abcd',
      ),
      startsWith('https://example.org/openzclick/?bridge='),
    );
  });

  test('the page reads back what the code carried', () {
    final String link = ConsoleEndpoint.pageLink(
      page: 'https://atlanwhite147.github.io/openzclick/',
      host: '192.168.1.24',
      port: 47124,
      code: 'abcd',
    );
    final Uri uri = Uri.parse(link);
    final ({String host, String code})? target = ConsoleEndpoint.fromQuery(
      uri.queryParameters,
    );

    expect(target, isNotNull);
    expect(target!.host, '192.168.1.24:47124');
    expect(target.code, 'abcd');
    // And the page turns that into the WebSocket of the relay.
    expect(
      ConsoleEndpoint.build(target.host, target.code),
      'ws://192.168.1.24:47124/console?token=abcd',
    );
  });

  test('a page opened by hand carries no target', () {
    expect(ConsoleEndpoint.fromQuery(const <String, String>{}), isNull);
    expect(
      ConsoleEndpoint.fromQuery(const <String, String>{'bridge': '1.2.3.4'}),
      isNull,
      reason: 'a host without a code is a half-filled form, not a target',
    );
    expect(
      ConsoleEndpoint.fromQuery(const <String, String>{'code': 'abcd'}),
      isNull,
    );
  });
}

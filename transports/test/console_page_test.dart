import 'dart:convert';
import 'dart:io';

import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';
import 'package:test/test.dart';

Future<HttpClientResponse> _get(int port, String path) async {
  final HttpClient client = HttpClient();
  final HttpClientRequest request = await client.get('127.0.0.1', port, path);
  return request.close();
}

Future<String> _body(int port, String path) async {
  final HttpClientResponse response = await _get(port, path);
  return response.transform(utf8.decoder).join();
}

void main() {
  group('the console page the bridge serves itself', () {
    late WebSocketRelayTransport relay;
    late int port;

    setUp(() async {
      relay = WebSocketRelayTransport(token: 'abcd', port: 0);
      await relay.start();
      port = relay.listeningPort;
    });

    tearDown(() async {
      await relay.stop();
    });

    test('is served on the relay port, so nothing is mixed', () async {
      // The hosted page lives on https:// and a browser refuses to open a ws://
      // socket from it. Serving the document from the bridge itself puts the
      // page and the socket on one origin, which is the whole point.
      final HttpClientResponse response = await _get(port, '/');
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(await response.transform(utf8.decoder).join(), contains('<html'));
    });

    test('offers the two shift buttons and asks for the code', () async {
      final String page = await _body(port, '/');
      expect(page, contains('Shift up'));
      expect(page, contains('Shift down'));
      // Without a code in the URL the field is there for a rider to type it.
      expect(page, contains('id="token"'));
    });

    test('a code in the URL is carried into the page and connects on its own',
        () async {
      // The QR code opens this address: nothing is typed on the phone.
      final String page = await _body(port, '/?token=abcd');
      expect(page, contains('data-token="abcd"'));
    });

    test('a code is escaped, never written raw into the document', () async {
      final String page = await _body(port, '/?token=%22onload%3Dalert(1)');
      expect(page, isNot(contains('data-token=""onload')));
      expect(page, contains('&quot;onload=alert(1)'));
    });

    test('the page address is http on the bridge, next to the socket',
        () async {
      // https would be blocked again, and a different port would be a second
      // thing for a rider to find.
      expect(
        relay.pageUrlFor('192.168.1.24'),
        'http://192.168.1.24:$port/?token=abcd',
      );
      expect(relay.urlFor('192.168.1.24'),
          'ws://192.168.1.24:$port/console?token=abcd');
    });

    test('the socket still accepts the code, and still refuses a wrong one',
        () async {
      final WebSocket socket = await WebSocket.connect(
        'ws://127.0.0.1:$port/console?token=abcd',
      );
      expect(socket.readyState, WebSocket.open);
      await socket.close();

      await expectLater(
        WebSocket.connect('ws://127.0.0.1:$port/console?token=zzzz'),
        throwsA(isA<WebSocketException>()),
      );
    });

    test('a shift pressed on the page reaches the bridge', () async {
      // The buttons are useless if the message never arrives; this is the link
      // between the two halves of the fix.
      final WebSocket socket = await WebSocket.connect(
        'ws://127.0.0.1:$port/console?token=abcd',
      );
      final Future<Action> received = relay.events
          .where((TransportEvent e) => e is TransportActionReceived)
          .map((TransportEvent e) => (e as TransportActionReceived).action)
          .first;
      socket.add(jsonEncode(<String, Object?>{'action': 'shiftUp'}));
      expect(await received, Action.shiftUp);
      await socket.close();
    });

    test('a stopped bridge stops answering, page included', () async {
      await relay.stop();
      await expectLater(_get(port, '/'), throwsA(isA<SocketException>()));
    });
  });
}

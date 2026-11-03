import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/net/console_endpoint.dart';

void main() {
  test('a bare address gets the console port and the path', () {
    expect(
      ConsoleEndpoint.build('192.168.1.24', 'abcd'),
      'ws://192.168.1.24:47124/console?token=abcd',
    );
  });

  test('an address that already carries a port keeps it', () {
    expect(
      ConsoleEndpoint.build('192.168.1.24:9000', 'abcd'),
      'ws://192.168.1.24:9000/console?token=abcd',
    );
  });

  test('a full URL is accepted, and the code appended when missing', () {
    expect(
      ConsoleEndpoint.build('ws://box.local:47124/console', 'abcd'),
      'ws://box.local:47124/console?token=abcd',
    );
    expect(
      ConsoleEndpoint.build('ws://box.local/console?token=abcd', 'zzzz'),
      'ws://box.local/console?token=abcd',
      reason: 'a URL that carries a code is used as typed',
    );
  });

  test('what a rider pastes from a screen is trimmed', () {
    expect(
      ConsoleEndpoint.build('  192.168.1.24  ', ' abcd '),
      'ws://192.168.1.24:47124/console?token=abcd',
    );
  });
}

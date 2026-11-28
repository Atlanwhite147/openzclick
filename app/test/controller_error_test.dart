import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/ble/controller_error.dart';

void main() {
  group('a Bluetooth failure a rider can act on', () {
    test(
      'the plugin stack trace of a machine without radio names the radio',
      () {
        const String raw =
            'FlutterBluePlusException | scan | web-code: 0 | '
            'Null check operator used on a null value';
        final String message = explainControllerError(raw);
        expect(message, isNot(contains('FlutterBluePlus')));
        expect(message, isNot(contains('Null check')));
        expect(message, contains('radio'));
      },
    );

    test('a radio that is off says so instead of failing silently', () {
      expect(
        explainControllerError(
          'FlutterBluePlusException | adapter is turned off',
        ),
        contains('Bluetooth is off'),
      );
    });

    test('a refused permission says which permission', () {
      expect(
        explainControllerError('NotAuthorizedException: notAuthorized'),
        contains('Permission'),
      );
    });

    test('a cancelled chooser is not reported as a fault', () {
      expect(
        explainControllerError('NotFoundException: was cancelled'),
        contains('No controller was chosen'),
      );
    });

    test('an unknown failure still leads with a true sentence', () {
      final String message = explainControllerError('kaboom');
      expect(message, startsWith('The controller could not be reached.'));
      // The original stays for a bug report, after the readable part.
      expect(message, contains('kaboom'));
    });

    test('nothing at all still produces a sentence', () {
      expect(explainControllerError(null), isNotEmpty);
    });
  });
}

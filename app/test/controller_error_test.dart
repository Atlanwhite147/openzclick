import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/ble/controller_error.dart';

void main() {
  group('a Bluetooth failure a rider can act on', () {
    test('the plugin stack trace of a page without Bluetooth becomes advice', () {
      // Exactly what appeared after tapping "Choose a controller" on a machine
      // with no radio: the raw exception, guessing included nothing. A rider can
      // only read it as "the application is broken".
      const String raw =
          'FlutterBluePlusException | scan | web-code: 0 | '
          'Null check operator used on a null value';
      // On localhost the context is secure, so the cause is the browser or the
      // machine, not the page.
      final String message = explainControllerError(raw, isWeb: true);
      expect(message, isNot(contains('FlutterBluePlus')));
      expect(message, isNot(contains('Null check')));
      expect(message, contains('Chrome'));
    });

    test(
      'a plain http page is told to change the address, not the machine',
      () {
        const String raw =
            'FlutterBluePlusException | scan | Null check operator used on a '
            'null value';
        final String message = explainControllerError(
          raw,
          isWeb: true,
          secureContext: false,
        );
        expect(message, contains('https'));
        expect(message, isNot(contains('radio')));
      },
    );

    test('the same plugin failure on a desktop names the missing radio', () {
      const String raw =
          'FlutterBluePlusException | scan | web-code: 0 | '
          'Null check operator used on a null value';
      final String message = explainControllerError(raw, isWeb: false);
      expect(message, contains('radio'));
    });

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

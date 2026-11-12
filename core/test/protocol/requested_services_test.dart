import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

void main() {
  group('what a client asks to be granted', () {
    test('the vendor service comes first, because it is the one guaranteed',
        () {
      // A branch-and-bound error here is silent: Web Bluetooth grants only what
      // a page names, and a page that misses `fc82` pairs with a controller it
      // then cannot talk to at all.
      expect(ControllerUuids.requested.first, ControllerUuids.service);
    });

    test('the battery and the Device Information service are asked for', () {
      expect(
          ControllerUuids.requested, contains(ControllerUuids.batteryService));
      expect(
        ControllerUuids.requested,
        contains(ControllerUuids.deviceInformationService),
      );
    });

    test('no service is asked for twice', () {
      // A duplicate is not harmless: the browser shows one line per requested
      // service, and two identical ones read as a bug in the page.
      expect(
        ControllerUuids.requested.toSet().length,
        ControllerUuids.requested.length,
      );
    });

    test('the identifiers are the ones the controller answers on', () {
      expect(ControllerUuids.service, '0000fc82-0000-1000-8000-00805f9b34fb');
      expect(ControllerUuids.batteryService,
          '0000180f-0000-1000-8000-00805f9b34fb');
      expect(
        ControllerUuids.deviceInformationService,
        '0000180a-0000-1000-8000-00805f9b34fb',
      );
    });
  });
}

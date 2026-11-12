import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

void main() {
  group('which pod a controller is', () {
    test('the right puck is 0x0A, the left 0x0B', () {
      // The codes come from the table bikecontrol publishes for the same family,
      // and they are the only way to tell two pods apart: both announce
      // themselves as "Zwift Click".
      expect(
        controllerSideFromManufacturerData(zwiftManufacturerId, <int>[0x0A]),
        ControllerSide.right,
      );
      expect(
        controllerSideFromManufacturerData(zwiftManufacturerId, <int>[0x0B]),
        ControllerSide.left,
      );
    });

    test('a payload from another manufacturer says nothing', () {
      // Guessing here would tell a rider to press a pod they are not holding.
      expect(controllerSideFromManufacturerData(0x004C, <int>[0x0A]), isNull);
      expect(controllerSideFromManufacturerData(zwiftManufacturerId, <int>[]),
          isNull);
    });

    test('a code this table does not know stays unnamed', () {
      // A Ride or an RC1 carries its own code; naming it "right" would be an
      // invention until one is measured.
      expect(
        controllerSideFromManufacturerData(zwiftManufacturerId, <int>[0x07]),
        isNull,
      );
    });

    test('the whole advertising map is read by identifier', () {
      final Map<int, List<int>> advertising = <int, List<int>>{
        0x004C: <int>[0x02, 0x15],
        zwiftManufacturerId: <int>[0x0A, 0x00],
      };
      expect(
          controllerSideFromAdvertisement(advertising), ControllerSide.right);
      expect(controllerSideFromAdvertisement(<int, List<int>>{}), isNull);
    });

    test('the labels name the pod a rider is holding', () {
      expect(controllerSideLabel(ControllerSide.right), contains('right'));
      expect(controllerSideLabel(ControllerSide.left), contains('left'));
      expect(controllerSideLabel(null), contains('not announced'));
    });
  });
}

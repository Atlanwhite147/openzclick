/// Which half of a Zwift controller pair a device is.
///
/// Two pods advertise the same name — `Zwift Click` — and the application has no
/// way to tell them apart without reading the manufacturer data. That matters
/// beyond curiosity: measured and documented elsewhere, the **left** puck is
/// locked to Zwift and closes a plain session about a minute after it opens,
/// while the right one is expected to hold. A rider told "use the right pod" had
/// no way to check which one they were actually pressing.
library;

/// Which side of a pair a controller is.
enum ControllerSide {
  /// The right puck: `+` and `B`, shifting without any unlock.
  right,

  /// The left puck: the arrows, and the one Zwift locks.
  left,
}

/// The manufacturer identifier Zwift writes in its advertising data.
const int zwiftManufacturerId = 0x094A;

/// Reads the side out of a Zwift advertising payload.
///
/// The first byte of the manufacturer data is a model-and-side code, taken from
/// the table `bikecontrol` publishes for the same family. Returns null when the
/// payload is not Zwift's, or carries a code this table does not know: a guess
/// here would tell a rider to press a pod they are not holding.
ControllerSide? controllerSideFromManufacturerData(
  int manufacturerId,
  List<int> data,
) {
  if (manufacturerId != zwiftManufacturerId) return null;
  if (data.isEmpty) return null;
  switch (data.first) {
    // Click v2: 0x0A right, 0x0B left.
    case 0x0A:
      return ControllerSide.right;
    case 0x0B:
      return ControllerSide.left;
    default:
      return null;
  }
}

/// Reads the side out of a whole advertising map, whatever key case the platform
/// used.
ControllerSide? controllerSideFromAdvertisement(
  Map<int, List<int>> manufacturerData,
) {
  final List<int>? zwift = manufacturerData[zwiftManufacturerId];
  if (zwift == null) return null;
  return controllerSideFromManufacturerData(zwiftManufacturerId, zwift);
}

/// Human-readable name, for the controller list and the report.
String controllerSideLabel(ControllerSide? side) => switch (side) {
      ControllerSide.right => 'right pod (+)',
      ControllerSide.left => 'left pod (arrows, locked to Zwift)',
      null => 'side not announced',
    };

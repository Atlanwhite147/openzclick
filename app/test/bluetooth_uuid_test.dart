import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/ble/bluetooth_uuid.dart';

void main() {
  test('a SIG service compares equal in its short and long forms', () {
    // Windows answers "fc82" where the specification and every other host use
    // the full string: comparing the raw strings found no service at all on a
    // controller that exposed one.
    expect(
      sameUuid('fc82', '0000fc82-0000-1000-8000-00805f9b34fb'),
      isTrue,
    );
    expect(
      sameUuid('FC82', '0000fc82-0000-1000-8000-00805f9b34fb'),
      isTrue,
    );
  });

  test('a custom 128 bit channel keeps its full identity', () {
    const String async = '00000002-19ca-4651-86e5-fa29dcdd09d1';
    expect(sameUuid(async, async.toUpperCase()), isTrue);
    expect(
      sameUuid(async, '00000003-19ca-4651-86e5-fa29dcdd09d1'),
      isFalse,
    );
  });

  test('the bare 128 bit form without its base suffix also matches', () {
    expect(sameUuid('fc82', 'fc82-0000-1000-8000-00805f9b34fb'), isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:openzclick_core/openzclick_core.dart';

import 'fake_publisher.dart';

void main() {
  test('one press crosses as many gears as configured', () {
    // Measured on the real machine before this rule existed: with the multiplier
    // at 3, one press moved the gear from 8 to 9 while the application was sent
    // three keys. The screen and the application disagreed, which is worse than
    // having no multiplier at all.
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);
    expect(state.shiftsPerPress, 1);

    state.setShiftsPerPress(3);
    final int before = state.engine.gearIndex;

    state.shiftUp();

    expect(state.engine.gearIndex, before + 3);
  });

  test('the multiplier stops at the end of the ladder', () {
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);
    state.setShiftsPerPress(3);
    for (int i = 0; i < 20; i++) {
      state.shiftUp();
    }
    expect(state.engine.gearIndex, state.engine.gearCount - 1);
  });

  test('a multiplier of one is one gear, as before', () {
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);
    final int before = state.engine.gearIndex;
    state.shiftDown();
    expect(state.engine.gearIndex, before - 1);
  });
}

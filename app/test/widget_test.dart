import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/main.dart';
import 'package:openzclick/state/app_state.dart';

void main() {
  testWidgets('trainer screen shows the default gear', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenZclickApp());
    await tester.pumpAndSettle();

    expect(find.text('Gear'), findsOneWidget);
    expect(find.textContaining('/ 12'), findsWidgets);
  });

  testWidgets('shift up changes the displayed gear', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenZclickApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Shift up'));
    await tester.pumpAndSettle();

    expect(find.text('7 / 12'), findsOneWidget);
  });

  test('state starts in simulation mode with the road profile', () {
    final AppState state = AppState();
    expect(state.engine.gearCount, 12);
    expect(state.engine.mode.name, 'sim');
    state.dispose();
  });
}

import 'package:openzclick_core/src/mapping/key_injector.dart';
import 'package:test/test.dart';

/// Fake implementation that records the calls it receives.
class _RecordingInjector implements KeyInjector {
  final List<String> calls = <String>[];

  @override
  Future<void> pressKey(String key) async {
    calls.add('key:$key');
  }

  @override
  Future<void> tapAt(double x, double y) async {
    calls.add('tap:${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}');
  }
}

void main() {
  group('KeyInjector', () {
    test('a port can be implemented and receives calls in order', () async {
      final _RecordingInjector injector = _RecordingInjector();
      await injector.tapAt(12.5, 40.5);
      await injector.pressKey('KeyW');
      expect(injector.calls, <String>['tap:12.5,40.5', 'key:KeyW']);
    });

    test('methods return a Future', () {
      final _RecordingInjector injector = _RecordingInjector();
      expect(injector.tapAt(0, 0), isA<Future<void>>());
      expect(injector.pressKey('Space'), isA<Future<void>>());
    });
  });
}

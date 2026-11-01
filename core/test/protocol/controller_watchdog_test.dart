import 'package:openzclick_core/src/protocol/openzclick_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ControllerLinkWatchdog', () {
    late ControllerLinkWatchdog watchdog;

    setUp(() {
      watchdog = ControllerLinkWatchdog(
        plainFallbackAfter: const Duration(seconds: 3),
        unlockHintAfter: const Duration(seconds: 10),
        silenceBeforeReconnect: const Duration(seconds: 45),
      );
      watchdog.onConnected();
    });

    test('nothing happens right after connecting', () {
      expect(watchdog.onElapsed(const Duration(seconds: 1)), isNull);
      expect(watchdog.frameSeen, isFalse);
      expect(watchdog.plainSent, isFalse);
    });

    test('the plain handshake is requested once, after the fallback delay', () {
      expect(watchdog.onElapsed(const Duration(seconds: 2)), isNull);
      expect(
        watchdog.onElapsed(const Duration(seconds: 1)),
        ControllerLinkAction.sendPlainHandshake,
      );
      expect(watchdog.plainSent, isTrue);
      expect(
        watchdog.onElapsed(const Duration(seconds: 1)),
        isNull,
        reason: 'the request must not repeat',
      );
    });

    test('an acknowledged handshake cancels the fallback', () {
      watchdog.onFrame();
      expect(
        watchdog.onElapsed(const Duration(seconds: 5)),
        isNull,
        reason: 'the controller answered, no fallback needed',
      );
      expect(watchdog.plainSent, isFalse);
      expect(watchdog.frameSeen, isTrue);
    });

    test('total silence is blamed on the controller lock, once', () {
      expect(
        watchdog.onElapsed(const Duration(seconds: 3)),
        ControllerLinkAction.sendPlainHandshake,
      );
      expect(watchdog.onElapsed(const Duration(seconds: 6)), isNull);
      expect(
        watchdog.onElapsed(const Duration(seconds: 1)),
        ControllerLinkAction.needsUnlock,
      );
      expect(watchdog.unlockHinted, isTrue);
      expect(watchdog.onElapsed(const Duration(seconds: 30)), isNull);
    });

    test('a silent established link asks for a reconnection', () {
      watchdog.onFrame();
      expect(watchdog.onElapsed(const Duration(seconds: 44)), isNull);
      expect(
        watchdog.onElapsed(const Duration(seconds: 1)),
        ControllerLinkAction.reconnect,
      );
      expect(
        watchdog.onElapsed(const Duration(seconds: 1)),
        isNull,
        reason: 'one reconnection at a time',
      );
    });

    test('traffic pushes the reconnection back', () {
      watchdog.onFrame();
      watchdog.onElapsed(const Duration(seconds: 40));
      watchdog.onFrame();
      expect(watchdog.onElapsed(const Duration(seconds: 40)), isNull);
      expect(
        watchdog.onElapsed(const Duration(seconds: 5)),
        ControllerLinkAction.reconnect,
      );
    });

    test('a reconnection resets the supervision', () {
      watchdog.onFrame();
      watchdog.onElapsed(const Duration(seconds: 45));
      watchdog.onConnected();
      expect(watchdog.frameSeen, isFalse);
      expect(watchdog.plainSent, isFalse);
      expect(watchdog.unlockHinted, isFalse);
      expect(watchdog.onElapsed(const Duration(seconds: 1)), isNull);
    });

    test('the fallback must come before the unlock hint', () {
      expect(
        () => ControllerLinkWatchdog(
          plainFallbackAfter: const Duration(seconds: 10),
          unlockHintAfter: const Duration(seconds: 3),
        ),
        throwsArgumentError,
      );
    });

    test('a negative elapsed time is refused', () {
      expect(
        () => watchdog.onElapsed(const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });
  });
}

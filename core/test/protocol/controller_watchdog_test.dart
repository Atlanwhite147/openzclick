import 'package:openzclick_core/src/protocol/openzclick_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ControllerLinkWatchdog', () {
    late ControllerLinkWatchdog watchdog;

    setUp(() {
      watchdog = ControllerLinkWatchdog(
        plainFallbackAfter: const Duration(seconds: 3),
        unlockHintAfter: const Duration(seconds: 10),
        keepaliveInterval: const Duration(seconds: 3),
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
      // Nothing answers at all. The plain handshake goes out, then the keepalive
      // cadence starts anyway — that write is the only thing that can wake a
      // controller — and the lock is named once, ten seconds in.
      expect(
        watchdog.onElapsed(const Duration(seconds: 3)),
        ControllerLinkAction.sendPlainHandshake,
      );
      expect(
        watchdog.onElapsed(const Duration(seconds: 3)),
        ControllerLinkAction.sendKeepalive,
      );
      expect(
        watchdog.onElapsed(const Duration(seconds: 3)),
        ControllerLinkAction.sendKeepalive,
      );
      expect(
        watchdog.onElapsed(const Duration(seconds: 1)),
        ControllerLinkAction.needsUnlock,
      );
      expect(watchdog.unlockHinted, isTrue);
      expect(
        watchdog.onElapsed(const Duration(seconds: 10)),
        anyOf(isNull, ControllerLinkAction.sendKeepalive),
        reason: 'the unlock hint is said once',
      );
    });

    test('a silent established link asks for a keepalive, not a reconnection',
        () {
      // Measured on a Click v2: the pod drops roughly a minute after the last
      // write it received, and coasting without pressing a button is normal.
      // So silence asks for a keepalive, and only a failed write is a reason to
      // reconnect.
      watchdog.onFrame();
      watchdog.onPlainHandshakeSent();
      expect(
        watchdog.onElapsed(const Duration(seconds: 3)),
        ControllerLinkAction.sendKeepalive,
      );
      expect(watchdog.onElapsed(const Duration(seconds: 2)), isNull);
      expect(
        watchdog.onElapsed(const Duration(seconds: 1)),
        ControllerLinkAction.sendKeepalive,
        reason: 'three seconds after the last one',
      );
      for (int i = 0; i < 200; i++) {
        final ControllerLinkAction? action = watchdog.onElapsed(
          const Duration(seconds: 1),
        );
        expect(
          action,
          anyOf(isNull, ControllerLinkAction.sendKeepalive),
          reason: 'no reconnection is ever asked for because of silence',
        );
      }
    });

    test('a frame pushes the keepalive back', () {
      watchdog.onPlainHandshakeSent();
      expect(watchdog.onElapsed(const Duration(seconds: 2)), isNull);
      watchdog.onFrame();
      expect(
        watchdog.onElapsed(const Duration(seconds: 2)),
        isNull,
        reason: 'the link just spoke',
      );
      expect(
        watchdog.onElapsed(const Duration(seconds: 1)),
        ControllerLinkAction.sendKeepalive,
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

    test('a keepalive cadence of zero is refused', () {
      expect(
        () => ControllerLinkWatchdog(keepaliveInterval: Duration.zero),
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

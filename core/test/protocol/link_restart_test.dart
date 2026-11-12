import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

void main() {
  group('restarting a link before the controller closes it', () {
    test('a young link is left alone', () {
      // A restart is a two-second hole in the button stream: it must not happen
      // on every tick.
      const LinkPolicy policy = LinkPolicy();
      expect(policy.wantsRestart(Duration.zero), isFalse);
      expect(policy.wantsRestart(const Duration(seconds: 30)), isFalse);
      expect(policy.wantsRestart(const Duration(seconds: 49)), isFalse);
    });

    test('the restart comes before the minute the pod closes at', () {
      // Measured on the right pod, 2026-11-12: the session closes at 57 to 62 s
      // whatever is written to it, and a closed pod cannot be reached again
      // without a press. The margin is what makes the workaround invisible.
      const LinkPolicy policy = LinkPolicy();
      expect(policy.restartAfter, const Duration(seconds: 50));
      expect(policy.wantsRestart(const Duration(seconds: 50)), isTrue);
      expect(
        policy.restartAfter,
        lessThan(const Duration(seconds: 57)),
        reason: 'the restart has to land while the pod still answers',
      );
    });

    test('the cadence can be shortened or lengthened by the caller', () {
      const LinkPolicy slow = LinkPolicy(restartAfter: Duration(seconds: 45));
      expect(slow.wantsRestart(const Duration(seconds: 46)), isTrue);
      expect(slow.wantsRestart(const Duration(seconds: 44)), isFalse);
    });
  });
}

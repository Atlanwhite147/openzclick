import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

void main() {
  group('battery watch', () {
    test('a comfortable level says nothing', () {
      final BatteryWatch watch = BatteryWatch();
      expect(watch.observe(90), BatteryNotice.none);
      expect(watch.observe(45), BatteryNotice.none);
      expect(watch.percent, 45);
      expect(watch.warns, isFalse);
    });

    test('the low mark warns once, not once per frame', () {
      // A pod reports its status repeatedly; a warning per frame would be a
      // banner the rider cannot read and would learn to ignore.
      final BatteryWatch watch = BatteryWatch();
      watch.observe(60);
      expect(watch.observe(20), BatteryNotice.low);
      expect(watch.observe(19), BatteryNotice.none);
      expect(watch.observe(18), BatteryNotice.none);
      expect(watch.warns, isTrue);
    });

    test('a low battery that gets worse escalates to critical', () {
      final BatteryWatch watch = BatteryWatch();
      watch.observe(20);
      expect(watch.observe(8), BatteryNotice.critical);
      expect(watch.observe(7), BatteryNotice.none, reason: 'already announced');
    });

    test('going straight to critical announces critical, not low', () {
      final BatteryWatch watch = BatteryWatch();
      expect(watch.observe(5), BatteryNotice.critical);
    });

    test('climbing back above the low mark clears the warning once', () {
      final BatteryWatch watch = BatteryWatch();
      watch.observe(15);
      expect(watch.observe(31), BatteryNotice.recovered);
      expect(watch.observe(40), BatteryNotice.none);
      expect(watch.warns, isFalse);
    });

    test('hovering around the mark does not flap', () {
      // The reason recoverAt sits above lowAt: 19, 21, 19, 21 is one battery, not
      // four events.
      final BatteryWatch watch = BatteryWatch();
      expect(watch.observe(21), BatteryNotice.none);
      expect(watch.observe(19), BatteryNotice.low);
      expect(watch.observe(21), BatteryNotice.none);
      expect(watch.observe(19), BatteryNotice.none);
      expect(watch.warns, isTrue);
    });

    test('an unknown level keeps what was known', () {
      final BatteryWatch watch = BatteryWatch();
      watch.observe(12);
      expect(watch.observe(DeviceStatusMessage.unknownBattery),
          BatteryNotice.none);
      expect(watch.percent, 12);
      expect(watch.warns, isTrue);
      expect(watch.observe(-3), BatteryNotice.none);
    });

    test('reset forgets both the level and the warning', () {
      final BatteryWatch watch = BatteryWatch();
      watch.observe(6);
      watch.reset();
      expect(watch.percent, isNull);
      expect(watch.warns, isFalse);
      expect(watch.observe(6), BatteryNotice.critical);
    });

    test('incoherent thresholds are refused', () {
      expect(
          () => BatteryWatch(lowAt: 10, criticalAt: 20), throwsArgumentError);
      expect(() => BatteryWatch(lowAt: 20, recoverAt: 20), throwsArgumentError);
    });
  });

  group('link policy', () {
    const LinkPolicy policy = LinkPolicy();

    test('nothing happens to a live link while an application wants it', () {
      final LinkDecision decision = policy.decide(
        const LinkSituation(connected: true, applicationPresent: true),
      );
      expect(decision.directive, LinkDirective.nothing);
    });

    test('a failed write reconnects, whatever else is true', () {
      final LinkDecision decision = policy.decide(
        const LinkSituation(
          connected: true,
          applicationPresent: true,
          writeFailed: true,
        ),
      );
      expect(decision.directive, LinkDirective.reconnect);
      expect(decision.reason, contains('acknowledging'));
    });

    test('an application waiting with no link gets one', () {
      final LinkDecision decision = policy.decide(
        const LinkSituation(connected: false, applicationPresent: true),
      );
      expect(decision.directive, LinkDirective.connect);
    });

    test('no application, no link, nothing to do', () {
      final LinkDecision decision = policy.decide(
        const LinkSituation(connected: false, applicationPresent: false),
      );
      expect(decision.directive, LinkDirective.nothing);
    });

    test('a short pause keeps the link: a bottle is not a session end', () {
      final LinkDecision decision = policy.decide(
        const LinkSituation(
          connected: true,
          applicationPresent: false,
          sinceSessionEnd: Duration(minutes: 4),
        ),
      );
      expect(decision.directive, LinkDirective.nothing);
    });

    test('ten minutes without an application release the pod', () {
      final LinkDecision decision = policy.decide(
        const LinkSituation(
          connected: true,
          applicationPresent: false,
          sinceSessionEnd: Duration(minutes: 10),
        ),
      );
      expect(decision.directive, LinkDirective.release);
      expect(decision.reason, contains('10 minutes'));
    });

    test('a critical battery only releases when nothing is using the buttons',
        () {
      const LinkPolicy releasing = LinkPolicy(releaseOnCriticalBattery: true);
      expect(
        releasing
            .decide(
              const LinkSituation(
                connected: true,
                applicationPresent: true,
                batteryCritical: true,
              ),
            )
            .directive,
        LinkDirective.nothing,
        reason: 'never cut a rider mid-ride',
      );
      expect(
        releasing
            .decide(
              const LinkSituation(
                connected: true,
                applicationPresent: false,
                batteryCritical: true,
              ),
            )
            .directive,
        LinkDirective.release,
      );
    });

    test('by default a critical battery does not end the link', () {
      // The default is the conservative one: the measurement that would justify
      // acting on the battery alone does not exist yet.
      final LinkDecision decision = policy.decide(
        const LinkSituation(
          connected: true,
          applicationPresent: false,
          batteryCritical: true,
          sinceSessionEnd: Duration(minutes: 1),
        ),
      );
      expect(decision.directive, LinkDirective.nothing);
    });
  });
}

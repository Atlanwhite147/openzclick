import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/ble/device_report.dart';
import 'package:openzclick/platform/bug_report.dart';

/// The report a rider is offered to publish.
///
/// Two promises are held here, and they are the reason this file exists:
/// nothing that identifies the rider leaves the machine, and what does leave is
/// enough to reproduce the fault.
void main() {
  DeviceReport full() => DeviceReport(
    generatedAt: DateTime.utc(2026, 11, 4, 12, 30, 15),
    appVersion: '0.3.3+6',
    host: 'windows',
    deviceName: 'Zwift Click',
    deviceId: 'F4:12:34:56:78:9A',
    status: 'ready',
    encrypted: true,
    batteryPercent: 87,
    information: const DeviceInformation(
      manufacturer: 'Zwift',
      model: 'Click v2',
      serial: 'SN-0123456789',
      firmware: '1.1.0',
      hardware: '1.0',
    ),
  );

  group('nothing personal leaves the machine', () {
    test('the device identifier is redacted, not blanked', () {
      final String text = full().anonymized().render();
      expect(text, isNot(contains('F4:12:34:56:78:9A')));
      // Still there as a line: a maintainer needs to see that two references
      // in a report are the same device.
      expect(text, contains('id       redacted'));
    });

    test('the serial number is redacted', () {
      final String text = full().anonymized().render();
      expect(text, isNot(contains('SN-0123456789')));
      expect(text, contains('serial       redacted'));
    });

    test('a MAC inside an error message is redacted too', () {
      // Windows names the device it failed on, inside the error string.
      final DeviceReport report = DeviceReport(
        generatedAt: DateTime.utc(2026, 11, 4),
        appVersion: '0.3.3+6',
        host: 'windows',
        error: 'connect failed for F4:12:34:56:78:9A: device is not connected',
      );
      final String text = report.anonymized().render();
      expect(text, isNot(contains('F4:12:34:56:78:9A')));
      expect(text, contains('redacted'));
      expect(text, contains('device is not connected'));
    });

    test('an address embedded inside a word is redacted', () {
      // Measured shape of a WinRT error, where the first pair sits against a
      // letter and a word boundary never matches. The first pattern missed
      // this and left a fragment of the address behind.
      const String error =
          'WinRT: GattSession for BluetoothLE#BluetoothLEf4:12:34:56:78:9a-aa:bb '
          'failed';
      expect(redactMacAddresses(error), isNot(contains('12:34:56')));
      expect(redactMacAddresses(error), isNot(contains(':bb')));
    });

    test('an address without separators is redacted', () {
      expect(redactMacAddresses('id 001A7DDA7113 here'), 'id redacted here');
    });

    test('the scrub leaves versions, UUIDs and frames alone', () {
      // Over-redacting makes the report useless: these are the diagnostics.
      expect(redactMacAddresses('firmware 1.1.0'), 'firmware 1.1.0');
      expect(redactMacAddresses('characteristic 0002'), 'characteristic 0002');
      expect(
        redactMacAddresses('frame 23 08 ff df ff ff 0f'),
        'frame 23 08 ff df ff ff 0f',
      );
    });

    test('the raw render is unchanged: only the copy is scrubbed', () {
      // A rider who copies the report for a conversation keeps the detail; the
      // scrub is what the publish button applies.
      expect(full().render(), contains('F4:12:34:56:78:9A'));
    });
  });

  group('what a maintainer needs is still there', () {
    test('version, platform, model and firmware survive', () {
      final String text = full().anonymized().render();
      expect(text, contains('version  0.3.3+6'));
      expect(text, contains('host     windows'));
      expect(text, contains('Click v2'));
      expect(text, contains('firmware     1.1.0'));
      expect(text, contains('87 %'));
    });

    test('the device name survives: it tells a v1 from a v2', () {
      expect(full().anonymized().render(), contains('Zwift Click'));
    });
  });

  group('the URL GitHub is given', () {
    test('points at the repository, with the bug label', () {
      final Uri url = BugReport.issueUrl(report: full());
      expect(url.host, 'github.com');
      expect(url.path, '/Atlanwhite147/openzclick/issues/new');
      expect(url.queryParameters['labels'], 'bug');
    });

    test('carries the report in the body', () {
      final Uri url = BugReport.issueUrl(report: full());
      final String body = url.queryParameters['body']!;
      expect(body, contains('openzclick device report'));
      expect(body, contains('firmware     1.1.0'));
      expect(body, contains('What happened:'));
      // And says so out loud, because the rider is publishing it.
      expect(body, contains('cleaned before opening'));
    });

    test('carries no identifier in the body either', () {
      final String body = BugReport.issueUrl(report: full())
          .queryParameters['body']!;
      expect(body, isNot(contains('F4:12:34:56:78:9A')));
      expect(body, isNot(contains('SN-0123456789')));
    });

    test('a typed summary becomes the title', () {
      final Uri url = BugReport.issueUrl(
        report: full(),
        summary: 'Buttons stop after one minute',
      );
      expect(url.queryParameters['title'], 'Buttons stop after one minute');
    });

    test('no summary still gives a searchable title', () {
      final Uri url = BugReport.issueUrl(report: full());
      expect(url.queryParameters['title'], 'Bug report on windows');
    });

    test('a title is capped rather than sent truncated by GitHub', () {
      final Uri url = BugReport.issueUrl(report: full(), summary: 'x' * 400);
      final String title = url.queryParameters['title']!;
      expect(title.length, BugReport.titleLimit);
      expect(title.endsWith('...'), isTrue);
    });

    test('a newline in the summary does not break the title', () {
      // The query string is percent encoded, but a title that arrives with a
      // newline in it reads as two issues.
      final Uri url = BugReport.issueUrl(
        report: full(),
        summary: 'passed\nno answer',
      );
      expect(url.queryParameters['title'], 'passed no answer');
    });
  });
}

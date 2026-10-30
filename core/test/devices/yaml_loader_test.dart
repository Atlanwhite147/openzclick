import 'package:openzclick_core/src/devices/openzclick_devices.dart';
import 'package:test/test.dart';

void main() {
  group('MiniYaml', () {
    test('parses a flat mapping with typed scalars', () {
      final document = MiniYaml.parse('''
# leading comment
id: two-button-controller # trailing comment
count: 42
hex: 0xFF
mask: 0b1010
ratio: 1.5
enabled: true
missing: null
titled: "value: with colon"
''');

      expect(document, isA<Map<String, Object?>>());
      final map = document! as Map<String, Object?>;
      expect(map['id'], 'two-button-controller');
      expect(map['count'], 42);
      expect(map['hex'], 255);
      expect(map['mask'], 10);
      expect(map['ratio'], 1.5);
      expect(map['enabled'], isTrue);
      expect(map['missing'], isNull);
      expect(map['titled'], 'value: with colon');
    });

    test('parses a sequence of nested mappings', () {
      final document = MiniYaml.parse('''
devices:
  - id: first
    name: First device
    services:
      - fff0
      - ffe0
  - id: second
    name: Second device
    flags: [fast, "with space", 3]
''');

      final map = document! as Map<String, Object?>;
      final devices = map['devices']! as List<Object?>;
      expect(devices, hasLength(2));

      final first = devices.first! as Map<String, Object?>;
      expect(first['id'], 'first');
      expect(first['name'], 'First device');
      expect(first['services'], <Object?>['fff0', 'ffe0']);

      final second = devices[1]! as Map<String, Object?>;
      expect(second['id'], 'second');
      expect(second['flags'], <Object?>['fast', 'with space', 3]);
    });

    test('parses quotes and escapes', () {
      final document = MiniYaml.parse(r'''
name: 'The device'
text: "a\tb"
backslash: "c\\d"
unicode: "\u03bb"
''');

      final map = document! as Map<String, Object?>;
      expect(map['name'], 'The device');
      expect(map['text'], 'a\tb');
      expect(map['backslash'], r'c\d');
      expect(map['unicode'], 'λ');
    });

    test('parses a nested inline map', () {
      final document = MiniYaml.parse('options: {a: 1, b: two, c: [x, y]}');
      final map = document! as Map<String, Object?>;
      final options = map['options']! as Map<String, Object?>;
      expect(options['a'], 1);
      expect(options['b'], 'two');
      expect(options['c'], <Object?>['x', 'y']);
    });

    test('tolerates an empty or comment-only source', () {
      expect(MiniYaml.parse(''), isNull);
      expect(MiniYaml.parse('# nothing\n\n   \n'), isNull);
    });

    test('separates multiple documents', () {
      final documents = MiniYaml.parseDocuments('''
---
id: first
---
id: second
...
''');
      expect(documents, hasLength(2));
      expect((documents[0]! as Map<String, Object?>)['id'], 'first');
      expect((documents[1]! as Map<String, Object?>)['id'], 'second');
    });

    test('refuses a tab in the indentation', () {
      expect(
        () => MiniYaml.parse('id: a\n\tname: b\n'),
        throwsA(
          isA<YamlFormatException>().having(
            (error) => error.line,
            'line',
            2,
          ),
        ),
      );
    });

    test('refuses a duplicate key', () {
      expect(
        () => MiniYaml.parse('id: a\nid: b\n'),
        throwsA(
          isA<YamlFormatException>().having(
            (error) => error.message,
            'message',
            contains('duplicate'),
          ),
        ),
      );
    });

    test('refuses a line without a colon inside a mapping', () {
      expect(
        () => MiniYaml.parse('no separator here\n'),
        throwsA(isA<YamlFormatException>()),
      );
    });

    test('refuses an unterminated string', () {
      expect(
        () => MiniYaml.parse('name: "open\n'),
        throwsA(
          isA<YamlFormatException>().having(
            (error) => error.message,
            'message',
            contains('unterminated'),
          ),
        ),
      );
    });

    test('refuses an unterminated inline collection', () {
      expect(
        () => MiniYaml.parse('flags: [a, b\n'),
        throwsA(
          isA<YamlFormatException>().having(
            (error) => error.message,
            'message',
            contains('not terminated'),
          ),
        ),
      );
    });
  });

  group('DeviceYamlLoader', () {
    const source = '''
id: test-controller
name: Test controller
manufacturer: Generic
services:
  - 0000fff0-0000-1000-8000-00805f9b34fb
characteristics:
  buttons: 0000fff1-0000-1000-8000-00805f9b34fb
decoder: raw-bytes
raw_to_button:
  0x01: 0x01
  0x02: 0x02
wake_on_press: true
sleep_after_seconds: 120
''';

    test('loads a single definition', () {
      final definition = DeviceYamlLoader.load(source);
      expect(definition.id, 'test-controller');
      expect(definition.decoderId, 'raw-bytes');
      expect(definition.rawToButton, <int, int>{0x01: 0x01, 0x02: 0x02});
      expect(definition.wakeOnPress, isTrue);
      expect(definition.sleepAfterSeconds, 120);
    });

    test('loads a list under the devices key', () {
      final definitions = DeviceYamlLoader.loadAll('''
devices:
  - id: first
    name: First
    manufacturer: Generic
    services: [fff0]
    characteristics: {buttons: fff1}
    decoder: raw-bytes
  - id: second
    name: Second
    manufacturer: Generic
    services: [ffe0]
    characteristics: {buttons: ffe1}
    decoder: uart-framed
''');
      expect(definitions, hasLength(2));
      expect(definitions.map((d) => d.id), <String>['first', 'second']);
    });

    test('loads definitions spread over several documents', () {
      final definitions = DeviceYamlLoader.loadAll('''
---
id: first
name: First
manufacturer: Generic
services: [fff0]
characteristics: {buttons: fff1}
decoder: raw-bytes
---
id: second
name: Second
manufacturer: Generic
services: [ffe0]
characteristics: {buttons: ffe1}
decoder: raw-bytes
''');
      expect(definitions.map((d) => d.id), <String>['first', 'second']);
    });

    test('refuses several devices when only one is expected', () {
      expect(
        () => DeviceYamlLoader.load('''
devices:
  - id: first
    name: First
    manufacturer: Generic
    services: [fff0]
    characteristics: {buttons: fff1}
    decoder: raw-bytes
  - id: second
    name: Second
    manufacturer: Generic
    services: [ffe0]
    characteristics: {buttons: ffe1}
    decoder: raw-bytes
'''),
        throwsA(isA<YamlFormatException>()),
      );
    });

    test('propagates definition errors', () {
      expect(
        () => DeviceYamlLoader.load('''
id: First
name: First
manufacturer: Generic
services: [fff0]
characteristics: {buttons: fff1}
decoder: raw-bytes
'''),
        throwsA(isA<DeviceDefinitionException>()),
      );
    });

    test('returns an unmodifiable list', () {
      final definitions = DeviceYamlLoader.loadAll(source);
      expect(() => definitions.clear(), throwsUnsupportedError);
    });
  });
}

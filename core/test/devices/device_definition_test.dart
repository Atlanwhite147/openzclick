import 'package:openzclick_core/src/devices/openzclick_devices.dart';
import 'package:test/test.dart';

Map<String, Object?> _validMap() => <String, Object?>{
      'id': 'test-controller',
      'name': 'Test controller',
      'manufacturer': 'Generic',
      'services': <Object?>['0000fff0-0000-1000-8000-00805f9b34fb'],
      'characteristics': <Object?, Object?>{
        'buttons': '0000fff1-0000-1000-8000-00805f9b34fb',
      },
      'decoder': 'raw-bytes',
      'raw_to_button': <Object?, Object?>{'0x01': '0x01'},
    };

void main() {
  group('DeviceDefinition.fromMap', () {
    test('builds a complete definition', () {
      final definition = DeviceDefinition.fromMap(_validMap());

      expect(definition.id, 'test-controller');
      expect(definition.name, 'Test controller');
      expect(definition.manufacturer, 'Generic');
      expect(definition.serviceUuids, <String>[
        '0000fff0-0000-1000-8000-00805f9b34fb',
      ]);
      expect(definition.characteristics['buttons'],
          '0000fff1-0000-1000-8000-00805f9b34fb');
      expect(definition.decoderId, 'raw-bytes');
      expect(definition.rawToButton, <int, int>{0x01: 0x01});
      expect(definition.wakeOnPress, isFalse);
      expect(definition.sleepAfterSeconds, isNull);
      expect(definition.staysAwake, isTrue);
    });

    test('applies the default values', () {
      final map = _validMap()
        ..remove('raw_to_button')
        ..remove('decoder');
      map['decoder'] = 'raw-bytes';
      final definition = DeviceDefinition.fromMap(map);
      expect(definition.rawToButton, isEmpty);
      expect(definition.wakeOnPress, isFalse);
      expect(definition.staysAwake, isTrue);
    });

    test('accepts key aliases', () {
      final definition = DeviceDefinition.fromMap(<String, Object?>{
        'id': 'alias-test',
        'name': 'Alias',
        'manufacturer': 'Generic',
        'service_uuids': <Object?>['fff0'],
        'characteristics': <Object?, Object?>{'buttons': 'fff1'},
        'decoder_id': 'raw-bytes',
        'rawToButton': <Object?, Object?>{1: 1},
        // Yes/no aliases stay supported by the parser.
        'wakeOnPress': 'yes',
        'sleepAfterSeconds': '0x10',
      });

      expect(definition.serviceUuids, <String>['fff0']);
      expect(definition.decoderId, 'raw-bytes');
      expect(definition.rawToButton, <int, int>{1: 1});
      expect(definition.wakeOnPress, isTrue);
      expect(definition.sleepAfterSeconds, 16);
    });

    test('normalises UUIDs to lowercase', () {
      final map = _validMap();
      map['services'] = <Object?>['{0000FFF0-0000-1000-8000-00805F9B34FB}'];
      final definition = DeviceDefinition.fromMap(map);
      expect(
        definition.serviceUuids,
        <String>['0000fff0-0000-1000-8000-00805f9b34fb'],
      );
    });

    test('reads sleep_after_seconds of zero as no sleep', () {
      final map = _validMap()..['sleep_after_seconds'] = 0;
      expect(DeviceDefinition.fromMap(map).sleepAfterSeconds, isNull);
    });

    test('refuses a missing id', () {
      final map = _validMap()..remove('id');
      expect(
        () => DeviceDefinition.fromMap(map),
        throwsA(
          isA<DeviceDefinitionException>().having(
            (error) => error.message,
            'message',
            contains('id'),
          ),
        ),
      );
    });

    test('refuses an id that is not kebab-case', () {
      final map = _validMap()..['id'] = 'Two Button Controller';
      expect(
        () => DeviceDefinition.fromMap(map),
        throwsA(isA<DeviceDefinitionException>()),
      );
    });

    test('refuses an empty list of services', () {
      final map = _validMap()..['services'] = <Object?>[];
      expect(
        () => DeviceDefinition.fromMap(map),
        throwsA(isA<DeviceDefinitionException>()),
      );
    });

    test('refuses an invalid service UUID', () {
      final map = _validMap()..['services'] = <Object?>['not-a-uuid'];
      expect(
        () => DeviceDefinition.fromMap(map),
        throwsA(isA<DeviceDefinitionException>()),
      );
    });

    test('refuses a characteristic without a role', () {
      final map = _validMap()
        ..['characteristics'] = <Object?, Object?>{'': 'fff1'};
      expect(
        () => DeviceDefinition.fromMap(map),
        throwsA(isA<DeviceDefinitionException>()),
      );
    });

    test('refuses a malformed characteristic role', () {
      final map = _validMap()
        ..['characteristics'] = <Object?, Object?>{'Buttons': 'fff1'};
      expect(
        () => DeviceDefinition.fromMap(map),
        throwsA(isA<DeviceDefinitionException>()),
      );
    });

    test('refuses an empty decoder', () {
      final map = _validMap()..['decoder'] = '  ';
      expect(
        () => DeviceDefinition.fromMap(map),
        throwsA(isA<DeviceDefinitionException>()),
      );
    });

    test('refuses a raw byte out of range', () {
      final map = _validMap()..['raw_to_button'] = <Object?, Object?>{0x100: 1};
      expect(
        () => DeviceDefinition.fromMap(map),
        throwsA(
          isA<DeviceDefinitionException>().having(
            (error) => error.message,
            'message',
            contains('out of range'),
          ),
        ),
      );
    });

    test('refuses a null button id', () {
      final map = _validMap()..['raw_to_button'] = <Object?, Object?>{1: 0};
      expect(
        () => DeviceDefinition.fromMap(map),
        throwsA(isA<DeviceDefinitionException>()),
      );
    });

    test('refuses a negative sleep delay', () {
      final map = _validMap()..['sleep_after_seconds'] = -5;
      expect(
        () => DeviceDefinition.fromMap(map),
        throwsA(isA<DeviceDefinitionException>()),
      );
    });

    test('refuses an unreadable boolean', () {
      final map = _validMap()..['wake_on_press'] = 'maybe';
      expect(
        () => DeviceDefinition.fromMap(map),
        throwsA(isA<DeviceDefinitionException>()),
      );
    });

    test('refuses services that are not a list', () {
      final map = _validMap()..['services'] = 42;
      expect(
        () => DeviceDefinition.fromMap(map),
        throwsA(isA<DeviceDefinitionException>()),
      );
    });
  });

  group('DeviceDefinition', () {
    test('finds a button by raw byte', () {
      final definition = DeviceDefinition.fromMap(_validMap());
      expect(definition.buttonIdFor(0x01), 0x01);
      expect(definition.buttonIdFor(0x7F), isNull);
    });

    test('recognises its services whatever the UUID form', () {
      final definition = DeviceDefinition.fromMap(_validMap());
      expect(definition.servesService('fff0'), isTrue);
      expect(definition.servesService('FFF0'), isTrue);
      expect(
        definition.servesService('{0000FFF0-0000-1000-8000-00805F9B34FB}'),
        isTrue,
      );
      expect(definition.servesService('0000ffe0-0000-1000-8000-00805f9b34fb'),
          isFalse);
    });

    test('compares by value rather than by identity', () {
      final first = DeviceDefinition.fromMap(_validMap());
      final second = DeviceDefinition.fromMap(_validMap());

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
    });

    test('ignores the insertion order of characteristics', () {
      final map = _validMap();
      map['characteristics'] = <Object?, Object?>{
        'buttons': '0000fff1-0000-1000-8000-00805f9b34fb',
        'battery': '0000180f-0000-1000-8000-00805f9b34fb',
      };
      final first = DeviceDefinition.fromMap(map);

      map['characteristics'] = <Object?, Object?>{
        'battery': '0000180f-0000-1000-8000-00805f9b34fb',
        'buttons': '0000fff1-0000-1000-8000-00805f9b34fb',
      };
      final second = DeviceDefinition.fromMap(map);

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
    });

    test('distinguishes two different definitions', () {
      final first = DeviceDefinition.fromMap(_validMap());
      final map = _validMap()..['id'] = 'other-controller';
      final second = DeviceDefinition.fromMap(map);
      expect(first, isNot(equals(second)));
    });

    test('exposes unmodifiable collections', () {
      final definition = DeviceDefinition.fromMap(_validMap());
      expect(() => definition.serviceUuids.add('fff0'), throwsUnsupportedError);
      expect(() => definition.characteristics['x'] = 'fff2',
          throwsUnsupportedError);
      expect(() => definition.rawToButton[0x02] = 0x02, throwsUnsupportedError);
    });

    test('normalises short UUIDs instead of rejecting them', () {
      final definition = DeviceDefinition(
        id: 'short',
        name: 'Short',
        manufacturer: 'Generic',
        serviceUuids: const <String>['FFF0'],
        characteristics: const <String, String>{'buttons': 'fff1'},
        decoderId: 'raw-bytes',
      );
      expect(definition.serviceUuids, <String>['fff0']);
      expect(definition.servesService('0000fff0-0000-1000-8000-00805f9b34fb'),
          isTrue);
    });
  });
}

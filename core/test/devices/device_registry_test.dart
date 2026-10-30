import 'dart:io';

import 'package:openzclick_core/src/devices/openzclick_devices.dart';
import 'package:test/test.dart';

/// Locates the directory of the declarative definitions.
///
/// Tests run from the package root; the fallback lets them run from the
/// repository root.
Directory _devicesDirectory() {
  final direct = Directory('assets/devices');
  if (direct.existsSync()) return direct;
  return Directory('core/assets/devices');
}

void main() {
  group('DeviceRegistry', () {
    test('exposes three generic built-in definitions', () {
      expect(DeviceRegistry.builtin, hasLength(3));
      expect(
        DeviceRegistry.builtin.map((definition) => definition.id),
        <String>[
          'two-button-controller',
          'six-button-shifter',
          'generic-gamepad',
        ],
      );
    });

    test('finds a definition by id', () {
      final definition = DeviceRegistry.byId('six-button-shifter');
      expect(definition, isNotNull);
      expect(definition!.name, 'Six-button shifter');
      expect(definition.rawToButton[0x12], 0x10);
    });

    test('returns null for an unknown id', () {
      expect(DeviceRegistry.byId('unknown'), isNull);
    });

    test('finds a definition by service, long or short form', () {
      expect(
        DeviceRegistry.matchingService('0000fff0-0000-1000-8000-00805f9b34fb')
            ?.id,
        'two-button-controller',
      );
      expect(DeviceRegistry.matchingService('FFF0')?.id,
          'two-button-controller');
      expect(
        DeviceRegistry.matchingService(
          '{0000FFE0-0000-1000-8000-00805F9B34FB}',
        )?.id,
        'six-button-shifter',
      );
    });

    test('returns null for an unknown service', () {
      expect(
          DeviceRegistry.matchingService(
              '0000dead-0000-1000-8000-00805f9b34fb'),
          isNull);
    });

    test('picks the first match among several services', () {
      expect(
        DeviceRegistry.matchingAnyService(<String>[
          '0000dead-0000-1000-8000-00805f9b34fb',
          'ff00',
        ])?.id,
        'generic-gamepad',
      );
      expect(DeviceRegistry.matchingAnyService(<String>['dead']), isNull);
    });

    test('exposes an unmodifiable list', () {
      expect(() => DeviceRegistry.builtin.clear(), throwsUnsupportedError);
    });

    test('contains no duplicated id', () {
      final ids = DeviceRegistry.builtin.map((definition) => definition.id);
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('maps every definition to a single built-in service', () {
      for (final definition in DeviceRegistry.builtin) {
        for (final service in definition.serviceUuids) {
          final match = DeviceRegistry.matchingService(service);
          expect(match?.id, definition.id);
        }
      }
    });

    test('stays consistent with the shipped YAML files', () {
      final directory = _devicesDirectory();
      expect(directory.existsSync(), isTrue,
          reason: 'assets/devices directory not found');

      final files = directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.yaml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      expect(files, hasLength(DeviceRegistry.builtin.length));

      final parsedIds = <String>{};
      for (final file in files) {
        final definition = DeviceYamlLoader.load(file.readAsStringSync());
        parsedIds.add(definition.id);

        final builtin = DeviceRegistry.byId(definition.id);
        expect(builtin, isNotNull,
            reason: '${file.path} describes a device missing from the registry');
        expect(
          definition,
          equals(builtin),
          reason: '${file.path} diverges from the built-in definition',
        );
      }

      expect(
        parsedIds,
        DeviceRegistry.builtin.map((definition) => definition.id).toSet(),
      );
    });
  });
}

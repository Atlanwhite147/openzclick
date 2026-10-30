/// Layer of the controller device definitions.
///
/// This entry point groups:
///
/// * [DeviceDefinition]: validated declarative model of a device;
/// * [DeviceRegistry]: read-only catalogue of the built-in devices;
/// * [MiniYaml] and [DeviceYamlLoader]: loading of definitions from a YAML
///   source, with no external dependency.
///
/// The layer is pure: no I/O, no Bluetooth access. Reading a file remains the
/// caller's responsibility.
library;

export 'device_definition.dart';
export 'device_registry.dart';
export 'yaml_loader.dart';

import 'package:openzclick/net/publisher_port.dart';
import 'package:openzclick_core/openzclick_core.dart';

/// A publisher whose state the test drives, so the guide can be read in each
/// situation a rider meets: stopped, running, and with MyWhoosh attached.
class FakePublisher implements PublisherPort {
  @override
  void Function()? onChanged;

  @override
  bool running = false;

  @override
  bool advertise = true;

  @override
  int port = 47123;

  @override
  int? listeningPort;

  @override
  String? address;

  @override
  int peers = 0;

  @override
  String? error;

  @override
  int consoles = 0;

  @override
  int? get consolePort => null;

  @override
  String get consoleToken => '';

  @override
  String? consoleUrl(String host) => null;

  @override
  Stream<Action> get consoleActions => const Stream<Action>.empty();

  @override
  Future<void> start() async {
    running = true;
    listeningPort = port;
    address = '192.168.1.24';
    onChanged?.call();
  }

  @override
  Future<void> stop() async {
    running = false;
    listeningPort = null;
    onChanged?.call();
  }

  @override
  Future<void> publish(Action action) async {}

  @override
  Future<void> publishConsoleState({
    required String profileId,
    required int gearIndex,
    required int gearCount,
    required String mode,
    required String lastAction,
  }) async {}

  @override
  Future<void> dispose() async {}
}

import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick/net/network_publisher.dart';

void main() {
  test('listens on a stable port and reports its address', () async {
    final NetworkPublisher publisher = NetworkPublisher(
      advertise: false,
      port: 0,
    );
    await publisher.start();
    expect(publisher.running, isTrue);
    expect(publisher.error, isNull);
    expect(publisher.listeningPort, isNotNull);
    expect(publisher.listeningPort, greaterThan(0));
    expect(publisher.address, isNotNull);
    await publisher.stop();
    expect(publisher.running, isFalse);
    expect(publisher.listeningPort, isNull);
  });

  test('without announcement, no multicast socket is opened', () async {
    final NetworkPublisher publisher = NetworkPublisher(
      advertise: false,
      port: 0,
    );
    await publisher.start();
    // A second publisher on the same UDP port would fail if the first one had
    // joined the multicast group; the announcement stays off here.
    expect(publisher.advertise, isFalse);
    await publisher.stop();
  });

  test('publishing while stopped is harmless', () async {
    final NetworkPublisher publisher = NetworkPublisher(
      advertise: false,
      port: 0,
    );
    await publisher.publish(Action.shiftUp);
    expect(publisher.running, isFalse);
  });
}

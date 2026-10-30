import 'package:openzclick_core/src/protocol/controller_crypto.dart';
import 'package:openzclick_core/src/protocol/controller_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ControllerCrypto', () {
    late ControllerKeyPair host;
    late ControllerKeyPair device;
    late ControllerCrypto hostSide;
    late ControllerCrypto deviceSide;

    setUp(() {
      host = ControllerCrypto.generateKeyPair();
      device = ControllerCrypto.generateKeyPair();
      // The host derives from the device public key, the device derives from
      // the host public key. Both must land on the same session keys.
      hostSide = ControllerCrypto.derive(
        devicePublicKeyBytes: device.publicKeyBytes,
        localKeyPair: host,
      );
      // The device keeps the same salt order as the host: device key first.
      deviceSide = ControllerCrypto.derive(
        devicePublicKeyBytes: host.publicKeyBytes,
        localKeyPair: device,
        salt: <int>[...device.publicKeyBytes, ...host.publicKeyBytes],
      );
    });

    test('public keys are 64 bytes', () {
      expect(host.publicKeyBytes.length, 64);
      expect(device.publicKeyBytes.length, 64);
    });

    test('both sides derive the same key and iv', () {
      expect(hostSide.aesKey, deviceSide.aesKey);
      expect(hostSide.iv, deviceSide.iv);
      expect(hostSide.aesKey.length, 32);
      expect(hostSide.iv.length, 4);
    });

    test('a frame encrypted by the device decrypts on the host', () {
      final List<int> message = <int>[ControllerMessageType.click, 0x08, 0x00];
      final List<int> frame = deviceSide.encryptFrame(message, counter: 7);
      expect(hostSide.decryptFrame(frame), message);
    });

    test('the counter changes the ciphertext', () {
      final List<int> message = <int>[ControllerMessageType.click, 0x08, 0x00];
      final List<int> first = deviceSide.encryptFrame(message, counter: 1);
      final List<int> second = deviceSide.encryptFrame(message, counter: 2);
      expect(first.sublist(4), isNot(second.sublist(4)));
    });

    test('a tampered frame is rejected', () {
      final List<int> message = <int>[ControllerMessageType.click, 0x08, 0x00];
      final List<int> frame = deviceSide.encryptFrame(message, counter: 3);
      final List<int> tampered = List<int>.of(frame);
      tampered[tampered.length - 1] ^= 0xFF;
      expect(hostSide.decryptFrame(tampered), isNull);
    });

    test('a truncated frame is rejected', () {
      expect(hostSide.decryptFrame(<int>[0, 0, 0, 1]), isNull);
    });

    test('a device key of the wrong length is rejected', () {
      expect(
        () => ControllerCrypto.derive(
          devicePublicKeyBytes: <int>[1, 2, 3],
          localKeyPair: host,
        ),
        throwsArgumentError,
      );
    });
  });
}

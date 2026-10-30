/// Encrypted transport of the controller family.
///
/// The device and the host agree on a shared secret with ECDH over P-256, then
/// derive an AES-CCM key and IV with HKDF-SHA256. Every frame carries a 4-byte
/// big-endian counter followed by the ciphertext and its 4-byte MAC.
///
/// Only protocol facts are reimplemented here; the primitives come from
/// `pointycastle`, a pure Dart cryptographic library.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Elliptic-curve key pair used during the handshake.
class ControllerKeyPair {
  /// Private key, kept in memory only.
  final ECPrivateKey privateKey;

  /// Public key as 64 bytes: X on 32 bytes, then Y on 32 bytes.
  final List<int> publicKeyBytes;

  const ControllerKeyPair(this.privateKey, this.publicKeyBytes);
}

/// Derives keys and decrypts frames of one controller session.
class ControllerCrypto {
  /// AES key, 32 bytes.
  final List<int> aesKey;

  /// IV prefix, 4 bytes.
  final List<int> iv;

  ControllerCrypto._(this.aesKey, this.iv);

  /// Length of the MAC appended to each frame, in bytes.
  static const int macLength = 4;

  /// P-256, the curve used by the controller.
  static final ECCurve_prime256v1 _curve = ECCurve_prime256v1();

  /// Generates a fresh key pair and returns it with its 64-byte public key.
  ///
  /// The private scalar is drawn from a cryptographically secure source and
  /// reduced into [1, n-1]; the public point is computed as `G * d`.
  static ControllerKeyPair generateKeyPair() {
    final BigInt order = _curve.n;
    final Random random = Random.secure();
    BigInt scalar;
    do {
      final Uint8List bytes = Uint8List(32);
      for (int i = 0; i < bytes.length; i++) {
        bytes[i] = random.nextInt(256);
      }
      scalar = _bytesToBigInt(bytes) % order;
    } while (scalar == BigInt.zero);

    final ECPrivateKey privateKey = ECPrivateKey(scalar, _curve);
    final ECPoint point = _curve.G * scalar as ECPoint;
    return ControllerKeyPair(privateKey, encodePoint(point));
  }

  /// Encodes an EC point as X on 32 bytes then Y on 32 bytes.
  ///
  /// Uses the uncompressed SEC1 encoding and drops the leading `0x04` tag,
  /// which also normalises projective coordinates.
  static List<int> encodePoint(ECPoint point) {
    final List<int> encoded = point.getEncoded(false);
    if (encoded.length != 65 || encoded.first != 0x04) {
      throw StateError('unexpected point encoding (${encoded.length} bytes)');
    }
    return encoded.sublist(1);
  }

  static List<int> _bigIntToBytes(BigInt value, int length) {
    final Uint8List out = Uint8List(length);
    final List<int> bytes = value
        .toRadixString(16)
        .padLeft(length * 2, '0')
        .codeUnits
        .map((int c) => int.parse(String.fromCharCode(c), radix: 16))
        .toList();
    out.setRange(0, length, bytes);
    return out;
  }

  static BigInt _bytesToBigInt(List<int> bytes) {
    final BigInt value = BigInt.parse(
      bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
    return value;
  }

  /// Builds the session from the device public key and the local key pair.
  ///
  /// The salt is the device public key followed by the local one, matching the
  /// documented handshake.
  ///
  /// [salt] overrides the default `device || local` concatenation, which is
  /// what the simulated device uses in the tests.
  factory ControllerCrypto.derive({
    required List<int> devicePublicKeyBytes,
    required ControllerKeyPair localKeyPair,
    List<int>? salt,
  }) {
    if (devicePublicKeyBytes.length != 64) {
      throw ArgumentError.value(
        devicePublicKeyBytes.length,
        'devicePublicKeyBytes',
        'expected 64 bytes',
      );
    }

    final ECPublicKey devicePublicKey = ECPublicKey(
      _curve.curve.createPoint(
        _bytesToBigInt(devicePublicKeyBytes.sublist(0, 32)),
        _bytesToBigInt(devicePublicKeyBytes.sublist(32, 64)),
      ),
      _curve,
    );

    final ECDHBasicAgreement agreement = ECDHBasicAgreement()
      ..init(localKeyPair.privateKey);
    final BigInt shared = agreement.calculateAgreement(devicePublicKey);
    final List<int> sharedBytes = _bigIntToBytes(shared, 32);

    final List<int> effectiveSalt =
        salt ?? <int>[...devicePublicKeyBytes, ...localKeyPair.publicKeyBytes];

    final HKDFKeyDerivator derivator = HKDFKeyDerivator(SHA256Digest())
      ..init(HkdfParameters(
        Uint8List.fromList(sharedBytes),
        36,
        Uint8List.fromList(effectiveSalt),
        Uint8List(0),
      ));
    final Uint8List derived =
        derivator.process(Uint8List.fromList(sharedBytes));

    return ControllerCrypto._(
      derived.sublist(0, 32),
      derived.sublist(32, 36),
    );
  }

  /// Decrypts one frame: 4-byte counter, then ciphertext and MAC.
  ///
  /// Returns the plaintext message, or null when the frame is too short or the
  /// MAC does not verify.
  List<int>? decryptFrame(List<int> frame) {
    if (frame.length <= macLength + 4) return null;
    final List<int> counter = frame.sublist(0, 4);
    final List<int> payload = frame.sublist(4);
    final List<int> nonce = <int>[...iv, ...counter];

    try {
      final CCMBlockCipher cipher = CCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(Uint8List.fromList(aesKey)),
            macLength * 8,
            Uint8List.fromList(nonce),
            Uint8List(0),
          ),
        );
      final Uint8List out = Uint8List(cipher.getOutputSize(payload.length));
      int len = cipher.processBytes(
          Uint8List.fromList(payload), 0, payload.length, out, 0);
      len += cipher.doFinal(out, len);
      return out.sublist(0, len);
    } catch (_) {
      return null;
    }
  }

  /// Encrypts one message with an explicit counter, used by tests and by the
  /// simulated device.
  List<int> encryptFrame(List<int> message, {int counter = 0}) {
    final List<int> counterBytes = <int>[
      (counter >> 24) & 0xFF,
      (counter >> 16) & 0xFF,
      (counter >> 8) & 0xFF,
      counter & 0xFF,
    ];
    final List<int> nonce = <int>[...iv, ...counterBytes];

    final CCMBlockCipher cipher = CCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(Uint8List.fromList(aesKey)),
          macLength * 8,
          Uint8List.fromList(nonce),
          Uint8List(0),
        ),
      );
    final Uint8List out = Uint8List(cipher.getOutputSize(message.length));
    int len = cipher.processBytes(
        Uint8List.fromList(message), 0, message.length, out, 0);
    len += cipher.doFinal(out, len);
    return <int>[...counterBytes, ...out.sublist(0, len)];
  }
}

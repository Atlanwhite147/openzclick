/// Wire protocol of the two-button Bluetooth controller, reconstructed from
/// public interoperability notes.
///
/// Only protocol facts are implemented here (service identifiers, handshake
/// bytes, message types, protobuf field numbers). No third-party code is
/// copied: everything is written from scratch in Dart, and the parser is
/// defensive about firmware changes.
library;

/// Bluetooth identifiers used by the controller family.
abstract final class ControllerUuids {
  /// Primary service.
  static const String service = '00000001-19ca-4651-86e5-fa29dcdd09d1';

  /// Asynchronous channel, notify only: the button stream arrives here.
  static const String asyncChannel = '00000002-19ca-4651-86e5-fa29dcdd09d1';

  /// Synchronous channel from the host to the controller, write only: this is
  /// where the handshake and the commands go. Its name comes from the
  /// controller's point of view, which is why it is not called transmit here.
  static const String syncRx = '00000003-19ca-4651-86e5-fa29dcdd09d1';

  /// Synchronous channel from the controller to the host, indicate: the
  /// acknowledgement of the handshake and the replies arrive here.
  static const String syncTx = '00000004-19ca-4651-86e5-fa29dcdd09d1';

  /// Standard battery service.
  static const String batteryService = '0000180f-0000-1000-8000-00805f9b34fb';
}

/// Message types carried in the first byte of an unencrypted frame.
abstract final class ControllerMessageType {
  /// Nothing happened.
  static const int empty = 21;

  /// Battery report.
  static const int battery = 25;

  /// Two-button notification (protobuf body).
  static const int click = 55;

  /// The controller is about to disconnect.
  static const int disconnect = 0xFE;
}

/// Handshake bytes.
abstract final class ControllerHandshake {
  /// ASCII "RideOn": every exchange starts with these six bytes.
  static const List<int> rideOn = <int>[82, 105, 100, 101, 79, 110];

  /// Client prefix, followed by the 64-byte public key when encryption is used.
  static const List<int> requestStart = <int>[0, 9];

  /// Device prefix, followed by its 64-byte public key.
  static const List<int> responseStart = <int>[1, 3];

  /// Builds the plain handshake, which asks for unencrypted frames.
  static List<int> plainRequest() => List<int>.of(rideOn);

  /// Builds the encrypted handshake around [publicKey] (64 bytes, X then Y).
  static List<int> encryptedRequest(List<int> publicKey) {
    if (publicKey.length != 64) {
      throw ArgumentError.value(
        publicKey.length,
        'publicKey',
        'expected 64 bytes (X on 32, Y on 32)',
      );
    }
    return <int>[...rideOn, ...requestStart, ...publicKey];
  }

  /// Extracts the device public key from a response frame, or null.
  static List<int>? parseDevicePublicKey(List<int> frame) {
    const int prefix = 8; // rideOn + responseStart
    if (frame.length != prefix + 64) return null;
    for (int i = 0; i < rideOn.length; i++) {
      if (frame[i] != rideOn[i]) return null;
    }
    if (frame[6] != responseStart[0] || frame[7] != responseStart[1]) {
      return null;
    }
    return frame.sublist(prefix);
  }
}

/// State of the two buttons of the controller.
class ClickButtons {
  /// Up (plus) button pressed.
  final bool up;

  /// Down (minus) button pressed.
  final bool down;

  /// Creates a button state.
  const ClickButtons({required this.up, required this.down});

  /// Neutral state: nothing pressed.
  static const ClickButtons released = ClickButtons(up: false, down: false);

  @override
  bool operator ==(Object other) =>
      other is ClickButtons && other.up == up && other.down == down;

  @override
  int get hashCode => Object.hash(up, down);

  @override
  String toString() => 'ClickButtons(up: $up, down: $down)';
}

/// Decoded message from the controller.
sealed class ControllerMessage {
  /// Creates a message.
  const ControllerMessage();
}

/// Button notification.
class ClickMessage extends ControllerMessage {
  /// Current button state.
  final ClickButtons buttons;

  /// Creates a button notification.
  const ClickMessage(this.buttons);
}

/// Battery report.
class BatteryMessage extends ControllerMessage {
  /// Battery percentage, 0 to 100.
  final int percent;

  /// Creates a battery report.
  const BatteryMessage(this.percent);
}

/// Empty keep-alive or disconnect notice.
class ControlMessage extends ControllerMessage {
  /// Message type that produced this notice.
  final int type;

  /// Creates a control notice.
  const ControlMessage(this.type);
}

/// Decoder for frames sent by the controller.
abstract final class ControllerCodec {
  /// Decodes one unencrypted frame: `[type] [body...]`.
  ///
  /// Returns null when the frame is too short or carries an unknown type.
  static ControllerMessage? decode(List<int> frame) {
    if (frame.isEmpty) return null;
    final int type = frame[0];
    final List<int> body = frame.sublist(1);
    switch (type) {
      case ControllerMessageType.click:
        final ClickButtons? buttons = parseClickNotification(body);
        return buttons == null ? null : ClickMessage(buttons);
      case ControllerMessageType.battery:
        return body.isEmpty ? null : BatteryMessage(body[0]);
      case ControllerMessageType.empty:
      case ControllerMessageType.disconnect:
        return ControlMessage(type);
      default:
        return null;
    }
  }

  /// Parses the protobuf body of a button notification.
  ///
  /// Field 1 is the up button, field 2 the down button; a varint equal to 0
  /// means pressed, any other value means released. Unknown fields are ignored
  /// so that a firmware update adding fields does not break the bridge.
  static ClickButtons? parseClickNotification(List<int> body) {
    bool up = false;
    bool down = false;
    int index = 0;

    while (index < body.length) {
      final int tag = body[index++];
      final int field = tag >> 3;
      final int wireType = tag & 0x07;
      if (wireType != 0) {
        // Only varints are expected; skip a length-delimited field defensively.
        if (wireType == 2 && index < body.length) {
          final int length = body[index++];
          index += length;
          continue;
        }
        return null;
      }
      final _VarintResult varint = _readVarint(body, index);
      index = varint.nextIndex;
      final bool pressed = varint.value == 0;
      if (field == 1) up = pressed;
      if (field == 2) down = pressed;
    }

    return ClickButtons(up: up, down: down);
  }
}

class _VarintResult {
  final int value;
  final int nextIndex;
  const _VarintResult(this.value, this.nextIndex);
}

_VarintResult _readVarint(List<int> bytes, int start) {
  int result = 0;
  int shift = 0;
  int index = start;
  while (index < bytes.length) {
    final int byte = bytes[index++];
    result |= (byte & 0x7F) << shift;
    if ((byte & 0x80) == 0) break;
    shift += 7;
    if (shift > 63) break;
  }
  return _VarintResult(result, index);
}

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
  /// Primary service, the vendor service the controller actually advertises.
  ///
  /// The `00000001-19ca-4651-86e5-fa29dcdd09d1` identifier is *not* announced
  /// in the advertising packet: it only exists as the parent of the channels
  /// below, inside this vendor service. A scan filtered on it never returns a
  /// controller (measured on a Click v2, firmware 1.1.0, which advertises
  /// `0000fc82-0000-1000-8000-00805f9b34fb`).
  static const String service = '0000fc82-0000-1000-8000-00805f9b34fb';

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

  /// Standard Device Information service: manufacturer, serial, firmware.
  static const String deviceInformationService =
      '0000180a-0000-1000-8000-00805f9b34fb';

  /// What a client has to be granted to do its job, vendor service first.
  ///
  /// A browser is granted only what the page names when it pairs, and a page
  /// that named the vendor service alone could never show a battery level or a
  /// firmware revision: measured on a Click v2 on 2026-11-12, where the same
  /// controller answered `180a` and `180f` under Windows and the browser build
  /// reported that it exposed neither.
  static const List<String> requested = <String>[
    service,
    batteryService,
    deviceInformationService,
  ];
}

/// Message types carried in the first byte of an unencrypted frame.
abstract final class ControllerMessageType {
  /// Nothing happened.
  static const int empty = 21;

  /// Battery report.
  static const int battery = 25;

  /// Button mask, one bit per button, as a Click v2 sends it.
  ///
  /// Measured on hardware (firmware 1.1.0): the frame is `23 08 <varint>`,
  /// field 1 holding a 32-bit mask where every bit is set at rest and the bit
  /// of a pressed button is cleared.
  static const int buttons = 0x23;

  /// Older two-field button notification (protobuf body).
  static const int click = 55;

  /// The controller is about to disconnect.
  static const int disconnect = 0xFE;
}

/// Bit positions of the button mask, measured one button at a time on a
/// Click v2 (firmware 1.1.0), each press isolated and read back from the
/// frame the controller sent.
///
/// A press clears the bit; every other bit stays set. Only [plus] and [b] reach
/// the gear engine: they are the two the rider uses to shift, so mapping the
/// other three would move a gear on a button pressed for another reason.
///
/// The positions of the left pod's arrows are deliberately absent: they have not
/// been measured here, and a guessed offset would decode a steering press as a
/// gear change. The frame is kept whole by [ClickButtonMask], so a reader of the
/// device report can name them the day one is measured.
abstract final class ControllerButtonBits {
  /// Y, the blue button at the top of the pod.
  static const int y = 6;

  /// Z, the orange button on the left.
  static const int z = 7;

  /// A, the green button on the right.
  static const int a = 4;

  /// B, the pink button at the bottom: shift down.
  static const int b = 5;

  /// The large `+` under the cluster: shift up.
  static const int plus = 12;

  /// Names of the measured positions, in English (code identifiers), for the
  /// diagnostics and the device report.
  static const Map<int, String> names = <int, String>{
    a: 'a',
    b: 'b',
    y: 'y',
    z: 'z',
    plus: 'plus',
  };

  /// Measured positions, ascending.
  static const List<int> all = <int>[a, b, y, z, plus];

  /// Returns the name of [bit], or `bit <n>` when the position was never
  /// measured: an unnamed bit is a finding, not a reason to invent a name.
  static String nameOf(int bit) => names[bit] ?? 'bit $bit';
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

  /// Suffix the controller itself answers with when it grants a plain session.
  ///
  /// Measured on a Click v2, firmware 1.1.0: the reply to an encrypted request
  /// is `RideOn 02 03 C8 00 …`, and `zwiftboard` opens its own session by
  /// sending exactly these eight bytes. `pizero_bikecomputer` writes a bare
  /// `RideOn` followed by `FF 04 00` instead. Both are attempts at the same
  /// answer, and this one is the one the controller gave us.
  static const List<int> plainGrant = <int>[0x02, 0x03];

  /// Opening frame of a plain session: the `RideOn` marker, then `02 03`.
  static List<int> plainStart() => <int>[...rideOn, ...plainGrant];

  /// First frame that completes the activation, after the plain handshake.
  ///
  /// A Click v2 streams its buttons only once the exchange has been opened with
  /// the plain `RideOn`; two short writes finish the activation. Lifted from
  /// `zwiftboard` (MIT), which measured them on Windows: `RideOn 02 03`,
  /// `00 08 00`, `00 08 10`, then a `RideOn` write every three seconds as a
  /// keepalive. The previous code sent the plain handshake alone and then
  /// waited, which works until the pod stops answering.
  static const List<int> activationFirst = <int>[0x00, 0x08, 0x00];

  /// Second frame of the activation, see [activationFirst].
  static const List<int> activationSecond = <int>[0x00, 0x08, 0x10];

  /// Frames that open a plain session, in the order they must be written.
  ///
  /// The opening frame is `RideOn 02 03`, not the bare marker: it is the
  /// answer the controller gives when it grants the session, so asking for it
  /// in the same words is the least guesswork available without Zwift.
  static List<List<int>> activationSequence() => <List<int>>[
        plainStart(),
        List<int>.of(activationFirst),
        List<int>.of(activationSecond),
      ];

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

/// State of the buttons of a controller, as a bitfield.
///
/// A `0x23` frame carries a 32-bit mask in which a pressed button has its bit
/// **cleared**; this class stores the opposite, a set bit meaning pressed, and
/// the decoder flips it once. Two booleans were enough while one pod was
/// decoded, and they threw away everything else the frame said: the left pod's
/// arrows, and the fact that a press on one pod is mirrored by the other.
class ClickButtonMask {
  /// Bitfield of the pressed positions, one bit per [ControllerButtonBits].
  final int pressed;

  /// Builds a mask from the two shifting buttons.
  const ClickButtonMask({bool up = false, bool down = false})
      : pressed = (up ? 1 << ControllerButtonBits.plus : 0) |
            (down ? 1 << ControllerButtonBits.b : 0);

  /// Builds a mask from a raw bitfield of pressed positions.
  const ClickButtonMask.bits(this.pressed);

  /// Neutral state: nothing pressed.
  static const ClickButtonMask released = ClickButtonMask();

  /// Whether the position [bit] is pressed.
  bool isPressed(int bit) => (pressed >> bit) & 1 == 1;

  /// Whether the up (`+`) button is pressed.
  bool get up => isPressed(ControllerButtonBits.plus);

  /// Whether the down (`B`) button is pressed.
  bool get down => isPressed(ControllerButtonBits.b);

  /// Whether no button is pressed.
  bool get isEmpty => pressed == 0;

  /// Pressed positions, ascending.
  List<int> get pressedBits => <int>[
        for (int bit = 0; bit < 32; bit++)
          if (isPressed(bit)) bit,
      ];

  /// Positions this mask presses and [previous] did not.
  ///
  /// The rule the two pods need: the left and the right one mirror each other's
  /// frames, so a state repeated by the second pod must not fire a second time.
  ClickButtonMask newlyPressedSince(ClickButtonMask previous) =>
      ClickButtonMask.bits(pressed & ~previous.pressed);

  /// Positions [previous] held and this mask released.
  ClickButtonMask releasedSince(ClickButtonMask previous) =>
      ClickButtonMask.bits(previous.pressed & ~pressed);

  @override
  bool operator ==(Object other) =>
      other is ClickButtonMask && other.pressed == pressed;

  @override
  int get hashCode => pressed.hashCode;

  @override
  String toString() {
    final List<int> bits = pressedBits;
    if (bits.isEmpty) return 'ClickButtonMask(none)';
    return 'ClickButtonMask(${bits.map(ControllerButtonBits.nameOf).join(', ')})';
  }
}

/// Decoded message from the controller.
sealed class ControllerMessage {
  /// Creates a message.
  const ControllerMessage();
}

/// Button notification.
class ClickMessage extends ControllerMessage {
  /// Current button state.
  final ClickButtonMask buttons;

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
      case ControllerMessageType.buttons:
        final ClickButtonMask? buttons = parseButtonMask(body);
        return buttons == null ? null : ClickMessage(buttons);
      case ControllerMessageType.click:
        final ClickButtonMask? buttons = parseClickNotification(body);
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

  /// Parses the button mask of a `0x23` frame.
  ///
  /// Field 1 carries one varint: a 32-bit mask, all ones at rest, with the bit
  /// of a pressed button cleared. Every position is kept, not only the two that
  /// shift: the rest of the frame is what the left pod's arrows will be read
  /// from once they are measured. Returns null when the frame carries no such
  /// field, so a future firmware cannot be mistaken for a press.
  static ClickButtonMask? parseButtonMask(List<int> body) {
    int index = 0;
    while (index < body.length) {
      final int tag = body[index++];
      final int field = tag >> 3;
      final int wireType = tag & 0x07;
      if (wireType != 0) {
        if (wireType == 2 && index < body.length) {
          final int length = body[index++];
          index += length;
          continue;
        }
        return null;
      }
      final _VarintResult varint = _readVarint(body, index);
      index = varint.nextIndex;
      if (field != 1) continue;
      // The wire clears the bit of a pressed button, and only a 32-bit window is
      // described by the specification: a wider varint would otherwise report
      // phantom presses in the higher positions.
      final int cleared = (~varint.value) & 0xFFFFFFFF;
      return ClickButtonMask.bits(cleared);
    }
    return null;
  }

  /// Parses the protobuf body of a button notification.
  ///
  /// Field 1 is the up button, field 2 the down button; a varint equal to 0
  /// means pressed, any other value means released. Unknown fields are ignored
  /// so that a firmware update adding fields does not break the bridge.
  static ClickButtonMask? parseClickNotification(List<int> body) {
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

    return ClickButtonMask(up: up, down: down);
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

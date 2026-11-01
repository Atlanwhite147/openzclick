import 'messages.dart';

/// Stream decoder: extracts complete frames from a byte buffer.
///
/// The OpenBikeControl specification carries no length field and no preamble:
/// a frame is a type byte followed by its body, and the transport is expected
/// to deliver one frame per write. On a byte stream that guarantee is soft, so
/// the decoder takes the longest prefix of the buffer that decodes into a valid
/// message, leaves the remainder buffered for the next read, and drops bytes
/// one at a time only when no prefix is decodable at all.
class ObcCodec {
  ObcCodec._();

  /// Tries to decode the first usable message of [buffer].
  ///
  /// Returns `null` when the buffer holds no decodable prefix. The caller can
  /// then consult [discardCount] to know how many bytes to drop before reading
  /// more of the stream.
  ///
  /// The `consumed` field of the result counts the bytes consumed from the
  /// start of the buffer, leading ignored bytes included: simply remove
  /// `consumed` bytes from the buffer after each successful decode.
  ///
  /// Two messages coalesced into one read are kept apart: the longest decodable
  /// prefix wins and the rest stays buffered. Bytes matching no known type are
  /// ignored, and a `0x01` frame longer than
  /// [ButtonStateMessage.maxFrameLength] bytes is rejected: no prefix of it is
  /// valid, so its bytes are dropped one by one and the scan resumes on the
  /// first usable type byte that follows.
  static ({ObcMessage message, int consumed})? tryDecode(List<int> buffer) {
    final _ScanResult result = _scan(buffer);
    final ObcMessage? message = result.message;
    if (message == null) {
      return null;
    }
    return (message: message, consumed: result.consumed);
  }

  /// Number of leading bytes to drop when [tryDecode] returned `null`.
  ///
  /// `0` when the buffer is empty or ends on a type byte whose frame is still
  /// on its way, and the rest of the buffer otherwise. After a successful
  /// decode this number is always `0`: the `consumed` bytes are what has to be
  /// removed then.
  static int discardCount(List<int> buffer) {
    final _ScanResult result = _scan(buffer);
    if (result.message != null) {
      return 0;
    }
    return result.discard;
  }

  /// Scans [buffer] up to the first valid message or until exhausted.
  static _ScanResult _scan(List<int> buffer) {
    if (buffer.isEmpty) {
      return const _ScanResult();
    }
    int index = 0;
    while (index < buffer.length) {
      final ObcMessageType? type = ObcMessageType.fromCode(buffer[index]);
      if (type == null) {
        // Unknown byte: ignored, resynchronize further on.
        index++;
        continue;
      }
      // A whole buffer that decodes is one complete message: that is the case
      // the specification describes, one write carrying one message, and it
      // keeps a multi-button press in a single frame.
      if (buffer.length - index >= _minFrameLength(type) &&
          (buffer.length - index <= ButtonStateMessage.maxFrameLength ||
              type != ObcMessageType.buttonState)) {
        final ObcMessage? whole = _decodeFrame(type, buffer.sublist(index));
        if (whole != null) {
          return _ScanResult(message: whole, consumed: buffer.length);
        }
      }
      // Otherwise the shortest prefix that decodes on its own and leaves a
      // usable remainder: two messages coalesced into one read stay apart.
      for (int end = index + _minFrameLength(type);
          end <= buffer.length;
          end++) {
        if (type == ObcMessageType.buttonState &&
            end - index > ButtonStateMessage.maxFrameLength) {
          break;
        }
        final ObcMessage? message =
            _decodeFrame(type, buffer.sublist(index, end));
        if (message == null) {
          continue;
        }
        if (_startsUsableFrame(buffer.sublist(end))) {
          return _ScanResult(message: message, consumed: end);
        }
      }
      index++;
    }
    // Nothing decodable. A known type byte whose frame is too short to be
    // complete yet is kept, the rest of the bytes is useless.
    for (int i = 0; i < buffer.length; i++) {
      final ObcMessageType? type = ObcMessageType.fromCode(buffer[i]);
      if (type != null && buffer.length - i < _minFrameLength(type)) {
        return _ScanResult(discard: i);
      }
    }
    return _ScanResult(discard: buffer.length);
  }

  /// True when [rest] is empty, starts a decodable frame, or is still too
  /// short to tell: the remainder left in the buffer after a message must be
  /// worth keeping.
  static bool _startsUsableFrame(List<int> rest) {
    if (rest.isEmpty) {
      return true;
    }
    final ObcMessageType? type = ObcMessageType.fromCode(rest.first);
    if (type == null) {
      return false;
    }
    return _scan(rest).message != null || rest.length < _minFrameLength(type);
  }

  /// Shortest frame a message type can produce, header included.
  static int _minFrameLength(ObcMessageType type) => switch (type) {
        ObcMessageType.buttonState => obcHeaderLength + 2,
        ObcMessageType.deviceStatus => obcHeaderLength + 2,
        ObcMessageType.haptic => obcHeaderLength + 3,
        ObcMessageType.appInfo => obcHeaderLength + 4,
      };

  /// Decodes a candidate frame, `null` if it is invalid.
  static ObcMessage? _decodeFrame(ObcMessageType type, List<int> frame) {
    try {
      switch (type) {
        case ObcMessageType.buttonState:
          return ButtonStateMessage.decode(frame).toMessage();
        case ObcMessageType.deviceStatus:
          return DeviceStatusMessage.decode(frame).toMessage();
        case ObcMessageType.haptic:
          return HapticMessage.decode(frame).toMessage();
        case ObcMessageType.appInfo:
          return AppInfoMessage.decode(frame).toMessage();
      }
    } on FormatException {
      return null;
    }
  }
}

/// Outcome of a buffer scan.
class _ScanResult {
  /// Message found, or `null` if the buffer holds no complete one.
  const _ScanResult({this.message, this.consumed = 0, this.discard = 0});

  final ObcMessage? message;

  /// Bytes consumed from the start of the buffer, leading ignored bytes
  /// included.
  final int consumed;

  /// Leading bytes that can be dropped when no message was found.
  final int discard;
}

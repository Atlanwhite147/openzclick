import 'messages.dart';

/// Stream decoder: extracts complete frames from a byte buffer.
///
/// The protocol carries no preamble: every frame starts directly with its
/// type byte. The decoder therefore scans the buffer for the first valid type
/// byte, which lets it resume the stream after a malformed frame or unknown
/// bytes.
class ObcCodec {
  ObcCodec._();

  /// Tries to decode the first usable message of [buffer].
  ///
  /// Returns `null` when no complete message is available: buffer too short
  /// for the header, body not fully received yet, or buffer holding no valid
  /// frame. In the latter case the caller can consult [discardCount] to know
  /// how many bytes to drop before reading more of the stream.
  ///
  /// The `consumed` field of the result counts the bytes consumed from the
  /// start of the buffer, leading ignored bytes included: simply remove
  /// `consumed` bytes from the buffer after each successful decode.
  ///
  /// Bytes matching no known type are ignored, and a `0x01` frame longer than
  /// [ButtonStateMessage.maxFrameLength] bytes is treated as malformed: the
  /// length it declares is authoritative, the frame is skipped as a whole and
  /// the scan resumes after it. A complete but invalid frame (inconsistent
  /// body length, rejected content) is skipped the same way.
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
  /// `0` when the buffer is empty or a valid but incomplete frame is awaiting
  /// more of the stream, and the length of the buffer when it holds nothing
  /// usable. After a successful decode this number is always `0`: the
  /// `consumed` bytes are what has to be removed then.
  static int discardCount(List<int> buffer) {
    final _ScanResult result = _scan(buffer);
    if (result.message != null) {
      return 0;
    }
    return result.discard;
  }

  /// Scans [buffer] up to the first valid message or until exhausted.
  static _ScanResult _scan(List<int> buffer) {
    int index = 0;
    while (index < buffer.length) {
      final ObcMessageType? type = ObcMessageType.fromCode(buffer[index]);
      if (type == null) {
        // Unknown byte: ignored, resynchronize further on.
        index++;
        continue;
      }
      if (index + 1 >= buffer.length) {
        // Truncated header: the length byte is missing.
        return _ScanResult(discard: index);
      }
      final int bodyLength = buffer[index + 1];
      final int frameLength = obcHeaderLength + bodyLength;
      if (type == ObcMessageType.buttonState &&
          frameLength > ButtonStateMessage.maxFrameLength) {
        // Malformed 0x01 frame: the declared length is authoritative, the
        // whole frame is skipped so that its body is not read as headers.
        index += frameLength;
        continue;
      }
      if (index + frameLength > buffer.length) {
        // Valid but incomplete frame: wait for more of the stream.
        return _ScanResult(discard: index);
      }
      final List<int> frame = buffer.sublist(index, index + frameLength);
      final ObcMessage? message = _decodeFrame(type, frame);
      if (message == null) {
        // Complete but invalid frame: skipped as a whole.
        index += frameLength;
        continue;
      }
      return _ScanResult(message: message, consumed: index + frameLength);
    }
    return _ScanResult(discard: buffer.length);
  }

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

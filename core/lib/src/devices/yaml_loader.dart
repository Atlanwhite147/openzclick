/// Minimal YAML parser, with no external dependency, and loader for device
/// definitions.
///
/// The `core` package is deliberately dependency-free: rather than adding a
/// YAML package, this file implements the subset of YAML needed by definition
/// files while staying tolerant about formatting.
///
/// ## Supported syntax
///
/// * mappings nested by indentation (spaces only);
/// * block sequences (`- value`) and sequences of mappings (`- key: value`);
/// * scalars: text, decimal / hexadecimal (`0x1f`) / binary (`0b1010`)
///   integers, floats, booleans (`true`/`false`/`yes`/`no`), `null` and `~`;
/// * single-quoted strings (`''` escapes an apostrophe) or double-quoted
///   strings (`\n`, `\t`, `\"`, `\\`, `\uXXXX` escapes);
/// * inline collections `[a, b]` and `{key: value}`;
/// * `#` comments at end of line or on their own line, outside quotes;
/// * several documents separated by `---` (and `...` as terminator);
/// * blank lines ignored, CRLF line endings accepted.
///
/// ## Accepted limitations
///
/// * anchors, aliases and tags are not interpreted: `&x`, `*x` and `!!str`
///   remain literal text;
/// * literal blocks (`|`, `>`) are not supported: the value is read as a
///   single-line text and the following lines raise an explicit indentation
///   error;
/// * complex keys (`?`) are not supported and raise an error;
/// * a duplicated key inside one mapping is an error (it would silently mask
///   a value);
/// * a tab character in the indentation is refused, as the standard requires.
///
/// Syntax errors throw [YamlFormatException] with the original line number.
library;

import 'device_definition.dart';

/// Syntax exception of the minimal YAML parser.
class YamlFormatException implements Exception {
  /// Creates the exception with a [message] and, when known, the offending
  /// [line] (1-based numbering).
  const YamlFormatException(this.message, [this.line]);

  /// Human-readable description of the problem.
  final String message;

  /// Original line number, or `null` when the error is not localised.
  final int? line;

  @override
  String toString() => line == null
      ? 'YamlFormatException: $message'
      : 'YamlFormatException (line $line): $message';
}

/// Minimal YAML parser, exposed for tests and diagnostic tools.
abstract final class MiniYaml {
  /// Parses a single document and returns its Dart value.
  ///
  /// Returns `null` for an empty source. When the source holds several
  /// documents, only the first one is returned: use [parseDocuments] to get
  /// them all.
  static Object? parse(String source) {
    final documents = _tokenize(source);
    if (documents.isEmpty) return null;
    return _BlockParser(documents.first).parseDocument();
  }

  /// Parses every document of a source and returns their values.
  static List<Object?> parseDocuments(String source) => _tokenize(source)
      .map((lines) => _BlockParser(lines).parseDocument())
      .toList(growable: false);
}

/// Loader for device definitions read from a YAML source.
///
/// The loader performs no I/O: files are read by the caller (tests,
/// application) and then passed in as a string.
abstract final class DeviceYamlLoader {
  /// Loads a single definition.
  ///
  /// Throws [YamlFormatException] when the syntax is invalid and
  /// [DeviceDefinitionException] when the definition is inconsistent.
  static DeviceDefinition load(String source) {
    final definitions = loadAll(source);
    if (definitions.length != 1) {
      throw YamlFormatException(
        'exactly one device expected, ${definitions.length} found',
      );
    }
    return definitions.single;
  }

  /// Loads one or more definitions.
  ///
  /// Three shapes are accepted:
  ///
  /// * a mapping describing one device;
  /// * a `devices: [ ... ]` mapping holding the list of devices;
  /// * a sequence of mappings, possibly spread over several `---` documents.
  static List<DeviceDefinition> loadAll(String source) {
    final definitions = <DeviceDefinition>[];
    for (final document in MiniYaml.parseDocuments(source)) {
      definitions.addAll(fromDocument(document));
    }
    return List<DeviceDefinition>.unmodifiable(definitions);
  }

  /// Converts an already parsed document into definitions.
  static List<DeviceDefinition> fromDocument(Object? document) {
    if (document == null) return const <DeviceDefinition>[];
    if (document is List<Object?>) {
      return document
          .map((item) => fromDocument(item).single)
          .toList(growable: false);
    }
    if (document is Map<String, Object?>) {
      final devices = document['devices'];
      if (devices != null) {
        if (devices is! List<Object?>) {
          throw const YamlFormatException(
            'key "devices" must be a list',
          );
        }
        return devices
            .map((item) => fromDocument(item).single)
            .toList(growable: false);
      }
      return <DeviceDefinition>[DeviceDefinition.fromMap(document)];
    }
    throw YamlFormatException(
      'unexpected YAML document: ${document.runtimeType}',
    );
  }
}

/// Significant line of the document, with its indentation and its number.
class _Line {
  _Line(this.indent, this.content, this.number);

  int indent;
  String content;
  final int number;

  bool get isItem =>
      content.startsWith('-') && (content.length == 1 || content[1] == ' ');

  @override
  String toString() => '$_Line($indent, "$content")';
}

/// Splits the source into documents, then into significant lines.
List<List<_Line>> _tokenize(String source) {
  final documents = <List<_Line>>[];
  var current = <_Line>[];
  final rawLines = source.split('\n');
  for (var index = 0; index < rawLines.length; index++) {
    final number = index + 1;
    final withoutCr = rawLines[index].replaceAll('\r', '');
    if (withoutCr.trim().isEmpty) continue;
    final stripped = _stripComment(withoutCr);
    if (stripped.trim().isEmpty) continue;
    final withoutTrailing = stripped.replaceFirst(RegExp(r'\s+$'), '');

    var cursor = 0;
    while (cursor < withoutTrailing.length &&
        (withoutTrailing[cursor] == ' ' || withoutTrailing[cursor] == '\t')) {
      if (withoutTrailing[cursor] == '\t') {
        throw YamlFormatException(
          'tab character not allowed in indentation: use spaces',
          number,
        );
      }
      cursor++;
    }
    final content = withoutTrailing.substring(cursor);

    if (content == '---') {
      if (current.isNotEmpty) {
        documents.add(current);
        current = <_Line>[];
      }
      continue;
    }
    if (content == '...') {
      if (current.isNotEmpty) {
        documents.add(current);
        current = <_Line>[];
      }
      continue;
    }
    current.add(_Line(cursor, content, number));
  }
  if (current.isNotEmpty) documents.add(current);
  return documents;
}

/// Removes a `#` comment located outside quotes.
String _stripComment(String line) {
  var inSingle = false;
  var inDouble = false;
  for (var index = 0; index < line.length; index++) {
    final char = line[index];
    if (inDouble) {
      if (char == r'\') {
        index++;
        continue;
      }
      if (char == '"') inDouble = false;
      continue;
    }
    if (inSingle) {
      if (char == "'") {
        if (index + 1 < line.length && line[index + 1] == "'") {
          index++;
          continue;
        }
        inSingle = false;
      }
      continue;
    }
    if (char == '"') {
      inDouble = true;
      continue;
    }
    if (char == "'") {
      inSingle = true;
      continue;
    }
    if (char == '#' && (index == 0 || line[index - 1] == ' ')) {
      return line.substring(0, index);
    }
  }
  return line;
}

/// Recursive parser over a document already split into lines.
class _BlockParser {
  _BlockParser(this._lines);

  final List<_Line> _lines;
  int _index = 0;

  Object? parseDocument() {
    final value = _parseBlock(_lines.first.indent);
    if (_index < _lines.length) {
      final line = _lines[_index];
      throw YamlFormatException(
        'inconsistent indentation: "${line.content}" cannot be attached to '
        'the previous block',
        line.number,
      );
    }
    return value;
  }

  Object? _parseBlock(int indent) {
    if (_lines[_index].isItem) return _parseSequence(indent);
    return _parseMapping(indent);
  }

  Map<String, Object?> _parseMapping(int indent) {
    final result = <String, Object?>{};
    while (_index < _lines.length) {
      final line = _lines[_index];
      if (line.indent < indent) break;
      if (line.indent > indent) {
        throw YamlFormatException('unexpected indentation', line.number);
      }
      if (line.isItem) {
        throw YamlFormatException(
          'unexpected sequence item inside a mapping',
          line.number,
        );
      }
      final split = _splitKey(line);
      _index++;
      if (result.containsKey(split.key)) {
        throw YamlFormatException(
          'duplicate key "${split.key}" in the same mapping',
          line.number,
        );
      }
      if (split.value.isEmpty) {
        if (_index < _lines.length && _lines[_index].indent > indent) {
          result[split.key] = _parseBlock(_lines[_index].indent);
        } else {
          result[split.key] = null;
        }
      } else {
        result[split.key] = _parseInline(split.value, line.number);
      }
    }
    return result;
  }

  List<Object?> _parseSequence(int indent) {
    final items = <Object?>[];
    while (_index < _lines.length) {
      final line = _lines[_index];
      if (line.indent < indent) break;
      if (line.indent > indent) {
        throw YamlFormatException('unexpected indentation', line.number);
      }
      if (!line.isItem) break;

      final rest =
          line.content.length <= 1 ? '' : line.content.substring(1).trim();
      if (rest.isEmpty) {
        _index++;
        if (_index < _lines.length && _lines[_index].indent > indent) {
          items.add(_parseBlock(_lines[_index].indent));
        } else {
          items.add(null);
        }
      } else if (_isMappingStart(rest)) {
        // `- key: value`: the mapping starts on the item line, its following
        // keys are aligned two columns further.
        line.content = rest;
        line.indent = indent + 2;
        items.add(_parseMapping(indent + 2));
      } else {
        _index++;
        items.add(_parseInline(rest, line.number));
      }
    }
    return items;
  }

  bool _isMappingStart(String content) {
    try {
      _splitKey(_Line(0, content, 0));
      return true;
    } on YamlFormatException {
      return false;
    }
  }

  ({String key, String value}) _splitKey(_Line line) {
    final content = line.content;
    var inSingle = false;
    var inDouble = false;
    var depth = 0;
    for (var index = 0; index < content.length; index++) {
      final char = content[index];
      if (inSingle) {
        if (char == "'") inSingle = false;
        continue;
      }
      if (inDouble) {
        if (char == r'\') {
          index++;
          continue;
        }
        if (char == '"') inDouble = false;
        continue;
      }
      if (char == "'") {
        inSingle = true;
        continue;
      }
      if (char == '"') {
        inDouble = true;
        continue;
      }
      if (char == '[' || char == '{') {
        depth++;
        continue;
      }
      if (char == ']' || char == '}') {
        depth--;
        continue;
      }
      if (char == ':' && depth == 0) {
        final isLast = index + 1 == content.length;
        if (isLast || content[index + 1] == ' ') {
          final rawKey = content.substring(0, index).trim();
          final rawValue = content.substring(index + 1).trim();
          if (rawKey.isEmpty) {
            throw YamlFormatException('empty key before ":"', line.number);
          }
          return (
            key: _keyString(rawKey, line.number),
            value: rawValue,
          );
        }
      }
    }
    throw YamlFormatException(
      'key without a ":" separator in "${line.content}"',
      line.number,
    );
  }

  String _keyString(String rawKey, int number) {
    final value = _parseScalar(rawKey, number);
    if (value == null) {
      throw YamlFormatException('empty key', number);
    }
    return '$value';
  }

  Object? _parseInline(String text, int number) {
    final trimmed = text.trim();
    if (trimmed.startsWith('[')) return _parseFlowList(trimmed, number);
    if (trimmed.startsWith('{')) return _parseFlowMap(trimmed, number);
    return _parseScalar(trimmed, number);
  }

  List<Object?> _parseFlowList(String text, int number) {
    if (!text.endsWith(']')) {
      throw YamlFormatException(
        'inline list not terminated by "]"',
        number,
      );
    }
    final inner = text.substring(1, text.length - 1).trim();
    if (inner.isEmpty) return <Object?>[];
    return _splitFlow(inner, number)
        .where((part) => part.trim().isNotEmpty)
        .map((part) => _parseInline(part, number))
        .toList(growable: false);
  }

  Map<String, Object?> _parseFlowMap(String text, int number) {
    if (!text.endsWith('}')) {
      throw YamlFormatException(
        'inline mapping not terminated by "}"',
        number,
      );
    }
    final inner = text.substring(1, text.length - 1).trim();
    final result = <String, Object?>{};
    if (inner.isEmpty) return result;
    for (final part in _splitFlow(inner, number)) {
      if (part.trim().isEmpty) continue;
      final colon = _topLevelColon(part);
      if (colon < 0) {
        throw YamlFormatException(
          'inline mapping entry without ":": "$part"',
          number,
        );
      }
      final key = _keyString(part.substring(0, colon).trim(), number);
      final value = part.substring(colon + 1).trim();
      result[key] = value.isEmpty ? null : _parseInline(value, number);
    }
    return result;
  }

  int _topLevelColon(String text) {
    var inSingle = false;
    var inDouble = false;
    var depth = 0;
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (inSingle) {
        if (char == "'") inSingle = false;
        continue;
      }
      if (inDouble) {
        if (char == r'\') {
          index++;
          continue;
        }
        if (char == '"') inDouble = false;
        continue;
      }
      if (char == "'") {
        inSingle = true;
        continue;
      }
      if (char == '"') {
        inDouble = true;
        continue;
      }
      if (char == '[' || char == '{') {
        depth++;
        continue;
      }
      if (char == ']' || char == '}') {
        depth--;
        continue;
      }
      if (char == ':' && depth == 0) return index;
    }
    return -1;
  }

  List<String> _splitFlow(String text, int number) {
    final parts = <String>[];
    var start = 0;
    var inSingle = false;
    var inDouble = false;
    var depth = 0;
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (inSingle) {
        if (char == "'") inSingle = false;
        continue;
      }
      if (inDouble) {
        if (char == r'\') {
          index++;
          continue;
        }
        if (char == '"') inDouble = false;
        continue;
      }
      if (char == "'") {
        inSingle = true;
        continue;
      }
      if (char == '"') {
        inDouble = true;
        continue;
      }
      if (char == '[' || char == '{') {
        depth++;
        continue;
      }
      if (char == ']' || char == '}') {
        depth--;
        if (depth < 0) {
          throw YamlFormatException('unexpected closing delimiter', number);
        }
        continue;
      }
      if (char == ',' && depth == 0) {
        parts.add(text.substring(start, index));
        start = index + 1;
      }
    }
    if (depth != 0) {
      throw YamlFormatException('unclosed opening delimiter', number);
    }
    parts.add(text.substring(start));
    return parts;
  }

  Object? _parseScalar(String text, int number) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('"')) return _doubleQuoted(trimmed, number);
    if (trimmed.startsWith("'")) return _singleQuoted(trimmed, number);
    final lower = trimmed.toLowerCase();
    if (lower == 'null' || lower == '~') return null;
    if (lower == 'true' || lower == 'yes') return true;
    if (lower == 'false' || lower == 'no') return false;
    final integer = _intLiteral(trimmed);
    if (integer != null) return integer;
    final real = _doubleLiteral(trimmed);
    if (real != null) return real;
    return trimmed;
  }

  String _singleQuoted(String text, int number) {
    if (text.length < 2 || !text.endsWith("'")) {
      throw YamlFormatException(
        'unterminated single quote in "$text"',
        number,
      );
    }
    return text.substring(1, text.length - 1).replaceAll("''", "'");
  }

  String _doubleQuoted(String text, int number) {
    if (text.length < 2 || !text.endsWith('"')) {
      throw YamlFormatException(
        'unterminated double quote in "$text"',
        number,
      );
    }
    final buffer = StringBuffer();
    for (var index = 1; index < text.length - 1; index++) {
      final char = text[index];
      if (char != r'\') {
        buffer.write(char);
        continue;
      }
      index++;
      if (index >= text.length - 1) {
        throw YamlFormatException(
          'incomplete escape in "$text"',
          number,
        );
      }
      final escaped = text[index];
      if (escaped == 'n') {
        buffer.write('\n');
      } else if (escaped == 't') {
        buffer.write('\t');
      } else if (escaped == 'r') {
        buffer.write('\r');
      } else if (escaped == '"') {
        buffer.write('"');
      } else if (escaped == r'\') {
        buffer.write(r'\');
      } else if (escaped == 'u') {
        if (index + 4 >= text.length) {
          throw YamlFormatException(
            'incomplete \\uXXXX sequence in "$text"',
            number,
          );
        }
        final hex = text.substring(index + 1, index + 5);
        final code = int.tryParse(hex, radix: 16);
        if (code == null) {
          throw YamlFormatException(
            'invalid \\uXXXX sequence "$hex"',
            number,
          );
        }
        buffer.writeCharCode(code);
        index += 4;
      } else {
        // Tolerant: an unknown escape keeps the character.
        buffer.write(escaped);
      }
    }
    return buffer.toString();
  }
}

/// Parses an integer literal (decimal, `0x`, `0b`) while tolerating `_`
/// separators.
int? _intLiteral(String text) {
  var body = text.replaceAll('_', '');
  var sign = 1;
  if (body.startsWith('-')) {
    sign = -1;
    body = body.substring(1);
  } else if (body.startsWith('+')) {
    body = body.substring(1);
  }
  if (body.isEmpty) return null;
  int? value;
  if (body.startsWith('0x') || body.startsWith('0X')) {
    value = int.tryParse(body.substring(2), radix: 16);
  } else if (body.startsWith('0b') || body.startsWith('0B')) {
    value = int.tryParse(body.substring(2), radix: 2);
  } else if (RegExp(r'^\d+$').hasMatch(body)) {
    value = int.tryParse(body);
  }
  return value == null ? null : sign * value;
}

/// Parses a simple float (decimal part and/or exponent).
double? _doubleLiteral(String text) {
  final body = text.replaceAll('_', '');
  if (!RegExp(r'^[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?$')
      .hasMatch(body)) {
    return null;
  }
  if (!body.contains('.') && !body.contains('e') && !body.contains('E')) {
    return null;
  }
  return double.tryParse(body);
}

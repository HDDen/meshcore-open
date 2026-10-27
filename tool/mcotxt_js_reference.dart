import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore_open/MCOtxt/mcotxt.dart';

// Эталон для переноса в JS: поток и frame строит существующий Dart-кодек.
// Сборка контейнера здесь независимая: Flutter-тест отдельно сравнивает её
// с настоящим MCOtxtAppCodec. Поэтому скрипт запускается обычным dart.
const mcotxtJsFixturePath = 'test/MCOtxt/fixtures/js_reference_v1.json';

const mcotxtJsCases = <MCOtxtJsReferenceCase>[
  MCOtxtJsReferenceCase('empty', ''),
  MCOtxtJsReferenceCase('one-letter', 'A'),
  MCOtxtJsReferenceCase('russian', 'Привет, как дела?'),
  MCOtxtJsReferenceCase('english', 'Hello there, meeting at seven.'),
  MCOtxtJsReferenceCase('mixed', 'Смешанный text with цифрами 12345!!!'),
  MCOtxtJsReferenceCase('case', 'ВНИМАНИЕ! Attention! ALL CAPS и Тихий текст.'),
  MCOtxtJsReferenceCase('punctuation', '0123456789 .,:;!? () [] {} / \\ @#%&'),
  MCOtxtJsReferenceCase('line-endings', 'Первая\r\nSecond\rТретья\n'),
  MCOtxtJsReferenceCase('combining', 'и\u0306 е\u0308 e\u0301 a\u0308 q\u0301'),
  MCOtxtJsReferenceCase('utf8', '日本語 中文 😀 🛰️ 👩‍🚀'),
  MCOtxtJsReferenceCase('other-languages', 'été déjà français über Straße українська беларуская'),
  MCOtxtJsReferenceCase('en-ru', 'Hello, привет!', languageA: MCOtxtLanguageId.en, languageB: MCOtxtLanguageId.ru),
  MCOtxtJsReferenceCase('ru-only', 'Привет world!', languageB: null),
  MCOtxtJsReferenceCase('fr', 'Bonjour, été français.', languageA: MCOtxtLanguageId.fr, languageB: null),
  MCOtxtJsReferenceCase('de', 'Guten Tag, schöne Straße!', languageA: MCOtxtLanguageId.de, languageB: null),
  MCOtxtJsReferenceCase('it', 'Buongiorno, perché è così?', languageA: MCOtxtLanguageId.it, languageB: null),
  MCOtxtJsReferenceCase('uk', 'Привіт, українська їжа є тут.', languageA: MCOtxtLanguageId.uk, languageB: null),
  MCOtxtJsReferenceCase('be', 'Прывітанне, беларуская мова.', languageA: MCOtxtLanguageId.be, languageB: null),
  MCOtxtJsReferenceCase('auto-pair', 'Hello, bonjour!', automaticPair: true),
  MCOtxtJsReferenceCase('sender', 'Привет!', senderName: 'HDDen'),
  // Dart допускает явное пустое поле. JS должен уметь прочитать и его,
  // хотя новый encode будет опускать senderName при пустой строке.
  MCOtxtJsReferenceCase('empty-sender-field', 'Текст', senderName: ''),
  MCOtxtJsReferenceCase('reply', 'Отвечаю!', senderName: 'Иван', replyAuthorName: 'Alice', replyTimestamp: 1699999999),
  MCOtxtJsReferenceCase('inherited-time', 'Ответ', includeTimestamp: false, replyAuthorName: 'Боб', replyTimestamp: 0),
  MCOtxtJsReferenceCase('uint32', 'Time', timestamp: 0xffffffff, replyAuthorName: '', replyTimestamp: 0xffffffff),
  MCOtxtJsReferenceCase('outer-name', 'Legacy envelope', outerSenderName: 'Relay'),
  MCOtxtJsReferenceCase('long-frame', 'Встречаемся у ретранслятора на вершине. Связь устойчивая, дорога свободна. Встречаемся у ретранслятора на вершине. Связь устойчивая, дорога свободна.'),
];

class MCOtxtJsReferenceCase {
  const MCOtxtJsReferenceCase(
    this.id,
    this.text, {
    this.languageA = MCOtxtLanguageId.ru,
    this.languageB = MCOtxtLanguageId.en,
    this.automaticPair = false,
    this.timestamp = 1700000000,
    this.includeTimestamp = true,
    this.senderName,
    this.replyAuthorName,
    this.replyTimestamp,
    this.outerSenderName = '',
  });

  final String id;
  final String text;
  final MCOtxtLanguageId languageA;
  final MCOtxtLanguageId? languageB;
  final bool automaticPair;
  final int timestamp;
  final bool includeTimestamp;
  final String? senderName;
  final String? replyAuthorName;
  final int? replyTimestamp;
  final String outerSenderName;

  MCOtxtLanguagePair? get pair => automaticPair
      ? null
      : MCOtxtLanguagePair(languageA, languageB);
}

Map<String, Object?> buildMCOtxtJsReference() {
  final savedPair = MCOtxtCodec.defaultLanguagePair;
  try {
    return <String, Object?>{
      'schema': 1,
      'codecVersion': 1,
      'modelGeneration': 0,
      'models': <String, Object?>{
        for (final model in MCOtxtModelRegistry.latest.models)
          model.id.name: model.wireHash,
      },
      'cases': <Object?>[
        for (final sample in mcotxtJsCases) _encodeCase(sample),
      ],
    };
  } finally {
    MCOtxtCodec.defaultLanguagePair = savedPair;
  }
}

Map<String, Object?> _encodeCase(MCOtxtJsReferenceCase sample) {
  MCOtxtCodec.defaultLanguagePair = sample.pair;
  final stream = MCOtxtCodec.encode(sample.text);
  final body = _body(sample);
  final outer = utf8.encode(sample.outerSenderName);
  final envelope = <int>[..._varUint(outer.length), ...outer, 0x31, ...body];
  return <String, Object?>{
    'id': sample.id,
    'input': <String, Object?>{
      'text': sample.text,
      'languageA': sample.automaticPair ? null : sample.languageA.name,
      'languageB': sample.automaticPair ? null : sample.languageB?.name,
      'timestamp': sample.timestamp,
      'includeTimestamp': sample.includeTimestamp,
      'senderName': sample.senderName,
      'replyAuthorName': sample.replyAuthorName,
      'replyTimestamp': sample.replyTimestamp,
      'outerSenderName': sample.outerSenderName,
    },
    'expected': <String, Object?>{
      'text': stream.decodedText,
      'originalBytes': utf8.encode(sample.text).length,
      'streamHex': mcotxtReferenceHex(stream.data),
      'bitLength': stream.bitLength,
      'encodingMode': stream.encodingMode.name,
      'languageA': stream.languageA?.name,
      'languageB': stream.languageB?.name,
      'usedTables': stream.usedTables.map((table) => table.name).toList(),
      'frameHex': mcotxtReferenceHex(MCOtxtFrame.wrap(stream)),
      'textEncodedBytes': MCOtxtFrame.wrap(stream).length,
      'bodyHex': mcotxtReferenceHex(body),
      'bodyBytes': body.length,
      'bodyBase91': _base91(body),
      'appPayloadHex': mcotxtReferenceHex(<int>[0x31, ...body]),
      'mct': 'mct:${_base91(<int>[0x31, ...body])}',
      // Лимит 165 — транспортный; длинный frame остаётся допустимым.
      'envelopeHex': envelope.length <= 165 ? mcotxtReferenceHex(envelope) : null,
      'timestamp': sample.includeTimestamp ? sample.timestamp : 0,
      'senderName': _normalizedOrNull(sample.senderName),
      'replyAuthorName': _normalizedOrNull(sample.replyAuthorName),
      'replyTimestamp': sample.replyTimestamp,
    },
  };
}

String? _normalizedOrNull(String? text) => text == null
    ? null
    : MCOtxtModelRegistry.normalizeInputText(text);

Uint8List _body(MCOtxtJsReferenceCase sample) {
  final out = <int>[
    (sample.replyAuthorName != null ? 1 : 0) |
        (sample.senderName != null ? 2 : 0) |
        (!sample.includeTimestamp ? 4 : 0),
    if (sample.includeTimestamp) ..._uint32(sample.timestamp),
    if (sample.senderName != null) ..._name(sample.senderName!),
    if (sample.replyAuthorName != null) ...<int>[
      ..._name(sample.replyAuthorName!),
      ..._uint32(sample.replyTimestamp!),
    ],
    0,
    ...MCOtxtFrame.encode(sample.text),
  ];
  return Uint8List.fromList(out);
}

List<int> _name(String text) {
  final normalized = MCOtxtModelRegistry.normalizeInputText(text);
  final utf8Bytes = utf8.encode(normalized);
  final plain = <int>[1, ..._varUint(utf8Bytes.length), ...utf8Bytes];
  final coded = <int>[0, ...MCOtxtFrame.encode(normalized)];
  return coded.length <= plain.length ? coded : plain;
}

List<int> _uint32(int value) => <int>[
  value & 255,
  (value >> 8) & 255,
  (value >> 16) & 255,
  (value >> 24) & 255,
];

List<int> _varUint(int value) {
  final bytes = <int>[];
  do {
    var next = value & 127;
    value >>= 7;
    if (value != 0) next |= 128;
    bytes.add(next);
  } while (value != 0);
  return bytes;
}

// Копия транспортного basE91 для независимого pure-Dart экспортера.
// Совпадение с рабочим private-классом проверяется через textFromBody.
String _base91(List<int> bytes) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
      '!#\$%&()*+,./:;<=>?@[]^_`{|}~"';
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in bytes) {
    buffer |= byte << bits;
    bits += 8;
    if (bits > 13) {
      var value = buffer & 8191;
      if (value > 88) {
        buffer >>= 13;
        bits -= 13;
      } else {
        value = buffer & 16383;
        buffer >>= 14;
        bits -= 14;
      }
      out.write(alphabet[value % 91]);
      out.write(alphabet[value ~/ 91]);
    }
  }
  if (bits != 0) {
    out.write(alphabet[buffer % 91]);
    if (bits > 7 || buffer > 90) out.write(alphabet[buffer ~/ 91]);
  }
  return out.toString();
}

String mcotxtReferenceHex(Iterable<int> bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

void main(List<String> args) {
  if (args.length > 1 ||
      (args.isNotEmpty && args.single != '--write' && args.single != '--check')) {
    throw ArgumentError('Usage: mcotxt_js_reference.dart [--write|--check]');
  }
  final literal = '${const JsonEncoder.withIndent('  ').convert(buildMCOtxtJsReference())}\n';
  final file = File(mcotxtJsFixturePath);
  if (args.isEmpty) {
    stdout.write(literal);
  } else if (args.single == '--write') {
    if (file.existsSync()) {
      throw StateError('Golden already exists; use --check. Do not overwrite it.');
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(literal, flush: true);
    stdout.writeln('Saved Dart reference: ${file.path}');
  } else {
    if (!file.existsSync() || file.readAsStringSync() != literal) {
      throw StateError('Dart output differs from the frozen reference (or it is missing).');
    }
    stdout.writeln('Dart bytes match the frozen reference. This is not a JS test.');
  }
}

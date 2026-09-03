import 'dart:convert';
import 'dart:typed_data';

import 'bit_reader.dart';
import 'bit_writer.dart';
import 'mcotxt_errors.dart';
import 'mcotxt_options.dart';
import 'mcotxt_result.dart';
import 'models/mcotxt_model.dart';
import 'models/mcotxt_model_registry.dart';
import 'models/punctuation.dart';

class McotxtCodec {
  static const int version = 1;
  static const int _versionBits = 3;
  static const int _languageBits = 3;
  static const int _normalHeaderBits = _versionBits + _languageBits * 2;
  static const int _extendedLanguagePair8HeaderBits = _normalHeaderBits + 16;
  static const int _rawUtf8HeaderBits = 16;
  static const int _primaryLimit = 31;
  static const int _extensionLimit = 32;
  static const int _extendedControlPrefix = 63;
  static const int _extendedControlPrefixBits = 6;
  static const int _extendedControlSubopcodeBits = 3;
  static const int _switchOtherLanguageSubopcode = 0;
  static const int _resetContextSubopcode = 1;
  static const int _utf8RunSubopcode = 2;
  static const int _utf8RunLengthBits = 5;
  static const int _utf8RunMaxBytes = 32;
  static const int _switchOtherLanguageBits =
      _extendedControlPrefixBits + _extendedControlSubopcodeBits + 8;
  static const int _utf8RunOverheadBits =
      _extendedControlPrefixBits +
      _extendedControlSubopcodeBits +
      _utf8RunLengthBits;

  static McotxtEncodeResult encode(
    String text, {
    McotxtEncodeOptions options = const McotxtEncodeOptions(),
  }) {
    final normalizedText = McotxtModelRegistry.normalizeInputText(text);
    final runes = normalizedText.runes.toList(growable: false);
    final built = _chooseEncoding(runes, options);
    final mcotxtWriter = BitWriter();
    _writeHeader(mcotxtWriter, built.languageA, built.languageB);
    for (final token in built.plan.tokens) {
      _writeToken(mcotxtWriter, token);
    }
    final mcotxtData = mcotxtWriter.toBytes();
    final rawUtf8Candidate = _buildRawUtf8Candidate(normalizedText);
    final useRawUtf8 = _isRawUtf8Better(
      rawDataLength: rawUtf8Candidate.data.length,
      rawBitLength: rawUtf8Candidate.bitLength,
      mcotxtDataLength: mcotxtData.length,
      mcotxtBitLength: mcotxtWriter.bitLength,
    );
    final data = useRawUtf8 ? rawUtf8Candidate.data : mcotxtData;
    final bitLength =
        useRawUtf8 ? rawUtf8Candidate.bitLength : mcotxtWriter.bitLength;
    final decoded = decode(data, bitLength: bitLength);
    return McotxtEncodeResult(
      inputText: text,
      data: data,
      bitLength: bitLength,
      encodingMode:
          useRawUtf8 ? McotxtEncodingMode.rawUtf8 : McotxtEncodingMode.mcotxt,
      bitStream: useRawUtf8 ? rawUtf8Candidate.bitStream : mcotxtWriter.bitString,
      debugTokens: useRawUtf8
          ? <String>[
              'RAW_UTF8(bytes=${rawUtf8Candidate.textBytes.length})',
              'MCOtxt candidate: ${mcotxtWriter.bitLength} bits / ${mcotxtData.length} bytes',
              'RAW_UTF8 candidate: ${rawUtf8Candidate.bitLength} bits / ${rawUtf8Candidate.data.length} bytes',
              'Selected: RAW_UTF8',
            ]
          : <String>[
              ...built.plan.tokens.map(_debugToken),
              'MCOtxt candidate: ${mcotxtWriter.bitLength} bits / ${mcotxtData.length} bytes',
              'RAW_UTF8 candidate: ${rawUtf8Candidate.bitLength} bits / ${rawUtf8Candidate.data.length} bytes',
              'Selected: MCOtxt',
            ],
      decodedText: decoded.text,
      encoderVersion: version,
      usedTables: useRawUtf8 ? const <McotxtTableId>[] : built.plan.usedTables,
      languageA: useRawUtf8 ? null : built.languageA,
      languageB: useRawUtf8 ? null : built.languageB,
      mcotxtCandidateBitLength: mcotxtWriter.bitLength,
      mcotxtCandidateBytes: mcotxtData.length,
      rawUtf8CandidateBitLength: rawUtf8Candidate.bitLength,
      rawUtf8CandidateBytes: rawUtf8Candidate.data.length,
      selectedBitLength: bitLength,
      selectedBytes: data.length,
      stats: options.collectStats
          ? McotxtEncodeStats(
              inputCharacters: runes.length,
              encodedCharacters:
                  useRawUtf8 ? runes.length : built.plan.encodedCharacters,
              skippedCharacters: 0,
              utf8FallbackRuns: useRawUtf8 ? 0 : built.plan.utf8FallbackRuns,
              utf8FallbackCodepoints:
                  useRawUtf8 ? 0 : built.plan.utf8FallbackCodepoints,
              utf8FallbackBytes: useRawUtf8 ? 0 : built.plan.utf8FallbackBytes,
              utf8FallbackBits: useRawUtf8 ? 0 : built.plan.utf8FallbackBits,
              top4Hits: useRawUtf8 ? 0 : built.plan.top4Hits,
              primaryLiterals: useRawUtf8 ? 0 : built.plan.primaryLiterals,
              extensionLiterals:
                  useRawUtf8 ? 0 : built.plan.extensionLiterals,
              punctuationSymbols:
                  useRawUtf8 ? 0 : built.plan.punctuationSymbols,
              shifts: useRawUtf8 ? 0 : built.plan.shifts,
              toggles: useRawUtf8 ? 0 : built.plan.toggles,
              otherLanguageSwitches:
                  useRawUtf8 ? 0 : built.plan.otherLanguageSwitches,
              totalBits: bitLength,
              utf8Bytes: rawUtf8Candidate.textBytes.length,
            )
          : null,
    );
  }

  static McotxtEncodeResult encodeToBitLimit(
    String text, {
    required int maxBits,
    McotxtEncodeOptions options = const McotxtEncodeOptions(),
  }) {
    if (maxBits < _normalHeaderBits) {
      throw const McotxtCodecException(
        McotxtCodecError.invalidInput,
        'maxBits is too small for MCOtxt header',
      );
    }
    final normalizedText = McotxtModelRegistry.normalizeInputText(text);
    final runes = normalizedText.runes.toList(growable: false);
    var low = 0;
    var high = runes.length;
    McotxtEncodeResult best = encode('', options: options);
    while (low <= high) {
      final middle = (low + high) >> 1;
      final candidate = encode(
        String.fromCharCodes(runes.take(middle)),
        options: options,
      );
      if (candidate.bitLength <= maxBits) {
        best = candidate;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return best;
  }

  static McotxtDecodeResult decode(
    Uint8List data, {
    required int bitLength,
  }) {
    final reader = BitReader(data, bitLength: bitLength);
    final receivedVersion = reader.readBits(_versionBits);
    if (receivedVersion != version) {
      throw McotxtCodecException(
        McotxtCodecError.unknownVersion,
        'Unsupported MCOtxt version $receivedVersion',
      );
    }
    final header = _readHeader(reader);
    if (header.mode == _McotxtWireMode.rawUtf8) {
      final text = _readRawUtf8Payload(reader);
      return McotxtDecodeResult(
        text: text,
        decoderVersion: version,
        usedTables: const <McotxtTableId>[],
        languageA: null,
        languageB: null,
      );
    }
    final languageA = header.languageA;
    final languageB = header.languageB;
    var currentLanguage = languageA;
    var contextKind = McotxtPredictionContextKind.start;
    int? previousRune;
    var shift = false;
    final output = <int>[];
    final usedTables = <McotxtTableId>[];

    void addTable(McotxtTableId table) {
      if (!usedTables.contains(table)) usedTables.add(table);
    }

    McotxtLanguageModel currentModel() {
      final model = McotxtModelRegistry.modelFor(currentLanguage);
      if (model == null) {
        throw const McotxtCodecException(
          McotxtCodecError.unknownLanguage,
          'Language token without active MCOtxt language',
        );
      }
      return model;
    }

    void emitLanguageRune(McotxtLanguageModel model, int rune) {
      final outputRune = shift ? model.lowercaseToUppercase[rune] : rune;
      if (shift && outputRune == null) {
        throw const McotxtCodecException(
          McotxtCodecError.invalidShift,
          'MCOtxt SHIFT cannot be applied to this symbol',
        );
      }
      output.add(outputRune ?? rune);
      contextKind = McotxtPredictionContextKind.symbol;
      previousRune = rune;
      shift = false;
      addTable(McotxtTableId.fromLanguage(model.id));
    }

    void assertNoPendingShiftBeforeControl() {
      if (!shift) return;
      throw const McotxtCodecException(
        McotxtCodecError.invalidShift,
        'MCOtxt SHIFT must be followed by a language symbol',
      );
    }

    while (reader.remainingBits > 0) {
      if (reader.readBit() == 0) {
        final rank = reader.readBits(2);
        final model = currentModel();
        final predictions = model.top4ForContext(contextKind, previousRune);
        if (rank >= predictions.length) {
          throw const McotxtCodecException(
            McotxtCodecError.invalidTop4Reference,
            'Invalid MCOtxt TOP4 reference',
          );
        }
        emitLanguageRune(model, predictions[rank]);
        continue;
      }
      if (reader.readBit() == 0) {
        final primaryId = reader.readBits(5);
        final model = currentModel();
        if (primaryId >= _primaryLimit ||
            primaryId >= model.primarySymbols.length) {
          throw const McotxtCodecException(
            McotxtCodecError.invalidPrimaryId,
            'Invalid MCOtxt primary literal',
          );
        }
        emitLanguageRune(model, model.primarySymbols[primaryId]);
        continue;
      }
      if (reader.readBit() == 0) {
        assertNoPendingShiftBeforeControl();
        final punctuationId = reader.readBits(5);
        if (punctuationId >= McotxtPunctuation.symbols.length) {
          throw const McotxtCodecException(
            McotxtCodecError.invalidPunctuationId,
            'Invalid MCOtxt punctuation literal',
          );
        }
        final rune = McotxtPunctuation.symbols[punctuationId];
        output.add(rune);
        final context = _contextAfterPunctuationRune(
          rune,
          contextKind,
          previousRune,
        );
        contextKind = context.kind;
        previousRune = context.previousRune;
        addTable(McotxtTableId.punctuation);
        continue;
      }
      if (reader.readBit() == 0) {
        final extensionId = reader.readBits(5);
        final model = currentModel();
        if (extensionId >= _extensionLimit ||
            extensionId >= model.extensionSymbols.length) {
          throw const McotxtCodecException(
            McotxtCodecError.invalidExtensionId,
            'Invalid MCOtxt extension literal',
          );
        }
        emitLanguageRune(model, model.extensionSymbols[extensionId]);
        continue;
      }
      if (reader.readBit() == 0) {
        if (shift) {
          throw const McotxtCodecException(
            McotxtCodecError.invalidShift,
            'Duplicate MCOtxt SHIFT',
          );
        }
        shift = true;
        continue;
      }
      if (reader.readBit() == 0) {
        assertNoPendingShiftBeforeControl();
        if (languageB == null) {
          throw const McotxtCodecException(
            McotxtCodecError.toggleWithoutLanguageB,
            'MCOtxt TOGGLE_LANGUAGE without Language B',
          );
        }
        if (currentLanguage == languageA) {
          currentLanguage = languageB;
        } else if (currentLanguage == languageB) {
          currentLanguage = languageA;
        } else {
          throw const McotxtCodecException(
            McotxtCodecError.toggleWithoutLanguageB,
            'MCOtxt TOGGLE_LANGUAGE outside A/B context',
          );
        }
        previousRune = null;
        contextKind = McotxtPredictionContextKind.start;
        continue;
      }
      assertNoPendingShiftBeforeControl();
      final subopcode = reader.readBits(3);
      switch (subopcode) {
        case _switchOtherLanguageSubopcode:
          final globalId = reader.readBits(8);
          final language = McotxtModelRegistry.languageForGlobalId(globalId);
          if (globalId == McotxtModelRegistry.globalLanguageNoneId ||
              language == null ||
              McotxtModelRegistry.modelFor(language) == null) {
            throw const McotxtCodecException(
              McotxtCodecError.invalidOtherLanguage,
              'Invalid MCOtxt SWITCH_OTHER_LANGUAGE',
            );
          }
          currentLanguage = language;
          previousRune = null;
          contextKind = McotxtPredictionContextKind.start;
        case _resetContextSubopcode:
          previousRune = null;
          contextKind = McotxtPredictionContextKind.start;
        case _utf8RunSubopcode:
          final length = reader.readBits(_utf8RunLengthBits) + 1;
          final bytes = Uint8List(length);
          for (var i = 0; i < length; i++) {
            bytes[i] = reader.readBits(8);
          }
          final text = _decodeStrictUtf8(bytes);
          output.addAll(text.runes);
          previousRune = null;
          contextKind = McotxtPredictionContextKind.start;
        default:
          throw const McotxtCodecException(
            McotxtCodecError.unknownExtendedControl,
            'Unknown MCOtxt extended control',
          );
      }
    }

    if (shift) {
      throw const McotxtCodecException(
        McotxtCodecError.invalidShift,
        'MCOtxt stream ends after SHIFT',
      );
    }

    return McotxtDecodeResult(
      text: String.fromCharCodes(output),
      decoderVersion: version,
      usedTables: usedTables,
      languageA: languageA,
      languageB: languageB,
    );
  }

  static _BuiltEncoding _chooseEncoding(
    List<int> runes,
    McotxtEncodeOptions options,
  ) {
    if (options.languageA != null || options.languageB != null) {
      if (options.languageA != null && options.languageA == options.languageB) {
        throw const McotxtCodecException(
          McotxtCodecError.invalidInput,
          'MCOtxt Language A and Language B must differ',
        );
      }
      if (options.languageA == null && options.languageB != null) {
        throw const McotxtCodecException(
          McotxtCodecError.invalidInput,
          'MCOtxt Language A is required when Language B is set',
        );
      }
      return _encodeWithLanguagePair(
        runes,
        options.languageA!,
        options.languageB,
      );
    }
    final languageAIds = McotxtModelRegistry.builtinModels
        .map((model) => model.id)
        .toList(growable: false);
    final languageBIds = <McotxtLanguageId?>[
      ...languageAIds,
      null,
    ];
    _BuiltEncoding? best;
    for (final languageA in languageAIds) {
      for (final languageB in languageBIds) {
        if (languageB != null && languageB == languageA) continue;
        final candidate = _encodeWithLanguagePair(runes, languageA, languageB);
        if (best == null || candidate.isBetterThan(best)) best = candidate;
      }
    }
    return best!;
  }

  static _BuiltEncoding _encodeWithLanguagePair(
    List<int> runes,
    McotxtLanguageId languageA,
    McotxtLanguageId? languageB,
  ) {
    final planner = _McotxtPlanner(
      runes: runes,
      languageA: languageA,
      languageB: languageB,
    );
    final plan = planner.plan();
    return _BuiltEncoding(
      languageA: languageA,
      languageB: languageB,
      plan: plan,
    );
  }

  static _RawUtf8Candidate _buildRawUtf8Candidate(String normalizedText) {
    final textBytes = Uint8List.fromList(utf8.encode(normalizedText));
    final writer = BitWriter()
      ..writeBits(version, _versionBits)
      ..writeBits(
        McotxtModelRegistry.extendedLanguageHeaderWireId,
        _languageBits,
      )
      ..writeBits(McotxtModelRegistry.rawUtf8HeaderFormat, _languageBits)
      ..writeBits(0, 7);
    for (final byte in textBytes) {
      writer.writeBits(byte, 8);
    }
    final bitLength = writer.bitLength;
    assert(bitLength == _rawUtf8HeaderBits + textBytes.length * 8);
    return _RawUtf8Candidate(
      data: writer.toBytes(),
      bitLength: bitLength,
      bitStream: writer.bitString,
      textBytes: textBytes,
    );
  }

  static bool _isRawUtf8Better({
    required int rawDataLength,
    required int rawBitLength,
    required int mcotxtDataLength,
    required int mcotxtBitLength,
  }) {
    if (rawDataLength != mcotxtDataLength) {
      return rawDataLength < mcotxtDataLength;
    }
    if (rawBitLength != mcotxtBitLength) {
      return rawBitLength < mcotxtBitLength;
    }
    return false;
  }

  static int _wireIdForLanguage(McotxtLanguageId? language) {
    return language?.wireId ?? McotxtModelRegistry.languageNoneWireId;
  }

  static int _globalIdForLanguage(McotxtLanguageId? language) {
    return language?.globalId ?? McotxtModelRegistry.globalLanguageNoneId;
  }

  static int _headerBitsFor(
    McotxtLanguageId languageA,
    McotxtLanguageId? languageB,
  ) {
    return _usesNormalHeader(languageA, languageB)
        ? _normalHeaderBits
        : _extendedLanguagePair8HeaderBits;
  }

  static bool _usesNormalHeader(
    McotxtLanguageId languageA,
    McotxtLanguageId? languageB,
  ) {
    return McotxtModelRegistry.inlineHeaderIdForGlobalId(languageA.globalId) !=
            null &&
        McotxtModelRegistry.inlineHeaderIdForGlobalId(languageB?.globalId) !=
            null;
  }

  static void _writeHeader(
    BitWriter writer,
    McotxtLanguageId languageA,
    McotxtLanguageId? languageB,
  ) {
    writer.writeBits(version, _versionBits);
    if (_usesNormalHeader(languageA, languageB)) {
      writer
        ..writeBits(languageA.wireId, _languageBits)
        ..writeBits(_wireIdForLanguage(languageB), _languageBits);
      return;
    }
    writer
      ..writeBits(
        McotxtModelRegistry.extendedLanguageHeaderWireId,
        _languageBits,
      )
      ..writeBits(
        McotxtModelRegistry.extendedLanguagePair8Format,
        _languageBits,
      )
      ..writeBits(languageA.globalId, 8)
      ..writeBits(_globalIdForLanguage(languageB), 8);
  }

  static _McotxtHeader _readHeader(BitReader reader) {
    final languageAInline = reader.readBits(_languageBits);
    final languageBInlineOrFormat = reader.readBits(_languageBits);
    if (languageAInline !=
        McotxtModelRegistry.extendedLanguageHeaderWireId) {
      final languageA = McotxtLanguageId.fromWireId(languageAInline);
      if (languageA == null) {
        throw const McotxtCodecException(
          McotxtCodecError.unknownLanguage,
          'Invalid MCOtxt Language A',
        );
      }
      final languageB = McotxtLanguageId.fromWireId(languageBInlineOrFormat);
      if (languageBInlineOrFormat != McotxtModelRegistry.languageNoneWireId &&
          languageB == null) {
        throw const McotxtCodecException(
          McotxtCodecError.unknownLanguage,
          'Invalid MCOtxt Language B',
        );
      }
      return _McotxtHeader(languageA: languageA, languageB: languageB);
    }

    if (languageBInlineOrFormat == McotxtModelRegistry.rawUtf8HeaderFormat) {
      return const _McotxtHeader.rawUtf8();
    }

    if (languageBInlineOrFormat !=
        McotxtModelRegistry.extendedLanguagePair8Format) {
      throw const McotxtCodecException(
        McotxtCodecError.unsupportedExtendedHeader,
        'Unsupported MCOtxt extended language header',
      );
    }

    final languageAGlobal = reader.readBits(8);
    final languageBGlobal = reader.readBits(8);
    if (languageAGlobal == McotxtModelRegistry.globalLanguageNoneId) {
      throw const McotxtCodecException(
        McotxtCodecError.unknownLanguage,
        'MCOtxt extended Language A cannot be NONE',
      );
    }
    final languageA = McotxtModelRegistry.languageForGlobalId(languageAGlobal);
    final languageB = McotxtModelRegistry.languageForGlobalId(languageBGlobal);
    if (McotxtModelRegistry.modelFor(languageA) == null ||
        (languageBGlobal != McotxtModelRegistry.globalLanguageNoneId &&
            McotxtModelRegistry.modelFor(languageB) == null)) {
      throw const McotxtCodecException(
        McotxtCodecError.unknownLanguage,
        'Unknown MCOtxt global language ID',
      );
    }
    return _McotxtHeader(languageA: languageA!, languageB: languageB);
  }

  static String _readRawUtf8Payload(BitReader reader) {
    final padding = reader.readBits(7);
    if (padding != 0) {
      throw const McotxtCodecException(
        McotxtCodecError.invalidRawUtf8,
        'MCOtxt RAW_UTF8 padding bits must be zero',
      );
    }
    if (reader.remainingBits % 8 != 0) {
      throw const McotxtCodecException(
        McotxtCodecError.invalidRawUtf8,
        'MCOtxt RAW_UTF8 payload must be byte-aligned',
      );
    }
    final bytes = Uint8List(reader.remainingBits ~/ 8);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = reader.readBits(8);
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException catch (error) {
      throw McotxtCodecException(
        McotxtCodecError.invalidRawUtf8,
        'Invalid MCOtxt RAW_UTF8 bytes: ${error.message}',
      );
    }
  }

  static String _decodeStrictUtf8(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException catch (error) {
      throw McotxtCodecException(
        McotxtCodecError.invalidUtf8Fallback,
        'Invalid MCOtxt UTF8_RUN bytes: ${error.message}',
      );
    }
  }

  static String _debugToken(_McotxtToken token) {
    switch (token.type) {
      case _McotxtTokenType.top4:
        return 'TOP4(${token.value})';
      case _McotxtTokenType.primary:
        return 'PRIMARY(${token.value})';
      case _McotxtTokenType.punctuation:
        return 'PUNCT(${token.value})';
      case _McotxtTokenType.extension:
        return 'EXTENSION(${token.value})';
      case _McotxtTokenType.shift:
        return 'SHIFT';
      case _McotxtTokenType.toggleLanguage:
        return 'TOGGLE_LANGUAGE';
      case _McotxtTokenType.switchOtherLanguage:
        return 'SWITCH_OTHER_LANGUAGE(${token.value})';
      case _McotxtTokenType.resetContext:
        return 'RESET_CONTEXT';
      case _McotxtTokenType.utf8Run:
        final bytes = token.bytes ?? Uint8List(0);
        final byteText = bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(' ')
            .toUpperCase();
        return 'UTF8_RUN(len=${bytes.length}, text=${jsonEncode(token.text ?? '')}, bytes=$byteText)';
    }
  }

  static void _writeToken(BitWriter writer, _McotxtToken token) {
    switch (token.type) {
      case _McotxtTokenType.top4:
        writer
          ..writeBit(0)
          ..writeBits(token.value, 2);
      case _McotxtTokenType.primary:
        writer
          ..writeBits(2, 2)
          ..writeBits(token.value, 5);
      case _McotxtTokenType.punctuation:
        writer
          ..writeBits(6, 3)
          ..writeBits(token.value, 5);
      case _McotxtTokenType.extension:
        writer
          ..writeBits(14, 4)
          ..writeBits(token.value, 5);
      case _McotxtTokenType.shift:
        writer.writeBits(30, 5);
      case _McotxtTokenType.toggleLanguage:
        writer.writeBits(62, 6);
      case _McotxtTokenType.switchOtherLanguage:
        writer
          ..writeBits(_extendedControlPrefix, _extendedControlPrefixBits)
          ..writeBits(
            _switchOtherLanguageSubopcode,
            _extendedControlSubopcodeBits,
          )
          ..writeBits(token.value, 8);
      case _McotxtTokenType.resetContext:
        writer
          ..writeBits(_extendedControlPrefix, _extendedControlPrefixBits)
          ..writeBits(_resetContextSubopcode, _extendedControlSubopcodeBits);
      case _McotxtTokenType.utf8Run:
        final bytes = token.bytes;
        if (bytes == null || bytes.isEmpty || bytes.length > _utf8RunMaxBytes) {
          throw const McotxtCodecException(
            McotxtCodecError.invalidInput,
            'Invalid MCOtxt UTF8_RUN token',
          );
        }
        writer
          ..writeBits(_extendedControlPrefix, _extendedControlPrefixBits)
          ..writeBits(_utf8RunSubopcode, _extendedControlSubopcodeBits)
          ..writeBits(bytes.length - 1, _utf8RunLengthBits);
        for (final byte in bytes) {
          writer.writeBits(byte, 8);
        }
    }
  }
}

enum _McotxtWireMode {
  mcotxt,
  rawUtf8,
}

class _McotxtHeader {
  final _McotxtWireMode mode;
  final McotxtLanguageId? languageA;
  final McotxtLanguageId? languageB;

  const _McotxtHeader({required this.languageA, required this.languageB})
    : mode = _McotxtWireMode.mcotxt;

  const _McotxtHeader.rawUtf8()
    : mode = _McotxtWireMode.rawUtf8,
      languageA = null,
      languageB = null;
}

class _RawUtf8Candidate {
  final Uint8List data;
  final int bitLength;
  final String bitStream;
  final Uint8List textBytes;

  const _RawUtf8Candidate({
    required this.data,
    required this.bitLength,
    required this.bitStream,
    required this.textBytes,
  });
}

_McotxtPredictionContext _contextAfterPunctuationRune(
  int rune,
  McotxtPredictionContextKind currentKind,
  int? currentPreviousRune,
) {
  if (rune == McotxtPunctuation.space) {
    return currentKind == McotxtPredictionContextKind.symbol
        ? _McotxtPredictionContext.symbol(currentPreviousRune!)
        : const _McotxtPredictionContext.start();
  }
  if (rune == McotxtPunctuation.lineFeed) {
    return const _McotxtPredictionContext.start();
  }
  return const _McotxtPredictionContext.afterPunctuation();
}

class _McotxtPredictionContext {
  final McotxtPredictionContextKind kind;
  final int? previousRune;

  const _McotxtPredictionContext.start()
    : kind = McotxtPredictionContextKind.start,
      previousRune = null;

  const _McotxtPredictionContext.afterPunctuation()
    : kind = McotxtPredictionContextKind.afterPunctuation,
      previousRune = null;

  const _McotxtPredictionContext.symbol(this.previousRune)
    : kind = McotxtPredictionContextKind.symbol;
}

class _McotxtPlanner {
  final List<int> runes;
  final McotxtLanguageId languageA;
  final McotxtLanguageId? languageB;
  final Map<String, _McotxtPlan> _memo = <String, _McotxtPlan>{};

  _McotxtPlanner({
    required this.runes,
    required this.languageA,
    required this.languageB,
  });

  _McotxtPlan plan() => _bestFrom(
    0,
    languageA,
    const _McotxtPredictionContext.start(),
  );

  _McotxtPlan _bestFrom(
    int position,
    McotxtLanguageId? currentLanguage,
    _McotxtPredictionContext context,
  ) {
    if (position >= runes.length) return _McotxtPlan.empty();
    final key =
        '$position|${currentLanguage?.globalId ?? 255}|'
        '${context.kind.index}|${context.previousRune ?? -1}';
    final cached = _memo[key];
    if (cached != null) return cached;

    final rune = runes[position];
    final candidates = <_McotxtPlan>[];
    final punctuationId = McotxtPunctuation.idByRune[rune];
    if (punctuationId != null) {
      candidates.add(
        _bestFrom(
          position + 1,
          currentLanguage,
          _contextAfterPunctuationRune(
            rune,
            context.kind,
            context.previousRune,
          ),
        ).prepend(
          _McotxtToken(_McotxtTokenType.punctuation, punctuationId),
          bits: 8,
          encodedCharacters: 1,
          punctuationSymbols: 1,
          table: McotxtTableId.punctuation,
        ),
      );
    }

    final currentModel = McotxtModelRegistry.modelFor(currentLanguage);
    if (currentModel != null) {
      final option = _symbolTokenForModel(currentModel, rune, context);
      if (option != null) {
        candidates.add(
          _bestFrom(
            position + 1,
            currentLanguage,
            _McotxtPredictionContext.symbol(option.previousRune),
          ).prependSymbolOption(option, currentModel.id),
        );
      }
    }

    final toggledLanguage = _toggledLanguage(currentLanguage);
    final toggledModel = McotxtModelRegistry.modelFor(toggledLanguage);
    if (toggledModel != null) {
      final option = _symbolTokenForModel(
        toggledModel,
        rune,
        const _McotxtPredictionContext.start(),
      );
      if (option != null) {
        candidates.add(
          _bestFrom(
                position + 1,
                toggledLanguage,
                _McotxtPredictionContext.symbol(option.previousRune),
              )
              .prependSymbolOption(option, toggledModel.id)
              .prepend(
                const _McotxtToken(_McotxtTokenType.toggleLanguage, 0),
                bits: 6,
                languageSwitches: 1,
                toggles: 1,
              ),
        );
      }
    }

    for (final model in McotxtModelRegistry.builtinModels) {
      if (model.id == currentLanguage || model.id == toggledLanguage) {
        continue;
      }
      final option = _symbolTokenForModel(
        model,
        rune,
        const _McotxtPredictionContext.start(),
      );
      if (option == null) continue;
      candidates.add(
        _bestFrom(
              position + 1,
              model.id,
              _McotxtPredictionContext.symbol(option.previousRune),
            )
            .prependSymbolOption(option, model.id)
            .prepend(
              _McotxtToken(
                _McotxtTokenType.switchOtherLanguage,
                model.globalId,
              ),
              bits: McotxtCodec._switchOtherLanguageBits,
              languageSwitches: 1,
              otherLanguageSwitches: 1,
            ),
      );
    }

    if (candidates.isEmpty) {
      final run = _utf8RunAt(position);
      candidates.add(
        _bestFrom(
          position + run.codepoints,
          currentLanguage,
          const _McotxtPredictionContext.start(),
        ).prependUtf8Run(run),
      );
    }

    candidates.sort(_McotxtPlan.compare);
    final best = candidates.first;
    _memo[key] = best;
    return best;
  }

  McotxtLanguageId? _toggledLanguage(McotxtLanguageId? currentLanguage) {
    if (languageB == null) return null;
    if (currentLanguage == languageA) return languageB;
    if (currentLanguage == languageB) return languageA;
    return null;
  }

  static bool _isSupportedAnywhere(int rune) {
    if (McotxtPunctuation.idByRune.containsKey(rune)) return true;
    for (final model in McotxtModelRegistry.builtinModels) {
      if (model.normalizeRune(rune) != null) return true;
    }
    return false;
  }

  _Utf8FallbackRun _utf8RunAt(int position) {
    final bytes = <int>[];
    var codepoints = 0;
    for (var i = position; i < runes.length; i++) {
      if (_isSupportedAnywhere(runes[i])) break;
      final runeText = String.fromCharCode(runes[i]);
      final runeBytes = utf8.encode(runeText);
      if (bytes.isNotEmpty &&
          bytes.length + runeBytes.length > McotxtCodec._utf8RunMaxBytes) {
        break;
      }
      bytes.addAll(runeBytes);
      codepoints++;
      if (bytes.length == McotxtCodec._utf8RunMaxBytes) break;
    }
    if (codepoints == 0) {
      final runeText = String.fromCharCode(runes[position]);
      bytes.addAll(utf8.encode(runeText));
      codepoints = 1;
    }
    return _Utf8FallbackRun(
      bytes: Uint8List.fromList(bytes),
      codepoints: codepoints,
      text: String.fromCharCodes(
        runes.getRange(position, position + codepoints),
      ),
    );
  }

  static _SymbolTokenOption? _symbolTokenForModel(
    McotxtLanguageModel model,
    int rune,
    _McotxtPredictionContext context,
  ) {
    final normalized = model.normalizeRune(rune);
    if (normalized == null) return null;
    final shift = normalized != rune;
    if (shift && model.lowercaseToUppercase[normalized] == null) return null;
    final predictions = model.top4ForContext(
      context.kind,
      context.previousRune,
    );
    final rank = predictions.indexOf(normalized);
    if (rank >= 0) {
      return _SymbolTokenOption(
        tokens: <_McotxtToken>[
          if (shift) const _McotxtToken(_McotxtTokenType.shift, 0),
          _McotxtToken(_McotxtTokenType.top4, rank),
        ],
        bits: shift ? 8 : 3,
        previousRune: normalized,
        top4Hits: 1,
        shifts: shift ? 1 : 0,
      );
    }
    final primaryId = model.primaryId(normalized);
    if (primaryId != null) {
      return _SymbolTokenOption(
        tokens: <_McotxtToken>[
          if (shift) const _McotxtToken(_McotxtTokenType.shift, 0),
          _McotxtToken(_McotxtTokenType.primary, primaryId),
        ],
        bits: shift ? 12 : 7,
        previousRune: normalized,
        primaryLiterals: 1,
        shifts: shift ? 1 : 0,
      );
    }
    final extensionId = model.extensionId(normalized);
    if (extensionId != null) {
      return _SymbolTokenOption(
        tokens: <_McotxtToken>[
          if (shift) const _McotxtToken(_McotxtTokenType.shift, 0),
          _McotxtToken(_McotxtTokenType.extension, extensionId),
        ],
        bits: shift ? 14 : 9,
        previousRune: normalized,
        extensionLiterals: 1,
        shifts: shift ? 1 : 0,
      );
    }
    return null;
  }
}

class _BuiltEncoding {
  final McotxtLanguageId languageA;
  final McotxtLanguageId? languageB;
  final _McotxtPlan plan;

  const _BuiltEncoding({
    required this.languageA,
    required this.languageB,
    required this.plan,
  });

  int get headerBits => McotxtCodec._headerBitsFor(languageA, languageB);

  int get bitLength => headerBits + plan.bits;

  bool isBetterThan(_BuiltEncoding other) {
    if (plan.encodedCharacters != other.plan.encodedCharacters) {
      return plan.encodedCharacters > other.plan.encodedCharacters;
    }
    if (bitLength != other.bitLength) return bitLength < other.bitLength;
    if (plan.languageSwitches != other.plan.languageSwitches) {
      return plan.languageSwitches < other.plan.languageSwitches;
    }
    final languageCount = _declaredLanguageCount;
    final otherLanguageCount = other._declaredLanguageCount;
    if (languageCount != otherLanguageCount) {
      return languageCount < otherLanguageCount;
    }
    final a = languageA.globalId;
    final otherA = other.languageA.globalId;
    if (a != otherA) return a < otherA;
    final b = McotxtCodec._globalIdForLanguage(languageB);
    final otherB = McotxtCodec._globalIdForLanguage(other.languageB);
    return b < otherB;
  }

  int get _declaredLanguageCount {
    return 1 + (languageB == null ? 0 : 1);
  }
}

class _McotxtPlan {
  final int bits;
  final int tokensCount;
  final int languageSwitches;
  final int encodedCharacters;
  final int skippedCharacters;
  final int utf8FallbackRuns;
  final int utf8FallbackCodepoints;
  final int utf8FallbackBytes;
  final int utf8FallbackBits;
  final int top4Hits;
  final int primaryLiterals;
  final int extensionLiterals;
  final int punctuationSymbols;
  final int shifts;
  final int toggles;
  final int otherLanguageSwitches;
  final List<_McotxtToken> tokens;
  final List<McotxtTableId> usedTables;

  const _McotxtPlan({
    required this.bits,
    required this.tokensCount,
    required this.languageSwitches,
    required this.encodedCharacters,
    required this.skippedCharacters,
    required this.utf8FallbackRuns,
    required this.utf8FallbackCodepoints,
    required this.utf8FallbackBytes,
    required this.utf8FallbackBits,
    required this.top4Hits,
    required this.primaryLiterals,
    required this.extensionLiterals,
    required this.punctuationSymbols,
    required this.shifts,
    required this.toggles,
    required this.otherLanguageSwitches,
    required this.tokens,
    required this.usedTables,
  });

  factory _McotxtPlan.empty() {
    return const _McotxtPlan(
      bits: 0,
      tokensCount: 0,
      languageSwitches: 0,
      encodedCharacters: 0,
      skippedCharacters: 0,
      utf8FallbackRuns: 0,
      utf8FallbackCodepoints: 0,
      utf8FallbackBytes: 0,
      utf8FallbackBits: 0,
      top4Hits: 0,
      primaryLiterals: 0,
      extensionLiterals: 0,
      punctuationSymbols: 0,
      shifts: 0,
      toggles: 0,
      otherLanguageSwitches: 0,
      tokens: <_McotxtToken>[],
      usedTables: <McotxtTableId>[],
    );
  }

  _McotxtPlan prependSymbolOption(
    _SymbolTokenOption option,
    McotxtLanguageId language,
  ) {
    return prependAll(
      option.tokens,
      bits: option.bits,
      encodedCharacters: 1,
      top4Hits: option.top4Hits,
      primaryLiterals: option.primaryLiterals,
      extensionLiterals: option.extensionLiterals,
      shifts: option.shifts,
      table: McotxtTableId.fromLanguage(language),
    );
  }

  _McotxtPlan prependUtf8Run(_Utf8FallbackRun run) {
    final bits =
        McotxtCodec._utf8RunOverheadBits + run.bytes.length * 8;
    return prepend(
      _McotxtToken.utf8Run(run.bytes, run.text),
      bits: bits,
      encodedCharacters: run.codepoints,
      utf8FallbackRuns: 1,
      utf8FallbackCodepoints: run.codepoints,
      utf8FallbackBytes: run.bytes.length,
      utf8FallbackBits: bits,
    );
  }

  _McotxtPlan prepend(
    _McotxtToken token, {
    required int bits,
    int languageSwitches = 0,
    int encodedCharacters = 0,
    int skippedCharacters = 0,
    int utf8FallbackRuns = 0,
    int utf8FallbackCodepoints = 0,
    int utf8FallbackBytes = 0,
    int utf8FallbackBits = 0,
    int top4Hits = 0,
    int primaryLiterals = 0,
    int extensionLiterals = 0,
    int punctuationSymbols = 0,
    int shifts = 0,
    int toggles = 0,
    int otherLanguageSwitches = 0,
    McotxtTableId? table,
  }) {
    return prependAll(
      <_McotxtToken>[token],
      bits: bits,
      languageSwitches: languageSwitches,
      encodedCharacters: encodedCharacters,
      skippedCharacters: skippedCharacters,
      utf8FallbackRuns: utf8FallbackRuns,
      utf8FallbackCodepoints: utf8FallbackCodepoints,
      utf8FallbackBytes: utf8FallbackBytes,
      utf8FallbackBits: utf8FallbackBits,
      top4Hits: top4Hits,
      primaryLiterals: primaryLiterals,
      extensionLiterals: extensionLiterals,
      punctuationSymbols: punctuationSymbols,
      shifts: shifts,
      toggles: toggles,
      otherLanguageSwitches: otherLanguageSwitches,
      table: table,
    );
  }

  _McotxtPlan prependAll(
    List<_McotxtToken> prefix, {
    required int bits,
    int languageSwitches = 0,
    int encodedCharacters = 0,
    int skippedCharacters = 0,
    int utf8FallbackRuns = 0,
    int utf8FallbackCodepoints = 0,
    int utf8FallbackBytes = 0,
    int utf8FallbackBits = 0,
    int top4Hits = 0,
    int primaryLiterals = 0,
    int extensionLiterals = 0,
    int punctuationSymbols = 0,
    int shifts = 0,
    int toggles = 0,
    int otherLanguageSwitches = 0,
    McotxtTableId? table,
  }) {
    final nextTables = <McotxtTableId>[];
    if (table != null) nextTables.add(table);
    for (final used in usedTables) {
      if (!nextTables.contains(used)) nextTables.add(used);
    }
    return _McotxtPlan(
      bits: this.bits + bits,
      tokensCount: tokensCount + prefix.length,
      languageSwitches: this.languageSwitches + languageSwitches,
      encodedCharacters: this.encodedCharacters + encodedCharacters,
      skippedCharacters: this.skippedCharacters + skippedCharacters,
      utf8FallbackRuns: this.utf8FallbackRuns + utf8FallbackRuns,
      utf8FallbackCodepoints:
          this.utf8FallbackCodepoints + utf8FallbackCodepoints,
      utf8FallbackBytes: this.utf8FallbackBytes + utf8FallbackBytes,
      utf8FallbackBits: this.utf8FallbackBits + utf8FallbackBits,
      top4Hits: this.top4Hits + top4Hits,
      primaryLiterals: this.primaryLiterals + primaryLiterals,
      extensionLiterals: this.extensionLiterals + extensionLiterals,
      punctuationSymbols: this.punctuationSymbols + punctuationSymbols,
      shifts: this.shifts + shifts,
      toggles: this.toggles + toggles,
      otherLanguageSwitches:
          this.otherLanguageSwitches + otherLanguageSwitches,
      tokens: <_McotxtToken>[...prefix, ...tokens],
      usedTables: nextTables,
    );
  }

  static int compare(_McotxtPlan a, _McotxtPlan b) {
    if (a.encodedCharacters != b.encodedCharacters) {
      return b.encodedCharacters.compareTo(a.encodedCharacters);
    }
    if (a.bits != b.bits) return a.bits.compareTo(b.bits);
    if (a.tokensCount != b.tokensCount) {
      return a.tokensCount.compareTo(b.tokensCount);
    }
    if (a.languageSwitches != b.languageSwitches) {
      return a.languageSwitches.compareTo(b.languageSwitches);
    }
    if (a.top4Hits != b.top4Hits) return b.top4Hits.compareTo(a.top4Hits);
    if (a.skippedCharacters != b.skippedCharacters) {
      return a.skippedCharacters.compareTo(b.skippedCharacters);
    }
    return 0;
  }
}

class _SymbolTokenOption {
  final List<_McotxtToken> tokens;
  final int bits;
  final int previousRune;
  final int top4Hits;
  final int primaryLiterals;
  final int extensionLiterals;
  final int shifts;

  const _SymbolTokenOption({
    required this.tokens,
    required this.bits,
    required this.previousRune,
    this.top4Hits = 0,
    this.primaryLiterals = 0,
    this.extensionLiterals = 0,
    this.shifts = 0,
  });
}

enum _McotxtTokenType {
  top4,
  primary,
  punctuation,
  extension,
  shift,
  toggleLanguage,
  switchOtherLanguage,
  resetContext,
  utf8Run,
}

class _McotxtToken {
  final _McotxtTokenType type;
  final int value;
  final Uint8List? bytes;
  final String? text;

  const _McotxtToken(this.type, this.value)
    : bytes = null,
      text = null;

  const _McotxtToken.utf8Run(this.bytes, this.text)
    : type = _McotxtTokenType.utf8Run,
      value = 0;
}

class _Utf8FallbackRun {
  final Uint8List bytes;
  final int codepoints;
  final String text;

  const _Utf8FallbackRun({
    required this.bytes,
    required this.codepoints,
    required this.text,
  });
}

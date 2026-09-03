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

class MCOtxtCodec {
  static const int version = 1;
  static const int _headerFieldBits = 3;
  static const int _versionBits = _headerFieldBits;
  static const int _generationBits = _headerFieldBits;
  static const int _headerFieldEscape = 7;
  static const int _headerFieldEscapeBits = 8;
  static const int _headerFieldMax = _headerFieldEscape + 0xff;
  static const int _languageBits = 3;
  static const int _normalHeaderBits =
      _versionBits + _generationBits + _languageBits * 2;
  static const int _extendedLanguagePair8HeaderBits = _normalHeaderBits + 16;
  static const int _rawUtf8HeaderBits = 16;
  static const int _rawUtf8PaddingBits = 4;
  static const int _primaryLimit = 32;
  static const int _extensionLimit = 32;
  static const int _extendedControlPrefix = 63;
  static const int _extendedControlPrefixBits = 6;
  static const int _extendedControlSubopcodeBits = 3;
  static const int _switchOtherLanguageSubopcode = 0;
  static const int _resetContextSubopcode = 1;
  static const int _utf8RunSubopcode = 2;
  static const int _toggleCaseModeSubopcode = 3;
  static const int _utf8RunLengthBits = 5;
  static const int _utf8RunMaxBytes = 32;
  static const int _switchOtherLanguageBits =
      _extendedControlPrefixBits + _extendedControlSubopcodeBits + 8;
  static const int _utf8RunOverheadBits =
      _extendedControlPrefixBits +
      _extendedControlSubopcodeBits +
      _utf8RunLengthBits;
  static const int _toggleCaseModeBits =
      _extendedControlPrefixBits + _extendedControlSubopcodeBits;

  static MCOtxtEncodeResult encode(
    String text, {
    MCOtxtEncodeOptions options = const MCOtxtEncodeOptions(),
  }) {
    final modelSet = _modelSetForOptions(options);
    final normalizedText = MCOtxtModelRegistry.normalizeInputText(text);
    final runes = normalizedText.runes.toList(growable: false);
    final built = _chooseEncoding(runes, options, modelSet);
    final mcotxtWriter = BitWriter();
    _writeHeader(
      mcotxtWriter,
      modelSet.generation,
      built.languageA,
      built.languageB,
    );
    for (final token in built.plan.tokens) {
      _writeToken(mcotxtWriter, token);
    }
    final mcotxtData = mcotxtWriter.toBytes();
    final rawUtf8Candidate = _buildRawUtf8Candidate(
      normalizedText,
      modelSet.generation,
    );
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
    return MCOtxtEncodeResult(
      inputText: text,
      data: data,
      bitLength: bitLength,
      encodingMode:
          useRawUtf8 ? MCOtxtEncodingMode.rawUtf8 : MCOtxtEncodingMode.mcotxt,
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
      modelGeneration: modelSet.generation,
      usedTables: useRawUtf8 ? const <MCOtxtTableId>[] : built.plan.usedTables,
      languageA: useRawUtf8 ? null : built.languageA,
      languageB: useRawUtf8 ? null : built.languageB,
      mcotxtCandidateBitLength: mcotxtWriter.bitLength,
      mcotxtCandidateBytes: mcotxtData.length,
      rawUtf8CandidateBitLength: rawUtf8Candidate.bitLength,
      rawUtf8CandidateBytes: rawUtf8Candidate.data.length,
      selectedBitLength: bitLength,
      selectedBytes: data.length,
      stats: options.collectStats
          ? MCOtxtEncodeStats(
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

  static MCOtxtEncodeResult encodeToBitLimit(
    String text, {
    required int maxBits,
    MCOtxtEncodeOptions options = const MCOtxtEncodeOptions(),
  }) {
    if (maxBits < _normalHeaderBits) {
      throw const MCOtxtCodecException(
        MCOtxtCodecError.invalidInput,
        'maxBits is too small for MCOtxt header',
      );
    }
    final normalizedText = MCOtxtModelRegistry.normalizeInputText(text);
    final runes = normalizedText.runes.toList(growable: false);
    var low = 0;
    var high = runes.length;
    MCOtxtEncodeResult best = encode('', options: options);
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

  static MCOtxtDecodeResult decode(
    Uint8List data, {
    required int bitLength,
  }) {
    final reader = BitReader(data, bitLength: bitLength);
    final receivedVersion = _readHeaderField(reader);
    if (receivedVersion != version) {
      throw MCOtxtCodecException(
        MCOtxtCodecError.unknownVersion,
        'Unsupported MCOtxt version $receivedVersion',
      );
    }
    final generation = _readHeaderField(reader);
    final header = _readHeader(reader);
    if (header.mode == _MCOtxtWireMode.rawUtf8) {
      // RAW_UTF8 uses no tables, so the generation is reported as read
      // and a stream from a newer generation still decodes.
      final text = _readRawUtf8Payload(reader);
      return MCOtxtDecodeResult(
        text: text,
        decoderVersion: version,
        modelGeneration: generation,
        usedTables: const <MCOtxtTableId>[],
        languageA: null,
        languageB: null,
      );
    }
    final modelSet = _modelSetForGeneration(generation);
    final languageA = header.languageA;
    final languageB = header.languageB;
    if (!modelSet.isAvailable(languageA) ||
        (languageB != null && !modelSet.isAvailable(languageB))) {
      throw const MCOtxtCodecException(
        MCOtxtCodecError.modelUnavailable,
        'MCOtxt payload requires a language model unavailable in this build',
      );
    }
    var currentLanguage = languageA;
    var contextKind = MCOtxtPredictionContextKind.start;
    int? previousRune;
    var shift = false;
    var capsMode = false;
    final output = <int>[];
    final usedTables = <MCOtxtTableId>[];

    void addTable(MCOtxtTableId table) {
      if (!usedTables.contains(table)) usedTables.add(table);
    }

    MCOtxtLanguageModel currentModel() {
      final model = modelSet.modelFor(currentLanguage);
      if (model == null) {
        final knownLanguage = currentLanguage != null &&
            modelSet.declarationFor(currentLanguage) != null;
        throw MCOtxtCodecException(
          knownLanguage
              ? MCOtxtCodecError.modelUnavailable
              : MCOtxtCodecError.unknownLanguage,
          knownLanguage
              ? 'MCOtxt model for ${currentLanguage.name.toUpperCase()} is unavailable'
              : 'Language token without active MCOtxt language',
        );
      }
      return model;
    }

    void emitLanguageRune(MCOtxtLanguageModel model, int rune) {
      final uppercaseRune = model.lowercaseToUppercase[rune];
      if (shift && uppercaseRune == null) {
        throw const MCOtxtCodecException(
          MCOtxtCodecError.invalidShift,
          'MCOtxt SHIFT cannot be applied to this symbol',
        );
      }

      // SHIFT is a one-symbol case inversion. With CAPS_MODE disabled this is
      // the original v1 behavior (SHIFT -> uppercase). With CAPS_MODE enabled
      // the default for caseable symbols is uppercase and SHIFT emits one
      // lowercase symbol. Non-caseable symbols (digits/SPACE/etc.) are
      // unaffected by CAPS_MODE.
      final makeUppercase = uppercaseRune != null && (capsMode != shift);
      output.add(makeUppercase ? uppercaseRune : rune);
      contextKind = MCOtxtPredictionContextKind.symbol;
      previousRune = rune;
      shift = false;
      addTable(MCOtxtTableId.fromLanguage(model.id));
    }

    void assertNoPendingShiftBeforeControl() {
      if (!shift) return;
      throw const MCOtxtCodecException(
        MCOtxtCodecError.invalidShift,
        'MCOtxt SHIFT must be followed by a language symbol',
      );
    }

    while (reader.remainingBits > 0) {
      if (reader.readBit() == 0) {
        final rank = _readTop4Rank(reader);
        final model = currentModel();
        final predictions = model.top4ForContext(contextKind, previousRune);
        if (rank >= predictions.length) {
          throw const MCOtxtCodecException(
            MCOtxtCodecError.invalidTop4Reference,
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
          throw const MCOtxtCodecException(
            MCOtxtCodecError.invalidPrimaryId,
            'Invalid MCOtxt primary literal',
          );
        }
        emitLanguageRune(model, model.primarySymbols[primaryId]);
        continue;
      }
      if (reader.readBit() == 0) {
        assertNoPendingShiftBeforeControl();
        final punctuationId = reader.readBits(5);
        if (punctuationId >= MCOtxtPunctuation.symbols.length) {
          throw const MCOtxtCodecException(
            MCOtxtCodecError.invalidPunctuationId,
            'Invalid MCOtxt punctuation literal',
          );
        }
        final rune = MCOtxtPunctuation.symbols[punctuationId];
        output.add(rune);
        final context = _contextAfterPunctuationRune(
          rune,
          contextKind,
          previousRune,
        );
        contextKind = context.kind;
        previousRune = context.previousRune;
        addTable(MCOtxtTableId.punctuation);
        continue;
      }
      if (reader.readBit() == 0) {
        final extensionId = reader.readBits(5);
        final model = currentModel();
        if (extensionId >= _extensionLimit ||
            extensionId >= model.extensionSymbols.length) {
          throw const MCOtxtCodecException(
            MCOtxtCodecError.invalidExtensionId,
            'Invalid MCOtxt extension literal',
          );
        }
        emitLanguageRune(model, model.extensionSymbols[extensionId]);
        continue;
      }
      if (reader.readBit() == 0) {
        if (shift) {
          throw const MCOtxtCodecException(
            MCOtxtCodecError.invalidShift,
            'Duplicate MCOtxt SHIFT',
          );
        }
        shift = true;
        continue;
      }
      if (reader.readBit() == 0) {
        assertNoPendingShiftBeforeControl();
        if (languageB == null) {
          throw const MCOtxtCodecException(
            MCOtxtCodecError.toggleWithoutLanguageB,
            'MCOtxt TOGGLE_LANGUAGE without Language B',
          );
        }
        if (currentLanguage == languageA) {
          currentLanguage = languageB;
        } else if (currentLanguage == languageB) {
          currentLanguage = languageA;
        } else {
          throw const MCOtxtCodecException(
            MCOtxtCodecError.toggleWithoutLanguageB,
            'MCOtxt TOGGLE_LANGUAGE outside A/B context',
          );
        }
        previousRune = null;
        contextKind = MCOtxtPredictionContextKind.start;
        continue;
      }
      assertNoPendingShiftBeforeControl();
      final subopcode = reader.readBits(3);
      switch (subopcode) {
        case _switchOtherLanguageSubopcode:
          final globalId = reader.readBits(8);
          final language = MCOtxtModelRegistry.languageForGlobalId(globalId);
          if (globalId == MCOtxtModelRegistry.globalLanguageNoneId ||
              language == null) {
            throw const MCOtxtCodecException(
              MCOtxtCodecError.invalidOtherLanguage,
              'Invalid MCOtxt SWITCH_OTHER_LANGUAGE',
            );
          }
          if (!modelSet.isAvailable(language)) {
            throw const MCOtxtCodecException(
              MCOtxtCodecError.modelUnavailable,
              'MCOtxt SWITCH_OTHER_LANGUAGE references an unavailable model',
            );
          }
          currentLanguage = language;
          previousRune = null;
          contextKind = MCOtxtPredictionContextKind.start;
        case _resetContextSubopcode:
          previousRune = null;
          contextKind = MCOtxtPredictionContextKind.start;
        case _utf8RunSubopcode:
          final length = reader.readBits(_utf8RunLengthBits) + 1;
          final bytes = Uint8List(length);
          for (var i = 0; i < length; i++) {
            bytes[i] = reader.readBits(8);
          }
          final text = _decodeStrictUtf8(bytes);
          output.addAll(text.runes);
          previousRune = null;
          contextKind = MCOtxtPredictionContextKind.start;
        case _toggleCaseModeSubopcode:
          // Persistent case mode does not alter the prediction context: the
          // statistical model is defined over normalized lowercase symbols.
          capsMode = !capsMode;
        default:
          throw const MCOtxtCodecException(
            MCOtxtCodecError.unknownExtendedControl,
            'Unknown MCOtxt extended control',
          );
      }
    }

    if (shift) {
      throw const MCOtxtCodecException(
        MCOtxtCodecError.invalidShift,
        'MCOtxt stream ends after SHIFT',
      );
    }

    return MCOtxtDecodeResult(
      text: String.fromCharCodes(output),
      decoderVersion: version,
      modelGeneration: generation,
      usedTables: usedTables,
      languageA: languageA,
      languageB: languageB,
    );
  }

  static _BuiltEncoding _chooseEncoding(
    List<int> runes,
    MCOtxtEncodeOptions options,
    MCOtxtModelSet modelSet,
  ) {
    if (options.languageA != null || options.languageB != null) {
      if (options.languageA != null && options.languageA == options.languageB) {
        throw const MCOtxtCodecException(
          MCOtxtCodecError.invalidInput,
          'MCOtxt Language A and Language B must differ',
        );
      }
      if (options.languageA == null && options.languageB != null) {
        throw const MCOtxtCodecException(
          MCOtxtCodecError.invalidInput,
          'MCOtxt Language A is required when Language B is set',
        );
      }
      return _encodeWithLanguagePair(
        runes,
        options.languageA!,
        options.languageB,
        modelSet,
      );
    }
    final languageAIds = modelSet.models
        .map((model) => model.id)
        .toList(growable: false);
    final languageBIds = <MCOtxtLanguageId?>[
      ...languageAIds,
      null,
    ];
    _BuiltEncoding? best;
    for (final languageA in languageAIds) {
      for (final languageB in languageBIds) {
        if (languageB != null && languageB == languageA) continue;
        final candidate = _encodeWithLanguagePair(
          runes,
          languageA,
          languageB,
          modelSet,
        );
        if (best == null || candidate.isBetterThan(best)) best = candidate;
      }
    }
    return best!;
  }

  static _BuiltEncoding _encodeWithLanguagePair(
    List<int> runes,
    MCOtxtLanguageId languageA,
    MCOtxtLanguageId? languageB,
    MCOtxtModelSet modelSet,
  ) {
    if (!modelSet.isAvailable(languageA) ||
        (languageB != null && !modelSet.isAvailable(languageB))) {
      throw const MCOtxtCodecException(
        MCOtxtCodecError.modelUnavailable,
        'Requested MCOtxt language model is unavailable',
      );
    }
    final planner = _MCOtxtPlanner(
      runes: runes,
      languageA: languageA,
      languageB: languageB,
      modelSet: modelSet,
    );
    final plan = planner.plan();
    return _BuiltEncoding(
      languageA: languageA,
      languageB: languageB,
      plan: plan,
    );
  }

  static _RawUtf8Candidate _buildRawUtf8Candidate(
    String normalizedText,
    int generation,
  ) {
    final textBytes = Uint8List.fromList(utf8.encode(normalizedText));
    final writer = BitWriter();
    _writeHeaderField(writer, version);
    _writeHeaderField(writer, generation);
    writer
      ..writeBits(
        MCOtxtModelRegistry.extendedLanguageHeaderWireId,
        _languageBits,
      )
      ..writeBits(MCOtxtModelRegistry.rawUtf8HeaderFormat, _languageBits)
      ..writeBits(0, _rawUtf8PaddingBits);
    // Every escape adds eight bits, so the header stays whole bytes and the
    // UTF-8 payload byte-aligned.
    final headerBits = writer.bitLength;
    assert(headerBits >= _rawUtf8HeaderBits && headerBits % 8 == 0);
    for (final byte in textBytes) {
      writer.writeBits(byte, 8);
    }
    final bitLength = writer.bitLength;
    assert(bitLength == headerBits + textBytes.length * 8);
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

  static int _wireIdForLanguage(MCOtxtLanguageId? language) {
    return language?.wireId ?? MCOtxtModelRegistry.languageNoneWireId;
  }

  static int _globalIdForLanguage(MCOtxtLanguageId? language) {
    return language?.globalId ?? MCOtxtModelRegistry.globalLanguageNoneId;
  }

  static int _headerBitsFor(
    MCOtxtLanguageId languageA,
    MCOtxtLanguageId? languageB,
  ) {
    return _usesNormalHeader(languageA, languageB)
        ? _normalHeaderBits
        : _extendedLanguagePair8HeaderBits;
  }

  static bool _usesNormalHeader(
    MCOtxtLanguageId languageA,
    MCOtxtLanguageId? languageB,
  ) {
    return MCOtxtModelRegistry.inlineHeaderIdForGlobalId(languageA.globalId) !=
            null &&
        MCOtxtModelRegistry.inlineHeaderIdForGlobalId(languageB?.globalId) !=
            null;
  }

  static void _writeHeader(
    BitWriter writer,
    int generation,
    MCOtxtLanguageId languageA,
    MCOtxtLanguageId? languageB,
  ) {
    _writeHeaderField(writer, version);
    _writeHeaderField(writer, generation);
    if (_usesNormalHeader(languageA, languageB)) {
      writer
        ..writeBits(languageA.wireId, _languageBits)
        ..writeBits(_wireIdForLanguage(languageB), _languageBits);
      return;
    }
    writer
      ..writeBits(
        MCOtxtModelRegistry.extendedLanguageHeaderWireId,
        _languageBits,
      )
      ..writeBits(
        MCOtxtModelRegistry.extendedLanguagePair8Format,
        _languageBits,
      )
      ..writeBits(languageA.globalId, 8)
      ..writeBits(_globalIdForLanguage(languageB), 8);
  }

  /// Parses the language part of the header. Whether the selected
  /// generation has tables for the languages is checked by [decode].
  static _MCOtxtHeader _readHeader(BitReader reader) {
    final languageAInline = reader.readBits(_languageBits);
    final languageBInlineOrFormat = reader.readBits(_languageBits);
    if (languageAInline !=
        MCOtxtModelRegistry.extendedLanguageHeaderWireId) {
      final languageA = MCOtxtLanguageId.fromWireId(languageAInline);
      if (languageA == null) {
        throw const MCOtxtCodecException(
          MCOtxtCodecError.unknownLanguage,
          'Invalid MCOtxt Language A',
        );
      }
      final languageB = MCOtxtLanguageId.fromWireId(languageBInlineOrFormat);
      if (languageBInlineOrFormat != MCOtxtModelRegistry.languageNoneWireId &&
          languageB == null) {
        throw const MCOtxtCodecException(
          MCOtxtCodecError.unknownLanguage,
          'Invalid MCOtxt Language B',
        );
      }
      return _MCOtxtHeader(languageA: languageA, languageB: languageB);
    }

    if (languageBInlineOrFormat == MCOtxtModelRegistry.rawUtf8HeaderFormat) {
      return const _MCOtxtHeader.rawUtf8();
    }

    if (languageBInlineOrFormat !=
        MCOtxtModelRegistry.extendedLanguagePair8Format) {
      throw const MCOtxtCodecException(
        MCOtxtCodecError.unsupportedExtendedHeader,
        'Unsupported MCOtxt extended language header',
      );
    }

    final languageAGlobal = reader.readBits(8);
    final languageBGlobal = reader.readBits(8);
    if (languageAGlobal == MCOtxtModelRegistry.globalLanguageNoneId) {
      throw const MCOtxtCodecException(
        MCOtxtCodecError.unknownLanguage,
        'MCOtxt extended Language A cannot be NONE',
      );
    }
    final languageA = MCOtxtModelRegistry.languageForGlobalId(languageAGlobal);
    final languageB = MCOtxtModelRegistry.languageForGlobalId(languageBGlobal);
    if (languageA == null ||
        (languageBGlobal != MCOtxtModelRegistry.globalLanguageNoneId &&
            languageB == null)) {
      throw const MCOtxtCodecException(
        MCOtxtCodecError.unknownLanguage,
        'Unknown MCOtxt global language ID',
      );
    }
    return _MCOtxtHeader(languageA: languageA, languageB: languageB);
  }

  /// Version and generation share one shape: a value below 7 is written in
  /// three bits, 7 and above as the escape `7` followed by eight bits of
  /// `value - 7`. Every value therefore has exactly one encoding.
  static void _writeHeaderField(BitWriter writer, int value) {
    if (value < 0 || value > _headerFieldMax) {
      throw MCOtxtCodecException(
        MCOtxtCodecError.invalidInput,
        'MCOtxt header field $value is out of range',
      );
    }
    if (value < _headerFieldEscape) {
      writer.writeBits(value, _headerFieldBits);
      return;
    }
    writer
      ..writeBits(_headerFieldEscape, _headerFieldBits)
      ..writeBits(value - _headerFieldEscape, _headerFieldEscapeBits);
  }

  static int _readHeaderField(BitReader reader) {
    final inline = reader.readBits(_headerFieldBits);
    if (inline != _headerFieldEscape) return inline;
    return _headerFieldEscape + reader.readBits(_headerFieldEscapeBits);
  }

  static MCOtxtModelSet _modelSetForOptions(MCOtxtEncodeOptions options) {
    final generation = options.modelGeneration;
    if (generation == null) return MCOtxtModelRegistry.latest;
    return _modelSetForGeneration(generation);
  }

  static MCOtxtModelSet _modelSetForGeneration(int generation) {
    final modelSet = MCOtxtModelRegistry.setFor(generation);
    if (modelSet == null) {
      throw MCOtxtCodecException(
        MCOtxtCodecError.unsupportedModelGeneration,
        'MCOtxt model generation $generation is not available in this build',
      );
    }
    return modelSet;
  }

  static String _readRawUtf8Payload(BitReader reader) {
    final padding = reader.readBits(_rawUtf8PaddingBits);
    if (padding != 0) {
      throw const MCOtxtCodecException(
        MCOtxtCodecError.invalidRawUtf8,
        'MCOtxt RAW_UTF8 padding bits must be zero',
      );
    }
    if (reader.remainingBits % 8 != 0) {
      throw const MCOtxtCodecException(
        MCOtxtCodecError.invalidRawUtf8,
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
      throw MCOtxtCodecException(
        MCOtxtCodecError.invalidRawUtf8,
        'Invalid MCOtxt RAW_UTF8 bytes: ${error.message}',
      );
    }
  }

  static String _decodeStrictUtf8(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException catch (error) {
      throw MCOtxtCodecException(
        MCOtxtCodecError.invalidUtf8Fallback,
        'Invalid MCOtxt UTF8_RUN bytes: ${error.message}',
      );
    }
  }

  static String _debugToken(_MCOtxtToken token) {
    switch (token.type) {
      case _MCOtxtTokenType.top4:
        return 'TOP4(${token.value})';
      case _MCOtxtTokenType.primary:
        return 'PRIMARY(${token.value})';
      case _MCOtxtTokenType.punctuation:
        return 'PUNCT(${token.value})';
      case _MCOtxtTokenType.extension:
        return 'EXTENSION(${token.value})';
      case _MCOtxtTokenType.shift:
        return 'SHIFT';
      case _MCOtxtTokenType.toggleLanguage:
        return 'TOGGLE_LANGUAGE';
      case _MCOtxtTokenType.switchOtherLanguage:
        return 'SWITCH_OTHER_LANGUAGE(${token.value})';
      case _MCOtxtTokenType.resetContext:
        return 'RESET_CONTEXT';
      case _MCOtxtTokenType.toggleCaseMode:
        return 'TOGGLE_CASE_MODE';
      case _MCOtxtTokenType.utf8Run:
        final bytes = token.bytes ?? Uint8List(0);
        final byteText = bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(' ')
            .toUpperCase();
        return 'UTF8_RUN(len=${bytes.length}, text=${jsonEncode(token.text ?? '')}, bytes=$byteText)';
    }
  }

  static int _top4BitsForRank(int rank) {
    if (rank == 0) return 2;
    if (rank == 1) return 3;
    if (rank == 2 || rank == 3) return 4;
    throw const MCOtxtCodecException(
      MCOtxtCodecError.invalidTop4Reference,
      'Invalid MCOtxt TOP4 rank',
    );
  }

  // Variable-length TOP4 code. The leading zero still identifies TOP4, so the
  // rest of the v1 token tree (all starting with 1) remains unchanged:
  //   rank 0 -> 00    (2 bits total)
  //   rank 1 -> 010   (3 bits total)
  //   rank 2 -> 0110  (4 bits total)
  //   rank 3 -> 0111  (4 bits total)
  static int _readTop4Rank(BitReader reader) {
    if (reader.readBit() == 0) return 0;
    if (reader.readBit() == 0) return 1;
    return reader.readBit() == 0 ? 2 : 3;
  }

  static void _writeTop4Rank(BitWriter writer, int rank) {
    switch (rank) {
      case 0:
        writer.writeBits(0, 2); // 00
      case 1:
        writer.writeBits(2, 3); // 010
      case 2:
        writer.writeBits(6, 4); // 0110
      case 3:
        writer.writeBits(7, 4); // 0111
      default:
        throw const MCOtxtCodecException(
          MCOtxtCodecError.invalidTop4Reference,
          'Invalid MCOtxt TOP4 rank',
        );
    }
  }

  static void _writeToken(BitWriter writer, _MCOtxtToken token) {
    switch (token.type) {
      case _MCOtxtTokenType.top4:
        _writeTop4Rank(writer, token.value);
      case _MCOtxtTokenType.primary:
        writer
          ..writeBits(2, 2)
          ..writeBits(token.value, 5);
      case _MCOtxtTokenType.punctuation:
        writer
          ..writeBits(6, 3)
          ..writeBits(token.value, 5);
      case _MCOtxtTokenType.extension:
        writer
          ..writeBits(14, 4)
          ..writeBits(token.value, 5);
      case _MCOtxtTokenType.shift:
        writer.writeBits(30, 5);
      case _MCOtxtTokenType.toggleLanguage:
        writer.writeBits(62, 6);
      case _MCOtxtTokenType.switchOtherLanguage:
        writer
          ..writeBits(_extendedControlPrefix, _extendedControlPrefixBits)
          ..writeBits(
            _switchOtherLanguageSubopcode,
            _extendedControlSubopcodeBits,
          )
          ..writeBits(token.value, 8);
      case _MCOtxtTokenType.resetContext:
        writer
          ..writeBits(_extendedControlPrefix, _extendedControlPrefixBits)
          ..writeBits(_resetContextSubopcode, _extendedControlSubopcodeBits);
      case _MCOtxtTokenType.toggleCaseMode:
        writer
          ..writeBits(_extendedControlPrefix, _extendedControlPrefixBits)
          ..writeBits(_toggleCaseModeSubopcode, _extendedControlSubopcodeBits);
      case _MCOtxtTokenType.utf8Run:
        final bytes = token.bytes;
        if (bytes == null || bytes.isEmpty || bytes.length > _utf8RunMaxBytes) {
          throw const MCOtxtCodecException(
            MCOtxtCodecError.invalidInput,
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

enum _MCOtxtWireMode {
  mcotxt,
  rawUtf8,
}

class _MCOtxtHeader {
  final _MCOtxtWireMode mode;
  final MCOtxtLanguageId? languageA;
  final MCOtxtLanguageId? languageB;

  const _MCOtxtHeader({required this.languageA, required this.languageB})
    : mode = _MCOtxtWireMode.mcotxt;

  const _MCOtxtHeader.rawUtf8()
    : mode = _MCOtxtWireMode.rawUtf8,
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

_MCOtxtPredictionContext _contextAfterPunctuationRune(
  int rune,
  MCOtxtPredictionContextKind currentKind,
  int? currentPreviousRune,
) {
  if (rune == MCOtxtPunctuation.space) {
    return currentKind == MCOtxtPredictionContextKind.symbol
        ? _MCOtxtPredictionContext.symbol(currentPreviousRune!)
        : const _MCOtxtPredictionContext.start();
  }
  if (rune == MCOtxtPunctuation.lineFeed) {
    return const _MCOtxtPredictionContext.start();
  }
  return const _MCOtxtPredictionContext.afterPunctuation();
}

class _MCOtxtPredictionContext {
  final MCOtxtPredictionContextKind kind;
  final int? previousRune;

  const _MCOtxtPredictionContext.start()
    : kind = MCOtxtPredictionContextKind.start,
      previousRune = null;

  const _MCOtxtPredictionContext.afterPunctuation()
    : kind = MCOtxtPredictionContextKind.afterPunctuation,
      previousRune = null;

  const _MCOtxtPredictionContext.symbol(this.previousRune)
    : kind = MCOtxtPredictionContextKind.symbol;
}

class _MCOtxtPlanner {
  final List<int> runes;
  final MCOtxtLanguageId languageA;
  final MCOtxtLanguageId? languageB;
  final MCOtxtModelSet modelSet;
  final Map<String, _MCOtxtPlan> _memo = <String, _MCOtxtPlan>{};
  late final _CasePlan _casePlan = _CasePlan.build(runes, modelSet);

  _MCOtxtPlanner({
    required this.runes,
    required this.languageA,
    required this.languageB,
    required this.modelSet,
  });

  _MCOtxtPlan plan() => _bestFrom(
    0,
    languageA,
    const _MCOtxtPredictionContext.start(),
  );

  _MCOtxtPlan _bestFrom(
    int position,
    MCOtxtLanguageId? currentLanguage,
    _MCOtxtPredictionContext context,
  ) {
    if (position >= runes.length) return _MCOtxtPlan.empty();
    final key =
        '$position|${currentLanguage?.globalId ?? 255}|'
        '${context.kind.index}|${context.previousRune ?? -1}';
    final cached = _memo[key];
    if (cached != null) return cached;

    final rune = runes[position];
    final candidates = <_MCOtxtPlan>[];

    // Punctuation remains a normal candidate. SPACE is also a language symbol,
    // so the planner is free to choose the cheaper representation.
    final punctuationId = MCOtxtPunctuation.idByRune[rune];
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
          _MCOtxtToken(_MCOtxtTokenType.punctuation, punctuationId),
          bits: 8,
          encodedCharacters: 1,
          punctuationSymbols: 1,
          table: MCOtxtTableId.punctuation,
        ),
      );
    }

    final currentModel = modelSet.modelFor(currentLanguage);
    if (currentModel != null) {
      _addSymbolCandidate(
        candidates: candidates,
        position: position,
        targetLanguage: currentLanguage!,
        model: currentModel,
        symbolContext: context,
      );
    }

    final toggledLanguage = _toggledLanguage(currentLanguage);
    final toggledModel = modelSet.modelFor(toggledLanguage);
    if (toggledModel != null) {
      _addSymbolCandidate(
        candidates: candidates,
        position: position,
        targetLanguage: toggledLanguage!,
        model: toggledModel,
        symbolContext: const _MCOtxtPredictionContext.start(),
        languagePrefix: const _MCOtxtToken(
          _MCOtxtTokenType.toggleLanguage,
          0,
        ),
        languagePrefixBits: 6,
        languageSwitches: 1,
        toggles: 1,
      );
    }

    for (final model in modelSet.models) {
      if (model.id == currentLanguage || model.id == toggledLanguage) {
        continue;
      }
      _addSymbolCandidate(
        candidates: candidates,
        position: position,
        targetLanguage: model.id,
        model: model,
        symbolContext: const _MCOtxtPredictionContext.start(),
        languagePrefix: _MCOtxtToken(
          _MCOtxtTokenType.switchOtherLanguage,
          model.globalId,
        ),
        languagePrefixBits: MCOtxtCodec._switchOtherLanguageBits,
        languageSwitches: 1,
        otherLanguageSwitches: 1,
      );
    }

    // UTF8_RUN is deliberately only the universal fallback again. It is not a
    // competing representation for text that can be represented by a language
    // model/punctuation. This keeps the encoder search small enough for MCU use.
    if (candidates.isEmpty) {
      final run = _utf8RunAt(position);
      candidates.add(
        _bestFrom(
          position + run.codepoints,
          currentLanguage,
          const _MCOtxtPredictionContext.start(),
        ).prependUtf8Run(run),
      );
    }

    candidates.sort(_MCOtxtPlan.compare);
    final best = candidates.first;
    _memo[key] = best;
    return best;
  }

  void _addSymbolCandidate({
    required List<_MCOtxtPlan> candidates,
    required int position,
    required MCOtxtLanguageId targetLanguage,
    required MCOtxtLanguageModel model,
    required _MCOtxtPredictionContext symbolContext,
    _MCOtxtToken? languagePrefix,
    int languagePrefixBits = 0,
    int languageSwitches = 0,
    int toggles = 0,
    int otherLanguageSwitches = 0,
  }) {
    final option = _symbolTokenForModel(
      model,
      runes[position],
      symbolContext,
      shift: _casePlan.shiftAt(position),
    );
    if (option == null) return;

    var plan = _bestFrom(
      position + 1,
      targetLanguage,
      _MCOtxtPredictionContext.symbol(option.previousRune),
    ).prependSymbolOption(option, model.id);

    // Case mode is optimized separately with a tiny 2-state DP over the case
    // pattern only. It does not multiply the much larger language/context DP.
    if (_casePlan.toggleBefore(position)) {
      plan = plan.prepend(
        const _MCOtxtToken(_MCOtxtTokenType.toggleCaseMode, 0),
        bits: MCOtxtCodec._toggleCaseModeBits,
      );
    }
    if (languagePrefix != null) {
      plan = plan.prepend(
        languagePrefix,
        bits: languagePrefixBits,
        languageSwitches: languageSwitches,
        toggles: toggles,
        otherLanguageSwitches: otherLanguageSwitches,
      );
    }
    candidates.add(plan);
  }

  MCOtxtLanguageId? _toggledLanguage(MCOtxtLanguageId? currentLanguage) {
    if (languageB == null) return null;
    if (currentLanguage == languageA) return languageB;
    if (currentLanguage == languageB) return languageA;
    return null;
  }

  bool _isSupportedAnywhere(int rune) {
    if (MCOtxtPunctuation.idByRune.containsKey(rune)) return true;
    for (final model in modelSet.models) {
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
          bytes.length + runeBytes.length > MCOtxtCodec._utf8RunMaxBytes) {
        break;
      }
      bytes.addAll(runeBytes);
      codepoints++;
      if (bytes.length == MCOtxtCodec._utf8RunMaxBytes) break;
    }
    if (codepoints == 0) {
      // Defensive fallback. In normal planner flow this can only happen for a
      // rune with no legal candidate, but never split a UTF-8 codepoint.
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
    MCOtxtLanguageModel model,
    int rune,
    _MCOtxtPredictionContext context, {
    required bool shift,
  }) {
    final normalized = model.normalizeRune(rune);
    if (normalized == null) return null;

    if (shift && model.lowercaseToUppercase[normalized] == null) return null;

    final predictions = model.top4ForContext(
      context.kind,
      context.previousRune,
    );
    final rank = predictions.indexOf(normalized);
    if (rank >= 0) {
      final top4Bits = MCOtxtCodec._top4BitsForRank(rank);
      return _SymbolTokenOption(
        tokens: <_MCOtxtToken>[
          if (shift) const _MCOtxtToken(_MCOtxtTokenType.shift, 0),
          _MCOtxtToken(_MCOtxtTokenType.top4, rank),
        ],
        bits: top4Bits + (shift ? 5 : 0),
        previousRune: normalized,
        top4Hits: 1,
        shifts: shift ? 1 : 0,
      );
    }
    final primaryId = model.primaryId(normalized);
    if (primaryId != null) {
      return _SymbolTokenOption(
        tokens: <_MCOtxtToken>[
          if (shift) const _MCOtxtToken(_MCOtxtTokenType.shift, 0),
          _MCOtxtToken(_MCOtxtTokenType.primary, primaryId),
        ],
        bits: (shift ? 5 : 0) + 7,
        previousRune: normalized,
        primaryLiterals: 1,
        shifts: shift ? 1 : 0,
      );
    }
    final extensionId = model.extensionId(normalized);
    if (extensionId != null) {
      return _SymbolTokenOption(
        tokens: <_MCOtxtToken>[
          if (shift) const _MCOtxtToken(_MCOtxtTokenType.shift, 0),
          _MCOtxtToken(_MCOtxtTokenType.extension, extensionId),
        ],
        bits: (shift ? 5 : 0) + 9,
        previousRune: normalized,
        extensionLiterals: 1,
        shifts: shift ? 1 : 0,
      );
    }
    return null;
  }
}

// CAPS/SHIFT decisions are independent of language prediction/context costs:
// case controls never alter the normalized symbol used by TOP4. Solve that
// tiny subproblem once with two states instead of adding capsMode to every
// language/context DP state.
class _CasePlan {
  final Set<int> _toggleBeforePositions;
  final Set<int> _shiftPositions;

  const _CasePlan(this._toggleBeforePositions, this._shiftPositions);

  bool toggleBefore(int position) => _toggleBeforePositions.contains(position);
  bool shiftAt(int position) => _shiftPositions.contains(position);

  factory _CasePlan.build(List<int> runes, MCOtxtModelSet modelSet) {
    final positions = <int>[];
    final wantsUppercase = <bool>[];
    for (var position = 0; position < runes.length; position++) {
      final requirement = _caseRequirement(runes[position], modelSet);
      if (requirement == null) continue;
      positions.add(position);
      wantsUppercase.add(requirement);
    }
    if (positions.isEmpty) {
      return const _CasePlan(<int>{}, <int>{});
    }

    // Cost after each caseable symbol for resulting CAPS state 0/1.
    var previous = <_CaseCost?>[
      const _CaseCost(bits: 0, toggles: 0, shifts: 0),
      null,
    ];
    final backtrack = <List<_CaseDecision?>>[];

    for (var i = 0; i < positions.length; i++) {
      final desiredUpper = wantsUppercase[i];
      final next = <_CaseCost?>[null, null];
      final decisions = <_CaseDecision?>[null, null];
      for (var previousState = 0; previousState <= 1; previousState++) {
        final previousCost = previous[previousState];
        if (previousCost == null) continue;
        for (var nextState = 0; nextState <= 1; nextState++) {
          final toggled = previousState != nextState;
          final shifted = desiredUpper != (nextState == 1);
          final candidate = _CaseCost(
            bits: previousCost.bits +
                (toggled ? MCOtxtCodec._toggleCaseModeBits : 0) +
                (shifted ? 5 : 0),
            toggles: previousCost.toggles + (toggled ? 1 : 0),
            shifts: previousCost.shifts + (shifted ? 1 : 0),
          );
          if (_betterCaseCost(candidate, next[nextState])) {
            next[nextState] = candidate;
            decisions[nextState] = _CaseDecision(
              previousState: previousState,
              toggled: toggled,
              shifted: shifted,
            );
          }
        }
      }
      previous = next;
      backtrack.add(decisions);
    }

    var state = _betterCaseCost(previous[0]!, previous[1]) ? 0 : 1;
    final toggles = <int>{};
    final shifts = <int>{};
    for (var i = positions.length - 1; i >= 0; i--) {
      final decision = backtrack[i][state]!;
      if (decision.toggled) toggles.add(positions[i]);
      if (decision.shifted) shifts.add(positions[i]);
      state = decision.previousState;
    }
    return _CasePlan(toggles, shifts);
  }

  static bool? _caseRequirement(int rune, MCOtxtModelSet modelSet) {
    for (final model in modelSet.models) {
      final normalized = model.normalizeRune(rune);
      if (normalized == null) continue;
      if (model.lowercaseToUppercase[normalized] == null) continue;
      return normalized != rune;
    }
    return null;
  }
}

class _CaseCost {
  final int bits;
  final int toggles;
  final int shifts;

  const _CaseCost({
    required this.bits,
    required this.toggles,
    required this.shifts,
  });
}

class _CaseDecision {
  final int previousState;
  final bool toggled;
  final bool shifted;

  const _CaseDecision({
    required this.previousState,
    required this.toggled,
    required this.shifted,
  });
}

bool _betterCaseCost(_CaseCost candidate, _CaseCost? current) {
  if (current == null) return true;
  if (candidate.bits != current.bits) return candidate.bits < current.bits;
  if (candidate.toggles != current.toggles) {
    return candidate.toggles < current.toggles;
  }
  return candidate.shifts < current.shifts;
}

class _BuiltEncoding {
  final MCOtxtLanguageId languageA;
  final MCOtxtLanguageId? languageB;
  final _MCOtxtPlan plan;

  const _BuiltEncoding({
    required this.languageA,
    required this.languageB,
    required this.plan,
  });

  int get headerBits => MCOtxtCodec._headerBitsFor(languageA, languageB);

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
    final b = MCOtxtCodec._globalIdForLanguage(languageB);
    final otherB = MCOtxtCodec._globalIdForLanguage(other.languageB);
    return b < otherB;
  }

  int get _declaredLanguageCount {
    return 1 + (languageB == null ? 0 : 1);
  }
}

class _MCOtxtPlan {
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
  final List<_MCOtxtToken> tokens;
  final List<MCOtxtTableId> usedTables;

  const _MCOtxtPlan({
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

  factory _MCOtxtPlan.empty() {
    return const _MCOtxtPlan(
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
      tokens: <_MCOtxtToken>[],
      usedTables: <MCOtxtTableId>[],
    );
  }

  _MCOtxtPlan prependSymbolOption(
    _SymbolTokenOption option,
    MCOtxtLanguageId language,
  ) {
    return prependAll(
      option.tokens,
      bits: option.bits,
      encodedCharacters: 1,
      top4Hits: option.top4Hits,
      primaryLiterals: option.primaryLiterals,
      extensionLiterals: option.extensionLiterals,
      shifts: option.shifts,
      table: MCOtxtTableId.fromLanguage(language),
    );
  }

  _MCOtxtPlan prependUtf8Run(_Utf8FallbackRun run) {
    final bits =
        MCOtxtCodec._utf8RunOverheadBits + run.bytes.length * 8;
    return prepend(
      _MCOtxtToken.utf8Run(run.bytes, run.text),
      bits: bits,
      encodedCharacters: run.codepoints,
      utf8FallbackRuns: 1,
      utf8FallbackCodepoints: run.codepoints,
      utf8FallbackBytes: run.bytes.length,
      utf8FallbackBits: bits,
    );
  }

  _MCOtxtPlan prepend(
    _MCOtxtToken token, {
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
    MCOtxtTableId? table,
  }) {
    return prependAll(
      <_MCOtxtToken>[token],
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

  _MCOtxtPlan prependAll(
    List<_MCOtxtToken> prefix, {
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
    MCOtxtTableId? table,
  }) {
    final nextTables = <MCOtxtTableId>[];
    if (table != null) nextTables.add(table);
    for (final used in usedTables) {
      if (!nextTables.contains(used)) nextTables.add(used);
    }
    return _MCOtxtPlan(
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
      tokens: <_MCOtxtToken>[...prefix, ...tokens],
      usedTables: nextTables,
    );
  }

  static int compare(_MCOtxtPlan a, _MCOtxtPlan b) {
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
  final List<_MCOtxtToken> tokens;
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

enum _MCOtxtTokenType {
  top4,
  primary,
  punctuation,
  extension,
  shift,
  toggleLanguage,
  switchOtherLanguage,
  resetContext,
  toggleCaseMode,
  utf8Run,
}

class _MCOtxtToken {
  final _MCOtxtTokenType type;
  final int value;
  final Uint8List? bytes;
  final String? text;

  const _MCOtxtToken(this.type, this.value)
    : bytes = null,
      text = null;

  const _MCOtxtToken.utf8Run(this.bytes, this.text)
    : type = _MCOtxtTokenType.utf8Run,
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

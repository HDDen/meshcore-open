import 'dart:typed_data';

import 'models/mcotxt_model.dart';

enum MCOtxtEncodingMode {
  mcotxt,
  rawUtf8,
}

class MCOtxtEncodeResult {
  final String inputText;
  final Uint8List data;
  final int bitLength;
  final MCOtxtEncodingMode encodingMode;
  final String bitStream;
  final List<String> debugTokens;
  final String decodedText;
  final int encoderVersion;

  /// Generation written into the header, also for RAW_UTF8 streams.
  final int modelGeneration;
  final List<MCOtxtTableId> usedTables;
  final MCOtxtLanguageId? languageA;
  final MCOtxtLanguageId? languageB;
  final int mcotxtCandidateBitLength;
  final int mcotxtCandidateBytes;
  final int rawUtf8CandidateBitLength;
  final int rawUtf8CandidateBytes;
  final int selectedBitLength;
  final int selectedBytes;
  final MCOtxtEncodeStats? stats;

  const MCOtxtEncodeResult({
    required this.inputText,
    required this.data,
    required this.bitLength,
    required this.encodingMode,
    required this.bitStream,
    required this.debugTokens,
    required this.decodedText,
    required this.encoderVersion,
    required this.modelGeneration,
    required this.usedTables,
    required this.languageA,
    required this.languageB,
    required this.mcotxtCandidateBitLength,
    required this.mcotxtCandidateBytes,
    required this.rawUtf8CandidateBitLength,
    required this.rawUtf8CandidateBytes,
    required this.selectedBitLength,
    required this.selectedBytes,
    this.stats,
  });
}

class MCOtxtDecodeResult {
  final String text;
  final int decoderVersion;

  /// Generation read from the header. For RAW_UTF8 it is reported as
  /// written and never checked against the tables this build has.
  final int modelGeneration;
  final List<MCOtxtTableId> usedTables;
  final MCOtxtLanguageId? languageA;
  final MCOtxtLanguageId? languageB;

  const MCOtxtDecodeResult({
    required this.text,
    required this.decoderVersion,
    required this.modelGeneration,
    required this.usedTables,
    required this.languageA,
    required this.languageB,
  });
}

class MCOtxtEncodeStats {
  final int inputCharacters;
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
  final int totalBits;
  final int utf8Bytes;

  const MCOtxtEncodeStats({
    required this.inputCharacters,
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
    required this.totalBits,
    required this.utf8Bytes,
  });

  double get top4HitRate {
    if (encodedCharacters == 0) return 0;
    return top4Hits / encodedCharacters;
  }

  double get bitsPerCharacter {
    if (encodedCharacters == 0) return 0;
    return totalBits / encodedCharacters;
  }

  double get compressionRatioVsUtf8 {
    if (utf8Bytes == 0) return 0;
    return (totalBits / 8) / utf8Bytes;
  }
}

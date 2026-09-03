import 'dart:typed_data';

import 'models/mcotxt_model.dart';

enum McotxtEncodingMode {
  mcotxt,
  rawUtf8,
}

class McotxtEncodeResult {
  final String inputText;
  final Uint8List data;
  final int bitLength;
  final McotxtEncodingMode encodingMode;
  final String bitStream;
  final List<String> debugTokens;
  final String decodedText;
  final int encoderVersion;
  final List<McotxtTableId> usedTables;
  final McotxtLanguageId? languageA;
  final McotxtLanguageId? languageB;
  final int mcotxtCandidateBitLength;
  final int mcotxtCandidateBytes;
  final int rawUtf8CandidateBitLength;
  final int rawUtf8CandidateBytes;
  final int selectedBitLength;
  final int selectedBytes;
  final McotxtEncodeStats? stats;

  const McotxtEncodeResult({
    required this.inputText,
    required this.data,
    required this.bitLength,
    required this.encodingMode,
    required this.bitStream,
    required this.debugTokens,
    required this.decodedText,
    required this.encoderVersion,
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

class McotxtDecodeResult {
  final String text;
  final int decoderVersion;
  final List<McotxtTableId> usedTables;
  final McotxtLanguageId? languageA;
  final McotxtLanguageId? languageB;

  const McotxtDecodeResult({
    required this.text,
    required this.decoderVersion,
    required this.usedTables,
    required this.languageA,
    required this.languageB,
  });
}

class McotxtEncodeStats {
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

  const McotxtEncodeStats({
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

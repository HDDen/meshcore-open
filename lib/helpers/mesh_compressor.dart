import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

class MeshCompressor {
  MeshCompressor._();

  static final MeshCompressor instance = MeshCompressor._();

  static const String prefix = 'mcmp:';
  static const String _modelAssetPath =
      'mesh-compressor/docs/model-universal-10lang.json';
  static const String _bos = '\x02';
  static const String _eof = '\x03';
  static const String _esc = '\x04';

  static const int _cdfScale = 1 << 20;
  static const int _precision = 32;
  static final BigInt _full = BigInt.one << _precision;
  static final BigInt _half = BigInt.one << (_precision - 1);
  static final BigInt _quarter = BigInt.one << (_precision - 2);
  static final BigInt _threeQuarter = BigInt.from(3) * _quarter;
  static final BigInt _mask = _full - BigInt.one;

  static const int _scriptBoost = 5;
  static const int _escProb = 500;
  static const int _cdfCacheMax = 50000;

  static const String _base91Alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
      '!#\$%&()*+,./:;<=>?@[]^_`{|}~"';
  static final Map<String, int> _base91Decode = {
    for (int i = 0; i < _base91Alphabet.length; i++) _base91Alphabet[i]: i,
  };

  static const List<_UnicodeBlock> _unicodeBlocks = [
    _UnicodeBlock(0, 0x4E00, 0x9FFF),
    _UnicodeBlock(1, 0xAC00, 0xD7AF),
    _UnicodeBlock(2, 0x0900, 0x097F),
    _UnicodeBlock(3, 0x0E00, 0x0E7F),
    _UnicodeBlock(4, 0x0980, 0x09FF),
    _UnicodeBlock(5, 0x0600, 0x06FF),
    _UnicodeBlock(6, 0x0400, 0x04FF),
    _UnicodeBlock(7, 0x0100, 0x024F),
    _UnicodeBlock(8, 0x3040, 0x309F),
    _UnicodeBlock(9, 0x30A0, 0x30FF),
    _UnicodeBlock(10, 0x0B80, 0x0BFF),
    _UnicodeBlock(11, 0x10A0, 0x10FF),
    _UnicodeBlock(12, 0x0590, 0x05FF),
    _UnicodeBlock(13, 0x0530, 0x058F),
    _UnicodeBlock(14, 0x3400, 0x4DBF),
  ];
  static const int _numBlocks = 15;
  static const int _fallbackBlockId = _numBlocks;
  static const int _cjkCommonBlockId = _numBlocks + 1;
  static const int _totalBlockIds = _numBlocks + 2;
  static const String _cjkCommon =
      '的一是不了人在有我他这中大来上个国和也子时道'
      '到说里自后以会家小下天生能对去出都开就过学好'
      '年多没要起然作那还可为发事看用力心想所如面成'
      '而日么之她着知行已经当其得地无把现前全进从于'
      '种同话被手只最长但因老让很才与两点什头方又样'
      '将间呢机系高正电长问力意理它山公几已明体间但'
      '外分水果定实向情位次应特路真程变合活走几给少'
      '做回本部那每月打工此新本太三给海等法加门间带'
      '气口主第儿美又各关名常感直至场见更重今求满百'
      '放书听民觉吃认已字信使通女号先条别万元车及口'
      '目关四言该区需接找怎任光并世文管北再风清今西'
      '城受望解表觉决期候度白马空叫安完住阳越持请城'
      '算吗花落平广双色近象件记料东入设南品相离消钱'
      '确运夜早半华段院客村须选式园远准习共议论林集'
      '周青王计省市台父争引坐容必办团令格深便政团容'
      '呀笑身板连单杀块红故哪节究极环越孩细拿强石故'
      '响建拉照化音形刚首医局服办随备易差尔争居推兵'
      '速若影断食即算业联调队古切病静份木服球基脸热'
      '止福欢兴终师际备般斯际欢负观题武角坚费另丝黄'
      '类造待千严干考整杂买试护穿复底致微席黑官龙';
  static final Set<String> _cjkCommonSet = _cjkCommon.split('').toSet();
  static final Map<String, int> _cjkCommonMap = {
    for (int i = 0; i < _cjkCommon.length; i++) _cjkCommon[i]: i,
  };

  static const Map<String, Set<String>> _scriptCompat = {
    'CJK': {'CJK', 'CJK_Punct', 'Hiragana', 'Katakana', 'Common'},
    'Hiragana': {'CJK', 'CJK_Punct', 'Hiragana', 'Katakana', 'Common'},
    'Katakana': {'CJK', 'CJK_Punct', 'Hiragana', 'Katakana', 'Common'},
    'CJK_Punct': {'CJK', 'CJK_Punct', 'Hiragana', 'Katakana', 'Common'},
    'Hangul': {'Hangul', 'CJK_Punct', 'Common'},
  };

  _MeshCompressionModel? _model;
  Future<void>? _initializing;

  bool get isReady => _model != null;

  Future<void> initialize() {
    if (_model != null) return Future.value();
    final current = _initializing;
    if (current != null) return current;
    _initializing = _loadModelFromAsset();
    return _initializing!;
  }

  Future<void> initializeFromJsonString(String jsonString) async {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    _model = _MeshCompressionModel.fromJson(decoded);
    _initializing = null;
  }

  String encodeIfSmaller(String text) {
    final model = _model;
    if (model == null || text.isEmpty || text.startsWith(prefix)) {
      return text;
    }
    try {
      final compressed = compressToBytes(text);
      final encoded = _base91Encode(compressed);
      final candidate = '$prefix$encoded';
      if (utf8.encode(candidate).length < utf8.encode(text).length) {
        return candidate;
      }
    } catch (_) {
      // Fall through to the original text on any model/codec issue.
    }
    return text;
  }

  Uint8List compressToBytes(String text) {
    final model = _requireModel();
    return _compress(text, model);
  }

  String decompressBytes(Uint8List data) {
    final model = _requireModel();
    return _decompress(data, model);
  }

  String? tryDecodePrefixed(String text) {
    final trimmedLeft = text.trimLeft();
    if (!trimmedLeft.startsWith(prefix) ||
        trimmedLeft.length <= prefix.length) {
      return null;
    }
    final model = _model;
    if (model == null) return null;
    try {
      final encoded = trimmedLeft.substring(prefix.length);
      final compressed = _base91DecodeBytes(encoded);
      return _decompress(compressed, model);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadModelFromAsset() async {
    try {
      final raw = await rootBundle.loadString(_modelAssetPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _model = _MeshCompressionModel.fromJson(decoded);
    } finally {
      _initializing = null;
    }
  }

  _MeshCompressionModel _requireModel() {
    final model = _model;
    if (model == null) {
      throw StateError('MeshCompressor model is not initialized.');
    }
    return model;
  }

  Uint8List _compress(String text, _MeshCompressionModel model) {
    if (text.isEmpty) {
      return Uint8List.fromList(const [0, 0]);
    }
    final utf8Bytes = Uint8List.fromList(utf8.encode(text));
    final acResult = _compressArithmetic(text, model);
    return acResult.length > utf8Bytes.length ? utf8Bytes : acResult;
  }

  Uint8List _compressArithmetic(String text, _MeshCompressionModel model) {
    final hasExtras = text.runes.any(
      (cp) => !model.vocabSet.contains(String.fromCharCode(cp)),
    );
    final flags = hasExtras ? 1 : 0;
    final encoder = _ArithmeticEncoder();
    var context = _bos * model.order;

    for (final rune in text.runes) {
      var ch = String.fromCharCode(rune);
      if (model.vocabSet.contains(ch)) {
        final cdf = model.getCdf(context);
        final entry = cdf.firstWhere(
          (item) => item.symbol == ch,
          orElse: () => throw StateError('Character missing from CDF: $ch'),
        );
        encoder.encodeSymbol(entry.low, entry.high, _cdfScale);
      } else {
        final cdf = model.getCdf(context);
        final escEntry = cdf.firstWhere(
          (item) => item.symbol == _esc,
          orElse: () => throw StateError('ESC symbol missing from CDF.'),
        );
        encoder.encodeSymbol(escEntry.low, escEntry.high, _cdfScale);
        _encodeCodepoint(encoder, rune);
        ch = String.fromCharCode(rune);
      }
      context = _appendContext(context, ch, model.order);
    }

    final eofEntry = model
        .getCdf(context)
        .firstWhere((item) => item.symbol == _eof);
    encoder.encodeSymbol(eofEntry.low, eofEntry.high, _cdfScale);

    final acBytes = encoder.finish();
    final textLength = text.runes.length;
    if (textLength < 128) {
      return Uint8List.fromList([0x00, (flags << 7) | textLength, ...acBytes]);
    }
    return Uint8List.fromList([
      (textLength >> 8) & 0xFF,
      textLength & 0xFF,
      flags,
      ...acBytes,
    ]);
  }

  String _decompress(Uint8List data, _MeshCompressionModel model) {
    if (data.isEmpty) {
      throw ArgumentError('Empty data');
    }
    if (data[0] != 0x00) {
      return utf8.decode(data, allowMalformed: true);
    }
    if (data.length < 2) {
      throw const FormatException('Data too short for compressed format');
    }
    if (data[1] == 0x00) {
      return '';
    }

    late final int textLength;
    late final bool hasEscapes;
    late final Uint8List acData;

    final byte1 = data[1];
    if ((byte1 & 0x80) == 0) {
      textLength = byte1 & 0x7F;
      hasEscapes = false;
      acData = Uint8List.sublistView(data, 2);
    } else if (byte1 != 0xFF && byte1 >= 0x80) {
      final compactTextLength = byte1 & 0x7F;
      if (compactTextLength > 0) {
        textLength = compactTextLength;
        hasEscapes = true;
        acData = Uint8List.sublistView(data, 2);
      } else {
        if (data.length < 3) {
          throw const FormatException('Data too short for standard header');
        }
        textLength = (data[0] << 8) | data[1];
        final flags = data[2];
        if (flags > 1) {
          return _decompressLegacyHeader(data, model, textLength, flags);
        }
        hasEscapes = flags == 1;
        acData = Uint8List.sublistView(data, 3);
      }
    } else {
      throw FormatException(
        'Unexpected header byte: 0x${byte1.toRadixString(16)}',
      );
    }

    if (acData.isEmpty) {
      throw const FormatException('No AC data after header');
    }
    return _decodeArithmetic(acData, model, textLength, hasEscapes);
  }

  String _decompressLegacyHeader(
    Uint8List data,
    _MeshCompressionModel model,
    int textLength,
    int extraCount,
  ) {
    var offset = 3;
    for (int i = 0; i < extraCount; i++) {
      final charLen = data[offset];
      offset += 1 + charLen;
    }
    final acData = Uint8List.sublistView(data, offset);
    if (acData.isEmpty) {
      throw const FormatException('No AC data after header');
    }
    return _decodeArithmetic(acData, model, textLength, false);
  }

  String _decodeArithmetic(
    Uint8List acData,
    _MeshCompressionModel model,
    int textLength,
    bool hasEscapes,
  ) {
    final decoder = _ArithmeticDecoder(acData);
    var context = _bos * model.order;
    final buffer = StringBuffer();

    for (int i = 0; i < textLength + 1; i++) {
      final cdf = model.getCdf(context);
      var ch = decoder.decodeSymbol(cdf);
      if (ch == _eof) {
        break;
      }
      if (ch == _esc && hasEscapes) {
        ch = String.fromCharCode(_decodeCodepoint(decoder));
      }
      buffer.write(ch);
      context = _appendContext(context, ch, model.order);
    }
    return buffer.toString();
  }

  void _encodeCodepoint(_ArithmeticEncoder encoder, int codepoint) {
    final ch = String.fromCharCode(codepoint);
    if (_cjkCommonSet.contains(ch)) {
      encoder.encodeSymbol(
        _cjkCommonBlockId,
        _cjkCommonBlockId + 1,
        _totalBlockIds,
      );
      final index = _cjkCommonMap[ch]!;
      encoder.encodeSymbol(index, index + 1, _cjkCommon.length);
      return;
    }

    for (final block in _unicodeBlocks) {
      if (codepoint >= block.start && codepoint <= block.end) {
        encoder.encodeSymbol(block.id, block.id + 1, _totalBlockIds);
        final offset = codepoint - block.start;
        encoder.encodeSymbol(offset, offset + 1, block.size);
        return;
      }
    }

    encoder.encodeSymbol(
      _fallbackBlockId,
      _fallbackBlockId + 1,
      _totalBlockIds,
    );
    encoder.encodeSymbol(codepoint & 0x7F, (codepoint & 0x7F) + 1, 128);
    encoder.encodeSymbol(
      (codepoint >> 7) & 0x7F,
      ((codepoint >> 7) & 0x7F) + 1,
      128,
    );
    encoder.encodeSymbol(
      (codepoint >> 14) & 0x7F,
      ((codepoint >> 14) & 0x7F) + 1,
      128,
    );
  }

  int _decodeCodepoint(_ArithmeticDecoder decoder) {
    final blockCdf = List<_CdfEntry>.generate(
      _totalBlockIds,
      (i) => _CdfEntry('', i, i + 1),
      growable: false,
    );
    final blockId = decoder.decodeSymbolIndex(blockCdf);

    if (blockId == _cjkCommonBlockId) {
      final idxCdf = List<_CdfEntry>.generate(
        _cjkCommon.length,
        (i) => _CdfEntry('', i, i + 1),
        growable: false,
      );
      final idx = decoder.decodeSymbolIndex(idxCdf);
      return _cjkCommon.runes.elementAt(idx);
    }
    if (blockId < _numBlocks) {
      final block = _unicodeBlocks[blockId];
      final offsetCdf = List<_CdfEntry>.generate(
        block.size,
        (i) => _CdfEntry('', i, i + 1),
        growable: false,
      );
      final offset = decoder.decodeSymbolIndex(offsetCdf);
      return block.start + offset;
    }

    final cpCdf = List<_CdfEntry>.generate(
      128,
      (i) => _CdfEntry('', i, i + 1),
      growable: false,
    );
    final b0 = decoder.decodeSymbolIndex(cpCdf);
    final b1 = decoder.decodeSymbolIndex(cpCdf);
    final b2 = decoder.decodeSymbolIndex(cpCdf);
    return b0 | (b1 << 7) | (b2 << 14);
  }

  String _appendContext(String context, String ch, int order) {
    final combined = '$context$ch';
    if (combined.runes.length <= order) return combined;
    final runes = combined.runes.toList(growable: false);
    return String.fromCharCodes(runes.sublist(runes.length - order));
  }

  String _charScript(String ch) {
    final cp = ch.runes.first;
    if (cp < 0x0041) return 'Common';
    if (cp <= 0x024F) return 'Latin';
    if (cp >= 0x1E00 && cp <= 0x1EFF) return 'Latin';
    if ((cp >= 0x0400 && cp <= 0x04FF) || (cp >= 0x0500 && cp <= 0x052F)) {
      return 'Cyrillic';
    }
    if ((cp >= 0x0600 && cp <= 0x06FF) ||
        (cp >= 0x0750 && cp <= 0x077F) ||
        (cp >= 0xFB50 && cp <= 0xFDFF) ||
        (cp >= 0xFE70 && cp <= 0xFEFF)) {
      return 'Arabic';
    }
    if (cp >= 0x0900 && cp <= 0x097F) return 'Devanagari';
    if (cp >= 0x0E00 && cp <= 0x0E7F) return 'Thai';
    if (cp >= 0x10A0 && cp <= 0x10FF) return 'Georgian';
    if ((cp >= 0xAC00 && cp <= 0xD7AF) ||
        (cp >= 0x1100 && cp <= 0x11FF) ||
        (cp >= 0x3130 && cp <= 0x318F)) {
      return 'Hangul';
    }
    if ((cp >= 0x4E00 && cp <= 0x9FFF) ||
        (cp >= 0x3400 && cp <= 0x4DBF) ||
        (cp >= 0x20000 && cp <= 0x2A6DF) ||
        (cp >= 0xF900 && cp <= 0xFAFF)) {
      return 'CJK';
    }
    if (cp >= 0x3040 && cp <= 0x309F) return 'Hiragana';
    if (cp >= 0x30A0 && cp <= 0x30FF) return 'Katakana';
    if ((cp >= 0x3000 && cp <= 0x303F) || (cp >= 0xFF00 && cp <= 0xFFEF)) {
      return 'CJK_Punct';
    }
    if (cp >= 0x0370 && cp <= 0x03FF) return 'Greek';
    if (cp >= 0x0590 && cp <= 0x05FF) return 'Hebrew';
    if (cp >= 0x0530 && cp <= 0x058F) return 'Armenian';
    if (cp >= 0x0980 && cp <= 0x09FF) return 'Bengali';
    if (cp >= 0x0B80 && cp <= 0x0BFF) return 'Tamil';
    if (cp > 0xFFFF) return 'Common';
    return 'Other';
  }

  String _base91Encode(Uint8List data) {
    if (data.isEmpty) return '';
    final result = StringBuffer();
    int n = 0;
    int nBits = 0;

    for (final byte in data) {
      n |= byte << nBits;
      nBits += 8;
      if (nBits > 13) {
        int value = n & 8191;
        if (value > 88) {
          n >>= 13;
          nBits -= 13;
        } else {
          value = n & 16383;
          n >>= 14;
          nBits -= 14;
        }
        result
          ..write(_base91Alphabet[value % 91])
          ..write(_base91Alphabet[value ~/ 91]);
      }
    }

    if (nBits > 0) {
      result.write(_base91Alphabet[n % 91]);
      if (n >= 91 || nBits > 7) {
        result.write(_base91Alphabet[n ~/ 91]);
      }
    }
    return result.toString();
  }

  Uint8List _base91DecodeBytes(String text) {
    if (text.isEmpty) return Uint8List(0);
    final out = BytesBuilder(copy: false);
    int n = 0;
    int nBits = 0;
    int value = -1;

    for (final ch in text.split('')) {
      final decoded = _base91Decode[ch];
      if (decoded == null) {
        throw FormatException('Invalid Base91 character: $ch');
      }
      if (value == -1) {
        value = decoded;
      } else {
        value += decoded * 91;
        final bitCount = (value & 8191) > 88 ? 13 : 14;
        n |= value << nBits;
        nBits += bitCount;
        value = -1;

        while (nBits >= 8) {
          out.addByte(n & 0xFF);
          n >>= 8;
          nBits -= 8;
        }
      }
    }

    if (value != -1) {
      n |= value << nBits;
      nBits += 7;
      while (nBits >= 8) {
        out.addByte(n & 0xFF);
        n >>= 8;
        nBits -= 8;
      }
    }

    return out.toBytes();
  }
}

class _MeshCompressionModel {
  _MeshCompressionModel({
    required this.order,
    required this.vocab,
    required this.counts,
  }) : vocabSet = vocab.toSet(),
       vocabIndex = {for (int i = 0; i < vocab.length; i++) vocab[i]: i},
       totals = List<Map<String, int>>.generate(
         counts.length,
         (n) => {
           for (final entry in counts[n].entries)
             entry.key: entry.value.values.fold(0, (sum, value) => sum + value),
         },
         growable: false,
       ) {
    for (final ch in vocab) {
      charScripts[ch] = MeshCompressor.instance._charScript(ch);
    }
  }

  factory _MeshCompressionModel.fromJson(Map<String, dynamic> json) {
    final order = json['o'] as int;
    final vocab = (json['v'] as List<dynamic>).cast<String>();
    final rawCounts = (json['c'] as List<dynamic>);
    final counts = List<Map<String, Map<String, int>>>.generate(order + 1, (n) {
      final contexts = rawCounts[n] as Map<String, dynamic>;
      return {
        for (final ctxEntry in contexts.entries)
          ctxEntry.key: {
            for (final countEntry
                in (ctxEntry.value as Map<String, dynamic>).entries)
              countEntry.key: (countEntry.value as num).toInt(),
          },
      };
    }, growable: false);
    return _MeshCompressionModel(order: order, vocab: vocab, counts: counts);
  }

  final int order;
  final List<String> vocab;
  final Set<String> vocabSet;
  final Map<String, int> vocabIndex;
  final List<Map<String, Map<String, int>>> counts;
  final List<Map<String, int>> totals;
  final Map<String, String> charScripts = {};
  final Map<String, List<_CdfEntry>> _cdfCache = {};

  List<_CdfEntry> getCdf(String context) {
    final cached = _cdfCache[context];
    if (cached != null) return cached;
    final cdf = _computeCdf(context);
    if (_cdfCache.length < MeshCompressor._cdfCacheMax) {
      _cdfCache[context] = cdf;
    }
    return cdf;
  }

  List<_CdfEntry> _computeCdf(String context) {
    final active = <(int, String, int, double)>[];
    double totalWeight = 0;

    String? earlyScript;
    final contextRunes = context.runes.toList(growable: false);
    for (int i = contextRunes.length - 1; i >= 0; i--) {
      final ch = String.fromCharCode(contextRunes[i]);
      if (ch == MeshCompressor._bos) continue;
      earlyScript = charScripts[ch];
      if (earlyScript != null && earlyScript != 'Common') {
        break;
      }
    }

    final isSparseScript =
        earlyScript == 'CJK' ||
        earlyScript == 'Hiragana' ||
        earlyScript == 'Katakana' ||
        earlyScript == 'Hangul';

    for (int n = order; n >= 0; n--) {
      final ctx = n > 0
          ? String.fromCharCodes(
              contextRunes.skip(math.max(0, contextRunes.length - n)),
            )
          : '';
      final total = totals[n][ctx] ?? 0;
      if (total <= 0) continue;
      final denom = isSparseScript ? (n + 8.0) : (n + 1.5);
      final confidence = math.min(total / denom, 1.0);
      final weight =
          math.pow(n + 1, 3).toDouble() * math.log(total + 1) * confidence;
      active.add((n, ctx, total, weight));
      totalWeight += weight;
    }

    String? contextScript;
    for (int i = contextRunes.length - 1; i >= 0; i--) {
      final ch = String.fromCharCode(contextRunes[i]);
      if (ch == MeshCompressor._bos) continue;
      contextScript = charScripts[ch];
      if (contextScript != null && contextScript != 'Common') {
        break;
      }
    }

    Set<String>? compatScripts;
    if (contextScript != null &&
        MeshCompressor._scriptCompat.containsKey(contextScript)) {
      compatScripts = MeshCompressor._scriptCompat[contextScript];
    } else if (contextScript != null && contextScript != 'Common') {
      compatScripts = {contextScript, 'Common'};
    }

    final freqs = List<int>.filled(vocab.length, 0, growable: false);
    int epsilonTotal = 0;
    for (int i = 0; i < vocab.length; i++) {
      final ch = vocab[i];
      final chScript = charScripts[ch] ?? 'Other';
      late final int epsilon;
      if (ch == MeshCompressor._esc) {
        epsilon = MeshCompressor._escProb;
      } else if (compatScripts != null && compatScripts.contains(chScript)) {
        epsilon = MeshCompressor._scriptBoost;
      } else if (chScript == 'Common') {
        epsilon = MeshCompressor._scriptBoost ~/ 3;
      } else {
        epsilon = 1;
      }
      freqs[i] = epsilon;
      epsilonTotal += epsilon;
    }

    if (epsilonTotal > MeshCompressor._cdfScale ~/ 2) {
      final scaleFactor = (MeshCompressor._cdfScale ~/ 2) / epsilonTotal;
      epsilonTotal = 0;
      for (int i = 0; i < freqs.length; i++) {
        freqs[i] = math.max(1, (freqs[i] * scaleFactor).toInt());
        epsilonTotal += freqs[i];
      }
    }

    if (totalWeight > 0) {
      final scale = MeshCompressor._cdfScale - epsilonTotal;
      for (final (n, ctx, total, weight) in active) {
        final countsForContext = counts[n][ctx];
        if (countsForContext == null) continue;
        final factor = (weight / totalWeight) * scale / total;
        for (final entry in countsForContext.entries) {
          final index = vocabIndex[entry.key];
          if (index == null) continue;
          freqs[index] += (entry.value * factor).toInt();
        }
      }
    }

    final total = freqs.fold<int>(0, (sum, value) => sum + value);
    if (total != MeshCompressor._cdfScale) {
      var diff = MeshCompressor._cdfScale - total;
      if (diff > 0) {
        int maxIndex = 0;
        for (int i = 1; i < freqs.length; i++) {
          if (freqs[i] > freqs[maxIndex]) maxIndex = i;
        }
        freqs[maxIndex] += diff;
      } else {
        final indices = List<int>.generate(freqs.length, (i) => i)
          ..sort((a, b) => freqs[b].compareTo(freqs[a]));
        var remaining = -diff;
        for (final index in indices) {
          if (remaining <= 0) break;
          final canRemove = freqs[index] - 1;
          final remove = math.min(canRemove, remaining);
          freqs[index] -= remove;
          remaining -= remove;
        }
      }
    }

    final cdf = <_CdfEntry>[];
    int cum = 0;
    for (int i = 0; i < vocab.length; i++) {
      final freq = freqs[i];
      cdf.add(_CdfEntry(vocab[i], cum, cum + freq));
      cum += freq;
    }
    return cdf;
  }
}

class _ArithmeticEncoder {
  BigInt low = BigInt.zero;
  BigInt high = MeshCompressor._mask;
  int pending = 0;
  final List<int> bits = [];

  void encodeSymbol(int lowCount, int highCount, int total) {
    final range = high - low + BigInt.one;
    final totalBig = BigInt.from(total);
    high = low + (range * BigInt.from(highCount)) ~/ totalBig - BigInt.one;
    low = low + (range * BigInt.from(lowCount)) ~/ totalBig;

    while (true) {
      if (high < MeshCompressor._half) {
        _emitBit(0);
      } else if (low >= MeshCompressor._half) {
        _emitBit(1);
        low -= MeshCompressor._half;
        high -= MeshCompressor._half;
      } else if (low >= MeshCompressor._quarter &&
          high < MeshCompressor._threeQuarter) {
        pending += 1;
        low -= MeshCompressor._quarter;
        high -= MeshCompressor._quarter;
      } else {
        break;
      }
      low = (low << 1) & MeshCompressor._mask;
      high = ((high << 1) | BigInt.one) & MeshCompressor._mask;
    }
  }

  Uint8List finish() {
    pending += 1;
    if (low < MeshCompressor._quarter) {
      _emitBit(0);
    } else {
      _emitBit(1);
    }

    while (bits.length % 8 != 0) {
      bits.add(0);
    }

    final out = BytesBuilder(copy: false);
    for (int i = 0; i < bits.length; i += 8) {
      int byte = 0;
      for (int j = 0; j < 8; j++) {
        byte = (byte << 1) | bits[i + j];
      }
      out.addByte(byte);
    }
    return out.toBytes();
  }

  void _emitBit(int bit) {
    bits.add(bit);
    final opposite = 1 - bit;
    for (int i = 0; i < pending; i++) {
      bits.add(opposite);
    }
    pending = 0;
  }
}

class _ArithmeticDecoder {
  _ArithmeticDecoder(this.data) : totalBits = data.length * 8 {
    for (int i = 0; i < MeshCompressor._precision; i++) {
      value = (value << 1) | BigInt.from(_readBit());
    }
  }

  final Uint8List data;
  final int totalBits;
  BigInt low = BigInt.zero;
  BigInt high = MeshCompressor._mask;
  BigInt value = BigInt.zero;
  int bitPos = 0;

  String decodeSymbol(List<_CdfEntry> cdf) {
    final index = decodeSymbolIndex(cdf);
    return cdf[index].symbol;
  }

  int decodeSymbolIndex(List<_CdfEntry> cdf) {
    final range = high - low + BigInt.one;
    final scaled =
        (((value - low + BigInt.one) * BigInt.from(MeshCompressor._cdfScale)) -
            BigInt.one) ~/
        range;
    final scaledInt = scaled.toInt();

    int left = 0;
    int right = cdf.length - 1;
    while (left < right) {
      final mid = (left + right) >> 1;
      if (cdf[mid].high <= scaledInt) {
        left = mid + 1;
      } else {
        right = mid;
      }
    }
    final entry = cdf[left];
    final totalBig = BigInt.from(MeshCompressor._cdfScale);
    high = low + (range * BigInt.from(entry.high)) ~/ totalBig - BigInt.one;
    low = low + (range * BigInt.from(entry.low)) ~/ totalBig;

    while (true) {
      if (high < MeshCompressor._half) {
        // noop
      } else if (low >= MeshCompressor._half) {
        low -= MeshCompressor._half;
        high -= MeshCompressor._half;
        value -= MeshCompressor._half;
      } else if (low >= MeshCompressor._quarter &&
          high < MeshCompressor._threeQuarter) {
        low -= MeshCompressor._quarter;
        high -= MeshCompressor._quarter;
        value -= MeshCompressor._quarter;
      } else {
        break;
      }
      low = (low << 1) & MeshCompressor._mask;
      high = ((high << 1) | BigInt.one) & MeshCompressor._mask;
      value = ((value << 1) | BigInt.from(_readBit())) & MeshCompressor._mask;
    }
    return left;
  }

  int _readBit() {
    if (bitPos >= totalBits) return 0;
    final byteIndex = bitPos >> 3;
    final bitIndex = 7 - (bitPos & 7);
    bitPos += 1;
    return (data[byteIndex] >> bitIndex) & 1;
  }
}

class _CdfEntry {
  const _CdfEntry(this.symbol, this.low, this.high);

  final String symbol;
  final int low;
  final int high;
}

class _UnicodeBlock {
  const _UnicodeBlock(this.id, this.start, this.end);

  final int id;
  final int start;
  final int end;

  int get size => end - start + 1;
}

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

class ModelTextCompression {
  static const String _assetPath = 'assets/models/model-universal-10lang.json';
  static const String _prefix = 'mc:';
  static const int _cdfScale = 1 << 20;
  static const int _precision = 32;
  static const int _full = 1 << _precision;
  static const int _half = 1 << (_precision - 1);
  static const int _quarter = 1 << (_precision - 2);
  static const int _threeQuarter = _quarter * 3;
  static const int _mask = _full - 1;
  static const String _bos = '\u0002';
  static const String _eof = '\u0003';
  static const String _esc = '\u0004';
  static const int _scriptBoost = 5;
  static const int _escapeProbability = 500;
  static const int _cdfCacheMax = 50000;

  static const List<_UnicodeBlock> _unicodeBlocks = [
    _UnicodeBlock(0x4E00, 0x9FFF),
    _UnicodeBlock(0xAC00, 0xD7AF),
    _UnicodeBlock(0x0900, 0x097F),
    _UnicodeBlock(0x0E00, 0x0E7F),
    _UnicodeBlock(0x0980, 0x09FF),
    _UnicodeBlock(0x0600, 0x06FF),
    _UnicodeBlock(0x0400, 0x04FF),
    _UnicodeBlock(0x0100, 0x024F),
    _UnicodeBlock(0x3040, 0x309F),
    _UnicodeBlock(0x30A0, 0x30FF),
    _UnicodeBlock(0x0B80, 0x0BFF),
    _UnicodeBlock(0x10A0, 0x10FF),
    _UnicodeBlock(0x0590, 0x05FF),
    _UnicodeBlock(0x0530, 0x058F),
    _UnicodeBlock(0x3400, 0x4DBF),
  ];

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

  static final Map<String, int> _cjkCommonMap = () {
    final map = <String, int>{};
    final chars = _cjkCommon.runes.map(String.fromCharCode).toList();
    for (int i = 0; i < chars.length; i++) {
      map[chars[i]] = i;
    }
    return map;
  }();
  static final int _numBlocks = _unicodeBlocks.length;
  static final int _fallbackBlockId = _numBlocks;
  static final int _cjkCommonBlockId = _numBlocks + 1;
  static final int _totalBlockIds = _numBlocks + 2;

  static const Map<String, Set<String>> _scriptCompat = {
    'CJK': {'CJK', 'CJK_Punct', 'Hiragana', 'Katakana', 'Common'},
    'Hiragana': {'CJK', 'CJK_Punct', 'Hiragana', 'Katakana', 'Common'},
    'Katakana': {'CJK', 'CJK_Punct', 'Hiragana', 'Katakana', 'Common'},
    'CJK_Punct': {'CJK', 'CJK_Punct', 'Hiragana', 'Katakana', 'Common'},
    'Hangul': {'Hangul', 'CJK_Punct', 'Common'},
  };

  static _NGramModel? _model;
  static Future<void>? _initFuture;

  static bool get isInitialized => _model != null;

  static Future<void> ensureInitialized() {
    final existing = _initFuture;
    if (existing != null) return existing;
    _initFuture = _loadModel();
    return _initFuture!;
  }

  static Future<void> _loadModel() async {
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _model = _NGramModel.fromJson(decoded);
  }

  static String encodeIfSmaller(String text) {
    final model = _model;
    if (model == null || text.isEmpty || text.startsWith(_prefix)) {
      return text;
    }

    try {
      final compressed = _compress(text, model);
      final encoded = _prefix + _b91encode(compressed);
      return utf8.encode(encoded).length < utf8.encode(text).length
          ? encoded
          : text;
    } catch (_) {
      return text;
    }
  }

  static String? tryDecodePrefixed(String text) {
    final model = _model;
    if (model == null) return null;
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith(_prefix) || trimmed.length <= _prefix.length) {
      return null;
    }

    try {
      final bytes = _b91decode(trimmed.substring(_prefix.length));
      return _decompress(bytes, model);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _compress(String text, _NGramModel model) {
    if (text.isEmpty) {
      return Uint8List.fromList([0, 0]);
    }

    final utf8Bytes = Uint8List.fromList(utf8.encode(text));
    final hasExtras = text.runes
        .map(String.fromCharCode)
        .any((ch) => !model.vocabSet.contains(ch));
    final flags = hasExtras ? 1 : 0;

    final encoder = _ArithmeticEncoder();
    var context = _bos * model.order;

    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final cdf = model.getCdf(context);
      if (model.vocabSet.contains(ch)) {
        final interval = _findInterval(cdf, ch);
        if (interval == null) {
          throw const FormatException('Character missing from CDF.');
        }
        encoder.encodeSymbol(interval.low, interval.high, _cdfScale);
      } else {
        final escape = _findInterval(cdf, _esc);
        if (escape == null) {
          throw const FormatException('Escape symbol missing from CDF.');
        }
        encoder.encodeSymbol(escape.low, escape.high, _cdfScale);
        _encodeCodepoint(encoder, rune);
      }
      context = _appendToContext(context, ch, model.order);
    }

    final eofInterval = _findInterval(model.getCdf(context), _eof);
    if (eofInterval == null) {
      throw const FormatException('EOF symbol missing from CDF.');
    }
    encoder.encodeSymbol(eofInterval.low, eofInterval.high, _cdfScale);

    final acBytes = encoder.finish();
    final textLen = text.runes.length;
    final out = BytesBuilder(copy: false);
    if (textLen < 128) {
      out.addByte(0);
      out.addByte((flags << 7) | textLen);
    } else {
      out.addByte((textLen >> 8) & 0xFF);
      out.addByte(textLen & 0xFF);
      out.addByte(flags);
    }
    out.add(acBytes);

    final result = out.toBytes();
    return result.length > utf8Bytes.length ? utf8Bytes : result;
  }

  static String _decompress(Uint8List data, _NGramModel model) {
    if (data.isEmpty) {
      throw const FormatException('Empty data');
    }
    if (data[0] != 0) {
      return utf8.decode(data, allowMalformed: true);
    }
    if (data.length < 2) {
      throw const FormatException('Data too short for compressed format.');
    }
    if (data[1] == 0) {
      return '';
    }

    final byte1 = data[1];
    late final int textLen;
    late final bool hasEscapes;
    late final Uint8List acData;

    if ((byte1 & 0x80) == 0) {
      textLen = byte1 & 0x7F;
      hasEscapes = false;
      acData = Uint8List.sublistView(data, 2);
    } else {
      final compactTextLen = byte1 & 0x7F;
      if (compactTextLen > 0) {
        textLen = compactTextLen;
        hasEscapes = true;
        acData = Uint8List.sublistView(data, 2);
      } else {
        if (data.length < 3) {
          throw const FormatException('Data too short for standard header.');
        }
        textLen = (data[0] << 8) | data[1];
        final flags = data[2];
        if (flags > 1) {
          return _decompressV1(data, model, textLen, flags);
        }
        hasEscapes = flags == 1;
        acData = Uint8List.sublistView(data, 3);
      }
    }

    if (acData.isEmpty) {
      throw const FormatException('No arithmetic-coded payload found.');
    }

    final decoder = _ArithmeticDecoder(acData);
    var context = _bos * model.order;
    final out = StringBuffer();

    for (int i = 0; i < textLen + 1; i++) {
      final symbol = decoder.decodeSymbol(model.getCdf(context));
      if (symbol == _eof) {
        break;
      }
      var ch = symbol;
      if (ch == _esc && hasEscapes) {
        ch = String.fromCharCode(_decodeCodepoint(decoder));
      }
      out.write(ch);
      context = _appendToContext(context, ch, model.order);
    }

    return out.toString();
  }

  static String _decompressV1(
    Uint8List data,
    _NGramModel model,
    int textLen,
    int nExtra,
  ) {
    var offset = 3;
    for (int i = 0; i < nExtra; i++) {
      final chLen = data[offset];
      offset += 1;
      final ch = utf8.decode(
        Uint8List.sublistView(data, offset, offset + chLen),
        allowMalformed: true,
      );
      offset += chLen;
      model.ensureChar(ch);
    }

    final decoder = _ArithmeticDecoder(Uint8List.sublistView(data, offset));
    var context = _bos * model.order;
    final out = StringBuffer();
    for (int i = 0; i < textLen + 1; i++) {
      final ch = decoder.decodeSymbol(model.getCdf(context));
      if (ch == _eof) break;
      out.write(ch);
      context = _appendToContext(context, ch, model.order);
    }
    return out.toString();
  }

  static String _appendToContext(String context, String ch, int order) {
    final runes = (context + ch).runes.toList(growable: false);
    final start = runes.length > order ? runes.length - order : 0;
    return String.fromCharCodes(runes.sublist(start));
  }

  static String _tailContext(String context, int count) {
    if (count <= 0) return '';
    final runes = context.runes.toList(growable: false);
    final start = runes.length > count ? runes.length - count : 0;
    return String.fromCharCodes(runes.sublist(start));
  }

  static _CdfInterval? _findInterval(List<_CdfInterval> cdf, String symbol) {
    for (final item in cdf) {
      if (item.symbol == symbol) return item;
    }
    return null;
  }

  static void _encodeCodepoint(_ArithmeticEncoder encoder, int codepoint) {
    final ch = String.fromCharCode(codepoint);
    final commonIndex = _cjkCommonMap[ch];
    if (commonIndex != null) {
      encoder.encodeSymbol(
        _cjkCommonBlockId,
        _cjkCommonBlockId + 1,
        _totalBlockIds,
      );
      encoder.encodeSymbol(commonIndex, commonIndex + 1, _cjkCommon.length);
      return;
    }

    for (int i = 0; i < _unicodeBlocks.length; i++) {
      final block = _unicodeBlocks[i];
      if (codepoint < block.start || codepoint > block.end) continue;
      encoder.encodeSymbol(i, i + 1, _totalBlockIds);
      final offset = codepoint - block.start;
      encoder.encodeSymbol(offset, offset + 1, block.size);
      return;
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

  static int _decodeCodepoint(_ArithmeticDecoder decoder) {
    final blockCdf = List<_CdfInterval>.generate(
      _totalBlockIds,
      (i) => _CdfInterval('$i', i, i + 1),
      growable: false,
    );
    final blockId = int.parse(decoder.decodeSymbol(blockCdf));

    if (blockId == _cjkCommonBlockId) {
      final idxCdf = List<_CdfInterval>.generate(
        _cjkCommon.length,
        (i) => _CdfInterval('$i', i, i + 1),
        growable: false,
      );
      final idx = int.parse(decoder.decodeSymbol(idxCdf));
      return _cjkCommon.runes.elementAt(idx);
    }

    if (blockId < _numBlocks) {
      final block = _unicodeBlocks[blockId];
      final offsetCdf = List<_CdfInterval>.generate(
        block.size,
        (i) => _CdfInterval('$i', i, i + 1),
        growable: false,
      );
      final offset = int.parse(decoder.decodeSymbol(offsetCdf));
      return block.start + offset;
    }

    final sevenBitCdf = List<_CdfInterval>.generate(
      128,
      (i) => _CdfInterval('$i', i, i + 1),
      growable: false,
    );
    final b0 = int.parse(decoder.decodeSymbol(sevenBitCdf));
    final b1 = int.parse(decoder.decodeSymbol(sevenBitCdf));
    final b2 = int.parse(decoder.decodeSymbol(sevenBitCdf));
    return b0 | (b1 << 7) | (b2 << 14);
  }

  static String _charScript(String ch) {
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

  static String _b91encode(Uint8List data) {
    if (data.isEmpty) return '';
    final out = StringBuffer();
    int n = 0;
    int nbits = 0;
    for (final byte in data) {
      n |= byte << nbits;
      nbits += 8;
      if (nbits > 13) {
        int value = n & 8191;
        if (value > 88) {
          n >>= 13;
          nbits -= 13;
        } else {
          value = n & 16383;
          n >>= 14;
          nbits -= 14;
        }
        out.write(_base91Alphabet[value % 91]);
        out.write(_base91Alphabet[value ~/ 91]);
      }
    }
    if (nbits > 0) {
      out.write(_base91Alphabet[n % 91]);
      if (n >= 91 || nbits > 7) {
        out.write(_base91Alphabet[n ~/ 91]);
      }
    }
    return out.toString();
  }

  static Uint8List _b91decode(String text) {
    if (text.isEmpty) return Uint8List(0);
    final out = <int>[];
    int n = 0;
    int nbits = 0;
    int value = -1;
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final decoded = _base91Decode[ch];
      if (decoded == null) {
        throw FormatException('Invalid Base91 character: $ch');
      }
      if (value == -1) {
        value = decoded;
        continue;
      }
      value += decoded * 91;
      final bits = (value & 8191) > 88 ? 13 : 14;
      n |= value << nbits;
      nbits += bits;
      value = -1;
      while (nbits >= 8) {
        out.add(n & 0xFF);
        n >>= 8;
        nbits -= 8;
      }
    }
    if (value != -1) {
      n |= value << nbits;
      nbits += 7;
      while (nbits >= 8) {
        out.add(n & 0xFF);
        n >>= 8;
        nbits -= 8;
      }
    }
    return Uint8List.fromList(out);
  }
}

class _UnicodeBlock {
  final int start;
  final int end;

  const _UnicodeBlock(this.start, this.end);

  int get size => end - start + 1;
}

class _CdfInterval {
  final String symbol;
  final int low;
  final int high;

  const _CdfInterval(this.symbol, this.low, this.high);
}

class _NGramModel {
  final int order;
  final List<String> vocab;
  final Set<String> vocabSet;
  final List<Map<String, Map<String, int>>> counts;
  final List<Map<String, int>> totals;
  final Map<String, int> vocabIndex;
  final Map<String, String> charScripts;
  final Map<String, List<_CdfInterval>> _cdfCache = {};

  _NGramModel._({
    required this.order,
    required this.vocab,
    required this.vocabSet,
    required this.counts,
    required this.totals,
    required this.vocabIndex,
    required this.charScripts,
  });

  factory _NGramModel.fromJson(Map<String, dynamic> json) {
    final order = json['o'] as int;
    final vocab = (json['v'] as List<dynamic>).cast<String>();
    final counts = <Map<String, Map<String, int>>>[];
    final totals = <Map<String, int>>[];
    for (int n = 0; n <= order; n++) {
      final orderMap = <String, Map<String, int>>{};
      final totalMap = <String, int>{};
      final rawOrder = json['c'][n] as Map<String, dynamic>;
      rawOrder.forEach((ctx, value) {
        final charMap = <String, int>{};
        int sum = 0;
        (value as Map<String, dynamic>).forEach((ch, count) {
          final parsed = count as int;
          charMap[ch] = parsed;
          sum += parsed;
        });
        orderMap[ctx] = charMap;
        totalMap[ctx] = sum;
      });
      counts.add(orderMap);
      totals.add(totalMap);
    }

    final vocabIndex = <String, int>{};
    final charScripts = <String, String>{};
    for (int i = 0; i < vocab.length; i++) {
      final ch = vocab[i];
      vocabIndex[ch] = i;
      charScripts[ch] = ModelTextCompression._charScript(ch);
    }

    return _NGramModel._(
      order: order,
      vocab: List<String>.from(vocab),
      vocabSet: vocab.toSet(),
      counts: counts,
      totals: totals,
      vocabIndex: vocabIndex,
      charScripts: charScripts,
    );
  }

  void ensureChar(String ch) {
    if (vocabSet.contains(ch)) return;
    vocabSet.add(ch);
    vocab.add(ch);
    vocab.sort();
    vocabIndex
      ..clear()
      ..addEntries(vocab.asMap().entries.map((e) => MapEntry(e.value, e.key)));
    charScripts[ch] = ModelTextCompression._charScript(ch);
    _cdfCache.clear();
  }

  List<_CdfInterval> getCdf(String context) {
    final cached = _cdfCache[context];
    if (cached != null) return cached;
    final cdf = _computeCdf(context);
    if (_cdfCache.length < ModelTextCompression._cdfCacheMax) {
      _cdfCache[context] = cdf;
    }
    return cdf;
  }

  List<_CdfInterval> _computeCdf(String context) {
    final active = <({int n, String ctx, int total, double weight})>[];
    double totalWeight = 0;
    String? ctxScriptEarly;

    for (final rune in context.runes.toList().reversed) {
      final ch = String.fromCharCode(rune);
      if (ch == ModelTextCompression._bos) continue;
      ctxScriptEarly = charScripts[ch];
      if (ctxScriptEarly != null && ctxScriptEarly != 'Common') {
        break;
      }
    }

    final sparse =
        ctxScriptEarly == 'CJK' ||
        ctxScriptEarly == 'Hiragana' ||
        ctxScriptEarly == 'Katakana' ||
        ctxScriptEarly == 'Hangul';

    for (int n = order; n >= 0; n--) {
      final ctx = ModelTextCompression._tailContext(context, n);
      final total = totals[n][ctx];
      if (total == null || total <= 0) continue;
      final confidence = sparse
          ? (total / (n + 8.0)).clamp(0.0, 1.0)
          : (total / (n + 1.5)).clamp(0.0, 1.0);
      final weight = (n + 1) * (n + 1) * (n + 1) * _log1p(total) * confidence;
      active.add((n: n, ctx: ctx, total: total, weight: weight));
      totalWeight += weight;
    }

    String? ctxScript;
    for (final rune in context.runes.toList().reversed) {
      final ch = String.fromCharCode(rune);
      if (ch == ModelTextCompression._bos) continue;
      ctxScript = charScripts[ch];
      if (ctxScript != null && ctxScript != 'Common') break;
    }

    final compatScripts = ctxScript == null
        ? null
        : ModelTextCompression._scriptCompat[ctxScript] ??
              {ctxScript, 'Common'};

    final freqs = List<int>.filled(vocab.length, 0, growable: false);
    int epsilonTotal = 0;
    for (int i = 0; i < vocab.length; i++) {
      final ch = vocab[i];
      final script = charScripts[ch] ?? 'Other';
      final eps = ch == ModelTextCompression._esc
          ? ModelTextCompression._escapeProbability
          : compatScripts != null && compatScripts.contains(script)
          ? ModelTextCompression._scriptBoost
          : script == 'Common'
          ? ModelTextCompression._scriptBoost ~/ 3
          : 1;
      freqs[i] = eps;
      epsilonTotal += eps;
    }

    if (epsilonTotal > ModelTextCompression._cdfScale ~/ 2) {
      final scale = (ModelTextCompression._cdfScale ~/ 2) / epsilonTotal;
      epsilonTotal = 0;
      for (int i = 0; i < freqs.length; i++) {
        freqs[i] = (freqs[i] * scale).floor();
        if (freqs[i] < 1) freqs[i] = 1;
        epsilonTotal += freqs[i];
      }
    }

    if (totalWeight > 0) {
      final availableScale = ModelTextCompression._cdfScale - epsilonTotal;
      for (final entry in active) {
        final ctxCounts = counts[entry.n][entry.ctx];
        if (ctxCounts == null) continue;
        final factor =
            (entry.weight / totalWeight) * availableScale / entry.total;
        ctxCounts.forEach((ch, count) {
          final idx = vocabIndex[ch];
          if (idx == null) return;
          freqs[idx] += (count * factor).floor();
        });
      }
    }

    int total = freqs.fold(0, (sum, item) => sum + item);
    if (total != ModelTextCompression._cdfScale) {
      int diff = ModelTextCompression._cdfScale - total;
      if (diff > 0) {
        int maxIdx = 0;
        for (int i = 1; i < freqs.length; i++) {
          if (freqs[i] > freqs[maxIdx]) maxIdx = i;
        }
        freqs[maxIdx] += diff;
      } else {
        final indices = List<int>.generate(freqs.length, (i) => i)
          ..sort((a, b) => freqs[b].compareTo(freqs[a]));
        int remaining = -diff;
        for (final idx in indices) {
          if (remaining <= 0) break;
          final removable = freqs[idx] - 1;
          final remove = removable < remaining ? removable : remaining;
          freqs[idx] -= remove;
          remaining -= remove;
        }
      }
    }

    final cdf = <_CdfInterval>[];
    int cumulative = 0;
    for (int i = 0; i < vocab.length; i++) {
      cdf.add(_CdfInterval(vocab[i], cumulative, cumulative + freqs[i]));
      cumulative += freqs[i];
    }
    return cdf;
  }

  double _log1p(num value) =>
      value <= -1 ? double.negativeInfinity : math.log(1 + value.toDouble());
}

class _ArithmeticEncoder {
  int low = 0;
  int high = ModelTextCompression._mask;
  int pending = 0;
  final List<int> bits = [];

  void _emitBit(int bit) {
    bits.add(bit);
    final opposite = 1 - bit;
    for (int i = 0; i < pending; i++) {
      bits.add(opposite);
    }
    pending = 0;
  }

  void encodeSymbol(int cumLow, int cumHigh, int total) {
    final range = high - low + 1;
    high = low + (range * cumHigh) ~/ total - 1;
    low = low + (range * cumLow) ~/ total;

    while (true) {
      if (high < ModelTextCompression._half) {
        _emitBit(0);
      } else if (low >= ModelTextCompression._half) {
        _emitBit(1);
        low -= ModelTextCompression._half;
        high -= ModelTextCompression._half;
      } else if (low >= ModelTextCompression._quarter &&
          high < ModelTextCompression._threeQuarter) {
        pending += 1;
        low -= ModelTextCompression._quarter;
        high -= ModelTextCompression._quarter;
      } else {
        break;
      }
      low = (low << 1) & ModelTextCompression._mask;
      high = ((high << 1) | 1) & ModelTextCompression._mask;
    }
  }

  Uint8List finish() {
    pending += 1;
    _emitBit(low < ModelTextCompression._quarter ? 0 : 1);
    while (bits.length % 8 != 0) {
      bits.add(0);
    }
    final out = Uint8List(bits.length ~/ 8);
    for (int i = 0; i < bits.length; i += 8) {
      int byte = 0;
      for (int j = 0; j < 8; j++) {
        byte = (byte << 1) | bits[i + j];
      }
      out[i ~/ 8] = byte;
    }
    return out;
  }
}

class _ArithmeticDecoder {
  final Uint8List data;
  int low = 0;
  int high = ModelTextCompression._mask;
  int value = 0;
  int bitPos = 0;

  _ArithmeticDecoder(this.data) {
    for (int i = 0; i < ModelTextCompression._precision; i++) {
      value = (value << 1) | _readBit();
    }
  }

  int _readBit() {
    final totalBits = data.length * 8;
    if (bitPos >= totalBits) return 0;
    final byteIndex = bitPos >> 3;
    final bitIndex = 7 - (bitPos & 7);
    bitPos += 1;
    return (data[byteIndex] >> bitIndex) & 1;
  }

  String decodeSymbol(List<_CdfInterval> cdf) {
    final range = high - low + 1;
    final scaled =
        (((value - low + 1) * ModelTextCompression._cdfScale) - 1) ~/ range;

    int lo = 0;
    int hi = cdf.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (cdf[mid].high <= scaled) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    final interval = cdf[lo];
    high = low + (range * interval.high) ~/ ModelTextCompression._cdfScale - 1;
    low = low + (range * interval.low) ~/ ModelTextCompression._cdfScale;

    while (true) {
      if (high < ModelTextCompression._half) {
        // no-op
      } else if (low >= ModelTextCompression._half) {
        low -= ModelTextCompression._half;
        high -= ModelTextCompression._half;
        value -= ModelTextCompression._half;
      } else if (low >= ModelTextCompression._quarter &&
          high < ModelTextCompression._threeQuarter) {
        low -= ModelTextCompression._quarter;
        high -= ModelTextCompression._quarter;
        value -= ModelTextCompression._quarter;
      } else {
        break;
      }
      low = (low << 1) & ModelTextCompression._mask;
      high = ((high << 1) | 1) & ModelTextCompression._mask;
      value = ((value << 1) | _readBit()) & ModelTextCompression._mask;
    }

    return interval.symbol;
  }
}

const String _base91Alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#\$%&()*+,./:;<=>?@[]^_`{|}~"';

final Map<String, int> _base91Decode = () {
  final map = <String, int>{};
  for (int i = 0; i < _base91Alphabet.length; i++) {
    map[_base91Alphabet[i]] = i;
  }
  return map;
}();

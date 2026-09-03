import 'mcotxt_model.dart';
import 'punctuation.dart';

class McotxtModelRegistry {
  static const int languageNoneWireId = 7;
  static const int extendedLanguageHeaderWireId = 7;
  static const int extendedLanguagePair8Format = 0;
  static const int rawUtf8HeaderFormat = 1;
  static const int globalLanguageNoneId = 255;
  static const int inlineLanguageMaxId = 6;

  static final List<McotxtLanguageModel> builtinModels =
      <McotxtLanguageModel>[
        _buildModel(
          McotxtLanguageId.en,
          primary: ' etaoinshrdlucmfwypvbgkqjxz',
          extension: '0123456789',
          uppercase: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
          lowercase: 'abcdefghijklmnopqrstuvwxyz',
          top4Seed: ' etaoinsrhl',
          training:
              'the quick brown fox jumps over the lazy dog. hello, world: meshcore lora message text',
        ),
        _buildModel(
          McotxtLanguageId.ru,
          primary: ' оеаинтсрвлкмдпуяызьгчбжйхцшюф',
          extension: 'ёъэщ',
          uppercase: 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ',
          lowercase: 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
          top4Seed: ' оеаинтрсвл',
          training:
              'привет мир, как дела. нормально работает: сообщение текст',
        ),
        _buildModel(
          McotxtLanguageId.fr,
          primary: ' eaistnrulodcmpvqfbghjxyzwk',
          extension: 'éèêëàâîïôùûçœ0123456789',
          uppercase:
              'ABCDEFGHIJKLMNOPQRSTUVWXYZÉÈÊËÀÂÎÏÔÙÛÇŒ',
          lowercase:
              'abcdefghijklmnopqrstuvwxyzéèêëàâîïôùûçœ',
          top4Seed: ' esaitnrul',
          training:
              'bonjour le monde, comment ca va. message texte reseau radio',
        ),
        _buildModel(
          McotxtLanguageId.de,
          primary: ' enirsatdhulgocmbfwkzpvjyxq',
          extension: 'äöüß0123456789',
          uppercase: 'ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ',
          lowercase: 'abcdefghijklmnopqrstuvwxyzäöü',
          top4Seed: ' enirsathd',
          training:
              'hallo welt, wie geht es dir. nachricht text funk netz',
        ),
        _buildModel(
          McotxtLanguageId.it,
          primary: ' eaionlrtscdupmvgfbzhqàèéìòù',
          extension: '0123456789',
          uppercase: 'ABCDEFGHIJKLMNOPQRSTUVWXYZÀÈÉÌÒÙ',
          lowercase: 'abcdefghijklmnopqrstuvwxyzàèéìòù',
          top4Seed: ' eaionlrst',
          training:
              'ciao mondo, come stai. messaggio testo radio rete',
        ),
        _buildModel(
          McotxtLanguageId.uk,
          primary: ' оаиенвртслкмудпязибьгчхйцшю',
          extension: 'іїєґщжфъыёэ',
          uppercase: 'АБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯ',
          lowercase: 'абвгґдеєжзиіїйклмнопрстуфхцчшщьюя',
          top4Seed: ' оаинертвс',
          training:
              'привіт світ, як справи. повідомлення текст працює через радіо',
        ),
        _buildModel(
          McotxtLanguageId.be,
          primary: ' аоеінтрсвлкмдзпуяыьчгхбйшю',
          extension: 'ўёэфцщжъ',
          uppercase: 'АБВГДЕЁЖЗІЙКЛМНОПРСТУЎФХЦЧШЫЬЭЮЯ',
          lowercase: 'абвгдеёжзійклмнопрстуўфхцчшыьэюя',
          top4Seed: ' аоеінтрсв',
          training:
              'прывітанне свет, як справы. паведамленне тэкст працуе радыё',
        ),
      ];

  static final Map<McotxtLanguageId, McotxtLanguageModel> _modelsById =
      <McotxtLanguageId, McotxtLanguageModel>{
        for (final model in builtinModels) model.id: model,
      };

  static final Map<int, McotxtLanguageModel> _modelsByGlobalId =
      <int, McotxtLanguageModel>{
        for (final model in builtinModels) model.globalId: model,
      };

  static McotxtLanguageModel? modelFor(McotxtLanguageId? id) {
    if (id == null) return null;
    return _modelsById[id];
  }

  static McotxtLanguageModel? modelForGlobalId(int? globalId) {
    if (globalId == null || globalId == globalLanguageNoneId) return null;
    return _modelsByGlobalId[globalId];
  }

  static McotxtLanguageId? languageForGlobalId(int? globalId) {
    if (globalId == null || globalId == globalLanguageNoneId) return null;
    return McotxtLanguageId.fromGlobalId(globalId);
  }

  static List<int> get availableGlobalLanguageIds =>
      List<int>.unmodifiable(_modelsByGlobalId.keys);

  static int? inlineHeaderIdForGlobalId(int? globalId) {
    if (globalId == null || globalId == globalLanguageNoneId) {
      return languageNoneWireId;
    }
    return globalId >= 0 && globalId <= inlineLanguageMaxId ? globalId : null;
  }

  static String normalizeInputText(String text) {
    final normalizedNewlines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final runes = normalizedNewlines.runes.toList(growable: false);
    final output = <int>[];
    for (var i = 0; i < runes.length; i++) {
      if (i + 1 < runes.length) {
        final composed = _composePair(runes[i], runes[i + 1]);
        if (composed != null) {
          output.add(composed);
          i++;
          continue;
        }
      }
      output.add(runes[i]);
    }
    return String.fromCharCodes(output);
  }

  static int? _composePair(int base, int combining) {
    return _nfcPairMap[(base << 21) | combining];
  }

  static final Map<int, int> _nfcPairMap = <int, int>{
    for (final entry in _nfcPairs)
      (entry.$1 << 21) | entry.$2: entry.$3,
  };

  static const List<(int, int, int)> _nfcPairs = <(int, int, int)>[
    (0x0061, 0x0300, 0x00e0),
    (0x0061, 0x0302, 0x00e2),
    (0x0041, 0x0300, 0x00c0),
    (0x0041, 0x0302, 0x00c2),
    (0x0063, 0x0327, 0x00e7),
    (0x0043, 0x0327, 0x00c7),
    (0x0065, 0x0300, 0x00e8),
    (0x0065, 0x0301, 0x00e9),
    (0x0065, 0x0302, 0x00ea),
    (0x0065, 0x0308, 0x00eb),
    (0x0045, 0x0300, 0x00c8),
    (0x0045, 0x0301, 0x00c9),
    (0x0045, 0x0302, 0x00ca),
    (0x0045, 0x0308, 0x00cb),
    (0x0069, 0x0300, 0x00ec),
    (0x0069, 0x0302, 0x00ee),
    (0x0069, 0x0308, 0x00ef),
    (0x0049, 0x0300, 0x00cc),
    (0x0049, 0x0302, 0x00ce),
    (0x0049, 0x0308, 0x00cf),
    (0x006f, 0x0302, 0x00f4),
    (0x006f, 0x0308, 0x00f6),
    (0x004f, 0x0302, 0x00d4),
    (0x004f, 0x0308, 0x00d6),
    (0x0075, 0x0300, 0x00f9),
    (0x0075, 0x0302, 0x00fb),
    (0x0075, 0x0308, 0x00fc),
    (0x0055, 0x0300, 0x00d9),
    (0x0055, 0x0302, 0x00db),
    (0x0055, 0x0308, 0x00dc),
    (0x0435, 0x0308, 0x0451),
    (0x0415, 0x0308, 0x0401),
    (0x0438, 0x0306, 0x0439),
    (0x0418, 0x0306, 0x0419),
    (0x0456, 0x0308, 0x0457),
    (0x0406, 0x0308, 0x0407),
    (0x0443, 0x0306, 0x045e),
    (0x0423, 0x0306, 0x040e),
  ];

  static McotxtLanguageModel _buildModel(
    McotxtLanguageId id, {
    required String primary,
    required String extension,
    required String uppercase,
    required String lowercase,
    required String top4Seed,
    required String training,
  }) {
    final primaryRunes = _uniqueRunes(primary);
    final extensionRunes = _uniqueRunes(extension)
        .where((rune) => !primaryRunes.contains(rune))
        .toList(growable: false);
    final symbols = <int>[...primaryRunes, ...extensionRunes];
    final caseMap = _caseMap(uppercase, lowercase);
    final seed = _uniqueRunes(top4Seed)
        .where(symbols.contains)
        .toList(growable: true);
    for (final symbol in symbols) {
      if (seed.length >= 4) break;
      if (!seed.contains(symbol)) seed.add(symbol);
    }
    final modelTop4 = _buildTop4Tables(
      symbols: symbols,
      seed: seed,
      training: training,
      caseMap: caseMap,
    );
    return McotxtLanguageModel(
      id: id,
      primarySymbols: primaryRunes,
      extensionSymbols: extensionRunes,
      startTop4: modelTop4.startTop4,
      punctStartTop4: modelTop4.punctStartTop4,
      top4: modelTop4.top4,
      uppercaseToLowercase: caseMap,
    );
  }

  static ({
    List<int> startTop4,
    List<int> punctStartTop4,
    List<List<int>> top4,
  })
  _buildTop4Tables({
    required List<int> symbols,
    required List<int> seed,
    required String training,
    required Map<int, int> caseMap,
  }) {
    final symbolSet = symbols.toSet();
    final symbolIndex = <int, int>{
      for (var i = 0; i < symbols.length; i++) symbols[i]: i,
    };
    final startCounts = <int, int>{};
    final punctStartCounts = <int, int>{};
    final transitionCounts = <int, Map<int, int>>{
      for (final symbol in symbols) symbol: <int, int>{},
    };
    var contextKind = McotxtPredictionContextKind.start;
    int? previous;
    for (final rawRune in training.runes) {
      if (rawRune != McotxtPunctuation.space &&
          McotxtPunctuation.idByRune.containsKey(rawRune)) {
        contextKind = rawRune == McotxtPunctuation.lineFeed
            ? McotxtPredictionContextKind.start
            : McotxtPredictionContextKind.afterPunctuation;
        previous = null;
        continue;
      }
      final rune = symbolSet.contains(rawRune) ? rawRune : caseMap[rawRune];
      if (rune == null || !symbolSet.contains(rune)) {
        continue;
      }
      switch (contextKind) {
        case McotxtPredictionContextKind.start:
          startCounts[rune] = (startCounts[rune] ?? 0) + 1;
        case McotxtPredictionContextKind.afterPunctuation:
          punctStartCounts[rune] = (punctStartCounts[rune] ?? 0) + 1;
        case McotxtPredictionContextKind.symbol:
          final counts = transitionCounts[previous]!;
          counts[rune] = (counts[rune] ?? 0) + 1;
      }
      previous = rune;
      contextKind = McotxtPredictionContextKind.symbol;
    }

    List<int> rankedTop4(Map<int, int> counts) {
      final ranked = counts.keys.toList(growable: true)
        ..sort((a, b) {
          final countCompare = counts[b]!.compareTo(counts[a]!);
          if (countCompare != 0) return countCompare;
          return symbolIndex[a]!.compareTo(symbolIndex[b]!);
        });
      final result = <int>[];
      for (final rune in ranked) {
        if (!result.contains(rune)) result.add(rune);
        if (result.length == 4) return result;
      }
      for (final rune in seed) {
        if (!result.contains(rune)) result.add(rune);
        if (result.length == 4) return result;
      }
      for (final rune in symbols) {
        if (!result.contains(rune)) result.add(rune);
        if (result.length == 4) return result;
      }
      return result;
    }

    return (
      startTop4: List<int>.unmodifiable(rankedTop4(startCounts)),
      punctStartTop4: List<int>.unmodifiable(rankedTop4(punctStartCounts)),
      top4: List<List<int>>.unmodifiable(
        symbols.map((symbol) {
          return List<int>.unmodifiable(rankedTop4(transitionCounts[symbol]!));
        }),
      ),
    );
  }

  static List<int> _uniqueRunes(String text) {
    final seen = <int>{};
    final result = <int>[];
    for (final rune in text.runes) {
      if (seen.add(rune)) result.add(rune);
    }
    return result;
  }

  static Map<int, int> _caseMap(String uppercase, String lowercase) {
    final upperRunes = uppercase.runes.toList(growable: false);
    final lowerRunes = lowercase.runes.toList(growable: false);
    if (upperRunes.length != lowerRunes.length) {
      throw ArgumentError('MCOtxt case map lengths differ');
    }
    return <int, int>{
      for (var i = 0; i < upperRunes.length; i++) upperRunes[i]: lowerRunes[i],
    };
  }
}

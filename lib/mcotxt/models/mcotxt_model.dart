enum MCOtxtLanguageId {
  en,
  ru,
  fr,
  de,
  it,
  uk,
  be;

  int get wireId {
    return switch (this) {
      MCOtxtLanguageId.en => 0,
      MCOtxtLanguageId.ru => 1,
      MCOtxtLanguageId.fr => 2,
      MCOtxtLanguageId.de => 3,
      MCOtxtLanguageId.it => 4,
      MCOtxtLanguageId.uk => 5,
      MCOtxtLanguageId.be => 6,
    };
  }

  int get globalId => wireId;

  bool get hasInlineHeaderId => wireId >= 0 && wireId <= 6;

  static MCOtxtLanguageId? fromWireId(int value) {
    return switch (value) {
      0 => MCOtxtLanguageId.en,
      1 => MCOtxtLanguageId.ru,
      2 => MCOtxtLanguageId.fr,
      3 => MCOtxtLanguageId.de,
      4 => MCOtxtLanguageId.it,
      5 => MCOtxtLanguageId.uk,
      6 => MCOtxtLanguageId.be,
      7 => null,
      _ => null,
    };
  }

  static MCOtxtLanguageId? fromGlobalId(int value) {
    return fromWireId(value);
  }
}

enum MCOtxtTableId {
  en,
  ru,
  fr,
  de,
  it,
  uk,
  be,
  punctuation;

  static MCOtxtTableId fromLanguage(MCOtxtLanguageId language) {
    return switch (language) {
      MCOtxtLanguageId.en => MCOtxtTableId.en,
      MCOtxtLanguageId.ru => MCOtxtTableId.ru,
      MCOtxtLanguageId.fr => MCOtxtTableId.fr,
      MCOtxtLanguageId.de => MCOtxtTableId.de,
      MCOtxtLanguageId.it => MCOtxtTableId.it,
      MCOtxtLanguageId.uk => MCOtxtTableId.uk,
      MCOtxtLanguageId.be => MCOtxtTableId.be,
    };
  }
}

class MCOtxtLanguageModel {
  final MCOtxtLanguageId id;
  final bool available;
  final String? wireHash;
  final List<int> primarySymbols;
  final List<int> extensionSymbols;
  final List<List<int>> top4;
  final List<int> startTop4;
  final List<int> punctStartTop4;
  final Map<int, int> uppercaseToLowercase;
  final Map<int, int> lowercaseToUppercase;
  final Map<int, int> _primaryIdByRune;
  final Map<int, int> _extensionIdByRune;
  final Map<int, int> _symbolIndexByRune;

  MCOtxtLanguageModel({
    required this.id,
    this.wireHash,
    required Iterable<int> primarySymbols,
    required Iterable<int> extensionSymbols,
    required Iterable<int> startTop4,
    required Iterable<int> punctStartTop4,
    required Iterable<Iterable<int>> top4,
    required Map<int, int> uppercaseToLowercase,
  }) : available = true,
       primarySymbols = List<int>.unmodifiable(primarySymbols),
       extensionSymbols = List<int>.unmodifiable(extensionSymbols),
       startTop4 = List<int>.unmodifiable(startTop4),
       punctStartTop4 = List<int>.unmodifiable(punctStartTop4),
       top4 = List<List<int>>.unmodifiable(
         top4.map((row) => List<int>.unmodifiable(row)),
       ),
       uppercaseToLowercase = Map<int, int>.unmodifiable(uppercaseToLowercase),
       lowercaseToUppercase = Map<int, int>.unmodifiable({
         for (final entry in uppercaseToLowercase.entries)
           entry.value: entry.key,
       }),
       _primaryIdByRune = {
         for (var i = 0; i < primarySymbols.length; i++)
           primarySymbols.elementAt(i): i,
       },
       _extensionIdByRune = {
         for (var i = 0; i < extensionSymbols.length; i++)
           extensionSymbols.elementAt(i): i,
       },
       _symbolIndexByRune = {
         for (var i = 0; i < primarySymbols.length; i++)
           primarySymbols.elementAt(i): i,
         for (var i = 0; i < extensionSymbols.length; i++)
           extensionSymbols.elementAt(i): primarySymbols.length + i,
       } {
    if (this.primarySymbols.length > 32) {
      throw ArgumentError('MCOtxt primary table is limited to 32 symbols');
    }
    if (this.extensionSymbols.length > 32) {
      throw ArgumentError('MCOtxt extension table is limited to 32 symbols');
    }
    if (!this.primarySymbols.contains(0x20)) {
      throw ArgumentError('MCOtxt primary table must contain SPACE');
    }
    if (this.startTop4.length != 4) {
      throw ArgumentError('MCOtxt startTop4 must contain exactly 4 symbols');
    }
    if (this.punctStartTop4.length != 4) {
      throw ArgumentError(
        'MCOtxt punctStartTop4 must contain exactly 4 symbols',
      );
    }
    if (this.top4.length != symbolCount ||
        this.top4.any((row) => row.length != 4)) {
      throw ArgumentError('MCOtxt top4 must contain one 4-symbol row per symbol');
    }
    _validateTop4Row(this.startTop4, 'startTop4');
    _validateTop4Row(this.punctStartTop4, 'punctStartTop4');
    for (var i = 0; i < this.top4.length; i++) {
      _validateTop4Row(this.top4[i], 'top4[$i]');
    }
  }

  MCOtxtLanguageModel.unavailable({required this.id})
    : available = false,
      wireHash = null,
      primarySymbols = const <int>[],
      extensionSymbols = const <int>[],
      top4 = const <List<int>>[],
      startTop4 = const <int>[],
      punctStartTop4 = const <int>[],
      uppercaseToLowercase = const <int, int>{},
      lowercaseToUppercase = const <int, int>{},
      _primaryIdByRune = const <int, int>{},
      _extensionIdByRune = const <int, int>{},
      _symbolIndexByRune = const <int, int>{};

  int get symbolCount => primarySymbols.length + extensionSymbols.length;

  int get globalId => id.globalId;

  List<int> get symbols => <int>[...primarySymbols, ...extensionSymbols];

  bool containsSymbol(int rune) => _symbolIndexByRune.containsKey(rune);

  int? symbolIndex(int rune) => _symbolIndexByRune[rune];

  int? primaryId(int rune) => _primaryIdByRune[rune];

  int? extensionId(int rune) => _extensionIdByRune[rune];

  int? normalizeRune(int rune) {
    if (containsSymbol(rune)) return rune;
    return uppercaseToLowercase[rune];
  }

  List<int> top4ForContext(
    MCOtxtPredictionContextKind contextKind,
    int? previousRune,
  ) {
    if (contextKind == MCOtxtPredictionContextKind.start) return startTop4;
    if (contextKind == MCOtxtPredictionContextKind.afterPunctuation) {
      return punctStartTop4;
    }
    if (previousRune == null) return const <int>[];
    final index = symbolIndex(previousRune);
    return index == null ? const <int>[] : top4[index];
  }

  void _validateTop4Row(List<int> row, String label) {
    final seen = <int>{};
    for (final symbol in row) {
      if (!containsSymbol(symbol)) {
        throw ArgumentError('MCOtxt $label contains an unknown symbol');
      }
      if (!seen.add(symbol)) {
        throw ArgumentError('MCOtxt $label contains duplicate symbols');
      }
    }
  }
}

enum MCOtxtPredictionContextKind {
  start,
  afterPunctuation,
  symbol,
}

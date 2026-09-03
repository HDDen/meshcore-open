enum McotxtLanguageId {
  en,
  ru,
  fr,
  de,
  it,
  uk,
  be;

  int get wireId {
    return switch (this) {
      McotxtLanguageId.en => 0,
      McotxtLanguageId.ru => 1,
      McotxtLanguageId.fr => 2,
      McotxtLanguageId.de => 3,
      McotxtLanguageId.it => 4,
      McotxtLanguageId.uk => 5,
      McotxtLanguageId.be => 6,
    };
  }

  int get globalId => wireId;

  bool get hasInlineHeaderId => wireId >= 0 && wireId <= 6;

  static McotxtLanguageId? fromWireId(int value) {
    return switch (value) {
      0 => McotxtLanguageId.en,
      1 => McotxtLanguageId.ru,
      2 => McotxtLanguageId.fr,
      3 => McotxtLanguageId.de,
      4 => McotxtLanguageId.it,
      5 => McotxtLanguageId.uk,
      6 => McotxtLanguageId.be,
      7 => null,
      _ => null,
    };
  }

  static McotxtLanguageId? fromGlobalId(int value) {
    return fromWireId(value);
  }
}

enum McotxtTableId {
  en,
  ru,
  fr,
  de,
  it,
  uk,
  be,
  punctuation;

  static McotxtTableId fromLanguage(McotxtLanguageId language) {
    return switch (language) {
      McotxtLanguageId.en => McotxtTableId.en,
      McotxtLanguageId.ru => McotxtTableId.ru,
      McotxtLanguageId.fr => McotxtTableId.fr,
      McotxtLanguageId.de => McotxtTableId.de,
      McotxtLanguageId.it => McotxtTableId.it,
      McotxtLanguageId.uk => McotxtTableId.uk,
      McotxtLanguageId.be => McotxtTableId.be,
    };
  }
}

class McotxtLanguageModel {
  final McotxtLanguageId id;
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

  McotxtLanguageModel({
    required this.id,
    required Iterable<int> primarySymbols,
    required Iterable<int> extensionSymbols,
    required Iterable<int> startTop4,
    required Iterable<int> punctStartTop4,
    required Iterable<Iterable<int>> top4,
    required Map<int, int> uppercaseToLowercase,
  }) : primarySymbols = List<int>.unmodifiable(primarySymbols),
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
    if (this.primarySymbols.length > 31) {
      throw ArgumentError('MCOtxt primary table is limited to 31 symbols');
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
    McotxtPredictionContextKind contextKind,
    int? previousRune,
  ) {
    if (contextKind == McotxtPredictionContextKind.start) return startTop4;
    if (contextKind == McotxtPredictionContextKind.afterPunctuation) {
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

enum McotxtPredictionContextKind {
  start,
  afterPunctuation,
  symbol,
}

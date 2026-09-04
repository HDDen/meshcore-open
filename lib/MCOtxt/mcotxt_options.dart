import 'models/mcotxt_model.dart';
import 'models/mcotxt_model_registry.dart';

/// The two languages a stream declares: A is the starting language, B the one
/// `TOGGLE_LANGUAGE` reaches, or none.
class MCOtxtLanguagePair {
  const MCOtxtLanguagePair(this.a, [this.b]);

  final MCOtxtLanguageId a;
  final MCOtxtLanguageId? b;

  /// The pair the app encodes with by default, derived from the UI language:
  /// that language and EN, or EN and RU when the UI is English. A UI
  /// language with no model falls back to RU when it is written in Cyrillic
  /// and to EN otherwise, so the second language stays the one most likely
  /// to be mixed in. Trying every available pair instead costs a full planning
  /// pass per pair on every keystroke of the composer counter.
  factory MCOtxtLanguagePair.forLocale(
    String languageCode, {
    MCOtxtModelSet? modelSet,
  }) {
    final set = modelSet ?? MCOtxtModelRegistry.latest;
    final code = languageCode.trim().toLowerCase();
    MCOtxtLanguageId? own;
    for (final id in MCOtxtLanguageId.values) {
      if (id.name == code) {
        own = id;
        break;
      }
    }
    if (own == null || !set.isAvailable(own)) {
      own = _cyrillicLanguageCodes.contains(code)
          ? MCOtxtLanguageId.ru
          : MCOtxtLanguageId.en;
    }
    final other =
        own == MCOtxtLanguageId.en ? MCOtxtLanguageId.ru : MCOtxtLanguageId.en;
    return MCOtxtLanguagePair(own, set.isAvailable(other) ? other : null);
  }

  static const Set<String> _cyrillicLanguageCodes = <String>{
    'ru', 'uk', 'be', 'bg', 'sr', 'mk', 'kk', 'ky', 'tg', 'mn',
  };

  @override
  bool operator ==(Object other) =>
      other is MCOtxtLanguagePair && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);

  @override
  String toString() => 'MCOtxtLanguagePair(${a.name}, ${b?.name})';
}

class MCOtxtEncodeOptions {
  final MCOtxtLanguageId? languageA;
  final MCOtxtLanguageId? languageB;

  /// Model-set generation to encode with; null takes the latest one the
  /// build has. A generation this build lacks is `unsupportedModelGeneration`.
  final int? modelGeneration;
  final bool collectStats;

  const MCOtxtEncodeOptions({
    this.languageA,
    this.languageB,
    this.modelGeneration,
    this.collectStats = true,
  });
}

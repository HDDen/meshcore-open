import 'models/mcotxt_model.dart';

class McotxtEncodeOptions {
  final McotxtLanguageId? languageA;
  final McotxtLanguageId? languageB;
  final bool collectStats;

  const McotxtEncodeOptions({
    this.languageA,
    this.languageB,
    this.collectStats = true,
  });
}

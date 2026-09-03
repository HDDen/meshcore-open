import 'models/mcotxt_model.dart';

class MCOtxtEncodeOptions {
  final MCOtxtLanguageId? languageA;
  final MCOtxtLanguageId? languageB;
  final bool collectStats;

  const MCOtxtEncodeOptions({
    this.languageA,
    this.languageB,
    this.collectStats = true,
  });
}

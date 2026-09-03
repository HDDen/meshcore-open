import 'models/mcotxt_model.dart';

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

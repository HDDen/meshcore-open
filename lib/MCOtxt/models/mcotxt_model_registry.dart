import 'mcotxt_model.dart';
import 'generated/v1/model_be.dart';
import 'generated/v1/model_de.dart';
import 'generated/v1/model_en.dart';
import 'generated/v1/model_fr.dart';
import 'generated/v1/model_it.dart';
import 'generated/v1/model_ru.dart';
import 'generated/v1/model_uk.dart';

class MCOtxtModelRegistry {
  static const int languageNoneWireId = 7;
  static const int extendedLanguageHeaderWireId = 7;
  static const int extendedLanguagePair8Format = 0;
  static const int rawUtf8HeaderFormat = 1;
  static const int globalLanguageNoneId = 255;
  static const int inlineLanguageMaxId = 6;

  // All reserved v1 language IDs have a static generated artifact.
  // Missing trained languages are represented by explicit unavailable models;
  // runtime never derives statistical tables from embedded training strings.
  static final List<MCOtxtLanguageModel> allModels = <MCOtxtLanguageModel>[
    mcotxtModelEn,
    mcotxtModelRu,
    mcotxtModelFr,
    mcotxtModelDe,
    mcotxtModelIt,
    mcotxtModelUk,
    mcotxtModelBe,
  ];

  // Historical name retained for codec callers: only wire-usable models are
  // exposed here, so unavailable placeholders never enter encoder search.
  static final List<MCOtxtLanguageModel> builtinModels =
      List<MCOtxtLanguageModel>.unmodifiable(
        allModels.where((model) => model.available),
      );

  static final Map<MCOtxtLanguageId, MCOtxtLanguageModel> _allModelsById =
      <MCOtxtLanguageId, MCOtxtLanguageModel>{
        for (final model in allModels) model.id: model,
      };

  static final Map<int, MCOtxtLanguageModel> _modelsByGlobalId =
      <int, MCOtxtLanguageModel>{
        for (final model in builtinModels) model.globalId: model,
      };

  static MCOtxtLanguageModel? declarationFor(MCOtxtLanguageId? id) {
    if (id == null) return null;
    return _allModelsById[id];
  }

  static bool isAvailable(MCOtxtLanguageId? id) =>
      declarationFor(id)?.available ?? false;

  static MCOtxtLanguageModel? modelFor(MCOtxtLanguageId? id) {
    final model = declarationFor(id);
    return model != null && model.available ? model : null;
  }

  static MCOtxtLanguageModel? modelForGlobalId(int? globalId) {
    if (globalId == null || globalId == globalLanguageNoneId) return null;
    return _modelsByGlobalId[globalId];
  }

  static MCOtxtLanguageId? languageForGlobalId(int? globalId) {
    if (globalId == null || globalId == globalLanguageNoneId) return null;
    return MCOtxtLanguageId.fromGlobalId(globalId);
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
}

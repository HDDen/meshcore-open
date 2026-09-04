// GENERATED FILE - DO NOT EDIT BY HAND.
// MCOtxt v1 static TOP-4 model (START + AFTER_PUNCT): BE (wire id 6).
// Generated with Python Unicode database 15.1.0.

// Package import is intentional: trainer output is also copied into lib/ for runtime.
import 'package:meshcore_open/MCOtxt/models/mcotxt_model.dart';

const String mcotxtBeWireHash = 'dd23c2b82288e0a4452f237ccd905055974779e3cc5cc6f3d03be1b24e5bb1fd';

const List<int> mcotxtBePrimarySymbols = <int>[
  0x0020, 0x043A, 0x043B, 0x043C, 0x0441, 0x0435, 0x0440, 0x0432, 0x043D, 0x044F, 0x0434, 0x0443,
  0x0442, 0x0447, 0x043E, 0x043F, 0x0437, 0x044B, 0x0439, 0x0433, 0x0431, 0x0436, 0x0430, 0x0448,
  0x044E, 0x0445, 0x044C, 0x044D, 0x0032, 0x0444, 0x0446, 0x0031,
];

const List<int> mcotxtBeExtensionSymbols = <int>[
  0x0034, 0x0451, 0x0033, 0x0036, 0x0038, 0x0035, 0x0037, 0x0030, 0x0039, 0x0456, 0x045E,
];

const List<int> mcotxtBeStartTop4Indexes = <int>[
  0, 12, 8, 5,
];

const List<int> mcotxtBePunctStartTop4Indexes = <int>[
  0, 12, 28, 38,
];

const List<int> mcotxtBeTop4Indexes = <int>[
  8, 15, 7, 4, 22, 14, 0, 2, 14, 26, 0, 22, 14, 0, 5, 22, 12, 0, 5, 14, 0, 12, 8, 6, 14, 22, 5, 11,
  0, 22, 5, 14, 22, 14, 5, 11, 0, 12, 16, 8, 5, 14, 22, 11, 0, 12, 21, 4, 14, 22, 0, 26, 5, 22, 12,
  8, 0, 10, 20, 12, 14, 6, 22, 5, 22, 0, 8, 14, 0, 18, 2, 12, 0, 12, 1, 4, 14, 6, 10, 22, 14, 17,
  11, 6, 5, 8, 11, 22, 0, 2, 4, 12, 5, 26, 22, 12, 13, 0, 12, 10, 14, 0, 22, 16, 0, 8, 23, 12, 12,
  1, 29, 7, 0, 28, 39, 32, 14, 22, 29, 11, 5, 22, 7, 17, 39, 37, 0, 31, 0, 37, 36, 39, 0, 12, 3,
  14, 0, 39, 28, 32, 0, 36, 38, 40, 35, 0, 37, 14, 0, 39, 35, 4, 0, 35, 28, 37, 39, 0, 28, 37, 39,
  0, 3, 34, 0, 14, 5, 22, 0, 14, 5, 22,
];

const List<int> mcotxtBeStartTop4 = <int>[
  0x0020, 0x0442, 0x043D, 0x0435,
];

const List<int> mcotxtBePunctStartTop4 = <int>[
  0x0020, 0x0442, 0x0032, 0x0037,
];

const List<List<int>> mcotxtBeTop4 = <List<int>>[
  <int>[0x043D, 0x043F, 0x0432, 0x0441], // #0: U+0020 'SPACE' SPACE
  <int>[0x0430, 0x043E, 0x0020, 0x043B], // #1: U+043A 'к' CYRILLIC SMALL LETTER KA
  <int>[0x043E, 0x044C, 0x0020, 0x0430], // #2: U+043B 'л' CYRILLIC SMALL LETTER EL
  <int>[0x043E, 0x0020, 0x0435, 0x0430], // #3: U+043C 'м' CYRILLIC SMALL LETTER EM
  <int>[0x0442, 0x0020, 0x0435, 0x043E], // #4: U+0441 'с' CYRILLIC SMALL LETTER ES
  <int>[0x0020, 0x0442, 0x043D, 0x0440], // #5: U+0435 'е' CYRILLIC SMALL LETTER IE
  <int>[0x043E, 0x0430, 0x0435, 0x0443], // #6: U+0440 'р' CYRILLIC SMALL LETTER ER
  <int>[0x0020, 0x0430, 0x0435, 0x043E], // #7: U+0432 'в' CYRILLIC SMALL LETTER VE
  <int>[0x0430, 0x043E, 0x0435, 0x0443], // #8: U+043D 'н' CYRILLIC SMALL LETTER EN
  <int>[0x0020, 0x0442, 0x0437, 0x043D], // #9: U+044F 'я' CYRILLIC SMALL LETTER YA
  <int>[0x0435, 0x043E, 0x0430, 0x0443], // #10: U+0434 'д' CYRILLIC SMALL LETTER DE
  <int>[0x0020, 0x0442, 0x0436, 0x0441], // #11: U+0443 'у' CYRILLIC SMALL LETTER U
  <int>[0x043E, 0x0430, 0x0020, 0x044C], // #12: U+0442 'т' CYRILLIC SMALL LETTER TE
  <int>[0x0435, 0x0430, 0x0442, 0x043D], // #13: U+0447 'ч' CYRILLIC SMALL LETTER CHE
  <int>[0x0020, 0x0434, 0x0431, 0x0442], // #14: U+043E 'о' CYRILLIC SMALL LETTER O
  <int>[0x043E, 0x0440, 0x0430, 0x0435], // #15: U+043F 'п' CYRILLIC SMALL LETTER PE
  <int>[0x0430, 0x0020, 0x043D, 0x043E], // #16: U+0437 'з' CYRILLIC SMALL LETTER ZE
  <int>[0x0020, 0x0439, 0x043B, 0x0442], // #17: U+044B 'ы' CYRILLIC SMALL LETTER YERU
  <int>[0x0020, 0x0442, 0x043A, 0x0441], // #18: U+0439 'й' CYRILLIC SMALL LETTER SHORT I
  <int>[0x043E, 0x0440, 0x0434, 0x0430], // #19: U+0433 'г' CYRILLIC SMALL LETTER GHE
  <int>[0x043E, 0x044B, 0x0443, 0x0440], // #20: U+0431 'б' CYRILLIC SMALL LETTER BE
  <int>[0x0435, 0x043D, 0x0443, 0x0430], // #21: U+0436 'ж' CYRILLIC SMALL LETTER ZHE
  <int>[0x0020, 0x043B, 0x0441, 0x0442], // #22: U+0430 'а' CYRILLIC SMALL LETTER A
  <int>[0x0435, 0x044C, 0x0430, 0x0442], // #23: U+0448 'ш' CYRILLIC SMALL LETTER SHA
  <int>[0x0447, 0x0020, 0x0442, 0x0434], // #24: U+044E 'ю' CYRILLIC SMALL LETTER YU
  <int>[0x043E, 0x0020, 0x0430, 0x0437], // #25: U+0445 'х' CYRILLIC SMALL LETTER HA
  <int>[0x0020, 0x043D, 0x0448, 0x0442], // #26: U+044C 'ь' CYRILLIC SMALL LETTER SOFT SIGN
  <int>[0x0442, 0x043A, 0x0444, 0x0432], // #27: U+044D 'э' CYRILLIC SMALL LETTER E
  <int>[0x0020, 0x0032, 0x0030, 0x0034], // #28: U+0032 '2' DIGIT TWO
  <int>[0x043E, 0x0430, 0x0444, 0x0443], // #29: U+0444 'ф' CYRILLIC SMALL LETTER EF
  <int>[0x0435, 0x0430, 0x0432, 0x044B], // #30: U+0446 'ц' CYRILLIC SMALL LETTER TSE
  <int>[0x0030, 0x0035, 0x0020, 0x0031], // #31: U+0031 '1' DIGIT ONE
  <int>[0x0020, 0x0035, 0x0038, 0x0030], // #32: U+0034 '4' DIGIT FOUR
  <int>[0x0020, 0x0442, 0x043C, 0x043E], // #33: U+0451 'ё' CYRILLIC SMALL LETTER IO
  <int>[0x0020, 0x0030, 0x0032, 0x0034], // #34: U+0033 '3' DIGIT THREE
  <int>[0x0020, 0x0038, 0x0037, 0x0039], // #35: U+0036 '6' DIGIT SIX
  <int>[0x0036, 0x0020, 0x0035, 0x043E], // #36: U+0038 '8' DIGIT EIGHT
  <int>[0x0020, 0x0030, 0x0036, 0x0441], // #37: U+0035 '5' DIGIT FIVE
  <int>[0x0020, 0x0036, 0x0032, 0x0035], // #38: U+0037 '7' DIGIT SEVEN
  <int>[0x0030, 0x0020, 0x0032, 0x0035], // #39: U+0030 '0' DIGIT ZERO
  <int>[0x0030, 0x0020, 0x043C, 0x0033], // #40: U+0039 '9' DIGIT NINE
  <int>[0x0020, 0x043E, 0x0435, 0x0430], // #41: U+0456 'і' CYRILLIC SMALL LETTER BYELORUSSIAN-UKRAINIAN I
  <int>[0x0020, 0x043E, 0x0435, 0x0430], // #42: U+045E 'ў' CYRILLIC SMALL LETTER SHORT U
];

const Map<int, int> mcotxtBeUppercaseToLowercase = <int, int>{
  0x0401: 0x0451, // Ё -> ё
  0x0406: 0x0456, // І -> і
  0x040E: 0x045E, // Ў -> ў
  0x0410: 0x0430, // А -> а
  0x0411: 0x0431, // Б -> б
  0x0412: 0x0432, // В -> в
  0x0413: 0x0433, // Г -> г
  0x0414: 0x0434, // Д -> д
  0x0415: 0x0435, // Е -> е
  0x0416: 0x0436, // Ж -> ж
  0x0417: 0x0437, // З -> з
  0x0419: 0x0439, // Й -> й
  0x041A: 0x043A, // К -> к
  0x041B: 0x043B, // Л -> л
  0x041C: 0x043C, // М -> м
  0x041D: 0x043D, // Н -> н
  0x041E: 0x043E, // О -> о
  0x041F: 0x043F, // П -> п
  0x0420: 0x0440, // Р -> р
  0x0421: 0x0441, // С -> с
  0x0422: 0x0442, // Т -> т
  0x0423: 0x0443, // У -> у
  0x0424: 0x0444, // Ф -> ф
  0x0425: 0x0445, // Х -> х
  0x0426: 0x0446, // Ц -> ц
  0x0427: 0x0447, // Ч -> ч
  0x0428: 0x0448, // Ш -> ш
  0x042B: 0x044B, // Ы -> ы
  0x042C: 0x044C, // Ь -> ь
  0x042D: 0x044D, // Э -> э
  0x042E: 0x044E, // Ю -> ю
  0x042F: 0x044F, // Я -> я
};

final MCOtxtLanguageModel mcotxtModelBe = MCOtxtLanguageModel(
  id: MCOtxtLanguageId.be,
  wireHash: mcotxtBeWireHash,
  primarySymbols: mcotxtBePrimarySymbols,
  extensionSymbols: mcotxtBeExtensionSymbols,
  startTop4: mcotxtBeStartTop4,
  punctStartTop4: mcotxtBePunctStartTop4,
  top4: mcotxtBeTop4,
  uppercaseToLowercase: mcotxtBeUppercaseToLowercase,
);

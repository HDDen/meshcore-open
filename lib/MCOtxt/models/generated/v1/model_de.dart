// GENERATED FILE - DO NOT EDIT BY HAND.
// MCOtxt v1 static TOP-4 model (START + AFTER_PUNCT): DE (wire id 3).
// Generated with Python Unicode database 15.1.0.

// Package import is intentional: trainer output is also copied into lib/ for runtime.
import 'package:meshcore_open/MCOtxt/models/mcotxt_model.dart';

const String mcotxtDeWireHash = '00b971288fee56f37535ce03b4ac0d8ebddfc12ecbd5ef282ab4b0f4a659f451';

const List<int> mcotxtDePrimarySymbols = <int>[
  0x0020, 0x0073, 0x0074, 0x0062, 0x0068, 0x006F, 0x0067, 0x006C, 0x0069, 0x006D, 0x006E, 0x0072,
  0x0075, 0x0077, 0x006B, 0x0066, 0x0065, 0x0063, 0x0061, 0x0064, 0x007A, 0x0070, 0x00FC, 0x0076,
  0x006A, 0x00F6, 0x00E4, 0x0031, 0x0033, 0x0032, 0x0079, 0x0035,
];

const List<int> mcotxtDeExtensionSymbols = <int>[
  0x0039, 0x0034, 0x0036, 0x0037, 0x0038, 0x00DF, 0x0078, 0x0030, 0x0071,
];

const List<int> mcotxtDeStartTop4Indexes = <int>[
  6, 9, 4, 19,
];

const List<int> mcotxtDePunctStartTop4Indexes = <int>[
  0, 3, 19, 18,
];

const List<int> mcotxtDeTop4Indexes = <int>[
  18, 19, 9, 8, 0, 2, 16, 17, 0, 16, 18, 2, 16, 8, 18, 0, 0, 18, 16, 2, 11, 8, 10, 21, 16, 12, 11,
  0, 7, 16, 8, 0, 10, 17, 16, 2, 5, 16, 8, 18, 0, 19, 16, 18, 0, 16, 6, 18, 1, 2, 10, 11, 16, 8,
  18, 5, 16, 5, 18, 0, 16, 18, 0, 11, 10, 11, 0, 8, 4, 14, 5, 0, 12, 10, 7, 17, 16, 18, 0, 8, 12,
  16, 2, 0, 1, 16, 21, 15, 37, 11, 3, 17, 5, 16, 8, 12, 16, 18, 5, 12, 10, 11, 7, 6, 2, 26, 12, 10,
  0, 39, 27, 29, 0, 27, 39, 36, 0, 39, 35, 28, 2, 0, 16, 5, 0, 39, 4, 35, 0, 4, 39, 36, 0, 35, 39,
  34, 0, 27, 28, 34, 0, 28, 27, 33, 0, 27, 28, 34, 16, 0, 2, 8, 0, 8, 2, 16, 0, 39, 34, 35, 12, 0,
  2, 1,
];

const List<int> mcotxtDeStartTop4 = <int>[
  0x0067, 0x006D, 0x0068, 0x0064,
];

const List<int> mcotxtDePunctStartTop4 = <int>[
  0x0020, 0x0062, 0x0064, 0x0061,
];

const List<List<int>> mcotxtDeTop4 = <List<int>>[
  <int>[0x0061, 0x0064, 0x006D, 0x0069], // #0: U+0020 'SPACE' SPACE
  <int>[0x0020, 0x0074, 0x0065, 0x0063], // #1: U+0073 's' LATIN SMALL LETTER S
  <int>[0x0020, 0x0065, 0x0061, 0x0074], // #2: U+0074 't' LATIN SMALL LETTER T
  <int>[0x0065, 0x0069, 0x0061, 0x0020], // #3: U+0062 'b' LATIN SMALL LETTER B
  <int>[0x0020, 0x0061, 0x0065, 0x0074], // #4: U+0068 'h' LATIN SMALL LETTER H
  <int>[0x0072, 0x0069, 0x006E, 0x0070], // #5: U+006F 'o' LATIN SMALL LETTER O
  <int>[0x0065, 0x0075, 0x0072, 0x0020], // #6: U+0067 'g' LATIN SMALL LETTER G
  <int>[0x006C, 0x0065, 0x0069, 0x0020], // #7: U+006C 'l' LATIN SMALL LETTER L
  <int>[0x006E, 0x0063, 0x0065, 0x0074], // #8: U+0069 'i' LATIN SMALL LETTER I
  <int>[0x006F, 0x0065, 0x0069, 0x0061], // #9: U+006D 'm' LATIN SMALL LETTER M
  <int>[0x0020, 0x0064, 0x0065, 0x0061], // #10: U+006E 'n' LATIN SMALL LETTER N
  <int>[0x0020, 0x0065, 0x0067, 0x0061], // #11: U+0072 'r' LATIN SMALL LETTER R
  <int>[0x0073, 0x0074, 0x006E, 0x0072], // #12: U+0075 'u' LATIN SMALL LETTER U
  <int>[0x0065, 0x0069, 0x0061, 0x006F], // #13: U+0077 'w' LATIN SMALL LETTER W
  <int>[0x0065, 0x006F, 0x0061, 0x0020], // #14: U+006B 'k' LATIN SMALL LETTER K
  <int>[0x0065, 0x0061, 0x0020, 0x0072], // #15: U+0066 'f' LATIN SMALL LETTER F
  <int>[0x006E, 0x0072, 0x0020, 0x0069], // #16: U+0065 'e' LATIN SMALL LETTER E
  <int>[0x0068, 0x006B, 0x006F, 0x0020], // #17: U+0063 'c' LATIN SMALL LETTER C
  <int>[0x0075, 0x006E, 0x006C, 0x0063], // #18: U+0061 'a' LATIN SMALL LETTER A
  <int>[0x0065, 0x0061, 0x0020, 0x0069], // #19: U+0064 'd' LATIN SMALL LETTER D
  <int>[0x0075, 0x0065, 0x0074, 0x0020], // #20: U+007A 'z' LATIN SMALL LETTER Z
  <int>[0x0073, 0x0065, 0x0070, 0x0066], // #21: U+0070 'p' LATIN SMALL LETTER P
  <int>[0x00DF, 0x0072, 0x0062, 0x0063], // #22: U+00FC 'ü' LATIN SMALL LETTER U WITH DIAERESIS
  <int>[0x006F, 0x0065, 0x0069, 0x0075], // #23: U+0076 'v' LATIN SMALL LETTER V
  <int>[0x0065, 0x0061, 0x006F, 0x0075], // #24: U+006A 'j' LATIN SMALL LETTER J
  <int>[0x006E, 0x0072, 0x006C, 0x0067], // #25: U+00F6 'ö' LATIN SMALL LETTER O WITH DIAERESIS
  <int>[0x0074, 0x00E4, 0x0075, 0x006E], // #26: U+00E4 'ä' LATIN SMALL LETTER A WITH DIAERESIS
  <int>[0x0020, 0x0030, 0x0031, 0x0032], // #27: U+0031 '1' DIGIT ONE
  <int>[0x0020, 0x0031, 0x0030, 0x0038], // #28: U+0033 '3' DIGIT THREE
  <int>[0x0020, 0x0030, 0x0037, 0x0033], // #29: U+0032 '2' DIGIT TWO
  <int>[0x0074, 0x0020, 0x0065, 0x006F], // #30: U+0079 'y' LATIN SMALL LETTER Y
  <int>[0x0020, 0x0030, 0x0068, 0x0037], // #31: U+0035 '5' DIGIT FIVE
  <int>[0x0020, 0x0068, 0x0030, 0x0038], // #32: U+0039 '9' DIGIT NINE
  <int>[0x0020, 0x0037, 0x0030, 0x0036], // #33: U+0034 '4' DIGIT FOUR
  <int>[0x0020, 0x0031, 0x0033, 0x0036], // #34: U+0036 '6' DIGIT SIX
  <int>[0x0020, 0x0033, 0x0031, 0x0034], // #35: U+0037 '7' DIGIT SEVEN
  <int>[0x0020, 0x0031, 0x0033, 0x0036], // #36: U+0038 '8' DIGIT EIGHT
  <int>[0x0065, 0x0020, 0x0074, 0x0069], // #37: U+00DF 'ß' LATIN SMALL LETTER SHARP S
  <int>[0x0020, 0x0069, 0x0074, 0x0065], // #38: U+0078 'x' LATIN SMALL LETTER X
  <int>[0x0020, 0x0030, 0x0036, 0x0037], // #39: U+0030 '0' DIGIT ZERO
  <int>[0x0075, 0x0020, 0x0074, 0x0073], // #40: U+0071 'q' LATIN SMALL LETTER Q
];

const Map<int, int> mcotxtDeUppercaseToLowercase = <int, int>{
  0x0041: 0x0061, // A -> a
  0x0042: 0x0062, // B -> b
  0x0043: 0x0063, // C -> c
  0x0044: 0x0064, // D -> d
  0x0045: 0x0065, // E -> e
  0x0046: 0x0066, // F -> f
  0x0047: 0x0067, // G -> g
  0x0048: 0x0068, // H -> h
  0x0049: 0x0069, // I -> i
  0x004A: 0x006A, // J -> j
  0x004B: 0x006B, // K -> k
  0x004C: 0x006C, // L -> l
  0x004D: 0x006D, // M -> m
  0x004E: 0x006E, // N -> n
  0x004F: 0x006F, // O -> o
  0x0050: 0x0070, // P -> p
  0x0051: 0x0071, // Q -> q
  0x0052: 0x0072, // R -> r
  0x0053: 0x0073, // S -> s
  0x0054: 0x0074, // T -> t
  0x0055: 0x0075, // U -> u
  0x0056: 0x0076, // V -> v
  0x0057: 0x0077, // W -> w
  0x0058: 0x0078, // X -> x
  0x0059: 0x0079, // Y -> y
  0x005A: 0x007A, // Z -> z
  0x00C4: 0x00E4, // Ä -> ä
  0x00D6: 0x00F6, // Ö -> ö
  0x00DC: 0x00FC, // Ü -> ü
  0x1E9E: 0x00DF, // ẞ -> ß
};

final MCOtxtLanguageModel mcotxtModelDe = MCOtxtLanguageModel(
  id: MCOtxtLanguageId.de,
  wireHash: mcotxtDeWireHash,
  primarySymbols: mcotxtDePrimarySymbols,
  extensionSymbols: mcotxtDeExtensionSymbols,
  startTop4: mcotxtDeStartTop4,
  punctStartTop4: mcotxtDePunctStartTop4,
  top4: mcotxtDeTop4,
  uppercaseToLowercase: mcotxtDeUppercaseToLowercase,
);

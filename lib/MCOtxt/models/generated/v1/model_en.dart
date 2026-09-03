// GENERATED FILE - DO NOT EDIT BY HAND.
// MCOtxt v1 static TOP-4 model (START + AFTER_PUNCT): EN (wire id 0).
// Generated with Python Unicode database 15.1.0.

// Package import is intentional: trainer output is also copied into lib/ for runtime.
import 'package:meshcore_open/MCOtxt/models/mcotxt_model.dart';

const String mcotxtEnWireHash = '55988b3bb2a000adf6e768a8541df5a25fec1628b4ec661a10b577e3af8b3770';

const List<int> mcotxtEnPrimarySymbols = <int>[
  0x0020, 0x006F, 0x0064, 0x0061, 0x0069, 0x006C, 0x0072, 0x006D, 0x0079, 0x0074, 0x0063, 0x0070,
  0x0077, 0x0073, 0x0066, 0x0067, 0x0068, 0x0062, 0x006E, 0x0065, 0x006B, 0x0075, 0x0076, 0x0078,
  0x0031, 0x006A, 0x0033, 0x0032, 0x0038, 0x0034, 0x007A, 0x0035,
];

const List<int> mcotxtEnExtensionSymbols = <int>[
  0x0071, 0x0036, 0x0037, 0x0039, 0x0030,
];

const List<int> mcotxtEnStartTop4Indexes = <int>[
  16, 7, 9, 4,
];

const List<int> mcotxtEnPunctStartTop4Indexes = <int>[
  0, 13, 9, 7,
];

const List<int> mcotxtEnTop4Indexes = <int>[
  9, 3, 4, 13, 18, 6, 0, 21, 0, 1, 19, 3, 18, 9, 5, 0, 18, 9, 13, 0, 5, 1, 0, 19, 19, 0, 18, 1, 19,
  1, 0, 3, 0, 1, 19, 13, 0, 16, 1, 19, 1, 16, 3, 19, 19, 13, 0, 1, 19, 4, 3, 0, 0, 9, 19, 16, 0, 1,
  6, 4, 0, 1, 16, 19, 19, 3, 1, 4, 19, 21, 1, 3, 15, 0, 4, 19, 0, 6, 13, 18, 19, 0, 13, 4, 9, 13,
  0, 6, 19, 4, 29, 3, 0, 9, 11, 4, 36, 0, 31, 27, 21, 1, 3, 19, 0, 36, 33, 2, 0, 27, 31, 36, 0, 7,
  33, 36, 0, 36, 29, 33, 19, 30, 8, 4, 0, 36, 33, 27, 21, 0, 7, 9, 0, 36, 35, 28, 0, 5, 10, 6, 0,
  33, 2, 35, 0, 36, 7, 35,
];

const List<int> mcotxtEnStartTop4 = <int>[
  0x0068, 0x006D, 0x0074, 0x0069,
];

const List<int> mcotxtEnPunctStartTop4 = <int>[
  0x0020, 0x0073, 0x0074, 0x006D,
];

const List<List<int>> mcotxtEnTop4 = <List<int>>[
  <int>[0x0074, 0x0061, 0x0069, 0x0073], // #0: U+0020 'SPACE' SPACE
  <int>[0x006E, 0x0072, 0x0020, 0x0075], // #1: U+006F 'o' LATIN SMALL LETTER O
  <int>[0x0020, 0x006F, 0x0065, 0x0061], // #2: U+0064 'd' LATIN SMALL LETTER D
  <int>[0x006E, 0x0074, 0x006C, 0x0020], // #3: U+0061 'a' LATIN SMALL LETTER A
  <int>[0x006E, 0x0074, 0x0073, 0x0020], // #4: U+0069 'i' LATIN SMALL LETTER I
  <int>[0x006C, 0x006F, 0x0020, 0x0065], // #5: U+006C 'l' LATIN SMALL LETTER L
  <int>[0x0065, 0x0020, 0x006E, 0x006F], // #6: U+0072 'r' LATIN SMALL LETTER R
  <int>[0x0065, 0x006F, 0x0020, 0x0061], // #7: U+006D 'm' LATIN SMALL LETTER M
  <int>[0x0020, 0x006F, 0x0065, 0x0073], // #8: U+0079 'y' LATIN SMALL LETTER Y
  <int>[0x0020, 0x0068, 0x006F, 0x0065], // #9: U+0074 't' LATIN SMALL LETTER T
  <int>[0x006F, 0x0068, 0x0061, 0x0065], // #10: U+0063 'c' LATIN SMALL LETTER C
  <int>[0x0065, 0x0073, 0x0020, 0x006F], // #11: U+0070 'p' LATIN SMALL LETTER P
  <int>[0x0065, 0x0069, 0x0061, 0x0020], // #12: U+0077 'w' LATIN SMALL LETTER W
  <int>[0x0020, 0x0074, 0x0065, 0x0068], // #13: U+0073 's' LATIN SMALL LETTER S
  <int>[0x0020, 0x006F, 0x0072, 0x0069], // #14: U+0066 'f' LATIN SMALL LETTER F
  <int>[0x0020, 0x006F, 0x0068, 0x0065], // #15: U+0067 'g' LATIN SMALL LETTER G
  <int>[0x0065, 0x0061, 0x006F, 0x0069], // #16: U+0068 'h' LATIN SMALL LETTER H
  <int>[0x0065, 0x0075, 0x006F, 0x0061], // #17: U+0062 'b' LATIN SMALL LETTER B
  <int>[0x0067, 0x0020, 0x0069, 0x0065], // #18: U+006E 'n' LATIN SMALL LETTER N
  <int>[0x0020, 0x0072, 0x0073, 0x006E], // #19: U+0065 'e' LATIN SMALL LETTER E
  <int>[0x0065, 0x0020, 0x0073, 0x0069], // #20: U+006B 'k' LATIN SMALL LETTER K
  <int>[0x0074, 0x0073, 0x0020, 0x0072], // #21: U+0075 'u' LATIN SMALL LETTER U
  <int>[0x0065, 0x0069, 0x0034, 0x0061], // #22: U+0076 'v' LATIN SMALL LETTER V
  <int>[0x0020, 0x0074, 0x0070, 0x0069], // #23: U+0078 'x' LATIN SMALL LETTER X
  <int>[0x0030, 0x0020, 0x0035, 0x0032], // #24: U+0031 '1' DIGIT ONE
  <int>[0x0075, 0x006F, 0x0061, 0x0065], // #25: U+006A 'j' LATIN SMALL LETTER J
  <int>[0x0020, 0x0030, 0x0036, 0x0064], // #26: U+0033 '3' DIGIT THREE
  <int>[0x0020, 0x0032, 0x0035, 0x0030], // #27: U+0032 '2' DIGIT TWO
  <int>[0x0020, 0x006D, 0x0036, 0x0030], // #28: U+0038 '8' DIGIT EIGHT
  <int>[0x0020, 0x0030, 0x0034, 0x0036], // #29: U+0034 '4' DIGIT FOUR
  <int>[0x0065, 0x007A, 0x0079, 0x0069], // #30: U+007A 'z' LATIN SMALL LETTER Z
  <int>[0x0020, 0x0030, 0x0036, 0x0032], // #31: U+0035 '5' DIGIT FIVE
  <int>[0x0075, 0x0020, 0x006D, 0x0074], // #32: U+0071 'q' LATIN SMALL LETTER Q
  <int>[0x0020, 0x0030, 0x0039, 0x0038], // #33: U+0036 '6' DIGIT SIX
  <int>[0x0020, 0x006C, 0x0063, 0x0072], // #34: U+0037 '7' DIGIT SEVEN
  <int>[0x0020, 0x0036, 0x0064, 0x0039], // #35: U+0039 '9' DIGIT NINE
  <int>[0x0020, 0x0030, 0x006D, 0x0039], // #36: U+0030 '0' DIGIT ZERO
];

const Map<int, int> mcotxtEnUppercaseToLowercase = <int, int>{
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
};

final MCOtxtLanguageModel mcotxtModelEn = MCOtxtLanguageModel(
  id: MCOtxtLanguageId.en,
  wireHash: mcotxtEnWireHash,
  primarySymbols: mcotxtEnPrimarySymbols,
  extensionSymbols: mcotxtEnExtensionSymbols,
  startTop4: mcotxtEnStartTop4,
  punctStartTop4: mcotxtEnPunctStartTop4,
  top4: mcotxtEnTop4,
  uppercaseToLowercase: mcotxtEnUppercaseToLowercase,
);

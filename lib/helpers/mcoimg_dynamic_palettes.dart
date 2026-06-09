import 'package:flutter/material.dart';

/// Canonical dynamic palettes for the new LoRa image codec version.
///
/// global512 is still arranged as 8 mathematical banks × 64 colors.
/// The dynamicGlobalN profiles are NOT simple prefixes of global512.
/// Instead, each compact dynamic profile uses a stable index table:
/// profileColorId -> globalIndex.
///
/// This preserves compatibility with the existing fixed master palettes:
/// - dynamicGlobal8Indices maps to the exact colors of existing master8.
/// - dynamicGlobal16Indices maps to the exact colors of existing master16.
/// - dynamicGlobal32Indices maps to the exact colors of existing master32.
/// - dynamicGlobal64Indices maps to the exact colors of existing master64.
class DynamicPalettes {
  /// 512-color dynamic palette.
  ///
  /// Layout is 8 banks × 64 colors by index math only:
  /// bankIndex = globalIndex >> 6
  /// offset = globalIndex & 0x3F
  ///
  /// Semantic bank names below are comments only; the codec must not rely on them.
  static const List<Color> global512 = [
    // Bank 0: grayscale, indices 0..63
    Color.fromARGB(255, 255, 255, 255), // 000 bank 0 offset 00
    Color.fromARGB(255, 251, 251, 251), // 001 bank 0 offset 01
    Color.fromARGB(255, 247, 247, 247), // 002 bank 0 offset 02
    Color.fromARGB(255, 242, 242, 242), // 003 bank 0 offset 03
    Color.fromARGB(255, 238, 238, 238), // 004 bank 0 offset 04
    Color.fromARGB(255, 234, 234, 234), // 005 bank 0 offset 05
    Color.fromARGB(255, 230, 230, 230), // 006 bank 0 offset 06
    Color.fromARGB(255, 225, 225, 225), // 007 bank 0 offset 07
    Color.fromARGB(255, 221, 221, 221), // 008 bank 0 offset 08
    Color.fromARGB(255, 217, 217, 217), // 009 bank 0 offset 09
    Color.fromARGB(255, 213, 213, 213), // 010 bank 0 offset 10
    Color.fromARGB(255, 209, 209, 209), // 011 bank 0 offset 11
    Color.fromARGB(255, 204, 204, 204), // 012 bank 0 offset 12
    Color.fromARGB(255, 200, 200, 200), // 013 bank 0 offset 13
    Color.fromARGB(255, 196, 196, 196), // 014 bank 0 offset 14
    Color.fromARGB(255, 192, 192, 192), // 015 bank 0 offset 15
    Color.fromARGB(255, 187, 187, 187), // 016 bank 0 offset 16
    Color.fromARGB(255, 183, 183, 183), // 017 bank 0 offset 17
    Color.fromARGB(255, 179, 179, 179), // 018 bank 0 offset 18
    Color.fromARGB(255, 174, 175, 174), // 019 bank 0 offset 19
    Color.fromARGB(255, 170, 170, 170), // 020 bank 0 offset 20
    Color.fromARGB(255, 164, 164, 164), // 021 bank 0 offset 21
    Color.fromARGB(255, 161, 161, 161), // 022 bank 0 offset 22
    Color.fromARGB(255, 156, 157, 156), // 023 bank 0 offset 23
    Color.fromARGB(255, 152, 152, 152), // 024 bank 0 offset 24
    Color.fromARGB(255, 147, 148, 147), // 025 bank 0 offset 25
    Color.fromARGB(255, 141, 141, 141), // 026 bank 0 offset 26
    Color.fromARGB(255, 138, 139, 138), // 027 bank 0 offset 27
    Color.fromARGB(255, 135, 136, 135), // 028 bank 0 offset 28
    Color.fromARGB(255, 132, 133, 132), // 029 bank 0 offset 29
    Color.fromARGB(255, 129, 130, 129), // 030 bank 0 offset 30
    Color.fromARGB(255, 126, 127, 126), // 031 bank 0 offset 31
    Color.fromARGB(255, 123, 123, 123), // 032 bank 0 offset 32
    Color.fromARGB(255, 120, 120, 120), // 033 bank 0 offset 33
    Color.fromARGB(255, 117, 117, 117), // 034 bank 0 offset 34
    Color.fromARGB(255, 114, 114, 114), // 035 bank 0 offset 35
    Color.fromARGB(255, 111, 111, 111), // 036 bank 0 offset 36
    Color.fromARGB(255, 107, 107, 107), // 037 bank 0 offset 37
    Color.fromARGB(255, 102, 102, 102), // 038 bank 0 offset 38
    Color.fromARGB(255, 100, 100, 100), // 039 bank 0 offset 39
    Color.fromARGB(255, 97, 97, 97), // 040 bank 0 offset 40
    Color.fromARGB(255, 93, 93, 93), // 041 bank 0 offset 41
    Color.fromARGB(255, 90, 90, 90), // 042 bank 0 offset 42
    Color.fromARGB(255, 86, 86, 86), // 043 bank 0 offset 43
    Color.fromARGB(255, 83, 83, 83), // 044 bank 0 offset 44
    Color.fromARGB(255, 79, 79, 79), // 045 bank 0 offset 45
    Color.fromARGB(255, 74, 74, 74), // 046 bank 0 offset 46
    Color.fromARGB(255, 69, 69, 69), // 047 bank 0 offset 47
    Color.fromARGB(255, 65, 65, 65), // 048 bank 0 offset 48
    Color.fromARGB(255, 60, 60, 60), // 049 bank 0 offset 49
    Color.fromARGB(255, 55, 55, 55), // 050 bank 0 offset 50
    Color.fromARGB(255, 50, 50, 50), // 051 bank 0 offset 51
    Color.fromARGB(255, 46, 46, 46), // 052 bank 0 offset 52
    Color.fromARGB(255, 41, 41, 41), // 053 bank 0 offset 53
    Color.fromARGB(255, 36, 36, 36), // 054 bank 0 offset 54
    Color.fromARGB(255, 32, 32, 32), // 055 bank 0 offset 55
    Color.fromARGB(255, 28, 28, 28), // 056 bank 0 offset 56
    Color.fromARGB(255, 24, 24, 24), // 057 bank 0 offset 57
    Color.fromARGB(255, 20, 20, 20), // 058 bank 0 offset 58
    Color.fromARGB(255, 16, 16, 16), // 059 bank 0 offset 59
    Color.fromARGB(255, 12, 12, 12), // 060 bank 0 offset 60
    Color.fromARGB(255, 8, 8, 8), // 061 bank 0 offset 61
    Color.fromARGB(255, 4, 4, 4), // 062 bank 0 offset 62
    Color.fromARGB(255, 0, 0, 0), // 063 bank 0 offset 63
    // Bank 1: red, indices 64..127
    Color.fromARGB(255, 255, 176, 163), // 064 bank 1 offset 00
    Color.fromARGB(255, 255, 174, 160), // 065 bank 1 offset 01
    Color.fromARGB(255, 255, 171, 157), // 066 bank 1 offset 02
    Color.fromARGB(255, 255, 169, 154), // 067 bank 1 offset 03
    Color.fromARGB(255, 255, 166, 151), // 068 bank 1 offset 04
    Color.fromARGB(255, 255, 164, 149), // 069 bank 1 offset 05
    Color.fromARGB(255, 255, 161, 146), // 070 bank 1 offset 06
    Color.fromARGB(255, 255, 159, 143), // 071 bank 1 offset 07
    Color.fromARGB(255, 255, 156, 140), // 072 bank 1 offset 08
    Color.fromARGB(255, 255, 154, 137), // 073 bank 1 offset 09
    Color.fromARGB(255, 255, 146, 129), // 074 bank 1 offset 10
    Color.fromARGB(255, 255, 139, 121), // 075 bank 1 offset 11
    Color.fromARGB(255, 255, 131, 113), // 076 bank 1 offset 12
    Color.fromARGB(255, 255, 123, 105), // 077 bank 1 offset 13
    Color.fromARGB(255, 255, 116, 97), // 078 bank 1 offset 14
    Color.fromARGB(255, 255, 108, 89), // 079 bank 1 offset 15
    Color.fromARGB(255, 255, 100, 81), // 080 bank 1 offset 16
    Color.fromARGB(255, 255, 93, 73), // 081 bank 1 offset 17
    Color.fromARGB(255, 255, 85, 65), // 082 bank 1 offset 18
    Color.fromARGB(255, 255, 80, 58), // 083 bank 1 offset 19
    Color.fromARGB(255, 255, 74, 51), // 084 bank 1 offset 20
    Color.fromARGB(255, 255, 69, 43), // 085 bank 1 offset 21
    Color.fromARGB(255, 255, 63, 36), // 086 bank 1 offset 22
    Color.fromARGB(255, 254, 58, 29), // 087 bank 1 offset 23
    Color.fromARGB(255, 254, 52, 22), // 088 bank 1 offset 24
    Color.fromARGB(255, 254, 47, 14), // 089 bank 1 offset 25
    Color.fromARGB(255, 254, 41, 7), // 090 bank 1 offset 26
    Color.fromARGB(255, 254, 36, 0), // 091 bank 1 offset 27
    Color.fromARGB(255, 249, 35, 0), // 092 bank 1 offset 28
    Color.fromARGB(255, 244, 35, 0), // 093 bank 1 offset 29
    Color.fromARGB(255, 239, 34, 0), // 094 bank 1 offset 30
    Color.fromARGB(255, 234, 33, 0), // 095 bank 1 offset 31
    Color.fromARGB(255, 229, 33, 1), // 096 bank 1 offset 32
    Color.fromARGB(255, 224, 32, 1), // 097 bank 1 offset 33
    Color.fromARGB(255, 219, 31, 1), // 098 bank 1 offset 34
    Color.fromARGB(255, 214, 31, 1), // 099 bank 1 offset 35
    Color.fromARGB(255, 209, 30, 1), // 100 bank 1 offset 36
    Color.fromARGB(255, 202, 29, 1), // 101 bank 1 offset 37
    Color.fromARGB(255, 195, 28, 1), // 102 bank 1 offset 38
    Color.fromARGB(255, 188, 27, 1), // 103 bank 1 offset 39
    Color.fromARGB(255, 181, 26, 1), // 104 bank 1 offset 40
    Color.fromARGB(255, 173, 25, 0), // 105 bank 1 offset 41
    Color.fromARGB(255, 166, 24, 0), // 106 bank 1 offset 42
    Color.fromARGB(255, 159, 23, 0), // 107 bank 1 offset 43
    Color.fromARGB(255, 152, 22, 0), // 108 bank 1 offset 44
    Color.fromARGB(255, 145, 21, 0), // 109 bank 1 offset 45
    Color.fromARGB(255, 140, 20, 0), // 110 bank 1 offset 46
    Color.fromARGB(255, 135, 19, 0), // 111 bank 1 offset 47
    Color.fromARGB(255, 129, 19, 0), // 112 bank 1 offset 48
    Color.fromARGB(255, 124, 18, 0), // 113 bank 1 offset 49
    Color.fromARGB(255, 119, 17, 1), // 114 bank 1 offset 50
    Color.fromARGB(255, 114, 16, 1), // 115 bank 1 offset 51
    Color.fromARGB(255, 108, 16, 1), // 116 bank 1 offset 52
    Color.fromARGB(255, 103, 15, 1), // 117 bank 1 offset 53
    Color.fromARGB(255, 98, 14, 1), // 118 bank 1 offset 54
    Color.fromARGB(255, 95, 14, 1), // 119 bank 1 offset 55
    Color.fromARGB(255, 92, 13, 1), // 120 bank 1 offset 56
    Color.fromARGB(255, 88, 13, 1), // 121 bank 1 offset 57
    Color.fromARGB(255, 85, 12, 1), // 122 bank 1 offset 58
    Color.fromARGB(255, 82, 12, 0), // 123 bank 1 offset 59
    Color.fromARGB(255, 79, 11, 0), // 124 bank 1 offset 60
    Color.fromARGB(255, 75, 11, 0), // 125 bank 1 offset 61
    Color.fromARGB(255, 72, 10, 0), // 126 bank 1 offset 62
    Color.fromARGB(255, 69, 10, 0), // 127 bank 1 offset 63
    // Bank 2: orange, indices 128..191
    Color.fromARGB(255, 255, 179, 99), // 128 bank 2 offset 00
    Color.fromARGB(255, 255, 178, 97), // 129 bank 2 offset 01
    Color.fromARGB(255, 255, 177, 96), // 130 bank 2 offset 02
    Color.fromARGB(255, 255, 175, 94), // 131 bank 2 offset 03
    Color.fromARGB(255, 255, 174, 93), // 132 bank 2 offset 04
    Color.fromARGB(255, 255, 173, 91), // 133 bank 2 offset 05
    Color.fromARGB(255, 255, 172, 90), // 134 bank 2 offset 06
    Color.fromARGB(255, 255, 170, 88), // 135 bank 2 offset 07
    Color.fromARGB(255, 255, 169, 87), // 136 bank 2 offset 08
    Color.fromARGB(255, 255, 168, 85), // 137 bank 2 offset 09
    Color.fromARGB(255, 255, 166, 81), // 138 bank 2 offset 10
    Color.fromARGB(255, 255, 163, 77), // 139 bank 2 offset 11
    Color.fromARGB(255, 255, 161, 74), // 140 bank 2 offset 12
    Color.fromARGB(255, 255, 159, 70), // 141 bank 2 offset 13
    Color.fromARGB(255, 255, 156, 66), // 142 bank 2 offset 14
    Color.fromARGB(255, 255, 154, 62), // 143 bank 2 offset 15
    Color.fromARGB(255, 255, 152, 59), // 144 bank 2 offset 16
    Color.fromARGB(255, 255, 149, 55), // 145 bank 2 offset 17
    Color.fromARGB(255, 255, 147, 51), // 146 bank 2 offset 18
    Color.fromARGB(255, 255, 145, 45), // 147 bank 2 offset 19
    Color.fromARGB(255, 255, 144, 40), // 148 bank 2 offset 20
    Color.fromARGB(255, 255, 142, 34), // 149 bank 2 offset 21
    Color.fromARGB(255, 255, 140, 28), // 150 bank 2 offset 22
    Color.fromARGB(255, 255, 139, 23), // 151 bank 2 offset 23
    Color.fromARGB(255, 255, 137, 17), // 152 bank 2 offset 24
    Color.fromARGB(255, 255, 135, 11), // 153 bank 2 offset 25
    Color.fromARGB(255, 255, 134, 6), // 154 bank 2 offset 26
    Color.fromARGB(255, 255, 132, 0), // 155 bank 2 offset 27
    Color.fromARGB(255, 252, 130, 0), // 156 bank 2 offset 28
    Color.fromARGB(255, 249, 129, 0), // 157 bank 2 offset 29
    Color.fromARGB(255, 246, 127, 0), // 158 bank 2 offset 30
    Color.fromARGB(255, 243, 126, 0), // 159 bank 2 offset 31
    Color.fromARGB(255, 240, 124, 1), // 160 bank 2 offset 32
    Color.fromARGB(255, 237, 123, 1), // 161 bank 2 offset 33
    Color.fromARGB(255, 234, 121, 1), // 162 bank 2 offset 34
    Color.fromARGB(255, 231, 120, 1), // 163 bank 2 offset 35
    Color.fromARGB(255, 228, 118, 1), // 164 bank 2 offset 36
    Color.fromARGB(255, 225, 116, 1), // 165 bank 2 offset 37
    Color.fromARGB(255, 221, 114, 1), // 166 bank 2 offset 38
    Color.fromARGB(255, 218, 113, 1), // 167 bank 2 offset 39
    Color.fromARGB(255, 214, 111, 1), // 168 bank 2 offset 40
    Color.fromARGB(255, 211, 109, 1), // 169 bank 2 offset 41
    Color.fromARGB(255, 207, 107, 1), // 170 bank 2 offset 42
    Color.fromARGB(255, 204, 106, 1), // 171 bank 2 offset 43
    Color.fromARGB(255, 200, 104, 1), // 172 bank 2 offset 44
    Color.fromARGB(255, 197, 102, 1), // 173 bank 2 offset 45
    Color.fromARGB(255, 191, 99, 1), // 174 bank 2 offset 46
    Color.fromARGB(255, 185, 96, 1), // 175 bank 2 offset 47
    Color.fromARGB(255, 179, 92, 1), // 176 bank 2 offset 48
    Color.fromARGB(255, 173, 89, 1), // 177 bank 2 offset 49
    Color.fromARGB(255, 166, 86, 0), // 178 bank 2 offset 50
    Color.fromARGB(255, 160, 83, 0), // 179 bank 2 offset 51
    Color.fromARGB(255, 154, 79, 0), // 180 bank 2 offset 52
    Color.fromARGB(255, 148, 76, 0), // 181 bank 2 offset 53
    Color.fromARGB(255, 142, 73, 0), // 182 bank 2 offset 54
    Color.fromARGB(255, 140, 72, 0), // 183 bank 2 offset 55
    Color.fromARGB(255, 138, 71, 0), // 184 bank 2 offset 56
    Color.fromARGB(255, 136, 70, 0), // 185 bank 2 offset 57
    Color.fromARGB(255, 134, 69, 0), // 186 bank 2 offset 58
    Color.fromARGB(255, 131, 68, 0), // 187 bank 2 offset 59
    Color.fromARGB(255, 129, 67, 0), // 188 bank 2 offset 60
    Color.fromARGB(255, 127, 66, 0), // 189 bank 2 offset 61
    Color.fromARGB(255, 125, 65, 0), // 190 bank 2 offset 62
    Color.fromARGB(255, 123, 64, 0), // 191 bank 2 offset 63
    // Bank 3: yellow, indices 192..255
    Color.fromARGB(255, 247, 229, 114), // 192 bank 3 offset 00
    Color.fromARGB(255, 247, 228, 111), // 193 bank 3 offset 01
    Color.fromARGB(255, 247, 227, 109), // 194 bank 3 offset 02
    Color.fromARGB(255, 246, 227, 106), // 195 bank 3 offset 03
    Color.fromARGB(255, 246, 226, 104), // 196 bank 3 offset 04
    Color.fromARGB(255, 246, 225, 101), // 197 bank 3 offset 05
    Color.fromARGB(255, 246, 224, 99), // 198 bank 3 offset 06
    Color.fromARGB(255, 245, 224, 96), // 199 bank 3 offset 07
    Color.fromARGB(255, 245, 223, 94), // 200 bank 3 offset 08
    Color.fromARGB(255, 245, 222, 91), // 201 bank 3 offset 09
    Color.fromARGB(255, 245, 221, 81), // 202 bank 3 offset 10
    Color.fromARGB(255, 244, 219, 71), // 203 bank 3 offset 11
    Color.fromARGB(255, 244, 218, 61), // 204 bank 3 offset 12
    Color.fromARGB(255, 243, 216, 51), // 205 bank 3 offset 13
    Color.fromARGB(255, 243, 215, 40), // 206 bank 3 offset 14
    Color.fromARGB(255, 242, 213, 30), // 207 bank 3 offset 15
    Color.fromARGB(255, 242, 212, 20), // 208 bank 3 offset 16
    Color.fromARGB(255, 241, 210, 10), // 209 bank 3 offset 17
    Color.fromARGB(255, 241, 209, 0), // 210 bank 3 offset 18
    Color.fromARGB(255, 239, 207, 0), // 211 bank 3 offset 19
    Color.fromARGB(255, 237, 205, 0), // 212 bank 3 offset 20
    Color.fromARGB(255, 235, 204, 1), // 213 bank 3 offset 21
    Color.fromARGB(255, 233, 202, 1), // 214 bank 3 offset 22
    Color.fromARGB(255, 231, 200, 1), // 215 bank 3 offset 23
    Color.fromARGB(255, 229, 198, 1), // 216 bank 3 offset 24
    Color.fromARGB(255, 227, 197, 2), // 217 bank 3 offset 25
    Color.fromARGB(255, 225, 195, 2), // 218 bank 3 offset 26
    Color.fromARGB(255, 223, 193, 2), // 219 bank 3 offset 27
    Color.fromARGB(255, 221, 191, 2), // 220 bank 3 offset 28
    Color.fromARGB(255, 219, 189, 2), // 221 bank 3 offset 29
    Color.fromARGB(255, 216, 188, 2), // 222 bank 3 offset 30
    Color.fromARGB(255, 214, 186, 2), // 223 bank 3 offset 31
    Color.fromARGB(255, 212, 184, 1), // 224 bank 3 offset 32
    Color.fromARGB(255, 210, 182, 1), // 225 bank 3 offset 33
    Color.fromARGB(255, 207, 181, 1), // 226 bank 3 offset 34
    Color.fromARGB(255, 205, 179, 1), // 227 bank 3 offset 35
    Color.fromARGB(255, 203, 177, 1), // 228 bank 3 offset 36
    Color.fromARGB(255, 201, 175, 1), // 229 bank 3 offset 37
    Color.fromARGB(255, 198, 173, 1), // 230 bank 3 offset 38
    Color.fromARGB(255, 196, 170, 1), // 231 bank 3 offset 39
    Color.fromARGB(255, 193, 168, 1), // 232 bank 3 offset 40
    Color.fromARGB(255, 191, 166, 2), // 233 bank 3 offset 41
    Color.fromARGB(255, 188, 164, 2), // 234 bank 3 offset 42
    Color.fromARGB(255, 186, 161, 2), // 235 bank 3 offset 43
    Color.fromARGB(255, 183, 159, 2), // 236 bank 3 offset 44
    Color.fromARGB(255, 181, 157, 2), // 237 bank 3 offset 45
    Color.fromARGB(255, 177, 153, 2), // 238 bank 3 offset 46
    Color.fromARGB(255, 173, 150, 2), // 239 bank 3 offset 47
    Color.fromARGB(255, 169, 146, 2), // 240 bank 3 offset 48
    Color.fromARGB(255, 165, 142, 2), // 241 bank 3 offset 49
    Color.fromARGB(255, 160, 139, 2), // 242 bank 3 offset 50
    Color.fromARGB(255, 156, 135, 2), // 243 bank 3 offset 51
    Color.fromARGB(255, 152, 131, 2), // 244 bank 3 offset 52
    Color.fromARGB(255, 148, 128, 2), // 245 bank 3 offset 53
    Color.fromARGB(255, 144, 124, 2), // 246 bank 3 offset 54
    Color.fromARGB(255, 141, 122, 2), // 247 bank 3 offset 55
    Color.fromARGB(255, 139, 120, 2), // 248 bank 3 offset 56
    Color.fromARGB(255, 136, 118, 2), // 249 bank 3 offset 57
    Color.fromARGB(255, 133, 116, 2), // 250 bank 3 offset 58
    Color.fromARGB(255, 131, 113, 2), // 251 bank 3 offset 59
    Color.fromARGB(255, 128, 111, 2), // 252 bank 3 offset 60
    Color.fromARGB(255, 125, 109, 2), // 253 bank 3 offset 61
    Color.fromARGB(255, 123, 107, 2), // 254 bank 3 offset 62
    Color.fromARGB(255, 120, 105, 2), // 255 bank 3 offset 63
    // Bank 4: green, indices 256..319
    Color.fromARGB(255, 183, 230, 155), // 256 bank 4 offset 00
    Color.fromARGB(255, 179, 229, 151), // 257 bank 4 offset 01
    Color.fromARGB(255, 175, 227, 147), // 258 bank 4 offset 02
    Color.fromARGB(255, 172, 226, 143), // 259 bank 4 offset 03
    Color.fromARGB(255, 168, 225, 139), // 260 bank 4 offset 04
    Color.fromARGB(255, 164, 223, 134), // 261 bank 4 offset 05
    Color.fromARGB(255, 160, 222, 130), // 262 bank 4 offset 06
    Color.fromARGB(255, 157, 221, 126), // 263 bank 4 offset 07
    Color.fromARGB(255, 153, 219, 122), // 264 bank 4 offset 08
    Color.fromARGB(255, 149, 218, 118), // 265 bank 4 offset 09
    Color.fromARGB(255, 145, 217, 113), // 266 bank 4 offset 10
    Color.fromARGB(255, 140, 215, 108), // 267 bank 4 offset 11
    Color.fromARGB(255, 136, 214, 104), // 268 bank 4 offset 12
    Color.fromARGB(255, 131, 212, 99), // 269 bank 4 offset 13
    Color.fromARGB(255, 127, 211, 94), // 270 bank 4 offset 14
    Color.fromARGB(255, 122, 209, 89), // 271 bank 4 offset 15
    Color.fromARGB(255, 118, 208, 85), // 272 bank 4 offset 16
    Color.fromARGB(255, 113, 206, 80), // 273 bank 4 offset 17
    Color.fromARGB(255, 109, 205, 75), // 274 bank 4 offset 18
    Color.fromARGB(255, 105, 204, 67), // 275 bank 4 offset 19
    Color.fromARGB(255, 101, 202, 58), // 276 bank 4 offset 20
    Color.fromARGB(255, 96, 201, 50), // 277 bank 4 offset 21
    Color.fromARGB(255, 92, 199, 42), // 278 bank 4 offset 22
    Color.fromARGB(255, 88, 198, 33), // 279 bank 4 offset 23
    Color.fromARGB(255, 84, 196, 25), // 280 bank 4 offset 24
    Color.fromARGB(255, 79, 195, 17), // 281 bank 4 offset 25
    Color.fromARGB(255, 75, 193, 8), // 282 bank 4 offset 26
    Color.fromARGB(255, 71, 192, 0), // 283 bank 4 offset 27
    Color.fromARGB(255, 70, 190, 0), // 284 bank 4 offset 28
    Color.fromARGB(255, 70, 188, 0), // 285 bank 4 offset 29
    Color.fromARGB(255, 69, 187, 0), // 286 bank 4 offset 30
    Color.fromARGB(255, 68, 185, 0), // 287 bank 4 offset 31
    Color.fromARGB(255, 68, 183, 0), // 288 bank 4 offset 32
    Color.fromARGB(255, 67, 181, 0), // 289 bank 4 offset 33
    Color.fromARGB(255, 66, 180, 0), // 290 bank 4 offset 34
    Color.fromARGB(255, 66, 178, 0), // 291 bank 4 offset 35
    Color.fromARGB(255, 65, 176, 0), // 292 bank 4 offset 36
    Color.fromARGB(255, 64, 173, 0), // 293 bank 4 offset 37
    Color.fromARGB(255, 63, 170, 0), // 294 bank 4 offset 38
    Color.fromARGB(255, 61, 167, 0), // 295 bank 4 offset 39
    Color.fromARGB(255, 60, 164, 0), // 296 bank 4 offset 40
    Color.fromARGB(255, 59, 160, 1), // 297 bank 4 offset 41
    Color.fromARGB(255, 58, 157, 1), // 298 bank 4 offset 42
    Color.fromARGB(255, 56, 154, 1), // 299 bank 4 offset 43
    Color.fromARGB(255, 55, 151, 1), // 300 bank 4 offset 44
    Color.fromARGB(255, 54, 148, 1), // 301 bank 4 offset 45
    Color.fromARGB(255, 52, 144, 1), // 302 bank 4 offset 46
    Color.fromARGB(255, 51, 140, 1), // 303 bank 4 offset 47
    Color.fromARGB(255, 49, 135, 1), // 304 bank 4 offset 48
    Color.fromARGB(255, 48, 131, 1), // 305 bank 4 offset 49
    Color.fromARGB(255, 46, 127, 0), // 306 bank 4 offset 50
    Color.fromARGB(255, 45, 123, 0), // 307 bank 4 offset 51
    Color.fromARGB(255, 43, 118, 0), // 308 bank 4 offset 52
    Color.fromARGB(255, 42, 114, 0), // 309 bank 4 offset 53
    Color.fromARGB(255, 40, 110, 0), // 310 bank 4 offset 54
    Color.fromARGB(255, 39, 107, 0), // 311 bank 4 offset 55
    Color.fromARGB(255, 38, 103, 0), // 312 bank 4 offset 56
    Color.fromARGB(255, 36, 100, 0), // 313 bank 4 offset 57
    Color.fromARGB(255, 35, 96, 0), // 314 bank 4 offset 58
    Color.fromARGB(255, 34, 93, 0), // 315 bank 4 offset 59
    Color.fromARGB(255, 33, 89, 0), // 316 bank 4 offset 60
    Color.fromARGB(255, 31, 86, 0), // 317 bank 4 offset 61
    Color.fromARGB(255, 30, 82, 0), // 318 bank 4 offset 62
    Color.fromARGB(255, 29, 79, 0), // 319 bank 4 offset 63
    // Bank 5: cyan, indices 320..383
    Color.fromARGB(255, 196, 241, 255), // 320 bank 5 offset 00
    Color.fromARGB(255, 193, 240, 255), // 321 bank 5 offset 01
    Color.fromARGB(255, 190, 239, 255), // 322 bank 5 offset 02
    Color.fromARGB(255, 188, 238, 255), // 323 bank 5 offset 03
    Color.fromARGB(255, 185, 237, 255), // 324 bank 5 offset 04
    Color.fromARGB(255, 182, 237, 255), // 325 bank 5 offset 05
    Color.fromARGB(255, 179, 236, 255), // 326 bank 5 offset 06
    Color.fromARGB(255, 177, 235, 255), // 327 bank 5 offset 07
    Color.fromARGB(255, 174, 234, 255), // 328 bank 5 offset 08
    Color.fromARGB(255, 171, 233, 255), // 329 bank 5 offset 09
    Color.fromARGB(255, 166, 232, 255), // 330 bank 5 offset 10
    Color.fromARGB(255, 161, 230, 255), // 331 bank 5 offset 11
    Color.fromARGB(255, 156, 229, 255), // 332 bank 5 offset 12
    Color.fromARGB(255, 151, 227, 255), // 333 bank 5 offset 13
    Color.fromARGB(255, 147, 226, 255), // 334 bank 5 offset 14
    Color.fromARGB(255, 142, 224, 255), // 335 bank 5 offset 15
    Color.fromARGB(255, 137, 223, 255), // 336 bank 5 offset 16
    Color.fromARGB(255, 132, 221, 255), // 337 bank 5 offset 17
    Color.fromARGB(255, 127, 220, 255), // 338 bank 5 offset 18
    Color.fromARGB(255, 113, 217, 255), // 339 bank 5 offset 19
    Color.fromARGB(255, 99, 214, 255), // 340 bank 5 offset 20
    Color.fromARGB(255, 85, 212, 255), // 341 bank 5 offset 21
    Color.fromARGB(255, 71, 209, 255), // 342 bank 5 offset 22
    Color.fromARGB(255, 57, 206, 255), // 343 bank 5 offset 23
    Color.fromARGB(255, 43, 203, 255), // 344 bank 5 offset 24
    Color.fromARGB(255, 29, 201, 255), // 345 bank 5 offset 25
    Color.fromARGB(255, 15, 198, 255), // 346 bank 5 offset 26
    Color.fromARGB(255, 1, 195, 255), // 347 bank 5 offset 27
    Color.fromARGB(255, 1, 194, 253), // 348 bank 5 offset 28
    Color.fromARGB(255, 1, 192, 251), // 349 bank 5 offset 29
    Color.fromARGB(255, 1, 191, 249), // 350 bank 5 offset 30
    Color.fromARGB(255, 1, 189, 247), // 351 bank 5 offset 31
    Color.fromARGB(255, 0, 188, 246), // 352 bank 5 offset 32
    Color.fromARGB(255, 0, 186, 244), // 353 bank 5 offset 33
    Color.fromARGB(255, 0, 185, 242), // 354 bank 5 offset 34
    Color.fromARGB(255, 0, 183, 240), // 355 bank 5 offset 35
    Color.fromARGB(255, 0, 182, 238), // 356 bank 5 offset 36
    Color.fromARGB(255, 0, 181, 236), // 357 bank 5 offset 37
    Color.fromARGB(255, 0, 179, 235), // 358 bank 5 offset 38
    Color.fromARGB(255, 0, 178, 233), // 359 bank 5 offset 39
    Color.fromARGB(255, 0, 177, 231), // 360 bank 5 offset 40
    Color.fromARGB(255, 1, 175, 230), // 361 bank 5 offset 41
    Color.fromARGB(255, 1, 174, 228), // 362 bank 5 offset 42
    Color.fromARGB(255, 1, 173, 226), // 363 bank 5 offset 43
    Color.fromARGB(255, 1, 171, 225), // 364 bank 5 offset 44
    Color.fromARGB(255, 1, 170, 223), // 365 bank 5 offset 45
    Color.fromARGB(255, 1, 167, 219), // 366 bank 5 offset 46
    Color.fromARGB(255, 1, 164, 214), // 367 bank 5 offset 47
    Color.fromARGB(255, 2, 160, 210), // 368 bank 5 offset 48
    Color.fromARGB(255, 2, 157, 206), // 369 bank 5 offset 49
    Color.fromARGB(255, 2, 154, 201), // 370 bank 5 offset 50
    Color.fromARGB(255, 2, 151, 197), // 371 bank 5 offset 51
    Color.fromARGB(255, 3, 147, 193), // 372 bank 5 offset 52
    Color.fromARGB(255, 3, 144, 188), // 373 bank 5 offset 53
    Color.fromARGB(255, 3, 141, 184), // 374 bank 5 offset 54
    Color.fromARGB(255, 3, 137, 179), // 375 bank 5 offset 55
    Color.fromARGB(255, 3, 134, 175), // 376 bank 5 offset 56
    Color.fromARGB(255, 2, 130, 170), // 377 bank 5 offset 57
    Color.fromARGB(255, 2, 127, 166), // 378 bank 5 offset 58
    Color.fromARGB(255, 2, 123, 161), // 379 bank 5 offset 59
    Color.fromARGB(255, 2, 120, 157), // 380 bank 5 offset 60
    Color.fromARGB(255, 1, 116, 152), // 381 bank 5 offset 61
    Color.fromARGB(255, 1, 113, 148), // 382 bank 5 offset 62
    Color.fromARGB(255, 1, 109, 143), // 383 bank 5 offset 63
    // Bank 6: blue, indices 384..447
    Color.fromARGB(255, 145, 170, 255), // 384 bank 6 offset 00
    Color.fromARGB(255, 142, 168, 255), // 385 bank 6 offset 01
    Color.fromARGB(255, 139, 166, 255), // 386 bank 6 offset 02
    Color.fromARGB(255, 136, 163, 255), // 387 bank 6 offset 03
    Color.fromARGB(255, 133, 161, 255), // 388 bank 6 offset 04
    Color.fromARGB(255, 129, 159, 255), // 389 bank 6 offset 05
    Color.fromARGB(255, 126, 157, 255), // 390 bank 6 offset 06
    Color.fromARGB(255, 123, 154, 255), // 391 bank 6 offset 07
    Color.fromARGB(255, 120, 152, 255), // 392 bank 6 offset 08
    Color.fromARGB(255, 117, 150, 255), // 393 bank 6 offset 09
    Color.fromARGB(255, 111, 144, 255), // 394 bank 6 offset 10
    Color.fromARGB(255, 104, 139, 255), // 395 bank 6 offset 11
    Color.fromARGB(255, 98, 133, 255), // 396 bank 6 offset 12
    Color.fromARGB(255, 91, 128, 255), // 397 bank 6 offset 13
    Color.fromARGB(255, 85, 122, 255), // 398 bank 6 offset 14
    Color.fromARGB(255, 78, 117, 255), // 399 bank 6 offset 15
    Color.fromARGB(255, 72, 111, 255), // 400 bank 6 offset 16
    Color.fromARGB(255, 61, 105, 255), // 401 bank 6 offset 17
    Color.fromARGB(255, 59, 100, 255), // 402 bank 6 offset 18
    Color.fromARGB(255, 52, 95, 255), // 403 bank 6 offset 19
    Color.fromARGB(255, 46, 91, 255), // 404 bank 6 offset 20
    Color.fromARGB(255, 39, 86, 255), // 405 bank 6 offset 21
    Color.fromARGB(255, 33, 81, 255), // 406 bank 6 offset 22
    Color.fromARGB(255, 26, 77, 255), // 407 bank 6 offset 23
    Color.fromARGB(255, 20, 72, 255), // 408 bank 6 offset 24
    Color.fromARGB(255, 13, 67, 255), // 409 bank 6 offset 25
    Color.fromARGB(255, 7, 63, 255), // 410 bank 6 offset 26
    Color.fromARGB(255, 0, 58, 255), // 411 bank 6 offset 27
    Color.fromARGB(255, 0, 57, 252), // 412 bank 6 offset 28
    Color.fromARGB(255, 0, 56, 248), // 413 bank 6 offset 29
    Color.fromARGB(255, 1, 56, 245), // 414 bank 6 offset 30
    Color.fromARGB(255, 1, 55, 242), // 415 bank 6 offset 31
    Color.fromARGB(255, 1, 54, 238), // 416 bank 6 offset 32
    Color.fromARGB(255, 1, 53, 235), // 417 bank 6 offset 33
    Color.fromARGB(255, 2, 53, 232), // 418 bank 6 offset 34
    Color.fromARGB(255, 2, 52, 228), // 419 bank 6 offset 35
    Color.fromARGB(255, 2, 51, 225), // 420 bank 6 offset 36
    Color.fromARGB(255, 2, 50, 222), // 421 bank 6 offset 37
    Color.fromARGB(255, 2, 50, 220), // 422 bank 6 offset 38
    Color.fromARGB(255, 2, 49, 217), // 423 bank 6 offset 39
    Color.fromARGB(255, 2, 49, 215), // 424 bank 6 offset 40
    Color.fromARGB(255, 2, 48, 212), // 425 bank 6 offset 41
    Color.fromARGB(255, 2, 48, 210), // 426 bank 6 offset 42
    Color.fromARGB(255, 2, 47, 207), // 427 bank 6 offset 43
    Color.fromARGB(255, 2, 47, 205), // 428 bank 6 offset 44
    Color.fromARGB(255, 2, 46, 202), // 429 bank 6 offset 45
    Color.fromARGB(255, 2, 45, 199), // 430 bank 6 offset 46
    Color.fromARGB(255, 2, 45, 196), // 431 bank 6 offset 47
    Color.fromARGB(255, 2, 44, 193), // 432 bank 6 offset 48
    Color.fromARGB(255, 2, 43, 190), // 433 bank 6 offset 49
    Color.fromARGB(255, 1, 43, 188), // 434 bank 6 offset 50
    Color.fromARGB(255, 1, 42, 185), // 435 bank 6 offset 51
    Color.fromARGB(255, 1, 41, 182), // 436 bank 6 offset 52
    Color.fromARGB(255, 1, 41, 179), // 437 bank 6 offset 53
    Color.fromARGB(255, 1, 40, 176), // 438 bank 6 offset 54
    Color.fromARGB(255, 1, 39, 173), // 439 bank 6 offset 55
    Color.fromARGB(255, 1, 39, 170), // 440 bank 6 offset 56
    Color.fromARGB(255, 1, 38, 167), // 441 bank 6 offset 57
    Color.fromARGB(255, 1, 37, 164), // 442 bank 6 offset 58
    Color.fromARGB(255, 0, 37, 162), // 443 bank 6 offset 59
    Color.fromARGB(255, 0, 36, 159), // 444 bank 6 offset 60
    Color.fromARGB(255, 0, 35, 156), // 445 bank 6 offset 61
    Color.fromARGB(255, 0, 35, 153), // 446 bank 6 offset 62
    Color.fromARGB(255, 0, 34, 150), // 447 bank 6 offset 63
    // Bank 7: violet, indices 448..511
    Color.fromARGB(255, 215, 178, 255), // 448 bank 7 offset 00
    Color.fromARGB(255, 211, 173, 255), // 449 bank 7 offset 01
    Color.fromARGB(255, 207, 168, 255), // 450 bank 7 offset 02
    Color.fromARGB(255, 203, 164, 255), // 451 bank 7 offset 03
    Color.fromARGB(255, 199, 159, 255), // 452 bank 7 offset 04
    Color.fromARGB(255, 194, 154, 255), // 453 bank 7 offset 05
    Color.fromARGB(255, 190, 149, 255), // 454 bank 7 offset 06
    Color.fromARGB(255, 186, 145, 255), // 455 bank 7 offset 07
    Color.fromARGB(255, 182, 140, 255), // 456 bank 7 offset 08
    Color.fromARGB(255, 178, 135, 255), // 457 bank 7 offset 09
    Color.fromARGB(255, 175, 131, 255), // 458 bank 7 offset 10
    Color.fromARGB(255, 173, 127, 255), // 459 bank 7 offset 11
    Color.fromARGB(255, 170, 124, 255), // 460 bank 7 offset 12
    Color.fromARGB(255, 167, 120, 255), // 461 bank 7 offset 13
    Color.fromARGB(255, 165, 116, 255), // 462 bank 7 offset 14
    Color.fromARGB(255, 162, 112, 255), // 463 bank 7 offset 15
    Color.fromARGB(255, 159, 109, 255), // 464 bank 7 offset 16
    Color.fromARGB(255, 157, 105, 255), // 465 bank 7 offset 17
    Color.fromARGB(255, 154, 101, 255), // 466 bank 7 offset 18
    Color.fromARGB(255, 152, 97, 255), // 467 bank 7 offset 19
    Color.fromARGB(255, 149, 92, 255), // 468 bank 7 offset 20
    Color.fromARGB(255, 147, 88, 255), // 469 bank 7 offset 21
    Color.fromARGB(255, 145, 83, 255), // 470 bank 7 offset 22
    Color.fromARGB(255, 142, 79, 255), // 471 bank 7 offset 23
    Color.fromARGB(255, 140, 74, 255), // 472 bank 7 offset 24
    Color.fromARGB(255, 138, 70, 255), // 473 bank 7 offset 25
    Color.fromARGB(255, 135, 65, 255), // 474 bank 7 offset 26
    Color.fromARGB(255, 133, 61, 255), // 475 bank 7 offset 27
    Color.fromARGB(255, 132, 54, 255), // 476 bank 7 offset 28
    Color.fromARGB(255, 130, 47, 255), // 477 bank 7 offset 29
    Color.fromARGB(255, 129, 41, 255), // 478 bank 7 offset 30
    Color.fromARGB(255, 128, 34, 255), // 479 bank 7 offset 31
    Color.fromARGB(255, 126, 27, 255), // 480 bank 7 offset 32
    Color.fromARGB(255, 125, 20, 255), // 481 bank 7 offset 33
    Color.fromARGB(255, 124, 14, 255), // 482 bank 7 offset 34
    Color.fromARGB(255, 122, 7, 255), // 483 bank 7 offset 35
    Color.fromARGB(255, 121, 0, 255), // 484 bank 7 offset 36
    Color.fromARGB(255, 119, 0, 251), // 485 bank 7 offset 37
    Color.fromARGB(255, 117, 0, 247), // 486 bank 7 offset 38
    Color.fromARGB(255, 116, 1, 244), // 487 bank 7 offset 39
    Color.fromARGB(255, 114, 1, 240), // 488 bank 7 offset 40
    Color.fromARGB(255, 112, 1, 236), // 489 bank 7 offset 41
    Color.fromARGB(255, 110, 1, 232), // 490 bank 7 offset 42
    Color.fromARGB(255, 109, 2, 229), // 491 bank 7 offset 43
    Color.fromARGB(255, 106, 0, 227), // 492 bank 7 offset 44
    Color.fromARGB(255, 105, 2, 221), // 493 bank 7 offset 45
    Color.fromARGB(255, 103, 2, 216), // 494 bank 7 offset 46
    Color.fromARGB(255, 100, 2, 211), // 495 bank 7 offset 47
    Color.fromARGB(255, 98, 2, 206), // 496 bank 7 offset 48
    Color.fromARGB(255, 95, 2, 201), // 497 bank 7 offset 49
    Color.fromARGB(255, 93, 1, 195), // 498 bank 7 offset 50
    Color.fromARGB(255, 90, 1, 190), // 499 bank 7 offset 51
    Color.fromARGB(255, 88, 1, 185), // 500 bank 7 offset 52
    Color.fromARGB(255, 85, 1, 180), // 501 bank 7 offset 53
    Color.fromARGB(255, 83, 1, 175), // 502 bank 7 offset 54
    Color.fromARGB(255, 79, 1, 167), // 503 bank 7 offset 55
    Color.fromARGB(255, 75, 1, 158), // 504 bank 7 offset 56
    Color.fromARGB(255, 71, 1, 150), // 505 bank 7 offset 57
    Color.fromARGB(255, 67, 1, 142), // 506 bank 7 offset 58
    Color.fromARGB(255, 63, 0, 133), // 507 bank 7 offset 59
    Color.fromARGB(255, 59, 0, 125), // 508 bank 7 offset 60
    Color.fromARGB(255, 55, 0, 117), // 509 bank 7 offset 61
    Color.fromARGB(255, 51, 0, 108), // 510 bank 7 offset 62
    Color.fromARGB(255, 47, 0, 100), // 511 bank 7 offset 63
  ];

  static const List<int> dynamicGlobal8Indices = [
    0,
    26,
    63,
    91,
    210,
    283,
    401,
    484,
  ];

  static const List<int> dynamicGlobal16Indices = [
    0,
    21,
    63,
    100,
    118,
    155,
    191,
    210,
    246,
    292,
    310,
    338,
    411,
    447,
    492,
    511,
  ];

  static const List<int> dynamicGlobal32Indices = [
    0,
    18,
    38,
    63,
    64,
    82,
    91,
    118,
    128,
    155,
    173,
    182,
    201,
    210,
    237,
    255,
    265,
    283,
    310,
    319,
    320,
    347,
    374,
    383,
    393,
    411,
    429,
    447,
    448,
    457,
    475,
    511,
  ];

  static const List<int> dynamicGlobal64Indices = [
    0,
    9,
    18,
    27,
    36,
    45,
    54,
    63,
    64,
    73,
    82,
    91,
    100,
    109,
    118,
    127,
    128,
    137,
    146,
    155,
    164,
    173,
    182,
    191,
    192,
    201,
    210,
    219,
    228,
    237,
    246,
    255,
    256,
    265,
    274,
    283,
    292,
    301,
    310,
    319,
    320,
    329,
    338,
    347,
    356,
    365,
    374,
    383,
    384,
    393,
    402,
    411,
    420,
    429,
    438,
    447,
    448,
    457,
    466,
    475,
    484,
    493,
    502,
    511,
  ];

  static const List<int> dynamicGlobal128Indices = [
    0,
    9,
    18,
    27,
    36,
    45,
    54,
    63,
    64,
    73,
    82,
    91,
    100,
    109,
    118,
    127,
    128,
    137,
    146,
    155,
    164,
    173,
    182,
    191,
    192,
    201,
    210,
    219,
    228,
    237,
    246,
    255,
    256,
    265,
    274,
    283,
    292,
    301,
    310,
    319,
    320,
    329,
    338,
    347,
    356,
    365,
    374,
    383,
    384,
    393,
    402,
    411,
    420,
    429,
    438,
    447,
    448,
    457,
    466,
    475,
    484,
    493,
    502,
    511,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    37,
    38,
    39,
    40,
    41,
    42,
    43,
    44,
    46,
    47,
    48,
    49,
    50,
    51,
    52,
    53,
    55,
    56,
    57,
    58,
    59,
    60,
    61,
    62,
    65,
    66,
    67,
    68,
    69,
    70,
    71,
    72,
  ];

  static const List<int> dynamicGlobal256Indices = [
    0,
    9,
    18,
    27,
    36,
    45,
    54,
    63,
    64,
    73,
    82,
    91,
    100,
    109,
    118,
    127,
    128,
    137,
    146,
    155,
    164,
    173,
    182,
    191,
    192,
    201,
    210,
    219,
    228,
    237,
    246,
    255,
    256,
    265,
    274,
    283,
    292,
    301,
    310,
    319,
    320,
    329,
    338,
    347,
    356,
    365,
    374,
    383,
    384,
    393,
    402,
    411,
    420,
    429,
    438,
    447,
    448,
    457,
    466,
    475,
    484,
    493,
    502,
    511,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    37,
    38,
    39,
    40,
    41,
    42,
    43,
    44,
    46,
    47,
    48,
    49,
    50,
    51,
    52,
    53,
    55,
    56,
    57,
    58,
    59,
    60,
    61,
    62,
    65,
    66,
    67,
    68,
    69,
    70,
    71,
    72,
    74,
    75,
    76,
    77,
    78,
    79,
    80,
    81,
    83,
    84,
    85,
    86,
    87,
    88,
    89,
    90,
    92,
    93,
    94,
    95,
    96,
    97,
    98,
    99,
    101,
    102,
    103,
    104,
    105,
    106,
    107,
    108,
    110,
    111,
    112,
    113,
    114,
    115,
    116,
    117,
    119,
    120,
    121,
    122,
    123,
    124,
    125,
    126,
    129,
    130,
    131,
    132,
    133,
    134,
    135,
    136,
    138,
    139,
    140,
    141,
    142,
    143,
    144,
    145,
    147,
    148,
    149,
    150,
    151,
    152,
    153,
    154,
    156,
    157,
    158,
    159,
    160,
    161,
    162,
    163,
    165,
    166,
    167,
    168,
    169,
    170,
    171,
    172,
    174,
    175,
    176,
    177,
    178,
    179,
    180,
    181,
    183,
    184,
    185,
    186,
    187,
    188,
    189,
    190,
    193,
    194,
    195,
    196,
    197,
    198,
    199,
    200,
    202,
    203,
    204,
    205,
    206,
    207,
    208,
    209,
    211,
    212,
    213,
    214,
    215,
    216,
    217,
    218,
  ];

  /// dynamicGlobal512 is identity: profileColorId == globalIndex.
  /// Avoid materializing this table in hot paths unless the UI needs it.
  static const List<int> dynamicGlobal512Indices = [
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
    38,
    39,
    40,
    41,
    42,
    43,
    44,
    45,
    46,
    47,
    48,
    49,
    50,
    51,
    52,
    53,
    54,
    55,
    56,
    57,
    58,
    59,
    60,
    61,
    62,
    63,
    64,
    65,
    66,
    67,
    68,
    69,
    70,
    71,
    72,
    73,
    74,
    75,
    76,
    77,
    78,
    79,
    80,
    81,
    82,
    83,
    84,
    85,
    86,
    87,
    88,
    89,
    90,
    91,
    92,
    93,
    94,
    95,
    96,
    97,
    98,
    99,
    100,
    101,
    102,
    103,
    104,
    105,
    106,
    107,
    108,
    109,
    110,
    111,
    112,
    113,
    114,
    115,
    116,
    117,
    118,
    119,
    120,
    121,
    122,
    123,
    124,
    125,
    126,
    127,
    128,
    129,
    130,
    131,
    132,
    133,
    134,
    135,
    136,
    137,
    138,
    139,
    140,
    141,
    142,
    143,
    144,
    145,
    146,
    147,
    148,
    149,
    150,
    151,
    152,
    153,
    154,
    155,
    156,
    157,
    158,
    159,
    160,
    161,
    162,
    163,
    164,
    165,
    166,
    167,
    168,
    169,
    170,
    171,
    172,
    173,
    174,
    175,
    176,
    177,
    178,
    179,
    180,
    181,
    182,
    183,
    184,
    185,
    186,
    187,
    188,
    189,
    190,
    191,
    192,
    193,
    194,
    195,
    196,
    197,
    198,
    199,
    200,
    201,
    202,
    203,
    204,
    205,
    206,
    207,
    208,
    209,
    210,
    211,
    212,
    213,
    214,
    215,
    216,
    217,
    218,
    219,
    220,
    221,
    222,
    223,
    224,
    225,
    226,
    227,
    228,
    229,
    230,
    231,
    232,
    233,
    234,
    235,
    236,
    237,
    238,
    239,
    240,
    241,
    242,
    243,
    244,
    245,
    246,
    247,
    248,
    249,
    250,
    251,
    252,
    253,
    254,
    255,
    256,
    257,
    258,
    259,
    260,
    261,
    262,
    263,
    264,
    265,
    266,
    267,
    268,
    269,
    270,
    271,
    272,
    273,
    274,
    275,
    276,
    277,
    278,
    279,
    280,
    281,
    282,
    283,
    284,
    285,
    286,
    287,
    288,
    289,
    290,
    291,
    292,
    293,
    294,
    295,
    296,
    297,
    298,
    299,
    300,
    301,
    302,
    303,
    304,
    305,
    306,
    307,
    308,
    309,
    310,
    311,
    312,
    313,
    314,
    315,
    316,
    317,
    318,
    319,
    320,
    321,
    322,
    323,
    324,
    325,
    326,
    327,
    328,
    329,
    330,
    331,
    332,
    333,
    334,
    335,
    336,
    337,
    338,
    339,
    340,
    341,
    342,
    343,
    344,
    345,
    346,
    347,
    348,
    349,
    350,
    351,
    352,
    353,
    354,
    355,
    356,
    357,
    358,
    359,
    360,
    361,
    362,
    363,
    364,
    365,
    366,
    367,
    368,
    369,
    370,
    371,
    372,
    373,
    374,
    375,
    376,
    377,
    378,
    379,
    380,
    381,
    382,
    383,
    384,
    385,
    386,
    387,
    388,
    389,
    390,
    391,
    392,
    393,
    394,
    395,
    396,
    397,
    398,
    399,
    400,
    401,
    402,
    403,
    404,
    405,
    406,
    407,
    408,
    409,
    410,
    411,
    412,
    413,
    414,
    415,
    416,
    417,
    418,
    419,
    420,
    421,
    422,
    423,
    424,
    425,
    426,
    427,
    428,
    429,
    430,
    431,
    432,
    433,
    434,
    435,
    436,
    437,
    438,
    439,
    440,
    441,
    442,
    443,
    444,
    445,
    446,
    447,
    448,
    449,
    450,
    451,
    452,
    453,
    454,
    455,
    456,
    457,
    458,
    459,
    460,
    461,
    462,
    463,
    464,
    465,
    466,
    467,
    468,
    469,
    470,
    471,
    472,
    473,
    474,
    475,
    476,
    477,
    478,
    479,
    480,
    481,
    482,
    483,
    484,
    485,
    486,
    487,
    488,
    489,
    490,
    491,
    492,
    493,
    494,
    495,
    496,
    497,
    498,
    499,
    500,
    501,
    502,
    503,
    504,
    505,
    506,
    507,
    508,
    509,
    510,
    511,
  ];

  static Color colorByGlobalIndex(int globalIndex) => global512[globalIndex];

  static List<Color> colorsForDynamicIndices(List<int> indices) =>
      List<Color>.unmodifiable(indices.map((i) => global512[i]));
}

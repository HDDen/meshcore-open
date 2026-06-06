import 'package:flutter/material.dart';

import 'mcoimg_codec.dart';

class MCOImagePalette {
  static const int blackIndex = 0;
  static const int whiteIndex = 1;

  static int blackIndexFor(PaletteProfile profile) {
    return switch (profile) {
      PaletteProfile.mono => 1,
      PaletteProfile.master4 => 3,
      PaletteProfile.master8 => 1,
      PaletteProfile.master16 => 3,
      PaletteProfile.master32 => 3,
      PaletteProfile.master64 => 7,
    };
  }

  static int whiteIndexFor(PaletteProfile profile) {
    return switch (profile) {
      PaletteProfile.mono => 0,
      PaletteProfile.master4 => 0,
      PaletteProfile.master8 => 0,
      PaletteProfile.master16 => 0,
      PaletteProfile.master32 => 0,
      PaletteProfile.master64 => 0,
    };
  }

  static List<Color> colorsFor(PaletteProfile profile) {
    return switch (profile) {
      PaletteProfile.mono => mono,
      PaletteProfile.master4 => master4,
      PaletteProfile.master8 => master8,
      PaletteProfile.master16 => master16,
      PaletteProfile.master32 => master32,
      PaletteProfile.master64 => master64,
    };
  }

  static const List<Color> mono = [Color(0xffffffff), Color(0xff000000)];

  static const List<Color> master4 = [
    Color(0xffffffff),
    Color(0xffc0c0c0),
    Color(0xFF565656),
    Color(0xff000000),
  ];

  static const List<Color> master8 = [
    Color(0xffffffff),
    Color(0xFF8D8D8D),
    Color(0xff000000),
    Color(0xFFFE2400),
    Color(0xFFF1D100),
    Color(0xFF47C000),
    Color(0xFF3D69FF),
    Color(0xFF7900FF),
  ];

  static const List<Color> master16 = [
    // Color(0xffffffff),
    // Color(0xffb8b8b8),
    // Color(0xff5c5c5c),
    // Color(0xff000000),
    // Color(0xFFFB7F7F),
    // Color(0xFFF70929),
    // Color(0xFFFA8108),
    // Color(0xFFFFD000),
    // Color(0xFF68E46C),
    // Color(0xFF005F1E),
    // Color(0xFF27AAD9),
    // Color(0xFF028C9B),
    // Color(0xFF0055FF),
    // Color(0xFF000E7A),
    // Color(0xFFA334ED),
    // Color(0xFF530084),

    Color.fromARGB(255, 255, 255, 255),
    Color.fromARGB(255, 196, 196, 196),
    Color.fromARGB(255, 98, 98, 98),
    Color(0xff000000),

    Color.fromARGB(255, 255, 176, 163),
    Color.fromARGB(255, 254, 36, 0),
    Color.fromARGB(255, 160, 23, 0),
    Color.fromARGB(255, 69, 10, 0),

    Color.fromARGB(255, 255, 179, 99),
    Color.fromARGB(255, 255, 132, 0),
    Color.fromARGB(255, 191, 99, 0),
    Color.fromARGB(255, 123, 64, 0),

    Color.fromARGB(255, 247, 229, 114),
    Color.fromARGB(255, 241, 209, 0),
    Color.fromARGB(255, 167, 146, 2),
    Color.fromARGB(255, 120, 105, 2),

    Color.fromARGB(255, 183, 230, 155),
    Color.fromARGB(255, 71, 192, 0),
    Color.fromARGB(255, 40, 107, 2),
    Color.fromARGB(255, 29, 79, 0),

    Color.fromARGB(255, 196, 241, 255),
    Color.fromARGB(255, 1, 195, 255),
    Color.fromARGB(255, 3, 166, 217),
    Color.fromARGB(255, 1, 109, 143),

    Color.fromARGB(255, 145, 170, 255),
    Color.fromARGB(255, 0, 58, 255),
    Color.fromARGB(255, 0, 42, 183),
    Color.fromARGB(255, 0, 26, 115),

    Color.fromARGB(255, 215, 178, 255),
    Color.fromARGB(255, 121, 0, 255),
    Color.fromARGB(255, 88, 2, 185),
    Color.fromARGB(255, 47, 0, 100),
  ];

  static const List<Color> master32 = [
    // Color(0xffffffff),
    // Color(0xff989898),
    // Color(0xff3d3d3d),
    // Color(0xff000000),
    // Color(0xffffaba3),
    // Color(0xfff66d67),
    // Color(0xffcb4644),
    // Color(0xff940015),
    // Color(0xfffeb07a),
    // Color(0xffec7c0e),
    // Color(0xffb75f0b),
    // Color(0xff753b07),
    // Color(0xffe6c216),
    // Color(0xffba9c13),
    // Color(0xff90790f),
    // Color(0xff5c4c02),
    // Color(0xff75e07c),
    // Color(0xff4db956),
    // Color(0xff1d9330),
    // Color(0xff045e17),
    // Color(0xff22dee6),
    // Color(0xff1bb3ba),
    // Color(0xff138b90),
    // Color(0xff04585c),
    // Color(0xffa2c5ff),
    // Color(0xff639dfe),
    // Color(0xff3876dd),
    // Color(0xff0145a7),
    // Color(0xffd5b2fe),
    // Color(0xffb77ff2),
    // Color(0xff925ac9),
    // Color(0xff632895),

    // Color(0xffffffff),
    // Color(0xff989898),
    // Color(0xff3d3d3d),
    // Color(0xff000000),
    // Color(0xfffdc9c4),
    // Color(0xffea6a64),
    // Color(0xFFDE0419),
    // Color(0xff530309),
    // Color(0xFFFABC65),
    // Color(0xFFF98E13),
    // Color(0xFFC76814),
    // Color(0xFF854306),
    // Color(0xFFFFDE5B),
    // Color(0xFFFFD000),
    // Color(0xFF9E8207),
    // Color(0xFF4B3F06),
    // Color(0xFF71F777),
    // Color(0xFF00FF3C),
    // Color(0xFF04951F),
    // Color(0xFF02440C),
    // Color(0xff26f4fd),
    // Color(0xFF0EBFC5),
    // Color(0xFF068292),
    // Color(0xFF025356),
    // Color(0xFF5392FF),
    // Color(0xFF1168F4),
    // Color(0xFF0033DC),
    // Color(0xFF002A69),
    // Color(0xFFB87BF5),
    // Color(0xFF8044B8),
    // Color(0xFF581391),
    // Color(0xFF2E004C),

    Color.fromARGB(255, 255, 255, 255),
    Color.fromARGB(255, 179, 179, 179),
    Color.fromARGB(255, 102, 102, 102),
    Color.fromARGB(255, 0, 0, 0),

    Color.fromARGB(255, 255, 176, 163),
    Color.fromARGB(255, 255, 85, 65),
    Color.fromARGB(255, 254, 36, 0),
    Color.fromARGB(255, 98, 14, 1),
    
    Color.fromARGB(255, 255, 179, 99),
    Color.fromARGB(255, 255, 132, 0),
    Color.fromARGB(255, 197, 102, 1),
    Color.fromARGB(255, 142, 73, 0),

    Color.fromARGB(255, 245, 222, 91),
    Color.fromARGB(255, 241, 209, 0),
    Color.fromARGB(255, 181, 157, 2),
    Color.fromARGB(255, 120, 105, 2),

    Color.fromARGB(255, 149, 218, 118),
    Color.fromARGB(255, 71, 192, 0),
    Color.fromARGB(255, 40, 110, 0),
    Color.fromARGB(255, 29, 79, 0),

    Color.fromARGB(255, 196, 241, 255),
    Color.fromARGB(255, 1, 195, 255),
    Color.fromARGB(255, 3, 141, 184),
    Color.fromARGB(255, 1, 109, 143),

    Color.fromARGB(255, 117, 150, 255),
    Color.fromARGB(255, 0, 58, 255),
    Color.fromARGB(255, 2, 46, 202),
    Color.fromARGB(255, 0, 34, 150),

    Color.fromARGB(255, 215, 178, 255),
    Color.fromARGB(255, 178, 135, 255),
    Color.fromARGB(255, 133, 61, 255),
    Color.fromARGB(255, 47, 0, 100),
  ];

  static const List<Color> master64 = [
    Color.fromARGB(255, 255, 255, 255),
    Color.fromARGB(255, 217, 217, 217),
    Color.fromARGB(255, 179, 179, 179),
    Color.fromARGB(255, 138, 139, 138),
    Color.fromARGB(255, 111, 111, 111),
    Color.fromARGB(255, 79, 79, 79),
    Color.fromARGB(255, 36, 36, 36),
    Color.fromARGB(255, 0, 0, 0),

    Color.fromARGB(255, 255, 176, 163),
    Color.fromARGB(255, 255, 154, 137),
    Color.fromARGB(255, 255, 85, 65),
    Color.fromARGB(255, 254, 36, 0),
    Color.fromARGB(255, 209, 30, 1),
    Color.fromARGB(255, 145, 21, 0),
    Color.fromARGB(255, 98, 14, 1),
    Color.fromARGB(255, 69, 10, 0),
    
    Color.fromARGB(255, 255, 179, 99),
    Color.fromARGB(255, 255, 168, 85),
    Color.fromARGB(255, 255, 147, 51),
    Color.fromARGB(255, 255, 132, 0),
    Color.fromARGB(255, 228, 118, 1),
    Color.fromARGB(255, 197, 102, 1),
    Color.fromARGB(255, 142, 73, 0),
    Color.fromARGB(255, 123, 64, 0),

    Color.fromARGB(255, 247, 229, 114),
    Color.fromARGB(255, 245, 222, 91),
    Color.fromARGB(255, 241, 209, 0),
    Color.fromARGB(255, 223, 193, 2),
    Color.fromARGB(255, 203, 177, 1),
    Color.fromARGB(255, 181, 157, 2),
    Color.fromARGB(255, 144, 124, 2),
    Color.fromARGB(255, 120, 105, 2),

    Color.fromARGB(255, 183, 230, 155),
    Color.fromARGB(255, 149, 218, 118),
    Color.fromARGB(255, 109, 205, 75),
    Color.fromARGB(255, 71, 192, 0),
    Color.fromARGB(255, 65, 176, 0),
    Color.fromARGB(255, 54, 148, 1),
    Color.fromARGB(255, 40, 110, 0),
    Color.fromARGB(255, 29, 79, 0),

    Color.fromARGB(255, 196, 241, 255),
    Color.fromARGB(255, 171, 233, 255),
    Color.fromARGB(255, 127, 220, 255),
    Color.fromARGB(255, 1, 195, 255),
    Color.fromARGB(255, 0, 182, 238),
    Color.fromARGB(255, 1, 170, 223),
    Color.fromARGB(255, 3, 141, 184),
    Color.fromARGB(255, 1, 109, 143),

    Color.fromARGB(255, 145, 170, 255),
    Color.fromARGB(255, 117, 150, 255),
    Color.fromARGB(255, 59, 100, 255),
    Color.fromARGB(255, 0, 58, 255),
    Color.fromARGB(255, 2, 51, 225),
    Color.fromARGB(255, 2, 46, 202),
    Color.fromARGB(255, 2, 46, 202),
    Color.fromARGB(255, 0, 34, 150),

    Color.fromARGB(255, 215, 178, 255),
    Color.fromARGB(255, 178, 135, 255),
    Color.fromARGB(255, 154, 101, 255),
    Color.fromARGB(255, 133, 61, 255),
    Color.fromARGB(255, 121, 0, 255),
    Color.fromARGB(255, 105, 2, 221),
    Color.fromARGB(255, 83, 1, 175),
    Color.fromARGB(255, 47, 0, 100),
  ];
}

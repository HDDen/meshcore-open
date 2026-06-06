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
    Color(0xff404040),
    Color(0xff000000),
  ];

  static const List<Color> master8 = [
    Color(0xffffffff),
    Color(0xff8a8a8a),
    Color(0xff000000),
    Color(0xffd84a4a),
    Color(0xffe5862a),
    Color(0xfff0c441),
    Color(0xff4caf50),
    Color(0xff4f83e8),
  ];

  static const List<Color> master16 = [
    Color(0xffffffff),
    Color(0xffb8b8b8),
    Color(0xff5c5c5c),
    Color(0xff000000),
    Color(0xffd84a4a),
    Color(0xff8f1d2c),
    Color(0xffe5862a),
    Color(0xfff0c441),
    Color(0xff4caf50),
    Color(0xff0b6b2a),
    Color(0xff27c6d9),
    Color(0xff16818c),
    Color(0xff4f83e8),
    Color(0xff1f3f91),
    Color(0xffa45bd6),
    Color(0xff6b2f8f),
  ];

  static const List<Color> master32 = [
    Color(0xffffffff),
    Color(0xff989898),
    Color(0xff3d3d3d),
    Color(0xff000000),
    Color(0xffffaba3),
    Color(0xfff66d67),
    Color(0xffcb4644),
    Color(0xff940015),
    Color(0xfffeb07a),
    Color(0xffec7c0e),
    Color(0xffb75f0b),
    Color(0xff753b07),
    Color(0xffe6c216),
    Color(0xffba9c13),
    Color(0xff90790f),
    Color(0xff5c4c02),
    Color(0xff75e07c),
    Color(0xff4db956),
    Color(0xff1d9330),
    Color(0xff045e17),
    Color(0xff22dee6),
    Color(0xff1bb3ba),
    Color(0xff138b90),
    Color(0xff04585c),
    Color(0xffa2c5ff),
    Color(0xff639dfe),
    Color(0xff3876dd),
    Color(0xff0145a7),
    Color(0xffd5b2fe),
    Color(0xffb77ff2),
    Color(0xff925ac9),
    Color(0xff632895),
  ];

  static const List<Color> master64 = [
    Color(0xffffffff),
    Color(0xffd1d1d1),
    Color(0xffa4a4a4),
    Color(0xff7a7a7a),
    Color(0xff525252),
    Color(0xff2e2e2e),
    Color(0xff0d0d0d),
    Color(0xff000000),
    Color(0xfffdc9c4),
    Color(0xfffd968f),
    Color(0xffea6a64),
    Color(0xffc74b47),
    Color(0xffa5292b),
    Color(0xff800613),
    Color(0xff530309),
    Color(0xff290102),
    Color(0xfffdccac),
    Color(0xfffd9c54),
    Color(0xffe1791b),
    Color(0xffb75f0b),
    Color(0xff8d4908),
    Color(0xff663305),
    Color(0xff411f03),
    Color(0xff1f0c01),
    Color(0xfff9d544),
    Color(0xffd8b501),
    Color(0xffb39615),
    Color(0xff90790f),
    Color(0xff6e5c09),
    Color(0xff4f4105),
    Color(0xff312802),
    Color(0xff161101),
    Color(0xff8ff394),
    Color(0xff6ed274),
    Color(0xff4db155),
    Color(0xff299236),
    Color(0xff02721c),
    Color(0xff065114),
    Color(0xff023309),
    Color(0xff011702),
    Color(0xff26f4fd),
    Color(0xff17d0d8),
    Color(0xff05adb4),
    Color(0xff138b90),
    Color(0xff076b6f),
    Color(0xff0c4c4f),
    Color(0xff042f32),
    Color(0xff001517),
    Color(0xffc3d9fd),
    Color(0xff8eb8fe),
    Color(0xff5b96fa),
    Color(0xff3d77d7),
    Color(0xff1f58b6),
    Color(0xff003b93),
    Color(0xff02245e),
    Color(0xff010f30),
    Color(0xffe2ccfd),
    Color(0xffcc9fff),
    Color(0xffb07be6),
    Color(0xff915dc5),
    Color(0xff733ea4),
    Color(0xff571f84),
    Color(0xff3a0060),
    Color(0xff1b0130),
  ];
}

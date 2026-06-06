import 'package:flutter/material.dart';

import 'mcoimg_codec.dart';

class MCOImagePalette {
  static const int blackIndex = 0;
  static const int whiteIndex = 1;

  static List<Color> colorsFor(PaletteProfile profile) {
    return switch (profile) {
      PaletteProfile.mono => mono,
      PaletteProfile.master4 => master4,
      PaletteProfile.master32 => master32,
      PaletteProfile.master64 => master64,
    };
  }

  static const List<Color> mono = [
    Color(0xff000000),
    Color(0xffffffff),
  ];

  static const List<Color> master4 = [
    Color(0xff000000),
    Color(0xffffffff),
    Color(0xffc0c0c0),
    Color(0xff404040),
  ];

  static const List<Color> master32 = [
    Color(0xff000000),
    Color(0xffffffff),
    Color(0xff808080),
    Color(0xffc0c0c0),
    Color(0xff800000),
    Color(0xffff0000),
    Color(0xffff8080),
    Color(0xffffc0c0),
    Color(0xff808000),
    Color(0xffffff00),
    Color(0xffffff80),
    Color(0xffffffc0),
    Color(0xff008000),
    Color(0xff00ff00),
    Color(0xff80ff80),
    Color(0xffc0ffc0),
    Color(0xff008080),
    Color(0xff00ffff),
    Color(0xff80ffff),
    Color(0xffc0ffff),
    Color(0xff000080),
    Color(0xff0000ff),
    Color(0xff8080ff),
    Color(0xffc0c0ff),
    Color(0xff800080),
    Color(0xffff00ff),
    Color(0xffff80ff),
    Color(0xffffc0ff),
    Color(0xffff8000),
    Color(0xffffc000),
    Color(0xff804000),
    Color(0xff408040),
  ];

  static const List<Color> master64 = [
    ...master32,
    Color(0xff202020),
    Color(0xff404040),
    Color(0xff606060),
    Color(0xffa0a0a0),
    Color(0xffe0e0e0),
    Color(0xff400000),
    Color(0xff400040),
    Color(0xff004000),
    Color(0xff004040),
    Color(0xff000040),
    Color(0xff404000),
    Color(0xff204080),
    Color(0xff208040),
    Color(0xff802040),
    Color(0xff804020),
    Color(0xff408020),
    Color(0xff40a0ff),
    Color(0xff80c0ff),
    Color(0xffffa040),
    Color(0xffffd080),
    Color(0xffa0ff40),
    Color(0xffd0ff80),
    Color(0xffff4080),
    Color(0xffff80c0),
    Color(0xff40ff80),
    Color(0xff80ffc0),
    Color(0xff8040ff),
    Color(0xffc080ff),
    Color(0xff0080ff),
    Color(0xff00ff80),
    Color(0xffff0080),
    Color(0xff80ff00),
  ];
}

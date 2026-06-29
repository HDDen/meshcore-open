import 'package:flutter/material.dart';

import 'mcoimg_dynamic_palettes.dart';
import 'mcoimg_types.dart';

class MCOImagePalette {
  static const int blackIndex = 0;
  static const int whiteIndex = 1;

  static int blackIndexFor(PaletteProfile profile) {
    if (profile.isDynamic) {
      return MCOImageDynamicPalette.blackGlobalIndexFor(profile);
    }
    return switch (profile) {
      PaletteProfile.mono => 1,
      PaletteProfile.master4 => 3,
      PaletteProfile.master8 => 1,
      PaletteProfile.grayscale8 => 7,
      PaletteProfile.master16 => 3,
      PaletteProfile.grayscale16 => 15,
      PaletteProfile.master32 => 3,
      PaletteProfile.grayscale32 => 31,
      PaletteProfile.master64 => 7,
      _ => throw MCOImageInvalidInputException(
        'Palette profile $profile is not fixed',
      ),
    };
  }

  static int whiteIndexFor(PaletteProfile profile) {
    if (profile.isDynamic) {
      return MCOImageDynamicPalette.whiteGlobalIndexFor(profile);
    }
    return switch (profile) {
      PaletteProfile.mono => 0,
      PaletteProfile.master4 => 0,
      PaletteProfile.master8 => 0,
      PaletteProfile.grayscale8 => 0,
      PaletteProfile.master16 => 0,
      PaletteProfile.grayscale16 => 0,
      PaletteProfile.master32 => 0,
      PaletteProfile.grayscale32 => 0,
      PaletteProfile.master64 => 0,
      _ => throw MCOImageInvalidInputException(
        'Palette profile $profile is not fixed',
      ),
    };
  }

  static List<Color> colorsFor(PaletteProfile profile) {
    if (profile.isDynamic) {
      return MCOImageDynamicPalette.colorsFor(profile);
    }
    return switch (profile) {
      PaletteProfile.mono => mono,
      PaletteProfile.master4 => master4,
      PaletteProfile.master8 => master8,
      PaletteProfile.grayscale8 => grayscale8,
      PaletteProfile.master16 => master16,
      PaletteProfile.grayscale16 => grayscale16,
      PaletteProfile.master32 => master32,
      PaletteProfile.grayscale32 => grayscale32,
      PaletteProfile.master64 => master64,
      _ => throw MCOImageInvalidInputException(
        'Palette profile $profile is not fixed',
      ),
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

  static const List<Color> grayscale8 = [
    Color(0xffffffff),
    Color(0xffdbdbdb),
    Color(0xffb6b6b6),
    Color(0xff919191),
    Color(0xff6d6d6d),
    Color(0xff484848),
    Color(0xff242424),
    Color(0xff000000),
  ];

  static const List<Color> master16 = [
    Color.fromARGB(255, 255, 255, 255),
    Color.fromARGB(255, 164, 164, 164),
    Color.fromARGB(255, 0, 0, 0),
    Color.fromARGB(255, 209, 30, 1),
    Color.fromARGB(255, 98, 14, 1),
    Color.fromARGB(255, 255, 132, 0),
    Color.fromARGB(255, 123, 64, 0),
    Color.fromARGB(255, 241, 209, 0),
    Color.fromARGB(255, 144, 124, 2),
    Color.fromARGB(255, 65, 176, 0),
    Color.fromARGB(255, 40, 110, 0),
    Color.fromARGB(255, 127, 220, 255),
    Color.fromARGB(255, 0, 58, 255),
    Color.fromARGB(255, 0, 34, 150),
    Color.fromARGB(255, 106, 0, 227),
    Color.fromARGB(255, 47, 0, 100),
  ];

  static const List<Color> grayscale16 = [
    Color(0xffffffff),
    Color(0xffeeeeee),
    Color(0xffdddddd),
    Color(0xffcccccc),
    Color(0xffbbbbbb),
    Color(0xffaaaaaa),
    Color(0xff999999),
    Color(0xff888888),
    Color(0xff777777),
    Color(0xff666666),
    Color(0xff555555),
    Color(0xff444444),
    Color(0xff333333),
    Color(0xff222222),
    Color(0xff111111),
    Color(0xff000000),
  ];

  static const List<Color> master32 = [
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

  static const List<Color> grayscale32 = [
    Color(0xffffffff),
    Color(0xfff7f7f7),
    Color(0xffefefef),
    Color(0xffe6e6e6),
    Color(0xffdedede),
    Color(0xffd6d6d6),
    Color(0xffcecece),
    Color(0xffc5c5c5),
    Color(0xffbdbdbd),
    Color(0xffb5b5b5),
    Color(0xffadadad),
    Color(0xffa5a5a5),
    Color(0xff9c9c9c),
    Color(0xff949494),
    Color(0xff8c8c8c),
    Color(0xff848484),
    Color(0xff7b7b7b),
    Color(0xff737373),
    Color(0xff6b6b6b),
    Color(0xff636363),
    Color(0xff5a5a5a),
    Color(0xff525252),
    Color(0xff4a4a4a),
    Color(0xff424242),
    Color(0xff393939),
    Color(0xff313131),
    Color(0xff292929),
    Color(0xff212121),
    Color(0xff181818),
    Color(0xff101010),
    Color(0xff080808),
    Color(0xff000000),
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
    Color.fromARGB(255, 1, 40, 176),
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

class MCOImageDynamicPalette {
  static const List<Color> global512 = DynamicPalettes.global512;

  static final Map<PaletteProfile, Map<int, int>> _reverseMaps = {};
  static final Map<PaletteProfile, List<Color>> _colorsByProfile = {};

  static List<int> indicesFor(PaletteProfile profile) {
    return switch (profile) {
      PaletteProfile.dynamicGlobal8 => DynamicPalettes.dynamicGlobal8Indices,
      PaletteProfile.dynamicGlobal16 => DynamicPalettes.dynamicGlobal16Indices,
      PaletteProfile.dynamicGlobal32 => DynamicPalettes.dynamicGlobal32Indices,
      PaletteProfile.dynamicGlobal64 => DynamicPalettes.dynamicGlobal64Indices,
      PaletteProfile.dynamicGlobal128 =>
        DynamicPalettes.dynamicGlobal128Indices,
      PaletteProfile.dynamicGlobal256 =>
        DynamicPalettes.dynamicGlobal256Indices,
      PaletteProfile.dynamicGlobal512 =>
        DynamicPalettes.dynamicGlobal512Indices,
      _ => throw MCOImageInvalidInputException(
        'Palette profile $profile is not dynamic',
      ),
    };
  }

  static List<Color> colorsFor(PaletteProfile profile) {
    return _colorsByProfile.putIfAbsent(profile, () {
      final indices = indicesFor(profile);
      return List<Color>.unmodifiable(indices.map((index) => global512[index]));
    });
  }

  static int? profileColorIdForGlobalIndex(
    PaletteProfile profile,
    int globalIndex,
  ) {
    if (!profile.isDynamic) return null;
    if (globalIndex < 0 || globalIndex >= global512.length) return null;
    return _reverseMapFor(profile)[globalIndex];
  }

  static int globalIndexForProfileColorId(
    PaletteProfile profile,
    int profileColorId,
  ) {
    final indices = indicesFor(profile);
    if (profileColorId < 0 || profileColorId >= indices.length) {
      throw MCOImageInvalidPayloadException(
        'Dynamic palette color id out of range: $profileColorId',
      );
    }
    return indices[profileColorId];
  }

  static int whiteGlobalIndexFor(PaletteProfile profile) {
    return _globalIndexForColor(profile, const Color(0xffffffff), 'white');
  }

  static int blackGlobalIndexFor(PaletteProfile profile) {
    return _globalIndexForColor(profile, const Color(0xff000000), 'black');
  }

  static Map<int, int> _reverseMapFor(PaletteProfile profile) {
    return _reverseMaps.putIfAbsent(profile, () {
      final indices = indicesFor(profile);
      return {for (var i = 0; i < indices.length; i++) indices[i]: i};
    });
  }

  static int _globalIndexForColor(
    PaletteProfile profile,
    Color color,
    String label,
  ) {
    final wanted = color.toARGB32();
    final indices = indicesFor(profile);
    for (var i = 0; i < indices.length; i++) {
      final globalIndex = indices[i];
      if (global512[globalIndex].toARGB32() == wanted) {
        return globalIndex;
      }
    }
    throw MCOImageInvalidInputException(
      'Dynamic palette $profile has no $label color',
    );
  }
}

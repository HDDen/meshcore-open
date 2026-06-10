(function(global) {
  'use strict';

  // Vanilla browser-global port of the Flutter MCO image codec.
  // Pixel arrays store palette indexes, not ARGB/RGB colors.
  const PaletteProfile = Object.freeze({
    mono: 0,
    master4: 1,
    master8: 2,
    master16: 3,
    master32: 4,
    master64: 5,
    grayscale16: 6,
    grayscale32: 7,
    grayscale8: 8,
    dynamicGlobal8: 9,
    dynamicGlobal16: 10,
    dynamicGlobal32: 11,
    dynamicGlobal64: 12,
    dynamicGlobal128: 13,
    dynamicGlobal256: 14,
    dynamicGlobal512: 15,
  });

  const PaletteProfileName = Object.freeze([
    'mono',
    'master4',
    'master8',
    'master16',
    'master32',
    'master64',
    'grayscale16',
    'grayscale32',
    'grayscale8',
    'dynamicGlobal8',
    'dynamicGlobal16',
    'dynamicGlobal32',
    'dynamicGlobal64',
    'dynamicGlobal128',
    'dynamicGlobal256',
    'dynamicGlobal512',
  ]);

  const PaletteDisplayOrder = Object.freeze([
    PaletteProfile.mono,
    PaletteProfile.grayscale8,
    PaletteProfile.grayscale16,
    PaletteProfile.grayscale32,
    PaletteProfile.master4,
    PaletteProfile.master8,
    PaletteProfile.master16,
    PaletteProfile.master32,
    PaletteProfile.master64,
    PaletteProfile.dynamicGlobal8,
    PaletteProfile.dynamicGlobal16,
    PaletteProfile.dynamicGlobal32,
    PaletteProfile.dynamicGlobal64,
    PaletteProfile.dynamicGlobal128,
    PaletteProfile.dynamicGlobal256,
    PaletteProfile.dynamicGlobal512,
  ]);

  const PaletteDisplayName = Object.freeze({
    [PaletteProfile.mono]: 'Mono',
    [PaletteProfile.grayscale8]: 'Grayscale 8',
    [PaletteProfile.grayscale16]: 'Grayscale 16',
    [PaletteProfile.grayscale32]: 'Grayscale 32',
    [PaletteProfile.master4]: 'Master 4',
    [PaletteProfile.master8]: 'Master 8',
    [PaletteProfile.master16]: 'Master 16',
    [PaletteProfile.master32]: 'Master 32',
    [PaletteProfile.master64]: 'Master 64',
    [PaletteProfile.dynamicGlobal8]: 'Dynamic Global 8',
    [PaletteProfile.dynamicGlobal16]: 'Dynamic Global 16',
    [PaletteProfile.dynamicGlobal32]: 'Dynamic Global 32',
    [PaletteProfile.dynamicGlobal64]: 'Dynamic Global 64',
    [PaletteProfile.dynamicGlobal128]: 'Dynamic Global 128',
    [PaletteProfile.dynamicGlobal256]: 'Dynamic Global 256',
    [PaletteProfile.dynamicGlobal512]: 'Dynamic Global 512',
  });

  const ImageMode = Object.freeze({
    rawGlobal: 0,
    rawLocal: 1,
    rleLocal: 2,
    sparseBg: 3,
    regionsBg: 4,
    biColorMask: 5,
    rowDelta: 6,
    rowRepeat: 7,
  });

  const ImageModeName = Object.freeze([
    'rawGlobal',
    'rawLocal',
    'rleLocal',
    'sparseBg',
    'regionsBg',
    'biColorMask',
    'rowDelta',
    'rowRepeat',
  ]);

  const ScanMode = Object.freeze({
    h: 0,
    v: 1,
    s: 2,
    sv: 3,
  });

  const ScanModeName = Object.freeze(['h', 'v', 's', 'sv']);

  const MCOImagePalettes = Object.freeze({
    [PaletteProfile.mono]: Object.freeze([0xffffffff, 0xff000000]),
    [PaletteProfile.master4]: Object.freeze([
      0xffffffff, 0xffc0c0c0, 0xff565656, 0xff000000,
    ]),
    [PaletteProfile.master8]: Object.freeze([
      0xffffffff, 0xff8d8d8d, 0xff000000, 0xfffe2400,
      0xfff1d100, 0xff47c000, 0xff3d69ff, 0xff7900ff,
    ]),
    [PaletteProfile.master16]: Object.freeze([
      0xffffffff, 0xffa4a4a4, 0xff000000, 0xffd11e01,
      0xff620e01, 0xffff8400, 0xff7b4000, 0xfff1d100,
      0xff907c02, 0xff41b000, 0xff286e00, 0xff7fdcff,
      0xff003aff, 0xff002296, 0xff6a00e3, 0xff2f0064,
    ]),
    [PaletteProfile.master32]: Object.freeze([
      0xffffffff, 0xffb3b3b3, 0xff666666, 0xff000000,
      0xffffb0a3, 0xffff5541, 0xfffe2400, 0xff620e01,
      0xffffb363, 0xffff8400, 0xffc56601, 0xff8e4900,
      0xfff5de5b, 0xfff1d100, 0xffb59d02, 0xff786902,
      0xff95da76, 0xff47c000, 0xff286e00, 0xff1d4f00,
      0xffc4f1ff, 0xff01c3ff, 0xff038db8, 0xff016d8f,
      0xff7596ff, 0xff003aff, 0xff022eca, 0xff002296,
      0xffd7b2ff, 0xffb287ff, 0xff853dff, 0xff2f0064,
    ]),
    [PaletteProfile.master64]: Object.freeze([
      0xffffffff, 0xffd9d9d9, 0xffb3b3b3, 0xff8a8b8a,
      0xff6f6f6f, 0xff4f4f4f, 0xff242424, 0xff000000,
      0xffffb0a3, 0xffff9a89, 0xffff5541, 0xfffe2400,
      0xffd11e01, 0xff911500, 0xff620e01, 0xff450a00,
      0xffffb363, 0xffffa855, 0xffff9333, 0xffff8400,
      0xffe47601, 0xffc56601, 0xff8e4900, 0xff7b4000,
      0xfff7e572, 0xfff5de5b, 0xfff1d100, 0xffdfc102,
      0xffcbb101, 0xffb59d02, 0xff907c02, 0xff786902,
      0xffb7e69b, 0xff95da76, 0xff6dcd4b, 0xff47c000,
      0xff41b000, 0xff369401, 0xff286e00, 0xff1d4f00,
      0xffc4f1ff, 0xffabe9ff, 0xff7fdcff, 0xff01c3ff,
      0xff00b6ee, 0xff01aadf, 0xff038db8, 0xff016d8f,
      0xff91aaff, 0xff7596ff, 0xff3b64ff, 0xff003aff,
      0xff0233e1, 0xff022eca, 0xff022eca, 0xff002296,
      0xffd7b2ff, 0xffb287ff, 0xff9a65ff, 0xff853dff,
      0xff7900ff, 0xff6902dd, 0xff5301af, 0xff2f0064,
    ]),
    [PaletteProfile.grayscale8]: Object.freeze([
      0xffffffff, 0xffdbdbdb, 0xffb6b6b6, 0xff919191,
      0xff6d6d6d, 0xff484848, 0xff242424, 0xff000000,
    ]),
    [PaletteProfile.grayscale16]: Object.freeze([
      0xffffffff, 0xffeeeeee, 0xffdddddd, 0xffcccccc,
      0xffbbbbbb, 0xffaaaaaa, 0xff999999, 0xff888888,
      0xff777777, 0xff666666, 0xff555555, 0xff444444,
      0xff333333, 0xff222222, 0xff111111, 0xff000000,
    ]),
    [PaletteProfile.grayscale32]: Object.freeze([
      0xffffffff, 0xfff7f7f7, 0xffefefef, 0xffe6e6e6,
      0xffdedede, 0xffd6d6d6, 0xffcecece, 0xffc5c5c5,
      0xffbdbdbd, 0xffb5b5b5, 0xffadadad, 0xffa5a5a5,
      0xff9c9c9c, 0xff949494, 0xff8c8c8c, 0xff848484,
      0xff7b7b7b, 0xff737373, 0xff6b6b6b, 0xff636363,
      0xff5a5a5a, 0xff525252, 0xff4a4a4a, 0xff424242,
      0xff393939, 0xff313131, 0xff292929, 0xff212121,
      0xff181818, 0xff101010, 0xff080808, 0xff000000,
    ]),
  });


  const DynamicPaletteReferenceEncoding = Object.freeze({
    flat: 0,
    banked8x64: 1,
  });

  const DynamicPaletteReferenceEncodingName = Object.freeze([
    'flat',
    'banked8x64',
  ]);

  const MCOImageEncodingVersion = Object.freeze({
    v1Legacy: 1,
    v2: 2,
  });

  const DynamicGlobal512 = Object.freeze([4294967295, 4294704123, 4294440951, 4294111986, 4293848814, 4293585642, 4293322470, 4292993505, 4292730333, 4292467161, 4292203989, 4291940817, 4291611852, 4291348680, 4291085508, 4290822336, 4290493371, 4290230199, 4289967027, 4289638318, 4289374890, 4288980132, 4288782753, 4288454044, 4288190616, 4287861907, 4287466893, 4287269770, 4287072391, 4286875012, 4286677633, 4286480254, 4286282619, 4286085240, 4285887861, 4285690482, 4285493103, 4285229931, 4284900966, 4284769380, 4284572001, 4284308829, 4284111450, 4283848278, 4283650899, 4283387727, 4283058762, 4282729797, 4282466625, 4282137660, 4281808695, 4281479730, 4281216558, 4280887593, 4280558628, 4280295456, 4280032284, 4279769112, 4279505940, 4279242768, 4278979596, 4278716424, 4278453252, 4278190080, 4294946979, 4294946464, 4294945693, 4294945178, 4294944407, 4294943893, 4294943122, 4294942607, 4294941836, 4294941321, 4294939265, 4294937465, 4294935409, 4294933353, 4294931553, 4294929497, 4294927441, 4294925641, 4294923585, 4294922298, 4294920755, 4294919467, 4294917924, 4294851101, 4294849558, 4294848270, 4294846727, 4294845440, 4294517504, 4294189824, 4293861888, 4293533952, 4293206273, 4292878337, 4292550401, 4292222721, 4291894785, 4291435777, 4290976769, 4290517761, 4290058753, 4289534208, 4289075200, 4288616192, 4288157184, 4287698176, 4287370240, 4287042304, 4286649088, 4286321152, 4285993217, 4285665281, 4285272065, 4284944129, 4284616193, 4284419585, 4284222721, 4283960577, 4283763713, 4283567104, 4283370240, 4283108096, 4282911232, 4282714624, 4294947683, 4294947425, 4294947168, 4294946654, 4294946397, 4294946139, 4294945882, 4294945368, 4294945111, 4294944853, 4294944337, 4294943565, 4294943050, 4294942534, 4294941762, 4294941246, 4294940731, 4294939959, 4294939443, 4294938925, 4294938664, 4294938146, 4294937628, 4294937367, 4294936849, 4294936331, 4294936070, 4294935552, 4294738432, 4294541568, 4294344448, 4294147584, 4293950465, 4293753601, 4293556481, 4293359617, 4293162497, 4292965377, 4292702721, 4292505857, 4292243201, 4292046081, 4291783425, 4291586561, 4291323905, 4291126785, 4290732801, 4290338817, 4289944577, 4289550593, 4289091072, 4288697088, 4288302848, 4287908864, 4287514880, 4287383552, 4287252224, 4287120896, 4286989568, 4286792704, 4286661376, 4286530048, 4286398720, 4286267392, 4294436210, 4294435951, 4294435693, 4294370154, 4294369896, 4294369637, 4294369379, 4294303840, 4294303582, 4294303323, 4294303057, 4294236999, 4294236733, 4294170675, 4294170408, 4294104350, 4294104084, 4294038026, 4294037760, 4293906176, 4293774592, 4293643265, 4293511681, 4293380097, 4293248513, 4293117186, 4292985602, 4292854018, 4292722434, 4292590850, 4292393986, 4292262402, 4292130817, 4291999233, 4291802369, 4291670785, 4291539201, 4291407617, 4291210497, 4291078657, 4290881537, 4290749954, 4290552834, 4290420994, 4290223874, 4290092290, 4289829122, 4289566210, 4289303042, 4289039874, 4288711426, 4288448258, 4288185090, 4287922178, 4287659010, 4287461890, 4287330306, 4287133186, 4286936066, 4286804226, 4286607106, 4286409986, 4286278402, 4286081282, 4290242203, 4289979799, 4289717139, 4289520271, 4289257867, 4288995206, 4288732802, 4288535934, 4288273274, 4288010870, 4287748465, 4287420268, 4287157864, 4286829667, 4286567262, 4286239065, 4285976661, 4285648464, 4285386059, 4285123651, 4284860986, 4284533042, 4284270378, 4284007969, 4283745305, 4283417361, 4283154696, 4282892288, 4282826240, 4282825728, 4282759936, 4282693888, 4282693376, 4282627328, 4282561536, 4282561024, 4282494976, 4282428672, 4282362368, 4282230528, 4282164224, 4282097665, 4282031361, 4281899521, 4281833217, 4281766913, 4281634817, 4281568257, 4281435905, 4281369345, 4281237248, 4281170688, 4281038336, 4280971776, 4280839680, 4280773376, 4280706816, 4280574976, 4280508416, 4280442112, 4280375552, 4280243712, 4280177152, 4280110848, 4291097087, 4290900223, 4290703359, 4290572031, 4290375167, 4290178559, 4289981695, 4289850367, 4289653503, 4289456639, 4289128703, 4288800511, 4288472575, 4288144383, 4287881983, 4287553791, 4287225855, 4286897663, 4286569727, 4285651455, 4284733183, 4283815167, 4282896895, 4281978623, 4281060351, 4280142335, 4279224063, 4278305791, 4278305533, 4278305019, 4278304761, 4278304247, 4278238454, 4278237940, 4278237682, 4278237168, 4278236910, 4278236652, 4278236139, 4278235881, 4278235623, 4278300646, 4278300388, 4278300130, 4278299617, 4278299359, 4278298587, 4278297814, 4278362322, 4278361550, 4278360777, 4278360005, 4278424513, 4278423740, 4278422968, 4278421939, 4278421167, 4278354602, 4278353830, 4278352801, 4278352029, 4278285464, 4278284692, 4278283663, 4287736575, 4287539455, 4287342335, 4287144959, 4286947839, 4286685183, 4286488063, 4286290687, 4286093567, 4285896447, 4285501695, 4285041663, 4284646911, 4284186879, 4283792127, 4283332095, 4282937343, 4282214911, 4282082559, 4281622527, 4281228287, 4280768255, 4280373759, 4279913983, 4279519487, 4279059455, 4278665215, 4278205183, 4278204924, 4278204664, 4278270197, 4278269938, 4278269678, 4278269419, 4278334952, 4278334692, 4278334433, 4278334174, 4278334172, 4278333913, 4278333911, 4278333652, 4278333650, 4278333391, 4278333389, 4278333130, 4278332871, 4278332868, 4278332609, 4278332350, 4278266812, 4278266553, 4278266294, 4278266291, 4278266032, 4278265773, 4278265770, 4278265511, 4278265252, 4278199714, 4278199455, 4278199196, 4278199193, 4278198934, 4292326143, 4292062719, 4291799295, 4291536127, 4291272703, 4290943743, 4290680319, 4290417151, 4290153727, 4289890303, 4289692671, 4289560575, 4289363199, 4289165567, 4289033471, 4288835839, 4288638463, 4288506367, 4288308735, 4288176639, 4287978751, 4287846655, 4287714303, 4287516671, 4287384319, 4287252223, 4287054335, 4286922239, 4286854911, 4286722047, 4286654975, 4286587647, 4286454783, 4286387455, 4286320383, 4286187519, 4286120191, 4285989115, 4285858039, 4285792756, 4285661680, 4285530604, 4285399528, 4285334245, 4285137123, 4285072093, 4284941016, 4284744403, 4284613326, 4284416713, 4284285379, 4284088766, 4283957689, 4283761076, 4283629999, 4283367847, 4283105694, 4282843542, 4282581390, 4282318981, 4282056829, 4281794677, 4281532524, 4281270372]);
  const DynamicGlobalIndices = Object.freeze({
    [PaletteProfile.dynamicGlobal8]: Object.freeze([0, 26, 63, 91, 210, 283, 401, 484]),
    [PaletteProfile.dynamicGlobal16]: Object.freeze([0, 21, 63, 100, 118, 155, 191, 210, 246, 292, 310, 338, 411, 447, 492, 511]),
    [PaletteProfile.dynamicGlobal32]: Object.freeze([0, 18, 38, 63, 64, 82, 91, 118, 128, 155, 173, 182, 201, 210, 237, 255, 265, 283, 310, 319, 320, 347, 374, 383, 393, 411, 429, 447, 448, 457, 475, 511]),
    [PaletteProfile.dynamicGlobal64]: Object.freeze([0, 9, 18, 27, 36, 45, 54, 63, 64, 73, 82, 91, 100, 109, 118, 127, 128, 137, 146, 155, 164, 173, 182, 191, 192, 201, 210, 219, 228, 237, 246, 255, 256, 265, 274, 283, 292, 301, 310, 319, 320, 329, 338, 347, 356, 365, 374, 383, 384, 393, 402, 411, 420, 429, 438, 447, 448, 457, 466, 475, 484, 493, 502, 511]),
    [PaletteProfile.dynamicGlobal128]: Object.freeze([0, 9, 18, 27, 36, 45, 54, 63, 64, 73, 82, 91, 100, 109, 118, 127, 128, 137, 146, 155, 164, 173, 182, 191, 192, 201, 210, 219, 228, 237, 246, 255, 256, 265, 274, 283, 292, 301, 310, 319, 320, 329, 338, 347, 356, 365, 374, 383, 384, 393, 402, 411, 420, 429, 438, 447, 448, 457, 466, 475, 484, 493, 502, 511, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 28, 29, 30, 31, 32, 33, 34, 35, 37, 38, 39, 40, 41, 42, 43, 44, 46, 47, 48, 49, 50, 51, 52, 53, 55, 56, 57, 58, 59, 60, 61, 62, 65, 66, 67, 68, 69, 70, 71, 72]),
    [PaletteProfile.dynamicGlobal256]: Object.freeze([0, 9, 18, 27, 36, 45, 54, 63, 64, 73, 82, 91, 100, 109, 118, 127, 128, 137, 146, 155, 164, 173, 182, 191, 192, 201, 210, 219, 228, 237, 246, 255, 256, 265, 274, 283, 292, 301, 310, 319, 320, 329, 338, 347, 356, 365, 374, 383, 384, 393, 402, 411, 420, 429, 438, 447, 448, 457, 466, 475, 484, 493, 502, 511, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 28, 29, 30, 31, 32, 33, 34, 35, 37, 38, 39, 40, 41, 42, 43, 44, 46, 47, 48, 49, 50, 51, 52, 53, 55, 56, 57, 58, 59, 60, 61, 62, 65, 66, 67, 68, 69, 70, 71, 72, 74, 75, 76, 77, 78, 79, 80, 81, 83, 84, 85, 86, 87, 88, 89, 90, 92, 93, 94, 95, 96, 97, 98, 99, 101, 102, 103, 104, 105, 106, 107, 108, 110, 111, 112, 113, 114, 115, 116, 117, 119, 120, 121, 122, 123, 124, 125, 126, 129, 130, 131, 132, 133, 134, 135, 136, 138, 139, 140, 141, 142, 143, 144, 145, 147, 148, 149, 150, 151, 152, 153, 154, 156, 157, 158, 159, 160, 161, 162, 163, 165, 166, 167, 168, 169, 170, 171, 172, 174, 175, 176, 177, 178, 179, 180, 181, 183, 184, 185, 186, 187, 188, 189, 190, 193, 194, 195, 196, 197, 198, 199, 200, 202, 203, 204, 205, 206, 207, 208, 209, 211, 212, 213, 214, 215, 216, 217, 218]),
    [PaletteProfile.dynamicGlobal512]: Object.freeze([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448, 449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511]),
  });

  class MCOImageCodecError extends Error {}
  class MCOImageInvalidInputError extends MCOImageCodecError {}
  class MCOImageInvalidPayloadError extends MCOImageCodecError {}
  class MCOImageTooLargeError extends MCOImageCodecError {}

  class MCOImage {
    constructor({
      width,
      height,
      paletteProfile = PaletteProfile.master32,
      pixels,
      transparentColor = null,
      encodingVersion = MCOImageEncodingVersion.v2,
    }) {
      this.width = width;
      this.height = height;
      this.paletteProfile = normalizePaletteProfile(paletteProfile);
      this.pixels = Array.from(pixels);
      this.transparentColor = transparentColor == null ? null : Number(transparentColor);
      this.encodingVersion = normalizeEncodingVersion(encodingVersion);
    }
  }

  class MCOImageCodec {
    encode(imageLike, options = {}) {
      const diagnostics = this.debugEncode(imageLike, options);
      const maxChars = options.maxChars;
      if (maxChars !== undefined && diagnostics.result.charLength > maxChars) {
        throw new MCOImageTooLargeError(
          `Encoded image is ${diagnostics.result.charLength} chars, max is ${maxChars}`,
        );
      }
      return diagnostics.result;
    }

    debugEncode(imageLike, options = {}) {
      const image = imageLike instanceof MCOImage
        ? imageLike
        : new MCOImage(imageLike);
      const backgroundColor = options.backgroundColor;
      const maxRegions = options.maxRegions ?? MCOImageCodec.defaultMaxRegions;
      validateImage(image);
      if (maxRegions < 0) {
        throw new MCOImageInvalidInputError('maxRegions must be >= 0');
      }
      if (backgroundColor !== undefined && backgroundColor !== null) {
        validateColor(backgroundColor, image.paletteProfile, 'backgroundColor');
      }

      const effectiveMaxRegions = Math.min(maxRegions, MCOImageCodec.defaultMaxRegions);
      const candidates = [];
      let best = null;
      for (const background of backgroundCandidates(image, backgroundColor)) {
        const bg = background.color;
        const bounds = findBounds(image.pixels, image.width, image.height, bg);
        for (const scan of Object.values(ScanMode)) {
          const linear = toScanOrder(image.pixels, image.width, image.height, scan);
          for (const mode of MCOImageCodec.blockModes) {
            const payload = this._buildPayload(image, linear, mode, scan, {
              dataWidth: image.width,
              dataHeight: image.height,
              backgroundColor: bg,
            });
            const candidate = candidateFromPayload(payload, mode, scan, {
              backgroundColor: bg,
              backgroundRank: background.rank,
            });
            candidates.push(candidate);
            if (isBetterCandidate(candidate, best)) best = candidate;
          }

          if (bounds.area < image.width * image.height) {
            const cropped = cropPixels(image.pixels, image.width, bounds);
            const boundedLinear = toScanOrder(cropped, bounds.width, bounds.height, scan);
            for (const mode of MCOImageCodec.blockModes) {
              const payload = this._buildPayload(image, boundedLinear, mode, scan, {
                dataWidth: bounds.width,
                dataHeight: bounds.height,
                backgroundColor: bg,
                bounds,
              });
              const candidate = candidateFromPayload(payload, mode, scan, {
                bounds,
                backgroundColor: bg,
                backgroundRank: background.rank,
              });
              candidates.push(candidate);
              if (isBetterCandidate(candidate, best)) best = candidate;
            }
          }
        }

        const regionsPayload = this._tryBuildRegionsPayload(
          image,
          bg,
          effectiveMaxRegions,
        );
        if (regionsPayload) {
          const candidate = candidateFromPayload(
            regionsPayload.payload,
            ImageMode.regionsBg,
            ScanMode.h,
            {
              backgroundColor: bg,
              backgroundRank: background.rank,
              regionCount: regionsPayload.regionCount,
            },
          );
          candidates.push(candidate);
          if (isBetterCandidate(candidate, best)) best = candidate;
        }
      }

      return {
        result: best,
        candidates: Object.freeze(candidates.slice()),
      };
    }

    decode(text) {
      if (!text.startsWith(MCOImageCodec.prefix)) {
        throw new MCOImageInvalidPayloadError('Missing im: prefix');
      }

      const bytes = base91Decode(text.slice(MCOImageCodec.prefix.length));
      if (bytes.length < 4) {
        throw new MCOImageInvalidPayloadError('Payload too short');
      }

      const header = bytes[0];
      const version = (header >> 6) & 0x03;
      if (
        version < MCOImageCodec.minSupportedVersion ||
        version > MCOImageCodec.maxSupportedVersion
      ) {
        throw new MCOImageInvalidPayloadError(`Unsupported version ${version}`);
      }

      const mode = modeFromBits((header >> 4) & 0x03);
      const scan = scanFromBits((header >> 2) & 0x03);
      const bgPresent = ((header >> 1) & 0x01) !== 0;
      const boundsPresent = version >= 1 && (header & 0x01) !== 0;
      if (version === 0 && (header & 0x01) !== 0) {
        throw new MCOImageInvalidPayloadError('Reserved header bit is set');
      }

      const profileHeader = bytes[1];
      const paletteProfile = profileFromBits((profileHeader >> 4) & 0x0f);
      const container = version >= 1
        ? profileHeader & 0x0f
        : MCOImageCodec.containerBlock;
      if (version === 0 && (profileHeader & 0x0f) !== 0) {
        throw new MCOImageInvalidPayloadError('Reserved palette bits are set');
      }
      if (
        container !== MCOImageCodec.containerBlock &&
        container !== MCOImageCodec.containerRegions
      ) {
        throw new MCOImageInvalidPayloadError('Unknown image container');
      }
      if (container === MCOImageCodec.containerBlock &&
          bgPresent !== (mode === ImageMode.sparseBg)) {
        throw new MCOImageInvalidPayloadError(
          'Background flag does not match mode',
        );
      }

      const width = bytes[2] + 1;
      const height = bytes[3] + 1;
      validateDimensions(width, height, true);
      const reader = new BitReader(bytes, 4);

      if (container === MCOImageCodec.containerRegions) {
        if (!bgPresent || boundsPresent) {
          throw new MCOImageInvalidPayloadError('Invalid regions header');
        }
        const pixels = this._decodeRegions(reader, width, height, paletteProfile);
        reader.finish();
        return new MCOImage({ width, height, paletteProfile, pixels });
      }

      if (boundsPresent) {
        const background = reader.readBits(globalBits(paletteProfile));
        validateColor(background, paletteProfile, 'backgroundColor', true);
        const bounds = readBounds(reader, width, height);
        if (bounds.area === 0) {
          reader.finish();
          return new MCOImage({
            width,
            height,
            paletteProfile,
            pixels: Array(width * height).fill(background),
          });
        }

        const croppedLinear = this._decodeBody(
          reader,
          bounds.width,
          bounds.height,
          paletteProfile,
          mode,
          { sparseBackgroundColor: background },
        );
        reader.finish();
        const cropped = fromScanOrder(
          croppedLinear,
          bounds.width,
          bounds.height,
          scan,
        );
        return new MCOImage({
          width,
          height,
          paletteProfile,
          pixels: insertBounds(width, height, background, cropped, bounds),
        });
      }

      const linear = this._decodeBody(reader, width, height, paletteProfile, mode);
      reader.finish();
      return new MCOImage({
        width,
        height,
        paletteProfile,
        pixels: fromScanOrder(linear, width, height, scan),
      });
    }

    _tryBuildRegionsPayload(image, backgroundColor, maxRegions) {
      if (maxRegions === 0) return null;
      const regions = findRegions(
        image.pixels,
        image.width,
        image.height,
        backgroundColor,
      );
      if (regions.length === 0 || regions.length > maxRegions) return null;

      const writer = new BitWriter();
      writer.writeAlignedByte(
        (MCOImageCodec.encodeVersion << 6) |
          (modeBits(ImageMode.rawGlobal) << 4) |
          (scanBits(ScanMode.h) << 2) |
          0x02,
      );
      writer.writeAlignedByte(
        (profileBits(image.paletteProfile) << 4) |
          MCOImageCodec.containerRegions,
      );
      writer.writeAlignedByte(image.width - 1);
      writer.writeAlignedByte(image.height - 1);
      writer.writeBits(backgroundColor, globalBits(image.paletteProfile));
      writer.writeVarUint(regions.length);

      for (const region of regions) {
        const regionPixels = cropPixels(image.pixels, image.width, region);
        const block = bestBlockPayload(
          regionPixels,
          region.width,
          region.height,
          image.paletteProfile,
          backgroundColor,
        );
        writer.writeVarUint(region.x);
        writer.writeVarUint(region.y);
        writer.writeVarUint(region.width);
        writer.writeVarUint(region.height);
        writer.writeAlignedByte(modeBits(block.mode));
        writer.writeAlignedByte(scanBits(block.scan));
        writer.writeVarUint(block.payload.length);
        writer.writeAlignedBytes(block.payload);
      }

      return { payload: writer.toBytes(), regionCount: regions.length };
    }

    _buildPayload(image, linear, mode, scan, options) {
      const {
        dataWidth,
        dataHeight,
        backgroundColor,
        bounds,
      } = options;
      const expectedDataLength = dataWidth * dataHeight;
      if (linear.length !== expectedDataLength) {
        throw new MCOImageInvalidInputError(
          `linear.length must be ${expectedDataLength}, got ${linear.length}`,
        );
      }

      const writer = new BitWriter();
      const bgPresent = mode === ImageMode.sparseBg;
      const boundsPresent = bounds != null;
      writer.writeAlignedByte(
        (MCOImageCodec.encodeVersion << 6) |
          (modeBits(mode) << 4) |
          (scanBits(scan) << 2) |
          (bgPresent ? 0x02 : 0) |
          (boundsPresent ? 0x01 : 0),
      );
      writer.writeAlignedByte(profileBits(image.paletteProfile) << 4);
      writer.writeAlignedByte(image.width - 1);
      writer.writeAlignedByte(image.height - 1);

      if (boundsPresent) {
        // Bounds keep the original canvas size in the header while the body
        // stores only the non-background rectangle.
        writer.writeBits(backgroundColor, globalBits(image.paletteProfile));
        writer.writeVarUint(bounds.x);
        writer.writeVarUint(bounds.y);
        writer.writeVarUint(bounds.width);
        writer.writeVarUint(bounds.height);
        if (bounds.area === 0) return writer.toBytes();
      }

      writeBlock(writer, linear, mode, image.paletteProfile, {
        backgroundColor,
        writeSparseBackground: !boundsPresent,
      });
      return writer.toBytes();
    }

    _decodeBody(reader, width, height, paletteProfile, mode, options = {}) {
      switch (mode) {
        case ImageMode.rawGlobal:
          return decodeRawGlobal(reader, width, height, paletteProfile);
        case ImageMode.rawLocal:
          return decodeRawLocal(reader, width, height, paletteProfile);
        case ImageMode.rleLocal:
          return decodeRleLocal(reader, width, height, paletteProfile);
        case ImageMode.sparseBg:
          return decodeSparseBg(reader, width, height, paletteProfile, {
            backgroundColor: options.sparseBackgroundColor,
          });
        case ImageMode.regionsBg:
          throw new MCOImageInvalidPayloadError(
            'REGIONS_BG is not a block body mode',
          );
        default:
          throw new MCOImageInvalidPayloadError('Unknown image mode');
      }
    }

    _decodeRegions(reader, width, height, paletteProfile) {
      const background = reader.readBits(globalBits(paletteProfile));
      validateColor(background, paletteProfile, 'backgroundColor', true);
      const regionCount = reader.readVarUint();
      if (
        regionCount <= 0 ||
        regionCount > MCOImageCodec.defaultMaxRegions
      ) {
        throw new MCOImageInvalidPayloadError('Invalid region count');
      }

      const pixels = Array(width * height).fill(background);
      const occupied = Array(width * height).fill(false);
      for (let i = 0; i < regionCount; i++) {
        const region = {
          x: reader.readVarUint(),
          y: reader.readVarUint(),
          width: reader.readVarUint(),
          height: reader.readVarUint(),
        };
        region.area = region.width * region.height;
        if (
          region.width <= 0 ||
          region.height <= 0 ||
          region.x + region.width > width ||
          region.y + region.height > height
        ) {
          throw new MCOImageInvalidPayloadError('Invalid image region');
        }

        const regionMode = modeFromBits(reader.readAlignedByte());
        const regionScan = scanFromBits(reader.readAlignedByte());
        const payloadLength = reader.readVarUint();
        const payload = reader.readAlignedBytes(payloadLength);
        const regionReader = new BitReader(payload);
        const linear = this._decodeBody(
          regionReader,
          region.width,
          region.height,
          paletteProfile,
          regionMode,
          { sparseBackgroundColor: background },
        );
        regionReader.finish();
        const regionPixels = fromScanOrder(
          linear,
          region.width,
          region.height,
          regionScan,
        );

        for (let y = 0; y < region.height; y++) {
          for (let x = 0; x < region.width; x++) {
            const target = (region.y + y) * width + region.x + x;
            if (occupied[target]) {
              throw new MCOImageInvalidPayloadError('Overlapping image regions');
            }
            occupied[target] = true;
            pixels[target] = regionPixels[y * region.width + x];
          }
        }
      }
      return pixels;
    }
  }

  MCOImageCodec.prefix = 'im:';
  MCOImageCodec.encodeVersion = 1;
  MCOImageCodec.minSupportedVersion = 0;
  MCOImageCodec.maxSupportedVersion = 1;
  MCOImageCodec.containerBlock = 0;
  MCOImageCodec.containerRegions = 1;
  MCOImageCodec.minSize = 1;
  MCOImageCodec.maxSize = 85;
  MCOImageCodec.defaultMaxRegions = 8;
  MCOImageCodec.blockModes = Object.freeze([
    ImageMode.rawGlobal,
    ImageMode.rawLocal,
    ImageMode.rleLocal,
    ImageMode.sparseBg,
  ]);
  MCOImageCodec.modeTieOrder = Object.freeze([
    ImageMode.sparseBg,
    ImageMode.rleLocal,
    ImageMode.rawLocal,
    ImageMode.rawGlobal,
    ImageMode.regionsBg,
  ]);

  function candidateFromPayload(payload, mode, scan, options = {}) {
    const text = `${MCOImageCodec.prefix}${base91Encode(payload)}`;
    const bounds = options.bounds;
    return {
      text,
      mode,
      modeName: ImageModeName[mode],
      scan,
      scanName: ScanModeName[scan],
      byteLength: payload.length,
      charLength: text.length,
      boundsPresent: bounds != null,
      boundsX: bounds ? bounds.x : null,
      boundsY: bounds ? bounds.y : null,
      boundsWidth: bounds ? bounds.width : null,
      boundsHeight: bounds ? bounds.height : null,
      backgroundColor: options.backgroundColor ?? null,
      backgroundRank: options.backgroundRank ?? 0,
      regionCount: options.regionCount ?? 0,
    };
  }

  function bestBlockPayload(pixels, width, height, profile, backgroundColor) {
    let best = null;
    for (const scan of Object.values(ScanMode)) {
      const linear = toScanOrder(pixels, width, height, scan);
      for (const mode of MCOImageCodec.blockModes) {
        const writer = new BitWriter();
        writeBlock(writer, linear, mode, profile, {
          backgroundColor,
          writeSparseBackground: false,
        });
        const candidate = { payload: writer.toBytes(), mode, scan };
        if (
          best == null ||
          candidate.payload.length < best.payload.length ||
          (
            candidate.payload.length === best.payload.length &&
            MCOImageCodec.modeTieOrder.indexOf(candidate.mode) <
              MCOImageCodec.modeTieOrder.indexOf(best.mode)
          )
        ) {
          best = candidate;
        }
      }
    }
    return best;
  }

  function writeBlock(writer, linear, mode, profile, options) {
    switch (mode) {
      case ImageMode.rawGlobal:
        encodeRawGlobal(writer, linear, profile);
        break;
      case ImageMode.rawLocal:
        encodeRawLocal(writer, linear, profile);
        break;
      case ImageMode.rleLocal:
        encodeRleLocal(writer, linear, profile);
        break;
      case ImageMode.sparseBg:
        encodeSparseBg(writer, linear, profile, {
          backgroundColor: options.backgroundColor,
          writeBackground: options.writeSparseBackground,
        });
        break;
      case ImageMode.regionsBg:
        throw new MCOImageInvalidInputError('REGIONS_BG is not a block mode');
      default:
        throw new MCOImageInvalidInputError('Unknown image mode');
    }
  }

  function encodeRawGlobal(writer, linear, profile) {
    const bits = globalBits(profile);
    for (const pixel of linear) writer.writeBits(pixel, bits);
  }

  function decodeRawGlobal(reader, width, height, profile) {
    const bits = globalBits(profile);
    return Array.from({ length: width * height }, () => reader.readBits(bits));
  }

  function encodeRawLocal(writer, linear, profile) {
    const local = buildLocalPalette(linear);
    const map = localIndexMap(local);
    const localBits = bitsForLocalPalette(local.length);
    writer.writeVarUint(local.length);
    writePalette(writer, local, profile);
    for (const pixel of linear) writer.writeBits(map.get(pixel), localBits);
  }

  function decodeRawLocal(reader, width, height, profile) {
    const count = width * height;
    const palette = readLocalPalette(reader, profile);
    const localBits = bitsForLocalPalette(palette.length);
    return Array.from({ length: count }, () => {
      const index = reader.readBits(localBits);
      if (index >= palette.length) {
        throw new MCOImageInvalidPayloadError('Local color index out of range');
      }
      return palette[index];
    });
  }

  function encodeRleLocal(writer, linear, profile) {
    const local = buildLocalPalette(linear);
    const map = localIndexMap(local);
    const localBits = bitsForLocalPalette(local.length);
    const runs = buildRuns(linear);
    writer.writeVarUint(local.length);
    writePalette(writer, local, profile);
    writer.writeVarUint(runs.length);
    for (const run of runs) {
      writer.writeBits(map.get(run.color), localBits);
      writer.writeVarUint(run.length);
    }
  }

  function decodeRleLocal(reader, width, height, profile) {
    const count = width * height;
    const palette = readLocalPalette(reader, profile);
    const localBits = bitsForLocalPalette(palette.length);
    const runCount = reader.readVarUint();
    const result = [];
    for (let i = 0; i < runCount; i++) {
      const index = reader.readBits(localBits);
      if (index >= palette.length) {
        throw new MCOImageInvalidPayloadError('RLE local color index out of range');
      }
      const length = reader.readVarUint();
      if (length <= 0 || result.length + length > count) {
        throw new MCOImageInvalidPayloadError('Invalid RLE length');
      }
      for (let j = 0; j < length; j++) result.push(palette[index]);
    }
    if (result.length !== count) {
      throw new MCOImageInvalidPayloadError('RLE data does not fill canvas');
    }
    return result;
  }

  function encodeSparseBg(writer, linear, profile, options) {
    const bg = options.backgroundColor;
    const writeBackground = options.writeBackground ?? true;
    if (writeBackground) {
      writer.writeBits(bg, globalBits(profile));
    }

    const nonBgColors = linear.filter((p) => p !== bg);
    const local = buildLocalPalette(nonBgColors);
    const map = localIndexMap(local);
    const localBits = bitsForLocalPalette(local.length);
    const segments = buildSparseSegments(linear, bg);

    writer.writeVarUint(local.length);
    writePalette(writer, local, profile);
    writer.writeVarUint(segments.length);
    let pos = 0;
    for (const segment of segments) {
      writer.writeVarUint(segment.start - pos);
      writer.writeBits(map.get(segment.color), localBits);
      writer.writeVarUint(segment.length);
      pos = segment.start + segment.length;
    }
  }

  function decodeSparseBg(reader, width, height, profile, options = {}) {
    const count = width * height;
    const bg = options.backgroundColor ?? reader.readBits(globalBits(profile));
    validateColor(bg, profile, 'backgroundColor', true);
    const palette = readLocalPalette(reader, profile, {
      excludedColor: bg,
      allowEmpty: true,
    });
    const localBits = bitsForLocalPalette(palette.length);
    const segmentCount = reader.readVarUint();
    const result = Array(count).fill(bg);
    let pos = 0;
    for (let i = 0; i < segmentCount; i++) {
      pos += reader.readVarUint();
      const index = reader.readBits(localBits);
      if (index >= palette.length) {
        throw new MCOImageInvalidPayloadError('Sparse local color index out of range');
      }
      const length = reader.readVarUint();
      if (length <= 0 || pos + length > count) {
        throw new MCOImageInvalidPayloadError('Invalid sparse segment');
      }
      for (let j = 0; j < length; j++) result[pos + j] = palette[index];
      pos += length;
    }
    return result;
  }

  function writePalette(writer, colors, profile) {
    const bits = globalBits(profile);
    for (const color of colors) writer.writeBits(color, bits);
  }

  function readLocalPalette(reader, profile, options = {}) {
    const { excludedColor, allowEmpty = false } = options;
    const k = reader.readVarUint();
    const maxColors = paletteSize(profile);
    if ((!allowEmpty && k === 0) || k > maxColors) {
      throw new MCOImageInvalidPayloadError('Invalid local palette size');
    }
    const bits = globalBits(profile);
    const colors = [];
    const seen = new Set();
    for (let i = 0; i < k; i++) {
      const color = reader.readBits(bits);
      validateColor(color, profile, 'localPalette', true);
      if (color === excludedColor || seen.has(color)) {
        throw new MCOImageInvalidPayloadError('Invalid local palette');
      }
      seen.add(color);
      colors.push(color);
    }
    return colors;
  }

  function readBounds(reader, fullWidth, fullHeight) {
    const bounds = {
      x: reader.readVarUint(),
      y: reader.readVarUint(),
      width: reader.readVarUint(),
      height: reader.readVarUint(),
    };
    bounds.area = bounds.width * bounds.height;
    if (
      bounds.x + bounds.width > fullWidth ||
      bounds.y + bounds.height > fullHeight ||
      (bounds.width === 0 && bounds.height !== 0) ||
      (bounds.height === 0 && bounds.width !== 0)
    ) {
      throw new MCOImageInvalidPayloadError('Invalid image bounds');
    }
    return bounds;
  }

  function findBounds(pixels, width, height, backgroundColor) {
    let minX = width;
    let minY = height;
    let maxX = -1;
    let maxY = -1;
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        if (pixels[y * width + x] === backgroundColor) continue;
        minX = Math.min(minX, x);
        minY = Math.min(minY, y);
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);
      }
    }
    if (maxX < 0) return { x: 0, y: 0, width: 0, height: 0, area: 0 };
    const bounds = {
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
    };
    bounds.area = bounds.width * bounds.height;
    return bounds;
  }

  function backgroundCandidates(image, explicitBackground) {
    const result = [];
    const seen = new Set();
    const add = (color, rank) => {
      if (color < 0 || color >= paletteSize(image.paletteProfile)) return;
      if (seen.has(color)) return;
      seen.add(color);
      result.push({ color, rank });
    };

    if (explicitBackground !== undefined && explicitBackground !== null) {
      add(explicitBackground, 0);
    }
    add(0, 1);

    const counts = new Map();
    for (const pixel of image.pixels) {
      counts.set(pixel, (counts.get(pixel) ?? 0) + 1);
    }
    const colors = Array.from(counts.keys()).sort((a, b) => {
      const byCount = counts.get(b) - counts.get(a);
      return byCount !== 0 ? byCount : a - b;
    });
    for (let i = 0; i < Math.min(3, colors.length); i++) {
      add(colors[i], 2 + i);
    }
    return result;
  }

  function findRegions(pixels, width, height, backgroundColor) {
    const visited = Array(width * height).fill(false);
    const regions = [];
    const neighbors = [
      [-1, -1], [0, -1], [1, -1],
      [-1, 0], [1, 0],
      [-1, 1], [0, 1], [1, 1],
    ];

    for (let start = 0; start < pixels.length; start++) {
      if (visited[start] || pixels[start] === backgroundColor) continue;
      let minX = start % width;
      let maxX = minX;
      let minY = Math.floor(start / width);
      let maxY = minY;
      const queue = [start];
      visited[start] = true;

      while (queue.length > 0) {
        const index = queue.pop();
        const x = index % width;
        const y = Math.floor(index / width);
        minX = Math.min(minX, x);
        maxX = Math.max(maxX, x);
        minY = Math.min(minY, y);
        maxY = Math.max(maxY, y);

        for (const [dx, dy] of neighbors) {
          const nx = x + dx;
          const ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          const next = ny * width + nx;
          if (visited[next] || pixels[next] === backgroundColor) continue;
          visited[next] = true;
          queue.push(next);
        }
      }

      const region = {
        x: minX,
        y: minY,
        width: maxX - minX + 1,
        height: maxY - minY + 1,
      };
      region.area = region.width * region.height;
      regions.push(region);
    }

    regions.sort((a, b) => {
      const byY = a.y - b.y;
      return byY !== 0 ? byY : a.x - b.x;
    });
    return regions;
  }

  function cropPixels(pixels, fullWidth, bounds) {
    const cropped = [];
    for (let y = 0; y < bounds.height; y++) {
      const start = (bounds.y + y) * fullWidth + bounds.x;
      for (let x = 0; x < bounds.width; x++) {
        cropped.push(pixels[start + x]);
      }
    }
    return cropped;
  }

  function insertBounds(fullWidth, fullHeight, backgroundColor, cropped, bounds) {
    const pixels = Array(fullWidth * fullHeight).fill(backgroundColor);
    for (let y = 0; y < bounds.height; y++) {
      for (let x = 0; x < bounds.width; x++) {
        pixels[(bounds.y + y) * fullWidth + bounds.x + x] =
          cropped[y * bounds.width + x];
      }
    }
    return pixels;
  }

  function isBetterCandidate(candidate, current) {
    if (current == null) return true;
    if (candidate.charLength !== current.charLength) {
      return candidate.charLength < current.charLength;
    }
    if (candidate.backgroundRank !== current.backgroundRank) {
      return candidate.backgroundRank < current.backgroundRank;
    }
    if (candidate.boundsPresent !== current.boundsPresent) {
      return candidate.boundsPresent;
    }
    const candidateContainerRank = containerRank(candidate);
    const currentContainerRank = containerRank(current);
    if (candidateContainerRank !== currentContainerRank) {
      return candidateContainerRank < currentContainerRank;
    }
    const candidateRank = MCOImageCodec.modeTieOrder.indexOf(candidate.mode);
    const currentRank = MCOImageCodec.modeTieOrder.indexOf(current.mode);
    if (candidateRank !== currentRank) return candidateRank < currentRank;
    return candidate.scan < current.scan;
  }

  function containerRank(candidate) {
    if (candidate.boundsPresent) return 0;
    if (candidate.mode === ImageMode.regionsBg) return 1;
    return 2;
  }

  function toScanOrder(pixels, width, height, scan) {
    return scanPositions(width, height, scan).map((i) => pixels[i]);
  }

  function fromScanOrder(linear, width, height, scan) {
    const result = Array(width * height).fill(0);
    const positions = scanPositions(width, height, scan);
    for (let i = 0; i < linear.length; i++) result[positions[i]] = linear[i];
    return result;
  }

  function scanPositions(width, height, scan) {
    const positions = [];
    switch (scan) {
      case ScanMode.h:
        for (let y = 0; y < height; y++) {
          for (let x = 0; x < width; x++) positions.push(y * width + x);
        }
        break;
      case ScanMode.v:
        for (let x = 0; x < width; x++) {
          for (let y = 0; y < height; y++) positions.push(y * width + x);
        }
        break;
      case ScanMode.s:
        for (let y = 0; y < height; y++) {
          if (y % 2 === 0) {
            for (let x = 0; x < width; x++) positions.push(y * width + x);
          } else {
            for (let x = width - 1; x >= 0; x--) positions.push(y * width + x);
          }
        }
        break;
      case ScanMode.sv:
        for (let x = 0; x < width; x++) {
          if (x % 2 === 0) {
            for (let y = 0; y < height; y++) positions.push(y * width + x);
          } else {
            for (let y = height - 1; y >= 0; y--) positions.push(y * width + x);
          }
        }
        break;
      default:
        throw new MCOImageInvalidInputError('Unknown scan mode');
    }
    return positions;
  }

  function buildLocalPalette(pixels) {
    const counts = new Map();
    for (const pixel of pixels) counts.set(pixel, (counts.get(pixel) ?? 0) + 1);
    return Array.from(counts.keys()).sort((a, b) => {
      const byFrequency = counts.get(b) - counts.get(a);
      return byFrequency !== 0 ? byFrequency : a - b;
    });
  }

  function localIndexMap(colors) {
    return new Map(colors.map((color, index) => [color, index]));
  }

  function buildRuns(pixels) {
    const runs = [];
    if (pixels.length === 0) return runs;
    let color = pixels[0];
    let length = 1;
    for (let i = 1; i < pixels.length; i++) {
      if (pixels[i] === color) {
        length++;
      } else {
        runs.push({ color, length });
        color = pixels[i];
        length = 1;
      }
    }
    runs.push({ color, length });
    return runs;
  }

  function buildSparseSegments(pixels, background) {
    const segments = [];
    let i = 0;
    while (i < pixels.length) {
      if (pixels[i] === background) {
        i++;
        continue;
      }
      const start = i;
      const color = pixels[i];
      let length = 0;
      while (i < pixels.length && pixels[i] === color) {
        length++;
        i++;
      }
      segments.push({ start, color, length });
    }
    return segments;
  }

  function bitsForLocalPalette(colorCount) {
    if (colorCount <= 1) return 1;
    return Math.ceil(Math.log2(colorCount));
  }

  function globalBits(profile) {
    switch (normalizePaletteProfile(profile)) {
      case PaletteProfile.mono:
        return 1;
      case PaletteProfile.master4:
        return 2;
      case PaletteProfile.master8:
      case PaletteProfile.grayscale8:
        return 3;
      case PaletteProfile.master16:
      case PaletteProfile.grayscale16:
        return 4;
      case PaletteProfile.master32:
      case PaletteProfile.grayscale32:
        return 5;
      case PaletteProfile.master64:
        return 6;
      default:
        throw new MCOImageInvalidInputError('Unknown palette profile');
    }
  }

  function paletteSize(profile) {
    return getPalette(profile).length;
  }

  function getPalette(profile) {
    const normalized = normalizePaletteProfile(profile);
    const palette = MCOImagePalettes[normalized];
    if (!palette) throw new MCOImageInvalidInputError('Unknown palette profile');
    return palette;
  }

  function whiteIndexFor(profile) {
    return 0;
  }

  function blackIndexFor(profile) {
    switch (normalizePaletteProfile(profile)) {
      case PaletteProfile.mono:
      case PaletteProfile.master8:
        return 1;
      case PaletteProfile.master4:
      case PaletteProfile.master16:
      case PaletteProfile.master32:
        return 3;
      case PaletteProfile.grayscale8:
        return 7;
      case PaletteProfile.grayscale16:
        return 15;
      case PaletteProfile.grayscale32:
        return 31;
      case PaletteProfile.master64:
        return 7;
      default:
        throw new MCOImageInvalidInputError('Unknown palette profile');
    }
  }

  function normalizePaletteProfile(profile) {
    if (typeof profile === 'number') return profile;
    if (typeof profile === 'string') {
      if (Object.prototype.hasOwnProperty.call(PaletteProfile, profile)) {
        return PaletteProfile[profile];
      }
      const index = PaletteProfileName.indexOf(profile);
      if (index >= 0) return index;
    }
    throw new MCOImageInvalidInputError(`Unknown palette profile ${profile}`);
  }

  function modeBits(mode) {
    switch (mode) {
      case ImageMode.rawGlobal: return 0;
      case ImageMode.rawLocal: return 1;
      case ImageMode.rleLocal: return 2;
      case ImageMode.sparseBg: return 3;
      case ImageMode.biColorMask: return 4;
      case ImageMode.rowDelta: return 5;
      case ImageMode.rowRepeat: return 6;
      case ImageMode.regionsBg: return 7;
      default: throw new MCOImageInvalidInputError('Unknown image mode');
    }
  }

  function scanBits(scan) {
    return scan;
  }

  function profileBits(profile) {
    return normalizePaletteProfile(profile);
  }

  function modeFromBits(value) {
    switch (value) {
      case 0: return ImageMode.rawGlobal;
      case 1: return ImageMode.rawLocal;
      case 2: return ImageMode.rleLocal;
      case 3: return ImageMode.sparseBg;
      case 4: return ImageMode.biColorMask;
      case 5: return ImageMode.rowDelta;
      case 6: return ImageMode.rowRepeat;
      case 7: return ImageMode.regionsBg;
      default: throw new MCOImageInvalidPayloadError('Unknown image mode');
    }
  }

  function scanFromBits(value) {
    if (value < 0 || value >= ScanModeName.length) {
      throw new MCOImageInvalidPayloadError(`Unknown scan mode ${value}`);
    }
    return value;
  }

  function profileFromBits(value) {
    if (value < 0 || value >= PaletteProfileName.length || value > 0x0f) {
      throw new MCOImageInvalidPayloadError(`Unknown palette profile ${value}`);
    }
    return value;
  }

  function validateImage(image) {
    validateDimensions(image.width, image.height);
    const expected = image.width * image.height;
    if (image.pixels.length !== expected) {
      throw new MCOImageInvalidInputError(
        `pixels.length must be ${expected}, got ${image.pixels.length}`,
      );
    }
    for (const pixel of image.pixels) {
      validateColor(pixel, image.paletteProfile, 'pixel');
    }
  }

  function validateDimensions(width, height, payload = false) {
    const ok =
      Number.isInteger(width) &&
      Number.isInteger(height) &&
      width >= MCOImageCodec.minSize &&
      height >= MCOImageCodec.minSize &&
      width <= MCOImageCodec.maxSize &&
      height <= MCOImageCodec.maxSize;
    if (ok) return;
    const message =
      `Image size must be ${MCOImageCodec.minSize}..${MCOImageCodec.maxSize} in both axes`;
    if (payload) throw new MCOImageInvalidPayloadError(message);
    throw new MCOImageInvalidInputError(message);
  }

  function validateColor(color, profile, label, payload = false) {
    const max = paletteSize(profile) - 1;
    const ok = Number.isInteger(color) && color >= 0 && color <= max;
    if (ok) return;
    const message = `${label} color must be 0..${max}, got ${color}`;
    if (payload) throw new MCOImageInvalidPayloadError(message);
    throw new MCOImageInvalidInputError(message);
  }

  class BitWriter {
    constructor() {
      this.bytes = [];
      this.bitOffset = 0;
    }

    writeAlignedByte(value) {
      this.alignToByte();
      this.bytes.push(value & 0xff);
    }

    writeAlignedBytes(values) {
      this.alignToByte();
      for (const value of values) this.bytes.push(value & 0xff);
    }

    writeBits(value, bitCount) {
      if (bitCount < 0) throw new MCOImageInvalidInputError('Negative bit count');
      let remaining = bitCount;
      let source = value;
      while (remaining > 0) {
        if (this.bitOffset === 0) this.bytes.push(0);
        const available = 8 - this.bitOffset;
        const take = Math.min(remaining, available);
        const mask = (1 << take) - 1;
        this.bytes[this.bytes.length - 1] |= (source & mask) << this.bitOffset;
        source >>= take;
        this.bitOffset = (this.bitOffset + take) & 7;
        remaining -= take;
      }
    }

    writeVarUint(value) {
      if (value < 0) throw new MCOImageInvalidInputError('Negative varuint');
      this.alignToByte();
      let current = value;
      do {
        let byte = current & 0x7f;
        current >>= 7;
        if (current !== 0) byte |= 0x80;
        this.bytes.push(byte);
      } while (current !== 0);
    }

    alignToByte() {
      if (this.bitOffset !== 0) this.bitOffset = 0;
    }

    toBytes() {
      this.alignToByte();
      return Uint8Array.from(this.bytes);
    }
  }

  class BitReader {
    constructor(bytes, byteIndex = 0) {
      this.bytes = bytes;
      this.byteIndex = byteIndex;
      this.bitOffset = 0;
    }

    readAlignedByte() {
      this.alignToByte();
      if (this.byteIndex >= this.bytes.length) {
        throw new MCOImageInvalidPayloadError('Unexpected end of byte');
      }
      return this.bytes[this.byteIndex++];
    }

    readAlignedBytes(length) {
      if (length < 0) {
        throw new MCOImageInvalidPayloadError('Negative byte length');
      }
      this.alignToByte();
      if (this.byteIndex + length > this.bytes.length) {
        throw new MCOImageInvalidPayloadError('Unexpected end of bytes');
      }
      const result = this.bytes.slice(this.byteIndex, this.byteIndex + length);
      this.byteIndex += length;
      return result;
    }

    readBits(bitCount) {
      if (bitCount < 0) {
        throw new MCOImageInvalidPayloadError('Negative bit count');
      }
      let result = 0;
      let shift = 0;
      let remaining = bitCount;
      while (remaining > 0) {
        if (this.byteIndex >= this.bytes.length) {
          throw new MCOImageInvalidPayloadError('Unexpected end of bits');
        }
        const available = 8 - this.bitOffset;
        const take = Math.min(remaining, available);
        const mask = (1 << take) - 1;
        result |= ((this.bytes[this.byteIndex] >> this.bitOffset) & mask) << shift;
        this.bitOffset += take;
        if (this.bitOffset === 8) {
          this.bitOffset = 0;
          this.byteIndex++;
        }
        shift += take;
        remaining -= take;
      }
      return result;
    }

    readVarUint(maxBytes = 5) {
      this.alignToByte();
      let result = 0;
      let shift = 0;
      for (let i = 0; i < maxBytes; i++) {
        if (this.byteIndex >= this.bytes.length) {
          throw new MCOImageInvalidPayloadError('Unexpected end of varuint');
        }
        const byte = this.bytes[this.byteIndex++];
        result |= (byte & 0x7f) << shift;
        if ((byte & 0x80) === 0) return result;
        shift += 7;
      }
      throw new MCOImageInvalidPayloadError('Varuint is too long');
    }

    alignToByte() {
      if (this.bitOffset !== 0) {
        if (this.byteIndex >= this.bytes.length) {
          throw new MCOImageInvalidPayloadError('Unexpected end of padding');
        }
        const unusedMask = (0xff << this.bitOffset) & 0xff;
        if ((this.bytes[this.byteIndex] & unusedMask) !== 0) {
          throw new MCOImageInvalidPayloadError('Non-zero padding bits');
        }
        this.byteIndex++;
        this.bitOffset = 0;
      }
    }

    finish() {
      if (this.bitOffset !== 0) {
        const unusedMask = (0xff << this.bitOffset) & 0xff;
        if ((this.bytes[this.byteIndex] & unusedMask) !== 0) {
          throw new MCOImageInvalidPayloadError('Non-zero padding bits');
        }
        this.byteIndex++;
        this.bitOffset = 0;
      }
      if (this.byteIndex !== this.bytes.length) {
        throw new MCOImageInvalidPayloadError('Trailing payload bytes');
      }
    }
  }

  const BASE91_ALPHABET =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789' +
    '!#$%&()*+,./:;<=>?@[]^_`{|}~"';

  const BASE91_DECODE = new Map(
    Array.from(BASE91_ALPHABET).map((char, index) => [char.charCodeAt(0), index]),
  );

  function base91Encode(bytes) {
    let output = '';
    let queue = 0;
    let bitCount = 0;
    for (const byte of bytes) {
      queue |= byte << bitCount;
      bitCount += 8;
      if (bitCount > 13) {
        let value = queue & 8191;
        if (value > 88) {
          queue >>= 13;
          bitCount -= 13;
        } else {
          value = queue & 16383;
          queue >>= 14;
          bitCount -= 14;
        }
        output += BASE91_ALPHABET[value % 91];
        output += BASE91_ALPHABET[Math.floor(value / 91)];
      }
    }
    if (bitCount > 0) {
      output += BASE91_ALPHABET[queue % 91];
      if (bitCount > 7 || queue > 90) {
        output += BASE91_ALPHABET[Math.floor(queue / 91)];
      }
    }
    return output;
  }

  function base91Decode(text) {
    const output = [];
    let value = -1;
    let queue = 0;
    let bitCount = 0;
    for (let i = 0; i < text.length; i++) {
      const decoded = BASE91_DECODE.get(text.charCodeAt(i));
      if (decoded == null) {
        throw new MCOImageInvalidPayloadError('Invalid basE91 character');
      }
      if (value < 0) {
        value = decoded;
      } else {
        value += decoded * 91;
        queue |= value << bitCount;
        bitCount += (value & 8191) > 88 ? 13 : 14;
        while (bitCount > 7) {
          output.push(queue & 0xff);
          queue >>= 8;
          bitCount -= 8;
        }
        value = -1;
      }
    }
    if (value >= 0) output.push((queue | (value << bitCount)) & 0xff);
    return Uint8Array.from(output);
  }

  function argbToCss(argb) {
    const rgb = argb & 0x00ffffff;
    return `#${rgb.toString(16).padStart(6, '0')}`;
  }

  function drawMCOImage(canvas, image, options = {}) {
    const scale = options.scale ?? 12;
    canvas.width = image.width * scale;
    canvas.height = image.height * scale;
    const ctx = canvas.getContext('2d');
    ctx.imageSmoothingEnabled = false;
    const palette = getPalette(image.paletteProfile);
    for (let y = 0; y < image.height; y++) {
      for (let x = 0; x < image.width; x++) {
        const colorIndex = Math.max(
          0,
          Math.min(palette.length - 1, image.pixels[y * image.width + x]),
        );
        ctx.fillStyle = argbToCss(palette[colorIndex]);
        ctx.fillRect(x * scale, y * scale, scale, scale);
      }
    }
  }

  function nearestPaletteIndex(profile, r, g, b) {
    const palette = getPalette(profile);
    let bestIndex = 0;
    let bestDistance = Number.POSITIVE_INFINITY;
    for (let i = 0; i < palette.length; i++) {
      const color = palette[i];
      const pr = (color >> 16) & 0xff;
      const pg = (color >> 8) & 0xff;
      const pb = color & 0xff;
      const dr = r - pr;
      const dg = g - pg;
      const db = b - pb;
      const distance = dr * dr + dg * dg + db * db;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }


  // ---- V2 codec extension -------------------------------------------------
  const __legacyDebugEncode = MCOImageCodec.prototype.debugEncode;
  const __legacyEncode = MCOImageCodec.prototype.encode;
  const __legacyDecode = MCOImageCodec.prototype.decode;
  const __legacyPaletteSize = paletteSize;
  const __legacyGetPalette = getPalette;
  const __legacyWhiteIndexFor = whiteIndexFor;
  const __legacyBlackIndexFor = blackIndexFor;
  const __legacyGlobalBits = globalBits;
  const __legacyValidateImage = validateImage;

  MCOImageCodec.encodeVersion = 1;
  MCOImageCodec.v2EncodeVersion = 2;
  MCOImageCodec.maxSupportedVersion = 2;
  MCOImageCodec.maxSizeV1 = 85;
  MCOImageCodec.maxSizeV2 = 256;
  MCOImageCodec.v2TransparentProfileFlag = 0x10;
  MCOImageCodec.v2ProfileIdMask = 0x0f;
  MCOImageCodec.maxV2Regions = 32;
  MCOImageCodec.maxDynamicLocalPalette = 64;
  MCOImageCodec.v2BlockModes = Object.freeze([
    ImageMode.rawGlobal,
    ImageMode.rawLocal,
    ImageMode.rleLocal,
    ImageMode.sparseBg,
    ImageMode.biColorMask,
    ImageMode.rowRepeat,
    ImageMode.rowDelta,
  ]);
  MCOImageCodec.dynamicBlockModes = Object.freeze([
    ImageMode.rawLocal,
    ImageMode.rleLocal,
    ImageMode.sparseBg,
    ImageMode.biColorMask,
    ImageMode.rowRepeat,
    ImageMode.rowDelta,
  ]);
  MCOImageCodec.modeTieOrder = Object.freeze([
    ImageMode.biColorMask,
    ImageMode.sparseBg,
    ImageMode.rowRepeat,
    ImageMode.rowDelta,
    ImageMode.rleLocal,
    ImageMode.rawLocal,
    ImageMode.rawGlobal,
    ImageMode.regionsBg,
  ]);

  function normalizeEncodingVersion(version) {
    if (version === undefined || version === null) return MCOImageEncodingVersion.v2;
    if (version === MCOImageEncodingVersion.v1Legacy || version === 'v1' || version === 'v1Legacy' || version === 1) {
      return MCOImageEncodingVersion.v1Legacy;
    }
    if (version === MCOImageEncodingVersion.v2 || version === 'v2' || version === 2) {
      return MCOImageEncodingVersion.v2;
    }
    throw new MCOImageInvalidInputError('Unknown encoding version');
  }

  function isDynamicProfile(profile) {
    return normalizePaletteProfile(profile) >= PaletteProfile.dynamicGlobal8;
  }

  function dynamicProfileSize(profile) {
    return dynamicIndicesFor(profile).length;
  }

  function dynamicProfileColorBits(profile) {
    return bitsForLocalPalette(dynamicProfileSize(profile));
  }

  function dynamicIndicesFor(profile) {
    const normalized = normalizePaletteProfile(profile);
    const indices = DynamicGlobalIndices[normalized];
    if (!indices) throw new MCOImageInvalidInputError('Not a dynamic palette profile');
    return indices;
  }

  function profileColorIdForGlobalIndex(profile, globalIndex) {
    const indices = dynamicIndicesFor(profile);
    for (let i = 0; i < indices.length; i++) {
      if (indices[i] === globalIndex) return i;
    }
    return null;
  }

  function globalIndexForProfileColorId(profile, profileColorId) {
    const indices = dynamicIndicesFor(profile);
    if (profileColorId < 0 || profileColorId >= indices.length) {
      throw new MCOImageInvalidPayloadError('Dynamic palette color id out of range');
    }
    return indices[profileColorId];
  }

  function dynamicPaletteFor(profile) {
    return Object.freeze(dynamicIndicesFor(profile).map((globalIndex) => DynamicGlobal512[globalIndex]));
  }

  function dynamicWhiteIndexFor(profile) {
    const id = profileColorIdForGlobalIndex(profile, 0);
    return id == null ? 0 : 0; // pixel values for dynamic images are global indices
  }

  function dynamicBlackIndexFor(profile) {
    const id = profileColorIdForGlobalIndex(profile, 63);
    return id == null ? 63 : 63; // pixel values for dynamic images are global indices
  }

  function fixedProfileId(profile) {
    switch (normalizePaletteProfile(profile)) {
      case PaletteProfile.mono: return 0;
      case PaletteProfile.master4: return 1;
      case PaletteProfile.master8: return 2;
      case PaletteProfile.grayscale8: return 3;
      case PaletteProfile.master16: return 4;
      case PaletteProfile.grayscale16: return 5;
      case PaletteProfile.master32: return 6;
      case PaletteProfile.grayscale32: return 7;
      case PaletteProfile.master64: return 8;
      default: throw new MCOImageInvalidInputError('Not a fixed palette profile');
    }
  }

  function fixedProfileFromId(id) {
    switch (id) {
      case 0: return PaletteProfile.mono;
      case 1: return PaletteProfile.master4;
      case 2: return PaletteProfile.master8;
      case 3: return PaletteProfile.grayscale8;
      case 4: return PaletteProfile.master16;
      case 5: return PaletteProfile.grayscale16;
      case 6: return PaletteProfile.master32;
      case 7: return PaletteProfile.grayscale32;
      case 8: return PaletteProfile.master64;
      default: throw new MCOImageInvalidPayloadError(`Unknown fixed palette profile ${id}`);
    }
  }

  function dynamicProfileId(profile) {
    switch (normalizePaletteProfile(profile)) {
      case PaletteProfile.dynamicGlobal8: return 0;
      case PaletteProfile.dynamicGlobal16: return 1;
      case PaletteProfile.dynamicGlobal32: return 2;
      case PaletteProfile.dynamicGlobal64: return 3;
      case PaletteProfile.dynamicGlobal128: return 4;
      case PaletteProfile.dynamicGlobal256: return 5;
      case PaletteProfile.dynamicGlobal512: return 6;
      default: throw new MCOImageInvalidInputError('Not a dynamic palette profile');
    }
  }

  function dynamicProfileFromId(id) {
    switch (id) {
      case 0: return PaletteProfile.dynamicGlobal8;
      case 1: return PaletteProfile.dynamicGlobal16;
      case 2: return PaletteProfile.dynamicGlobal32;
      case 3: return PaletteProfile.dynamicGlobal64;
      case 4: return PaletteProfile.dynamicGlobal128;
      case 5: return PaletteProfile.dynamicGlobal256;
      case 6: return PaletteProfile.dynamicGlobal512;
      default: throw new MCOImageInvalidPayloadError(`Unknown dynamic palette profile ${id}`);
    }
  }

  function getPaletteV2Aware(profile) {
    const normalized = normalizePaletteProfile(profile);
    if (isDynamicProfile(normalized)) return dynamicPaletteFor(normalized);
    return __legacyGetPalette(normalized);
  }

  function paletteSizeV2Aware(profile) {
    const normalized = normalizePaletteProfile(profile);
    return isDynamicProfile(normalized) ? dynamicProfileSize(normalized) : __legacyPaletteSize(normalized);
  }

  function globalBitsV2Aware(profile) {
    const normalized = normalizePaletteProfile(profile);
    return isDynamicProfile(normalized) ? dynamicProfileColorBits(normalized) : __legacyGlobalBits(normalized);
  }

  function validateDimensionsAny(width, height, payload = false) {
    const max = MCOImageCodec.maxSizeV2;
    if (width < MCOImageCodec.minSize || height < MCOImageCodec.minSize || width > max || height > max) {
      throw new (payload ? MCOImageInvalidPayloadError : MCOImageInvalidInputError)(
        `Image dimensions must be 1..${max}`,
      );
    }
  }

  function validateColorAny(color, profile, label, payload = false) {
    const normalized = normalizePaletteProfile(profile);
    if (isDynamicProfile(normalized)) {
      if (!Number.isInteger(color) || color < 0 || color >= DynamicGlobal512.length || profileColorIdForGlobalIndex(normalized, color) == null) {
        throw new (payload ? MCOImageInvalidPayloadError : MCOImageInvalidInputError)(
          `${label} is outside selected dynamic palette`,
        );
      }
      return;
    }
    validateColor(color, normalized, label, payload);
  }

  function validateImageAny(image) {
    validateDimensionsAny(image.width, image.height);
    const expected = image.width * image.height;
    if (image.pixels.length !== expected) {
      throw new MCOImageInvalidInputError(`pixels.length must be ${expected}, got ${image.pixels.length}`);
    }
    for (const pixel of image.pixels) validateColorAny(pixel, image.paletteProfile, 'pixel');
    if (image.transparentColor !== null && image.transparentColor !== undefined) {
      validateColorAny(image.transparentColor, image.paletteProfile, 'transparentColor');
    }
  }

  function writeBitVarUint(writer, value) {
    if (value < 0) throw new MCOImageInvalidInputError('Negative bit varuint');
    let current = value;
    do {
      let byte = current & 0x7f;
      current = Math.floor(current / 128);
      if (current !== 0) byte |= 0x80;
      writer.writeBits(byte, 8);
    } while (current !== 0);
  }

  function readBitVarUint(reader, maxBytes = 5) {
    let result = 0;
    let shift = 0;
    for (let i = 0; i < maxBytes; i++) {
      const byte = reader.readBits(8);
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) === 0) return result;
      shift += 7;
    }
    throw new MCOImageInvalidPayloadError('Bit varuint is too long');
  }

  function writeV2ColorRef(writer, profile, color) {
    if (isDynamicProfile(profile)) {
      const id = profileColorIdForGlobalIndex(profile, color);
      if (id == null) throw new MCOImageInvalidInputError(`Color ${color} is not available in dynamic profile`);
      writer.writeBits(id, dynamicProfileColorBits(profile));
      return;
    }
    validateColor(color, profile, 'color');
    writer.writeBits(color, __legacyGlobalBits(profile));
  }

  function readV2ColorRef(reader, profile) {
    if (isDynamicProfile(profile)) {
      const id = reader.readBits(dynamicProfileColorBits(profile));
      if (id >= dynamicProfileSize(profile)) throw new MCOImageInvalidPayloadError('Dynamic color id is outside selected profile');
      return globalIndexForProfileColorId(profile, id);
    }
    const color = reader.readBits(__legacyGlobalBits(profile));
    validateColor(color, profile, 'color', true);
    return color;
  }

  function writeV2Bounds(writer, bounds) {
    writeBitVarUint(writer, bounds.x);
    writeBitVarUint(writer, bounds.y);
    writeBitVarUint(writer, bounds.width);
    writeBitVarUint(writer, bounds.height);
  }

  function readV2Bounds(reader, fullWidth, fullHeight) {
    const bounds = {
      x: readBitVarUint(reader),
      y: readBitVarUint(reader),
      width: readBitVarUint(reader),
      height: readBitVarUint(reader),
    };
    bounds.area = bounds.width * bounds.height;
    if (bounds.width < 0 || bounds.height < 0 || bounds.x + bounds.width > fullWidth || bounds.y + bounds.height > fullHeight) {
      throw new MCOImageInvalidPayloadError('Invalid image bounds');
    }
    return bounds;
  }

  function rowLengthForScan(scan, width, height) {
    return (scan === ScanMode.h || scan === ScanMode.s) ? width : height;
  }

  function writeV2Header(writer, { profile, container, mode, scan, boundsPresent, referenceEncoding, width, height, hasTransparentColor }) {
    writer.writeAlignedByte(
      (MCOImageCodec.v2EncodeVersion << 6) |
      (modeBits(mode) << 3) |
      (scanBits(scan) << 1) |
      (boundsPresent ? 1 : 0)
    );
    writer.writeAlignedByte(
      (isDynamicProfile(profile) ? 0x80 : 0) |
      (container << 6) |
      ((referenceEncoding ?? DynamicPaletteReferenceEncoding.flat) << 5) |
      (hasTransparentColor ? MCOImageCodec.v2TransparentProfileFlag : 0) |
      (isDynamicProfile(profile) ? dynamicProfileId(profile) : fixedProfileId(profile))
    );
    writer.writeAlignedByte(width - 1);
    writer.writeAlignedByte(height - 1);
  }

  function readV2LocalPalette(reader, profile, options = {}) {
    const excludedColor = options.excludedColor;
    const allowEmpty = options.allowEmpty === true;
    const k = readBitVarUint(reader);
    const maxColors = paletteSizeV2Aware(profile);
    if ((!allowEmpty && k === 0) || k > maxColors) {
      throw new MCOImageInvalidPayloadError('Invalid local palette size');
    }
    const colors = [];
    const seen = new Set();
    for (let i = 0; i < k; i++) {
      const color = readV2ColorRef(reader, profile);
      if (color === excludedColor || seen.has(color)) {
        throw new MCOImageInvalidPayloadError('Invalid local palette');
      }
      seen.add(color);
      colors.push(color);
    }
    return colors;
  }

  function writeV2LocalPalette(writer, colors, profile) {
    writeBitVarUint(writer, colors.length);
    for (const color of colors) writeV2ColorRef(writer, profile, color);
  }

  function buildDynamicLocalPalette(profile, profileColorIds, backgroundProfileColorId) {
    const counts = new Map();
    for (const id of profileColorIds) counts.set(id, (counts.get(id) || 0) + 1);
    return Array.from(counts.keys()).sort((a, b) => {
      if (a === backgroundProfileColorId && b !== backgroundProfileColorId) return -1;
      if (b === backgroundProfileColorId && a !== backgroundProfileColorId) return 1;
      const byFrequency = counts.get(b) - counts.get(a);
      if (byFrequency !== 0) return byFrequency;
      return globalIndexForProfileColorId(profile, a) - globalIndexForProfileColorId(profile, b);
    });
  }

  function writeDynamicLocalPalette(writer, profile, profileColorIds, referenceEncoding) {
    if (profileColorIds.length === 0 || profileColorIds.length > MCOImageCodec.maxDynamicLocalPalette) {
      throw new MCOImageInvalidInputError('Invalid dynamic local palette size');
    }
    if (referenceEncoding === DynamicPaletteReferenceEncoding.banked8x64) {
      if (profile !== PaletteProfile.dynamicGlobal512) throw new MCOImageInvalidInputError('Banked palette requires dynamicGlobal512');
      writeBitVarUint(writer, profileColorIds.length);
      const banks = Array.from(new Set(profileColorIds.map((id) => id >> 6))).sort((a, b) => a - b);
      writeBitVarUint(writer, banks.length);
      for (const bank of banks) writer.writeBits(bank, 3);
      const bankBits = bitsForLocalPalette(banks.length);
      for (const id of profileColorIds) {
        writer.writeBits(banks.indexOf(id >> 6), bankBits);
        writer.writeBits(id & 0x3f, 6);
      }
      return;
    }
    writeBitVarUint(writer, profileColorIds.length);
    const bits = dynamicProfileColorBits(profile);
    for (const id of profileColorIds) writer.writeBits(id, bits);
  }

  function readDynamicFlatPalette(reader, profile) {
    const length = readBitVarUint(reader);
    if (length <= 0 || length > MCOImageCodec.maxDynamicLocalPalette || length > dynamicProfileSize(profile)) {
      throw new MCOImageInvalidPayloadError('Invalid dynamic local palette size');
    }
    const bits = dynamicProfileColorBits(profile);
    const ids = [];
    const seen = new Set();
    for (let i = 0; i < length; i++) {
      const id = reader.readBits(bits);
      if (id >= dynamicProfileSize(profile) || seen.has(id)) {
        throw new MCOImageInvalidPayloadError('Invalid dynamic local palette');
      }
      seen.add(id);
      ids.push(id);
    }
    return ids;
  }

  function readDynamicBankedPalette(reader, profile) {
    if (profile !== PaletteProfile.dynamicGlobal512) {
      throw new MCOImageInvalidPayloadError('Banked references require dynamicGlobal512');
    }
    const length = readBitVarUint(reader);
    if (length <= 0 || length > MCOImageCodec.maxDynamicLocalPalette) {
      throw new MCOImageInvalidPayloadError('Invalid dynamic banked palette length');
    }
    const bankCount = readBitVarUint(reader);
    if (bankCount <= 0 || bankCount > 8) throw new MCOImageInvalidPayloadError('Invalid dynamic bank count');
    const banks = [];
    const seenBanks = new Set();
    for (let i = 0; i < bankCount; i++) {
      const bank = reader.readBits(3);
      if (seenBanks.has(bank)) throw new MCOImageInvalidPayloadError('Duplicate dynamic bank');
      seenBanks.add(bank);
      banks.push(bank);
    }
    const bankBits = bitsForLocalPalette(banks.length);
    const ids = [];
    const seen = new Set();
    for (let i = 0; i < length; i++) {
      const bankIndex = reader.readBits(bankBits);
      if (bankIndex >= banks.length) throw new MCOImageInvalidPayloadError('Dynamic bank index out of range');
      const id = (banks[bankIndex] << 6) | reader.readBits(6);
      if (seen.has(id)) throw new MCOImageInvalidPayloadError('Duplicate dynamic palette color');
      seen.add(id);
      ids.push(id);
    }
    return ids;
  }

  function readDynamicLocalPalette(reader, profile, referenceEncoding) {
    const ids = referenceEncoding === DynamicPaletteReferenceEncoding.banked8x64
      ? readDynamicBankedPalette(reader, profile)
      : readDynamicFlatPalette(reader, profile);
    const globalColors = ids.map((id) => globalIndexForProfileColorId(profile, id));
    return { profileColorIds: ids, globalColors };
  }

  function buildSparseSegmentsGeneric(pixels, background) {
    const segments = [];
    let i = 0;
    while (i < pixels.length) {
      while (i < pixels.length && pixels[i] === background) i++;
      if (i >= pixels.length) break;
      const start = i;
      const color = pixels[i];
      while (i < pixels.length && pixels[i] === color) i++;
      segments.push({ start, color, length: i - start });
    }
    return segments;
  }

  function biColorForeground(pixels, background) {
    let foreground = null;
    for (const p of pixels) {
      if (p === background) continue;
      if (foreground === null) foreground = p;
      else if (foreground !== p) return null;
    }
    return foreground;
  }

  function writeBiColorMask(writer, pixels, background, foreground) {
    for (const p of pixels) {
      if (p === background) writer.writeBits(0, 1);
      else if (p === foreground) writer.writeBits(1, 1);
      else throw new MCOImageInvalidInputError('BI_COLOR_MASK cannot encode more than two colors');
    }
  }

  function readBiColorMask(reader, count, background, foreground) {
    const result = new Array(count);
    for (let i = 0; i < count; i++) result[i] = reader.readBits(1) === 0 ? background : foreground;
    return result;
  }

  function writeRowRepeatBody(writer, localPixels, rowLength, localBits) {
    if (rowLength <= 0 || localPixels.length % rowLength !== 0) throw new MCOImageInvalidInputError('Invalid row-repeat geometry');
    if (localPixels.length === 0) return;
    for (let x = 0; x < rowLength; x++) writer.writeBits(localPixels[x], localBits);
    const rowCount = localPixels.length / rowLength;
    for (let row = 1; row < rowCount; row++) {
      const rowStart = row * rowLength;
      const prev = rowStart - rowLength;
      let same = true;
      for (let x = 0; x < rowLength; x++) {
        if (localPixels[rowStart + x] !== localPixels[prev + x]) { same = false; break; }
      }
      writer.writeBits(same ? 1 : 0, 1);
      if (!same) for (let x = 0; x < rowLength; x++) writer.writeBits(localPixels[rowStart + x], localBits);
    }
  }

  function readRowRepeatBody(reader, count, rowLength, localBits) {
    if (rowLength <= 0 || count % rowLength !== 0) throw new MCOImageInvalidPayloadError('Invalid row-repeat geometry');
    if (count === 0) return [];
    const result = new Array(count).fill(0);
    for (let x = 0; x < rowLength; x++) result[x] = reader.readBits(localBits);
    const rowCount = count / rowLength;
    for (let row = 1; row < rowCount; row++) {
      const rowStart = row * rowLength;
      const prev = rowStart - rowLength;
      const repeat = reader.readBits(1) !== 0;
      if (repeat) {
        for (let x = 0; x < rowLength; x++) result[rowStart + x] = result[prev + x];
      } else {
        for (let x = 0; x < rowLength; x++) result[rowStart + x] = reader.readBits(localBits);
      }
    }
    return result;
  }

  const RowDelta = Object.freeze({
    raw: 0, repeat: 1, delta: 2, extended: 3,
    extMask: 0, extSegment: 1, extSameColorMask: 2,
    predSame: 0, predLeft: 1, predRight: 2,
  });

  function copyRowDeltaPredictedRow(result, rowStart, previousStart, row, rowLength, useVirtualBaseRow, predictor) {
    if (row === 0 && useVirtualBaseRow) {
      for (let x = 0; x < rowLength; x++) result[rowStart + x] = 0;
      return;
    }
    for (let x = 0; x < rowLength; x++) {
      let sx = x;
      if (predictor === RowDelta.predLeft) sx = x + 1;
      else if (predictor === RowDelta.predRight) sx = x - 1;
      result[rowStart + x] = (sx >= 0 && sx < rowLength) ? result[previousStart + sx] : 0;
    }
  }

  function readRowDeltaPredictor(reader, row, useVirtualBaseRow, allowShiftPredictors) {
    if (!allowShiftPredictors) return RowDelta.predSame;
    const predictor = reader.readBits(2);
    if ((row === 0 && useVirtualBaseRow && predictor !== RowDelta.predSame) ||
        (predictor !== RowDelta.predSame && predictor !== RowDelta.predLeft && predictor !== RowDelta.predRight)) {
      throw new MCOImageInvalidPayloadError('Invalid row-delta predictor');
    }
    return predictor;
  }

  function readRowDeltaBody(reader, count, rowLength, localBits) {
    if (rowLength <= 0 || count % rowLength !== 0) throw new MCOImageInvalidPayloadError('Invalid row-delta geometry');
    if (count === 0) return [];
    const useVirtualBaseRow = reader.readBits(1) !== 0;
    const allowShiftPredictors = reader.readBits(1) !== 0;
    const positionBits = bitsForLocalPalette(rowLength);
    const result = new Array(count).fill(0);
    const rowCount = count / rowLength;
    const firstDeltaRow = useVirtualBaseRow ? 0 : 1;
    if (!useVirtualBaseRow) {
      for (let x = 0; x < rowLength; x++) result[x] = reader.readBits(localBits);
    }
    for (let row = firstDeltaRow; row < rowCount; row++) {
      const rowStart = row * rowLength;
      const previousStart = rowStart - rowLength;
      const op = reader.readBits(2);
      if (op === RowDelta.raw) {
        for (let x = 0; x < rowLength; x++) result[rowStart + x] = reader.readBits(localBits);
      } else if (op === RowDelta.repeat) {
        copyRowDeltaPredictedRow(result, rowStart, previousStart, row, rowLength, useVirtualBaseRow, RowDelta.predSame);
      } else if (op === RowDelta.delta) {
        const predictor = readRowDeltaPredictor(reader, row, useVirtualBaseRow, allowShiftPredictors);
        copyRowDeltaPredictedRow(result, rowStart, previousStart, row, rowLength, useVirtualBaseRow, predictor);
        const changeCount = readBitVarUint(reader);
        let previousX = -1;
        for (let i = 0; i < changeCount; i++) {
          const x = reader.readBits(positionBits);
          if (x >= rowLength || x <= previousX) throw new MCOImageInvalidPayloadError('Invalid row-delta change position');
          result[rowStart + x] = reader.readBits(localBits);
          previousX = x;
        }
      } else if (op === RowDelta.extended) {
        const predictor = readRowDeltaPredictor(reader, row, useVirtualBaseRow, allowShiftPredictors);
        const extendedOp = reader.readBits(2);
        copyRowDeltaPredictedRow(result, rowStart, previousStart, row, rowLength, useVirtualBaseRow, predictor);
        if (extendedOp === RowDelta.extMask || extendedOp === RowDelta.extSameColorMask) {
          const flags = new Array(rowLength);
          let any = false;
          for (let x = 0; x < rowLength; x++) {
            flags[x] = reader.readBits(1) !== 0;
            any = any || flags[x];
          }
          if (!any) throw new MCOImageInvalidPayloadError('Empty row-delta mask');
          if (extendedOp === RowDelta.extMask) {
            for (let x = 0; x < rowLength; x++) if (flags[x]) result[rowStart + x] = reader.readBits(localBits);
          } else {
            const value = reader.readBits(localBits);
            for (let x = 0; x < rowLength; x++) if (flags[x]) result[rowStart + x] = value;
          }
        } else if (extendedOp === RowDelta.extSegment) {
          const segmentCount = readBitVarUint(reader);
          if (segmentCount <= 0) throw new MCOImageInvalidPayloadError('Empty row-delta segment list');
          const lengthBits = bitsForLocalPalette(rowLength);
          let previousEnd = -1;
          for (let i = 0; i < segmentCount; i++) {
            const x = reader.readBits(positionBits);
            const length = reader.readBits(lengthBits) + 1;
            if (x <= previousEnd || x + length > rowLength) throw new MCOImageInvalidPayloadError('Invalid row-delta segment');
            for (let dx = 0; dx < length; dx++) result[rowStart + x + dx] = reader.readBits(localBits);
            previousEnd = x + length - 1;
          }
        } else {
          throw new MCOImageInvalidPayloadError('Unknown row-delta extended op');
        }
      } else {
        throw new MCOImageInvalidPayloadError('Unknown row-delta row op');
      }
    }
    return result;
  }

  function writeSimpleRowDeltaBody(writer, localPixels, rowLength, localBits) {
    return writeDartRowDeltaBody(writer, localPixels, rowLength, localBits);
  }

  function tryBuildV2BlockBody(linear, profile, mode, referenceEncoding, { rowLength, backgroundColor, writeSparseBackground }) {
    const count = linear.length;
    const writer = new BitWriter();
    const dynamic = isDynamicProfile(profile);
    if (dynamic && referenceEncoding == null) throw new MCOImageInvalidInputError('Dynamic v2 payload requires reference encoding');
    if (!dynamic && referenceEncoding != null) return null;

    if (mode === ImageMode.rawGlobal) {
      if (dynamic) return null;
      for (const p of linear) writer.writeBits(p, __legacyGlobalBits(profile));
      return { payload: writer.toBytes(), localPaletteSize: null, bitsPerLocalPixel: __legacyGlobalBits(profile) };
    }

    if (mode === ImageMode.biColorMask) {
      const foreground = biColorForeground(linear, backgroundColor);
      if (foreground == null) return null;
      if (writeSparseBackground) writeV2ColorRef(writer, profile, backgroundColor);
      writeV2ColorRef(writer, profile, foreground);
      writeBiColorMask(writer, linear, backgroundColor, foreground);
      return { payload: writer.toBytes(), localPaletteSize: 2, bitsPerLocalPixel: 1 };
    }

    let localPalette;
    let mapKey;
    if (dynamic) {
      const ids = [];
      for (const globalIndex of linear) {
        if (mode === ImageMode.sparseBg && globalIndex === backgroundColor) continue;
        const id = profileColorIdForGlobalIndex(profile, globalIndex);
        if (id == null) throw new MCOImageInvalidInputError(`Pixel ${globalIndex} is not available in dynamic profile`);
        ids.push(id);
      }
      const bgId = profileColorIdForGlobalIndex(profile, backgroundColor);
      if (bgId == null) throw new MCOImageInvalidInputError('Background is not available in dynamic profile');
      if (ids.length === 0) return null;
      const localIds = buildDynamicLocalPalette(profile, ids, bgId);
      if (localIds.length > MCOImageCodec.maxDynamicLocalPalette) return null;
      const idToLocal = new Map(localIds.map((id, i) => [id, i]));
      const localBits = bitsForLocalPalette(localIds.length);
      if (mode === ImageMode.sparseBg && writeSparseBackground) writeV2ColorRef(writer, profile, backgroundColor);
      writeDynamicLocalPalette(writer, profile, localIds, referenceEncoding);
      localPalette = localIds.map((id) => globalIndexForProfileColorId(profile, id));
      mapKey = (globalIndex) => idToLocal.get(profileColorIdForGlobalIndex(profile, globalIndex));
      return writeV2LocalBodyAfterPalette(writer, linear, mode, backgroundColor, localPalette, mapKey, localBits, rowLength);
    }

    const sourcePixels = mode === ImageMode.sparseBg ? linear.filter((p) => p !== backgroundColor) : linear;
    if (sourcePixels.length === 0) return null;
    localPalette = buildLocalPalette(sourcePixels);
    if (mode === ImageMode.sparseBg) localPalette = localPalette.filter((p) => p !== backgroundColor);
    if (localPalette.length === 0) return null;
    const localBits = bitsForLocalPalette(localPalette.length);
    if (mode === ImageMode.sparseBg && writeSparseBackground) writeV2ColorRef(writer, profile, backgroundColor);
    writeV2LocalPalette(writer, localPalette, profile);
    const localMap = localIndexMap(localPalette);
    mapKey = (color) => localMap.get(color);
    return writeV2LocalBodyAfterPalette(writer, linear, mode, backgroundColor, localPalette, mapKey, localBits, rowLength);
  }

  function writeV2LocalBodyAfterPalette(writer, linear, mode, backgroundColor, localPalette, mapKey, localBits, rowLength) {
    if (mode === ImageMode.rawLocal) {
      for (const p of linear) writer.writeBits(mapKey(p), localBits);
    } else if (mode === ImageMode.rleLocal) {
      const localPixels = linear.map(mapKey);
      const runs = buildRuns(localPixels);
      writeBitVarUint(writer, runs.length);
      for (const run of runs) {
        writer.writeBits(run.color, localBits);
        writeBitVarUint(writer, run.length);
      }
    } else if (mode === ImageMode.sparseBg) {
      const segments = [];
      let i = 0;
      while (i < linear.length) {
        while (i < linear.length && linear[i] === backgroundColor) i++;
        if (i >= linear.length) break;
        const start = i;
        const color = linear[i];
        while (i < linear.length && linear[i] === color) i++;
        segments.push({ start, color: mapKey(color), length: i - start });
      }
      writeBitVarUint(writer, segments.length);
      let pos = 0;
      for (const seg of segments) {
        writeBitVarUint(writer, seg.start - pos);
        writer.writeBits(seg.color, localBits);
        writeBitVarUint(writer, seg.length);
        pos = seg.start + seg.length;
      }
    } else if (mode === ImageMode.rowRepeat) {
      writeRowRepeatBody(writer, linear.map(mapKey), rowLength, localBits);
    } else if (mode === ImageMode.rowDelta) {
      writeSimpleRowDeltaBody(writer, linear.map(mapKey), rowLength, localBits);
    } else {
      return null;
    }
    return { payload: writer.toBytes(), localPaletteSize: localPalette.length, bitsPerLocalPixel: localBits };
  }

  function tryBuildV2Payload(image, linear, mode, scan, referenceEncoding, { dataWidth, dataHeight, backgroundColor, bounds }) {
    const block = tryBuildV2BlockBody(linear, image.paletteProfile, mode, referenceEncoding, {
      rowLength: rowLengthForScan(scan, dataWidth, dataHeight),
      backgroundColor,
      writeSparseBackground: bounds == null,
    });
    if (block == null && !(bounds != null && bounds.area === 0)) return null;
    const writer = new BitWriter();
    writeV2Header(writer, {
      profile: image.paletteProfile,
      container: MCOImageCodec.containerBlock,
      mode,
      scan,
      boundsPresent: bounds != null,
      referenceEncoding,
      width: image.width,
      height: image.height,
      hasTransparentColor: image.transparentColor != null,
    });
    if (image.transparentColor != null) writeV2ColorRef(writer, image.paletteProfile, image.transparentColor);
    if (bounds != null) {
      writeV2ColorRef(writer, image.paletteProfile, backgroundColor);
      writeV2Bounds(writer, bounds);
      if (bounds.area === 0) {
        return { payload: writer.toBytes(), localPaletteSize: 0, bitsPerLocalPixel: 0 };
      }
    }
    writer.writeAlignedBytes(block.payload);
    return { payload: writer.toBytes(), localPaletteSize: block.localPaletteSize, bitsPerLocalPixel: block.bitsPerLocalPixel };
  }

  function candidateFromV2Payload(payload, mode, scan, options = {}) {
    return {
      text: MCOImageCodec.prefix + base91Encode(payload),
      mode,
      modeName: ImageModeName[mode],
      scan,
      scanName: ScanModeName[scan],
      byteLength: payload.length,
      charLength: MCOImageCodec.prefix.length + base91Encode(payload).length,
      boundsPresent: options.bounds != null,
      boundsX: options.bounds && options.bounds.x,
      boundsY: options.bounds && options.bounds.y,
      boundsWidth: options.bounds && options.bounds.width,
      boundsHeight: options.bounds && options.bounds.height,
      backgroundColor: options.backgroundColor,
      transparentColor: options.transparentColor,
      regionCount: options.regionCount || 0,
      backgroundRank: options.backgroundRank || 0,
      codecVersion: MCOImageCodec.v2EncodeVersion,
      dynamicReferenceEncoding: options.dynamicReferenceEncoding,
      dynamicReferenceEncodingName: options.dynamicReferenceEncoding == null ? null : DynamicPaletteReferenceEncodingName[options.dynamicReferenceEncoding],
      localPaletteSize: options.localPaletteSize,
      bitsPerLocalPixel: options.bitsPerLocalPixel,
      requestedEncodingVersion: options.requestedEncodingVersion || MCOImageEncodingVersion.v2,
      actualEncodingVersion: MCOImageEncodingVersion.v2,
      paletteKind: isDynamicProfile(options.paletteProfile) ? 'dynamic' : 'fixed',
      container: options.container || 'block',
    };
  }

  function debugEncodeV2(image, options = {}) {
    validateImageAny(image);
    const backgroundColor = options.backgroundColor;
    if (backgroundColor != null) validateColorAny(backgroundColor, image.paletteProfile, 'backgroundColor');
    const preferred = backgroundColor ?? image.transparentColor;
    const bgs = backgroundCandidates(image, preferred);
    const refs = isDynamicProfile(image.paletteProfile)
      ? (image.paletteProfile === PaletteProfile.dynamicGlobal512
          ? [DynamicPaletteReferenceEncoding.flat, DynamicPaletteReferenceEncoding.banked8x64]
          : [DynamicPaletteReferenceEncoding.flat])
      : [null];
    const modes = isDynamicProfile(image.paletteProfile) ? MCOImageCodec.dynamicBlockModes : MCOImageCodec.v2BlockModes;
    const candidates = [];
    let best = null;
    for (const bgInfo of bgs) {
      const bg = bgInfo.color;
      const bounds = findBounds(image.pixels, image.width, image.height, bg);
      for (const scan of Object.values(ScanMode)) {
        const linear = toScanOrder(image.pixels, image.width, image.height, scan);
        for (const mode of modes) {
          for (const ref of refs) {
            const payload = tryBuildV2Payload(image, linear, mode, scan, ref, {
              dataWidth: image.width,
              dataHeight: image.height,
              backgroundColor: bg,
            });
            if (!payload) continue;
            const candidate = candidateFromV2Payload(payload.payload, mode, scan, {
              backgroundColor: bg,
              transparentColor: image.transparentColor,
              backgroundRank: bgInfo.rank,
              dynamicReferenceEncoding: ref,
              localPaletteSize: payload.localPaletteSize,
              bitsPerLocalPixel: payload.bitsPerLocalPixel,
              paletteProfile: image.paletteProfile,
            });
            candidates.push(candidate);
            if (isBetterCandidate(candidate, best)) best = candidate;
          }
        }
        if (bounds.area < image.width * image.height) {
          const cropped = cropPixels(image.pixels, image.width, bounds);
          const boundedLinear = toScanOrder(cropped, bounds.width, bounds.height, scan);
          for (const mode of modes) {
            for (const ref of refs) {
              const payload = tryBuildV2Payload(image, boundedLinear, mode, scan, ref, {
                dataWidth: bounds.width,
                dataHeight: bounds.height,
                backgroundColor: bg,
                bounds,
              });
              if (!payload) continue;
              const candidate = candidateFromV2Payload(payload.payload, mode, scan, {
                bounds,
                backgroundColor: bg,
                transparentColor: image.transparentColor,
                backgroundRank: bgInfo.rank,
                dynamicReferenceEncoding: ref,
                localPaletteSize: payload.localPaletteSize,
                bitsPerLocalPixel: payload.bitsPerLocalPixel,
                paletteProfile: image.paletteProfile,
              });
              candidates.push(candidate);
              if (isBetterCandidate(candidate, best)) best = candidate;
            }
          }
        }
      }
    }
    if (!best) throw new MCOImageTooLargeError('Image uses too many colors for local palette');
    return { result: best, candidates: Object.freeze(candidates.slice()) };
  }

  function decodeV2Body(reader, width, height, profile, mode, referenceEncoding, { rowLength, sparseBackgroundColor } = {}) {
    const dynamic = isDynamicProfile(profile);
    const count = width * height;
    let palette, localBits;
    if (dynamic) {
      if (referenceEncoding == null) throw new MCOImageInvalidPayloadError('Dynamic v2 block is missing reference encoding');
      switch (mode) {
        case ImageMode.rawLocal:
        case ImageMode.rleLocal:
        case ImageMode.sparseBg:
        case ImageMode.rowRepeat:
        case ImageMode.rowDelta:
          palette = readDynamicLocalPalette(reader, profile, referenceEncoding).globalColors;
          break;
        case ImageMode.biColorMask: {
          const bg = sparseBackgroundColor ?? readV2ColorRef(reader, profile);
          const fg = readV2ColorRef(reader, profile);
          if (fg === bg) throw new MCOImageInvalidPayloadError('Bi-color foreground equals background');
          return readBiColorMask(reader, count, bg, fg);
        }
        default:
          throw new MCOImageInvalidPayloadError('Unsupported dynamic block mode');
      }
      localBits = bitsForLocalPalette(palette.length);
    } else {
      switch (mode) {
        case ImageMode.rawGlobal:
          return decodeRawGlobal(reader, width, height, profile);
        case ImageMode.rawLocal:
        case ImageMode.rleLocal:
        case ImageMode.rowRepeat:
        case ImageMode.rowDelta:
          palette = readV2LocalPalette(reader, profile);
          break;
        case ImageMode.sparseBg: {
          const bg = sparseBackgroundColor ?? readV2ColorRef(reader, profile);
          palette = readV2LocalPalette(reader, profile, { excludedColor: bg });
          localBits = bitsForLocalPalette(palette.length);
          const segmentCount = readBitVarUint(reader);
          const result = new Array(count).fill(bg);
          let pos = 0;
          for (let i = 0; i < segmentCount; i++) {
            pos += readBitVarUint(reader);
            const index = reader.readBits(localBits);
            if (index >= palette.length) throw new MCOImageInvalidPayloadError('Sparse local color index out of range');
            const length = readBitVarUint(reader);
            if (length <= 0 || pos + length > count) throw new MCOImageInvalidPayloadError('Invalid sparse segment');
            for (let j = 0; j < length; j++) result[pos + j] = palette[index];
            pos += length;
          }
          return result;
        }
        case ImageMode.biColorMask: {
          const bg = sparseBackgroundColor ?? readV2ColorRef(reader, profile);
          const fg = readV2ColorRef(reader, profile);
          if (fg === bg) throw new MCOImageInvalidPayloadError('Bi-color foreground equals background');
          return readBiColorMask(reader, count, bg, fg);
        }
        default:
          throw new MCOImageInvalidPayloadError('Unsupported block mode');
      }
      localBits = bitsForLocalPalette(palette.length);
    }

    if (mode === ImageMode.rawLocal) {
      return Array.from({ length: count }, () => {
        const idx = reader.readBits(localBits);
        if (idx >= palette.length) throw new MCOImageInvalidPayloadError('Local color index out of range');
        return palette[idx];
      });
    }
    if (mode === ImageMode.rleLocal) {
      const runCount = readBitVarUint(reader);
      const result = [];
      for (let i = 0; i < runCount; i++) {
        const idx = reader.readBits(localBits);
        if (idx >= palette.length) throw new MCOImageInvalidPayloadError('RLE color index out of range');
        const len = readBitVarUint(reader);
        if (len <= 0 || result.length + len > count) throw new MCOImageInvalidPayloadError('Invalid RLE length');
        for (let j = 0; j < len; j++) result.push(palette[idx]);
      }
      if (result.length !== count) throw new MCOImageInvalidPayloadError('RLE data does not fill canvas');
      return result;
    }
    if (mode === ImageMode.sparseBg && dynamic) {
      const bg = sparseBackgroundColor ?? readV2ColorRef(reader, profile);
      if (palette.includes(bg)) throw new MCOImageInvalidPayloadError('Invalid dynamic sparse local palette');
      const segmentCount = readBitVarUint(reader);
      const result = new Array(count).fill(bg);
      let pos = 0;
      for (let i = 0; i < segmentCount; i++) {
        pos += readBitVarUint(reader);
        const idx = reader.readBits(localBits);
        if (idx >= palette.length) throw new MCOImageInvalidPayloadError('Dynamic sparse color index out of range');
        const len = readBitVarUint(reader);
        if (len <= 0 || pos + len > count) throw new MCOImageInvalidPayloadError('Invalid dynamic sparse segment');
        for (let j = 0; j < len; j++) result[pos + j] = palette[idx];
        pos += len;
      }
      return result;
    }
    if (mode === ImageMode.rowRepeat) {
      return readRowRepeatBody(reader, count, rowLength, localBits).map((idx) => {
        if (idx >= palette.length) throw new MCOImageInvalidPayloadError('Row-repeat color index out of range');
        return palette[idx];
      });
    }
    if (mode === ImageMode.rowDelta) {
      return readRowDeltaBody(reader, count, rowLength, localBits).map((idx) => {
        if (idx >= palette.length) throw new MCOImageInvalidPayloadError('Row-delta color index out of range');
        return palette[idx];
      });
    }
    throw new MCOImageInvalidPayloadError('Unknown v2 body mode');
  }

  function decodeV2Regions(reader, width, height, profile, referenceEncoding) {
    const background = readV2ColorRef(reader, profile);
    let sharedPalette = null;
    if (isDynamicProfile(profile)) {
      if (referenceEncoding == null) throw new MCOImageInvalidPayloadError('Dynamic v2 regions are missing reference encoding');
      sharedPalette = readDynamicLocalPalette(reader, profile, referenceEncoding).globalColors;
    }
    const regionCount = readBitVarUint(reader);
    if (regionCount <= 0 || regionCount > MCOImageCodec.maxV2Regions) throw new MCOImageInvalidPayloadError('Invalid v2 region count');
    const pixels = new Array(width * height).fill(background);
    const occupied = new Array(width * height).fill(false);
    for (let i = 0; i < regionCount; i++) {
      const region = { x: readBitVarUint(reader), y: readBitVarUint(reader), width: readBitVarUint(reader), height: readBitVarUint(reader) };
      region.area = region.width * region.height;
      if (region.width <= 0 || region.height <= 0 || region.x + region.width > width || region.y + region.height > height) throw new MCOImageInvalidPayloadError('Invalid v2 image region');
      const modeAndScan = reader.readAlignedByte();
      if ((modeAndScan & 0x07) !== 0) throw new MCOImageInvalidPayloadError('Reserved region bits are set');
      const regionMode = modeFromBits((modeAndScan >> 5) & 0x07);
      const regionScan = scanFromBits((modeAndScan >> 3) & 0x03);
      const payloadLength = readBitVarUint(reader);
      const payload = reader.readAlignedBytes(payloadLength);
      const regionReader = new BitReader(payload);
      let linear;
      if (sharedPalette && isDynamicProfile(profile)) {
        linear = decodeV2DynamicRegionBody(regionReader, region.width, region.height, sharedPalette, background, regionMode, { rowLength: rowLengthForScan(regionScan, region.width, region.height) });
      } else {
        linear = decodeV2Body(regionReader, region.width, region.height, profile, regionMode, referenceEncoding, {
          rowLength: rowLengthForScan(regionScan, region.width, region.height),
          sparseBackgroundColor: background,
        });
      }
      regionReader.finish();
      const regionPixels = fromScanOrder(linear, region.width, region.height, regionScan);
      for (let y = 0; y < region.height; y++) {
        for (let x = 0; x < region.width; x++) {
          const target = (region.y + y) * width + region.x + x;
          if (occupied[target]) throw new MCOImageInvalidPayloadError('Overlapping v2 image regions');
          occupied[target] = true;
          pixels[target] = regionPixels[y * region.width + x];
        }
      }
    }
    return pixels;
  }

  function decodeV2DynamicRegionBody(reader, width, height, palette, background, mode, { rowLength }) {
    const count = width * height;
    const localBits = bitsForLocalPalette(palette.length);
    if (mode === ImageMode.rawLocal) {
      return Array.from({ length: count }, () => palette[reader.readBits(localBits)]);
    }
    if (mode === ImageMode.rleLocal) {
      const runCount = readBitVarUint(reader);
      const result = [];
      for (let i = 0; i < runCount; i++) {
        const idx = reader.readBits(localBits);
        const len = readBitVarUint(reader);
        if (idx >= palette.length || len <= 0 || result.length + len > count) throw new MCOImageInvalidPayloadError('Invalid dynamic region RLE');
        for (let j = 0; j < len; j++) result.push(palette[idx]);
      }
      if (result.length !== count) throw new MCOImageInvalidPayloadError('Dynamic region RLE does not fill region');
      return result;
    }
    if (mode === ImageMode.sparseBg) {
      const segmentCount = readBitVarUint(reader);
      const result = new Array(count).fill(background);
      let pos = 0;
      for (let i = 0; i < segmentCount; i++) {
        pos += readBitVarUint(reader);
        const idx = reader.readBits(localBits);
        const len = readBitVarUint(reader);
        if (idx >= palette.length || len <= 0 || pos + len > count) throw new MCOImageInvalidPayloadError('Invalid dynamic region sparse');
        for (let j = 0; j < len; j++) result[pos + j] = palette[idx];
        pos += len;
      }
      return result;
    }
    if (mode === ImageMode.rowRepeat) return readRowRepeatBody(reader, count, rowLength, localBits).map((idx) => palette[idx]);
    if (mode === ImageMode.rowDelta) return readRowDeltaBody(reader, count, rowLength, localBits).map((idx) => palette[idx]);
    if (mode === ImageMode.biColorMask) {
      const idx = reader.readBits(localBits);
      if (idx >= palette.length) throw new MCOImageInvalidPayloadError('Dynamic region bi-color index out of range');
      return readBiColorMask(reader, count, background, palette[idx]);
    }
    throw new MCOImageInvalidPayloadError('Unsupported dynamic region block mode');
  }

  function decodeV2(bytes, header) {
    const mode = modeFromBits((header >> 3) & 0x07);
    const scan = scanFromBits((header >> 1) & 0x03);
    const boundsPresent = (header & 0x01) !== 0;
    const paletteHeader = bytes[1];
    const paletteKind = (paletteHeader >> 7) & 0x01;
    const container = (paletteHeader >> 6) & 0x01;
    const referenceEncoding = ((paletteHeader >> 5) & 0x01) === 0
      ? DynamicPaletteReferenceEncoding.flat
      : DynamicPaletteReferenceEncoding.banked8x64;
    const hasTransparentColor = (paletteHeader & MCOImageCodec.v2TransparentProfileFlag) !== 0;
    const profileId = paletteHeader & MCOImageCodec.v2ProfileIdMask;
    const profile = paletteKind === 1 ? dynamicProfileFromId(profileId) : fixedProfileFromId(profileId);
    const width = bytes[2] + 1;
    const height = bytes[3] + 1;
    validateDimensionsAny(width, height, true);
    const reader = new BitReader(bytes, 4);
    const transparentColor = hasTransparentColor ? readV2ColorRef(reader, profile) : null;
    if (container === MCOImageCodec.containerRegions) {
      if (boundsPresent) throw new MCOImageInvalidPayloadError('Invalid v2 regions header');
      const pixels = decodeV2Regions(reader, width, height, profile, paletteKind === 1 ? referenceEncoding : null);
      reader.finish();
      return new MCOImage({ width, height, paletteProfile: profile, pixels, transparentColor, encodingVersion: MCOImageEncodingVersion.v2 });
    }
    if (boundsPresent) {
      const background = readV2ColorRef(reader, profile);
      const bounds = readV2Bounds(reader, width, height);
      if (bounds.area === 0) {
        reader.finish();
        return new MCOImage({ width, height, paletteProfile: profile, pixels: new Array(width * height).fill(background), transparentColor, encodingVersion: MCOImageEncodingVersion.v2 });
      }
      reader.alignToByte();
      const croppedLinear = decodeV2Body(reader, bounds.width, bounds.height, profile, mode, paletteKind === 1 ? referenceEncoding : null, {
        rowLength: rowLengthForScan(scan, bounds.width, bounds.height),
        sparseBackgroundColor: background,
      });
      reader.finish();
      const cropped = fromScanOrder(croppedLinear, bounds.width, bounds.height, scan);
      return new MCOImage({ width, height, paletteProfile: profile, pixels: insertBounds(width, height, background, cropped, bounds), transparentColor, encodingVersion: MCOImageEncodingVersion.v2 });
    }
    reader.alignToByte();
    const linear = decodeV2Body(reader, width, height, profile, mode, paletteKind === 1 ? referenceEncoding : null, {
      rowLength: rowLengthForScan(scan, width, height),
    });
    reader.finish();
    return new MCOImage({ width, height, paletteProfile: profile, pixels: fromScanOrder(linear, width, height, scan), transparentColor, encodingVersion: MCOImageEncodingVersion.v2 });
  }

  MCOImageCodec.decodeHeaderVersion = function(text) {
    if (!text.startsWith(MCOImageCodec.prefix)) return null;
    try {
      const bytes = base91Decode(text.slice(MCOImageCodec.prefix.length));
      if (bytes.length === 0) return null;
      return (bytes[0] >> 6) & 0x03;
    } catch (_) {
      return null;
    }
  };

  MCOImageCodec.prototype.debugEncode = function(imageLike, options = {}) {
    const image = imageLike instanceof MCOImage ? imageLike : new MCOImage(imageLike);
    const version = normalizeEncodingVersion(options.encodingVersion ?? image.encodingVersion);
    if (version === MCOImageEncodingVersion.v1Legacy) {
      if (image.transparentColor != null) throw new MCOImageInvalidInputError('Legacy v1 encoding does not support transparency');
      if (isDynamicProfile(image.paletteProfile)) throw new MCOImageInvalidInputError('Legacy v1 encoding supports fixed palettes only');
      return __legacyDebugEncode.call(this, image, options);
    }
    return debugEncodeV2(image, options);
  };

  MCOImageCodec.prototype.encode = function(imageLike, options = {}) {
    const diagnostics = this.debugEncode(imageLike, options);
    const maxChars = options.maxChars;
    if (maxChars !== undefined && diagnostics.result.charLength > maxChars) {
      throw new MCOImageTooLargeError(`Encoded image is ${diagnostics.result.charLength} chars, max is ${maxChars}`);
    }
    return diagnostics.result;
  };

  MCOImageCodec.prototype.decode = function(text) {
    if (!text.startsWith(MCOImageCodec.prefix)) throw new MCOImageInvalidPayloadError('Missing im: prefix');
    const bytes = base91Decode(text.slice(MCOImageCodec.prefix.length));
    if (bytes.length < 4) throw new MCOImageInvalidPayloadError('Payload too short');
    const header = bytes[0];
    const version = (header >> 6) & 0x03;
    if (version < MCOImageCodec.minSupportedVersion || version > MCOImageCodec.maxSupportedVersion) {
      throw new MCOImageInvalidPayloadError(`Unsupported version ${version}`);
    }
    if (version === MCOImageCodec.v2EncodeVersion) return decodeV2(bytes, header);
    const image = __legacyDecode.call(this, text);
    image.encodingVersion = MCOImageEncodingVersion.v1Legacy;
    image.transparentColor = null;
    return image;
  };

  // Replace palette helpers with v2-aware variants for exported consumers.
  globalBits = globalBitsV2Aware;
  paletteSize = paletteSizeV2Aware;
  getPalette = getPaletteV2Aware;
  whiteIndexFor = function(profile) {
    const normalized = normalizePaletteProfile(profile);
    if (isDynamicProfile(normalized)) return globalIndexForProfileColorId(normalized, 0);
    return __legacyWhiteIndexFor(normalized);
  };
  blackIndexFor = function(profile) {
    const normalized = normalizePaletteProfile(profile);
    if (isDynamicProfile(normalized)) return DynamicGlobal512.indexOf(0xff000000);
    return __legacyBlackIndexFor(normalized);
  };

  normalizePaletteProfile = function(profile) {
    if (typeof profile === 'string') {
      const idx = PaletteProfileName.indexOf(profile);
      if (idx >= 0) return idx;
    }
    if (typeof profile === 'number' && profile >= 0 && profile < PaletteProfileName.length) return profile;
    throw new MCOImageInvalidInputError('Unknown palette profile');
  };

  validateImage = validateImageAny;

  const __legacyNearestPaletteIndex = nearestPaletteIndex;
  nearestPaletteIndex = function(profile, r, g, b) {
    const palette = getPaletteV2Aware(profile);
    let bestProfileColorId = 0;
    let bestGlobalIndex = 0;
    let bestDistance = Number.POSITIVE_INFINITY;
    const dynamic = isDynamicProfile(profile);
    for (let i = 0; i < palette.length; i++) {
      const color = palette[i];
      const pr = (color >> 16) & 0xff;
      const pg = (color >> 8) & 0xff;
      const pb = color & 0xff;
      const dr = r - pr;
      const dg = g - pg;
      const db = b - pb;
      const distance = dr * dr + dg * dg + db * db;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestProfileColorId = i;
        bestGlobalIndex = dynamic ? globalIndexForProfileColorId(profile, i) : i;
      }
    }
    return dynamic ? bestGlobalIndex : bestProfileColorId;
  };

  drawMCOImage = function(canvas, imageLike, options = {}) {
    const image = imageLike instanceof MCOImage ? imageLike : new MCOImage(imageLike);
    const scale = options.scale || 12;
    canvas.width = image.width * scale;
    canvas.height = image.height * scale;
    const ctx = canvas.getContext('2d');
    ctx.imageSmoothingEnabled = false;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const palette = getPalette(image.paletteProfile);
    const dynamic = isDynamicProfile(image.paletteProfile);
    for (let y = 0; y < image.height; y++) {
      for (let x = 0; x < image.width; x++) {
        const pixel = image.pixels[y * image.width + x];
        if (image.transparentColor != null && pixel === image.transparentColor) continue;
        const paletteIndex = dynamic ? profileColorIdForGlobalIndex(image.paletteProfile, pixel) : pixel;
        const color = palette[paletteIndex ?? 0] ?? 0xff000000;
        ctx.fillStyle = argbToCss(color);
        ctx.fillRect(x * scale, y * scale, scale, scale);
      }
    }
  };
  // ---- End V2 codec extension ---------------------------------------------


  // ---- Dart-parity v2 encoder extension -----------------------------------
  function bitVarUintBitLength(value) {
    if (value < 0) throw new MCOImageInvalidInputError('Negative varuint');
    let bits = 0;
    let current = value;
    do {
      bits += 8;
      current = Math.floor(current / 128);
    } while (current !== 0);
    return bits;
  }

  function rowDeltaSegments(changes) {
    if (changes.length === 0) return [];
    const segments = [];
    let startX = changes[0].x;
    let values = [changes[0].value];
    let previousX = startX;
    for (let i = 1; i < changes.length; i++) {
      const change = changes[i];
      if (change.x === previousX + 1) {
        values.push(change.value);
      } else {
        segments.push({ x: startX, values: values.slice(), length: values.length });
        startX = change.x;
        values = [change.value];
      }
      previousX = change.x;
    }
    segments.push({ x: startX, values: values.slice(), length: values.length });
    return segments;
  }

  function sameRowDeltaChangeValue(changes) {
    if (changes.length === 0) return null;
    const value = changes[0].value;
    for (let i = 1; i < changes.length; i++) {
      if (changes[i].value !== value) return null;
    }
    return value;
  }

  function rowDeltaPredictedValue(localPixels, rowLength, row, x, previousStart, useVirtualBaseRow, predictor) {
    if (row === 0 && useVirtualBaseRow) return 0;
    let sourceX = x;
    if (predictor === RowDelta.predLeft) sourceX = x + 1;
    else if (predictor === RowDelta.predRight) sourceX = x - 1;
    else if (predictor !== RowDelta.predSame) {
      throw new MCOImageInvalidInputError('Invalid row-delta predictor');
    }
    if (sourceX < 0 || sourceX >= rowLength) return 0;
    return localPixels[previousStart + sourceX];
  }

  function rowDeltaChanges(localPixels, rowLength, row, useVirtualBaseRow, predictor) {
    const rowStart = row * rowLength;
    const previousStart = rowStart - rowLength;
    const changes = [];
    for (let x = 0; x < rowLength; x++) {
      const previousValue = rowDeltaPredictedValue(
        localPixels,
        rowLength,
        row,
        x,
        previousStart,
        useVirtualBaseRow,
        predictor,
      );
      const value = localPixels[rowStart + x];
      if (value !== previousValue) changes.push({ x, value });
    }
    return changes;
  }

  function rowDeltaExtendedRowBitCostForOp(changes, rowLength, localBits, extendedOp) {
    if (extendedOp === RowDelta.extMask) {
      return rowLength + changes.length * localBits;
    }
    if (extendedOp === RowDelta.extSegment) {
      const segments = rowDeltaSegments(changes);
      return bitVarUintBitLength(segments.length) +
        segments.length * (bitsForLocalPalette(rowLength) + bitsForLocalPalette(rowLength)) +
        changes.length * localBits;
    }
    if (extendedOp === RowDelta.extSameColorMask) {
      return rowLength + (sameRowDeltaChangeValue(changes) == null ? (1 << 30) : localBits);
    }
    throw new MCOImageInvalidInputError('Invalid row-delta extended op');
  }

  function bestRowDeltaExtendedOp(changes, rowLength, localBits) {
    const maskBits = rowDeltaExtendedRowBitCostForOp(changes, rowLength, localBits, RowDelta.extMask);
    const segmentBits = rowDeltaExtendedRowBitCostForOp(changes, rowLength, localBits, RowDelta.extSegment);
    const sameColorMaskBits = rowDeltaExtendedRowBitCostForOp(changes, rowLength, localBits, RowDelta.extSameColorMask);
    if (sameColorMaskBits <= segmentBits && sameColorMaskBits <= maskBits) return RowDelta.extSameColorMask;
    return segmentBits < maskBits ? RowDelta.extSegment : RowDelta.extMask;
  }

  function rowDeltaDecisionForChanges(changes, rowLength, localBits, predictor, allowShiftPredictors) {
    const predictorBits = allowShiftPredictors ? 2 : 0;
    if (changes.length === 0) {
      if (!allowShiftPredictors || predictor === RowDelta.predSame) {
        return {
          op: RowDelta.repeat,
          extendedOp: -1,
          predictor: RowDelta.predSame,
          changes,
          bitCost: 2,
        };
      }
      return {
        op: RowDelta.delta,
        extendedOp: -1,
        predictor,
        changes,
        bitCost: 2 + predictorBits + bitVarUintBitLength(0),
      };
    }

    const rawCost = 2 + rowLength * localBits;
    const indexedCost =
      2 +
      predictorBits +
      bitVarUintBitLength(changes.length) +
      changes.length * (bitsForLocalPalette(rowLength) + localBits);
    const extendedOp = bestRowDeltaExtendedOp(changes, rowLength, localBits);
    const extendedCost =
      2 +
      predictorBits +
      2 +
      rowDeltaExtendedRowBitCostForOp(changes, rowLength, localBits, extendedOp);

    if (indexedCost < rawCost && indexedCost <= extendedCost) {
      return { op: RowDelta.delta, extendedOp: -1, predictor, changes, bitCost: indexedCost };
    }
    if (extendedCost < rawCost) {
      return { op: RowDelta.extended, extendedOp, predictor, changes, bitCost: extendedCost };
    }
    return {
      op: RowDelta.raw,
      extendedOp: -1,
      predictor: RowDelta.predSame,
      changes,
      bitCost: rawCost,
    };
  }

  function rowDeltaPredictorsForRow(row, useVirtualBaseRow, allowShiftPredictors) {
    if (!allowShiftPredictors || (row === 0 && useVirtualBaseRow)) return [RowDelta.predSame];
    return [RowDelta.predSame, RowDelta.predLeft, RowDelta.predRight];
  }

  function bestRowDeltaDecision(localPixels, rowLength, localBits, row, useVirtualBaseRow, allowShiftPredictors) {
    let best = null;
    for (const predictor of rowDeltaPredictorsForRow(row, useVirtualBaseRow, allowShiftPredictors)) {
      const changes = rowDeltaChanges(localPixels, rowLength, row, useVirtualBaseRow, predictor);
      const decision = rowDeltaDecisionForChanges(
        changes,
        rowLength,
        localBits,
        predictor,
        allowShiftPredictors,
      );
      if (best == null || decision.bitCost < best.bitCost) best = decision;
    }
    return best;
  }

  function rowDeltaBodyVariantBitCost(localPixels, rowLength, localBits, useVirtualBaseRow, allowShiftPredictors) {
    let bits = 0;
    const rowCount = Math.floor(localPixels.length / rowLength);
    const firstDeltaRow = useVirtualBaseRow ? 0 : 1;
    if (!useVirtualBaseRow) bits += rowLength * localBits;
    for (let row = firstDeltaRow; row < rowCount; row++) {
      const decision = bestRowDeltaDecision(
        localPixels,
        rowLength,
        localBits,
        row,
        useVirtualBaseRow,
        allowShiftPredictors,
      );
      bits += decision.bitCost;
    }
    return bits;
  }

  function rowDeltaBodyBitCost(localPixels, rowLength, localBits, allowShiftPredictors) {
    const rawFirstCost = rowDeltaBodyVariantBitCost(localPixels, rowLength, localBits, false, allowShiftPredictors);
    const virtualBaseCost = rowDeltaBodyVariantBitCost(localPixels, rowLength, localBits, true, allowShiftPredictors);
    return {
      rawFirstCost,
      virtualBaseCost,
      bestCost: Math.min(rawFirstCost, virtualBaseCost),
    };
  }

  function writeRowDeltaPredictorIfNeeded(writer, predictor, allowShiftPredictors) {
    if (!allowShiftPredictors) return;
    writer.writeBits(predictor, 2);
  }

  function writeRowDeltaMaskRow(writer, changes, rowLength, localBits) {
    let changeIndex = 0;
    for (let x = 0; x < rowLength; x++) {
      const isChanged = changeIndex < changes.length && changes[changeIndex].x === x;
      writer.writeBits(isChanged ? 1 : 0, 1);
      if (isChanged) changeIndex++;
    }
    for (const change of changes) writer.writeBits(change.value, localBits);
  }

  function writeRowDeltaSameColorMaskRow(writer, changes, rowLength, localBits) {
    const value = sameRowDeltaChangeValue(changes);
    if (value == null) throw new MCOImageInvalidInputError('Row-delta changes are not same-color');
    let changeIndex = 0;
    for (let x = 0; x < rowLength; x++) {
      const isChanged = changeIndex < changes.length && changes[changeIndex].x === x;
      writer.writeBits(isChanged ? 1 : 0, 1);
      if (isChanged) changeIndex++;
    }
    writer.writeBits(value, localBits);
  }

  function writeRowDeltaSegmentRow(writer, changes, rowLength, localBits) {
    const segments = rowDeltaSegments(changes);
    const positionBits = bitsForLocalPalette(rowLength);
    const lengthBits = bitsForLocalPalette(rowLength);
    writeBitVarUint(writer, segments.length);
    for (const segment of segments) {
      writer.writeBits(segment.x, positionBits);
      writer.writeBits(segment.length - 1, lengthBits);
      for (const value of segment.values) writer.writeBits(value, localBits);
    }
  }

  function writeRowDeltaBodyVariant(writer, localPixels, rowLength, localBits, useVirtualBaseRow, allowShiftPredictors) {
    const rowCount = Math.floor(localPixels.length / rowLength);
    const firstDeltaRow = useVirtualBaseRow ? 0 : 1;

    if (!useVirtualBaseRow) {
      for (let x = 0; x < rowLength; x++) writer.writeBits(localPixels[x], localBits);
    }

    for (let row = firstDeltaRow; row < rowCount; row++) {
      const rowStart = row * rowLength;
      const decision = bestRowDeltaDecision(
        localPixels,
        rowLength,
        localBits,
        row,
        useVirtualBaseRow,
        allowShiftPredictors,
      );
      const changes = decision.changes;
      if (changes.length === 0 && decision.op === RowDelta.repeat) {
        writer.writeBits(RowDelta.repeat, 2);
        continue;
      }

      if (decision.op === RowDelta.raw) {
        writer.writeBits(RowDelta.raw, 2);
        for (let x = 0; x < rowLength; x++) writer.writeBits(localPixels[rowStart + x], localBits);
      } else if (decision.op === RowDelta.delta) {
        writer.writeBits(RowDelta.delta, 2);
        writeRowDeltaPredictorIfNeeded(writer, decision.predictor, allowShiftPredictors);
        const positionBits = bitsForLocalPalette(rowLength);
        writeBitVarUint(writer, changes.length);
        let previousX = -1;
        for (const change of changes) {
          if (change.x <= previousX) throw new MCOImageInvalidInputError('Invalid row-delta change order');
          writer.writeBits(change.x, positionBits);
          writer.writeBits(change.value, localBits);
          previousX = change.x;
        }
      } else if (decision.op === RowDelta.extended) {
        writer.writeBits(RowDelta.extended, 2);
        writeRowDeltaPredictorIfNeeded(writer, decision.predictor, allowShiftPredictors);
        writer.writeBits(decision.extendedOp, 2);
        if (decision.extendedOp === RowDelta.extMask) {
          writeRowDeltaMaskRow(writer, changes, rowLength, localBits);
        } else if (decision.extendedOp === RowDelta.extSegment) {
          writeRowDeltaSegmentRow(writer, changes, rowLength, localBits);
        } else if (decision.extendedOp === RowDelta.extSameColorMask) {
          writeRowDeltaSameColorMaskRow(writer, changes, rowLength, localBits);
        } else {
          throw new MCOImageInvalidInputError('Invalid row-delta extended op');
        }
      } else {
        throw new MCOImageInvalidInputError('Invalid row-delta op');
      }
    }
  }

  function writeDartRowDeltaBody(writer, localPixels, rowLength, localBits) {
    if (rowLength <= 0 || localPixels.length % rowLength !== 0) {
      throw new MCOImageInvalidInputError('Invalid row-delta geometry');
    }
    if (localPixels.length === 0) return;

    const noShiftCost = rowDeltaBodyBitCost(localPixels, rowLength, localBits, false);
    const shiftCost = rowDeltaBodyBitCost(localPixels, rowLength, localBits, true);
    const allowShiftPredictors = shiftCost.bestCost < noShiftCost.bestCost;
    const rawFirstCost = allowShiftPredictors ? shiftCost.rawFirstCost : noShiftCost.rawFirstCost;
    const virtualBaseCost = allowShiftPredictors ? shiftCost.virtualBaseCost : noShiftCost.virtualBaseCost;
    const useVirtualBaseRow = virtualBaseCost < rawFirstCost;

    writer.writeBits(useVirtualBaseRow ? 1 : 0, 1);
    writer.writeBits(allowShiftPredictors ? 1 : 0, 1);
    writeRowDeltaBodyVariant(
      writer,
      localPixels,
      rowLength,
      localBits,
      useVirtualBaseRow,
      allowShiftPredictors,
    );
  }

  // Replace the earlier simple row-delta writer with the Dart cost-based one.
  writeSimpleRowDeltaBody = writeDartRowDeltaBody;

  function bestV2BlockPayload(regionPixels, width, height, profile, backgroundColor) {
    let best = null;
    for (const scan of Object.values(ScanMode)) {
      const linear = toScanOrder(regionPixels, width, height, scan);
      for (const mode of MCOImageCodec.v2BlockModes) {
        const block = tryBuildV2BlockBody(linear, profile, mode, null, {
          rowLength: rowLengthForScan(scan, width, height),
          backgroundColor,
          writeSparseBackground: false,
        });
        if (!block) continue;
        const candidate = {
          payload: block.payload,
          mode,
          scan,
          byteLength: block.payload.length,
          localPaletteSize: block.localPaletteSize,
          bitsPerLocalPixel: block.bitsPerLocalPixel,
          container: 'block',
        };
        if (
          best == null ||
          candidate.byteLength < best.byteLength ||
          (candidate.byteLength === best.byteLength &&
            isBetterCandidate(
              candidateFromV2Payload(candidate.payload, candidate.mode, candidate.scan, { container: 'block', paletteProfile: profile }),
              candidateFromV2Payload(best.payload, best.mode, best.scan, { container: 'block', paletteProfile: profile }),
            ))
        ) {
          best = candidate;
        }
      }
    }
    if (!best) throw new MCOImageTooLargeError('Region could not be encoded');
    return best;
  }

  function tryBuildDynamicSharedBlockBody(linear, profile, mode, backgroundColor, localIndexByProfileColorId, rowLength) {
    const writer = new BitWriter();
    const idsForLinear = linear.map((globalIndex) => {
      const id = profileColorIdForGlobalIndex(profile, globalIndex);
      if (id == null) throw new MCOImageInvalidInputError('Dynamic pixel is not available in selected profile');
      const local = localIndexByProfileColorId.get(id);
      if (local == null) throw new MCOImageInvalidInputError('Dynamic pixel is not available in shared palette');
      return local;
    });
    const localBits = bitsForLocalPalette(localIndexByProfileColorId.size);

    if (mode === ImageMode.rawLocal) {
      for (const index of idsForLinear) writer.writeBits(index, localBits);
    } else if (mode === ImageMode.rleLocal) {
      const runs = buildRuns(idsForLinear);
      writeBitVarUint(writer, runs.length);
      for (const run of runs) {
        writer.writeBits(run.color, localBits);
        writeBitVarUint(writer, run.length);
      }
    } else if (mode === ImageMode.sparseBg) {
      const backgroundId = profileColorIdForGlobalIndex(profile, backgroundColor);
      const backgroundLocal = localIndexByProfileColorId.get(backgroundId);
      const segments = [];
      let i = 0;
      while (i < linear.length) {
        while (i < linear.length && idsForLinear[i] === backgroundLocal) i++;
        if (i >= linear.length) break;
        const start = i;
        const color = idsForLinear[i];
        while (i < linear.length && idsForLinear[i] === color) i++;
        segments.push({ start, color, length: i - start });
      }
      writeBitVarUint(writer, segments.length);
      let pos = 0;
      for (const segment of segments) {
        writeBitVarUint(writer, segment.start - pos);
        writer.writeBits(segment.color, localBits);
        writeBitVarUint(writer, segment.length);
        pos = segment.start + segment.length;
      }
    } else if (mode === ImageMode.rowRepeat) {
      writeRowRepeatBody(writer, idsForLinear, rowLength, localBits);
    } else if (mode === ImageMode.rowDelta) {
      writeDartRowDeltaBody(writer, idsForLinear, rowLength, localBits);
    } else if (mode === ImageMode.biColorMask) {
      const foreground = biColorForeground(linear, backgroundColor);
      if (foreground == null) return null;
      const fgId = profileColorIdForGlobalIndex(profile, foreground);
      const fgLocal = localIndexByProfileColorId.get(fgId);
      if (fgLocal == null) return null;
      writer.writeBits(fgLocal, localBits);
      writeBiColorMask(writer, linear, backgroundColor, foreground);
    } else {
      return null;
    }

    return {
      payload: writer.toBytes(),
      localPaletteSize: localIndexByProfileColorId.size,
      bitsPerLocalPixel: localBits,
    };
  }

  function bestV2DynamicSharedBlockPayload(regionPixels, width, height, profile, backgroundColor, localIndexByProfileColorId) {
    let best = null;
    for (const scan of Object.values(ScanMode)) {
      const linear = toScanOrder(regionPixels, width, height, scan);
      for (const mode of MCOImageCodec.dynamicBlockModes) {
        const block = tryBuildDynamicSharedBlockBody(
          linear,
          profile,
          mode,
          backgroundColor,
          localIndexByProfileColorId,
          rowLengthForScan(scan, width, height),
        );
        if (!block) continue;
        const candidate = {
          payload: block.payload,
          mode,
          scan,
          byteLength: block.payload.length,
          localPaletteSize: block.localPaletteSize,
          bitsPerLocalPixel: block.bitsPerLocalPixel,
          container: 'block',
        };
        if (
          best == null ||
          candidate.byteLength < best.byteLength ||
          (candidate.byteLength === best.byteLength &&
            isBetterCandidate(
              candidateFromV2Payload(candidate.payload, candidate.mode, candidate.scan, { container: 'block', paletteProfile: profile }),
              candidateFromV2Payload(best.payload, best.mode, best.scan, { container: 'block', paletteProfile: profile }),
            ))
        ) {
          best = candidate;
        }
      }
    }
    if (!best) throw new MCOImageTooLargeError('Dynamic region could not be encoded');
    return best;
  }

  function splitRegionsByEmptyLines(pixels, fullWidth, background, regions, maxRegions) {
    if (maxRegions === 0 || regions.length === 0) return [];
    const result = [];
    for (const region of regions) {
      splitRegionByEmptyLines(pixels, fullWidth, background, region, result, maxRegions);
      if (result.length > maxRegions) return [];
    }
    result.sort((a, b) => (a.y - b.y) || (a.x - b.x));
    if (result.length === regions.length && sameRegionList(result, regions)) return [];
    return result;
  }

  function splitRegionByEmptyLines(pixels, fullWidth, background, region, out, maxRegions) {
    let y = region.y;
    const yEnd = region.y + region.height;
    while (y < yEnd) {
      while (y < yEnd && isRegionRowEmpty(pixels, fullWidth, background, region, y)) y++;
      if (y >= yEnd) break;
      const startY = y;
      while (y < yEnd && !isRegionRowEmpty(pixels, fullWidth, background, region, y)) y++;
      const height = y - startY;
      out.push({ x: region.x, y: startY, width: region.width, height, area: region.width * height });
      if (out.length > maxRegions) return;
    }
  }

  function isRegionRowEmpty(pixels, fullWidth, background, region, y) {
    for (let x = region.x; x < region.x + region.width; x++) {
      if (pixels[y * fullWidth + x] !== background) return false;
    }
    return true;
  }

  function splitRegionsBySparseLines(pixels, fullWidth, background, regions, maxRegions, maxLineNonBackground) {
    if (maxRegions === 0 || regions.length === 0) return [];
    const result = [];
    for (const region of regions) {
      splitRegionByBestSparseLine(pixels, fullWidth, background, region, result, maxRegions, maxLineNonBackground);
      if (result.length > maxRegions) return [];
    }
    result.sort((a, b) => (a.y - b.y) || (a.x - b.x));
    if (result.length === regions.length && sameRegionList(result, regions)) return [];
    return result;
  }

  function splitRegionByBestSparseLine(pixels, fullWidth, background, region, out, maxRegions, maxLineNonBackground) {
    const splitY = bestSparseSplitLine(pixels, fullWidth, background, region, maxLineNonBackground);
    if (splitY == null) {
      out.push(region);
      return;
    }
    const top = { x: region.x, y: region.y, width: region.width, height: splitY - region.y, area: region.width * (splitY - region.y) };
    const bottomHeight = region.y + region.height - splitY - 1;
    const bottom = { x: region.x, y: splitY + 1, width: region.width, height: bottomHeight, area: region.width * bottomHeight };
    if (top.height > 0) splitRegionByBestSparseLine(pixels, fullWidth, background, top, out, maxRegions, maxLineNonBackground);
    if (bottom.height > 0) splitRegionByBestSparseLine(pixels, fullWidth, background, bottom, out, maxRegions, maxLineNonBackground);
  }

  function bestSparseSplitLine(pixels, fullWidth, background, region, maxLineNonBackground) {
    let bestY = null;
    let bestCount = Number.POSITIVE_INFINITY;
    for (let y = region.y + 1; y < region.y + region.height - 1; y++) {
      let count = 0;
      for (let x = region.x; x < region.x + region.width; x++) {
        if (pixels[y * fullWidth + x] !== background) count++;
      }
      if (count <= maxLineNonBackground && count < bestCount) {
        bestCount = count;
        bestY = y;
      }
    }
    return bestY;
  }

  function sameRegionList(a, b) {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) {
      if (a[i].x !== b[i].x || a[i].y !== b[i].y || a[i].width !== b[i].width || a[i].height !== b[i].height) return false;
    }
    return true;
  }

  function greedyRunLength(pixels, covered, width, background, startX, y, horizontalDirection) {
    let run = 0;
    for (let x = startX; x >= 0 && x < width; x += horizontalDirection) {
      const index = y * width + x;
      if (pixels[index] === background || covered[index]) break;
      run++;
    }
    return run;
  }

  function isBetterGreedyRect(width, height, bestWidth, bestHeight, tieMode) {
    const area = width * height;
    const bestArea = bestWidth * bestHeight;
    if (area !== bestArea) return area > bestArea;
    if (tieMode === 1) return width > bestWidth;
    if (tieMode === 2) return height > bestHeight;
    return height > bestHeight;
  }

  function bestGreedyRectAt(pixels, covered, width, height, background, startX, startY, strategy) {
    let bestWidth = 1;
    let bestHeight = 1;
    let maxCandidateWidth = greedyRunLength(pixels, covered, width, background, startX, startY, strategy.h);
    for (let candidateHeight = 1; ; candidateHeight++) {
      const y = startY + (candidateHeight - 1) * strategy.v;
      if (y < 0 || y >= height) break;
      const rowWidth = greedyRunLength(pixels, covered, width, background, startX, y, strategy.h);
      if (rowWidth === 0) break;
      maxCandidateWidth = Math.min(maxCandidateWidth, rowWidth);
      if (isBetterGreedyRect(maxCandidateWidth, candidateHeight, bestWidth, bestHeight, strategy.tie)) {
        bestWidth = maxCandidateWidth;
        bestHeight = candidateHeight;
      }
    }
    const x = strategy.h > 0 ? startX : startX - bestWidth + 1;
    const y = strategy.v > 0 ? startY : startY - bestHeight + 1;
    return { x, y, width: bestWidth, height: bestHeight, area: bestWidth * bestHeight };
  }

  function findGreedyStartIndex(pixels, covered, width, height, background, strategy) {
    const yStart = strategy.v > 0 ? 0 : height - 1;
    const yEnd = strategy.v > 0 ? height : -1;
    const xStart = strategy.h > 0 ? 0 : width - 1;
    const xEnd = strategy.h > 0 ? width : -1;
    for (let y = yStart; y !== yEnd; y += strategy.v) {
      for (let x = xStart; x !== xEnd; x += strategy.h) {
        const index = y * width + x;
        if (pixels[index] !== background && !covered[index]) return index;
      }
    }
    return -1;
  }

  function findGreedyRectRegionsWithStrategy(pixels, width, height, background, maxRegions, strategy) {
    const covered = new Array(pixels.length).fill(false);
    const regions = [];
    while (true) {
      const startIndex = findGreedyStartIndex(pixels, covered, width, height, background, strategy);
      if (startIndex < 0) break;
      const startX = startIndex % width;
      const startY = Math.floor(startIndex / width);
      const rect = bestGreedyRectAt(pixels, covered, width, height, background, startX, startY, strategy);
      regions.push(rect);
      if (regions.length > maxRegions) return [];
      for (let y = rect.y; y < rect.y + rect.height; y++) {
        for (let x = rect.x; x < rect.x + rect.width; x++) {
          covered[y * width + x] = true;
        }
      }
    }
    regions.sort((a, b) => (a.y - b.y) || (a.x - b.x));
    return regions;
  }

  function regionListKey(regions) {
    return regions.map((r) => `${r.x},${r.y},${r.width},${r.height}`).join(';');
  }

  function findGreedyRectRegionVariants(pixels, width, height, background, maxRegions) {
    if (maxRegions === 0) return [];
    const strategies = [
      { h: 1, v: 1, tie: 0 },
      { h: 1, v: 1, tie: 1 },
      { h: 1, v: 1, tie: 2 },
      { h: -1, v: 1, tie: 0 },
      { h: 1, v: -1, tie: 0 },
      { h: -1, v: -1, tie: 0 },
    ];
    const variants = [];
    const seen = new Set();
    for (const strategy of strategies) {
      const regions = findGreedyRectRegionsWithStrategy(pixels, width, height, background, maxRegions, strategy);
      if (regions.length === 0) continue;
      const key = regionListKey(regions);
      if (!seen.has(key)) {
        seen.add(key);
        variants.push(regions);
      }
    }
    return variants;
  }

  function tryBuildV2RegionsPayloadFromRegions(image, backgroundColor, referenceEncoding, regions, maxRegions) {
    if (regions.length === 0 || regions.length > maxRegions) return null;
    if (isDynamicProfile(image.paletteProfile) && referenceEncoding == null) {
      throw new MCOImageInvalidInputError('Dynamic v2 regions require reference encoding');
    }
    if (!isDynamicProfile(image.paletteProfile) && referenceEncoding != null) return null;

    const writer = new BitWriter();
    writeV2Header(writer, {
      profile: image.paletteProfile,
      container: MCOImageCodec.containerRegions,
      mode: ImageMode.rawGlobal,
      scan: ScanMode.h,
      boundsPresent: false,
      referenceEncoding,
      width: image.width,
      height: image.height,
      hasTransparentColor: image.transparentColor != null,
    });
    if (image.transparentColor != null) writeV2ColorRef(writer, image.paletteProfile, image.transparentColor);
    writeV2ColorRef(writer, image.paletteProfile, backgroundColor);

    let localIndexByProfileColorId = null;
    let usedBankCount = null;
    let bitsPerLocalPixel = null;
    let localPaletteSize = null;

    if (isDynamicProfile(image.paletteProfile)) {
      const allRegionProfileColorIds = [];
      for (const region of regions) {
        const regionPixels = cropPixels(image.pixels, image.width, region);
        for (const globalIndex of regionPixels) {
          const profileColorId = profileColorIdForGlobalIndex(image.paletteProfile, globalIndex);
          if (profileColorId == null) {
            throw new MCOImageInvalidInputError(`Pixel globalIndex ${globalIndex} is not available in dynamic profile`);
          }
          allRegionProfileColorIds.push(profileColorId);
        }
      }
      const backgroundProfileColorId = profileColorIdForGlobalIndex(image.paletteProfile, backgroundColor);
      const localPalette = buildDynamicLocalPalette(
        image.paletteProfile,
        allRegionProfileColorIds,
        backgroundProfileColorId,
      );
      if (localPalette.length === 0 || localPalette.length > MCOImageCodec.maxDynamicLocalPalette) return null;
      writeDynamicLocalPalette(writer, image.paletteProfile, localPalette, referenceEncoding);
      localIndexByProfileColorId = new Map(localPalette.map((id, i) => [id, i]));
      bitsPerLocalPixel = bitsForLocalPalette(localPalette.length);
      localPaletteSize = localPalette.length;
      usedBankCount = referenceEncoding === DynamicPaletteReferenceEncoding.banked8x64
        ? new Set(localPalette.map((id) => id >> 6)).size
        : null;
    }

    writeBitVarUint(writer, regions.length);
    for (const region of regions) {
      const regionPixels = cropPixels(image.pixels, image.width, region);
      const block = isDynamicProfile(image.paletteProfile)
        ? bestV2DynamicSharedBlockPayload(
            regionPixels,
            region.width,
            region.height,
            image.paletteProfile,
            backgroundColor,
            localIndexByProfileColorId,
          )
        : bestV2BlockPayload(regionPixels, region.width, region.height, image.paletteProfile, backgroundColor);

      writeBitVarUint(writer, region.x);
      writeBitVarUint(writer, region.y);
      writeBitVarUint(writer, region.width);
      writeBitVarUint(writer, region.height);
      writer.writeAlignedByte((modeBits(block.mode) << 5) | (scanBits(block.scan) << 3));
      writeBitVarUint(writer, block.payload.length);
      writer.writeAlignedBytes(block.payload);
    }

    return {
      payload: writer.toBytes(),
      regionCount: regions.length,
      localPaletteSize,
      usedBankCount,
      bitsPerLocalPixel,
    };
  }

  function tryBuildV2RegionsPayload(image, backgroundColor, referenceEncoding, maxRegions) {
    if (maxRegions === 0) return null;
    const connectedRegions = findRegions(image.pixels, image.width, image.height, backgroundColor);
    const splitRegions = splitRegionsByEmptyLines(image.pixels, image.width, backgroundColor, connectedRegions, maxRegions);
    const sparseSplitRegions = splitRegionsBySparseLines(
      image.pixels,
      image.width,
      backgroundColor,
      connectedRegions,
      maxRegions,
      2,
    );
    const greedyRegionVariants = findGreedyRectRegionVariants(
      image.pixels,
      image.width,
      image.height,
      backgroundColor,
      maxRegions,
    );

    const variants = [
      connectedRegions,
      ...(splitRegions.length ? [splitRegions] : []),
      ...(sparseSplitRegions.length ? [sparseSplitRegions] : []),
      ...greedyRegionVariants,
    ];

    let best = null;
    for (const regions of variants) {
      const payload = tryBuildV2RegionsPayloadFromRegions(
        image,
        backgroundColor,
        referenceEncoding,
        regions,
        maxRegions,
      );
      if (!payload) continue;
      if (
        best == null ||
        payload.payload.length < best.payload.length ||
        (payload.payload.length === best.payload.length && payload.regionCount < best.regionCount)
      ) {
        best = payload;
      }
    }
    return best;
  }

  function debugEncodeV2Full(image, options = {}) {
    validateImageAny(image);
    let maxRegions = options.maxRegions ?? MCOImageCodec.defaultMaxRegions;
    if (maxRegions < 0) throw new MCOImageInvalidInputError('maxRegions must be >= 0');
    maxRegions = Math.min(maxRegions, MCOImageCodec.maxV2Regions);
    const effectiveMaxRegions = maxRegions > MCOImageCodec.defaultMaxRegions
      ? MCOImageCodec.defaultMaxRegions
      : maxRegions;
    const backgroundColor = options.backgroundColor;
    if (backgroundColor != null) validateColorAny(backgroundColor, image.paletteProfile, 'backgroundColor');
    const preferred = backgroundColor ?? image.transparentColor;
    const bgs = backgroundCandidates(image, preferred);
    const refs = isDynamicProfile(image.paletteProfile)
      ? (image.paletteProfile === PaletteProfile.dynamicGlobal512
          ? [DynamicPaletteReferenceEncoding.flat, DynamicPaletteReferenceEncoding.banked8x64]
          : [DynamicPaletteReferenceEncoding.flat])
      : [null];
    const modes = isDynamicProfile(image.paletteProfile) ? MCOImageCodec.dynamicBlockModes : MCOImageCodec.v2BlockModes;
    const candidates = [];
    let best = null;

    for (const bgInfo of bgs) {
      const bg = bgInfo.color;
      const bounds = findBounds(image.pixels, image.width, image.height, bg);

      for (const ref of refs) {
        const regionsPayload = tryBuildV2RegionsPayload(image, bg, ref, effectiveMaxRegions);
        if (regionsPayload) {
          const candidate = candidateFromV2Payload(
            regionsPayload.payload,
            ImageMode.regionsBg,
            ScanMode.h,
            {
              backgroundColor: bg,
              transparentColor: image.transparentColor,
              backgroundRank: bgInfo.rank,
              regionCount: regionsPayload.regionCount,
              dynamicReferenceEncoding: ref,
              localPaletteSize: regionsPayload.localPaletteSize,
              usedBankCount: regionsPayload.usedBankCount,
              bitsPerLocalPixel: regionsPayload.bitsPerLocalPixel,
              paletteProfile: image.paletteProfile,
              container: 'regions',
            },
          );
          candidates.push(candidate);
          if (isBetterCandidate(candidate, best)) best = candidate;
        }
      }

      for (const scan of Object.values(ScanMode)) {
        const linear = toScanOrder(image.pixels, image.width, image.height, scan);
        for (const mode of modes) {
          for (const ref of refs) {
            const payload = tryBuildV2Payload(image, linear, mode, scan, ref, {
              dataWidth: image.width,
              dataHeight: image.height,
              backgroundColor: bg,
            });
            if (!payload) continue;
            const candidate = candidateFromV2Payload(payload.payload, mode, scan, {
              backgroundColor: bg,
              transparentColor: image.transparentColor,
              backgroundRank: bgInfo.rank,
              dynamicReferenceEncoding: ref,
              localPaletteSize: payload.localPaletteSize,
              bitsPerLocalPixel: payload.bitsPerLocalPixel,
              paletteProfile: image.paletteProfile,
              container: 'block',
            });
            candidates.push(candidate);
            if (isBetterCandidate(candidate, best)) best = candidate;
          }
        }

        if (bounds.area < image.width * image.height) {
          const cropped = cropPixels(image.pixels, image.width, bounds);
          const boundedLinear = toScanOrder(cropped, bounds.width, bounds.height, scan);
          for (const mode of modes) {
            for (const ref of refs) {
              const payload = tryBuildV2Payload(image, boundedLinear, mode, scan, ref, {
                dataWidth: bounds.width,
                dataHeight: bounds.height,
                backgroundColor: bg,
                bounds,
              });
              if (!payload) continue;
              const candidate = candidateFromV2Payload(payload.payload, mode, scan, {
                bounds,
                backgroundColor: bg,
                transparentColor: image.transparentColor,
                backgroundRank: bgInfo.rank,
                dynamicReferenceEncoding: ref,
                localPaletteSize: payload.localPaletteSize,
                bitsPerLocalPixel: payload.bitsPerLocalPixel,
                paletteProfile: image.paletteProfile,
                container: 'block',
              });
              candidates.push(candidate);
              if (isBetterCandidate(candidate, best)) best = candidate;
            }
          }
        }
      }
    }

    if (!best) throw new MCOImageTooLargeError('Image uses too many colors for local palette');
    return { result: best, candidates: Object.freeze(candidates.slice()) };
  }

  MCOImageCodec.prototype.debugEncode = function(imageLike, options = {}) {
    const image = imageLike instanceof MCOImage ? imageLike : new MCOImage(imageLike);
    const version = normalizeEncodingVersion(options.encodingVersion ?? image.encodingVersion);
    if (version === MCOImageEncodingVersion.v1Legacy) {
      if (image.transparentColor != null) throw new MCOImageInvalidInputError('Legacy v1 encoding does not support transparency');
      if (isDynamicProfile(image.paletteProfile)) throw new MCOImageInvalidInputError('Legacy v1 encoding supports fixed palettes only');
      return __legacyDebugEncode.call(this, image, options);
    }
    return debugEncodeV2Full(image, options);
  };
  // ---- End Dart-parity v2 encoder extension -------------------------------

  global.MCOImg = Object.freeze({
    PaletteProfile,
    PaletteProfileName,
    PaletteDisplayOrder,
    PaletteDisplayName,
    ImageMode,
    ImageModeName,
    ScanMode,
    ScanModeName,
    DynamicPaletteReferenceEncoding,
    DynamicPaletteReferenceEncodingName,
    MCOImageEncodingVersion,
    DynamicGlobal512,
    DynamicGlobalIndices,
    MCOImagePalettes,
    MCOImageCodecError,
    MCOImageInvalidInputError,
    MCOImageInvalidPayloadError,
    MCOImageTooLargeError,
    MCOImage,
    MCOImageCodec,
    globalBits,
    paletteSize,
    getPalette,
    whiteIndexFor,
    blackIndexFor,
    normalizePaletteProfile,
    base91Encode,
    base91Decode,
    argbToCss,
    drawMCOImage,
    nearestPaletteIndex,
  });
})(typeof window !== 'undefined' ? window : globalThis);

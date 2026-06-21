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
    extended: 8,
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
    'extended',
  ]);

  const ExtendedImageMode = Object.freeze({
    wrappedBlock: 0,
    solidRects: 1,
    compactRle: 2,
    compactSparse: 3,
    lzPixels: 4,
    quadtree: 5,
    bitplanes: 6,
    compactRowDelta: 7,
  });

  const ExtendedImageModeName = Object.freeze([
    'wrappedBlock',
    'solidRects',
    'compactRle',
    'compactSparse',
    'lzPixels',
    'quadtree',
    'bitplanes',
    'compactRowDelta',
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
    sortedDelta: 2,
    rangeRuns: 3,
    profileBitmap: 4,
    bankBitmaps: 5,
  });

  const DynamicPaletteReferenceEncodingName = Object.freeze([
    'flat',
    'banked8x64',
    'sortedDelta',
    'rangeRuns',
    'profileBitmap',
    'bankBitmaps',
  ]);

  const MCOImageEncodingVersion = Object.freeze({
    v1Legacy: 1,
    v2: 2,
  });

  const MCOImageOutputTarget = Object.freeze({
    text: 'text',
    binary: 'binary',
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

  // Generated from lib/helpers/mcoimg_dynamic_palettes.dart. Keep this table in
  // lockstep with the Dart codec; palette IDs are part of the wire format.
  const DynamicGlobal512Current = Object.freeze([4294967295, 4294038451, 4292324995, 4290479965, 4288373566, 4286335277, 4284363551, 4282458390, 4280619275, 4292467161, 4294962661, 4294960595, 4294957254, 4294495423, 4294229925, 4293638287, 4292913540, 4291991419, 4289967027, 4294956768, 4294958280, 4294963896, 4291685583, 4291423984, 4291747322, 4292924148, 4293578723, 4287269770, 4293189806, 4291479427, 4289374559, 4287204163, 4285362484, 4283651625, 4282006558, 4280493078, 4285493103, 4294963640, 4294959242, 4294232413, 4292718391, 4291072804, 4288508184, 4285812751, 4282986504, 4283387727, 4290376680, 4286766543, 4283351989, 4280788119, 4279665785, 4279133020, 4278731839, 4278396450, 4280558628, 4294230184, 4293368700, 4292114007, 4290336318, 4288036141, 4285672226, 4283374616, 4281011725, 4278190080, 4294946979, 4294636520, 4293911506, 4293054905, 4292067234, 4290947463, 4289368175, 4287460956, 4285488201, 4294941321, 4294959298, 4294230687, 4292846974, 4291332450, 4289358665, 4286730298, 4284167466, 4281671707, 4294923585, 4287466893, 4288980132, 4284900966, 4294917924, 4294851101, 4294849558, 4294848270, 4294846727, 4294845440, 4294517504, 4294189824, 4293861888, 4293533952, 4293206273, 4292878337, 4292550401, 4292222721, 4291894785, 4291435777, 4290976769, 4290517761, 4290058753, 4289534208, 4289075200, 4288616192, 4288157184, 4287698176, 4287370240, 4287042304, 4286649088, 4286321152, 4285993217, 4285665281, 4285272065, 4284944129, 4284616193, 4284419585, 4284222721, 4283960577, 4283763713, 4283567104, 4283370240, 4283108096, 4282911232, 4282714624, 4294947683, 4294947425, 4294947168, 4294946654, 4294946397, 4294946139, 4294945882, 4294945368, 4294945111, 4294944853, 4294944337, 4294943565, 4294943050, 4294942534, 4294941762, 4294941246, 4294940731, 4294939959, 4294939443, 4294938925, 4294938664, 4294938146, 4294937628, 4294937367, 4294936849, 4294936331, 4294936070, 4294935552, 4294738432, 4294541568, 4294344448, 4294147584, 4293950465, 4293753601, 4293556481, 4293359617, 4293162497, 4292965377, 4292702721, 4292505857, 4292243201, 4292046081, 4291783425, 4291586561, 4291323905, 4291126785, 4290732801, 4290338817, 4289944577, 4289550593, 4289091072, 4288697088, 4288302848, 4287908864, 4287514880, 4287383552, 4287252224, 4287120896, 4286989568, 4286792704, 4286661376, 4286530048, 4286398720, 4286267392, 4294436210, 4294435951, 4294435693, 4294370154, 4294369896, 4294369637, 4294369379, 4294303840, 4294303582, 4294303323, 4294303057, 4294236999, 4294236733, 4294170675, 4294170408, 4294104350, 4294104084, 4294038026, 4294037760, 4293906176, 4293774592, 4293643265, 4293511681, 4293380097, 4293248513, 4293117186, 4292985602, 4292854018, 4292722434, 4292590850, 4292393986, 4292262402, 4292130817, 4291999233, 4291802369, 4291670785, 4291539201, 4291407617, 4291210497, 4291078657, 4290881537, 4290749954, 4290552834, 4290420994, 4290223874, 4290092290, 4289829122, 4289566210, 4289303042, 4289039874, 4288711426, 4288448258, 4288185090, 4287922178, 4287659010, 4287461890, 4287330306, 4287133186, 4286936066, 4286804226, 4286607106, 4286409986, 4286278402, 4286081282, 4290242203, 4289979799, 4289717139, 4289520271, 4289257867, 4288995206, 4288732802, 4288535934, 4288273274, 4288010870, 4287748465, 4287420268, 4287157864, 4286829667, 4286567262, 4286239065, 4285976661, 4285648464, 4285386059, 4285123651, 4284860986, 4284533042, 4284270378, 4284007969, 4283745305, 4283417361, 4283154696, 4282892288, 4282826240, 4282825728, 4282759936, 4282693888, 4282693376, 4282627328, 4282561536, 4282561024, 4282494976, 4282428672, 4282362368, 4282230528, 4282164224, 4282097665, 4282031361, 4281899521, 4281833217, 4281766913, 4281634817, 4281568257, 4281435905, 4281369345, 4281237248, 4281170688, 4281038336, 4280971776, 4280839680, 4280773376, 4280706816, 4280574976, 4280508416, 4280442112, 4280375552, 4280243712, 4280177152, 4280110848, 4291097087, 4290900223, 4290703359, 4290572031, 4290375167, 4290178559, 4289981695, 4289850367, 4289653503, 4289456639, 4289128703, 4288800511, 4288472575, 4288144383, 4287881983, 4287553791, 4287225855, 4286897663, 4286569727, 4285651455, 4284733183, 4283815167, 4282896895, 4281978623, 4281060351, 4280142335, 4279224063, 4278305791, 4278305533, 4278305019, 4278304761, 4278304247, 4278238454, 4278237940, 4278237682, 4278237168, 4278236910, 4278236652, 4278236139, 4278235881, 4278235623, 4278300646, 4278300388, 4278300130, 4278299617, 4278299359, 4278298587, 4278297814, 4278362322, 4278361550, 4278360777, 4278360005, 4278424513, 4278423740, 4278422968, 4278421939, 4278421167, 4278354602, 4278353830, 4278352801, 4278352029, 4278285464, 4278284692, 4278283663, 4287736575, 4287539455, 4287342335, 4287144959, 4286947839, 4286685183, 4286488063, 4286290687, 4286093567, 4285896447, 4285501695, 4285041663, 4284646911, 4284186879, 4283792127, 4283332095, 4282937343, 4282214911, 4282082559, 4281622527, 4281228287, 4280768255, 4280373759, 4279913983, 4279519487, 4279059455, 4278665215, 4278205183, 4278204924, 4278204664, 4278270197, 4278269938, 4278269678, 4278269419, 4278334952, 4278334692, 4278334433, 4278334174, 4278334172, 4278333913, 4278333911, 4278333652, 4278333650, 4278333391, 4278333389, 4278333130, 4278332871, 4278332868, 4278332609, 4278332350, 4278266812, 4278266553, 4278266294, 4278266291, 4278266032, 4278265773, 4278265770, 4278265511, 4278265252, 4278199714, 4278199455, 4278199196, 4278199193, 4278198934, 4292326143, 4292062719, 4291799295, 4291536127, 4291272703, 4290943743, 4290680319, 4290417151, 4290153727, 4289890303, 4289692671, 4289560575, 4289363199, 4289165567, 4289033471, 4288835839, 4288638463, 4288506367, 4288308735, 4288176639, 4287978751, 4287846655, 4287714303, 4287516671, 4287384319, 4287252223, 4287054335, 4286922239, 4286854911, 4286722047, 4286654975, 4286587647, 4286454783, 4286387455, 4286320383, 4286187519, 4286120191, 4285989115, 4285858039, 4285792756, 4285661680, 4285530604, 4285399528, 4285334245, 4285137123, 4285072093, 4284941016, 4284744403, 4284613326, 4284416713, 4284285379, 4284088766, 4283957689, 4283761076, 4283629999, 4283367847, 4283105694, 4282843542, 4282581390, 4282318981, 4282056829, 4281794677, 4281532524, 4281270372]);
  const DynamicGlobalIndicesCurrent = Object.freeze({
    [PaletteProfile.dynamicGlobal8]: Object.freeze([0, 83, 63, 91, 210, 283, 401, 484]),
    [PaletteProfile.dynamicGlobal16]: Object.freeze([0, 84, 63, 100, 118, 155, 191, 210, 246, 292, 310, 338, 411, 447, 492, 511]),
    [PaletteProfile.dynamicGlobal32]: Object.freeze([0, 18, 85, 63, 64, 82, 91, 118, 128, 155, 173, 182, 201, 210, 237, 255, 265, 283, 310, 319, 320, 347, 374, 383, 393, 411, 429, 447, 448, 457, 475, 511]),
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
      payload: payload.slice(),
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

  function isBetterCandidate(candidate, current, outputTarget = MCOImageOutputTarget.text) {
    if (current == null) return true;
    const candidateLength = outputTarget === MCOImageOutputTarget.binary
      ? candidate.byteLength
      : candidate.charLength;
    const currentLength = outputTarget === MCOImageOutputTarget.binary
      ? current.byteLength
      : current.charLength;
    if (candidateLength !== currentLength) {
      return candidateLength < currentLength;
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

  function buildLocalPalette(pixels, preferredFirstColor = null) {
    const counts = new Map();
    for (const pixel of pixels) counts.set(pixel, (counts.get(pixel) ?? 0) + 1);
    return Array.from(counts.keys()).sort((a, b) => {
      if (preferredFirstColor !== null) {
        if (a === preferredFirstColor && b !== preferredFirstColor) return -1;
        if (b === preferredFirstColor && a !== preferredFirstColor) return 1;
      }
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
      case ImageMode.extended: return 7;
      case ImageMode.regionsBg:
        throw new MCOImageInvalidInputError('REGIONS_BG has no block mode bits');
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
      case 7: return ImageMode.extended;
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
    ImageMode.extended,
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
    const indices = DynamicGlobalIndicesCurrent[normalized];
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
    return Object.freeze(dynamicIndicesFor(profile).map((globalIndex) => DynamicGlobal512Current[globalIndex]));
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
      if (!Number.isInteger(color) || color < 0 || color >= DynamicGlobal512Current.length || profileColorIdForGlobalIndex(normalized, color) == null) {
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

  function writeV2Header(writer, {
    profile,
    container,
    mode,
    scan,
    boundsPresent,
    referenceEncoding,
    width,
    height,
    hasTransparentColor,
    implicitWhiteBackground = false,
    sharedFixedRegionsPalette = false,
    unalignedExtendedBody = false,
  }) {
    const dynamic = isDynamicProfile(profile);
    const fixedBlockExtension = !dynamic &&
      container === MCOImageCodec.containerBlock &&
      mode !== ImageMode.rawGlobal &&
      (implicitWhiteBackground || unalignedExtendedBody);
    const contextBit = sharedFixedRegionsPalette ||
      fixedBlockExtension ||
      referenceEncoding === DynamicPaletteReferenceEncoding.banked8x64;
    writer.writeAlignedByte(
      (MCOImageCodec.v2EncodeVersion << 6) |
      (modeBits(mode) << 3) |
      (scanBits(scan) << 1) |
      (boundsPresent ? 1 : 0)
    );
    writer.writeAlignedByte(
      (dynamic ? 0x80 : 0) |
      (container << 6) |
      (contextBit ? 0x20 : 0) |
      (hasTransparentColor ? MCOImageCodec.v2TransparentProfileFlag : 0) |
      (dynamic
        ? dynamicProfileId(profile) | (implicitWhiteBackground ? 0x08 : 0)
        : fixedProfileId(profile))
    );
    writer.writeAlignedByte(width - 1);
    writer.writeAlignedByte(height - 1);
    if (fixedBlockExtension) {
      writer.writeBits(
        (implicitWhiteBackground ? 1 : 0) |
        (unalignedExtendedBody ? 2 : 0),
        2,
      );
    }
  }

  function readV2LocalPalette(reader, profile, options = {}) {
    const excludedColor = options.excludedColor;
    const allowEmpty = options.allowEmpty === true;
    const k = readBitVarUint(reader);
    if (k === 0 && !allowEmpty) {
      return readV2FixedPaletteDescriptor(reader, profile, excludedColor);
    }
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
    if (referenceEncoding === DynamicPaletteReferenceEncoding.sortedDelta) {
      writeBitVarUint(writer, 0);
      writer.writeBits(0, 2);
      writer.writeBits(profileColorIds.length - 1, 6);
      writer.writeBits(profileColorIds[0], dynamicProfileColorBits(profile));
      for (let i = 1; i < profileColorIds.length; i++) {
        writeCompactUint(writer, profileColorIds[i] - profileColorIds[i - 1] - 1);
      }
      return;
    }
    if (referenceEncoding === DynamicPaletteReferenceEncoding.rangeRuns) {
      writeBitVarUint(writer, 0);
      writer.writeBits(1, 2);
      const runs = [];
      let start = profileColorIds[0], previous = start;
      for (let i = 1; i < profileColorIds.length; i++) {
        if (profileColorIds[i] === previous + 1) previous = profileColorIds[i];
        else { runs.push({ start, length: previous - start + 1 }); start = previous = profileColorIds[i]; }
      }
      runs.push({ start, length: previous - start + 1 });
      writeCompactUint(writer, runs.length - 1);
      let previousEnd = -1;
      for (let i = 0; i < runs.length; i++) {
        const run = runs[i];
        if (i === 0) writer.writeBits(run.start, dynamicProfileColorBits(profile));
        else writeCompactUint(writer, run.start - previousEnd - 1);
        writeCompactUint(writer, run.length - 1);
        previousEnd = run.start + run.length - 1;
      }
      return;
    }
    if (referenceEncoding === DynamicPaletteReferenceEncoding.profileBitmap) {
      writeBitVarUint(writer, 0);
      writer.writeBits(2, 2);
      const selected = new Set(profileColorIds);
      for (let id = 0; id < dynamicProfileSize(profile); id++) writer.writeBits(selected.has(id) ? 1 : 0, 1);
      return;
    }
    if (referenceEncoding === DynamicPaletteReferenceEncoding.bankBitmaps) {
      if (profile !== PaletteProfile.dynamicGlobal512) return;
      writeBitVarUint(writer, 0);
      writer.writeBits(3, 2);
      const selected = new Set(profileColorIds);
      let bankMask = 0;
      for (const id of profileColorIds) bankMask |= 1 << (id >> 6);
      writer.writeBits(bankMask, 8);
      for (let bank = 0; bank < 8; bank++) {
        if ((bankMask & (1 << bank)) === 0) continue;
        for (let offset = 0; offset < 64; offset++) writer.writeBits(selected.has((bank << 6) | offset) ? 1 : 0, 1);
      }
      return;
    }
    if (referenceEncoding === DynamicPaletteReferenceEncoding.banked8x64) {
      if (profile !== PaletteProfile.dynamicGlobal512) throw new MCOImageInvalidInputError('Banked palette requires dynamicGlobal512');
      writeBitVarUint(writer, profileColorIds.length);
      const banks = Array.from(new Set(profileColorIds.map((id) => id >> 6))).sort((a, b) => a - b);
      writeBitVarUint(writer, banks.length);
      for (const bank of banks) writer.writeBits(bank, 3);
      const bankBits = bitsForChoiceCount(banks.length);
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
    const globalColors = readDynamicLocalPaletteCurrent(reader, profile, referenceEncoding);
    return {
      profileColorIds: globalColors.map((color) => profileColorIdForGlobalIndex(profile, color)),
      globalColors,
    };
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
      if (referenceEncoding >= DynamicPaletteReferenceEncoding.sortedDelta) {
        localIds.sort((a, b) => a - b);
      }
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
    localPalette = buildLocalPalette(sourcePixels, backgroundColor);
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
    const backgroundCanBeImplicit = isImplicitWhite(image.paletteProfile, backgroundColor) &&
      (isDynamicProfile(image.paletteProfile) || __legacyGlobalBits(image.paletteProfile) > 2);
    const implicitWhiteBackground = backgroundCanBeImplicit &&
      (bounds != null || mode === ImageMode.sparseBg || mode === ImageMode.biColorMask);
    const block = tryBuildV2BlockBody(linear, image.paletteProfile, mode, referenceEncoding, {
      rowLength: rowLengthForScan(scan, dataWidth, dataHeight),
      backgroundColor,
      writeSparseBackground: bounds == null && !implicitWhiteBackground,
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
      implicitWhiteBackground,
    });
    if (image.transparentColor != null) writeV2ColorRef(writer, image.paletteProfile, image.transparentColor);
    if (bounds != null) {
      if (!implicitWhiteBackground) writeV2ColorRef(writer, image.paletteProfile, backgroundColor);
      writeV2Bounds(writer, bounds);
      if (bounds.area === 0) {
        return { payload: writer.toBytes(), localPaletteSize: 0, bitsPerLocalPixel: 0 };
      }
    }
    writer.writeAlignedBytes(block.payload);
    return { payload: writer.toBytes(), localPaletteSize: block.localPaletteSize, bitsPerLocalPixel: block.bitsPerLocalPixel };
  }

  function candidateFromV2Payload(payload, mode, scan, options = {}) {
    const text = MCOImageCodec.prefix + base91Encode(payload);
    return {
      payload: payload.slice(),
      text,
      mode,
      modeName: ImageModeName[mode],
      scan,
      scanName: ScanModeName[scan],
      byteLength: payload.length,
      charLength: text.length,
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
          ? [
              DynamicPaletteReferenceEncoding.flat,
              DynamicPaletteReferenceEncoding.banked8x64,
              DynamicPaletteReferenceEncoding.sortedDelta,
              DynamicPaletteReferenceEncoding.rangeRuns,
              DynamicPaletteReferenceEncoding.profileBitmap,
              DynamicPaletteReferenceEncoding.bankBitmaps,
            ]
          : [
              DynamicPaletteReferenceEncoding.flat,
              DynamicPaletteReferenceEncoding.sortedDelta,
              DynamicPaletteReferenceEncoding.rangeRuns,
              DynamicPaletteReferenceEncoding.profileBitmap,
            ])
      : [null];
    const modes = isDynamicProfile(image.paletteProfile) ? MCOImageCodec.dynamicBlockModes : MCOImageCodec.v2BlockModes;
    const candidates = [];
    let best = null;
    const outputTarget = options.outputTarget ?? MCOImageOutputTarget.text;
    for (const bgInfo of bgs) {
      const bg = bgInfo.color;
      const bounds = findBounds(image.pixels, image.width, image.height, bg);
      for (const scan of Object.values(ScanMode)) {
        const linear = toScanOrder(image.pixels, image.width, image.height, scan);
        for (const ref of refs) {
          for (const submode of [
            ExtendedImageMode.compactRle,
            ExtendedImageMode.compactSparse,
            ExtendedImageMode.lzPixels,
            ExtendedImageMode.quadtree,
            ExtendedImageMode.bitplanes,
          ]) {
            const payload = tryBuildExtendedPayload(image, linear, scan, ref, {
              dataWidth: image.width,
              dataHeight: image.height,
              backgroundColor: bg,
              submode,
            });
            if (!payload) continue;
            const candidate = candidateFromV2Payload(payload.payload, ImageMode.extended, scan, {
              backgroundColor: bg,
              transparentColor: image.transparentColor,
              backgroundRank: bgInfo.rank,
              dynamicReferenceEncoding: ref,
              localPaletteSize: payload.localPaletteSize,
              bitsPerLocalPixel: payload.bitsPerLocalPixel,
              paletteProfile: image.paletteProfile,
              container: ExtendedImageModeName[submode],
            });
            candidates.push(candidate);
            if (isBetterCandidate(candidate, best, outputTarget)) best = candidate;
          }
        }
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
          for (const ref of refs) {
            for (const submode of [
              ExtendedImageMode.compactRle,
              ExtendedImageMode.compactSparse,
              ExtendedImageMode.lzPixels,
              ExtendedImageMode.quadtree,
              ExtendedImageMode.bitplanes,
            ]) {
              const payload = tryBuildExtendedPayload(image, boundedLinear, scan, ref, {
                dataWidth: bounds.width,
                dataHeight: bounds.height,
                backgroundColor: bg,
                bounds,
                submode,
              });
              if (!payload) continue;
              const candidate = candidateFromV2Payload(payload.payload, ImageMode.extended, scan, {
                bounds,
                backgroundColor: bg,
                transparentColor: image.transparentColor,
                backgroundRank: bgInfo.rank,
                dynamicReferenceEncoding: ref,
                localPaletteSize: payload.localPaletteSize,
                bitsPerLocalPixel: payload.bitsPerLocalPixel,
                paletteProfile: image.paletteProfile,
                container: `${ExtendedImageModeName[submode]}-bounds`,
              });
              candidates.push(candidate);
              if (isBetterCandidate(candidate, best, outputTarget)) best = candidate;
            }
          }
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

  function bitsForChoiceCount(count) {
    if (count <= 1) return 0;
    return Math.ceil(Math.log2(count));
  }

  function readCompactUint(reader) {
    if (reader.readBits(1) === 0) return reader.readBits(2);
    if (reader.readBits(1) === 0) return reader.readBits(4) + 4;
    if (reader.readBits(1) === 0) return reader.readBits(8) + 20;
    return readBitVarUint(reader);
  }

  function readV2CompactBounds(reader, fullWidth, fullHeight) {
    const x = reader.readBits(bitsForChoiceCount(fullWidth));
    const y = reader.readBits(bitsForChoiceCount(fullHeight));
    if (x >= fullWidth || y >= fullHeight) {
      throw new MCOImageInvalidPayloadError('Invalid compact bounds');
    }
    const width = reader.readBits(bitsForChoiceCount(fullWidth - x)) + 1;
    const height = reader.readBits(bitsForChoiceCount(fullHeight - y)) + 1;
    if (x + width > fullWidth || y + height > fullHeight) {
      throw new MCOImageInvalidPayloadError('Invalid compact bounds');
    }
    return { x, y, width, height, area: width * height };
  }

  function readV2FixedPaletteDescriptor(reader, profile, excludedColor) {
    const descriptor = reader.readBits(2);
    const colors = [];
    if (descriptor === 0) {
      for (let color = 0; color < paletteSizeV2Aware(profile); color++) {
        if (reader.readBits(1) !== 0) colors.push(color);
      }
    } else if (descriptor === 1) {
      const count = readBitVarUint(reader);
      if (count <= 0 || count > paletteSizeV2Aware(profile)) {
        throw new MCOImageInvalidPayloadError('Invalid fixed delta palette size');
      }
      colors.push(reader.readBits(__legacyGlobalBits(profile)));
      while (colors.length < count) colors.push(colors[colors.length - 1] + readCompactUint(reader) + 1);
    } else if (descriptor === 2) {
      const runCount = readCompactUint(reader) + 1;
      if (runCount > paletteSizeV2Aware(profile)) {
        throw new MCOImageInvalidPayloadError('Invalid fixed palette range count');
      }
      for (let i = 0; i < runCount; i++) {
        const start = reader.readBits(__legacyGlobalBits(profile));
        const length = readCompactUint(reader) + 1;
        if (start + length > paletteSizeV2Aware(profile) ||
            colors.length + length > paletteSizeV2Aware(profile)) {
          throw new MCOImageInvalidPayloadError('Invalid fixed palette range');
        }
        for (let offset = 0; offset < length; offset++) colors.push(start + offset);
      }
    } else {
      throw new MCOImageInvalidPayloadError('Unsupported fixed palette descriptor');
    }
    const seen = new Set();
    if (colors.length === 0 || colors.length > paletteSizeV2Aware(profile)) {
      throw new MCOImageInvalidPayloadError('Invalid compact fixed palette size');
    }
    for (const color of colors) {
      validateColor(color, profile, 'localPalette', true);
      if (color === excludedColor || seen.has(color)) {
        throw new MCOImageInvalidPayloadError('Invalid local palette');
      }
      seen.add(color);
    }
    return colors;
  }

  function readV2LocalPaletteCurrent(reader, profile, excludedColor) {
    const length = readBitVarUint(reader);
    if (length === 0) return readV2FixedPaletteDescriptor(reader, profile, excludedColor);
    if (length > paletteSizeV2Aware(profile)) {
      throw new MCOImageInvalidPayloadError('Invalid local palette size');
    }
    const colors = [];
    const seen = new Set();
    for (let i = 0; i < length; i++) {
      const color = reader.readBits(__legacyGlobalBits(profile));
      validateColor(color, profile, 'localPalette', true);
      if (color === excludedColor || seen.has(color)) {
        throw new MCOImageInvalidPayloadError('Invalid local palette');
      }
      seen.add(color);
      colors.push(color);
    }
    return colors;
  }

  function readDynamicLocalPaletteBodyCurrent(reader, profile, referenceEncoding, length) {
    if (length <= 0 || length > MCOImageCodec.maxDynamicLocalPalette) {
      throw new MCOImageInvalidPayloadError('Invalid dynamic local palette size');
    }
    let ids;
    if (referenceEncoding === DynamicPaletteReferenceEncoding.flat) {
      ids = [];
      const seen = new Set();
      for (let i = 0; i < length; i++) {
        const id = reader.readBits(dynamicProfileColorBits(profile));
        if (id >= dynamicProfileSize(profile) || seen.has(id)) {
          throw new MCOImageInvalidPayloadError('Invalid dynamic local palette');
        }
        seen.add(id);
        ids.push(id);
      }
    } else if (referenceEncoding === DynamicPaletteReferenceEncoding.banked8x64) {
      if (profile !== PaletteProfile.dynamicGlobal512) {
        throw new MCOImageInvalidPayloadError('Banked references require dynamicGlobal512');
      }
      const bankCount = readBitVarUint(reader);
      if (bankCount <= 0 || bankCount > 8) throw new MCOImageInvalidPayloadError('Invalid bank count');
      const banks = [];
      const seenBanks = new Set();
      for (let i = 0; i < bankCount; i++) {
        const bank = reader.readBits(3);
        if (seenBanks.has(bank)) throw new MCOImageInvalidPayloadError('Duplicate bank index');
        seenBanks.add(bank);
        banks.push(bank);
      }
      const bankBits = bitsForChoiceCount(bankCount);
      ids = [];
      const seen = new Set();
      for (let i = 0; i < length; i++) {
        const bankIndex = reader.readBits(bankBits);
        if (bankIndex >= banks.length) throw new MCOImageInvalidPayloadError('Bank index out of range');
        const id = (banks[bankIndex] << 6) | reader.readBits(6);
        if (seen.has(id)) throw new MCOImageInvalidPayloadError('Duplicate dynamic color');
        seen.add(id);
        ids.push(id);
      }
    } else {
      throw new MCOImageInvalidPayloadError('Extended dynamic palette requires a zero marker');
    }
    return ids.map((id) => globalIndexForProfileColorId(profile, id));
  }

  function readExtendedDynamicPaletteCurrent(reader, profile) {
    const descriptor = reader.readBits(2);
    let ids = [];
    if (descriptor === 0) {
      const length = reader.readBits(6) + 1;
      ids.push(reader.readBits(dynamicProfileColorBits(profile)));
      while (ids.length < length) ids.push(ids[ids.length - 1] + readCompactUint(reader) + 1);
    } else if (descriptor === 1) {
      const runCount = readCompactUint(reader) + 1;
      let previousEnd = -1;
      for (let i = 0; i < runCount; i++) {
        const start = i === 0
          ? reader.readBits(dynamicProfileColorBits(profile))
          : previousEnd + readCompactUint(reader) + 1;
        const length = readCompactUint(reader) + 1;
        const end = start + length - 1;
        if (start <= previousEnd || end >= dynamicProfileSize(profile)) {
          throw new MCOImageInvalidPayloadError('Dynamic palette range is out of bounds');
        }
        for (let id = start; id <= end; id++) ids.push(id);
        previousEnd = end;
      }
    } else if (descriptor === 2) {
      for (let id = 0; id < dynamicProfileSize(profile); id++) {
        if (reader.readBits(1) !== 0) ids.push(id);
      }
    } else {
      if (profile !== PaletteProfile.dynamicGlobal512) {
        throw new MCOImageInvalidPayloadError('Bank bitmaps require dynamicGlobal512');
      }
      const bankMask = reader.readBits(8);
      if (bankMask === 0) throw new MCOImageInvalidPayloadError('Dynamic bank bitmap is empty');
      for (let bank = 0; bank < 8; bank++) {
        if ((bankMask & (1 << bank)) === 0) continue;
        const before = ids.length;
        for (let offset = 0; offset < 64; offset++) {
          if (reader.readBits(1) !== 0) ids.push((bank << 6) | offset);
        }
        if (ids.length === before) throw new MCOImageInvalidPayloadError('Dynamic bank bitmap has an empty bank');
      }
    }
    if (ids.length === 0 || ids.length > MCOImageCodec.maxDynamicLocalPalette ||
        ids.some((id) => id < 0 || id >= dynamicProfileSize(profile))) {
      throw new MCOImageInvalidPayloadError('Invalid dynamic local palette size');
    }
    return ids.map((id) => globalIndexForProfileColorId(profile, id));
  }

  function readDynamicLocalPaletteCurrent(reader, profile, referenceEncoding) {
    const length = readBitVarUint(reader);
    return length === 0
      ? readExtendedDynamicPaletteCurrent(reader, profile)
      : readDynamicLocalPaletteBodyCurrent(reader, profile, referenceEncoding, length);
  }

  function readCurrentLocalPalette(reader, profile, referenceEncoding, excludedColor) {
    return isDynamicProfile(profile)
      ? readDynamicLocalPaletteCurrent(reader, profile, referenceEncoding)
      : readV2LocalPaletteCurrent(reader, profile, excludedColor);
  }

  function decodeExtendedSolidRects(reader, width, height, profile, referenceEncoding, backgroundColor) {
    const background = backgroundColor ?? readV2ColorRef(reader, profile);
    const palette = readCurrentLocalPalette(reader, profile, referenceEncoding, background);
    if (palette.includes(background)) throw new MCOImageInvalidPayloadError('Rectangle palette contains background');
    const localBits = bitsForLocalPalette(palette.length);
    const rectCount = readBitVarUint(reader);
    if (rectCount <= 0 || rectCount > 64) throw new MCOImageInvalidPayloadError('Invalid rectangle count');
    const result = new Array(width * height).fill(background);
    const occupied = new Array(width * height).fill(false);
    for (let i = 0; i < rectCount; i++) {
      const bounds = readV2CompactBounds(reader, width, height);
      const colorIndex = reader.readBits(localBits);
      if (colorIndex >= palette.length) throw new MCOImageInvalidPayloadError('Rectangle color out of range');
      for (let y = bounds.y; y < bounds.y + bounds.height; y++) {
        for (let x = bounds.x; x < bounds.x + bounds.width; x++) {
          const index = y * width + x;
          if (occupied[index]) throw new MCOImageInvalidPayloadError('Overlapping rectangles');
          occupied[index] = true;
          result[index] = palette[colorIndex];
        }
      }
    }
    return result;
  }

  function decodeExtendedCompactRle(reader, width, height, profile, referenceEncoding) {
    const palette = readCurrentLocalPalette(reader, profile, referenceEncoding);
    const localBits = bitsForLocalPalette(palette.length);
    const count = width * height;
    const result = [];
    while (result.length < count) {
      const index = reader.readBits(localBits);
      const length = readCompactUint(reader) + 1;
      if (index >= palette.length || result.length + length > count) {
        throw new MCOImageInvalidPayloadError('Invalid compact RLE');
      }
      for (let i = 0; i < length; i++) result.push(palette[index]);
    }
    return result;
  }

  function decodeExtendedCompactSparse(reader, width, height, profile, referenceEncoding, backgroundColor) {
    const background = backgroundColor ?? readV2ColorRef(reader, profile);
    const palette = readCurrentLocalPalette(reader, profile, referenceEncoding, background);
    if (palette.includes(background)) throw new MCOImageInvalidPayloadError('Sparse palette contains background');
    const count = width * height;
    const segmentCount = readCompactUint(reader) + 1;
    if (segmentCount <= 0 || segmentCount > count) throw new MCOImageInvalidPayloadError('Invalid sparse segments');
    const localBits = bitsForLocalPalette(palette.length);
    const result = new Array(count).fill(background);
    let pos = 0;
    for (let i = 0; i < segmentCount; i++) {
      pos += readCompactUint(reader);
      const index = reader.readBits(localBits);
      const length = readCompactUint(reader) + 1;
      if (index >= palette.length || pos >= count || pos + length > count) {
        throw new MCOImageInvalidPayloadError('Invalid compact sparse segment');
      }
      for (let j = 0; j < length; j++) result[pos + j] = palette[index];
      pos += length;
    }
    return result;
  }

  function decodeExtendedLz(reader, width, height, profile, referenceEncoding) {
    const palette = readCurrentLocalPalette(reader, profile, referenceEncoding);
    const localBits = bitsForLocalPalette(palette.length);
    const count = width * height;
    const result = [];
    while (result.length < count) {
      if (reader.readBits(1) !== 0) {
        const distance = readCompactUint(reader) + 1;
        const length = readCompactUint(reader) + 3;
        if (distance > result.length || result.length + length > count) {
          throw new MCOImageInvalidPayloadError('Invalid LZ match');
        }
        for (let i = 0; i < length; i++) result.push(result[result.length - distance]);
      } else {
        const length = readCompactUint(reader) + 1;
        if (result.length + length > count) throw new MCOImageInvalidPayloadError('Invalid LZ literal');
        for (let i = 0; i < length; i++) {
          const index = reader.readBits(localBits);
          if (index >= palette.length) throw new MCOImageInvalidPayloadError('LZ color out of range');
          result.push(palette[index]);
        }
      }
    }
    return result;
  }

  function decodeExtendedQuadtree(reader, width, height, profile, referenceEncoding) {
    const palette = readCurrentLocalPalette(reader, profile, referenceEncoding);
    const localBits = bitsForLocalPalette(palette.length);
    const result = new Array(width * height).fill(palette[0]);
    function node(x, y, w, h) {
      if (reader.readBits(1) !== 0) {
        const index = reader.readBits(localBits);
        if (index >= palette.length) throw new MCOImageInvalidPayloadError('Quadtree color out of range');
        for (let dy = 0; dy < h; dy++) for (let dx = 0; dx < w; dx++) result[(y + dy) * width + x + dx] = palette[index];
        return;
      }
      if (w === 1 && h === 1) throw new MCOImageInvalidPayloadError('Quadtree splits one pixel');
      if (w === 1) {
        const top = Math.floor(h / 2);
        node(x, y, w, top); node(x, y + top, w, h - top); return;
      }
      if (h === 1) {
        const left = Math.floor(w / 2);
        node(x, y, left, h); node(x + left, y, w - left, h); return;
      }
      const left = Math.floor(w / 2), top = Math.floor(h / 2);
      node(x, y, left, top);
      node(x + left, y, w - left, top);
      node(x, y + top, left, h - top);
      node(x + left, y + top, w - left, h - top);
    }
    node(0, 0, width, height);
    return result;
  }

  function readFixedPaletteBody(reader, profile, length) {
    if (length <= 0 || length > paletteSizeV2Aware(profile)) {
      throw new MCOImageInvalidPayloadError('Invalid fixed palette size');
    }
    const result = [], seen = new Set();
    for (let i = 0; i < length; i++) {
      const color = reader.readBits(__legacyGlobalBits(profile));
      validateColor(color, profile, 'localPalette', true);
      if (seen.has(color)) throw new MCOImageInvalidPayloadError('Duplicate fixed palette color');
      seen.add(color);
      result.push(color);
    }
    return result;
  }

  function decodeLegacyBitplanesBody(reader, width, height, palette) {
    const count = width * height;
    const localBits = bitsForLocalPalette(palette.length);
    const localPixels = new Array(count).fill(0);
    for (let bit = 0; bit < localBits; bit++) {
      if (reader.readBits(1) === 0) {
        for (let i = 0; i < count; i++) localPixels[i] |= reader.readBits(1) << bit;
        continue;
      }
      let value = reader.readBits(1), position = 0;
      while (position < count) {
        const length = readCompactUint(reader) + 1;
        if (position + length > count) throw new MCOImageInvalidPayloadError('Bitplane RLE exceeds pixels');
        if (value !== 0) for (let i = 0; i < length; i++) localPixels[position + i] |= 1 << bit;
        position += length;
        value ^= 1;
      }
    }
    return localPixels.map((index) => {
      if (index >= palette.length) throw new MCOImageInvalidPayloadError('Bitplane color out of range');
      return palette[index];
    });
  }

  function readShortBitplaneRun(reader) {
    if (reader.readBits(1) === 0) return 1;
    if (reader.readBits(1) === 0) return 2;
    if (reader.readBits(1) === 0) return 3;
    return readCompactUint(reader) + 4;
  }

  function decodeAdaptiveBitplanesBody(reader, width, height, palette) {
    const count = width * height;
    const localBits = bitsForLocalPalette(palette.length);
    const localPixels = new Array(count).fill(0);
    function runs(bit, shortLengths) {
      let value = reader.readBits(1), position = 0;
      while (position < count) {
        const length = shortLengths ? readShortBitplaneRun(reader) : readCompactUint(reader) + 1;
        if (length <= 0 || position + length > count) throw new MCOImageInvalidPayloadError('Adaptive bitplane RLE exceeds pixels');
        if (value !== 0) for (let i = 0; i < length; i++) localPixels[position + i] |= 1 << bit;
        position += length;
        value ^= 1;
      }
    }
    function sparse(bit, minorityBit) {
      const minorityCount = readCompactUint(reader) + 1;
      if (minorityCount > count) throw new MCOImageInvalidPayloadError('Sparse bitplane count exceeds pixels');
      let previous = -1;
      for (let i = 0; i < minorityCount; i++) {
        const position = previous + readCompactUint(reader) + 1;
        if (position <= previous || position >= count) throw new MCOImageInvalidPayloadError('Sparse bit position out of range');
        if (minorityBit === 0) localPixels[position] &= ~(1 << bit);
        else localPixels[position] |= 1 << bit;
        previous = position;
      }
    }
    for (let bit = 0; bit < localBits; bit++) {
      if (reader.readBits(1) === 0) {
        for (let i = 0; i < count; i++) localPixels[i] |= reader.readBits(1) << bit;
        continue;
      }
      if (reader.readBits(1) === 0) { runs(bit, false); continue; }
      if (reader.readBits(1) === 0) { runs(bit, true); continue; }
      const op = reader.readBits(2);
      if (op === 1 || op === 3) for (let i = 0; i < count; i++) localPixels[i] |= 1 << bit;
      if (op === 2) sparse(bit, 1);
      if (op === 3) sparse(bit, 0);
    }
    return localPixels.map((index) => {
      if (index >= palette.length) throw new MCOImageInvalidPayloadError('Adaptive bitplane color out of range');
      return palette[index];
    });
  }

  function decodeExtendedBitplanes(reader, width, height, profile, referenceEncoding) {
    const marker = reader.readBits(8);
    let palette;
    if (marker === 0) {
      palette = isDynamicProfile(profile)
        ? readExtendedDynamicPaletteCurrent(reader, profile)
        : readV2FixedPaletteDescriptor(reader, profile);
      return decodeLegacyBitplanesBody(reader, width, height, palette);
    }
    if (marker >= 1 && marker <= 64) {
      palette = isDynamicProfile(profile)
        ? readDynamicLocalPaletteBodyCurrent(reader, profile, referenceEncoding, marker)
        : readFixedPaletteBody(reader, profile, marker);
      return decodeLegacyBitplanesBody(reader, width, height, palette);
    }
    if ((marker & 0xc0) === 0x80) {
      const length = (marker & 0x3f) + 1;
      palette = isDynamicProfile(profile)
        ? readDynamicLocalPaletteBodyCurrent(reader, profile, referenceEncoding, length)
        : readFixedPaletteBody(reader, profile, length);
      return decodeAdaptiveBitplanesBody(reader, width, height, palette);
    }
    if (marker === 0xc0) {
      if ([PaletteProfile.grayscale8, PaletteProfile.grayscale16, PaletteProfile.grayscale32].includes(profile)) {
        palette = Array.from({ length: paletteSizeV2Aware(profile) }, (_, i) => i);
        return decodeAdaptiveBitplanesBody(reader, width, height, palette);
      }
      if (isDynamicProfile(profile)) {
        return decodeAdaptiveBitplanesBody(reader, width, height, dynamicIndicesFor(profile).slice());
      }
    }
    throw new MCOImageInvalidPayloadError('Invalid Bitplanes palette marker');
  }

  function decodeExtendedCompactRowDelta(reader, width, height, profile, referenceEncoding, rowLength) {
    const directGrayscale = reader.readBits(1) !== 0;
    const grayscale = [PaletteProfile.grayscale8, PaletteProfile.grayscale16, PaletteProfile.grayscale32].includes(profile);
    if (directGrayscale && !grayscale) throw new MCOImageInvalidPayloadError('Direct row delta requires grayscale');
    let palette = null, valueBits, maxValue;
    if (directGrayscale) {
      valueBits = __legacyGlobalBits(profile);
      maxValue = paletteSizeV2Aware(profile) - 1;
    } else {
      palette = readCurrentLocalPalette(reader, profile, referenceEncoding);
      valueBits = bitsForLocalPalette(palette.length);
      maxValue = palette.length - 1;
    }
    const count = width * height;
    if (rowLength <= 0 || count % rowLength !== 0) throw new MCOImageInvalidPayloadError('Invalid compact row geometry');
    const virtualBase = reader.readBits(1) !== 0;
    const values = new Array(count).fill(0);
    const rows = count / rowLength;
    let row = virtualBase ? 0 : 1;
    if (!virtualBase) {
      for (let x = 0; x < rowLength; x++) {
        const value = reader.readBits(valueBits);
        if (value > maxValue) throw new MCOImageInvalidPayloadError('Row delta value out of range');
        values[x] = value;
      }
    }
    function predictorValue(rowIndex, x, predictor) {
      if (rowIndex === 0 && virtualBase) return 0;
      const sourceX = predictor === 0 ? x : predictor === 1 ? x + 1 : x - 1;
      if (sourceX < 0 || sourceX >= rowLength) return 0;
      return values[(rowIndex - 1) * rowLength + sourceX];
    }
    function copyPredicted(rowIndex, predictor) {
      const start = rowIndex * rowLength;
      for (let x = 0; x < rowLength; x++) values[start + x] = predictorValue(rowIndex, x, predictor);
    }
    function readPredictor() {
      if (reader.readBits(1) === 0) return 0;
      return reader.readBits(1) === 0 ? 1 : 2;
    }
    function decodeValue(encoded, predicted, residual) {
      const value = residual
        ? predicted + ((encoded & 1) !== 0 ? Math.floor((encoded + 1) / 2) : -Math.floor(encoded / 2))
        : encoded;
      if (value < 0 || value > maxValue) throw new MCOImageInvalidPayloadError('Row delta reconstructed value out of range');
      return value;
    }
    while (row < rows) {
      const op = reader.readBits(3);
      if (op === 0 || op === 6) {
        const repeat = op === 0 ? 1 : readCompactUint(reader) + 2;
        if (row + repeat > rows) throw new MCOImageInvalidPayloadError('Row repeat exceeds row count');
        for (let i = 0; i < repeat; i++, row++) copyPredicted(row, 0);
        continue;
      }
      if (op === 1) {
        const start = row * rowLength;
        for (let x = 0; x < rowLength; x++) {
          const value = reader.readBits(valueBits);
          if (value > maxValue) throw new MCOImageInvalidPayloadError('Raw row value out of range');
          values[start + x] = value;
        }
        row++;
        continue;
      }
      const predictor = readPredictor();
      if (row === 0 && virtualBase && predictor !== 0) throw new MCOImageInvalidPayloadError('Shifted virtual predictor');
      copyPredicted(row, predictor);
      if (op === 7) { row++; continue; }
      const residual = directGrayscale && reader.readBits(1) !== 0;
      const positions = [];
      if (op === 2 || op === 3) {
        const changes = readCompactUint(reader) + 1;
        if (changes > rowLength) throw new MCOImageInvalidPayloadError('Too many row changes');
        let previous = -1;
        for (let i = 0; i < changes; i++) {
          const x = previous + readCompactUint(reader) + 1;
          if (x >= rowLength) throw new MCOImageInvalidPayloadError('Row change out of range');
          positions.push(x); previous = x;
        }
      } else if (op === 4) {
        const segments = readCompactUint(reader) + 1;
        let previousEnd = 0;
        for (let i = 0; i < segments; i++) {
          const start = (i === 0 ? 0 : previousEnd) + readCompactUint(reader);
          const length = readCompactUint(reader) + 1;
          if (start < previousEnd || start + length > rowLength) throw new MCOImageInvalidPayloadError('Invalid row segment');
          for (let x = start; x < start + length; x++) positions.push(x);
          previousEnd = start + length;
        }
      } else if (op === 5) {
        const start = readCompactUint(reader);
        const span = readCompactUint(reader) + 1;
        if (start + span > rowLength) throw new MCOImageInvalidPayloadError('Invalid row mask');
        for (let offset = 0; offset < span; offset++) if (reader.readBits(1) !== 0) positions.push(start + offset);
        if (positions.length === 0) throw new MCOImageInvalidPayloadError('Empty row mask');
      } else {
        throw new MCOImageInvalidPayloadError('Unknown compact row delta op');
      }
      const start = row * rowLength;
      if (op === 3) {
        const encoded = residual ? readCompactUint(reader) + 1 : reader.readBits(valueBits);
        for (const x of positions) values[start + x] = decodeValue(encoded, values[start + x], residual);
      } else {
        for (const x of positions) {
          const encoded = residual ? readCompactUint(reader) + 1 : reader.readBits(valueBits);
          values[start + x] = decodeValue(encoded, values[start + x], residual);
        }
      }
      row++;
    }
    return directGrayscale ? values : values.map((value) => palette[value]);
  }

  function decodeV2Body(reader, width, height, profile, mode, referenceEncoding, { rowLength, sparseBackgroundColor, unalignedExtendedBody = false } = {}) {
    if (mode === ImageMode.extended) {
      const submode = reader.readBits(3);
      if (submode === ExtendedImageMode.solidRects) {
        return decodeExtendedSolidRects(reader, width, height, profile, referenceEncoding, sparseBackgroundColor);
      }
      if (submode === ExtendedImageMode.compactRle) {
        return decodeExtendedCompactRle(reader, width, height, profile, referenceEncoding);
      }
      if (submode === ExtendedImageMode.compactSparse) {
        return decodeExtendedCompactSparse(reader, width, height, profile, referenceEncoding, sparseBackgroundColor);
      }
      if (submode === ExtendedImageMode.lzPixels) {
        return decodeExtendedLz(reader, width, height, profile, referenceEncoding);
      }
      if (submode === ExtendedImageMode.quadtree) {
        return decodeExtendedQuadtree(reader, width, height, profile, referenceEncoding);
      }
      if (submode === ExtendedImageMode.bitplanes) {
        return decodeExtendedBitplanes(reader, width, height, profile, referenceEncoding);
      }
      if (submode === ExtendedImageMode.compactRowDelta) {
        return decodeExtendedCompactRowDelta(reader, width, height, profile, referenceEncoding, rowLength);
      }
      if (submode !== ExtendedImageMode.wrappedBlock) {
        throw new MCOImageInvalidPayloadError(`Unsupported extended image submode ${submode}`);
      }
      const innerMode = modeFromBits(reader.readBits(3));
      if (innerMode === ImageMode.extended || innerMode === ImageMode.regionsBg) {
        throw new MCOImageInvalidPayloadError('Invalid wrapped image mode');
      }
      if (!unalignedExtendedBody) reader.alignToByte();
      return decodeV2Body(reader, width, height, profile, innerMode, referenceEncoding, {
        rowLength,
        sparseBackgroundColor,
        unalignedExtendedBody,
      });
    }
    const dynamic = isDynamicProfile(profile);
    const count = width * height;
    let palette, localBits, dynamicSparseBackground;
    if (dynamic) {
      if (referenceEncoding == null) throw new MCOImageInvalidPayloadError('Dynamic v2 block is missing reference encoding');
      switch (mode) {
        case ImageMode.rawLocal:
        case ImageMode.rleLocal:
        case ImageMode.rowRepeat:
        case ImageMode.rowDelta:
          palette = readDynamicLocalPalette(reader, profile, referenceEncoding).globalColors;
          break;
        case ImageMode.sparseBg:
          dynamicSparseBackground = sparseBackgroundColor ?? readV2ColorRef(reader, profile);
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
      const bg = dynamicSparseBackground;
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

  function readV2BackgroundCurrent(reader, profile, implicitWhite) {
    if (implicitWhite) return isDynamicProfile(profile)
      ? globalIndexForProfileColorId(profile, 0)
      : 0;
    return readV2ColorRef(reader, profile);
  }

  function isImplicitWhite(profile, color) {
    return isDynamicProfile(profile)
      ? color === globalIndexForProfileColorId(profile, 0)
      : color === 0;
  }

  function decodeV2RegionsCurrent(reader, width, height, profile, referenceEncoding, {
    compactGeometry,
    implicitWhiteBackground,
    sharedFixedPalette,
  }) {
    const effectiveImplicitWhite = sharedFixedPalette
      ? reader.readBits(1) !== 0
      : implicitWhiteBackground;
    const background = readV2BackgroundCurrent(reader, profile, effectiveImplicitWhite);
    let sharedPalette = null;
    if (isDynamicProfile(profile)) {
      sharedPalette = readDynamicLocalPaletteCurrent(reader, profile, referenceEncoding);
    } else if (sharedFixedPalette) {
      sharedPalette = readV2LocalPaletteCurrent(reader, profile);
    }
    const regionCount = compactGeometry
      ? reader.readBits(bitsForChoiceCount(MCOImageCodec.maxV2Regions)) + 1
      : readBitVarUint(reader);
    if (regionCount <= 0 || regionCount > MCOImageCodec.maxV2Regions) {
      throw new MCOImageInvalidPayloadError('Invalid v2 region count');
    }
    const pixels = new Array(width * height).fill(background);
    const occupied = new Array(width * height).fill(false);
    for (let i = 0; i < regionCount; i++) {
      const region = compactGeometry
        ? readV2CompactBounds(reader, width, height)
        : {
            x: readBitVarUint(reader),
            y: readBitVarUint(reader),
            width: readBitVarUint(reader),
            height: readBitVarUint(reader),
          };
      if (region.width <= 0 || region.height <= 0 ||
          region.x + region.width > width || region.y + region.height > height) {
        throw new MCOImageInvalidPayloadError('Invalid v2 image region');
      }
      const modeAndScan = reader.readAlignedByte();
      if ((modeAndScan & 0x07) !== 0) throw new MCOImageInvalidPayloadError('Reserved region bits are set');
      const regionMode = modeFromBits((modeAndScan >> 5) & 0x07);
      const regionScan = scanFromBits((modeAndScan >> 3) & 0x03);
      if (isDynamicProfile(profile) && regionMode === ImageMode.rawGlobal) {
        throw new MCOImageInvalidPayloadError('Dynamic region rawGlobal is reserved');
      }
      const payloadLength = readBitVarUint(reader);
      const payload = reader.readAlignedBytes(payloadLength);
      const regionReader = new BitReader(payload);
      const linear = sharedPalette
        ? decodeV2DynamicRegionBody(
            regionReader,
            region.width,
            region.height,
            sharedPalette,
            background,
            regionMode,
            { rowLength: rowLengthForScan(regionScan, region.width, region.height) },
          )
        : decodeV2Body(
            regionReader,
            region.width,
            region.height,
            profile,
            regionMode,
            null,
            {
              rowLength: rowLengthForScan(regionScan, region.width, region.height),
              sparseBackgroundColor: background,
            },
          );
      regionReader.finish();
      const regionPixels = fromScanOrder(linear, region.width, region.height, regionScan);
      for (let y = 0; y < region.height; y++) {
        for (let x = 0; x < region.width; x++) {
          const target = (region.y + y) * width + region.x + x;
          if (occupied[target]) throw new MCOImageInvalidPayloadError('Overlapping v2 regions');
          occupied[target] = true;
          pixels[target] = regionPixels[y * region.width + x];
        }
      }
    }
    return pixels;
  }

  function decodeV2Current(bytes, header) {
    if (bytes.length < 4) throw new MCOImageInvalidPayloadError('Payload too short');
    const mode = modeFromBits((header >> 3) & 0x07);
    const scan = scanFromBits((header >> 1) & 0x03);
    const boundsPresent = (header & 1) !== 0;
    const paletteHeader = bytes[1];
    const dynamic = ((paletteHeader >> 7) & 1) !== 0;
    const regions = ((paletteHeader >> 6) & 1) !== 0;
    const contextBit = (paletteHeader >> 5) & 1;
    const hasTransparentColor = (paletteHeader & MCOImageCodec.v2TransparentProfileFlag) !== 0;
    const encodedProfileId = paletteHeader & MCOImageCodec.v2ProfileIdMask;
    const headerImplicitWhite = (dynamic && (encodedProfileId & 0x08) !== 0) ||
      (!dynamic && !regions && mode === ImageMode.rawGlobal && scan === ScanMode.v && contextBit !== 0);
    const fixedBlockExtension = !dynamic && !regions && mode !== ImageMode.rawGlobal && contextBit !== 0;
    const profileId = dynamic ? encodedProfileId & 0x07 : encodedProfileId;
    const profile = dynamic ? dynamicProfileFromId(profileId) : fixedProfileFromId(profileId);
    const referenceEncoding = dynamic
      ? (contextBit === 0 ? DynamicPaletteReferenceEncoding.flat : DynamicPaletteReferenceEncoding.banked8x64)
      : null;
    if (referenceEncoding === DynamicPaletteReferenceEncoding.banked8x64 &&
        profile !== PaletteProfile.dynamicGlobal512) {
      throw new MCOImageInvalidPayloadError('Banked references require Dynamic Global 512');
    }
    const sharedFixedPalette = !dynamic && regions && contextBit !== 0;
    const solidBackground = !regions && mode === ImageMode.rawGlobal && (dynamic || contextBit !== 0);
    const width = bytes[2] + 1, height = bytes[3] + 1;
    validateDimensionsAny(width, height, true);
    const reader = new BitReader(bytes, 4);

    if (regions) {
      const compactGeometry = mode === ImageMode.extended;
      if (boundsPresent || (mode !== ImageMode.rawGlobal && !compactGeometry) || scan !== ScanMode.h) {
        throw new MCOImageInvalidPayloadError('Invalid v2 regions header');
      }
      const transparentColor = hasTransparentColor ? readV2ColorRef(reader, profile) : null;
      const pixels = decodeV2RegionsCurrent(reader, width, height, profile, referenceEncoding, {
        compactGeometry,
        implicitWhiteBackground: headerImplicitWhite,
        sharedFixedPalette,
      });
      reader.finish();
      return new MCOImage({
        width, height, paletteProfile: profile, pixels, transparentColor,
        encodingVersion: MCOImageEncodingVersion.v2,
      });
    }

    let implicitWhite = headerImplicitWhite;
    let unalignedExtendedBody = false;
    if (fixedBlockExtension) {
      const flags = reader.readBits(2);
      implicitWhite = (flags & 1) !== 0;
      unalignedExtendedBody = (flags & 2) !== 0;
      if (unalignedExtendedBody && mode !== ImageMode.extended) {
        throw new MCOImageInvalidPayloadError('Unaligned body requires extended mode');
      }
    }
    const transparentColor = hasTransparentColor ? readV2ColorRef(reader, profile) : null;
    if (solidBackground) {
      const background = readV2BackgroundCurrent(reader, profile, implicitWhite);
      reader.finish();
      return new MCOImage({
        width, height, paletteProfile: profile,
        pixels: new Array(width * height).fill(background),
        transparentColor, encodingVersion: MCOImageEncodingVersion.v2,
      });
    }
    if (boundsPresent) {
      const background = readV2BackgroundCurrent(reader, profile, implicitWhite);
      const bounds = mode === ImageMode.extended
        ? readV2CompactBounds(reader, width, height)
        : readV2Bounds(reader, width, height);
      if (bounds.area === 0) {
        reader.finish();
        return new MCOImage({
          width, height, paletteProfile: profile,
          pixels: new Array(width * height).fill(background),
          transparentColor, encodingVersion: MCOImageEncodingVersion.v2,
        });
      }
      if (!unalignedExtendedBody) reader.alignToByte();
      const linear = decodeV2Body(reader, bounds.width, bounds.height, profile, mode, referenceEncoding, {
        rowLength: rowLengthForScan(scan, bounds.width, bounds.height),
        sparseBackgroundColor: background,
        unalignedExtendedBody,
      });
      reader.finish();
      const cropped = fromScanOrder(linear, bounds.width, bounds.height, scan);
      return new MCOImage({
        width, height, paletteProfile: profile,
        pixels: insertBounds(width, height, background, cropped, bounds),
        transparentColor, encodingVersion: MCOImageEncodingVersion.v2,
      });
    }
    const implicitBackground = implicitWhite
      ? (dynamic ? globalIndexForProfileColorId(profile, 0) : 0)
      : undefined;
    if (!unalignedExtendedBody) reader.alignToByte();
    const linear = decodeV2Body(reader, width, height, profile, mode, referenceEncoding, {
      rowLength: rowLengthForScan(scan, width, height),
      sparseBackgroundColor: implicitBackground,
      unalignedExtendedBody,
    });
    reader.finish();
    return new MCOImage({
      width, height, paletteProfile: profile,
      pixels: fromScanOrder(linear, width, height, scan),
      transparentColor, encodingVersion: MCOImageEncodingVersion.v2,
    });
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

  MCOImageCodec.binaryPayloadFromText = function(text) {
    if (!text.startsWith(MCOImageCodec.prefix)) {
      throw new MCOImageInvalidPayloadError('Missing im: prefix');
    }
    return base91Decode(text.slice(MCOImageCodec.prefix.length));
  };

  MCOImageCodec.textFromBinaryPayload = function(bytes) {
    const payload = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    return MCOImageCodec.prefix + base91Encode(payload);
  };

  const imageModeLabels = Object.freeze({
    [ImageMode.rawGlobal]: 'Raw global',
    [ImageMode.rawLocal]: 'Raw local',
    [ImageMode.rleLocal]: 'RLE local',
    [ImageMode.sparseBg]: 'Sparse background',
    [ImageMode.regionsBg]: 'Regions',
    [ImageMode.biColorMask]: 'Bi-color mask',
    [ImageMode.rowDelta]: 'Row delta',
    [ImageMode.rowRepeat]: 'Row repeat',
    [ImageMode.extended]: 'Extended',
  });
  const extendedModeLabels = Object.freeze([
    'Wrapped block',
    'Solid rectangles',
    'Compact RLE',
    'Compact sparse',
    'LZ pixels',
    'Quadtree',
    'Bitplanes',
    'Compact row delta',
  ]);

  MCOImageCodec.inspectPayloadBytes = function(bytesLike) {
    const bytes = bytesLike instanceof Uint8Array ? bytesLike : new Uint8Array(bytesLike);
    if (bytes.length < 4) throw new MCOImageInvalidPayloadError('Payload too short');
    const header = bytes[0];
    const version = (header >> 6) & 0x03;
    if (version !== MCOImageCodec.v2EncodeVersion) {
      const mode = modeFromBits((header >> 4) & 0x03);
      return {
        version,
        algorithm: (bytes[1] & 0x0f) === MCOImageCodec.containerRegions
          ? 'Regions'
          : imageModeLabels[mode],
        binaryLength: bytes.length,
      };
    }
    const mode = modeFromBits((header >> 3) & 0x07);
    const scan = scanFromBits((header >> 1) & 0x03);
    const boundsPresent = (header & 1) !== 0;
    const paletteHeader = bytes[1];
    const dynamic = ((paletteHeader >> 7) & 1) !== 0;
    const regions = ((paletteHeader >> 6) & 1) !== 0;
    const contextBit = (paletteHeader >> 5) & 1;
    if (regions) return { version, algorithm: 'Regions', binaryLength: bytes.length };
    if (mode === ImageMode.rawGlobal && (dynamic || contextBit !== 0)) {
      return { version, algorithm: 'Solid background', binaryLength: bytes.length };
    }
    if (mode !== ImageMode.extended) {
      return { version, algorithm: imageModeLabels[mode], binaryLength: bytes.length };
    }
    const encodedProfileId = paletteHeader & MCOImageCodec.v2ProfileIdMask;
    const profile = dynamic
      ? dynamicProfileFromId(encodedProfileId & 0x07)
      : fixedProfileFromId(encodedProfileId);
    const fixedExtension = !dynamic && contextBit !== 0;
    const reader = new BitReader(bytes, 4);
    let implicitWhite = dynamic && (encodedProfileId & 0x08) !== 0;
    let unaligned = false;
    if (fixedExtension) {
      const flags = reader.readBits(2);
      implicitWhite = (flags & 1) !== 0;
      unaligned = (flags & 2) !== 0;
    }
    if ((paletteHeader & MCOImageCodec.v2TransparentProfileFlag) !== 0) readV2ColorRef(reader, profile);
    if (boundsPresent) {
      readV2BackgroundCurrent(reader, profile, implicitWhite);
      readV2CompactBounds(reader, bytes[2] + 1, bytes[3] + 1);
    }
    if (!unaligned) reader.alignToByte();
    const submode = reader.readBits(3);
    const algorithm = submode === ExtendedImageMode.wrappedBlock
      ? imageModeLabels[modeFromBits(reader.readBits(3))]
      : (extendedModeLabels[submode] || 'Extended');
    return { version, algorithm, binaryLength: bytes.length };
  };

  MCOImageCodec.inspectPayload = function(text) {
    try {
      return MCOImageCodec.inspectPayloadBytes(MCOImageCodec.binaryPayloadFromText(text));
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

  MCOImageCodec.prototype.encodeBytes = function(imageLike, options = {}) {
    const encoded = this.encode(imageLike, {
      ...options,
      outputTarget: MCOImageOutputTarget.binary,
    });
    return new Uint8Array(encoded.payload || base91Decode(encoded.text.slice(MCOImageCodec.prefix.length)));
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
    if (version === MCOImageCodec.v2EncodeVersion) return decodeV2Current(bytes, header);
    const image = __legacyDecode.call(this, text);
    image.encodingVersion = MCOImageEncodingVersion.v1Legacy;
    image.transparentColor = null;
    return image;
  };

  MCOImageCodec.prototype.decodeBytes = function(bytes) {
    const payload = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    return this.decode(MCOImageCodec.prefix + base91Encode(payload));
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
    if (isDynamicProfile(normalized)) return DynamicGlobal512Current.indexOf(0xff000000);
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
      if (referenceEncoding >= DynamicPaletteReferenceEncoding.sortedDelta) {
        localPalette.sort((a, b) => a - b);
      }
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

  function writeCompactUint(writer, value) {
    if (value < 0) throw new MCOImageInvalidInputError('Negative compact uint');
    if (value <= 3) {
      writer.writeBits(0, 1); writer.writeBits(value, 2);
    } else if (value <= 19) {
      writer.writeBits(1, 2); writer.writeBits(value - 4, 4);
    } else if (value <= 275) {
      writer.writeBits(3, 3); writer.writeBits(value - 20, 8);
    } else {
      writer.writeBits(7, 3); writeBitVarUint(writer, value);
    }
  }

  function writeV2CompactBounds(writer, bounds, fullWidth, fullHeight) {
    writer.writeBits(bounds.x, bitsForChoiceCount(fullWidth));
    writer.writeBits(bounds.y, bitsForChoiceCount(fullHeight));
    writer.writeBits(bounds.width - 1, bitsForChoiceCount(fullWidth - bounds.x));
    writer.writeBits(bounds.height - 1, bitsForChoiceCount(fullHeight - bounds.y));
  }

  function writeCurrentLocalPalette(writer, profile, colors, referenceEncoding) {
    if (colors.length === 0 || colors.length > 64) return null;
    if (isDynamicProfile(profile)) {
      const ids = colors.map((color) => profileColorIdForGlobalIndex(profile, color));
      if (ids.some((id) => id == null)) return null;
      writeDynamicLocalPalette(writer, profile, ids, referenceEncoding);
      return ids;
    }
    const globalBitsCount = __legacyGlobalBits(profile);
    const compactBitLength = (value) => {
      if (value <= 3) return 3;
      if (value <= 19) return 6;
      if (value <= 275) return 11;
      return 3 + bitVarUintBitLength(value);
    };
    const runs = [];
    let start = colors[0], previous = start;
    for (let i = 1; i < colors.length; i++) {
      if (colors[i] === previous + 1) previous = colors[i];
      else { runs.push({ start, length: previous - start + 1 }); start = previous = colors[i]; }
    }
    runs.push({ start, length: previous - start + 1 });
    const costs = [
      { type: 'regular', bits: bitVarUintBitLength(colors.length) + colors.length * globalBitsCount },
      { type: 'bitmap', bits: 8 + 2 + paletteSizeV2Aware(profile) },
      {
        type: 'delta',
        bits: 8 + 2 + bitVarUintBitLength(colors.length) + globalBitsCount +
          colors.slice(1).reduce((sum, color, index) =>
            sum + compactBitLength(color - colors[index] - 1), 0),
      },
      {
        type: 'ranges',
        bits: 8 + 2 + compactBitLength(runs.length - 1) +
          runs.reduce((sum, run) => sum + globalBitsCount + compactBitLength(run.length - 1), 0),
      },
    ].sort((a, b) => a.bits - b.bits);
    const best = costs[0].type;
    if (best === 'regular') {
      writeV2LocalPalette(writer, colors, profile);
    } else {
      writeBitVarUint(writer, 0);
      if (best === 'bitmap') {
        writer.writeBits(0, 2);
        const selected = new Set(colors);
        for (let color = 0; color < paletteSizeV2Aware(profile); color++) {
          writer.writeBits(selected.has(color) ? 1 : 0, 1);
        }
      } else if (best === 'delta') {
        writer.writeBits(1, 2);
        writeBitVarUint(writer, colors.length);
        writer.writeBits(colors[0], globalBitsCount);
        for (let i = 1; i < colors.length; i++) writeCompactUint(writer, colors[i] - colors[i - 1] - 1);
      } else {
        writer.writeBits(2, 2);
        writeCompactUint(writer, runs.length - 1);
        for (const run of runs) {
          writer.writeBits(run.start, globalBitsCount);
          writeCompactUint(writer, run.length - 1);
        }
      }
    }
    return colors;
  }

  function buildLzTokens(localPixels) {
    const tokens = [];
    let position = 0;
    while (position < localPixels.length) {
      let bestDistance = 0, bestLength = 0;
      const maxDistance = Math.min(position, 255);
      for (let distance = 1; distance <= maxDistance; distance++) {
        let length = 0;
        while (position + length < localPixels.length &&
               localPixels[position + length] === localPixels[position + length - distance]) {
          length++;
        }
        if (length >= 3 && length > bestLength) {
          bestDistance = distance;
          bestLength = length;
        }
      }
      if (bestLength >= 3) {
        tokens.push({ match: true, distance: bestDistance, length: bestLength });
        position += bestLength;
        continue;
      }
      const literals = [localPixels[position++]];
      while (position < localPixels.length && literals.length < 64) {
        let hasMatch = false;
        const maxLookback = Math.min(position, 255);
        for (let distance = 1; distance <= maxLookback && !hasMatch; distance++) {
          let length = 0;
          while (position + length < localPixels.length &&
                 localPixels[position + length] === localPixels[position + length - distance] &&
                 length < 3) length++;
          hasMatch = length >= 3;
        }
        if (hasMatch) break;
        literals.push(localPixels[position++]);
      }
      tokens.push({ match: false, literals });
    }
    return tokens;
  }

  function writeQuadtreeBody(writer, localPixels, width, height, localBits) {
    function node(x, y, w, h) {
      const first = localPixels[y * width + x];
      let solid = true;
      for (let dy = 0; dy < h && solid; dy++) {
        for (let dx = 0; dx < w; dx++) {
          if (localPixels[(y + dy) * width + x + dx] !== first) { solid = false; break; }
        }
      }
      if (solid) {
        writer.writeBits(1, 1); writer.writeBits(first, localBits); return;
      }
      writer.writeBits(0, 1);
      if (w === 1) {
        const top = Math.floor(h / 2);
        node(x, y, w, top); node(x, y + top, w, h - top); return;
      }
      if (h === 1) {
        const left = Math.floor(w / 2);
        node(x, y, left, h); node(x + left, y, w - left, h); return;
      }
      const left = Math.floor(w / 2), top = Math.floor(h / 2);
      node(x, y, left, top);
      node(x + left, y, w - left, top);
      node(x, y + top, left, h - top);
      node(x + left, y + top, w - left, h - top);
    }
    node(0, 0, width, height);
  }

  function writeLegacyBitplanesBody(writer, localPixels, localBits) {
    for (let bit = 0; bit < localBits; bit++) {
      const plane = localPixels.map((value) => (value >> bit) & 1);
      const runs = [];
      let value = plane[0], length = 1;
      for (let i = 1; i < plane.length; i++) {
        if (plane[i] === value) length++;
        else { runs.push({ value, length }); value = plane[i]; length = 1; }
      }
      runs.push({ value, length });
      const rleBits = 2 + runs.reduce((sum, run) => sum + (run.length <= 3 ? 3 : run.length <= 19 ? 6 : run.length <= 275 ? 11 : 19), 0);
      if (rleBits >= 1 + plane.length) {
        writer.writeBits(0, 1);
        for (const pixel of plane) writer.writeBits(pixel, 1);
      } else {
        writer.writeBits(1, 1);
        writer.writeBits(runs[0].value, 1);
        for (const run of runs) writeCompactUint(writer, run.length - 1);
      }
    }
  }

  function buildExtendedBody(linear, width, height, profile, referenceEncoding, submode, backgroundColor, backgroundProvided) {
    if (submode === ExtendedImageMode.lzPixels && linear.length > 4096) {
      return null;
    }
    const writer = new BitWriter();
    writer.writeBits(submode, 3);
    let palette;
    if (submode === ExtendedImageMode.compactSparse) {
      if (!backgroundProvided) writeV2ColorRef(writer, profile, backgroundColor);
      palette = buildLocalPalette(linear.filter((color) => color !== backgroundColor));
    } else {
      palette = buildLocalPalette(linear);
    }
    if (palette.length === 0 || palette.length > 64) return null;
    if (isDynamicProfile(profile) &&
        referenceEncoding >= DynamicPaletteReferenceEncoding.sortedDelta) {
      palette.sort((a, b) =>
        profileColorIdForGlobalIndex(profile, a) - profileColorIdForGlobalIndex(profile, b));
    } else if (!isDynamicProfile(profile)) {
      palette.sort((a, b) => a - b);
    }
    const paletteIds = submode === ExtendedImageMode.bitplanes
      ? (isDynamicProfile(profile)
          ? palette.map((color) => profileColorIdForGlobalIndex(profile, color))
          : palette.slice())
      : writeCurrentLocalPalette(writer, profile, palette, referenceEncoding);
    if (!paletteIds || paletteIds.some((id) => id == null)) return null;
    const localByColor = new Map(palette.map((color, index) => [color, index]));
    const local = linear.map((color) => localByColor.get(color));
    const localBits = bitsForLocalPalette(palette.length);

    if (submode === ExtendedImageMode.compactRle) {
      for (const run of buildRuns(local)) {
        writer.writeBits(run.color, localBits);
        writeCompactUint(writer, run.length - 1);
      }
    } else if (submode === ExtendedImageMode.compactSparse) {
      const segments = buildSparseSegmentsGeneric(linear, backgroundColor);
      if (segments.length === 0) return null;
      writeCompactUint(writer, segments.length - 1);
      let pos = 0;
      for (const segment of segments) {
        writeCompactUint(writer, segment.start - pos);
        writer.writeBits(localByColor.get(segment.color), localBits);
        writeCompactUint(writer, segment.length - 1);
        pos = segment.start + segment.length;
      }
    } else if (submode === ExtendedImageMode.lzPixels) {
      for (const token of buildLzTokens(local)) {
        writer.writeBits(token.match ? 1 : 0, 1);
        if (token.match) {
          writeCompactUint(writer, token.distance - 1);
          writeCompactUint(writer, token.length - 3);
        } else {
          writeCompactUint(writer, token.literals.length - 1);
          for (const value of token.literals) writer.writeBits(value, localBits);
        }
      }
    } else if (submode === ExtendedImageMode.quadtree) {
      writeQuadtreeBody(writer, local, width, height, localBits);
    } else if (submode === ExtendedImageMode.bitplanes) {
      writer.writeBits(palette.length, 8);
      // Bitplanes stores its palette body without the usual length prefix.
      if (isDynamicProfile(profile)) {
        if (referenceEncoding === DynamicPaletteReferenceEncoding.banked8x64) {
          const banks = Array.from(new Set(paletteIds.map((id) => id >> 6))).sort((a, b) => a - b);
          writeBitVarUint(writer, banks.length);
          for (const bank of banks) writer.writeBits(bank, 3);
          const bankBits = bitsForChoiceCount(banks.length);
          for (const id of paletteIds) {
            writer.writeBits(banks.indexOf(id >> 6), bankBits);
            writer.writeBits(id & 0x3f, 6);
          }
        } else {
          for (const id of paletteIds) writer.writeBits(id, dynamicProfileColorBits(profile));
        }
      } else {
        for (const color of palette) writer.writeBits(color, __legacyGlobalBits(profile));
      }
      writeLegacyBitplanesBody(writer, local, localBits);
    } else {
      return null;
    }
    return { payload: writer.toBytes(), localPaletteSize: palette.length, bitsPerLocalPixel: localBits };
  }

  function tryBuildExtendedPayload(image, linear, scan, referenceEncoding, {
    dataWidth,
    dataHeight,
    backgroundColor,
    bounds,
    submode,
  }) {
    const backgroundCanBeImplicit = isImplicitWhite(image.paletteProfile, backgroundColor) &&
      (isDynamicProfile(image.paletteProfile) || __legacyGlobalBits(image.paletteProfile) > 2);
    const implicitWhiteBackground = backgroundCanBeImplicit &&
      (bounds != null || submode === ExtendedImageMode.compactSparse);
    const body = buildExtendedBody(
      linear, dataWidth, dataHeight, image.paletteProfile, referenceEncoding,
      submode, backgroundColor, bounds != null || implicitWhiteBackground,
    );
    if (!body) return null;
    const writer = new BitWriter();
    writeV2Header(writer, {
      profile: image.paletteProfile,
      container: MCOImageCodec.containerBlock,
      mode: ImageMode.extended,
      scan,
      boundsPresent: bounds != null,
      referenceEncoding,
      width: image.width,
      height: image.height,
      hasTransparentColor: image.transparentColor != null,
      implicitWhiteBackground,
    });
    if (image.transparentColor != null) writeV2ColorRef(writer, image.paletteProfile, image.transparentColor);
    if (bounds != null) {
      if (!implicitWhiteBackground) writeV2ColorRef(writer, image.paletteProfile, backgroundColor);
      writeV2CompactBounds(writer, bounds, image.width, image.height);
    }
    writer.writeAlignedBytes(body.payload);
    return {
      ...body,
      payload: writer.toBytes(),
    };
  }

  function tryBuildSolidBackgroundPayload(image, backgroundColor, referenceEncoding) {
    if (!image.pixels.every((pixel) => pixel === backgroundColor)) return null;
    const dynamic = isDynamicProfile(image.paletteProfile);
    const white = dynamic
      ? backgroundColor === globalIndexForProfileColorId(image.paletteProfile, 0)
      : backgroundColor === 0;
    const scan = !dynamic && white ? ScanMode.v : ScanMode.h;
    const writer = new BitWriter();
    writer.writeAlignedByte(
      (MCOImageCodec.v2EncodeVersion << 6) |
      (modeBits(ImageMode.rawGlobal) << 3) |
      (scanBits(scan) << 1),
    );
    writer.writeAlignedByte(
      (dynamic ? 0x80 : 0) |
      ((!dynamic || referenceEncoding === DynamicPaletteReferenceEncoding.banked8x64) ? 0x20 : 0) |
      (image.transparentColor != null ? MCOImageCodec.v2TransparentProfileFlag : 0) |
      (dynamic
        ? dynamicProfileId(image.paletteProfile) | (white ? 0x08 : 0)
        : fixedProfileId(image.paletteProfile)),
    );
    writer.writeAlignedByte(image.width - 1);
    writer.writeAlignedByte(image.height - 1);
    if (image.transparentColor != null) writeV2ColorRef(writer, image.paletteProfile, image.transparentColor);
    if (!white) writeV2ColorRef(writer, image.paletteProfile, backgroundColor);
    return { payload: writer.toBytes(), scan };
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
          ? [
              DynamicPaletteReferenceEncoding.flat,
              DynamicPaletteReferenceEncoding.banked8x64,
              DynamicPaletteReferenceEncoding.sortedDelta,
              DynamicPaletteReferenceEncoding.rangeRuns,
              DynamicPaletteReferenceEncoding.profileBitmap,
              DynamicPaletteReferenceEncoding.bankBitmaps,
            ]
          : [
              DynamicPaletteReferenceEncoding.flat,
              DynamicPaletteReferenceEncoding.sortedDelta,
              DynamicPaletteReferenceEncoding.rangeRuns,
              DynamicPaletteReferenceEncoding.profileBitmap,
            ])
      : [null];
    const modes = isDynamicProfile(image.paletteProfile) ? MCOImageCodec.dynamicBlockModes : MCOImageCodec.v2BlockModes;
    const candidates = [];
    let best = null;
    const outputTarget = options.outputTarget ?? MCOImageOutputTarget.text;
    function addExtendedCandidates(linear, scan, bg, bgInfo, dataWidth, dataHeight, bounds, refs) {
      for (const ref of refs) {
        for (const submode of [
          ExtendedImageMode.compactRle,
          ExtendedImageMode.compactSparse,
          ExtendedImageMode.lzPixels,
          ExtendedImageMode.quadtree,
          ExtendedImageMode.bitplanes,
        ]) {
          const built = tryBuildExtendedPayload(image, linear, scan, ref, {
            dataWidth,
            dataHeight,
            backgroundColor: bg,
            bounds,
            submode,
          });
          if (!built) continue;
          const candidate = candidateFromV2Payload(built.payload, ImageMode.extended, scan, {
            bounds,
            backgroundColor: bg,
            transparentColor: image.transparentColor,
            backgroundRank: bgInfo.rank,
            dynamicReferenceEncoding: ref,
            localPaletteSize: built.localPaletteSize,
            bitsPerLocalPixel: built.bitsPerLocalPixel,
            paletteProfile: image.paletteProfile,
            container: `${ExtendedImageModeName[submode]}${bounds ? '-bounds' : ''}`,
          });
          candidates.push(candidate);
          if (isBetterCandidate(candidate, best, outputTarget)) best = candidate;
        }
      }
    }

    for (const bgInfo of bgs) {
      const bg = bgInfo.color;
      const bounds = findBounds(image.pixels, image.width, image.height, bg);

      for (const ref of refs) {
        const solidPayload = tryBuildSolidBackgroundPayload(image, bg, ref);
        if (solidPayload) {
          const solidCandidate = candidateFromV2Payload(solidPayload.payload, ImageMode.rawGlobal, solidPayload.scan, {
            backgroundColor: bg,
            transparentColor: image.transparentColor,
            backgroundRank: bgInfo.rank,
            dynamicReferenceEncoding: ref,
            localPaletteSize: 1,
            bitsPerLocalPixel: 0,
            paletteProfile: image.paletteProfile,
            container: 'solid-bg',
          });
          candidates.push(solidCandidate);
          if (isBetterCandidate(solidCandidate, best, outputTarget)) best = solidCandidate;
        }
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
          if (isBetterCandidate(candidate, best, outputTarget)) best = candidate;
        }
      }

      for (const scan of Object.values(ScanMode)) {
        const linear = toScanOrder(image.pixels, image.width, image.height, scan);
        addExtendedCandidates(
          linear,
          scan,
          bg,
          bgInfo,
          image.width,
          image.height,
          null,
          refs,
        );
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
            if (isBetterCandidate(candidate, best, outputTarget)) best = candidate;
          }
        }

        if (bounds.area < image.width * image.height) {
          const cropped = cropPixels(image.pixels, image.width, bounds);
          const boundedLinear = toScanOrder(cropped, bounds.width, bounds.height, scan);
          addExtendedCandidates(
            boundedLinear,
            scan,
            bg,
            bgInfo,
            bounds.width,
            bounds.height,
            bounds,
            refs,
          );
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
              if (isBetterCandidate(candidate, best, outputTarget)) best = candidate;
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
    ExtendedImageMode,
    ExtendedImageModeName,
    ScanMode,
    ScanModeName,
    DynamicPaletteReferenceEncoding,
    DynamicPaletteReferenceEncodingName,
    MCOImageEncodingVersion,
    MCOImageOutputTarget,
    DynamicGlobal512: DynamicGlobal512Current,
    DynamicGlobalIndices: DynamicGlobalIndicesCurrent,
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

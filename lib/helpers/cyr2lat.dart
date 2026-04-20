class Cyr2Lat {
  static Map<String, String> _charMap = {
    'А': 'A',
    'В': 'B',
    'Е': 'E',
    'Ё': 'E',
    'З': '3',
    'К': 'K',
    'М': 'M',
    'Н': 'H',
    'О': 'O',
    'Р': 'P',
    'С': 'C',
    'Т': 'T',
    'Х': 'X',
    'Ь': 'b',
    'а': 'a',
    //'б': '6',
    'е': 'e',
    'ё': 'e',
    //'к': 'k',
    'о': 'o',
    'р': 'p',
    'с': 'c',
    'у': 'y',
    'х': 'x',
  };

  static void setCharMap(Map<String, String> charMap) {
    _charMap = Map.from(charMap);
  }

  static String encode(String text) {
    if (text.isEmpty) return text;
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_charMap[char] ?? char);
    }
    return buffer.toString();
  }
}

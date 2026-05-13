class Cyr2Lat {
  static const Map<String, String> defaultCharMap = {
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
    'е': 'e',
    'ё': 'e',
    'о': 'o',
    'р': 'p',
    'с': 'c',
    'у': 'y',
    'х': 'x',
  };

  static const Map<String, String> extendedCharMap = {
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
    'т': 'm',
    'п': 'n',
    'и': 'u',
    'е': 'e',
    'ё': 'e',
    'о': 'o',
    'р': 'p',
    'с': 'c',
    'у': 'y',
    'х': 'x',
  };

  static const Map<String, String> transliterationCharMap = {
    'А': 'A',
    'Б': 'B',
    'В': 'V',
    'Г': 'G',
    'Д': 'D',
    'Е': 'E',
    'Ё': 'E',
    'Ж': 'Zh',
    'З': 'Z',
    'И': 'I',
    'Й': 'Y',
    'К': 'K',
    'Л': 'L',
    'М': 'M',
    'Н': 'N',
    'О': 'O',
    'П': 'P',
    'Р': 'R',
    'С': 'S',
    'Т': 'T',
    'У': 'U',
    'Ф': 'F',
    'Х': 'H',
    'Ц': 'C',
    'Ч': 'Ch',
    'Ш': 'Sh',
    'Щ': 'Sch',
    'Ъ': '',
    'Ы': 'Y',
    'Ь': '',
    'Э': 'E',
    'Ю': 'Yu',
    'Я': 'Ya',
    'а': 'a',
    'б': 'b',
    'в': 'v',
    'г': 'g',
    'д': 'd',
    'е': 'e',
    'ё': 'e',
    'ж': 'zh',
    'з': 'z',
    'и': 'i',
    'й': 'y',
    'к': 'k',
    'л': 'l',
    'м': 'm',
    'н': 'n',
    'о': 'o',
    'п': 'p',
    'р': 'r',
    'с': 's',
    'т': 't',
    'у': 'u',
    'ф': 'f',
    'х': 'h',
    'ц': 'c',
    'ч': 'ch',
    'ш': 'sh',
    'щ': 'sch',
    'ъ': '',
    'ы': 'y',
    'ь': '',
    'э': 'e',
    'ю': 'yu',
    'я': 'ya',
  };

  static final RegExp _prefixRegExp = RegExp(r'\@\[[\S\s]+\] ');

  static Map<String, String> _charMap = Map.from(defaultCharMap);

  static void setCharMap(Map<String, String> charMap) {
    _charMap = Map.from(charMap);
  }

  static String encode(String text) {
    if (text.isEmpty) return text;
    final buffer = StringBuffer();

    final senderName = extractSenderName(text);
    final msgText = removeSenderName(text);

    for (final rune in msgText.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_charMap[char] ?? char);
    }

    return senderName + buffer.toString();
  }

  static String removeSenderName(String text) {
    final match = _prefixRegExp.matchAsPrefix(text);
    if (match != null) {
      return text.substring(match.end);
    }
    return text;
  }

  static String extractSenderName(String text) {
    final match = _prefixRegExp.matchAsPrefix(text);
    if (match != null) {
      return match.group(0) ?? '';
    }
    return '';
  }
}

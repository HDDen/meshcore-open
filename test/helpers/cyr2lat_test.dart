import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/cyr2lat.dart';

// Latin look-alikes cannot be told from Cyrillic in source, so expectations
// are assembled from the parts typed as they are, text encoded on its own,
// and text put through the table directly.
void main() {
  String mapped(String text) => [
    for (final rune in text.runes)
      Cyr2Lat.defaultCharMap[String.fromCharCode(rune)] ??
          String.fromCharCode(rune),
  ].join();

  setUp(() => Cyr2Lat.setCharMap(Cyr2Lat.defaultCharMap));

  group('Cyr2Lat reply mention', () {
    test('keeps the mention a message starts with as typed', () {
      expect(
        Cyr2Lat.encode('@[Вася] привет'),
        '@[Вася] ${Cyr2Lat.encode('привет')}',
      );
      expect(
        Cyr2Lat.encode('@[Дед Мороз] привет'),
        '@[Дед Мороз] ${Cyr2Lat.encode('привет')}',
      );
    });

    test('transliterates the text before a later mention', () {
      const rest = 'привет @[Петя] как дела';

      expect(Cyr2Lat.encode(rest), isNot(rest));
      expect(
        Cyr2Lat.encode('@[Вася] $rest'),
        '@[Вася] ${Cyr2Lat.encode(rest)}',
      );
    });

    test('transliterates the quote line and the text around a colour tag', () {
      const rest = '>цитата\nтекст [r]красный[/r] дальше';

      expect(Cyr2Lat.encode(rest), isNot(rest));
      expect(
        Cyr2Lat.encode('@[Вася] $rest'),
        '@[Вася] ${Cyr2Lat.encode(rest)}',
      );
    });
  });

  group('Cyr2Lat square brackets', () {
    test('keeps what sits inside them as typed', () {
      expect(
        Cyr2Lat.encode('привет @[Петя], смотри [заметку]'),
        '${mapped('привет @')}[Петя]${mapped(', смотри ')}[заметку]',
      );
      expect(
        Cyr2Lat.encode('@[Вася] привет @[Петя]'),
        '@[Вася] ${mapped('привет @')}[Петя]',
      );
    });

    test('transliterates the text a colour tag encloses', () {
      expect(Cyr2Lat.encode('[r]красный[/r]'), '[r]${mapped('красный')}[/r]');
    });

    test('protects nothing behind a bracket that is never closed', () {
      expect(Cyr2Lat.encode('цена [от ста'), mapped('цена [от ста'));
    });

    test('transliterates a reply quote line whole, as receivers match it', () {
      expect(
        Cyr2Lat.encode('@[Вася] >спроси @[Петя]\nладно [Петя]'),
        '@[Вася] ${mapped('>спроси @[Петя]\n')}${mapped('ладно ')}[Петя]',
      );
    });

    test('encoding twice changes nothing more', () {
      const text = '@[Вася] >спроси @[Петя]\nладно [Петя] [r]да[/r]';
      final once = Cyr2Lat.encode(text);

      expect(Cyr2Lat.encode(once), once);
    });
  });
}

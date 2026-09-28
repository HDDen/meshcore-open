import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/MCOtxt/mcotxt.dart';
import 'package:meshcore_open/helpers/mcotxt_app_codec.dart';

// The contract anything that remembers an encoding relies on: the same text
// encodes to the same bytes every time, the language pair is part of what
// decides them, explicit options win over the default pair, and what a
// caller does with one result never reaches a later one.

const _texts = [
  'Привет, как дела?',
  'Hello there, meeting at seven.',
  'Смешанный text with цифрами 12345 и знаками!!!',
  'Поднимаемся на перевал к обеду, связь через ретранслятор на хребте.',
];

void main() {
  tearDown(() => MCOtxtCodec.defaultLanguagePair = null);

  test('the same text encodes to the same bytes and bit length every time',
      () {
    for (final pair in [null, MCOtxtLanguagePair.forLocale('ru')]) {
      MCOtxtCodec.defaultLanguagePair = pair;
      for (final text in _texts) {
        final first = MCOtxtCodec.encode(text);
        final second = MCOtxtCodec.encode(text);
        expect(second.data, first.data, reason: text);
        expect(second.bitLength, first.bitLength, reason: text);
        expect(second.encodingMode, first.encodingMode, reason: text);
        expect(second.decodedText, first.decodedText, reason: text);
        expect(second.languageA, first.languageA, reason: text);
        expect(second.languageB, first.languageB, reason: text);
      }
    }
  });

  test('the default language pair is part of the result, and explicit '
      'options win over it', () {
    const text = 'Привет, как дела? Hello!';
    MCOtxtCodec.defaultLanguagePair = MCOtxtLanguagePair.forLocale('ru');
    final russianFirst = MCOtxtCodec.encode(text);
    MCOtxtCodec.defaultLanguagePair = MCOtxtLanguagePair.forLocale('en');
    final englishFirst = MCOtxtCodec.encode(text);

    expect(russianFirst.languageA, MCOtxtLanguageId.ru);
    expect(englishFirst.languageA, MCOtxtLanguageId.en);
    expect(englishFirst.data, isNot(equals(russianFirst.data)));

    final explicit = MCOtxtCodec.encode(
      text,
      options: const MCOtxtEncodeOptions(
        languageA: MCOtxtLanguageId.ru,
        languageB: MCOtxtLanguageId.en,
      ),
    );
    expect(explicit.data, russianFirst.data);
    expect(explicit.bitLength, russianFirst.bitLength);
  });

  test('a result a caller changed does not change a later one', () {
    const text = 'Привет, как дела?';
    final first = MCOtxtCodec.encode(text);
    final snapshot = List<int>.of(first.data);

    first.data.fillRange(0, first.data.length, 0);

    final second = MCOtxtCodec.encode(text);
    expect(second.data, snapshot);
    expect(MCOtxtCodec.decode(second.data, bitLength: second.bitLength).text,
        text);
  });

  test('the text transport is the same for the same input', () {
    MCOtxtCodec.defaultLanguagePair = MCOtxtLanguagePair.forLocale('ru');
    String transport() => MCOtxtAppCodec.encodeTextTransport(
      text: 'Привет, как дела?',
      timestamp: 1700000000,
    );

    final first = transport();
    expect(first, startsWith('mct:'));
    expect(transport(), first);
    expect(
      MCOtxtAppCodec.tryDecodeTextPayloadMessage(first)?.text,
      'Привет, как дела?',
    );
  });
}

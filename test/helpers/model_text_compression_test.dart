import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/message_text_codec.dart';
import 'package:meshcore_open/helpers/model_text_compression.dart';
import 'package:meshcore_open/helpers/smaz.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ModelTextCompression.ensureInitialized();
  });

  test('round-trips compressed multilingual text', () {
    const samples = <String>[
      'Привет, как дела сегодня?',
      'Battery at 40%, switching to power save',
      '今日の天気は晴れ、気温22度',
      'مرحبا، كيف حالك اليوم؟',
    ];

    for (final text in samples) {
      final encoded = ModelTextCompression.encodeIfSmaller(text);
      final decoded = MessageTextCodec.decode(encoded);
      expect(decoded, text);
    }
  });

  test('leaves plain short text untouched when compression is not smaller', () {
    const text = 'ok';
    expect(ModelTextCompression.encodeIfSmaller(text), text);
  });

  test('generic message decoder still supports smaz payloads', () {
    const text = 'hello there general kenobi';
    final smazEncoded = Smaz.encodeIfSmaller(text);
    expect(MessageTextCodec.decode(smazEncoded), text);
  });
}

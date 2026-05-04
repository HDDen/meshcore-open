import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mesh_compressor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final json = await File(
      'assets/models/model-universal-10lang.json',
    ).readAsString();
    await MeshCompressor.instance.initializeFromJsonString(json);
  });

  test('roundtrips multilingual text through byte codec', () {
    const samples = [
      'Battery at 40%, switching to power save',
      'Привет, как дела? Проверка связи.',
      'مرحبا، كيف حالك اليوم؟',
      '今日の天気は晴れ、気温22度',
      'Emoji test: 👍📡🙂',
    ];

    for (final sample in samples) {
      final compressed = MeshCompressor.instance.compressToBytes(sample);
      final decoded = MeshCompressor.instance.decompressBytes(compressed);
      expect(decoded, sample);
    }
  });

  test('encodes with mcmp prefix when beneficial and decodes back', () {
    const text =
        'Battery at 40%, switching to power save and checking channel five for traffic.';

    final encoded = MeshCompressor.instance.encodeIfSmaller(text);
    expect(encoded, startsWith(MeshCompressor.prefix));

    final decoded = MeshCompressor.instance.tryDecodePrefixed(encoded);
    expect(decoded, text);
  });

  test('leaves tiny messages uncompressed', () {
    expect(MeshCompressor.instance.encodeIfSmaller('ok'), 'ok');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/mco_image_pack_originals.dart';

void main() {
  group('MCOimg pack original formats', () {
    test('recognizes the compound Lottie suffix explicitly', () {
      expect(
        mcoImageOriginalFormatForFileName('animation.LOTTIE.JSON'),
        McoImageOriginalFormat.lottieJson,
      );
      expect(
        mcoImageOriginalFormatForFileName('animation.LOTTIE'),
        McoImageOriginalFormat.lottie,
      );
      expect(isMcoImageOriginalFileName('animation.json'), isFalse);
      expect(isMcoImageOriginalFileName('animation.webp'), isFalse);
      expect(isMcoImageOriginalFileName('animation.apng'), isFalse);
    });

    test('orders supported originals by wire-pack preference', () {
      final names = [
        'preview.jpeg',
        'preview.gif',
        'preview.png',
        'preview.jpg',
        'preview.lottie',
        'preview.lottie.json',
      ]..sort(compareMcoImageOriginalFileNames);

      expect(names, [
        'preview.lottie.json',
        'preview.lottie',
        'preview.png',
        'preview.gif',
        'preview.jpg',
        'preview.jpeg',
      ]);
    });

    test('uses natural file-name order within the same format', () {
      final names = ['preview10.png', 'preview2.png', 'preview1.png']
        ..sort(compareMcoImageOriginalFileNames);

      expect(names, ['preview1.png', 'preview2.png', 'preview10.png']);
    });

    test('reads both legacy string and candidate-list index entries', () {
      final index = decodeMcoImageOriginalsIndex({
        'legacy': 'pack/images/1/preview.png',
        'current': [
          'pack/images/2/preview.lottie.json',
          'pack/images/2/preview.png',
        ],
      });

      expect(index['legacy'], ['pack/images/1/preview.png']);
      expect(index['current'], [
        'pack/images/2/preview.lottie.json',
        'pack/images/2/preview.png',
      ]);
    });

    test('rebuilds only missing, malformed, or legacy indexes', () {
      expect(mcoImageOriginalsIndexNeedsRebuild(null), isTrue);
      expect(
        mcoImageOriginalsIndexNeedsRebuild({'hash': 'preview.png'}),
        isTrue,
      );
      expect(
        mcoImageOriginalsIndexNeedsRebuild({
          'hash': ['preview.png'],
        }),
        isFalse,
      );
    });
  });
}

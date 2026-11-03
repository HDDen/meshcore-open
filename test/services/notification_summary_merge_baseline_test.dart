import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/gif_helper.dart';
import 'package:meshcore_open/helpers/mcoimg_codec.dart';
import 'package:meshcore_open/helpers/reaction_helper.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/services/notification_service.dart';
import 'package:meshcore_open/services/received_image_store.dart';

// Accepted fork baseline, extended with U06c1 behavior. No plugin
// initialization, network, filesystem, model inference or rendering:
// only notification text selection. MCOimg keeps its separate attachment path.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  String format(String text) =>
      NotificationService.formatNotificationText(text, l10n);

  group('U06c1: notification summaries and fork invariants', () {
    test('ordinary text, whitespace and multiline content are unchanged', () {
      for (final text in [
        '',
        '  hello  ',
        'Привет, @имя!',
        'first line\nsecond line',
        'see you at m:ain street',
        'https://example.org/photo.png',
        'g:not a compact GIF',
        'aeic:1:not-an-image-id',
        'r:abcd:zz',
        'm:999,999|invalid|',
      ]) {
        expect(format(text), text, reason: text);
      }
    });

    test('both reaction protocols retain their emoji', () {
      final emojiIndex = ReactionHelper.emojiToIndex('👍');
      expect(emojiIndex, isNotNull);
      final compact = ReactionHelper.encodeReaction('ab12', emojiIndex!);
      for (final text in [
        compact,
        '👍\nabcd2345',
        '@[Alice]👍\nabcd2345',
        '👍@[Alice]\nabcd2345',
      ]) {
        expect(format('  $text  '), 'Reacted 👍', reason: text);
      }
    });

    test('compact GIF is summarized without fetching its contents', () {
      final text = GifHelper.encodeGif('xT9IgG50Fb7Mi0prBC');
      expect(format('  $text  '), 'Sent a GIF');
    });

    test('recognized GIF URLs are summarized without fetching them', () {
      for (final text in [
        'https://media.giphy.com/media/xT9IgG50Fb7Mi0prBC/giphy.gif',
        'https://giphy.com/gifs/xT9IgG50Fb7Mi0prBC',
      ]) {
        expect(GifHelper.parseGif(text), 'xT9IgG50Fb7Mi0prBC');
        expect(format(text), 'Sent a GIF');
      }
    });

    test('shared locations keep their label and omit encoded coordinates', () {
      expect(format('m:45.5,-122.6|Camp|poi'), 'Shared a location: Camp');
      expect(format('m:45.5,-122.6||poi'), 'Shared a location');
      expect(
        format('Alice: m:45.5,-122.6|Camp|poi'),
        'Shared a location: Camp',
      );
    });

    test('AEIC reference is summarized without opening the store', () {
      final text = ReceivedImageRef.encode('0a1b2c3d4e5f60');
      expect(ReceivedImageRef.parse(text), '0a1b2c3d4e5f60');
      expect(format(text), 'Sent an image');
      expect(NotificationService.isMcoImageNotificationText(text), isFalse);
    });

    test('MCOimg label survives a sender prefix and surrounding whitespace', () {
      // The same tiny fixture as the existing queued-notification tests.
      // This exercises the legacy text codec, not the neural AEIC backend.
      final image = MCOImage(
        width: 2,
        height: 2,
        paletteProfile: PaletteProfile.mono,
        pixels: const [0, 0, 0, 0],
      );
      final text = MCOImageCodec().encode(image, backgroundColor: 0).text;
      for (final message in [text, 'Alice: $text', '  Alice: $text  ']) {
        expect(NotificationService.isMcoImageNotificationText(message), isTrue);
        expect(format(message), 'MCOimg');
      }
    });

    test('plain text after a sender prefix is not an MCOimg attachment', () {
      const text = 'Alice: ordinary message';
      expect(NotificationService.isMcoImageNotificationText(text), isFalse);
      expect(format(text), text);
    });

    for (final language in ['en', 'ru']) {
      test('summaries use the supplied locale ($language)', () {
        final local = lookupAppLocalizations(Locale(language));
        final expected = language == 'ru'
            ? [
                'Реакция 👍',
                'Отправлен GIF',
                'Отправлено изображение',
                'Отправлена геопозиция',
                'Отправлена геопозиция: Лагерь',
              ]
            : [
                'Reacted 👍',
                'Sent a GIF',
                'Sent an image',
                'Shared a location',
                'Shared a location: Лагерь',
              ];
        final inputs = [
          '👍\nabcd2345',
          'g:xT9IgG50Fb7Mi0prBC',
          'aeic:1:0a1b2c3d4e5f60',
          'm:45.5,-122.6||poi',
          'm:45.5,-122.6|Лагерь|poi',
        ];
        for (var i = 0; i < inputs.length; i++) {
          expect(
            NotificationService.formatNotificationText(inputs[i], local),
            expected[i],
            reason: inputs[i],
          );
        }
      });
    }
  });
}

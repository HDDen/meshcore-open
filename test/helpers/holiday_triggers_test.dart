import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/holiday_triggers.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';

void main() {
  group('holidayAnimationFor', () {
    test('every greeting in every language triggers its holiday', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(Locale(locale.languageCode));
        for (final animation in HolidayAnimation.values) {
          final greetings = holidayGreetingsIn(l10n, animation);
          expect(greetings.trim(), isNotEmpty, reason: '$locale $animation');
          for (final phrase in greetings.split('|')) {
            expect(
              holidayAnimationFor('$phrase!'),
              animation,
              reason: '${locale.languageCode}: "$phrase"',
            );
          }
        }
      }
    });

    test('case, punctuation and surrounding words do not matter', () {
      expect(
        holidayAnimationFor('HAPPY HALLOWEEN!!! 🎃'),
        HolidayAnimation.halloween,
      );
      expect(
        holidayAnimationFor('hey all, happy new year’s from the mesh'),
        HolidayAnimation.newYear,
      );
      expect(holidayAnimationFor('#HappyNewYear'), HolidayAnimation.newYear);
      expect(
        holidayAnimationFor('Merry  Christmas, everyone'),
        HolidayAnimation.christmas,
      );
      expect(
        holidayAnimationFor('happy thanksgiving y’all'),
        HolidayAnimation.thanksgiving,
      );
      expect(holidayAnimationFor('FELIZ NAVIDAD'), HolidayAnimation.christmas);
      expect(holidayAnimationFor('С НОВЫМ ГОДОМ!'), HolidayAnimation.newYear);
      expect(holidayAnimationFor('みんな、メリークリスマス！'), HolidayAnimation.christmas);
      expect(holidayAnimationFor('祝大家新年快乐'), HolidayAnimation.newYear);
    });

    test('ordinary messages and near misses do not trigger', () {
      for (final text in [
        '',
        'happy',
        'halloween party at 8?',
        'feliz natalia', // a name, not "feliz natal"
        'my christmas tree fell over',
        'new year plans?',
        'unhappy new yearly report',
        'thanksgiving dinner menu',
      ]) {
        expect(holidayAnimationFor(text), isNull, reason: text);
      }
    });
  });

}

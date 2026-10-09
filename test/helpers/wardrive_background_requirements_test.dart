import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/wardrive_background_requirements.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';

// Which requirement a tap on the background wardriving option asks for: the
// first missing one, then the next missing one after the one asked last
// time, round the end, so a screen the user backed out of is not the only
// one offered. Every requirement has a name for the messages in both
// languages the option is localized in.

const _notifications = WardriveBackgroundRequirement.notifications;
const _services = WardriveBackgroundRequirement.locationServices;
const _always = WardriveBackgroundRequirement.locationAlways;
const _background = WardriveBackgroundRequirement.backgroundActivity;
const _battery = WardriveBackgroundRequirement.batteryOptimization;

void main() {
  test('the first missing requirement is asked for first', () {
    expect(nextWardriveBackgroundRequirement([_always, _battery], null), _always);
    expect(
      nextWardriveBackgroundRequirement([_background, _battery], null),
      _background,
    );
    expect(
      nextWardriveBackgroundRequirement(
        WardriveBackgroundRequirement.values,
        null,
      ),
      _notifications,
    );
  });

  test('after one was asked for, the next missing one follows, round the '
      'end', () {
    expect(
      nextWardriveBackgroundRequirement([_notifications, _always], _notifications),
      _always,
    );
    expect(
      nextWardriveBackgroundRequirement([_notifications, _always], _always),
      _notifications,
    );
    expect(nextWardriveBackgroundRequirement([_always], _always), _always);
    expect(
      nextWardriveBackgroundRequirement([_background, _battery], _background),
      _battery,
    );
    // The one asked last time was granted meanwhile: the next after it.
    expect(
      nextWardriveBackgroundRequirement([_notifications, _battery], _services),
      _battery,
    );
  });

  test('with nothing missing there is nothing to ask for', () {
    expect(nextWardriveBackgroundRequirement(const [], null), isNull);
    expect(nextWardriveBackgroundRequirement(const [], _always), isNull);
  });

  test('every requirement is named, apart from the others, in en and ru', () {
    for (final locale in const [Locale('en'), Locale('ru')]) {
      final l10n = lookupAppLocalizations(locale);
      final names = {
        for (final requirement in WardriveBackgroundRequirement.values)
          wardriveBackgroundRequirementText(l10n, requirement),
      };
      expect(names, hasLength(WardriveBackgroundRequirement.values.length));
      expect(names.every((name) => name.trim().isNotEmpty), isTrue);
    }
  });
}

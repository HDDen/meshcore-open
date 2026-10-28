import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/companion_cli_commands.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';

void main() {
  for (final locale in ['en', 'ru']) {
    test('Companion CLI catalog has local commands and conditional sections ($locale)', () async {
      final l10n = await AppLocalizations.delegate.load(Locale(locale));
      final sections = companionCliHelpSections(l10n);
      final entries = sections.expand((section) => section.commands).toList();
      final commands = entries.map((entry) => entry.command).toSet();
      expect(commands.length, entries.length);
      expect(commands, containsAll(companionCliQuickCommands));
      expect(commands, containsAll([
        'get tz.offset', 'set tz.offset <hours>',
        'set radio <freq>,<bw>,<sf>,<cr>',
        'set cad <on|off>', 'get path.hash.mode',
      ]));
      // Эти команды существуют в другом CLI, но не в локальном API 66.
      expect(commands.intersection({
        'help', 'advert', 'clock', 'discover.neighbors',
        'erase', 'rebuild', 'ls', 'cat', 'rm', 'clear stats',
      }), isEmpty);
      final wifi = sections.singleWhere((section) => section.title == l10n.companionCli_helpWifiTitle);
      expect(wifi.note, l10n.companionCli_helpWifiNote);
      expect(wifi.commands.length, 9);
      final hardware = sections.singleWhere((section) => section.title == l10n.companionCli_helpHardwareTitle);
      expect(hardware.note, l10n.companionCli_helpHardwareNote);
      expect(hardware.commands.map((entry) => entry.command), contains('get fan'));
      expect(entries.every((entry) => entry.description.trim().isNotEmpty), isTrue);
    });
  }

  test('PIN example leaves the number for the user and retains editable spacing', () {
    expect(companionCliCommandExample('set pin <PIN>'), 'set pin ');
    expect(companionCliCommandExample('get cad'), 'get cad');
  });
}

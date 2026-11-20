import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoa_theme_options.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/custom_theme.dart';
import 'package:meshcore_open/screens/contacts_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/mcoa_chat_list_style.dart';
import 'package:meshcore_open/widgets/mcoa_theme_color_control.dart';
import 'package:meshcore_open/widgets/mcoa_theme_editor.dart';
import 'package:meshcore_open/widgets/mcoa_theme_preview.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';
import 'package:meshcore_open/widgets/middle_ellipsis_text.dart';
import 'package:meshcore_open/widgets/unread_badge.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _colors = <String, Color>{
  'chats_border': Color(0xFF110001),
  'chats_background': Color(0xFF220002),
  'chats_title': Color(0xFF330003),
  'chats_preview': Color(0xFF440004),
  'chats_icons': Color(0xFF550005),
  'chats_index_border': Color(0xFF660006),
  'chats_index_background': Color(0xFF770007),
  'chats_index_text': Color(0xFF880008),
  'chats_index_dot': Color(0xFF990009),
  'chats_unread_background': Color(0xFFAA000A),
  'chats_unread_text': Color(0xFFBB000B),
  'chats_search_border': Color(0xFF101112),
  'chats_search_background': Color(0xFF202122),
  'chats_search_contacts_background': Color(0xFF515253),
  'chats_search_text': Color(0xFF303132),
  'chats_search_hint_icons': Color(0xFF404142),
  'chats_key': Color(0xFFCC000C),
  'chats_prefix_border': Color(0xFFDD000D),
  'chats_prefix_background': Color(0xFFEE000E),
  'chats_prefix_text': Color(0xFFFF000F),
};
const _theme = CustomTheme(
  id: 'custom:chat-lists', name: 'Lists',
  background: Color(0xFF17112A), accent: Color(0xFFA855F7),
);

void main() {
  late AppSettingsService settings;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    settings = AppSettingsService();
  });
  tearDown(() { settings.dispose(); });

  Widget app(Widget child) => ChangeNotifierProvider.value(
    value: settings,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  testWidgets('real channel and contact cards use all independent list slots', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final before = settings.settings.toJson();
    Widget preview(McoaThemeOptions options) => app(McoaThemePreview(
      theme: _theme.copyWith(mcoa: options), openedAt: DateTime(2026, 11, 20),
    ));
    Future<void> select(int tab) async {
      final target = find.byKey(ValueKey('theme-preview-tab-$tab'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(preview(const McoaThemeOptions()));
    await tester.pumpAndSettle();
    await select(2);
    final card = find.byKey(const ValueKey('channel_0'));
    expect(tester.widget<MeshCard>(card).color, isNull);
    expect(tester.widget<MeshCard>(card).borderColor, isNull);
    final baselineChip = tester.widget<StatusChip>(find.byType(StatusChip).first);
    expect(baselineChip.dotColor, isNull);
    expect(baselineChip.backgroundColor, isNull);

    await tester.pumpWidget(preview(const McoaThemeOptions(colors: _colors)));
    await tester.pumpAndSettle();
    final search = find.descendant(
      of: find.byKey(const ValueKey('theme-preview-channel-search')),
      matching: find.byType(TextField),
    );
    expect(search, findsOneWidget);
    final field = tester.widget<TextField>(search);
    expect(field.readOnly, isTrue);
    expect(field.decoration!.hintText, AppLocalizations.of(tester.element(search)).channels_searchChannels);
    expect(field.decoration!.fillColor, _colors['chats_search_background']);
    expect(field.decoration!.enabledBorder!.borderSide.color, _colors['chats_search_border']);
    expect(field.style!.color, _colors['chats_search_text']);
    expect(field.decoration!.hintStyle!.color, _colors['chats_search_hint_icons']);
    expect(field.decoration!.prefixIconColor, _colors['chats_search_hint_icons']);
    expect(field.decoration!.suffixIconColor, _colors['chats_search_hint_icons']);
    expect(tester.widget<MeshCard>(card).color, _colors['chats_background']);
    expect(tester.widget<MeshCard>(card).borderColor, _colors['chats_border']);
    expect(tester.widget<Text>(find.text('Public')).style!.color, _colors['chats_title']);
    final previews = tester.widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))
        .where((text) => text.textSpan != null);
    expect(previews, isNotEmpty);
    expect(previews.first.textSpan!.style!.color, _colors['chats_preview']);
    final chip = tester.widget<StatusChip>(find.byType(StatusChip).first);
    expect(chip.borderColor, _colors['chats_index_border']);
    expect(chip.backgroundColor, _colors['chats_index_background']);
    expect(chip.textColor, _colors['chats_index_text']);
    expect(chip.dotColor, _colors['chats_index_dot']);
    final unread = tester.widget<UnreadBadge>(find.descendant(of: card, matching: find.byType(UnreadBadge)));
    expect(unread.backgroundColor, _colors['chats_unread_background']);
    expect(unread.textColor, _colors['chats_unread_text']);
    final mute = tester.widgetList<Icon>(find.descendant(
      of: find.byKey(const ValueKey('channel_7')), matching: find.byType(Icon),
    )).where((icon) => icon.size == 14);
    expect(mute, isNotEmpty);
    expect(mute.first.color, _colors['chats_icons']);

    await select(3);
    final contact = find.byType(ContactThemePreviewTile).first;
    expect(tester.widget<MeshCard>(find.descendant(of: contact, matching: find.byType(MeshCard))).color,
        _colors['chats_background']);
    expect(tester.widget<Text>(find.text('Alice')).style!.color, _colors['chats_title']);
    expect(tester.widget<MiddleEllipsisText>(find.descendant(of: contact,
        matching: find.byType(MiddleEllipsisText))).style.color, _colors['chats_key']);
    final sample = tester.widget<ContactThemePreviewTile>(contact);
    final prefix = find.descendant(of: contact, matching: find.text(sample.contact.publicKeyPrefixHex(2)));
    expect(prefix, findsOneWidget);
    expect(tester.widget<Text>(prefix).style!.color, _colors['chats_prefix_text']);
    final prefixBox = tester.widget<Container>(find.ancestor(of: prefix, matching: find.byType(Container)).first);
    final decoration = prefixBox.decoration! as BoxDecoration;
    expect(decoration.color, _colors['chats_prefix_background']);
    expect((decoration.border! as Border).top.color, _colors['chats_prefix_border']);
    expect(tester.widget<Text>(find.text(sample.pathLabel)).style!.color, _colors['chats_icons']);
    expect(tester.widget<Text>(find.descendant(of: contact, matching: find.text(sample.lastSeenText))).style!.color,
        _colors['chats_icons']);

    await tester.pumpWidget(preview(const McoaThemeOptions(colors: _colors, showChannelIndices: false)));
    await tester.pumpAndSettle();
    await select(2);
    expect(find.byType(McoaChannelIndexChip), findsNothing);
    await tester.pumpWidget(preview(const McoaThemeOptions(colors: _colors, showChannelIndices: true)));
    await tester.pumpAndSettle();
    expect(find.byType(McoaChannelIndexChip), findsNWidgets(2));
    expect(settings.settings.toJson(), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Chats section follows Outgoing and editing remains a draft', (tester) async {
    final before = settings.settings.toJson();
    var options = const McoaThemeOptions();
    await tester.pumpWidget(app(StatefulBuilder(builder: (context, update) => McoaThemeEditor(
      theme: _theme.copyWith(mcoa: options),
      onChanged: (value) => update(() { options = value; }),
    ))));
    final outgoing = find.byKey(const ValueKey('theme-section-mcoa-outgoing-toggle'));
    final chats = find.byKey(const ValueKey('theme-section-mcoa-chats-toggle'));
    final preferences = find.byKey(const ValueKey('theme-section-mcoa-preferences-toggle'));
    expect(tester.getTopLeft(outgoing).dy, lessThan(tester.getTopLeft(chats).dy));
    expect(tester.getTopLeft(chats).dy, lessThan(tester.getTopLeft(preferences).dy));
    expect(find.byKey(const ValueKey('mcoa-color-chats_border')), findsNothing);
    await tester.ensureVisible(chats);
    await tester.tap(chats);
    await tester.pumpAndSettle();
    for (final entry in _colors.entries) {
      final control = find.descendant(
        of: find.byKey(ValueKey('mcoa-color-${entry.key}')),
        matching: find.byType(McoaThemeColorControl),
      );
      expect(control, findsOneWidget);
      tester.widget<McoaThemeColorControl>(control).onChanged(entry.value);
      await tester.pump();
    }
    expect(options.colors, _colors);
    await tester.ensureVisible(preferences);
    await tester.tap(preferences);
    await tester.pumpAndSettle();
    final indices = find.byKey(const ValueKey('mcoa-channel-indices'));
    tester.widget<SwitchListTile>(indices).onChanged!(true);
    await tester.pump();
    expect(options.showChannelIndices, isTrue);
    expect(settings.settings.toJson(), before);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test('activation sets channel indices once and reload preserves manual changes', () async {
    await PrefsManager.initialize();
    await settings.loadSettings();
    await settings.saveCustomTheme(_theme.copyWith(
      mcoa: const McoaThemeOptions(showChannelIndices: true),
    ), apply: true);
    expect(settings.settings.hideChannelIndexIndicator, isFalse);
    await settings.updateSettings(settings.settings.copyWith(hideChannelIndexIndicator: true));
    expect(settings.settings.activeThemeId, _theme.id);
    await settings.loadSettings();
    expect(settings.settings.hideChannelIndexIndicator, isTrue);
  });
}

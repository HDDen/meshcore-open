import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/readable_accent.dart';
import 'package:meshcore_open/helpers/snack_bar_builder.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/chat_background.dart';
import 'package:meshcore_open/models/custom_theme.dart';
import 'package:meshcore_open/screens/themes_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/chat_background_image_store.dart';
import 'package:meshcore_open/services/chat_background_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';
import 'package:meshcore_open/theme/theme_icons.dart';
import 'package:meshcore_open/widgets/adaptive_app_bar_title.dart';
import 'package:meshcore_open/widgets/chat_background.dart';
import 'package:meshcore_open/widgets/quick_switch_bar.dart';
import 'package:meshcore_open/widgets/themed_icon.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/wrapping_label_expectations.dart';

const _key = 'contact:demo';
const _photoTint = ChatBackground.color(Color(0xFF109060));

void main() {
  late AppSettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    settings = AppSettingsService();
    await settings.loadSettings();
    addTearDown(() {
      settings.dispose();
      PrefsManager.reset();
    });
  });

  Widget app(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      // The store queue must start in the widget test's FakeAsync zone.
      ChangeNotifierProvider(
        create: (_) => ChatBackgroundService(
          settings,
          imageStore: InMemoryChatBackgroundImageStore(),
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: child,
    ),
  );

  testWidgets('U19b: selecting a preset and Default preserves stock mode', (tester) async {
    await settings.setThemeMode('light');
    await tester.pumpWidget(app(const ThemesScreen()));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ThemesScreen)),
    );

    final preset = CustomTheme.presets.first;
    await tester.tap(find.text(preset.name));
    await tester.pumpAndSettle();
    expect(settings.activeCustomTheme, preset);

    await tester.tap(find.text(l10n.themes_default));
    await tester.pumpAndSettle();
    expect(settings.activeCustomTheme, isNull);
    expect(settings.settings.themeMode, 'light');
    expect(tester.takeException(), isNull);
  });

  testWidgets('U19b: the editor saves and applies a new theme', (tester) async {
    await tester.pumpWidget(app(const ThemesScreen()));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ThemesScreen)),
    );
    await tester.tap(find.text(l10n.themes_create));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Field notes');
    await tester.pump();

    final save = find.text(l10n.themes_saveAndUse);
    await tester.scrollUntilVisible(
      save,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(settings.activeCustomTheme?.name, 'Field notes');
    expect(settings.settings.customThemes.single, settings.activeCustomTheme);
    expect(find.text('Field notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('U19b: a new backdrop keeps the draft and input usable', (tester) async {
    await tester.pumpWidget(
      app(
        const Scaffold(
          body: ChatBackdrop(
            chatKey: _key,
            child: Center(child: TextField()),
          ),
        ),
      ),
    );
    final backdrop = tester.element(find.byType(ChatBackdrop));
    final backgrounds = backdrop.read<ChatBackgroundService>();
    final input = find.byType(TextField);
    await tester.enterText(input, 'draft');
    final field = tester.state<EditableTextState>(find.byType(EditableText));

    await backgrounds.setChatBackground(_key, _photoTint);
    await tester.pump();
    expect(find.byType(ChatBackgroundLayer), findsOneWidget);
    expect(tester.state<EditableTextState>(find.byType(EditableText)), same(field));
    expect(find.text('draft'), findsOneWidget);
    await tester.enterText(input, 'draft updated');
    expect(find.text('draft updated'), findsOneWidget);

    await backgrounds.setChatBackground(_key, null);
    await tester.pump();
    expect(find.byType(ChatBackgroundLayer), findsNothing);
    expect(find.text('draft updated'), findsOneWidget);
  });

  for (final locale in ['ru', 'en']) {
    testWidgets('U29 baseline: large titles retain the complete text ($locale)',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 720);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: Locale(locale),
        theme: MeshTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            appBar: AppBar(
              title: AdaptiveAppBarTitle(l10n.settings_modSettings),
              actions: [
                IconButton(onPressed: () {}, icon: const Icon(Icons.info_outline)),
              ],
            ),
          );
        }),
      ));
      final l10n = AppLocalizations.of(tester.element(find.byType(AppBar)));
      final title = find.text(l10n.settings_modSettings);
      expectCompleteWrappingLabel(tester, title, wraps: false);
      final titleRect = tester.getRect(title);
      final appBar = tester.getRect(find.byType(AppBar));
      final action = tester.getRect(find.byIcon(Icons.info_outline));
      expect(titleRect.left, greaterThanOrEqualTo(appBar.left));
      expect(titleRect.right, lessThanOrEqualTo(action.left));
      expect(titleRect.bottom, lessThanOrEqualTo(appBar.bottom));
      expect(tester.takeException(), isNull);
    });
  }

  test('U29: Snackbar text and actions contrast with the themed surface', () {
    final custom = MeshTheme.fromCustom(const CustomTheme(
      id: 'custom:mid',
      name: 'Mid',
      background: Color(0xFF747474),
      accent: Color(0xFF9C8787),
    ));
    for (final theme in [MeshTheme.light(), MeshTheme.dark(), custom]) {
      final snackBar = theme.snackBarTheme;
      final background = snackBar.backgroundColor!;
      expect(meshContrastRatio(snackBar.actionTextColor!, background),
          greaterThanOrEqualTo(4.5));
      expect(meshContrastRatio(snackBar.contentTextStyle!.color!, background),
          greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('U29: Snackbar with an action still expires', (tester) async {
    late BuildContext snackContext;
    await tester.pumpWidget(MaterialApp(
      theme: MeshTheme.light(),
      home: Scaffold(
        body: Builder(builder: (context) {
          snackContext = context;
          return const SizedBox();
        }),
      ),
    ));
    showDismissibleSnackBar(
      snackContext,
      content: const Text('Contact added'),
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('U29: quick switch releases focus without changing the draft',
      (tester) async {
    final focus = FocusNode();
    final controller = TextEditingController(text: 'Draft');
    addTearDown(focus.dispose);
    addTearDown(controller.dispose);
    int? destination;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: TextField(focusNode: focus, controller: controller),
        bottomNavigationBar: QuickSwitchBar(
          selectedIndex: 0,
          onDestinationSelected: (index) => destination = index,
        ),
      ),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(QuickSwitchBar)),
    );
    await tester.tap(find.text(l10n.nav_channels));
    await tester.pumpAndSettle();
    expect(destination, 1);
    expect(focus.hasFocus, isFalse);
    expect(controller.text, 'Draft');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('U19b: custom palettes and icons resolve with stock fallbacks', (tester) async {
    const theme = CustomTheme(
      id: 'custom:forest',
      name: 'Forest',
      background: Color(0xFF102018),
      accent: Color(0xFF48AB78),
      icons: {
        'repeater': ThemeIconOverride.icon('park'),
        'contacts': ThemeIconOverride.icon('bolt'),
      },
    );
    final palette = MeshTheme.fromCustom(theme);
    expect(palette.scaffoldBackgroundColor, theme.background);
    expect(palette.brightness, Brightness.dark);
    expect(palette.extension<MeshBubbleTheme>()?.me, isNot(MeshPalette.me));
    expect(palette.extension<MeshMapTheme>()?.tileTint, theme.background);
    await tester.pumpWidget(
      MaterialApp(
        theme: palette,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          bottomNavigationBar: QuickSwitchBar(
            selectedIndex: 0,
            contactsUnreadCount: 7,
            onDestinationSelected: (_) {},
          ),
          body: const Row(
            children: [
              ThemedIcon(ThemeIconSlot.mapRepeater),
              ThemedIcon(ThemeIconSlot.send),
            ],
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.park), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
    final themedContact = find.byIcon(Icons.bolt);
    expect(themedContact, findsOneWidget);
    final badge = find.ancestor(of: themedContact, matching: find.byType(Badge));
    expect(find.descendant(of: badge, matching: find.text('7')), findsOneWidget);
  });
}

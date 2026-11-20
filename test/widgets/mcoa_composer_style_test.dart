import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoa_theme_options.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/custom_theme.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';
import 'package:meshcore_open/widgets/byte_count_input.dart';
import 'package:meshcore_open/widgets/chat_additional_actions_menu.dart';
import 'package:meshcore_open/widgets/contact_chat_composer.dart';

const _theme = CustomTheme(
  id: 'custom:composer',
  name: 'Composer',
  background: Colors.white,
  accent: Colors.blue,
  mcoa: McoaThemeOptions(colors: {
    'composer_background': Color(0xFF112233),
    'composer_action_icon': Color(0xFF223344),
    'composer_input_border': Color(0xFF334455),
    'composer_input_background': Color(0xFF445566),
    'composer_input_hint': Color(0xFF556677),
    'composer_input_text': Color(0xFF667788),
    'composer_send_background': Color(0xFF778899),
    'composer_send_icon': Color(0xFF8899AA),
    'composer_counter': Color(0xFF99AABB),
    'composer_counter_warning': Color(0xFFAABBCC),
    'composer_counter_error': Color(0xFFBBCCDD),
  }),
);

Widget _app(Widget child) => MaterialApp(
  theme: MeshTheme.fromCustom(_theme),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('composer colors reach the field, send button and all counter states', (tester) async {
    final controller = TextEditingController(text: '12345');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(_app(ContactChatComposer(
      contactName: 'Alice',
      controller: controller,
      focusNode: focus,
      maxBytes: 10,
      onSend: () {},
      actions: IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () {}),
    )));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.fillColor, const Color(0xFF445566));
    expect(field.decoration!.hintStyle!.color, const Color(0xFF556677));
    expect(field.decoration!.enabledBorder!.borderSide.color, const Color(0xFF334455));
    expect(field.decoration!.focusedBorder!.borderSide.color, const Color(0xFF334455));
    expect(field.style!.color, const Color(0xFF667788));
    final boxes = tester.widgetList<Container>(find.byType(Container));
    expect(boxes.any((box) => box.decoration is BoxDecoration &&
        (box.decoration! as BoxDecoration).color == const Color(0xFF112233)), isTrue);
    final send = find.byType(ChatComposerSendButton);
    expect(tester.widget<Material>(find.descendant(
      of: send, matching: find.byType(Material),
    )).color, const Color(0xFF778899));
    expect(tester.widget<Icon>(find.descendant(
      of: send, matching: find.byType(Icon),
    )).color, const Color(0xFF8899AA));
    final action = find.byIcon(Icons.add_circle_outline);
    expect(IconTheme.of(tester.element(action)).color, const Color(0xFF223344));
    expect(tester.widget<Text>(find.text('5 / 10')).style!.color, const Color(0xFF99AABB));
    controller.text = '12345678';
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<Text>(find.text('8 / 10')).style!.color, const Color(0xFFAABBCC));
    controller.text = '12345678901';
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<Text>(find.text('11 / 10')).style!.color, const Color(0xFFBBCCDD));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('a byte-counted field outside a composer keeps the ordinary theme', (tester) async {
    final controller = TextEditingController(text: '12345');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(ByteCountedTextField(
      controller: controller,
      maxBytes: 10,
    )));
    await tester.pump();
    final context = tester.element(find.byType(ByteCountedTextField));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.style, isNull);
    expect(field.decoration!.hintStyle, isNull);
    expect(tester.widget<Text>(find.text('5 / 10')).style!.color,
        Theme.of(context).colorScheme.onSurfaceVariant);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

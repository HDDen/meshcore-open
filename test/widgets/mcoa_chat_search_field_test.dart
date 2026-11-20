import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoa_theme_options.dart';
import 'package:meshcore_open/theme/mcoa_theme_style.dart';
import 'package:meshcore_open/widgets/mcoa_chat_search_field.dart';

void main() {
  testWidgets('search colors preserve border shapes, editing and default appearance', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    var changed = '';
    final base = ThemeData.dark().copyWith(inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: Colors.grey,
      hintStyle: const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.grey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blue, width: 2),
      ),
    ));
    Widget app(McoaThemeOptions options, {bool contacts = false}) => MaterialApp(
      themeAnimationStyle: AnimationStyle.noAnimation,
      theme: McoaThemeStyle.apply(base, options),
      home: Scaffold(body: McoaChatSearchField(
        controller: controller, focusNode: focus, contacts: contacts,
        onChanged: (value) { changed = value; },
        decoration: const InputDecoration(
          hintText: 'Search', prefixIcon: Icon(Icons.search), suffixIcon: Icon(Icons.filter_list_outlined),
        ),
      )),
    );
    await tester.pumpWidget(app(const McoaThemeOptions()));
    final target = find.byType(TextField);
    var field = tester.widget<TextField>(target);
    expect(field.style, isNull);
    expect(field.decoration!.fillColor, base.inputDecorationTheme.fillColor);
    expect(field.decoration!.enabledBorder, base.inputDecorationTheme.enabledBorder);
    expect(field.decoration!.focusedBorder, base.inputDecorationTheme.focusedBorder);
    expect(field.decoration!.hintStyle, base.inputDecorationTheme.hintStyle);
    await tester.pumpWidget(app(const McoaThemeOptions(colors: {
      'chats_search_border': Colors.red,
      'chats_search_background': Colors.black,
      'chats_search_text': Colors.green,
      'chats_search_hint_icons': Colors.orange,
    })));
    await tester.pumpAndSettle();
    field = tester.widget<TextField>(target);
    expect(field.decoration!.fillColor, Colors.black);
    expect(field.style!.color, Colors.green);
    expect(field.decoration!.hintStyle!.color, Colors.orange);
    expect(field.decoration!.prefixIconColor, Colors.orange);
    expect(field.decoration!.suffixIconColor, Colors.orange);
    for (final border in [field.decoration!.enabledBorder!, field.decoration!.focusedBorder!]) {
      expect(border.borderSide.color, Colors.red);
      expect((border as OutlineInputBorder).borderRadius, BorderRadius.circular(12));
    }
    expect(field.decoration!.focusedBorder!.borderSide.width, 2);
    await tester.enterText(target, 'Echo');
    expect(controller.text, 'Echo');
    expect(changed, 'Echo');
    const separateBackgrounds = McoaThemeOptions(colors: {
      'chats_search_background': Colors.black,
      'chats_search_contacts_background': Colors.pink,
    });
    await tester.pumpWidget(app(separateBackgrounds, contacts: true));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(target).decoration!.fillColor, Colors.pink);
    await tester.pumpWidget(app(separateBackgrounds));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(target).decoration!.fillColor, Colors.black);
    await tester.pumpWidget(app(const McoaThemeOptions(colors: {
      'chats_search_contacts_background': Colors.pink,
    })));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(target).decoration!.fillColor, Colors.grey);
    await tester.pumpWidget(app(const McoaThemeOptions(colors: {
      'chats_search_background': Colors.black,
    }), contacts: true));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(target).decoration!.fillColor, Colors.black);
    expect(controller.text, 'Echo');
    await tester.pumpWidget(app(const McoaThemeOptions()));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(target).style, isNull);
    expect(controller.text, 'Echo');
    expect(tester.widget<TextField>(target).decoration!.fillColor, Colors.grey);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

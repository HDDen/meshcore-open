import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/widgets/byte_count_input.dart';

// What the composer field promises about its counter, pinned before the
// counter's timing changes: once the field has settled, the number is the
// UTF-8 length of the encoder's output for the text, the `(-N)` form and the
// soft-limit note follow it, the limiter cuts what does not fit, a selection
// change alone never runs the encoder, and a rebuild that hands the field a
// fresh encoder closure for the same text, which the screens do on every
// build, leaves the count right.

class _CountingEncoder {
  int calls = 0;

  /// Every Cyrillic letter becomes one ASCII letter, so the encoded length
  /// differs from the typed one and the counter can be seen to use it.
  String call(String text) {
    calls++;
    return text.replaceAll(RegExp('[а-яА-Я]'), 'x');
  }
}

Future<void> pumpField(WidgetTester tester, Widget field) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: field)));

/// Lets any deferred counting run: the field may wait a moment after a
/// change before it encodes.
Future<void> settle(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 1));

void main() {
  testWidgets('the counter shows the encoded length of the text once the '
      'field has settled', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final encoder = _CountingEncoder();
    await pumpField(
      tester,
      ByteCountedTextField(
        maxBytes: 20,
        controller: controller,
        encoder: encoder.call,
        hideCounterWhenEmpty: false,
      ),
    );
    await settle(tester);
    expect(find.text('0 / 20'), findsOneWidget);

    // Six Cyrillic letters: twelve bytes typed, six once encoded.
    await tester.enterText(find.byType(TextField), 'привет');
    await settle(tester);

    expect(controller.text, 'привет');
    expect(find.text('6 / 20'), findsOneWidget);
    expect(encoder.calls, greaterThan(0));
  });

  testWidgets('the limiter keeps what fits of a paste', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpField(
      tester,
      ByteCountedTextField(maxBytes: 5, controller: controller),
    );

    await tester.enterText(find.byType(TextField), 'abcdefgh');
    await settle(tester);

    expect(controller.text, 'abcde');
    expect(find.text('5 / 5'), findsOneWidget);
  });

  testWidgets('the (-N) form and the soft-limit note follow the count', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'abcdefgh');
    addTearDown(controller.dispose);
    await pumpField(
      tester,
      ByteCountedTextField(
        maxBytes: 20,
        controller: controller,
        excessBytes: (text) => text.length > 6 ? text.length - 6 : null,
        softLimitBytes: 4,
        softLimitNote: 'long',
      ),
    );
    await settle(tester);

    expect(find.text('8 (-2) / 20'), findsOneWidget);
    expect(find.text('long'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'abc');
    await settle(tester);

    expect(find.text('3 / 20'), findsOneWidget);
    expect(find.text('long'), findsNothing);
  });

  testWidgets('a selection change alone does not run the encoder', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'привет');
    addTearDown(controller.dispose);
    final encoder = _CountingEncoder();
    await pumpField(
      tester,
      ByteCountedTextField(
        maxBytes: 20,
        controller: controller,
        encoder: encoder.call,
      ),
    );
    await settle(tester);
    final callsAfterBuild = encoder.calls;
    expect(callsAfterBuild, greaterThan(0));

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await settle(tester);
    controller.selection = const TextSelection.collapsed(offset: 6);
    await settle(tester);

    expect(encoder.calls, callsAfterBuild);
    expect(find.text('6 / 20'), findsOneWidget);
  });

  testWidgets('a burst of rebuilds with fresh closures costs one encoding, '
      'after the wait', (tester) async {
    final controller = TextEditingController(text: 'привет');
    addTearDown(controller.dispose);
    final encoder = _CountingEncoder();
    Widget field() => ByteCountedTextField(
      maxBytes: 20,
      controller: controller,
      encoder: (text) => encoder.call(text),
    );
    await pumpField(tester, field());
    await settle(tester);
    final before = encoder.calls;

    for (var i = 0; i < 5; i++) {
      await pumpField(tester, field());
    }
    expect(encoder.calls, before);
    expect(find.text('6 / 20'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 150));
    expect(encoder.calls, before);
    await tester.pump(const Duration(milliseconds: 150));
    expect(encoder.calls, before + 1);
    expect(find.text('6 / 20'), findsOneWidget);
  });

  testWidgets('changes within the wait cost the counter one encoding, and '
      'the number follows the last one', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final encoder = _CountingEncoder();
    await pumpField(
      tester,
      ByteCountedTextField(
        maxBytes: 20,
        controller: controller,
        encoder: encoder.call,
        hideCounterWhenEmpty: false,
      ),
    );
    await settle(tester);
    final before = encoder.calls;

    // Set through the controller, which bypasses the limiter, so only the
    // counter's own encodings are counted.
    for (final draft in ['п', 'пр', 'при', 'прив']) {
      controller.text = draft;
      await tester.pump();
    }
    expect(encoder.calls, before);
    expect(find.text('0 / 20'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    expect(encoder.calls, before + 1);
    expect(find.text('4 / 20'), findsOneWidget);
  });

  testWidgets('a field can name its own wait', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final encoder = _CountingEncoder();
    await pumpField(
      tester,
      ByteCountedTextField(
        maxBytes: 20,
        controller: controller,
        encoder: encoder.call,
        countDelay: const Duration(milliseconds: 20),
      ),
    );
    await settle(tester);
    final before = encoder.calls;

    controller.text = 'привет';
    await tester.pump(const Duration(milliseconds: 30));

    expect(encoder.calls, before + 1);
    expect(find.text('6 / 20'), findsOneWidget);
  });

  testWidgets('a rebuild with a fresh encoder closure and the same text '
      'keeps the count right', (tester) async {
    final controller = TextEditingController(text: 'привет');
    addTearDown(controller.dispose);
    final encoder = _CountingEncoder();
    // The screens create the closure in build, so every rebuild hands the
    // field a new function object.
    Widget field() => ByteCountedTextField(
      maxBytes: 20,
      controller: controller,
      encoder: (text) => encoder.call(text),
    );

    await pumpField(tester, field());
    await settle(tester);
    expect(find.text('6 / 20'), findsOneWidget);

    for (var i = 0; i < 5; i++) {
      await pumpField(tester, field());
    }
    await settle(tester);

    expect(find.text('6 / 20'), findsOneWidget);
    expect(controller.text, 'привет');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/widgets/empty_state.dart';

// U11b baseline on unchanged EmptyState. Preserve visible text, the optional
// action and its explicit invocation before adding short-screen scrolling.
// Pure widgets: no radio, database, platform plugins or HTTP.
const _layouts = [
  (name: 'phone', size: Size(320, 568), textScale: 1.0),
  (name: 'desktop', size: Size(1280, 800), textScale: 2.0),
];

void main() {
  for (final language in ['en', 'ru']) {
    for (final layout in _layouts) {
      testWidgets('U11b baseline: empty-state content and action ($language, ${layout.name})', (tester) async {
        tester.view.physicalSize = layout.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final title = language == 'ru' ? 'Ничего не найдено' : 'No items yet';
        final subtitle = language == 'ru'
            ? 'После синхронизации здесь появятся новые записи.'
            : 'New items appear here after synchronization.';
        final action = language == 'ru' ? 'Добавить запись' : 'Add item';
        var taps = 0;
        try {
          await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(layout.textScale),
              ),
              child: child!,
            ),
            home: Scaffold(body: EmptyState(
              icon: Icons.forum_outlined,
              title: title,
              subtitle: subtitle,
              action: FilledButton(onPressed: () => taps++, child: Text(action)),
            )),
          ));
          // The entrance animation is finite. No pumpAndSettle around any
          // asynchronous service is needed to exercise the shared widget.
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
          for (final text in [title, subtitle, action]) {
            expect(find.text(text), findsOneWidget);
            final rect = tester.getRect(find.text(text));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(layout.size.width));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.bottom, lessThanOrEqualTo(layout.size.height));
          }
          expect(taps, 0);
          await tester.tap(find.text(action));
          await tester.pump();
          expect(taps, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      });
    }
  }

  for (final language in ['en', 'ru']) {
    for (final keyboard in [false, true]) {
      testWidgets('U11b1: empty-state action remains reachable with large text ($language, keyboard=$keyboard)', (tester) async {
        tester.view.physicalSize = keyboard ? const Size(320, 568) : const Size(568, 220);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final title = language == 'ru' ? 'Ничего не найдено' : 'No items yet';
        final action = language == 'ru' ? 'Добавить запись' : 'Add item';
        var taps = 0;
        try {
          await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: EdgeInsets.only(bottom: keyboard ? 360 : 0),
              ),
              child: child!,
            ),
            home: Scaffold(body: EmptyState(
              icon: Icons.forum_outlined,
              title: title,
              subtitle: language == 'ru'
                  ? 'После синхронизации здесь появятся новые записи. Чтобы начать работу, добавьте первый элемент.'
                  : 'New items appear here after synchronization. Add the first item to start using this screen.',
              action: FilledButton(onPressed: () => taps++, child: Text(action)),
            )),
          ));
          await tester.pump(const Duration(milliseconds: 500));
          final viewport = find.descendant(
            of: find.byType(EmptyState), matching: find.byType(SingleChildScrollView),
          );
          final scrollable = find.descendant(
            of: viewport, matching: find.byType(Scrollable),
          );
          expect(tester.state<ScrollableState>(scrollable).position.maxScrollExtent, greaterThan(0));
          expect(find.text(title), findsOneWidget);
          expect(taps, 0);
          await tester.ensureVisible(find.text(action));
          await tester.pumpAndSettle();
          final visible = tester.getRect(viewport);
          final button = tester.getRect(find.byType(FilledButton));
          expect(button.top, greaterThanOrEqualTo(visible.top - 0.1));
          expect(button.bottom, lessThanOrEqualTo(visible.bottom + 0.1));
          await tester.tap(find.text(action));
          await tester.pump();
          expect(taps, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      });
    }
  }

  testWidgets('U11b1: unbounded parent keeps its own primary scroll controller', (tester) async {
    tester.view.physicalSize = const Size(320, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final outer = ScrollController();
    var taps = 0;
    try {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PrimaryScrollController(
          controller: outer,
          child: SingleChildScrollView(
            primary: true,
            child: EmptyState(
              icon: Icons.usb,
              title: 'Synthetic nested placeholder',
              subtitle: 'The placeholder must not require a bounded parent height.',
              action: FilledButton(onPressed: () => taps++, child: const Text('Add item')),
            ),
          ),
        )),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      expect(outer.positions, hasLength(1));
      expect(outer.position.maxScrollExtent, greaterThan(0));
      await tester.ensureVisible(find.text('Add item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add item'));
      await tester.pump();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      outer.dispose();
    }
  });

  testWidgets('U11b baseline: title-only state has no invented subtitle or action', (tester) async {
    try {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: EmptyState(icon: Icons.usb, title: 'Synthetic title')),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Synthetic title'), findsOneWidget);
      expect(find.byIcon(Icons.usb), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(Text), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

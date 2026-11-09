import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/services/message_filter/message_filter_service.dart';
import 'package:meshcore_open/storage/message_filter_store.dart';
import 'package:meshcore_open/widgets/filtered_channel_message.dart';

const _manual = FilterVerdict(reason: FilterReason.manual);
const _action = ValueKey('spam-action');
const _prompt =
    'Для полноценного функционирования функционала необходимо включить '
    'функцию обучения спам-фильтра. Включить это сейчас?';

class _Store extends MessageFilterStore {
  MessageFilterSettings settings = const MessageFilterSettings(enabled: true);
  Completer<void>? holdSave;
  int saves = 0;

  @override
  MessageFilterSettings loadSettings() => settings;

  @override
  List<FilterRule> loadRules() => const [];

  @override
  Future<({int spam, int notSpam})> loadTrainingLabelCounts() async =>
      (spam: 0, notSpam: 0);

  @override
  Future<void> saveSettings(MessageFilterSettings next) async {
    saves++;
    await holdSave?.future;
    settings = next;
  }
}

class _Connector extends MeshCoreConnector {
  _Connector({required super.messageFilterService});

  final marks = <({bool learningEnabled, FilterVerdict? verdict})>[];

  @override
  Future<bool> setChannelMessageFilterVerdict(
    Channel channel,
    ChannelMessage message,
    FilterVerdict? verdict,
  ) async {
    marks.add((
      learningEnabled: messageFilterService!.learningEnabled,
      verdict: verdict,
    ));
    return true;
  }
}

Future<AppLocalizations> _open(
  WidgetTester tester,
  _Connector connector, {
  required FilterVerdict? verdict,
}) async {
  final channel = Channel.fromHex(0, 'Test', Channel.publicChannelPsk);
  final now = DateTime.utc(2026);
  final message = ChannelMessage(
    channelIndex: channel.index,
    senderName: 'Alice',
    text: 'Example post',
    timestamp: now,
    receivedAt: now,
    isOutgoing: false,
    filterVerdict: verdict == null ? _manual : null,
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: verdict == null
            ? FilteredChannelMessage(
                key: _action,
                connector: connector,
                channel: channel,
                message: message,
              )
            : Builder(
                builder: (context) => TextButton(
                  key: _action,
                  onPressed: () => saveChannelMessageVerdict(
                    context,
                    connector,
                    channel,
                    message,
                    verdict,
                  ),
                  child: const Text('Test'),
                ),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final l10n = AppLocalizations.of(tester.element(find.byKey(_action)));
  if (verdict == null) {
    await tester.tap(find.text(l10n.messageFilter_ghostSingle));
    await tester.pumpAndSettle();
  }
  return l10n;
}

void main() {
  for (final (name, verdict) in [('spam', _manual), ('restore', null)]) {
    testWidgets('cancel does not apply the $name action', (
      tester,
    ) async {
      final store = _Store();
      final service = MessageFilterService(store: store)..load();
      final connector = _Connector(messageFilterService: service);
      addTearDown(service.dispose);
      addTearDown(connector.dispose);
      final l10n = await _open(tester, connector, verdict: verdict);
      final action = verdict == null
          ? find.text(l10n.messageFilter_notSpam)
          : find.byKey(_action);

      await tester.tap(action);
      await tester.pumpAndSettle();
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.title, isNull);
      expect((dialog.content! as Text).data, _prompt);
      expect(connector.marks, isEmpty);

      await tester.tap(find.text(l10n.common_cancel));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(connector.marks, isEmpty);
      expect(store.saves, 0);
      expect(service.learningEnabled, isFalse);
      if (verdict == null) {
        final tile = tester.widget<FilteredChannelMessage>(find.byKey(_action));
        expect(tile.message.filterVerdict, _manual);
        expect(find.text(l10n.messageFilter_reasonManual), findsOneWidget);
        final body = tester.widget<SelectableText>(find.byType(SelectableText));
        expect(body.data, 'Alice: Example post');
      }
    });

    testWidgets('OK saves learning before applying the $name action', (tester) async {
      final store = _Store()..holdSave = Completer<void>();
      final service = MessageFilterService(store: store)..load();
      final connector = _Connector(messageFilterService: service);
      addTearDown(service.dispose);
      addTearDown(connector.dispose);
      final l10n = await _open(tester, connector, verdict: verdict);
      final action = verdict == null
          ? find.text(l10n.messageFilter_notSpam)
          : find.byKey(_action);

      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.common_ok));
      await tester.pumpAndSettle();
      expect(store.saves, 1);
      expect(store.settings.learning, isFalse);
      expect(connector.marks, isEmpty);

      store.holdSave!.complete();
      await tester.pumpAndSettle();
      expect(store.settings.learning, isTrue);
      expect(connector.marks, [(learningEnabled: true, verdict: verdict)]);

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(connector.marks, hasLength(2));
      expect(store.saves, 1);
    });
  }
}

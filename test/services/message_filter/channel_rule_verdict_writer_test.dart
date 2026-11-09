import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/services/message_filter/channel_rule_verdict_writer.dart';

const _first = FilterVerdict(reason: FilterReason.textRule, detail: 'first');
const _last = FilterVerdict(reason: FilterReason.textRule, detail: 'last');

void main() {
  testWidgets('quick edits write only the latest snapshot after one second', (
    tester,
  ) async {
    final written = <ChannelRuleVerdictUpdates>[];
    var verdict = _first;
    final writer = ChannelRuleVerdictWriter(
      () => {'channel': {'post': verdict}},
      (updates) async => written.add(updates),
    );

    writer.schedule();
    await tester.pump(const Duration(milliseconds: 600));
    verdict = _last;
    writer.schedule();
    await tester.pump(const Duration(milliseconds: 999));
    expect(written, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(written, [
      {'channel': {'post': _last}},
    ]);
  });

  testWidgets('a flush during a write queues the newer batch', (tester) async {
    final firstWrite = Completer<void>();
    final written = <ChannelRuleVerdictUpdates>[];
    FilterVerdict? verdict = _first;
    final writer = ChannelRuleVerdictWriter(
      () => {'channel': {'post': verdict}},
      (updates) async {
        written.add(updates);
        if (written.length == 1) await firstWrite.future;
      },
    );

    writer.schedule();
    await tester.pump(const Duration(seconds: 1));
    expect(written, [
      {'channel': {'post': _first}},
    ]);

    verdict = null;
    writer.schedule();
    final flushed = writer.flush();
    await tester.pump();
    expect(written, hasLength(1));

    firstWrite.complete();
    await flushed;
    expect(written, [
      {'channel': {'post': _first}},
      {'channel': {'post': null}},
    ]);
  });
}

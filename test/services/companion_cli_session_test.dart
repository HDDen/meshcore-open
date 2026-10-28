import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/companion_cli_entry.dart';
import 'package:meshcore_open/services/companion_cli_session.dart';
import 'package:meshcore_open/storage/companion_cli_store.dart';

class _History implements CompanionCliHistory {
  final rows = <String, CompanionCliEntry>{};
  bool fail = false;
  Completer<void>? gate;
  final revisions = <String, int>{};
  @override
  int revision(String nodeKey) => revisions[nodeKey] ?? 0;
  @override
  Future<void> clear(String nodeKey) async {
    rows.removeWhere((_, entry) => entry.nodeKey == nodeKey);
    revisions[nodeKey] = revision(nodeKey) + 1;
  }
  @override
  Future<List<CompanionCliEntry>> load() async => rows.values.toList();
  @override
  Future<bool> save(CompanionCliEntry entry, {int? revision}) async {
    final pending = gate;
    gate = null;
    if (pending != null) {
      await pending.future;
    }
    if (fail) {
      throw StateError('Synthetic storage failure');
    }
    if (revision != null && this.revision(entry.nodeKey) != revision) {
      return false;
    }
    rows['${entry.nodeKey}:${entry.id}'] = entry;
    return true;
  }
}

Uint8List _answer(Uint8List sent, String text) =>
  Uint8List.fromList([29, ...sent.sublist(1, 4), ...utf8.encode(text)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _History history;
  late CompanionCliSession session;
  late List<Uint8List> sent;
  var connected = true;
  var node = '01' * 32;
  Future<void> Function(Uint8List)? writer;
  var timedOut = 0;

  setUp(() {
    history = _History();
    sent = [];
    node = '01' * 32;
    connected = true;
    writer = null;
    timedOut = 0;
    session = CompanionCliSession(history: history,
      nodeKey: () => node, nodeName: () => 'Synthetic node', available: () => connected,
      timeout: const Duration(seconds: 1), onTimeout: (_) { timedOut++; },
      send: (frame) async { sent.add(frame); await writer?.call(frame); });
  });
  tearDown(() { session.dispose(); });

  test('reply before writer completion is retained and sensitive console text is persisted', () async {
    writer = (frame) async { session.observeReply(_answer(frame, 'SYNTHETIC_VALUE')); };
    await session.sendCommand('set wifi.pwd SYNTHETIC_ONLY');
    final row = history.rows.values.single;
    expect(row.command, 'set wifi.pwd SYNTHETIC_ONLY');
    expect(row.response, 'SYNTHETIC_VALUE');
    expect(row.status, CompanionCliStatus.replied);
    expect(row.nodeKey, node);
    expect(session.busy, isFalse);
    expect(sent.length, 1);
  });

  testWidgets('a late response never completes the next operation and no command is retried', (tester) async {
    final first = session.sendCommand('ver');
    await tester.pump();
    final old = sent.single;
    await tester.pump(const Duration(seconds: 2));
    await first;
    expect(timedOut, 1);
    expect(sent.length, 1);
    expect(history.rows.values.single.failure, 'timeout');
    var finished = false;
    final second = session.sendCommand('board').then((_) { finished = true; });
    await tester.pump();
    session.observeReply(_answer(old, 'old secret must not cross operations'));
    await tester.pump();
    expect(finished, isFalse);
    session.observeReply(_answer(sent.last, 'new reply'));
    await tester.pump();
    await second;
    expect(session.entries(shared: false).last.response, 'new reply');
    expect(sent.length, 2);
  });

  testWidgets('changing a node interrupts its pending command and shared view keeps provenance', (tester) async {
    final firstNode = node;
    final pending = session.sendCommand('ver');
    await tester.pump();
    node = '02' * 32;
    session.connectionChanged();
    await tester.pump();
    await pending;
    expect(session.entries(shared: false), isEmpty);
    expect(session.entries(shared: true).single.nodeKey, firstNode);
    expect(session.entries(shared: true).single.status, CompanionCliStatus.disconnected);
    writer = (frame) async { session.observeReply(_answer(frame, 'second node')); };
    await session.sendCommand('board');
    expect(session.entries(shared: false).single.nodeKey, node);
    expect(session.entries(shared: true).length, 2);
  });

  testWidgets('durable first-write failure or a node switch before it completes prevents transmission', (tester) async {
    history.fail = true;
    await expectLater(session.sendCommand('ver'), throwsStateError);
    expect(sent, isEmpty);
    history.fail = false;
    final gate = Completer<void>();
    history.gate = gate;
    final pending = session.sendCommand('ver');
    await tester.pump();
    node = '02' * 32;
    session.connectionChanged();
    gate.complete();
    await tester.pump();
    await pending;
    expect(sent, isEmpty);
    expect(history.rows.values.single.status, CompanionCliStatus.disconnected);
  });

  test('loaded pending commands are displayed as interrupted and never resumed', () async {
    final entry = CompanionCliEntry(id: 'old', nodeKey: node, nodeName: 'Synthetic node',
      command: 'reboot', createdAt: DateTime.utc(2026));
    history.rows['old'] = entry;
    await session.ensureLoaded();
    expect(session.entries(shared: true).single.status, CompanionCliStatus.disconnected);
    expect(sent, isEmpty);
  });

  testWidgets('local clear does not cancel or resend a command and its later reply stays deleted', (tester) async {
    final pending = session.sendCommand('ver');
    await tester.pump();
    final request = sent.single;
    await session.clearHistory(node);
    expect(session.entries(shared: true), isEmpty);
    expect(session.busy, isTrue);
    session.observeReply(_answer(request, 'late result after local clear'));
    await tester.pump();
    await pending;
    expect(history.rows, isEmpty);
    expect(session.entries(shared: true), isEmpty);
    expect(sent, hasLength(1));
    expect(timedOut, 0);
  });
}

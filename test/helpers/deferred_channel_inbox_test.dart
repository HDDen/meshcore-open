import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/deferred_channel_inbox.dart';
import 'package:meshcore_open/models/pending_channel_frame.dart';

class _Repository implements PendingChannelFrameRepository {
  final rows = <String, PendingChannelFrame>{};
  Completer<void>? holdPut;
  bool failPut = false;
  bool failRemove = false;
  int reads = 0;

  @override
  Future<void> putPendingChannelFrame(PendingChannelFrame frame) async {
    if (holdPut case final held?) {
      await held.future;
    }
    if (failPut) {
      throw StateError('disk full');
    }
    rows[frame.id] = frame;
  }

  @override
  Future<List<PendingChannelFrame>> readPendingChannelFrames(String nodeKey) async {
    reads++;
    return rows.values.where((row) => row.nodeKey == nodeKey).toList();
  }

  @override
  Future<void> removePendingChannelFrame(String nodeKey, String id) async {
    if (failRemove) {
      throw StateError('ack failed');
    }
    if (rows[id]?.nodeKey == nodeKey) {
      rows.remove(id);
    }
  }
}

void main() {
  final node = List.filled(64, 'a').join();
  final otherNode = List.filled(64, 'b').join();
  final at = DateTime.utc(2026, 10, 30, 12);
  const binding = (name: 'Test', key: 'original-key');
  late _Repository repository;
  late DeferredChannelInbox inbox;

  Future<void> stage({String? nodeKey}) => inbox.defer(
    nodeKey: nodeKey ?? node,
    channelIndex: 2,
    frame: Uint8List.fromList([8, 2, 0, 0, 1, 0, 0, 0, 65]),
    receivedAt: at,
  );

  setUp(() {
    repository = _Repository();
    inbox = DeferredChannelInbox(repository);
  });

  test('defer finishes only after the durable writer finishes', () async {
    repository.holdPut = Completer<void>();
    var completed = false;
    final deferred = stage().then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(repository.rows, isEmpty);
    repository.holdPut!.complete();
    await deferred;
    expect(repository.rows, hasLength(1));
    expect(repository.rows.values.single.receivedAt, at);
  });

  test('disk failure is propagated instead of reporting a successful receive', () async {
    repository.failPut = true;
    await expectLater(stage(), throwsStateError);
    expect(repository.rows, isEmpty);
  });

  test('a new coordinator restores rows and leaves unresolved channels alone', () async {
    await stage();
    inbox = DeferredChannelInbox(repository);
    var processed = 0;
    await inbox.replay(
      nodeKey: node, isCurrent: () => true, bindingFor: (_) => null,
      process: (_, _) async { processed++; },
    );
    expect(processed, 0);
    expect(repository.rows, hasLength(1));
    await inbox.replay(
      nodeKey: node, isCurrent: () => true, bindingFor: (_) => binding,
      process: (frame, canApply) async {
        expect(canApply(), isTrue);
        expect(repository.rows.containsKey(frame.id), isTrue);
        expect(frame.receivedAt, at);
        expect(frame.channelName, binding.name);
        processed++;
      },
    );
    expect(processed, 1);
    expect(repository.rows, isEmpty);
  });

  test('a failed history write retains a pinned row and does not poison retries', () async {
    await stage();
    await expectLater(inbox.replay(
      nodeKey: node, isCurrent: () => true, bindingFor: (_) => binding,
      process: (_, _) async { throw StateError('history write failed'); },
    ), throwsStateError);
    expect(repository.rows.values.single.channelKey, binding.key);
    await inbox.replay(
      nodeKey: node, isCurrent: () => true, bindingFor: (_) => binding,
      process: (_, _) async {},
    );
    expect(repository.rows, isEmpty);
  });

  test('a reused slot cannot take a frame already pinned to another channel', () async {
    await stage();
    await expectLater(inbox.replay(
      nodeKey: node, isCurrent: () => true, bindingFor: (_) => binding,
      process: (_, _) async { throw StateError('interrupted'); },
    ), throwsStateError);
    var processed = 0;
    for (final replacement in [
      (name: 'Other', key: 'original-key'),
      (name: 'Test', key: 'new-key'),
    ]) {
      await inbox.replay(
        nodeKey: node, isCurrent: () => true, bindingFor: (_) => replacement,
        process: (_, _) async { processed++; },
      );
    }
    expect(processed, 0);
    expect(repository.rows, hasLength(1));
  });

  test('node scopes are independent', () async {
    await stage();
    await stage(nodeKey: otherNode);
    await inbox.replay(
      nodeKey: node, isCurrent: () => true, bindingFor: (_) => binding,
      process: (frame, _) async { expect(frame.nodeKey, node); },
    );
    expect(repository.rows.values.single.nodeKey, otherNode);
  });

  test('a node switch during processing keeps the row for its original node', () async {
    await stage();
    var current = true;
    await inbox.replay(
      nodeKey: node, isCurrent: () => current, bindingFor: (_) => binding,
      process: (_, canApply) async {
        current = false;
        expect(canApply(), isFalse);
      },
    );
    expect(repository.rows.values.single.nodeKey, node);
  });

  test('overlapping replay triggers process a retained frame only once', () async {
    await stage();
    final hold = Completer<void>();
    var processed = 0;
    Future<void> replay() => inbox.replay(
      nodeKey: node, isCurrent: () => true, bindingFor: (_) => binding,
      process: (_, _) async { processed++; await hold.future; },
    );
    final first = replay();
    final second = replay();
    await Future<void>.delayed(Duration.zero);
    expect(processed, 1);
    hold.complete();
    await Future.wait([first, second]);
    expect(processed, 1);
    expect(repository.rows, isEmpty);
  });

  test('failure to acknowledge a committed history write retains recovery data', () async {
    await stage();
    repository.failRemove = true;
    await expectLater(inbox.replay(
      nodeKey: node, isCurrent: () => true, bindingFor: (_) => binding,
      process: (_, _) async {},
    ), throwsStateError);
    expect(repository.rows, hasLength(1));
  });

  test('empty inbox is queried once and a newly deferred frame invalidates it', () async {
    Future<void> replay() => inbox.replay(
      nodeKey: node, isCurrent: () => true, bindingFor: (_) => binding,
      process: (_, _) async {},
    );
    await replay();
    await replay();
    expect(repository.reads, 1);
    await stage();
    await replay();
    expect(repository.reads, 2);
    expect(repository.rows, isEmpty);
  });

  test('unknown node identity never creates an unscoped row', () async {
    await expectLater(stage(nodeKey: ''), throwsStateError);
    expect(repository.rows, isEmpty);
  });
}

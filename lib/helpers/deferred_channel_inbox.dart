import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/pending_channel_frame.dart';

abstract interface class PendingChannelFrameRepository {
  Future<void> putPendingChannelFrame(PendingChannelFrame frame);
  Future<List<PendingChannelFrame>> readPendingChannelFrames(String nodeKey);
  Future<void> removePendingChannelFrame(String nodeKey, String id);
}

typedef DeferredChannelBinding = ({String name, String? key});

/// Unknown channels go to disk before the caller may advance the radio queue.
/// Normal bound traffic does not incur an extra inbox write. Replay uses the
/// existing message parser and deduplication, never a second wire codec.
class DeferredChannelInbox {
  DeferredChannelInbox(this.repository);

  final PendingChannelFrameRepository repository;
  Future<void> _replayTail = Future<void>.value();
  final Set<String> _emptyNodes = {};
  int _writeRevision = 0;

  bool mayHavePendingFrames(String nodeKey) => !_emptyNodes.contains(nodeKey);

  Future<void> defer({
    required String nodeKey,
    required int channelIndex,
    required Uint8List frame,
    required DateTime receivedAt,
    DeferredChannelBinding? binding,
  }) async {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(nodeKey)) {
      throw StateError('Cannot retain a channel frame without its node identity');
    }
    _writeRevision++;
    await repository.putPendingChannelFrame(PendingChannelFrame(
      id: const Uuid().v4(),
      nodeKey: nodeKey.toLowerCase(),
      channelIndex: channelIndex,
      frame: Uint8List.fromList(frame),
      receivedAt: receivedAt,
      channelName: binding?.name,
      channelKey: binding?.key,
    ));
    _emptyNodes.remove(nodeKey.toLowerCase());
  }

  Future<void> replay({
    required String nodeKey,
    required bool Function() isCurrent,
    required DeferredChannelBinding? Function(int) bindingFor,
    required Future<void> Function(PendingChannelFrame, bool Function()) process,
  }) {
    final operation = _replayTail.then((_) async {
      if (!isCurrent() || !mayHavePendingFrames(nodeKey)) {
        return;
      }
      final writeRevision = _writeRevision;
      final frames = await repository.readPendingChannelFrames(nodeKey);
      var remaining = false;
      for (var frame in frames) {
        if (!isCurrent()) {
          return;
        }
        final binding = bindingFor(frame.channelIndex);
        if (binding == null) {
          remaining = true;
          continue;
        }
        // Once resolved, retain identity across failed processing and restarts.
        // A reused slot must never redirect an already bound pending message.
        if (frame.channelName != null &&
            (frame.channelName != binding.name || frame.channelKey != binding.key)) {
          remaining = true;
          continue;
        }
        if (frame.channelName == null) {
          frame = frame.bind(binding.name, binding.key);
          await repository.putPendingChannelFrame(frame);
        }
        bool stillCurrent() => isCurrent() && bindingFor(frame.channelIndex) == binding;
        if (!stillCurrent()) {
          return;
        }
        await process(frame, stillCurrent);
        if (!stillCurrent()) {
          return;
        }
        // Failed parsing/persistence leaves the original frame on disk.
        await repository.removePendingChannelFrame(nodeKey, frame.id);
      }
      if (!remaining && writeRevision == _writeRevision) {
        _emptyNodes.add(nodeKey);
      }
    });
    // A failed replay must not poison future reconnects. The caller still
    // observes the original error; only the sequencing tail consumes it.
    _replayTail = operation.catchError((Object _, StackTrace _) {});
    return operation;
  }
}

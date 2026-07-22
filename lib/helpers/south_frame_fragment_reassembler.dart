import 'dart:typed_data';

typedef SouthFrameFragmentWarning = void Function(String message);

class SouthFrameFragmentInfo {
  const SouthFrameFragmentInfo({
    required this.fragmentId,
    required this.fragmentIndex,
    required this.fragmentCount,
    required this.originalFrameType,
    required this.originalFrameLength,
    required this.chunkOffset,
    required this.chunkLength,
    required this.isQueued,
  });

  final int fragmentId;
  final int fragmentIndex;
  final int fragmentCount;
  final int originalFrameType;
  final int originalFrameLength;
  final int chunkOffset;
  final int chunkLength;
  final bool isQueued;
}

class SouthFrameFragmentIngestResult {
  const SouthFrameFragmentIngestResult({
    required this.frames,
    this.acceptedFragment,
  });

  final List<Uint8List> frames;
  final SouthFrameFragmentInfo? acceptedFragment;
}

/// Reassembles South Edition's private `0xED / FR01` companion frames.
///
/// This is deliberately separate from the proposed upstream `0x91` codec:
/// the two values identify different wire formats and may coexist later.
class SouthFrameFragmentReassembler {
  SouthFrameFragmentReassembler({
    this.timeout = const Duration(seconds: 30),
    this.maxPendingSets = 4,
    this.onWarning,
  }) : assert(maxPendingSets > 0);

  static const int fragmentFrameType = 0xED;
  static const List<int> versionSignature = <int>[0x46, 0x52, 0x30, 0x31];
  static const int queuedFlag = 0x01;
  static const int knownFlags = queuedFlag;
  static const int headerLength = 15;
  static const int maxFrameLength = 176;
  static const int chunkLength = maxFrameLength - headerLength;
  static const int maxOriginalLength = 259;

  final Duration timeout;
  final int maxPendingSets;
  SouthFrameFragmentWarning? onWarning;
  final Map<int, _SouthFragmentSet> _pending = <int, _SouthFragmentSet>{};

  SouthFrameFragmentIngestResult ingestDetailed(
    Uint8List frame, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    _pruneExpired(timestamp);
    if (frame.isEmpty || frame[0] != fragmentFrameType) {
      return SouthFrameFragmentIngestResult(frames: <Uint8List>[frame]);
    }
    if (frame.length <= headerLength || frame.length > maxFrameLength) {
      return _reject('invalid physical length ${frame.length}');
    }
    for (var i = 0; i < versionSignature.length; i++) {
      if (frame[i + 1] != versionSignature[i]) {
        return _reject('unsupported signature');
      }
    }

    final flags = frame[5];
    final fragmentId = frame[6] | (frame[7] << 8);
    final fragmentIndex = frame[8];
    final fragmentCount = frame[9];
    final originalFrameType = frame[10];
    final originalFrameLength = frame[11] | (frame[12] << 8);
    final chunkOffset = frame[13] | (frame[14] << 8);
    final actualChunkLength = frame.length - headerLength;

    if ((flags & ~knownFlags) != 0) {
      return _reject('unknown flags 0x${flags.toRadixString(16)}', fragmentId);
    }
    if (fragmentId == 0) return _reject('fragment id is zero');
    if (originalFrameLength <= maxFrameLength ||
        originalFrameLength > maxOriginalLength) {
      return _reject(
        'invalid original length $originalFrameLength',
        fragmentId,
      );
    }
    final expectedCount =
        (originalFrameLength + chunkLength - 1) ~/ chunkLength;
    if (fragmentCount != expectedCount || fragmentIndex >= fragmentCount) {
      return _reject(
        'invalid index/count $fragmentIndex/$fragmentCount',
        fragmentId,
      );
    }
    final expectedOffset = fragmentIndex * chunkLength;
    final remaining = originalFrameLength - expectedOffset;
    final expectedChunkLength = remaining > chunkLength
        ? chunkLength
        : remaining;
    if (chunkOffset != expectedOffset ||
        actualChunkLength != expectedChunkLength) {
      return _reject(
        'invalid chunk geometry offset=$chunkOffset len=$actualChunkLength',
        fragmentId,
      );
    }

    final info = SouthFrameFragmentInfo(
      fragmentId: fragmentId,
      fragmentIndex: fragmentIndex,
      fragmentCount: fragmentCount,
      originalFrameType: originalFrameType,
      originalFrameLength: originalFrameLength,
      chunkOffset: chunkOffset,
      chunkLength: actualChunkLength,
      isQueued: (flags & queuedFlag) != 0,
    );
    final chunk = Uint8List.sublistView(frame, headerLength);
    final existing = _pending[fragmentId];
    if (existing != null && !existing.matches(info)) {
      return _reject('metadata mismatch', fragmentId);
    }
    if (existing == null && _pending.length >= maxPendingSets) {
      final oldest = _pending.entries.reduce(
        (a, b) => a.value.updatedAt.isBefore(b.value.updatedAt) ? a : b,
      );
      _pending.remove(oldest.key);
      _warn('Dropping FR01 fragment set ${oldest.key}: pending limit');
    }
    final set = existing ?? _SouthFragmentSet(info: info, updatedAt: timestamp);
    final previous = set.fragments[fragmentIndex];
    if (previous != null) {
      if (_bytesEqual(previous, chunk)) {
        set.updatedAt = timestamp;
        _pending[fragmentId] = set;
        return SouthFrameFragmentIngestResult(
          frames: const <Uint8List>[],
          acceptedFragment: info,
        );
      }
      return _reject('conflicting duplicate', fragmentId);
    }

    set.fragments[fragmentIndex] = Uint8List.fromList(chunk);
    set.updatedAt = timestamp;
    _pending[fragmentId] = set;
    if (set.fragments.length != fragmentCount) {
      return SouthFrameFragmentIngestResult(
        frames: const <Uint8List>[],
        acceptedFragment: info,
      );
    }

    final rebuilt = set.rebuild();
    _pending.remove(fragmentId);
    if (rebuilt == null || rebuilt[0] != originalFrameType) {
      _warn('Dropping FR01 fragment set $fragmentId: rebuilt type mismatch');
      return const SouthFrameFragmentIngestResult(frames: <Uint8List>[]);
    }
    return SouthFrameFragmentIngestResult(
      frames: <Uint8List>[rebuilt],
      acceptedFragment: info,
    );
  }

  void clear() => _pending.clear();

  SouthFrameFragmentIngestResult _reject(String reason, [int? fragmentId]) {
    if (fragmentId != null) _pending.remove(fragmentId);
    _warn(
      'Ignoring FR01 frame${fragmentId == null ? '' : ' $fragmentId'}: $reason',
    );
    return const SouthFrameFragmentIngestResult(frames: <Uint8List>[]);
  }

  void _pruneExpired(DateTime now) {
    final expired = <int>[];
    for (final entry in _pending.entries) {
      if (now.difference(entry.value.updatedAt) > timeout) {
        expired.add(entry.key);
      }
    }
    for (final id in expired) {
      _pending.remove(id);
      _warn('Dropping FR01 fragment set $id: timeout');
    }
  }

  void _warn(String message) => onWarning?.call(message);

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _SouthFragmentSet {
  _SouthFragmentSet({
    required SouthFrameFragmentInfo info,
    required this.updatedAt,
  }) : fragmentCount = info.fragmentCount,
       originalFrameType = info.originalFrameType,
       originalFrameLength = info.originalFrameLength,
       isQueued = info.isQueued;

  final int fragmentCount;
  final int originalFrameType;
  final int originalFrameLength;
  final bool isQueued;
  final Map<int, Uint8List> fragments = <int, Uint8List>{};
  DateTime updatedAt;

  bool matches(SouthFrameFragmentInfo info) {
    return fragmentCount == info.fragmentCount &&
        originalFrameType == info.originalFrameType &&
        originalFrameLength == info.originalFrameLength &&
        isQueued == info.isQueued;
  }

  Uint8List? rebuild() {
    final result = Uint8List(originalFrameLength);
    for (var index = 0; index < fragmentCount; index++) {
      final chunk = fragments[index];
      if (chunk == null) return null;
      final offset = index * SouthFrameFragmentReassembler.chunkLength;
      result.setRange(offset, offset + chunk.length, chunk);
    }
    return result;
  }
}

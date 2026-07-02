import 'dart:typed_data';

typedef FrameFragmentWarning = void Function(String message);

class FrameFragmentInfo {
  const FrameFragmentInfo({
    required this.fragmentId,
    required this.fragmentIndex,
    required this.fragmentCount,
    required this.originalFrameType,
    required this.originalFrameLength,
    required this.chunkOffset,
    required this.chunkLength,
  });

  final int fragmentId;
  final int fragmentIndex;
  final int fragmentCount;
  final int originalFrameType;
  final int originalFrameLength;
  final int chunkOffset;
  final int chunkLength;
}

class FrameFragmentIngestResult {
  const FrameFragmentIngestResult({
    required this.frames,
    this.acceptedFragment,
  });

  final List<Uint8List> frames;
  final FrameFragmentInfo? acceptedFragment;
}

class FrameFragmentReassembler {
  FrameFragmentReassembler({
    this.timeout = const Duration(seconds: 30),
    this.onWarning,
  });

  static const int fragmentFrameType = 0x91;

  final Duration timeout;
  FrameFragmentWarning? onWarning;
  final Map<int, _FragmentSet> _pending = <int, _FragmentSet>{};

  List<Uint8List> ingest(Uint8List frame, {DateTime? now}) {
    return ingestDetailed(frame, now: now).frames;
  }

  FrameFragmentIngestResult ingestDetailed(Uint8List frame, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    _pruneExpired(timestamp);
    if (frame.isEmpty || frame[0] != fragmentFrameType) {
      return FrameFragmentIngestResult(frames: <Uint8List>[frame]);
    }
    final result = _ingestFragment(frame, timestamp);
    final rebuilt = result.rebuiltFrame;
    return FrameFragmentIngestResult(
      frames: rebuilt == null ? const <Uint8List>[] : <Uint8List>[rebuilt],
      acceptedFragment: result.acceptedFragment,
    );
  }

  void clear() {
    _pending.clear();
  }

  _FragmentIngestResult _ingestFragment(Uint8List frame, DateTime now) {
    if (frame.length < 10) {
      _warn('Ignoring short frame fragment: len=${frame.length}');
      return const _FragmentIngestResult();
    }

    final fragmentId = frame[1] | (frame[2] << 8);
    final fragmentIndex = frame[3];
    final fragmentCount = frame[4];
    final originalFrameType = frame[5];
    final originalFrameLength = frame[6] | (frame[7] << 8);
    final chunkOffset = frame[8] | (frame[9] << 8);
    final chunk = Uint8List.sublistView(frame, 10);
    final info = FrameFragmentInfo(
      fragmentId: fragmentId,
      fragmentIndex: fragmentIndex,
      fragmentCount: fragmentCount,
      originalFrameType: originalFrameType,
      originalFrameLength: originalFrameLength,
      chunkOffset: chunkOffset,
      chunkLength: chunk.length,
    );

    if (fragmentCount == 0) {
      _warn('Ignoring frame fragment $fragmentId: fragmentCount=0');
      _pending.remove(fragmentId);
      return const _FragmentIngestResult();
    }
    if (fragmentIndex >= fragmentCount) {
      _warn(
        'Ignoring frame fragment $fragmentId: index=$fragmentIndex count=$fragmentCount',
      );
      _pending.remove(fragmentId);
      return const _FragmentIngestResult();
    }
    if (originalFrameLength == 0) {
      _warn('Ignoring frame fragment $fragmentId: originalFrameLength=0');
      _pending.remove(fragmentId);
      return const _FragmentIngestResult();
    }
    if (chunkOffset + chunk.length > originalFrameLength) {
      _warn(
        'Ignoring frame fragment $fragmentId: chunk out of bounds '
        'offset=$chunkOffset len=${chunk.length} total=$originalFrameLength',
      );
      _pending.remove(fragmentId);
      return const _FragmentIngestResult();
    }

    final existing = _pending[fragmentId];
    final set = existing ??
        _FragmentSet(
          originalFrameType: originalFrameType,
          originalFrameLength: originalFrameLength,
          fragmentCount: fragmentCount,
          updatedAt: now,
        );

    if (!set.matches(
      originalFrameType: originalFrameType,
      originalFrameLength: originalFrameLength,
      fragmentCount: fragmentCount,
    )) {
      _warn('Dropping frame fragment set $fragmentId: metadata mismatch');
      _pending.remove(fragmentId);
      return const _FragmentIngestResult();
    }

    final previous = set.fragments[fragmentIndex];
    if (previous != null) {
      if (previous.offset == chunkOffset && _bytesEqual(previous.bytes, chunk)) {
        set.updatedAt = now;
        _pending[fragmentId] = set;
        return _FragmentIngestResult(acceptedFragment: info);
      }
      _warn('Dropping frame fragment set $fragmentId: duplicate conflict');
      _pending.remove(fragmentId);
      return const _FragmentIngestResult();
    }

    set.fragments[fragmentIndex] = _FragmentChunk(
      offset: chunkOffset,
      bytes: Uint8List.fromList(chunk),
    );
    set.updatedAt = now;
    _pending[fragmentId] = set;

    if (set.fragments.length != set.fragmentCount) {
      return _FragmentIngestResult(acceptedFragment: info);
    }

    final rebuilt = set.rebuild();
    _pending.remove(fragmentId);
    if (rebuilt == null) {
      _warn('Dropping frame fragment set $fragmentId: incomplete coverage');
      return const _FragmentIngestResult();
    }
    if (rebuilt.isEmpty || rebuilt[0] != set.originalFrameType) {
      _warn(
        'Dropping frame fragment set $fragmentId: original type mismatch',
      );
      return const _FragmentIngestResult();
    }
    return _FragmentIngestResult(
      rebuiltFrame: rebuilt,
      acceptedFragment: info,
    );
  }

  void _pruneExpired(DateTime now) {
    if (_pending.isEmpty) return;
    final expired = <int>[];
    for (final entry in _pending.entries) {
      if (now.difference(entry.value.updatedAt) > timeout) {
        expired.add(entry.key);
      }
    }
    for (final id in expired) {
      _pending.remove(id);
      _warn('Dropping frame fragment set $id: timeout');
    }
  }

  void _warn(String message) {
    onWarning?.call(message);
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _FragmentIngestResult {
  const _FragmentIngestResult({
    this.rebuiltFrame,
    this.acceptedFragment,
  });

  final Uint8List? rebuiltFrame;
  final FrameFragmentInfo? acceptedFragment;
}

class _FragmentSet {
  _FragmentSet({
    required this.originalFrameType,
    required this.originalFrameLength,
    required this.fragmentCount,
    required this.updatedAt,
  });

  final int originalFrameType;
  final int originalFrameLength;
  final int fragmentCount;
  final Map<int, _FragmentChunk> fragments = <int, _FragmentChunk>{};
  DateTime updatedAt;

  bool matches({
    required int originalFrameType,
    required int originalFrameLength,
    required int fragmentCount,
  }) {
    return this.originalFrameType == originalFrameType &&
        this.originalFrameLength == originalFrameLength &&
        this.fragmentCount == fragmentCount;
  }

  Uint8List? rebuild() {
    final result = Uint8List(originalFrameLength);
    final covered = List<bool>.filled(originalFrameLength, false);
    for (final chunk in fragments.values) {
      final end = chunk.offset + chunk.bytes.length;
      if (end > originalFrameLength) return null;
      result.setRange(chunk.offset, end, chunk.bytes);
      for (var i = chunk.offset; i < end; i++) {
        if (covered[i]) return null;
        covered[i] = true;
      }
    }
    for (final isCovered in covered) {
      if (!isCovered) return null;
    }
    return result;
  }
}

class _FragmentChunk {
  const _FragmentChunk({required this.offset, required this.bytes});

  final int offset;
  final Uint8List bytes;
}

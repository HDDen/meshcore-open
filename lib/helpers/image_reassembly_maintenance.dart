import 'dart:async';
import 'dart:typed_data';

import '../services/app_settings_service.dart';
import '../services/image_chunk_transport.dart';

/// Управляет только расписанием очистки; сборка и TTL остаются в базовом классе.
class MaintainedImageReassembler extends ImageReassembler {
  MaintainedImageReassembler({
    super.selfPrefix,
    super.ttl,
    super.maxConcurrentStreams,
    super.maxCompletedStreams,
    super.onImage,
    super.onFailed,
    super.clock,
  });

  static const sweepInterval = Duration(seconds: 5);

  Timer? _sweepTimer;
  bool _started = false;
  bool _pauseWhileIdle = false;
  int _mutationDepth = 0;

  void startMaintenance({required bool pauseWhileIdle}) {
    _started = true;
    _pauseWhileIdle = pauseWhileIdle;
    _syncTimer();
  }

  void stopMaintenance() {
    _started = false;
    _sweepTimer?.cancel();
    _sweepTimer = null;
  }

  void _syncTimer() {
    if (_mutationDepth != 0) return;
    final needed = _started &&
        (!_pauseWhileIdle || pendingCount > 0 || completedCount > 0);
    if (!needed) {
      _sweepTimer?.cancel();
      _sweepTimer = null;
    } else {
      // Без новых чанков незавершённое сообщение тоже должно получить timeout.
      _sweepTimer ??= Timer.periodic(sweepInterval, (_) => evictExpired());
    }
  }

  void _endMutation() {
    _mutationDepth--;
    // addChunk вызывает evictExpired; callbacks ошибок тоже могут добавить поток.
    // Сверяем состояние только после всей вложенной операции.
    _syncTimer();
  }

  @override
  ImageChunkOutcome addChunk(
    Uint8List blob, {
    int channelIndex = 0,
    DateTime? now,
  }) {
    _mutationDepth++;
    try {
      return super.addChunk(blob, channelIndex: channelIndex, now: now);
    } finally {
      _endMutation();
    }
  }

  @override
  List<ImageReassemblyFailure> evictExpired({DateTime? now}) {
    _mutationDepth++;
    try {
      return super.evictExpired(now: now);
    } finally {
      _endMutation();
    }
  }

  @override
  void clear({DateTime? now}) {
    _mutationDepth++;
    try {
      super.clear(now: now);
    } finally {
      _endMutation();
    }
  }

  @override
  void clearChannel(int channelIndex, {DateTime? now}) {
    _mutationDepth++;
    try {
      super.clearChannel(channelIndex, now: now);
    } finally {
      _endMutation();
    }
  }
}

/// Жизненный цикл прежнего app-state таймера и применение выбранного профиля.
class ImageReassemblyMaintenance {
  ImageReassemblyMaintenance({
    required this.reassembler,
    required this.settings,
  }) {
    settings.addListener(_sync);
    _sync();
  }

  final MaintainedImageReassembler reassembler;
  final AppSettingsService settings;
  bool _disposed = false;

  void _sync() {
    if (_disposed) return;
    reassembler.startMaintenance(
      pauseWhileIdle:
          settings.settings.powerSaving.effective.pauseIdleImageCleanup,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    settings.removeListener(_sync);
    reassembler.stopMaintenance();
  }
}

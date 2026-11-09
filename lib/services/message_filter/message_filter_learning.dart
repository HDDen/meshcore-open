import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/message_filter.dart';
import '../../storage/message_filter_store.dart';
import '../../utils/app_logger.dart';
import 'message_filter_text.dart';
import 'ngram_spam_classifier.dart';

typedef SpamTrainer = Future<SpamModel?> Function(SpamTrainingJob job);

/// Owns the optional classifier. The training corpus lives in profile SQLite.
class MessageFilterLearning {
  MessageFilterLearning(this._store, {SpamTrainer? trainer})
    : _trainer = trainer ?? _trainInBackground;

  static const _allowedCap = 400;
  static const _cleanBatchSize = 10;
  static const _cleanFlushDelay = Duration(seconds: 5);
  static const _minSpamExamples = 2;
  static const _trainingDelay = Duration(milliseconds: 250);
  static const _exampleTextLimit = 500;

  final MessageFilterStore _store;
  final SpamTrainer _trainer;
  final _classifier = NgramSpamClassifier();
  final _pendingClean = <FilterExample>[];
  final _allowedTexts = <(String, String)>{};
  ({int spam, int notSpam}) _counts = (spam: 0, notSpam: 0);
  Future<void> _writes = Future<void>.value();
  Timer? _timer;
  Timer? _cleanTimer;
  bool _initialized = false;
  bool _cleanFlushQueued = false;
  bool _waitingForClean = false;
  bool _enabled = false;
  bool _training = false;
  bool _trainingNeeded = false;
  int _activation = 0;
  int _revision = 0;

  int get spamCount => _counts.spam;
  int get notSpamCount => _counts.notSpam;
  bool get canScore => _enabled && _classifier.isTrained;

  static Future<SpamModel?> _trainInBackground(SpamTrainingJob job) =>
      compute(NgramSpamClassifier.fitInBackground, job);

  Future<void> setEnabled(bool enabled) async {
    if (enabled == _enabled) return;
    _enabled = enabled;
    _activation++;
    if (enabled) {
      final activation = _activation;
      await _enqueueWrite(() async {
        if (!_enabled || _activation != activation) return;
        await _initialize();
        if (_enabled && _activation == activation) _requestTraining();
      }).catchError(_logStorageError);
    } else {
      _clearModel();
      flushRecentClean();
    }
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    _counts = await _store.loadTrainingLabelCounts();
    _initialized = true;
  }

  void _clearModel() {
    _timer?.cancel();
    _timer = null;
    _trainingNeeded = false;
    _revision++;
    _waitingForClean = false;
    _allowedTexts.clear();
    _classifier.reset();
  }

  void allow(String channelId, String textKey) {
    if (!_enabled || textKey.isEmpty) return;
    _allowedTexts.add((channelId, textKey));
    if (_allowedTexts.length > _allowedCap) {
      _allowedTexts.remove(_allowedTexts.first);
    }
  }

  bool matches(
    String channelId,
    String normalizedSender,
    String normalizedText, {
    String? duplicateKey,
  }) {
    if (!canScore) return false;
    if (_allowedTexts.isNotEmpty &&
        _allowedTexts.contains((
          channelId,
          duplicateKey ?? MessageFilterText.duplicateKey(normalizedText),
        ))) {
      return false;
    }
    return _classifier.probability(normalizedSender, normalizedText) >= 0.80;
  }

  void recordClean(String sender, String text) {
    if (!_enabled) return;
    final trimmed = text.trim();
    final sample = trimmed.length > _exampleTextLimit
        ? trimmed.substring(0, _exampleTextLimit)
        : trimmed;
    final sourceKey = FilterExample.sourceKeyFor(sender, sample);
    if (_pendingClean.lastOrNull?.sourceKey == sourceKey) return;
    final example = _example(sender, sample, spam: false, sourceKey: sourceKey);
    if (example.text.isEmpty) return;
    _pendingClean.add(example);
    _limitPendingClean();
    _scheduleCleanFlush();
    if (_waitingForClean) _requestTraining();
  }

  void _limitPendingClean() {
    while (_pendingClean.length > _cleanBatchSize) {
      _pendingClean.removeAt(0);
    }
  }

  void _scheduleCleanFlush() {
    if (_cleanFlushQueued || _pendingClean.isEmpty) return;
    if (!_enabled || _pendingClean.length >= _cleanBatchSize) {
      flushRecentClean();
    } else {
      _cleanTimer ??= Timer(_cleanFlushDelay, flushRecentClean);
    }
  }

  /// No more than one transaction in flight and one short pending batch.
  void flushRecentClean() {
    _cleanTimer?.cancel();
    _cleanTimer = null;
    if (_cleanFlushQueued || _pendingClean.isEmpty) return;
    _cleanFlushQueued = true;
    unawaited(_enqueueWrite(() async {
      final batch = List<FilterExample>.of(_pendingClean);
      _pendingClean.clear();
      try {
        if (batch.isNotEmpty) {
          await _store.saveTrainingExamples(batch, manual: false);
        }
        if (_waitingForClean && _enabled && batch.isNotEmpty) {
          _requestTraining();
        }
      } catch (error) {
        _pendingClean.insertAll(0, batch);
        _limitPendingClean();
        rethrow;
      } finally {
        _cleanFlushQueued = false;
      }
      _scheduleCleanFlush();
    }).catchError(_logStorageError));
  }

  Future<void> recordFeedback(String sender, String text, {required bool spam}) {
    if (!_enabled) return Future<void>.value();
    final example = _example(sender, text, spam: spam);
    if (example.text.isEmpty) return Future<void>.value();
    final activation = _activation;
    return _enqueueWrite(() async {
      if (!_enabled || activation != _activation) return;
      await _initialize();
      if (!_enabled || activation != _activation) return;
      await _store.saveTrainingExamples([example], manual: true);
      _pendingClean.removeWhere((pending) => pending.text == example.text);
      _counts = await _store.loadTrainingLabelCounts();
      if (_enabled) _requestTraining();
    });
  }

  Future<void> reset() => _enqueueWrite(() async {
    await _store.clearTrainingExamples();
    _counts = (spam: 0, notSpam: 0);
    _initialized = true;
    _pendingClean.clear();
    _cleanTimer?.cancel();
    _cleanTimer = null;
    _clearModel();
  });

  static void _logStorageError(Object error) {
    appLogger.warn('Channel spam corpus storage failed: $error', tag: 'MessageFilter');
  }

  Future<void> _enqueueWrite(Future<void> Function() operation) {
    final result = _writes.then((_) => operation());
    // Keep later writes usable if this particular write fails.
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static FilterExample _example(
    String sender,
    String text, {
    required bool spam,
    String? sourceKey,
  }) {
    String boundedNormalized(String value, int maxLength) {
      final prefix = value.length > maxLength ? value.substring(0, maxLength) : value;
      final normalized = MessageFilterText.normalize(prefix);
      return normalized.length > maxLength
          ? normalized.substring(0, maxLength)
          : normalized;
    }

    return FilterExample(
      sender: boundedNormalized(sender, 100),
      text: boundedNormalized(text, _exampleTextLimit),
      spam: spam,
      sourceKey: sourceKey,
    );
  }

  void _requestTraining() {
    _revision++;
    _waitingForClean = false;
    _trainingNeeded = _counts.spam >= _minSpamExamples;
    if (!_trainingNeeded) {
      _classifier.reset();
      _timer?.cancel();
      _timer = null;
      return;
    }
    _scheduleTraining();
  }

  void _scheduleTraining() {
    if (!_enabled || !_trainingNeeded || _training || _timer != null) return;
    _timer = Timer(_trainingDelay, () {
      _timer = null;
      unawaited(_fit());
    });
  }

  Future<void> _fit() async {
    _trainingNeeded = false;
    _training = true;
    final revision = _revision;
    try {
      flushRecentClean();
      await _writes;
      if (!_enabled || _revision != revision) return;
      final examples = await _store.loadTrainingExamples();
      if (!_enabled || _revision != revision) return;
      final spam = [for (final example in examples) if (example.spam) example];
      final ham = [for (final example in examples) if (!example.spam) example];
      if (spam.length < _minSpamExamples || ham.isEmpty) {
        _classifier.reset();
        _waitingForClean = spam.length >= _minSpamExamples && ham.isEmpty;
        return;
      }
      final model = await _trainer(_classifier.trainingJob(spam, ham));
      if (!_enabled || _revision != revision) return;
      if (model == null) {
        _classifier.reset();
      } else {
        _classifier.use(model);
      }
    } catch (error) {
      appLogger.warn('Channel spam training failed: $error', tag: 'MessageFilter');
    } finally {
      _training = false;
      _scheduleTraining();
    }
  }
}

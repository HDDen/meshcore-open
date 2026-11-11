import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../helpers/backup_filter_training.dart';
import '../../helpers/backup_message_filter.dart';
import '../../helpers/mention_autocomplete.dart';
import '../../models/message_filter.dart';
import '../../storage/message_filter_store.dart';
import '../../utils/app_logger.dart';
import 'duplicate_tracker.dart';
import 'message_filter_learning.dart';
import 'message_filter_rules.dart';
import 'message_filter_text.dart';

/// Evaluates filters once per newly stored incoming channel message.
class MessageFilterService extends ChangeNotifier {
  MessageFilterService({MessageFilterStore? store, SpamTrainer? trainer})
    : _store = store ?? MessageFilterStore(),
      _trainer = trainer;

  final MessageFilterStore _store;
  final SpamTrainer? _trainer;
  MessageFilterSettings _settings = const MessageFilterSettings();
  List<FilterRule> _rules = const [];
  MessageFilterRules? _ruleMatcher;
  Future<void> _preferenceWrites = Future<void>.value();
  DuplicateTracker? _duplicates;
  MessageFilterLearning? _learning;

  MessageFilterSettings get settings => _settings;
  List<FilterRule> get rules => _rules;
  MessageFilterRules get ruleMatcher =>
      _ruleMatcher ??= MessageFilterRules(_rules);

  void load() {
    _settings = _store.loadSettings();
    _rules = List.unmodifiable(_store.loadRules());
    _ruleMatcher = null;
    _duplicates = null;
    unawaited(_syncLearning());
  }

  Future<void> updateSettings(MessageFilterSettings settings) =>
      _queuePreferenceWrite(() async {
        await _saveSettings(settings);
        notifyListeners();
      });

  Future<void> _saveSettings(MessageFilterSettings settings) async {
    final next = settings.copyWith(
      excludedChannelIds: Set.unmodifiable(settings.excludedChannelIds),
    );
    await _store.saveSettings(next);
    _settings = next;
    if (!next.enabled || !next.duplicates) _duplicates = null;
    await _syncLearning();
  }

  Future<void> setChannelExcluded(String channelId, {required bool excluded}) =>
      _queuePreferenceWrite(() async {
        final ids = {..._settings.excludedChannelIds};
        final changed = excluded ? ids.add(channelId) : ids.remove(channelId);
        if (!changed) return;
        await _saveSettings(_settings.copyWith(excludedChannelIds: ids));
        notifyListeners();
      });

  Future<void> addRule(FilterRule rule) =>
      _writeRules(() => [..._rules, rule]);

  Future<void> replaceRules(List<FilterRule> rules) {
    final replacement = List<FilterRule>.unmodifiable(rules);
    return _writeRules(() => replacement);
  }

  Future<void> _writeRules(List<FilterRule> Function() nextRules) =>
      _queuePreferenceWrite(() async {
        await _saveRules(nextRules());
        notifyListeners();
      });

  Future<void> _saveRules(List<FilterRule> rules) async {
    final next = List<FilterRule>.unmodifiable(rules);
    await _store.saveRules(next);
    _rules = next;
    _ruleMatcher = null;
  }

  Future<T> _queuePreferenceWrite<T>(Future<T> Function() operation) {
    final write = _preferenceWrites.then((_) => operation());
    _preferenceWrites = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  Future<bool> restoreBackup(BackupMessageFilterPreview preview) =>
      _queuePreferenceWrite(() async {
        if (!identical(preview.baselineSettings, _settings) ||
            !identical(preview.baselineRules, _rules)) return false;
        try {
          if (preview.changedSettings > 0) await _saveSettings(preview.settings);
          if (preview.addedRules.isNotEmpty) {
            await _saveRules([..._rules, ...preview.addedRules]);
          }
          return true;
        } finally {
          if (!identical(preview.baselineSettings, _settings) ||
              !identical(preview.baselineRules, _rules)) notifyListeners();
        }
      });

  bool appliesTo(String? channelId) =>
      _settings.enabled &&
      channelId != null &&
      !_settings.excludedChannelIds.contains(channelId);

  bool get hasActiveChecks =>
      _settings.enabled &&
      (_rules.isNotEmpty ||
          _settings.duplicates ||
          _settings.repeatedCharacters ||
          learningEnabled);

  static bool get learningAvailable => !kIsWeb;

  bool get learningEnabled =>
      learningAvailable && _settings.enabled && _settings.learning;
  int get spamExampleCount => _learning?.spamCount ?? 0;
  int get notSpamExampleCount => _learning?.notSpamCount ?? 0;

  bool get trainingBackupAvailable => learningAvailable && _store.trainingBackupAvailable;

  Future<BackupFilterTraining> snapshotTrainingBackup() async {
    if (!trainingBackupAvailable) throw StateError('Training corpus is unavailable');
    return BackupFilterTraining(await _getLearning().snapshotCorpus());
  }

  Future<int> restoreTrainingBackup(BackupFilterTraining backup) async {
    if (!trainingBackupAvailable) throw StateError('Training corpus is unavailable');
    final count = await _getLearning().restoreCorpus(backup.rows);
    if (count > 0) notifyListeners();
    return count;
  }

  MessageFilterLearning _getLearning() =>
      _learning ??= MessageFilterLearning(_store, trainer: _trainer);

  Future<void> _syncLearning() async {
    if (learningEnabled) {
      await _getLearning().setEnabled(true);
    } else {
      await _learning?.setEnabled(false);
    }
  }

  void flushRecentClean() => _learning?.flushRecentClean();

  Future<void> resetLearning() async {
    if (!learningAvailable) return;
    await _getLearning().reset();
    notifyListeners();
  }

  void recordClean(String channelId, String sender, String text) {
    if (!learningEnabled || !appliesTo(channelId)) return;
    final body = text.trimLeft();
    if (body.isEmpty || MessageFilterText.isStructuredPayload(body)) return;
    _learning?.recordClean(sender, body);
  }

  Future<void> recordFeedback(
    String channelId,
    String sender,
    String text, {
    required bool spam,
  }) async {
    if (!learningEnabled || !appliesTo(channelId)) return;
    final body = text.trimLeft();
    if (body.isEmpty || MessageFilterText.isStructuredPayload(body)) return;
    try {
      await _getLearning().recordFeedback(sender, body, spam: spam);
    } catch (error) {
      appLogger.warn('Could not save channel spam feedback: $error', tag: 'MessageFilter');
    }
  }

  void allowRestoredText(String channelId, String text) {
    if (!appliesTo(channelId) || (!_settings.duplicates && !learningEnabled)) {
      return;
    }
    final key = MessageFilterText.duplicateKey(MessageFilterText.normalize(text));
    if (_settings.duplicates) {
      (_duplicates ??= DuplicateTracker()).allow(channelId, key);
    }
    _learning?.allow(channelId, key);
  }

  FilterVerdict? evaluate({
    required String channelId,
    required String sender,
    required String text,
    DateTime? sentAt,
    DateTime? receivedAt,
    String? verifiedSenderKey,
    String? binaryPublicationKey,
    bool isAddressed = false,
  }) {
    if (!hasActiveChecks || !appliesTo(channelId)) {
      return null;
    }
    final body = text.trimLeft();
    if (body.isEmpty || MessageFilterText.isStructuredPayload(body)) {
      return null;
    }

    final checksRepeatedCharacters =
        _settings.repeatedCharacters &&
        body.length >= MessageFilterText.repeatedCharacterRun;
    final duplicateCheck =
        _settings.duplicates && !isAddressed && !MentionText.has(body);
    final normalizedText = duplicateCheck || checksRepeatedCharacters
        ? MessageFilterText.normalize(body)
        : null;
    final duplicateKey = duplicateCheck
        ? MessageFilterText.duplicateKey(normalizedText!)
        : null;
    String? normalizedSender;
    FilterReason? duplicateReason;
    if (duplicateCheck) {
      final now = receivedAt ?? DateTime.now();
      if (verifiedSenderKey == null) {
        normalizedSender = MessageFilterText.normalize(sender);
      }
      final identity = verifiedSenderKey == null
          ? 'name:$normalizedSender'
          : 'key:$verifiedSenderKey';
      duplicateReason = (_duplicates ??= DuplicateTracker()).check(
        channelId: channelId,
        sender: identity,
        textKey: duplicateKey!,
        sentAt: sentAt ?? now,
        receivedAt: now,
        sameSenderSends: _settings.repeatSends,
        publicationId:
            binaryPublicationKey ??
            (sentAt == null
                ? null
                : (sentAt.millisecondsSinceEpoch ~/ 1000, text)),
      );
    }

    final rule = _rules.isEmpty
        ? null
        : ruleMatcher.match(
            sender,
            body,
            normalizedSender: normalizedSender,
            normalizedText: normalizedText,
          );
    if (rule != null) return rule;
    if (checksRepeatedCharacters &&
        MessageFilterText.hasRepeatedCharacters(normalizedText!)) {
      return const FilterVerdict(reason: FilterReason.repeatedCharacters);
    }
    if (duplicateReason != null) return FilterVerdict(reason: duplicateReason);

    final learning = _learning;
    if (learning == null || !learning.canScore) return null;
    final textForScoring = normalizedText ?? MessageFilterText.normalize(body);
    if (learning.matches(
      channelId,
      normalizedSender ?? MessageFilterText.normalize(sender),
      textForScoring,
      duplicateKey: duplicateKey,
    )) {
      return const FilterVerdict(reason: FilterReason.learned);
    }
    return null;
  }

  @override
  void dispose() {
    unawaited(_learning?.setEnabled(false));
    super.dispose();
  }
}

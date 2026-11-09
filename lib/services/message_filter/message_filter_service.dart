import 'dart:async';

import 'package:flutter/foundation.dart';

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

  Future<void> updateSettings(MessageFilterSettings settings) async {
    final next = settings.copyWith(
      excludedChannelIds: Set.unmodifiable(settings.excludedChannelIds),
    );
    await _store.saveSettings(next);
    _settings = next;
    if (!next.enabled || !next.duplicates) _duplicates = null;
    await _syncLearning();
    notifyListeners();
  }

  Future<void> replaceRules(List<FilterRule> rules) async {
    final next = List<FilterRule>.unmodifiable(rules);
    await _store.saveRules(next);
    _rules = next;
    _ruleMatcher = null;
    notifyListeners();
  }

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
    final duplicateCheck = _settings.duplicates;
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

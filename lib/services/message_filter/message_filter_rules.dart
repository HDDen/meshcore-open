import '../../helpers/reaction_helper.dart';
import '../../models/channel_message.dart';
import '../../models/message_filter.dart';
import 'message_filter_text.dart';

/// Prepared user rules shared by ingest, the history view and search.
class MessageFilterRules {
  MessageFilterRules(this._rules);

  final List<FilterRule> _rules;
  List<(FilterRule, String)>? _normalized;
  final _projected = Expando<ChannelMessage>();

  /// View-only verdicts. Keep memoized copies for unchanged message snapshots
  /// so receiving a packet does not recheck every row in the loaded window.
  ChannelMessage project(ChannelMessage message) {
    if (_rules.isEmpty && !message.isFiltered) return message;
    final cached = _projected[message];
    if (cached != null) return cached;
    final projected = _project(message);
    _projected[message] = projected;
    if (!identical(message, projected)) _projected[projected] = projected;
    return projected;
  }

  ChannelMessage _project(ChannelMessage message) {
    final previous = message.filterVerdict;
    final verdict = forHistory(
      previous: previous,
      sender: message.senderName,
      text: message.text,
      isOutgoing: message.isOutgoing,
      wasBlocked: message.wasBlocked,
      restored: message.filterRestored,
    );
    return verdict == previous
        ? message
        : message.copyWith(filterVerdict: verdict);
  }

  FilterVerdict? forHistory({
    required FilterVerdict? previous,
    required String sender,
    required String text,
    required bool isOutgoing,
    required bool wasBlocked,
    required bool restored,
  }) {
    if (isOutgoing || wasBlocked || restored) return previous;
    if (previous != null &&
        previous.reason != FilterReason.senderRule &&
        previous.reason != FilterReason.textRule) {
      return previous;
    }
    if (_rules.isEmpty) return null;
    final body = text.trimLeft();
    if (body.isEmpty ||
        MessageFilterText.isStructuredPayload(body) ||
        ReactionHelper.parseReaction(text) != null) {
      return previous;
    }
    return match(sender, body);
  }

  FilterVerdict? match(
    String sender,
    String body, {
    String? normalizedSender,
    String? normalizedText,
  }) {
    final rules = _normalized ??= [
      for (final rule in _rules)
        if (rule.enabled) (rule, MessageFilterText.normalize(rule.pattern)),
    ];
    for (final (rule, pattern) in rules) {
      if (rule.field == FilterRuleField.text) continue;
      if (MessageFilterText.matchesNormalized(
        pattern,
        rule.match,
        normalizedSender ??= MessageFilterText.normalize(sender),
      )) {
        return FilterVerdict(
          reason: FilterReason.senderRule,
          detail: rule.pattern,
        );
      }
    }

    for (final (rule, pattern) in rules) {
      if (rule.field == FilterRuleField.sender) continue;
      if (MessageFilterText.matchesNormalized(
        pattern,
        rule.match,
        normalizedText ??= MessageFilterText.normalize(body),
      )) {
        return FilterVerdict(
          reason: FilterReason.textRule,
          detail: rule.pattern,
        );
      }
    }
    return null;
  }
}

import '../helpers/channel_message_timeline_helper.dart';
import '../models/channel.dart';
import '../models/channel_message.dart';
import '../models/message.dart';
import 'channel_identity_matcher.dart';
import 'channel_message_store.dart';
import 'channel_store.dart';
import 'message_store.dart';
import 'message_history_storage.dart';
import 'node_identity_store.dart';
import 'prefs_manager.dart';

class SharedMessageHistoryHelper {
  static const int scopeLength = 10;
  static final RegExp _channelsKeyPattern = RegExp(
    r'^channels([0-9a-fA-F]{10})$',
  );
  static final RegExp _channelMessagesKeyPattern = RegExp(
    r'^channel_messages_([0-9a-fA-F]{10})(?:\d+|name_[A-Za-z0-9_-]+)$',
  );
  static final RegExp _messagesKeyPattern = RegExp(
    r'^messages_([0-9a-fA-F]{10})[0-9a-fA-F]{64}$',
  );

  Future<List<ChannelMessage>> loadSecondaryChannelMessages({
    required String currentPublicKeyHex,
    required Channel channel,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;

    final currentScope = scopeFor(currentPublicKeyHex);
    if (currentScope.isEmpty) return const [];

    final result = <ChannelMessage>[];
    var processedMessages = 0;
    for (final scope in knownScopes()) {
      if (cancelled()) return const [];
      if (scope == currentScope) continue;

      final channelStore = ChannelStore()..setPublicKeyHex = scope;
      final channels = await channelStore.loadChannels();
      if (cancelled()) return const [];
      final matchedIndex = ChannelIdentityMatcher.findMatchingChannelIndex(
        channels,
        name: channel.name,
        pskHex: channel.pskHex,
      );
      if (matchedIndex == null) continue;

      final messageStore = ChannelMessageStore()..setPublicKeyHex = scope;
      messageStore.replaceChannels(channels);
      final messages = await messageStore.loadChannelMessages(
        matchedIndex,
        allowLegacyMigration: false,
      );
      if (cancelled()) return const [];
      final sourceName = _sourceNameForScope(scope);
      for (final message in messages) {
        result.add(_asHistoricalChannelMessage(message, sourceName));
        if (++processedMessages % 200 == 0) {
          await Future<void>.delayed(Duration.zero);
          if (cancelled()) return const [];
        }
      }
    }

    await Future<void>.delayed(Duration.zero);
    if (cancelled()) return const [];
    result.sort(ChannelMessageTimelineHelper.compare);
    return result;
  }

  /// Removes [messageId] from every other node's copy of [channel].
  ///
  /// Shared history is read straight out of the other scopes on this phone, so
  /// a message that lives there has to be deleted where it actually is —
  /// dropping it from the merged list alone would bring it back on the next
  /// merge.
  Future<bool> deleteSecondaryChannelMessage({
    required String currentPublicKeyHex,
    required Channel channel,
    required String messageId,
  }) {
    if (messageId.isEmpty) return Future.value(false);
    return _rewriteSecondaryChannelMessages(
      currentPublicKeyHex: currentPublicKeyHex,
      channel: channel,
      rewrite: (messages) =>
          messages.where((message) => message.messageId != messageId).toList(),
    );
  }

  /// Marks [messageId] blocked in every other node's copy of [channel].
  ///
  /// Same reason as the delete above: the flag has to be written where the
  /// message actually lives, or the next merge brings back the unflagged copy.
  Future<bool> markSecondaryChannelMessageBlocked({
    required String currentPublicKeyHex,
    required Channel channel,
    required String messageId,
  }) {
    if (messageId.isEmpty) return Future.value(false);
    return _rewriteSecondaryChannelMessages(
      currentPublicKeyHex: currentPublicKeyHex,
      channel: channel,
      rewrite: (messages) => [
        for (final message in messages)
          message.messageId == messageId && !message.wasBlocked
              ? message.copyWith(wasBlocked: true)
              : message,
      ],
    );
  }

  /// Walks every other node's copy of [channel] and saves back whatever
  /// [rewrite] returns, skipping scopes it leaves untouched.
  Future<bool> _rewriteSecondaryChannelMessages({
    required String currentPublicKeyHex,
    required Channel channel,
    required List<ChannelMessage> Function(List<ChannelMessage>) rewrite,
  }) async {
    final currentScope = scopeFor(currentPublicKeyHex);
    if (currentScope.isEmpty) return false;

    var changed = false;
    for (final scope in knownScopes()) {
      if (scope == currentScope) continue;

      final channelStore = ChannelStore()..setPublicKeyHex = scope;
      final channels = await channelStore.loadChannels();
      final matchedIndex = ChannelIdentityMatcher.findMatchingChannelIndex(
        channels,
        name: channel.name,
        pskHex: channel.pskHex,
      );
      if (matchedIndex == null) continue;

      final messageStore = ChannelMessageStore()..setPublicKeyHex = scope;
      messageStore.replaceChannels(channels);
      final messages = await messageStore.loadChannelMessages(
        matchedIndex,
        allowLegacyMigration: false,
      );
      final rewritten = rewrite(messages);
      if (_sameChannelMessages(messages, rewritten)) continue;

      await messageStore.replaceChannelMessages(matchedIndex, rewritten);
      changed = true;
    }
    return changed;
  }

  static bool _sameChannelMessages(
    List<ChannelMessage> a,
    List<ChannelMessage> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// Contact-chat counterpart of [deleteSecondaryChannelMessage].
  Future<bool> deleteSecondaryContactMessage({
    required String currentPublicKeyHex,
    required String contactKeyHex,
    required String messageId,
  }) async {
    final currentScope = scopeFor(currentPublicKeyHex);
    if (currentScope.isEmpty || contactKeyHex.isEmpty || messageId.isEmpty) {
      return false;
    }

    var deleted = false;
    for (final scope in knownScopes()) {
      if (scope == currentScope) continue;

      final messageStore = MessageStore()..setPublicKeyHex = scope;
      final messages = await messageStore.loadScopedMessages(contactKeyHex);
      final remaining = messages
          .where((message) => message.messageId != messageId)
          .toList();
      if (remaining.length == messages.length) continue;

      await messageStore.deleteMessage(contactKeyHex, messageId);
      deleted = true;
    }
    return deleted;
  }

  /// Flags one message as blocked in every other node's copy of this
  /// conversation.
  ///
  /// Same reason [deleteSecondaryContactMessage] exists: flagging only our own
  /// copy lets the next merge uncover the unflagged twin.
  Future<bool> markSecondaryContactMessageBlocked({
    required String currentPublicKeyHex,
    required String contactKeyHex,
    required String messageId,
  }) async {
    final currentScope = scopeFor(currentPublicKeyHex);
    if (currentScope.isEmpty || contactKeyHex.isEmpty || messageId.isEmpty) {
      return false;
    }

    var marked = false;
    for (final scope in knownScopes()) {
      if (scope == currentScope) continue;

      final messageStore = MessageStore()..setPublicKeyHex = scope;
      final messages = await messageStore.loadScopedMessages(contactKeyHex);
      final index = messages.indexWhere((m) => m.messageId == messageId);
      if (index < 0 || messages[index].wasBlocked) continue;

      messages[index] = messages[index].copyWith(wasBlocked: true);
      await messageStore.saveMessages(contactKeyHex, messages);
      marked = true;
    }
    return marked;
  }

  Future<List<Message>> loadSecondaryContactMessages({
    required String currentPublicKeyHex,
    required String contactKeyHex,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;

    final currentScope = scopeFor(currentPublicKeyHex);
    if (currentScope.isEmpty || contactKeyHex.isEmpty) return const [];

    final result = <Message>[];
    var processedMessages = 0;
    for (final scope in knownScopes()) {
      if (cancelled()) return const [];
      if (scope == currentScope) continue;

      final messageStore = MessageStore()..setPublicKeyHex = scope;
      final messages = await messageStore.loadScopedMessages(contactKeyHex);
      if (cancelled()) return const [];
      final sourceName = _sourceNameForScope(scope);
      for (final message in messages) {
        result.add(_asHistoricalContactMessage(message, sourceName));
        if (++processedMessages % 200 == 0) {
          await Future<void>.delayed(Duration.zero);
          if (cancelled()) return const [];
        }
      }
    }

    await Future<void>.delayed(Duration.zero);
    if (cancelled()) return const [];
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Future<MessageStoreSummary?> loadSecondaryContactMessageSummary({
    required String currentPublicKeyHex,
    required String contactKeyHex,
  }) async {
    return (await loadSecondaryContactMessageSummaries(
      currentPublicKeyHex: currentPublicKeyHex,
      contactKeyHexes: [contactKeyHex],
    ))[contactKeyHex];
  }

  Future<Map<String, MessageStoreSummary>>
  loadSecondaryContactMessageSummaries({
    required String currentPublicKeyHex,
    required Iterable<String> contactKeyHexes,
  }) async {
    final currentScope = scopeFor(currentPublicKeyHex);
    final contactKeys = contactKeyHexes.where((key) => key.isNotEmpty).toSet();
    if (currentScope.isEmpty || contactKeys.isEmpty) return const {};

    final result = <String, MessageStoreSummary>{};
    for (final scope in knownScopes()) {
      if (scope == currentScope) continue;

      final messageStore = MessageStore()..setPublicKeyHex = scope;
      final summaries = await messageStore.loadMessageSummaries(
        contactKeys,
        includeLegacyUnscoped: false,
      );
      for (final entry in summaries.entries) {
        final existing = result[entry.key];
        final summary = entry.value;
        result[entry.key] = MessageStoreSummary(
          messageCount: (existing?.messageCount ?? 0) + summary.messageCount,
          latestMessageAt:
              existing == null ||
                  summary.latestMessageAt.isAfter(existing.latestMessageAt)
              ? summary.latestMessageAt
              : existing.latestMessageAt,
          latestMessageText:
              existing == null ||
                  summary.latestMessageAt.isAfter(existing.latestMessageAt)
              ? summary.latestMessageText
              : existing.latestMessageText,
        );
      }
    }
    return result;
  }

  /// True when any other node's copy of this conversation could hold a
  /// marker. This uses the database's cached marker keys, so loading every
  /// secondary conversation just to find pins is unnecessary.
  ///
  /// [scopes] is passed in rather than fetched, because [knownScopes] walks
  /// every known storage key, so asking it once per contact is still wasteful.
  static bool secondaryMayContainMarker({
    required String currentPublicKeyHex,
    required String contactKeyHex,
    required Set<String> scopes,
  }) {
    final currentScope = scopeFor(currentPublicKeyHex);
    if (currentScope.isEmpty || contactKeyHex.isEmpty) return false;
    for (final scope in scopes) {
      if (scope == currentScope) continue;
      final store = MessageStore()..setPublicKeyHex = scope;
      if (store.mayContainMarker(contactKeyHex)) return true;
    }
    return false;
  }

  static Set<String> knownScopes() {
    final result = <String>{};
    final keys = <String>{
      ...PrefsManager.instance.getKeys(),
      ...MessageHistoryStorage.instance.getKeys(MessageHistoryKind.direct),
      ...MessageHistoryStorage.instance.getKeys(MessageHistoryKind.channel),
    };
    for (final key in keys) {
      final channelsMatch = _channelsKeyPattern.firstMatch(key);
      if (channelsMatch != null) {
        result.add(channelsMatch.group(1)!.toLowerCase());
        continue;
      }

      final channelMessagesMatch = _channelMessagesKeyPattern.firstMatch(key);
      if (channelMessagesMatch != null) {
        result.add(channelMessagesMatch.group(1)!.toLowerCase());
        continue;
      }

      final messagesMatch = _messagesKeyPattern.firstMatch(key);
      if (messagesMatch != null) {
        result.add(messagesMatch.group(1)!.toLowerCase());
      }
    }
    return result;
  }

  static String scopeFor(String publicKeyHex) {
    final value = publicKeyHex.trim();
    if (value.length < scopeLength) return '';
    return value.substring(0, scopeLength).toLowerCase();
  }

  String _sourceNameForScope(String scope) {
    final storedName = (NodeIdentityStore()..setPublicKeyHex = scope)
        .loadName();
    return storedName ?? scope.substring(0, 6).toUpperCase();
  }

  ChannelMessage _asHistoricalChannelMessage(
    ChannelMessage message,
    String sourceName,
  ) {
    return message.copyWith(
      status:
          message.isOutgoing && message.status == ChannelMessageStatus.pending
          ? ChannelMessageStatus.sent
          : message.status,
      sharedHistorySourceName: sourceName,
    );
  }

  Message _asHistoricalContactMessage(Message message, String sourceName) {
    return message.copyWith(
      status: message.isOutgoing && message.status == MessageStatus.pending
          ? MessageStatus.sent
          : message.status,
      sharedHistorySourceName: sourceName,
    );
  }
}

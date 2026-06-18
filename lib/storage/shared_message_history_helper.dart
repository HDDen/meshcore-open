import '../models/channel.dart';
import '../models/channel_message.dart';
import '../models/message.dart';
import 'channel_identity_matcher.dart';
import 'channel_message_store.dart';
import 'channel_store.dart';
import 'message_store.dart';
import 'node_identity_store.dart';
import 'prefs_manager.dart';

class SharedMessageHistoryHelper {
  static const int _scopeLength = 10;
  static final RegExp _channelsKeyPattern = RegExp(
    r'^channels([0-9a-fA-F]{10})$',
  );
  static final RegExp _channelMessagesKeyPattern = RegExp(
    r'^channel_messages_([0-9a-fA-F]{10})\d+$',
  );
  static final RegExp _messagesKeyPattern = RegExp(
    r'^messages_([0-9a-fA-F]{10}).+',
  );

  Future<List<ChannelMessage>> loadSecondaryChannelMessages({
    required String currentPublicKeyHex,
    required Channel channel,
  }) async {
    final currentScope = _scopeFor(currentPublicKeyHex);
    if (currentScope.isEmpty) return const [];

    final result = <ChannelMessage>[];
    for (final scope in _knownScopes()) {
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
      final messages = await messageStore.loadChannelMessages(matchedIndex);
      final sourceName = _sourceNameForScope(scope);
      result.addAll(
        messages.map(
          (message) => _asHistoricalChannelMessage(message, sourceName),
        ),
      );
    }

    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Future<List<Message>> loadSecondaryContactMessages({
    required String currentPublicKeyHex,
    required String contactKeyHex,
  }) async {
    final currentScope = _scopeFor(currentPublicKeyHex);
    if (currentScope.isEmpty || contactKeyHex.isEmpty) return const [];

    final result = <Message>[];
    for (final scope in _knownScopes()) {
      if (scope == currentScope) continue;

      final messageStore = MessageStore()..setPublicKeyHex = scope;
      final messages = await messageStore.loadMessages(contactKeyHex);
      final sourceName = _sourceNameForScope(scope);
      result.addAll(
        messages.map(
          (message) => _asHistoricalContactMessage(message, sourceName),
        ),
      );
    }

    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Set<String> _knownScopes() {
    final result = <String>{};
    for (final key in PrefsManager.instance.getKeys()) {
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

  String _scopeFor(String publicKeyHex) {
    if (publicKeyHex.length < _scopeLength) return '';
    return publicKeyHex.substring(0, _scopeLength).toLowerCase();
  }

  String _sourceNameForScope(String scope) {
    final storedName = (NodeIdentityStore()..setPublicKeyHex = scope).loadName();
    return storedName ?? scope.substring(0, 6).toUpperCase();
  }

  ChannelMessage _asHistoricalChannelMessage(
    ChannelMessage message,
    String sourceName,
  ) {
    return message.copyWith(
      status: message.isOutgoing && message.status == ChannelMessageStatus.pending
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

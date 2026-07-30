import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/message_search_worker.dart';
import '../l10n/l10n.dart';
import '../models/app_settings.dart';
import '../models/channel.dart';
import '../models/contact.dart';
import '../services/app_settings_service.dart';
import '../storage/channel_identity_matcher.dart';
import '../storage/channel_message_store.dart';
import '../storage/channel_store.dart';
import '../storage/message_store.dart';
import '../storage/prefs_manager.dart';

enum MessageSearchEntryType { channel, room, contact }

enum MessageSearchScope { channels, contacts }

class MessageSearchResult {
  final MessageSearchEntryType type;
  final Channel? channel;
  final Contact? contact;
  final String messageId;
  final DateTime timestamp;
  final String senderName;
  final String text;
  final String dedupeKey;

  const MessageSearchResult({
    required this.type,
    required this.messageId,
    required this.timestamp,
    required this.senderName,
    required this.text,
    required this.dedupeKey,
    this.channel,
    this.contact,
  });
}

class MessageSearchSheet extends StatefulWidget {
  final MessageSearchScope scope;
  final Future<void> Function(MessageSearchResult result) onOpenResult;

  const MessageSearchSheet({
    super.key,
    required this.scope,
    required this.onOpenResult,
  });

  static Future<void> show(
    BuildContext context, {
    required MessageSearchScope scope,
    required Future<void> Function(MessageSearchResult result) onOpenResult,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MessageSearchSheet(
        scope: scope,
        onOpenResult: onOpenResult,
      ),
    );
  }

  @override
  State<MessageSearchSheet> createState() => _MessageSearchSheetState();
}

class _MessageSearchSheetState extends State<MessageSearchSheet> {
  static const Duration _debounceDuration = Duration(milliseconds: 1500);
  static const int _minimumQueryLength = 3;
  static const int _scopeLength = 10;

  static final RegExp _scopeKeyPattern = RegExp(
    r'^(?:channels|messages_|channel_messages_)([0-9a-fA-F]{10})',
  );

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  Future<void>? _activeSearch;
  String _lastSearchText = '';
  int _generation = 0;
  bool _hasSearched = false;
  bool _isSearching = false;
  List<MessageSearchResult> _results = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_scheduleSearch);
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _controller.removeListener(_scheduleSearch);
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    final rawText = _controller.text;
    if (rawText == _lastSearchText) return;
    _lastSearchText = rawText;
    _generation++;
    _debounce?.cancel();
    final query = rawText.trim();
    if (query.length < _minimumQueryLength) {
      setState(() {
        _hasSearched = false;
        _isSearching = false;
        _results = const [];
      });
      return;
    }

    setState(() {
      _hasSearched = false;
      _isSearching = false;
      _results = const [];
    });

    final generation = _generation;
    _debounce = Timer(_debounceDuration, () {
      _queueSearch(query, generation);
    });
  }

  void _queueSearch(String query, int generation) {
    final previousSearch = _activeSearch;
    final queuedSearch = () async {
      if (previousSearch != null) {
        try {
          await previousSearch;
        } catch (_) {
          // A failed stale search must not block the latest query.
        }
      }
      if (!mounted || generation != _generation) return;
      try {
        await _runSearch(query, generation);
      } catch (_) {
        // Keep the sheet responsive if one stored scope is unreadable.
      }
    }();
    _activeSearch = queuedSearch;
    unawaited(
      queuedSearch.whenComplete(() {
        if (identical(_activeSearch, queuedSearch)) {
          _activeSearch = null;
        }
      }),
    );
  }

  Future<void> _runSearch(String query, int generation) async {
    if (!mounted || generation != _generation) return;
    setState(() {
      _hasSearched = true;
      _isSearching = true;
      _results = const [];
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || generation != _generation) return;

    final connector = context.read<MeshCoreConnector>();
    final settings = context.read<AppSettingsService>().settings;
    final normalizedQuery = query.toLowerCase();
    var published = <MessageSearchResult>[];
    final pending = <MessageSearchResult>[];
    final seen = <String>{};
    Timer? publishTimer;

    void publishResults() {
      if (generation != _generation || !mounted) return;
      if (pending.isEmpty) return;
      pending.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      published = _mergeNewestFirst(published, pending);
      pending.clear();
      setState(() => _results = published);
    }

    void addResults(Iterable<MessageSearchResult> results) {
      if (generation != _generation || !mounted) return;
      for (final result in results) {
        if (seen.add(result.dedupeKey)) pending.add(result);
      }
      if (pending.isEmpty) return;
      publishTimer ??= Timer(const Duration(milliseconds: 250), () {
        publishTimer = null;
        publishResults();
      });
    }

    try {
      if (widget.scope == MessageSearchScope.channels) {
        await _searchChannels(
          connector: connector,
          settings: settings,
          query: normalizedQuery,
          generation: generation,
          addResults: addResults,
        );
        if (settings.roomServerShowNotemptyContactsOnChatscreen) {
          await _searchContacts(
            connector: connector,
            settings: settings,
            query: normalizedQuery,
            includeContacts: true,
            includeRooms: false,
            generation: generation,
            addResults: addResults,
          );
        }
        if (settings.roomServerShowNotemptyOnChatscreen) {
          await _searchContacts(
            connector: connector,
            settings: settings,
            query: normalizedQuery,
            includeContacts: false,
            includeRooms: true,
            generation: generation,
            addResults: addResults,
          );
        }
      } else {
        await _searchContacts(
          connector: connector,
          settings: settings,
          query: normalizedQuery,
          includeContacts: true,
          includeRooms: true,
          generation: generation,
          addResults: addResults,
        );
      }
    } finally {
      publishTimer?.cancel();
      publishResults();
      if (mounted && generation == _generation) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _searchChannels({
    required MeshCoreConnector connector,
    required AppSettings settings,
    required String query,
    required int generation,
    required void Function(Iterable<MessageSearchResult> results) addResults,
  }) async {
    final currentScope = _scopeFor(connector.selfPublicKeyHex);
    if (currentScope.isEmpty) return;
    final channels = connector.channels.where((c) => !c.isEmpty).toList();
    if (channels.isEmpty) return;

    final currentStore = ChannelMessageStore()..setPublicKeyHex = currentScope;
    currentStore.replaceChannels(channels);
    for (final channel in channels) {
      if (generation != _generation) return;
      await _searchChannelMessages(
        store: currentStore,
        channel: channel,
        channelIndex: channel.index,
        scope: currentScope,
        query: query,
        generation: generation,
        addResults: addResults,
      );
    }

    if (!settings.sharedMessageHistoryMode.includesChannels) return;

    for (final scope in _knownScopes()) {
      if (generation != _generation) return;
      if (scope == currentScope) continue;
      final channelStore = ChannelStore()..setPublicKeyHex = scope;
      final secondaryChannels = await channelStore.loadChannels();
      if (secondaryChannels.isEmpty) continue;
      final messageStore = ChannelMessageStore()..setPublicKeyHex = scope;
      messageStore.replaceChannels(secondaryChannels);

      for (final channel in channels) {
        final matchedIndex = ChannelIdentityMatcher.findMatchingChannelIndex(
          secondaryChannels,
          name: channel.name,
          pskHex: channel.pskHex,
        );
        if (matchedIndex == null) continue;
        await _searchChannelMessages(
          store: messageStore,
          channel: channel,
          channelIndex: matchedIndex,
          scope: scope,
          query: query,
          generation: generation,
          addResults: addResults,
        );
      }
    }
  }

  Future<void> _searchChannelMessages({
    required ChannelMessageStore store,
    required Channel channel,
    required int channelIndex,
    required String scope,
    required String query,
    required int generation,
    required void Function(Iterable<MessageSearchResult> results) addResults,
  }) async {
    final jsonString = await store.loadChannelMessagesJsonForSearch(
      channelIndex,
    );
    if (jsonString == null || generation != _generation) return;
    final hits = await searchStoredMessages(
      jsonString: jsonString,
      normalizedQuery: query,
      type: StoredMessageSearchType.channel,
    );
    if (!mounted || generation != _generation) return;

    final batch = <MessageSearchResult>[];
    for (var index = 0; index < hits.length; index++) {
      final hit = hits[index];
      batch.add(
        MessageSearchResult(
          type: MessageSearchEntryType.channel,
          channel: channel,
          messageId: hit.messageId,
          timestamp: DateTime.fromMillisecondsSinceEpoch(hit.timestampMs),
          senderName: hit.senderName,
          text: hit.text,
          dedupeKey:
              'c|$scope|${channel.pskHex}|${channel.name}|${hit.messageId}',
        ),
      );
      if (batch.length >= 200) {
        addResults(List.of(batch));
        batch.clear();
        await Future<void>.delayed(Duration.zero);
        if (!mounted || generation != _generation) return;
      }
    }
    if (batch.isNotEmpty) addResults(batch);
  }

  Future<void> _searchContacts({
    required MeshCoreConnector connector,
    required AppSettings settings,
    required String query,
    required bool includeContacts,
    required bool includeRooms,
    required int generation,
    required void Function(Iterable<MessageSearchResult> results) addResults,
  }) async {
    final currentScope = _scopeFor(connector.selfPublicKeyHex);
    if (currentScope.isEmpty) return;
    final contacts = _searchableContacts(
      connector.contacts,
      includeContacts: includeContacts,
      includeRooms: includeRooms,
    );
    if (contacts.isEmpty) return;
    final roomSenderNamesByPrefix = includeRooms
        ? _roomSenderNamesByPrefix(connector)
        : const <String, String>{};

    final currentStore = MessageStore()..setPublicKeyHex = currentScope;
    for (final contact in contacts) {
      if (generation != _generation) return;
      await _searchContactMessages(
        store: currentStore,
        contact: contact,
        scope: currentScope,
        query: query,
        roomSenderNamesByPrefix: roomSenderNamesByPrefix,
        generation: generation,
        addResults: addResults,
      );
    }

    if (!settings.sharedMessageHistoryMode.includesContacts) return;

    for (final scope in _knownScopes()) {
      if (generation != _generation) return;
      if (scope == currentScope) continue;
      final store = MessageStore()..setPublicKeyHex = scope;
      for (final contact in contacts) {
        if (contact.type == advTypeRoom) continue;
        await _searchContactMessages(
          store: store,
          contact: contact,
          scope: scope,
          query: query,
          roomSenderNamesByPrefix: roomSenderNamesByPrefix,
          generation: generation,
          addResults: addResults,
        );
      }
    }
  }

  List<Contact> _searchableContacts(
    Iterable<Contact> contacts, {
    required bool includeContacts,
    required bool includeRooms,
  }) {
    final byKey = <String, Contact>{};
    for (final contact in contacts) {
      if (contact.type == advTypeChat && includeContacts) {
        byKey[contact.publicKeyHex] = contact;
      } else if (contact.type == advTypeRoom && includeRooms) {
        byKey[contact.publicKeyHex] = contact;
      }
    }
    return byKey.values.toList();
  }

  Future<void> _searchContactMessages({
    required MessageStore store,
    required Contact contact,
    required String scope,
    required String query,
    required Map<String, String> roomSenderNamesByPrefix,
    required int generation,
    required void Function(Iterable<MessageSearchResult> results) addResults,
  }) async {
    final jsonString = await store.loadMessagesJsonForSearch(
      contact.publicKeyHex,
    );
    if (jsonString == null || generation != _generation) return;
    final hits = await searchStoredMessages(
      jsonString: jsonString,
      normalizedQuery: query,
      type: contact.type == advTypeRoom
          ? StoredMessageSearchType.room
          : StoredMessageSearchType.contact,
      contactName: contact.name,
      roomSenderNamesByPrefix: roomSenderNamesByPrefix,
    );
    if (!mounted || generation != _generation) return;

    final batch = <MessageSearchResult>[];
    for (var index = 0; index < hits.length; index++) {
      final hit = hits[index];
      batch.add(
        MessageSearchResult(
          type: contact.type == advTypeRoom
              ? MessageSearchEntryType.room
              : MessageSearchEntryType.contact,
          contact: contact,
          messageId: hit.messageId,
          timestamp: DateTime.fromMillisecondsSinceEpoch(hit.timestampMs),
          senderName: hit.senderName,
          text: hit.text,
          dedupeKey: 'm|$scope|${contact.publicKeyHex}|${hit.messageId}',
        ),
      );
      if (batch.length >= 200) {
        addResults(List.of(batch));
        batch.clear();
        await Future<void>.delayed(Duration.zero);
        if (!mounted || generation != _generation) return;
      }
    }
    if (batch.isNotEmpty) addResults(batch);
  }

  List<MessageSearchResult> _mergeNewestFirst(
    List<MessageSearchResult> existing,
    List<MessageSearchResult> additions,
  ) {
    if (existing.isEmpty) return List.of(additions);
    final merged = <MessageSearchResult>[];
    var existingIndex = 0;
    var additionIndex = 0;
    while (existingIndex < existing.length &&
        additionIndex < additions.length) {
      final existingResult = existing[existingIndex];
      final addition = additions[additionIndex];
      if (!addition.timestamp.isAfter(existingResult.timestamp)) {
        merged.add(existingResult);
        existingIndex++;
      } else {
        merged.add(addition);
        additionIndex++;
      }
    }
    if (existingIndex < existing.length) {
      merged.addAll(existing.getRange(existingIndex, existing.length));
    }
    if (additionIndex < additions.length) {
      merged.addAll(additions.getRange(additionIndex, additions.length));
    }
    return merged;
  }

  Map<String, String> _roomSenderNamesByPrefix(
    MeshCoreConnector connector,
  ) {
    final result = <String, String>{};
    for (final contact in connector.allContactsUnfiltered) {
      if (contact.publicKey.length < 4) continue;
      result.putIfAbsent(
        _hexPrefix(contact.publicKey, 4),
        () => contact.name,
      );
    }
    return result;
  }

  String _hexPrefix(List<int> bytes, int count) {
    final buffer = StringBuffer();
    for (var index = 0; index < count; index++) {
      buffer.write(bytes[index].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  String _scopeFor(String publicKeyHex) {
    final value = publicKeyHex.trim().toLowerCase();
    return value.length >= _scopeLength ? value.substring(0, _scopeLength) : '';
  }

  Set<String> _knownScopes() {
    final result = <String>{};
    for (final key in PrefsManager.instance.getKeys()) {
      final match = _scopeKeyPattern.firstMatch(key);
      if (match != null) result.add(match.group(1)!.toLowerCase());
    }
    return result;
  }

  Future<void> _openResult(MessageSearchResult result) async {
    await widget.onOpenResult(result);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
    final theme = Theme.of(context);
    final dateFormat = DateFormat.yMd(
      Localizations.localeOf(context).toString(),
    ).add_Hm();

    return SafeArea(
      child: SizedBox(
        height: maxHeight,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.chat_serchMessages,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.l10n.chat_serchMessages_placeholder,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              if (_hasSearched)
                Text(
                  context.l10n.chat_serchMessages_results_found(
                    _results.length,
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 8),
              Expanded(
                child: !_hasSearched
                    ? Center(
                        child: Text(context.l10n.chat_serchMessages_results),
                      )
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _titleForResult(context, result),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  dateFormat.format(result.timestamp),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '${result.senderName}: ${result.text}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => unawaited(_openResult(result)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _titleForResult(BuildContext context, MessageSearchResult result) {
    switch (result.type) {
      case MessageSearchEntryType.channel:
        return context.l10n.chat_serchMessages_results_channel(
          result.channel?.name ?? '',
        );
      case MessageSearchEntryType.room:
        return context.l10n.chat_serchMessages_results_room(
          result.contact?.name ?? '',
        );
      case MessageSearchEntryType.contact:
        return context.l10n.chat_serchMessages_results_contact(
          result.contact?.name ?? '',
        );
    }
  }
}

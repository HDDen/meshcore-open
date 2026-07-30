import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/cancellable_compute.dart';
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
import '../storage/shared_message_history_helper.dart';

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
  final String sourceId;

  const MessageSearchResult({
    required this.type,
    required this.messageId,
    required this.timestamp,
    required this.senderName,
    required this.text,
    required this.dedupeKey,
    required this.sourceId,
    this.channel,
    this.contact,
  });
}

class _MessageSearchSourceDescriptor {
  final StoredMessageSearchSource workerSource;
  final MessageSearchEntryType type;
  final Channel? channel;
  final List<Channel> channelCandidates;
  final Contact? contact;

  const _MessageSearchSourceDescriptor({
    required this.workerSource,
    required this.type,
    this.channel,
    this.channelCandidates = const [],
    this.contact,
  });
}

class MessageSearchSheet extends StatefulWidget {
  final MessageSearchScope scope;
  final Channel? channelFilter;
  final Contact? contactFilter;
  final Future<void> Function(MessageSearchResult result) onOpenResult;

  const MessageSearchSheet({
    super.key,
    required this.scope,
    this.channelFilter,
    this.contactFilter,
    required this.onOpenResult,
  });

  static Future<void> show(
    BuildContext context, {
    required MessageSearchScope scope,
    Channel? channelFilter,
    Contact? contactFilter,
    required Future<void> Function(MessageSearchResult result) onOpenResult,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MessageSearchSheet(
        scope: scope,
        channelFilter: channelFilter,
        contactFilter: contactFilter,
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
  static const int _maxWorkerSources = 24;
  static const int _maxWorkerJsonChars = 1024 * 1024;

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  Future<void>? _activeSearch;
  CancellableComputeTask<List<StoredMessageSearchHit>>? _activeWorkerTask;
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
    _activeWorkerTask?.cancel();
    _activeWorkerTask = null;
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
    _activeWorkerTask?.cancel();
    _activeWorkerTask = null;
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
    final queuedSearch = () async {
      if (!mounted || generation != _generation) return;
      try {
        await _runSearch(query, generation);
      } on CancellableComputeCancelledException {
        // A newer query or a closed sheet cancelled this search.
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
    final seenSourceMessages = <String>{};
    final dedupeOwners = <String, String>{};
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
        final sourceMessageKey = '${result.sourceId}|${result.messageId}';
        if (!seenSourceMessages.add(sourceMessageKey)) continue;
        final owner = dedupeOwners.putIfAbsent(
          result.dedupeKey,
          () => result.sourceId,
        );
        if (owner == result.sourceId) pending.add(result);
      }
      if (pending.isEmpty) return;
      publishTimer ??= Timer(const Duration(milliseconds: 250), () {
        publishTimer = null;
        publishResults();
      });
    }

    try {
      final sources = <_MessageSearchSourceDescriptor>[];
      if (widget.scope == MessageSearchScope.channels) {
        sources.addAll(
          await _collectChannelSources(
            connector: connector,
            settings: settings,
            generation: generation,
            channelFilter: widget.channelFilter,
          ),
        );
        if (!mounted || generation != _generation) return;
        if (widget.channelFilter == null &&
            settings.roomServerShowNotemptyContactsOnChatscreen) {
          sources.addAll(
            await _collectContactSources(
              connector: connector,
              settings: settings,
              includeContacts: true,
              includeRooms: false,
              generation: generation,
            ),
          );
        }
        if (!mounted || generation != _generation) return;
        if (widget.channelFilter == null &&
            settings.roomServerShowNotemptyOnChatscreen) {
          sources.addAll(
            await _collectContactSources(
              connector: connector,
              settings: settings,
              includeContacts: false,
              includeRooms: true,
              generation: generation,
            ),
          );
        }
      } else {
        sources.addAll(
          await _collectContactSources(
            connector: connector,
            settings: settings,
            includeContacts: true,
            includeRooms: true,
            generation: generation,
            contactFilter: widget.contactFilter,
          ),
        );
      }
      if (!mounted || generation != _generation) return;

      final descriptorsById = <String, _MessageSearchSourceDescriptor>{};
      for (final source in sources) {
        descriptorsById.putIfAbsent(source.workerSource.sourceId, () => source);
      }
      final roomSenderNamesByPrefix = _roomSenderNamesByPrefix(connector);

      for (final batch in _workerBatches(descriptorsById.values)) {
        if (!mounted || generation != _generation) return;
        final task =
            startCancellableCompute<
              StoredMessageSearchRequest,
              List<StoredMessageSearchHit>
            >(
              searchStoredMessageBatch,
              StoredMessageSearchRequest(
                normalizedQuery: normalizedQuery,
                sources: batch.map((source) => source.workerSource).toList(),
                roomSenderNamesByPrefix: roomSenderNamesByPrefix,
              ),
              debugLabel: 'message-search',
            );
        _activeWorkerTask = task;
        final List<StoredMessageSearchHit> hits;
        try {
          hits = await task.result;
        } finally {
          if (identical(_activeWorkerTask, task)) {
            _activeWorkerTask = null;
          }
        }
        if (!mounted || generation != _generation) return;

        final resultBatch = <MessageSearchResult>[];
        for (final hit in hits) {
          final descriptor = descriptorsById[hit.sourceId];
          if (descriptor == null) continue;
          final channelTarget =
              descriptor.type == MessageSearchEntryType.channel
              ? _channelTargetForSearchHit(connector, descriptor, hit)
              : null;
          resultBatch.add(
            MessageSearchResult(
              type: descriptor.type,
              channel: channelTarget?.channel ?? descriptor.channel,
              contact: descriptor.contact,
              messageId: channelTarget?.messageId ?? hit.messageId,
              timestamp: DateTime.fromMillisecondsSinceEpoch(hit.timestampMs),
              senderName: hit.senderName,
              text: hit.text,
              dedupeKey: _resultDedupeKey(descriptor, hit),
              sourceId: hit.sourceId,
            ),
          );
          if (resultBatch.length >= 200) {
            addResults(List.of(resultBatch));
            resultBatch.clear();
            await Future<void>.delayed(Duration.zero);
            if (!mounted || generation != _generation) return;
          }
        }
        if (resultBatch.isNotEmpty) addResults(resultBatch);
      }
    } finally {
      publishTimer?.cancel();
      publishResults();
      if (mounted && generation == _generation) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<List<_MessageSearchSourceDescriptor>> _collectChannelSources({
    required MeshCoreConnector connector,
    required AppSettings settings,
    required int generation,
    Channel? channelFilter,
  }) async {
    final currentScope = SharedMessageHistoryHelper.scopeFor(
      connector.selfPublicKeyHex,
    );
    if (currentScope.isEmpty) return const [];
    final channels = channelFilter == null
        ? connector.channels.where((channel) => !channel.isEmpty).toList()
        : connector.channels
              .where(
                (channel) =>
                    !channel.isEmpty && channel.index == channelFilter.index,
              )
              .toList();
    if (channels.isEmpty && channelFilter != null && !channelFilter.isEmpty) {
      channels.add(channelFilter);
    }
    if (channels.isEmpty) return const [];
    final channelGroups = _channelStorageGroups(channels);
    final result = <_MessageSearchSourceDescriptor>[];

    final currentStore = ChannelMessageStore()..setPublicKeyHex = currentScope;
    currentStore.replaceChannels(channels);
    for (final candidates in channelGroups) {
      if (generation != _generation) return result;
      final channel = _preferredChannel(connector, candidates);
      final source = await _loadChannelSource(
        store: currentStore,
        channel: channel,
        channelCandidates: candidates,
        channelIndex: channel.index,
        scope: currentScope,
        includeLegacyIndexFallback: true,
      );
      if (source != null) result.add(source);
    }

    if (!settings.sharedMessageHistoryMode.includesChannels) return result;

    final secondaryScopes = SharedMessageHistoryHelper.knownScopes().toList()
      ..sort();
    for (final scope in secondaryScopes) {
      if (generation != _generation) return result;
      if (scope == currentScope) continue;
      final channelStore = ChannelStore()..setPublicKeyHex = scope;
      final secondaryChannels = await channelStore.loadChannels();
      if (secondaryChannels.isEmpty) continue;
      final messageStore = ChannelMessageStore()..setPublicKeyHex = scope;
      messageStore.replaceChannels(secondaryChannels);

      for (final candidates in channelGroups) {
        final channel = _preferredChannel(connector, candidates);
        final matchedIndex = ChannelIdentityMatcher.findMatchingChannelIndex(
          secondaryChannels,
          name: channel.name,
          pskHex: channel.pskHex,
        );
        if (matchedIndex == null) continue;
        final source = await _loadChannelSource(
          store: messageStore,
          channel: channel,
          channelCandidates: candidates,
          channelIndex: matchedIndex,
          scope: scope,
        );
        if (source != null) result.add(source);
      }
    }
    return result;
  }

  Future<_MessageSearchSourceDescriptor?> _loadChannelSource({
    required ChannelMessageStore store,
    required Channel channel,
    required List<Channel> channelCandidates,
    required int channelIndex,
    required String scope,
    bool includeLegacyIndexFallback = false,
  }) async {
    final jsonString = await store.loadChannelMessagesJsonForSearch(
      channelIndex,
      includeLegacyIndexFallback: includeLegacyIndexFallback,
    );
    if (jsonString == null) return null;
    return _MessageSearchSourceDescriptor(
      workerSource: StoredMessageSearchSource(
        sourceId: 'channel|$scope|${channel.name.trim()}',
        jsonString: jsonString,
        type: StoredMessageSearchType.channel,
      ),
      type: MessageSearchEntryType.channel,
      channel: channel,
      channelCandidates: channelCandidates,
    );
  }

  List<List<Channel>> _channelStorageGroups(Iterable<Channel> channels) {
    final groups = <String, List<Channel>>{};
    for (final channel in channels) {
      final storageName = channel.name.trim();
      if (storageName.isEmpty) continue;
      groups.putIfAbsent(storageName, () => <Channel>[]).add(channel);
    }
    return groups.values.toList();
  }

  Channel _preferredChannel(
    MeshCoreConnector connector,
    List<Channel> candidates,
  ) {
    var preferred = candidates.first;
    var preferredCount = _loadedChannelMessageCount(connector, preferred);
    for (final candidate in candidates.skip(1)) {
      final count = _loadedChannelMessageCount(connector, candidate);
      if (count > preferredCount) {
        preferred = candidate;
        preferredCount = count;
      }
    }
    return preferred;
  }

  int _loadedChannelMessageCount(MeshCoreConnector connector, Channel channel) {
    return connector.getLoadedChannelMessages(channel).length +
        connector.getPendingChannelMessages(channel.index).length;
  }

  ({Channel channel, String messageId})? _channelTargetForSearchHit(
    MeshCoreConnector connector,
    _MessageSearchSourceDescriptor descriptor,
    StoredMessageSearchHit hit,
  ) {
    final candidates = descriptor.channelCandidates;
    if (candidates.isEmpty) {
      final channel = descriptor.channel;
      return channel == null
          ? null
          : (channel: channel, messageId: hit.messageId);
    }

    for (final channel in candidates) {
      final hasLocalMessage =
          connector
              .getLoadedChannelMessages(channel)
              .any((message) => message.messageId == hit.messageId) ||
          connector
              .getPendingChannelMessages(channel.index)
              .any((message) => message.messageId == hit.messageId);
      if (hasLocalMessage) {
        return (channel: channel, messageId: hit.messageId);
      }
    }
    for (final channel in candidates) {
      final messages = connector.getChannelMessages(channel);
      if (messages.any((message) => message.messageId == hit.messageId)) {
        return (channel: channel, messageId: hit.messageId);
      }
      for (final message in messages) {
        if (message.senderName.trim().toLowerCase() !=
                hit.senderName.trim().toLowerCase() ||
            message.text != hit.text ||
            _channelHourKey(message.timestamp.millisecondsSinceEpoch) !=
                _channelHourKey(hit.identityTimestampMs)) {
          continue;
        }
        return (channel: channel, messageId: message.messageId);
      }
    }
    return (
      channel: _preferredChannel(connector, candidates),
      messageId: hit.messageId,
    );
  }

  Future<List<_MessageSearchSourceDescriptor>> _collectContactSources({
    required MeshCoreConnector connector,
    required AppSettings settings,
    required bool includeContacts,
    required bool includeRooms,
    required int generation,
    Contact? contactFilter,
  }) async {
    final currentScope = SharedMessageHistoryHelper.scopeFor(
      connector.selfPublicKeyHex,
    );
    if (currentScope.isEmpty) return const [];
    final contactCandidates = contactFilter == null
        ? connector.contacts
        : connector.contacts
              .where(
                (contact) => contact.publicKeyHex == contactFilter.publicKeyHex,
              )
              .toList();
    if (contactCandidates.isEmpty && contactFilter != null) {
      contactCandidates.add(contactFilter);
    }
    final contacts = _searchableContacts(
      contactCandidates,
      includeContacts: includeContacts,
      includeRooms: includeRooms,
    );
    if (contacts.isEmpty) return const [];
    final result = <_MessageSearchSourceDescriptor>[];

    final currentStore = MessageStore()..setPublicKeyHex = currentScope;
    for (final contact in contacts) {
      if (generation != _generation) return result;
      final source = await _loadContactSource(
        store: currentStore,
        contact: contact,
        scope: currentScope,
        includeLegacyUnscoped: true,
      );
      if (source != null) result.add(source);
    }

    if (!settings.sharedMessageHistoryMode.includesContacts) return result;

    final secondaryScopes = SharedMessageHistoryHelper.knownScopes().toList()
      ..sort();
    for (final scope in secondaryScopes) {
      if (generation != _generation) return result;
      if (scope == currentScope) continue;
      final store = MessageStore()..setPublicKeyHex = scope;
      for (final contact in contacts) {
        if (contact.type == advTypeRoom) continue;
        final source = await _loadContactSource(
          store: store,
          contact: contact,
          scope: scope,
        );
        if (source != null) result.add(source);
      }
    }
    return result;
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

  Future<_MessageSearchSourceDescriptor?> _loadContactSource({
    required MessageStore store,
    required Contact contact,
    required String scope,
    bool includeLegacyUnscoped = false,
  }) async {
    final jsonString = await store.loadMessagesJsonForSearch(
      contact.publicKeyHex,
      includeLegacyUnscoped: includeLegacyUnscoped,
    );
    if (jsonString == null) return null;
    final resultType = contact.type == advTypeRoom
        ? MessageSearchEntryType.room
        : MessageSearchEntryType.contact;
    return _MessageSearchSourceDescriptor(
      workerSource: StoredMessageSearchSource(
        sourceId: 'peer|$scope|${contact.publicKeyHex}|${resultType.name}',
        jsonString: jsonString,
        type: contact.type == advTypeRoom
            ? StoredMessageSearchType.room
            : StoredMessageSearchType.contact,
        contactName: contact.name,
      ),
      type: resultType,
      contact: contact,
    );
  }

  Iterable<List<_MessageSearchSourceDescriptor>> _workerBatches(
    Iterable<_MessageSearchSourceDescriptor> sources,
  ) sync* {
    var batch = <_MessageSearchSourceDescriptor>[];
    var jsonChars = 0;
    for (final source in sources) {
      final sourceChars = source.workerSource.jsonString.length;
      if (batch.isNotEmpty &&
          (batch.length >= _maxWorkerSources ||
              jsonChars + sourceChars > _maxWorkerJsonChars)) {
        yield batch;
        batch = <_MessageSearchSourceDescriptor>[];
        jsonChars = 0;
      }
      batch.add(source);
      jsonChars += sourceChars;
    }
    if (batch.isNotEmpty) yield batch;
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

  Map<String, String> _roomSenderNamesByPrefix(MeshCoreConnector connector) {
    final result = <String, String>{};
    for (final contact in connector.allContactsUnfiltered) {
      if (contact.publicKey.length < 4) continue;
      result.putIfAbsent(hexPrefix(contact.publicKey, 4), () => contact.name);
    }
    return result;
  }

  String _resultDedupeKey(
    _MessageSearchSourceDescriptor descriptor,
    StoredMessageSearchHit hit,
  ) {
    final channelTimeKey = descriptor.type == MessageSearchEntryType.channel
        ? _channelHourKey(hit.identityTimestampMs)
        : hit.identityTimestampMs.toString();
    final conversationKey = switch (descriptor.type) {
      MessageSearchEntryType.channel =>
        '${descriptor.channel?.name.trim().toLowerCase() ?? ''}|'
            '${descriptor.channel?.pskHex.toLowerCase() ?? ''}',
      MessageSearchEntryType.room =>
        descriptor.contact?.publicKeyHex.toLowerCase() ?? '',
      MessageSearchEntryType.contact =>
        descriptor.contact?.publicKeyHex.toLowerCase() ?? '',
    };
    return [
      descriptor.type.name,
      conversationKey,
      channelTimeKey,
      hit.senderName.trim().toLowerCase(),
      hit.text,
    ].join('\u001f');
  }

  String _channelHourKey(int timestampMs) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    return '${timestamp.year.toString().padLeft(4, '0')}-'
        '${timestamp.month.toString().padLeft(2, '0')}-'
        '${timestamp.day.toString().padLeft(2, '0')}-'
        '${timestamp.hour.toString().padLeft(2, '0')}';
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
            top: 16,
            bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.chat_searchMessages,
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
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: context.l10n.chat_searchMessages_placeholder,
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
              ),
              const SizedBox(height: 8),
              if (_hasSearched)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    context.l10n.chat_searchMessages_results_found(
                      _results.length,
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: !_hasSearched
                    ? Center(
                        child: Text(context.l10n.chat_searchMessages_results),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _results.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 4, endIndent: 4),
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
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
        return context.l10n.chat_searchMessages_results_channel(
          result.channel?.name ?? '',
        );
      case MessageSearchEntryType.room:
        return context.l10n.chat_searchMessages_results_room(
          result.contact?.name ?? '',
        );
      case MessageSearchEntryType.contact:
        return context.l10n.chat_searchMessages_results_contact(
          result.contact?.name ?? '',
        );
    }
  }
}

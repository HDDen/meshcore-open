import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../utils/platform_info.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../config/build_features.dart';
import '../helpers/channel_binary_data_helper.dart';
import '../helpers/chat_keyboard_navigation_history.dart';
import '../helpers/contact_share_helper.dart';
import '../helpers/cyr2lat.dart';
import '../helpers/reaction_helper.dart';
import '../helpers/shared_marker_deletions.dart';
import '../helpers/inserted_text_limiter.dart';
import '../helpers/offline_mode_helper.dart';
import '../widgets/markup_text_editing_controller.dart';
import '../widgets/mention_suggestions_panel.dart';
import '../helpers/blocked_senders.dart';
import '../widgets/blocked_message_body.dart';
import '../widgets/message_status_icon.dart';
import '../helpers/chat_scroll_controller.dart';
import '../helpers/gif_helper.dart';
import '../helpers/mco_image_file_saver.dart';
import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_v3_codec.dart';
import '../helpers/mention_autocomplete.dart';
import '../helpers/path_helper.dart';
import '../helpers/quick_answers_helper.dart';
import '../models/channel_message.dart';
import '../models/contact.dart';
import '../l10n/contact_localization.dart';
import '../models/message.dart';
import '../models/message_compression.dart';
import '../models/mco_image_gallery_item.dart';
import '../models/translation_support.dart';
import '../services/app_settings_service.dart';
import '../services/chat_text_scale_service.dart';
import '../services/mco_image_pack_originals.dart';
import '../services/translation_service.dart';
import '../widgets/chat_zoom_wrapper.dart';
import '../widgets/chat_additional_actions_menu.dart';
import '../widgets/composer_text_builder.dart';
import '../widgets/byte_count_input.dart';
import '../widgets/popup_menu_row.dart';
import 'canvas_editor_screen.dart';
import 'channel_message_path_screen.dart';
import 'contacts_screen.dart';
import 'map_screen.dart';
import '../utils/emoji_utils.dart';
import '../widgets/emoji_picker.dart';
import '../widgets/gif_message.dart';
import '../widgets/jump_to_bottom_button.dart';
import '../widgets/gif_picker.dart';
import '../widgets/mco_image_message.dart';
import '../widgets/mco_image_original.dart';
import '../widgets/mcmp_signature_badge.dart';
import '../widgets/message_translation_button.dart';
import '../widgets/message_search_sheet.dart';
import '../widgets/quick_answers_selection_dialog.dart';
import '../widgets/quick_answers_picker_dialog.dart';
import '../widgets/radio_stats_entry.dart';
import '../storage/mco_image_gallery_store.dart';
import 'mco_image_gallery_screen.dart';
import '../widgets/routing_sheet.dart';
import '../widgets/shared_contact_message.dart';
import '../widgets/sync_progress_overlay.dart';
import '../widgets/translated_message_content.dart';
import '../l10n/l10n.dart';
import '../helpers/snack_bar_builder.dart';
import '../widgets/unread_divider.dart';
import '../theme/mesh_theme.dart';
import 'telemetry_screen.dart';
import '../widgets/pending_send_cancel_bar.dart';

class ChatScreen extends StatefulWidget {
  final Contact contact;
  final int initialUnreadCount;
  final String? initialMessageId;

  const ChatScreen({
    super.key,
    required this.contact,
    this.initialUnreadCount = 0,
    this.initialMessageId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = MarkupTextEditingController();
  final _scrollController = ChatScrollController();
  final _textFieldFocusNode = FocusNode();
  final _screenFocusNode = FocusNode();
  final GlobalKey _unreadScrollKey = GlobalKey();
  final Map<String, GlobalKey> _messageKeys = {};
  bool _keyboardNavigationActive = true;
  bool _ignoreNextTextFieldFocus = false;
  String _lastTextFieldText = '';
  bool _isLoadingOlder = false;
  MeshCoreConnector? _connector;
  StreamSubscription<void>? _mcmpSigningFailedSubscription;
  Message? _pendingUnreadScrollTarget;
  String? _unreadDividerMessageId;
  DateTime? _lastTextSendAt;
  String? _highlightedMessageId;
  int _highlightSequence = 0;
  int _messageScrollGeneration = 0;
  List<Contact> _mentionSuggestions = const [];
  MentionQuery? _mentionQuery;

  /// Message ids whose MCOimg variant the user flipped away from the default
  /// (the default is "show pack original" when the mod setting is enabled,
  /// otherwise "show received LoRa version").
  final Set<String> _mcoVariantOverridden = {};

  /// Blocked bodies the user tapped to read. Display only — a revealed body is
  /// still never parsed — and forgotten whenever the block table changes, so a
  /// re-blocked author starts hidden again.
  final Set<String> _revealedBlockedMessages = {};

  /// Effective "render the received LoRa version" flag for a message,
  /// combining the mod setting default with the per-message override.
  bool _mcoForceLora(String messageId, bool showReplacements) {
    final defaultLora = !showReplacements;
    final overridden = _mcoVariantOverridden.contains(messageId);
    return defaultLora != overridden;
  }

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextFieldTextChange);
    _textController.addListener(_updateMentionSuggestions);
    _textFieldFocusNode.addListener(_onTextFieldFocusChange);
    _textFieldFocusNode.addListener(_updateMentionSuggestions);
    BlockedSenders.instance.addListener(_handleBlockedSendersChanged);
    if (PlatformInfo.isDesktop) {
      HardwareKeyboard.instance.addHandler(_handleDesktopKeyEvent);
    }
    _scrollController.onScrollNearTop = _loadOlderMessages;
    _scrollController.showJumpToBottom.addListener(_clearDividerAtBottom);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final connector = context.read<MeshCoreConnector>();
      final settings = context.read<AppSettingsService>().settings;
      final keyHex = widget.contact.publicKeyHex;
      final unread = widget.initialUnreadCount;
      final messages = connector.getMessages(widget.contact);
      final initialMessageId = widget.initialMessageId;
      Message? anchor;
      if (unread > 0) {
        anchor = _findOldestUnreadAnchor(messages, unread);
      }
      setState(() {
        if (anchor != null) _unreadDividerMessageId = anchor.messageId;
        if (initialMessageId == null &&
            anchor != null &&
            settings.jumpToOldestUnread) {
          _pendingUnreadScrollTarget = anchor;
        }
      });
      connector.setActiveContact(keyHex);
      _connector = connector;
      _mcmpSigningFailedSubscription = connector.mcmpSigningFailures.listen(
        (_) => _showMcmpSigningFailed(),
      );
      if (PlatformInfo.isDesktop && !connector.isOfflineMode) {
        _ignoreNextTextFieldFocus = true;
        _textFieldFocusNode.requestFocus();
        _keyboardNavigationActive = true;
      }
      if (initialMessageId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToMessage(
            initialMessageId,
            animate: false,
            stabilize: true,
            highlightOnSuccess: true,
          );
        });
      } else if (anchor != null && settings.jumpToOldestUnread) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollController.jumpToEstimatedOffset(
            unreadCount: unread,
            totalMessages: messages.length,
            onJumped: () async {
              if (!mounted) return;
              final ctx = _unreadScrollKey.currentContext;
              if (ctx != null) {
                await Scrollable.ensureVisible(
                  ctx,
                  duration: const Duration(milliseconds: 350),
                  alignment: 0.15,
                );
              }
              if (mounted) {
                setState(() => _pendingUnreadScrollTarget = null);
              }
            },
          );
        });
      }
    });
  }

  BuildContext? _tryGetMessageContext(String messageId) {
    final key = _messageKeys[messageId];
    return key?.currentContext;
  }

  List<Message> _messagesForDisplay(MeshCoreConnector connector) {
    return [
      ...connector.getMessages(widget.contact),
      ...connector.getPendingContactMessages(widget.contact.publicKeyHex),
    ];
  }

  Future<BuildContext?> _materializeMessageContext(String messageId) async {
    final connector = context.read<MeshCoreConnector>();
    var emptyOlderLoads = 0;
    var loadedTargetRetries = 0;

    while (mounted) {
      final targetContext = _tryGetMessageContext(messageId);
      if (targetContext != null && targetContext.mounted) {
        return targetContext;
      }

      final messages = _messagesForDisplay(connector);
      final targetIndex = messages.indexWhere(
        (message) => message.messageId == messageId,
      );
      if (targetIndex >= 0) {
        if (_scrollController.hasClients) {
          final targetOffset = messages.length > 1
              ? _scrollController.position.maxScrollExtent *
                    ((messages.length - 1 - targetIndex) /
                        (messages.length - 1))
              : 0.0;
          final materializedContext = await _probeMessageContextAroundOffset(
            messageId,
            targetOffset,
          );
          if (materializedContext != null && materializedContext.mounted) {
            return materializedContext;
          }
        }
        if (loadedTargetRetries < 2) {
          loadedTargetRetries++;
          await Future<void>.delayed(const Duration(milliseconds: 150));
          await WidgetsBinding.instance.endOfFrame;
          continue;
        }
        // The message is already loaded, so loading older history cannot make
        // it materialize.
        return null;
      }
      loadedTargetRetries = 0;

      final olderMessages = await connector.loadOlderMessages(
        widget.contact.publicKeyHex,
      );
      if (olderMessages.isEmpty) {
        if (emptyOlderLoads < 5) {
          emptyOlderLoads++;
          await Future<void>.delayed(const Duration(milliseconds: 150));
          await WidgetsBinding.instance.endOfFrame;
          continue;
        }
        return null;
      }
      emptyOlderLoads = 0;
      await WidgetsBinding.instance.endOfFrame;
    }

    return null;
  }

  // Keep in sync with ChannelChatScreen._probeMessageContextAroundOffset.
  Future<BuildContext?> _probeMessageContextAroundOffset(
    String messageId,
    double estimatedOffset,
  ) async {
    if (!_scrollController.hasClients) return null;
    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    final offsetsInViewports = <double>[
      0,
      -0.75,
      0.75,
      -1.5,
      1.5,
      -2.5,
      2.5,
      -4,
      4,
    ];
    for (final multiplier in offsetsInViewports) {
      if (!mounted || !_scrollController.hasClients) return null;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final offset = (estimatedOffset + viewport * multiplier).clamp(
        0.0,
        maxExtent,
      );
      _scrollController.jumpTo(offset);
      await WidgetsBinding.instance.endOfFrame;
      final context = _tryGetMessageContext(messageId);
      if (context != null && context.mounted) return context;
    }
    return null;
  }

  Future<bool> _scrollToMessage(
    String messageId, {
    bool animate = true,
    bool stabilize = false,
    bool highlightOnSuccess = false,
  }) async {
    final scrollGeneration = ++_messageScrollGeneration;
    final targetContext = await _materializeMessageContext(messageId);

    if (!mounted || scrollGeneration != _messageScrollGeneration) return false;

    if (targetContext == null) {
      return false;
    }

    if (!targetContext.mounted) {
      return false;
    }

    await _ensureMessageVisible(
      messageId,
      initialContext: targetContext,
      animate: animate,
      stabilize: stabilize,
      scrollGeneration: scrollGeneration,
      onInitialPositioned: highlightOnSuccess
          ? () => _highlightMessage(messageId)
          : null,
    );
    return true;
  }

  Future<void> _showMessageSearch() {
    final connector = context.read<MeshCoreConnector>();
    return MessageSearchSheet.show(
      context,
      scope: MessageSearchScope.contacts,
      contactFilter: _resolveContact(connector),
      onOpenResult: (result) async {
        if (!mounted || result.type == MessageSearchEntryType.channel) return;
        Navigator.of(context).pop();
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        await _scrollToMessage(
          result.messageId,
          highlightOnSuccess: true,
          animate: false,
          stabilize: true,
        );
      },
    );
  }

  // Keep in sync with ChannelChatScreen._ensureMessageVisible.
  Future<void> _ensureMessageVisible(
    String messageId, {
    required BuildContext initialContext,
    required bool animate,
    required bool stabilize,
    required int scrollGeneration,
    VoidCallback? onInitialPositioned,
  }) async {
    await Scrollable.ensureVisible(
      initialContext,
      duration: animate ? const Duration(milliseconds: 300) : Duration.zero,
      curve: Curves.easeInOut,
      alignment: 0.3,
    );
    await WidgetsBinding.instance.endOfFrame;
    onInitialPositioned?.call();
    if (!stabilize) return;

    const checks = [
      Duration(milliseconds: 100),
      Duration(milliseconds: 250),
      Duration(milliseconds: 500),
      Duration(milliseconds: 1000),
    ];
    for (final delay in checks) {
      await Future<void>.delayed(delay);
      if (!mounted || scrollGeneration != _messageScrollGeneration) return;
      await WidgetsBinding.instance.endOfFrame;
      if (scrollGeneration != _messageScrollGeneration) return;
      var context = _tryGetMessageContext(messageId);
      if (context == null || !context.mounted) {
        context = await _materializeMessageContext(messageId);
      }
      if (context == null ||
          !context.mounted ||
          !mounted ||
          scrollGeneration != _messageScrollGeneration) {
        return;
      }
      await Scrollable.ensureVisible(
        context,
        duration: Duration.zero,
        alignment: 0.3,
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  void _cancelMessageScrollStabilization() {
    _messageScrollGeneration++;
  }

  void _highlightMessage(String messageId) {
    final sequence = ++_highlightSequence;
    if (mounted) {
      setState(() {
        _highlightedMessageId = messageId;
      });
    }

    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 1000)).then((_) {
        if (!mounted || _highlightSequence != sequence) return;
        setState(() {
          if (_highlightedMessageId == messageId) {
            _highlightedMessageId = null;
          }
        });
      }),
    );
  }

  Message? _findOldestUnreadAnchor(List<Message> messages, int unreadCount) {
    if (unreadCount <= 0 || messages.isEmpty) return null;
    var n = 0;
    Message? oldest;
    for (final m in messages.reversed) {
      if (m.isOutgoing || m.isCli) continue;
      n++;
      oldest = m;
      if (n >= unreadCount) break;
    }
    return oldest;
  }

  void _clearDividerAtBottom() {
    if (!_scrollController.showJumpToBottom.value &&
        _unreadDividerMessageId != null) {
      setState(() => _unreadDividerMessageId = null);
    }
  }

  void _onTextFieldFocusChange() {
    if (!_textFieldFocusNode.hasFocus) {
      _keyboardNavigationActive = true;
      _ignoreNextTextFieldFocus = false;
      return;
    }
    if (_ignoreNextTextFieldFocus) {
      _ignoreNextTextFieldFocus = false;
    } else {
      _keyboardNavigationActive = false;
    }
    if (mounted) {
      _scrollController.handleKeyboardOpen();
    }
  }

  /// Keeps the mention picker in sync with the caret. Room servers relay to a
  /// crowd, so naming who a message is for makes sense there; a one-to-one
  /// conversation has nobody to disambiguate, and the picker stays away.
  void _updateMentionSuggestions() {
    if (!mounted) return;
    final connector = context.read<MeshCoreConnector>();
    final query =
        _textFieldFocusNode.hasFocus &&
            _resolveContact(connector).type == advTypeRoom
        ? MentionAutocomplete.queryAt(_textController.value)
        : null;
    final suggestions = query == null
        ? const <Contact>[]
        : MentionAutocomplete.suggestionsFor(connector.contacts, query.filter);
    // Remember where the mention sits even when the list itself did not
    // change: one more typed letter moves its end, and the picker replaces
    // exactly that range.
    _mentionQuery = suggestions.isEmpty ? null : query;
    if (_sameContacts(suggestions, _mentionSuggestions)) return;
    setState(() => _mentionSuggestions = suggestions);
  }

  bool _sameContacts(List<Contact> a, List<Contact> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].publicKeyHex != b[i].publicKeyHex) return false;
    }
    return true;
  }

  /// Uses the remembered range rather than re-reading the caret: by the time a
  /// row is picked the composer may already have lost focus, and with it the
  /// selection this would be derived from.
  void _applyMentionSuggestion(Contact contact) {
    final query = _mentionQuery;
    final value = _textController.value;
    if (query == null || query.end > value.text.length) return;
    _mentionQuery = null;
    _textController.value = MentionAutocomplete.apply(
      value,
      query,
      contact.name,
    );
    _textFieldFocusNode.requestFocus();
  }

  void _onTextFieldTextChange() {
    final text = _textController.text;
    if (text == _lastTextFieldText) return;
    _lastTextFieldText = text;
    if (_textFieldFocusNode.hasFocus) {
      _keyboardNavigationActive = false;
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingOlder) return;
    setState(() => _isLoadingOlder = true);

    final connector = context.read<MeshCoreConnector>();
    await connector.loadOlderMessages(widget.contact.publicKeyHex);

    if (mounted) {
      setState(() => _isLoadingOlder = false);
    }
  }

  @override
  void dispose() {
    _connector?.setActiveContact(null);
    _mcmpSigningFailedSubscription?.cancel();
    if (PlatformInfo.isDesktop) {
      HardwareKeyboard.instance.removeHandler(_handleDesktopKeyEvent);
    }
    _scrollController.showJumpToBottom.removeListener(_clearDividerAtBottom);
    BlockedSenders.instance.removeListener(_handleBlockedSendersChanged);
    _textController.removeListener(_onTextFieldTextChange);
    _textController.removeListener(_updateMentionSuggestions);
    _textFieldFocusNode.removeListener(_onTextFieldFocusChange);
    _textFieldFocusNode.removeListener(_updateMentionSuggestions);
    _screenFocusNode.dispose();
    _textFieldFocusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showMcmpSigningFailed() {
    if (!mounted) return;
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.chat_mcmpSigningFailed),
      backgroundColor: Theme.of(context).colorScheme.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _screenFocusNode,
      autofocus: PlatformInfo.isDesktop,
      child: Scaffold(
        appBar: AppBar(
          title: Consumer<MeshCoreConnector>(
            builder: (context, connector, _) {
              final contact = _resolveContact(connector);
              final unreadCount = connector.getUnreadCountForContactKey(
                widget.contact.publicKeyHex,
              );
              final unreadLabel = context.l10n.chat_unread(unreadCount);
              final pathLabel = _currentPathLabel(contact);

              // Show path details if we have non-empty path data (from device or override)
              final effectivePath = contact.pathOverrideBytes ?? contact.path;
              final hasPathData = effectivePath.isNotEmpty;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(contact.name),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        ContactRoutingSheet.show(context, contact: contact),
                    child: Text(
                      '$pathLabel • $unreadLabel',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.normal,
                        decoration: hasPathData
                            ? TextDecoration.underline
                            : null,
                        decorationStyle: TextDecorationStyle.dotted,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          centerTitle: false,
          bottom: const SyncProgressAppBarBottom(),
          actions: [
            Consumer<MeshCoreConnector>(
              builder: (context, connector, _) {
                final contact = _resolveContact(connector);
                final isFloodMode = contact.pathOverride == -1;
                return IconButton(
                  icon: Icon(isFloodMode ? Icons.waves : Icons.route),
                  tooltip: context.l10n.repeater_routingMode,
                  onPressed: () =>
                      ContactRoutingSheet.show(context, contact: contact),
                );
              },
            ),
            const RadioStatsIconButton(),
            Consumer<MeshCoreConnector>(
              builder: (context, connector, _) {
                return PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    switch (value) {
                      case 'searchMessages':
                        unawaited(_showMessageSearch());
                      case 'info':
                        _showContactInfo(context);
                      case 'settings':
                        _showContactSettings(context);
                      case 'telemetry':
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                TelemetryScreen(contact: widget.contact),
                          ),
                        );
                      case 'clearChat':
                        _confirmClearChat(context, connector);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'searchMessages',
                      child: PopupMenuRow(
                        icon: Icons.search,
                        text: context.l10n.chat_searchMessages,
                      ),
                    ),
                    if (!connector.isOfflineMode)
                      PopupMenuItem(
                        value: 'info',
                        child: PopupMenuRow(
                          icon: Icons.info_outline,
                          text: context.l10n.contact_info,
                        ),
                      ),
                    if (!connector.isOfflineMode)
                      PopupMenuItem(
                        value: 'telemetry',
                        child: PopupMenuRow(
                          icon: Icons.bar_chart,
                          text: context.l10n.contact_telemetry,
                        ),
                      ),
                    if (!connector.isOfflineMode)
                      PopupMenuItem(
                        value: 'settings',
                        child: PopupMenuRow(
                          icon: Icons.settings,
                          text: context.l10n.contact_settings,
                        ),
                      ),
                    if (!connector.isOfflineMode)
                      PopupMenuItem(
                        value: 'clearChat',
                        child: PopupMenuRow(
                          icon: Icons.delete,
                          iconColor: Colors.red,
                          text: context.l10n.contact_clearChat,
                          textStyle: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        body: Consumer<MeshCoreConnector>(
          builder: (context, connector, child) {
            final messages = _messagesForDisplay(connector);
            return Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      messages.isEmpty
                          ? _buildEmptyState()
                          : _buildMessageList(messages, connector),
                      JumpToBottomButton(scrollController: _scrollController),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  alignment: Alignment.bottomCenter,
                  child: _mentionSuggestions.isEmpty
                      ? const SizedBox(width: double.infinity)
                      : MentionSuggestionsPanel(
                          contacts: _mentionSuggestions,
                          onSelected: _applyMentionSuggestion,
                        ),
                ),
                _buildInputBar(connector),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _handleDesktopKeyEvent(KeyEvent event) {
    if (!PlatformInfo.isDesktop) {
      return false;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    if ((PlatformInfo.isWindows || PlatformInfo.isLinux) &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isControlPressed) {
      unawaited(_showMessageSearch());
      return true;
    }
    final isNavigationKeyDown = event is KeyDownEvent;
    final isScrollKeyEvent = event is KeyDownEvent || event is KeyRepeatEvent;
    if (!isNavigationKeyDown && !isScrollKeyEvent) {
      return false;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        unawaited(_handleEscapeNavigation());
        return true;
      case LogicalKeyboardKey.arrowLeft:
        if (!isNavigationKeyDown || !_keyboardNavigationActive) return false;
        unawaited(_handleEscapeNavigation());
        return true;
      case LogicalKeyboardKey.pageUp:
        if (!isScrollKeyEvent) return false;
        return _scrollMessagesByPage(1);
      case LogicalKeyboardKey.pageDown:
        if (!isScrollKeyEvent) return false;
        return _scrollMessagesByPage(-1);
      case LogicalKeyboardKey.arrowUp:
        if (!isScrollKeyEvent || !_keyboardNavigationActive) return false;
        return _scrollMessagesByLine(1);
      case LogicalKeyboardKey.arrowDown:
        if (!isScrollKeyEvent || !_keyboardNavigationActive) return false;
        return _scrollMessagesByLine(-1);
    }
    return false;
  }

  bool _scrollMessagesByPage(int direction) {
    if (!_scrollController.hasClients) return false;
    _cancelMessageScrollStabilization();
    return _scrollController.scrollBy(
      _scrollController.position.viewportDimension * 0.85 * direction,
    );
  }

  bool _scrollMessagesByLine(int direction) {
    _cancelMessageScrollStabilization();
    return _scrollController.scrollBy(72.0 * direction);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            context.l10n.chat_noMessages,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.chat_sendMessageTo(
              _resolveContact(context.read<MeshCoreConnector>()).name,
            ),
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(
    List<Message> messages,
    MeshCoreConnector connector,
  ) {
    // Reverse messages so newest appear at bottom with reverse: true
    final reversedMessages = messages.reversed.toList();
    final itemCount = reversedMessages.length + (_isLoadingOlder ? 1 : 0);
    final liveIds = reversedMessages
        .map((message) => message.messageId)
        .toSet();
    _messageKeys.removeWhere((id, _) => !liveIds.contains(id));
    final keyedIndices = <int>{};
    final duplicateKeys = <int, ValueKey<String>>{};
    final occurrencesById = <String, int>{};
    for (var i = 0; i < reversedMessages.length; i++) {
      final messageId = reversedMessages[i].messageId;
      final occurrence = occurrencesById[messageId] ?? 0;
      occurrencesById[messageId] = occurrence + 1;
      if (occurrence == 0) {
        keyedIndices.add(i);
      } else {
        duplicateKeys[i] = ValueKey('$messageId#$occurrence');
      }
    }

    // Auto-scroll to bottom if user is already at bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pendingUnreadScrollTarget != null) return;
      _scrollController.scrollToBottomIfAtBottom();
    });

    return JumpToBottomReservedPadding(
      scrollController: _scrollController,
      basePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      builder: (context, padding, bottomReservedExtent) {
        final hasBottomSpacer = bottomReservedExtent > 0;
        final spacerItemCount = hasBottomSpacer ? 1 : 0;
        return Listener(
          onPointerDown: (_) => _cancelMessageScrollStabilization(),
          onPointerSignal: (_) => _cancelMessageScrollStabilization(),
          child: ChatZoomWrapper(
            child: ListView.builder(
              reverse: true, // List grows from bottom up
              controller: _scrollController,
              padding: padding,
              itemCount: itemCount + spacerItemCount,
              itemBuilder: (context, index) {
                if (hasBottomSpacer && index == 0) {
                  return SizedBox(height: bottomReservedExtent);
                }
                final adjustedIndex = index - spacerItemCount;

                // Loading indicator now appears at end (bottom) of reversed list
                if (_isLoadingOlder && adjustedIndex == itemCount - 1) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final messageIndex = adjustedIndex;
                Contact contact = _resolveContact(connector);
                final message = reversedMessages[messageIndex];
                final Key messageKey = keyedIndices.contains(messageIndex)
                    ? _messageKeys.putIfAbsent(message.messageId, GlobalKey.new)
                    : duplicateKeys[messageIndex]!;
                String fourByteHex = '';
                if (contact.type == advTypeRoom) {
                  // Room-server messages carry the original author's 4-byte prefix
                  // separately from message.text; use it only for resolving the name.
                  contact =
                      _resolveContactFrom4Bytes(
                        connector,
                        message.fourByteRoomContactKey.isEmpty
                            ? Uint8List.fromList([0, 0, 0, 0])
                            : message.fourByteRoomContactKey,
                      ) ??
                      contact;
                  fourByteHex = message.fourByteRoomContactKey
                      .map((b) => b.toRadixString(16).padLeft(2, '0'))
                      .join()
                      .toUpperCase();
                }

                return Builder(
                  builder: (context) {
                    final textScale = context
                        .select<ChatTextScaleService, double>(
                          (service) => service.scale,
                        );
                    final resolvedContact = _resolveContact(connector);
                    final bubble = _MessageBubble(
                      message: message,
                      isHighlighted: _highlightedMessageId == message.messageId,
                      senderName: resolvedContact.type == advTypeRoom
                          ? "${contact.name} [$fourByteHex]"
                          : contact.name,
                      sourceId: widget.contact.publicKeyHex,
                      isRoomChat: resolvedContact.type == advTypeRoom,
                      mcoVariantOverridden: _mcoVariantOverridden.contains(
                        message.messageId,
                      ),
                      blockedRevealed: _revealedBlockedMessages.contains(
                        message.messageId,
                      ),
                      onToggleBlocked: () => setState(() {
                        if (!_revealedBlockedMessages.remove(
                          message.messageId,
                        )) {
                          _revealedBlockedMessages.add(message.messageId);
                        }
                      }),
                      textScale: textScale,
                      onTap: () => _openMessagePath(message, contact),
                      onLongPress: () =>
                          unawaited(_showMessageActions(message, contact)),
                      onRetryReaction: (msg, emoji) =>
                          _sendReaction(msg, contact, emoji),
                      onAddSharedContact: _addSharedContact,
                      pendingSendAt: connector.pendingContactSendAt(
                        message.messageId,
                      ),
                      pendingSendDelaySeconds: connector
                          .pendingContactSendDelaySeconds(message.messageId),
                      onCancelPendingSend: () => _cancelPendingContactSend(
                        connector,
                        message.messageId,
                      ),
                    );
                    final isUnreadAnchor =
                        _unreadDividerMessageId != null &&
                        message.messageId == _unreadDividerMessageId;
                    final child = isUnreadAnchor
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [const UnreadDivider(), bubble],
                          )
                        : bubble;
                    if (identical(message, _pendingUnreadScrollTarget)) {
                      return KeyedSubtree(key: _unreadScrollKey, child: child);
                    }
                    return KeyedSubtree(key: messageKey, child: child);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleEscapeNavigation() async {
    ChatKeyboardNavigationHistory.rememberContact(widget.contact);
    final navigator = Navigator.of(context);
    final didPop = await navigator.maybePop();
    if (!mounted || didPop) return;
    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => const ContactsScreen(hideBackButton: true),
      ),
    );
  }

  void _markAsUnread(Message message) {
    final connector = context.read<MeshCoreConnector>();
    final messages = connector.getMessages(widget.contact);
    var count = 0;
    var found = false;
    for (final m in messages) {
      if (m.messageId == message.messageId) found = true;
      if (found && !m.isOutgoing && !m.isCli) count++;
    }
    connector.setContactUnreadCount(widget.contact.publicKeyHex, count);
  }

  /// Byte counting must match what actually goes on air, so the field and the
  /// colour palette share one encoder.
  String Function(String)? _composerEncoder(MeshCoreConnector connector) {
    final key = widget.contact.publicKeyHex;
    final usesEncoding =
        connector.isContactMcmpEnabled(key) ||
        connector.isContactSmazEnabled(key) ||
        connector.isContactCyr2LatEnabled(key);
    if (!usesEncoding) return null;
    return (text) =>
        connector.prepareContactOutboundText(widget.contact, text);
  }

  Widget _buildInputBar(MeshCoreConnector connector) {
    final maxBytes = _maxContactInputBytes(connector);
    final colorScheme = Theme.of(context).colorScheme;
    final settings = context.watch<AppSettingsService>().settings;
    final mediaQuery = MediaQuery.of(context);
    final maxInputHeight =
        (mediaQuery.size.height -
                mediaQuery.padding.top -
                kToolbarHeight -
                mediaQuery.viewInsets.bottom -
                48)
            .clamp(56.0, 240.0)
            .toDouble();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            ChatComposerSideAction(
              child: ChatAdditionalActionsButton(
                canvasActive: settings.canvasActive,
                offlineMode: connector.isOfflineMode,
                onSendSelfContact: () => _insertSelfContact(connector),
                onSendMyLocation: () => unawaited(_insertMyLocation(connector)),
                onSendContact: () => _pickAndInsertContact(),
                onPickLocationFromMap: () =>
                    unawaited(_pickAndInsertLocationFromMap()),
                onOpenQuickAnswers: () => _showQuickAnswersPicker(connector),
                onSendGif: () => _showGifPicker(context),
                onOpenCanvas: () => _showCanvasEditor(connector, maxBytes),
                onOpenMcoImageGallery: () =>
                    _showMcoImageGallery(connector, maxBytes),
              ),
            ),
            if (BuildFeatures.llmTranslationEnabled &&
                settings.translationEnabled)
              MessageTranslationButton(
                enabled: settings.composerTranslationEnabled,
                languageCode: settings.translationTargetLanguageCode,
                onPressed: _showTranslationOptions,
              ),
            Expanded(
              child: ComposerTextBuilder(
                controller: _textController,
                builder: (context, composerText) {
                  final gifId = GifHelper.parseGif(composerText);
                  if (gifId != null) {
                    return Focus(
                      autofocus: true,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent &&
                            (event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey ==
                                    LogicalKeyboardKey.numpadEnter)) {
                          _sendMessage(connector);
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: GifMessage(
                                url:
                                    'https://media.giphy.com/media/$gifId/giphy.gif',
                                backgroundColor:
                                    colorScheme.surfaceContainerHighest,
                                fallbackTextColor: colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                                maxSize: 160,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _textController.clear();
                              _textFieldFocusNode.requestFocus();
                            },
                          ),
                        ],
                      ),
                    );
                  }
                  return ByteCountedTextField(
                    maxBytes: maxBytes,
                    controller: _textController,
                    focusNode: _textFieldFocusNode,
                    enabled: !connector.isOfflineMode,
                    maxHeight: maxInputHeight,
                    hintText: context.l10n.chat_typeMessage,
                    onSubmitted: (_) => _sendMessage(connector),
                    extraFormatters:
                        connector.isContactMcmpEnabled(
                          widget.contact.publicKeyHex,
                        )
                        ? [
                            InsertedTextLimiter(
                              maxInsertedChars: settings.mcmpTextLimit,
                            ),
                          ]
                        : const [],
                    encoder: _composerEncoder(connector),
                    decoration: InputDecoration(
                      hintText: context.l10n.chat_typeMessage,
                      hintMaxLines: 1,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(MeshRadii.md),
                      ),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLow,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            ChatComposerSideAction(
              child: ChatComposerSendButton(
                tooltip: context.l10n.chat_sendMessage,
                semanticLabel: context.l10n.chat_sendMessageTo(
                  _resolveContact(connector).name,
                ),
                onLongPress: connector.isOfflineMode
                    ? null
                    : () => _showQuickAnswersPicker(connector),
                onPressed: connector.isOfflineMode
                    ? null
                    : () => _sendMessage(connector),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGifPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => GifPicker(
        onGifSelected: (gifId) {
          _textController.text = GifHelper.encodeGif(gifId);
        },
      ),
    );
  }

  void _insertTextIntoComposer(String text) {
    final value = _textController.value;
    final selection = value.selection;
    final range = selection.isValid
        ? selection
        : TextSelection.collapsed(offset: value.text.length);
    final nextText = value.text.replaceRange(range.start, range.end, text);
    final nextOffset = range.start + text.length;
    _textController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _textFieldFocusNode.requestFocus();
  }

  void _insertSelfContact(MeshCoreConnector connector) {
    final publicKey = connector.selfPublicKey;
    if (publicKey == null || publicKey.isEmpty) return;
    _insertTextIntoComposer(
      formatContactShareText(
        publicKey: publicKey,
        type: advTypeChat,
        name: connector.selfName ?? connector.deviceDisplayName,
      ),
    );
  }

  Future<void> _insertMyLocation(MeshCoreConnector connector) async {
    final location = await connector.refreshSelfLocation();
    if (!mounted || location == null) return;
    _insertTextIntoComposer(
      '${location.latitude.toStringAsFixed(6)},'
      '${location.longitude.toStringAsFixed(6)}',
    );
  }

  Future<void> _pickAndInsertLocationFromMap() async {
    final location = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (context) => const MapScreen(locationPickerMode: true),
      ),
    );
    if (!mounted || location == null) return;
    _insertTextIntoComposer(
      '${location.latitude.toStringAsFixed(6)},'
      '${location.longitude.toStringAsFixed(6)}',
    );
  }

  Future<void> _pickAndInsertContact() async {
    final contact = await Navigator.push<Contact>(
      context,
      MaterialPageRoute(
        builder: (_) => const ContactsScreen(selectionMode: true),
      ),
    );
    if (contact == null || !mounted) return;
    _insertTextIntoComposer(formatContactShareTextForContact(contact));
  }

  Future<void> _showCanvasEditor(
    MeshCoreConnector connector,
    int maxTextChars, {
    MCOImage? initialImage,
    Uint8List? initialImageBytes,
    int? initialImageWidth,
    int? initialImageHeight,
    PaletteProfile? initialPaletteProfile,
  }) async {
    final result = await Navigator.push<CanvasEditorResult>(
      context,
      MaterialPageRoute(
        builder: (context) => CanvasEditorScreen(
          maxTextChars: maxTextChars,
          initialImage: initialImage,
          initialImageBytes: initialImageBytes,
          initialImageWidth: initialImageWidth,
          initialImageHeight: initialImageHeight,
          initialPaletteProfile: initialPaletteProfile,
        ),
      ),
    );
    if (result == null || result.text.isEmpty) return;
    if (!mounted) return;
    final encodedText = result.text;
    _textController.text = encodedText;
    _textController.selection = TextSelection.collapsed(
      offset: encodedText.length,
    );
    await _sendMessage(connector, skipTranslation: true);
  }

  Future<void> _showMcoImageGallery(
    MeshCoreConnector connector,
    int maxTextChars,
  ) async {
    final result = await showModalBottomSheet<MCOImageGalleryResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const MCOImageGalleryScreen(),
    );
    if (result == null || !mounted) return;
    if (result.action == MCOImageGalleryAction.edit) {
      await _openGalleryItemInCanvas(connector, maxTextChars, result.item);
      return;
    }
    await _sendGalleryItem(connector, result.item);
  }

  Future<void> _openGalleryItemInCanvas(
    MeshCoreConnector connector,
    int maxTextChars,
    MCOImageGalleryItem item,
  ) async {
    final useRasterOriginal = item.showPngFallback && !item.originalIsLottie;
    final image = useRasterOriginal ? null : item.tryDecodeImage();
    await _showCanvasEditor(
      connector,
      maxTextChars,
      initialImage: image,
      initialImageBytes: image == null && !item.originalIsLottie
          ? item.pngBytes
          : null,
      initialImageWidth: item.width,
      initialImageHeight: item.height,
      initialPaletteProfile: item.paletteProfile,
    );
  }

  Future<void> _sendGalleryItem(
    MeshCoreConnector connector,
    MCOImageGalleryItem item,
  ) async {
    final text = item.textPayload;
    final outboundText = connector.prepareContactOutboundText(
      _resolveContact(connector),
      text,
    );
    final payloadBytes = utf8.encode(outboundText).length;
    final maxBytes = _maxContactInputBytes(connector);
    if (payloadBytes > maxBytes) {
      showDismissibleSnackBar(
        context,
        content: Text(
          context.l10n.chat_canvasCannotSend(payloadBytes - maxBytes),
        ),
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
      );
      return;
    }
    _textController.text = text;
    _textController.selection = TextSelection.collapsed(offset: text.length);
    await _sendMessage(connector, skipTranslation: true);
  }

  Future<void> _showQuickAnswersPicker(MeshCoreConnector connector) async {
    final selectedAnswerIds = await connector.loadContactQuickAnswerIds(
      widget.contact.publicKeyHex,
    );
    if (!mounted) return;
    final answer = await showQuickAnswersPickerDialog(
      context,
      answers: filterAvailableQuickAnswers(
        selectedAnswerIds: selectedAnswerIds,
        globalAnswers: context.read<AppSettingsService>().settings.quickAnswers,
      ),
    );
    if (answer == null) return;
    if (!mounted) return;
    if (answer.sendAtSelect) {
      await _sendMessage(connector, quickAnswerText: answer.text);
      return;
    }
    insertQuickAnswerIntoComposer(
      controller: _textController,
      focusNode: _textFieldFocusNode,
      text: answer.text,
    );
  }

  Future<void> _showTranslationOptions() async {
    final settingsService = context.read<AppSettingsService>();
    final settings = settingsService.settings;
    await showMessageTranslationSheet(
      context: context,
      enabled: settings.composerTranslationEnabled,
      selectedLanguageCode: settings.translationTargetLanguageCode,
      onEnabledChanged: settingsService.setComposerTranslationEnabled,
      onLanguageSelected: settingsService.setTranslationTargetLanguageCode,
    );
  }

  Future<void> _sendMessage(
    MeshCoreConnector connector, {
    String? quickAnswerText,
    bool skipTranslation = false,
  }) async {
    final rawText = quickAnswerText ?? _textController.text;
    final text = quickAnswerText == null ? rawText.trim() : rawText;
    if (text.trim().isEmpty) return;
    if (blockIfOffline(context, connector)) return;

    final now = DateTime.now();
    if (_lastTextSendAt != null &&
        now.difference(_lastTextSendAt!) < const Duration(seconds: 1)) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.chat_sendCooldown),
      );
      return;
    }
    _lastTextSendAt = now;

    final settings = context.read<AppSettingsService>().settings;
    final translationService = context.read<TranslationService>();
    var outgoingText = text;
    String? originalText;
    String? translatedLanguageCode;
    String? translationModelId;
    if (BuildFeatures.llmTranslationEnabled &&
        settings.translationEnabled &&
        !skipTranslation) {
      final targetLanguageCode = translationService.resolvedTargetLanguageCode(
        Localizations.localeOf(context).languageCode,
      );
      if (translationService.shouldTranslateOutgoing(
        text: text,
        targetLanguageCode: targetLanguageCode,
      )) {
        final result = await translationService.translateOutgoingText(
          text: text,
          targetLanguageCode: targetLanguageCode,
        );
        if (!mounted) return;
        if (result != null &&
            result.status == MessageTranslationStatus.completed &&
            result.translatedText.isNotEmpty) {
          outgoingText = result.translatedText;
          originalText = text;
          translatedLanguageCode = result.targetLanguageCode;
          translationModelId = result.modelId;
        }
      }
    }
    final compressionSourceText = outgoingText;
    final maxBytes = _maxContactInputBytes(connector);
    final outboundText = connector.prepareContactOutboundText(
      _resolveContact(connector),
      outgoingText,
    );
    if (utf8.encode(outboundText).length > maxBytes) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.chat_messageTooLong(maxBytes)),
      );
      return;
    }

    // This is only for cyr2lat compression - to see the message being sent in the same format as the other person will receive
    try {
      if (!outgoingText.startsWith(MCOImageCodec.prefix) &&
          !MCOImageV3Codec.isTextPayload(outgoingText) &&
          // Shared contact payloads must stay untouched.
          parseSharedContactText(outgoingText) == null &&
          // See channel_chat_screen: markers keep their structure and `del:`
          // commands stay verbatim, both handled in the connector.
          !SharedMarkerDeletion.isMarkerPayload(outgoingText) &&
          connector.isContactCyr2LatEnabled(
            _resolveContact(connector).publicKeyHex,
          )) {
        outgoingText = Cyr2Lat.encode(outgoingText);
      }
    } catch (_) {
      // TODO maybe log
    }
    // end transform

    if (quickAnswerText == null) {
      _textController.clear();
      _textFieldFocusNode.requestFocus();
    }
    final contact = _resolveContact(connector);
    final useSendingDelay =
        settings.sendingDelayForCancellationSeconds > 0 &&
        await connector.loadContactSendingDelayEnabled(contact.publicKeyHex);
    if (!mounted) return;
    if (useSendingDelay) {
      connector.scheduleContactMessage(
        contact,
        outgoingText,
        inputText: text,
        uncompressedText: compressionSourceText,
        delaySeconds: settings.sendingDelayForCancellationSeconds,
        originalText: originalText,
        translatedLanguageCode: translatedLanguageCode,
        translationModelId: translationModelId,
      );
    } else {
      connector.sendMessage(
        contact,
        outgoingText,
        uncompressedText: compressionSourceText,
        originalText: originalText,
        translatedLanguageCode: translatedLanguageCode,
        translationModelId: translationModelId,
      );
    }
  }

  void _cancelPendingContactSend(
    MeshCoreConnector connector,
    String messageId,
  ) {
    final text = connector.cancelPendingContactSend(messageId);
    if (text == null) return;
    _textController.text = text;
    _textController.selection = TextSelection.collapsed(offset: text.length);
    _textFieldFocusNode.requestFocus();
  }

  int _maxContactInputBytes(MeshCoreConnector connector) {
    // Room servers store posts in a 151-byte buffer and silently truncate
    // longer texts, which would destroy an MCMP container and its signature.
    final limit = _resolveContact(connector).type == advTypeRoom
        ? math.min(maxContactMessageBytes(), maxRoomServerTextBytes)
        : maxContactMessageBytes();
    if (connector.isContactMcmpEnabled(widget.contact.publicKeyHex)) {
      return math.max(0, limit - 2);
    }
    return limit;
  }

  int _resolveContactIndex = -1;

  Contact _resolveContact(MeshCoreConnector connector) {
    if (_resolveContactIndex >= 0 &&
        _resolveContactIndex < connector.contacts.length &&
        connector.contacts[_resolveContactIndex].publicKeyHex ==
            widget.contact.publicKeyHex) {
      return connector.contacts[_resolveContactIndex];
    }
    _resolveContactIndex = connector.contacts.indexWhere(
      (c) => c.publicKeyHex == widget.contact.publicKeyHex,
    );
    if (_resolveContactIndex == -1) {
      return widget.contact;
    }
    return connector.contacts[_resolveContactIndex];
  }

  Contact? _resolveContactFrom4Bytes(
    MeshCoreConnector connector,
    Uint8List key4Bytes,
  ) {
    // Match against saved contacts first, then nodes only seen via discovery —
    // a room poster you haven't saved may still be in the discovered list.
    return connector.allContactsUnfiltered.cast<Contact?>().firstWhere(
      (c) =>
          c != null &&
          listEquals(c.publicKey.sublist(0, 4), key4Bytes.sublist(0, 4)),
      orElse: () => null,
    );
  }

  String _currentPathLabel(Contact contact) {
    final connector = context.read<MeshCoreConnector>();

    // Check if user has set a path override
    if (contact.pathOverride != null) {
      if (contact.pathOverride! < 0) return context.l10n.chat_floodForced;
      if (contact.pathOverride == 0) return context.l10n.chat_directForced;
      final bytes = contact.pathOverrideBytes ?? Uint8List(0);
      final hopCount = _displayHopCount(
        bytes,
        contact.pathOverride!,
        connector.pathHashByteWidth,
      );
      return context.l10n.chat_hopsForced(hopCount);
    }

    // Use device's path
    if (contact.pathLength < 0) return context.l10n.chat_floodAuto;
    if (contact.pathLength == 0) return context.l10n.chat_direct;
    final hopCount = _displayHopCount(
      contact.path,
      contact.pathLength,
      connector.pathHashByteWidth,
    );
    return context.l10n.chat_hopsCount(hopCount);
  }

  int _displayHopCount(List<int> pathBytes, int storedHopCount, int hashWidth) {
    if (pathBytes.isEmpty) return storedHopCount;
    return PathHelper.splitPathBytes(pathBytes, hashWidth).length;
  }

  void _showContactInfo(BuildContext context) {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final contact = _resolveContact(connector);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: SelectableText(contact.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow(
                context.l10n.chat_type,
                contact.typeLabel(context.l10n),
              ),
              _buildInfoRow(
                context.l10n.chat_path,
                contact.pathLabel(
                  context.l10n,
                  pathHashByteWidth: connector.pathHashByteWidth,
                ),
              ),
              _buildInfoRow(
                context.l10n.contact_lastSeen,
                _formatContactLastMessage(contact.lastMessageAt),
              ),
              if (contact.hasLocation)
                _buildInfoRow(
                  context.l10n.chat_location,
                  '${contact.latitude?.toStringAsFixed(4)}, ${contact.longitude?.toStringAsFixed(4)}',
                ),
              _buildInfoRow(context.l10n.chat_publicKey, contact.publicKeyHex),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.common_close),
          ),
        ],
      ),
    );
  }

  void _showContactSettings(BuildContext context) {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final appSettingsService = Provider.of<AppSettingsService>(
      context,
      listen: false,
    );
    connector.ensureContactMcmpSettingLoaded(widget.contact.publicKeyHex);
    connector.ensureContactSmazSettingLoaded(widget.contact.publicKeyHex);
    connector.ensureContactCyr2LatSettingLoaded(widget.contact.publicKeyHex);
    connector.ensureContactSendingDelaySettingLoaded(
      widget.contact.publicKeyHex,
    );
    connector.ensureContactQuickAnswerIdsLoaded(widget.contact.publicKeyHex);
    final contact = widget.contact;
    bool mcmpEnabled = connector.isContactMcmpEnabled(contact.publicKeyHex);
    int selectedMcmpVersion = connector.contactMcmpVersion(
      contact.publicKeyHex,
    );
    bool mcmpUseSign = connector.contactMcmpUseSign(contact.publicKeyHex);
    bool smazEnabled = connector.isContactSmazEnabled(contact.publicKeyHex);
    bool cyr2latEnabled = connector.isContactCyr2LatEnabled(
      contact.publicKeyHex,
    );
    bool sendingDelayEnabled = connector.isContactSendingDelayEnabled(
      contact.publicKeyHex,
    );
    List<String> selectedQuickAnswerIds = connector.getContactQuickAnswerIds(
      contact.publicKeyHex,
    );
    String? selectedCyr2LatProfileId = connector.getContactCyr2LatProfileId(
      contact.publicKeyHex,
    );
    bool teleBaseEnabled = contact.teleBaseEnabled;
    bool teleLocEnabled = contact.teleLocEnabled;
    bool teleEnvEnabled = contact.teleEnvEnabled;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.contact_settings),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (contact.hasLocation) ...[
                  _buildInfoRow(
                    context.l10n.chat_location,
                    '${contact.latitude?.toStringAsFixed(4)}, ${contact.longitude?.toStringAsFixed(4)}',
                  ),
                  const Divider(height: 8),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.channels_mcmpCompression),
                  subtitle: Text(
                    context.l10n.channels_mcmpCompressionDescription,
                  ),
                  value: mcmpEnabled,
                  onChanged: (value) {
                    connector.setContactMcmpEnabled(
                      contact.publicKeyHex,
                      value,
                    );
                    if (value) {
                      connector.setContactSmazEnabled(
                        contact.publicKeyHex,
                        false,
                      );
                      connector.setContactCyr2LatEnabled(
                        contact.publicKeyHex,
                        false,
                      );
                    }
                    setDialogState(() {
                      mcmpEnabled = value;
                      if (mcmpEnabled) {
                        smazEnabled = false;
                        cyr2latEnabled = false;
                      }
                    });
                  },
                ),
                if (mcmpEnabled) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                    child: DropdownButtonFormField<int>(
                      initialValue: selectedMcmpVersion,
                      decoration: InputDecoration(
                        labelText: context.l10n.settings_mcmp_version,
                        border: const OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 2, child: Text('v2 (legacy)')),
                        DropdownMenuItem(value: 3, child: Text('v3')),
                      ],
                      onChanged: (value) {
                        final normalized = value == 3 ? 3 : 2;
                        connector.setContactMcmpVersion(
                          contact.publicKeyHex,
                          normalized,
                        );
                        setDialogState(() {
                          selectedMcmpVersion = normalized;
                        });
                      },
                    ),
                  ),
                  if (contact.type == advTypeRoom && selectedMcmpVersion == 3)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                      child: DropdownButtonFormField<bool>(
                        initialValue: mcmpUseSign,
                        decoration: InputDecoration(
                          labelText: context.l10n.settings_mcmp_useSign,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: true,
                            child: Text(context.l10n.settings_mcmp_signed),
                          ),
                          DropdownMenuItem(
                            value: false,
                            child: Text(context.l10n.settings_mcmp_noSign),
                          ),
                        ],
                        onChanged: (value) {
                          final normalized = value ?? true;
                          connector.setContactMcmpUseSign(
                            contact.publicKeyHex,
                            normalized,
                          );
                          setDialogState(() {
                            mcmpUseSign = normalized;
                          });
                        },
                      ),
                    ),
                ],
                const Divider(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.channels_smazCompression),
                  subtitle: Text(context.l10n.chat_compressOutgoingMessages),
                  value: smazEnabled,
                  onChanged: (value) {
                    connector.setContactSmazEnabled(
                      contact.publicKeyHex,
                      value,
                    );
                    connector.setContactMcmpEnabled(
                      contact.publicKeyHex,
                      false,
                    );
                    connector.setContactCyr2LatEnabled(
                      contact.publicKeyHex,
                      false,
                    );
                    setDialogState(() {
                      smazEnabled = value;
                      if (smazEnabled) {
                        mcmpEnabled = false;
                        cyr2latEnabled = false;
                      }
                    });
                  },
                ),
                const Divider(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.channels_cyr2latCompression),
                  subtitle: Text(context.l10n.channels_cyr2latCompressionDscr),
                  value: cyr2latEnabled,
                  onChanged: (value) {
                    connector.setContactCyr2LatEnabled(
                      contact.publicKeyHex,
                      value,
                    );
                    connector.setContactMcmpEnabled(
                      contact.publicKeyHex,
                      false,
                    );
                    connector.setContactSmazEnabled(
                      contact.publicKeyHex,
                      false,
                    );
                    setDialogState(() {
                      cyr2latEnabled = value;
                      if (cyr2latEnabled) {
                        mcmpEnabled = false;
                        smazEnabled = false;
                      }
                    });
                  },
                ),
                if (cyr2latEnabled) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedCyr2LatProfileId,
                      decoration: InputDecoration(
                        labelText:
                            context.l10n.channels_cyr2latSettingsSubheading,
                        border: const OutlineInputBorder(),
                      ),
                      items: appSettingsService.settings.cyr2latProfiles.map((
                        profile,
                      ) {
                        return DropdownMenuItem(
                          value: profile.id,
                          child: Text(profile.name),
                        );
                      }).toList(),
                      onChanged: (value) {
                        connector.setContactCyr2LatProfileId(
                          contact.publicKeyHex,
                          value,
                        );
                        setDialogState(() {
                          selectedCyr2LatProfileId = value;
                        });
                      },
                    ),
                  ),
                ],
                const Divider(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.settings_useSendingDelay),
                  value: sendingDelayEnabled,
                  onChanged: (value) {
                    connector.setContactSendingDelayEnabled(
                      contact.publicKeyHex,
                      value,
                    );
                    setDialogState(() {
                      sendingDelayEnabled = value;
                    });
                  },
                ),
                const Divider(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.quickreply_outlined),
                  title: Text(context.l10n.settings_quickAnswersTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final selection = await showQuickAnswersSelectionDialog(
                      context,
                      settingsService: appSettingsService,
                      selectedAnswerIds: selectedQuickAnswerIds,
                    );
                    if (selection == null) return;
                    await connector.setContactQuickAnswerIds(
                      contact.publicKeyHex,
                      selection,
                    );
                    setDialogState(() {
                      selectedQuickAnswerIds = selection;
                    });
                  },
                ),
                const Divider(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.contact_teleBase),
                  subtitle: Text(context.l10n.contact_teleBaseSubtitle),
                  value: teleBaseEnabled,
                  onChanged: (value) {
                    setDialogState(() => teleBaseEnabled = value);
                  },
                ),
                const Divider(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.contact_teleLoc),
                  subtitle: Text(context.l10n.contact_teleLocSubtitle),
                  value: teleLocEnabled,
                  onChanged: (value) {
                    setDialogState(() => teleLocEnabled = value);
                  },
                ),
                const Divider(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.contact_teleEnv),
                  subtitle: Text(context.l10n.contact_teleEnvSubtitle),
                  value: teleEnvEnabled,
                  onChanged: (value) {
                    setDialogState(() => teleEnvEnabled = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                connector.setContactFlags(
                  contact,
                  teleBase: teleBaseEnabled,
                  teleLoc: teleLocEnabled,
                  teleEnv: teleEnvEnabled,
                );
                Navigator.pop(context);
              },
              child: Text(context.l10n.common_close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  String _formatContactLastMessage(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.isNegative || diff.inMinutes < 5) {
      return context.l10n.contacts_lastSeenNow;
    }
    if (diff.inMinutes < 60) {
      return context.l10n.contacts_lastSeenMinsAgo(diff.inMinutes);
    }
    if (diff.inHours < 24) {
      final hours = diff.inHours;
      return hours == 1
          ? context.l10n.contacts_lastSeenHourAgo
          : context.l10n.contacts_lastSeenHoursAgo(hours);
    }
    final days = diff.inDays;
    return days == 1
        ? context.l10n.contacts_lastSeenDayAgo
        : context.l10n.contacts_lastSeenDaysAgo(days);
  }

  void _openChat(BuildContext context, Contact contact) {
    final connector = context.read<MeshCoreConnector>();
    final unread = connector.getUnreadCountForContactKey(contact.publicKeyHex);
    connector.markContactRead(contact.publicKeyHex);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ChatScreen(contact: contact, initialUnreadCount: unread),
      ),
    );
  }

  /// Mutes or unmutes the author of a room post.
  ///
  /// The message the block was ordered from is flagged too, so it disappears
  /// behind the placeholder along with any command it carried — the same
  /// exception a channel block makes. Unblocking clears no flags.
  /// A body revealed by hand is forgotten whenever the table changes, so a
  /// re-blocked author starts hidden again. The redraw itself comes from the
  /// connector, which re-emits the same signal.
  void _handleBlockedSendersChanged() {
    if (!mounted || _revealedBlockedMessages.isEmpty) return;
    setState(_revealedBlockedMessages.clear);
  }

  void _toggleRoomAuthorBlock(Message message) {
    final blocked = BlockedSenders.instance;
    final authorId = BlockedSenders.roomAuthorIdOf(message);
    if (authorId == null) return;
    if (blocked.isRoomAuthorBlocked(message)) {
      unawaited(blocked.unblockRoomAuthor(authorId));
      return;
    }
    unawaited(blocked.blockRoomAuthor(message));
    unawaited(
      context.read<MeshCoreConnector>().markContactMessageBlocked(
        widget.contact,
        message,
      ),
    );
  }

  void _openMessagePath(Message message, Contact contact) {
    final connector = context.read<MeshCoreConnector>();
    final fourByteHex = message.fourByteRoomContactKey
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    final String senderName;
    if (message.isOutgoing) {
      senderName = connector.selfName ?? context.l10n.chat_me;
    } else if (_resolveContact(connector).type == advTypeRoom) {
      // An unresolved author leaves `contact` as the room server itself; show
      // only the prefix rather than mislabeling the post with the room's name.
      senderName = contact.type == advTypeRoom
          ? "[$fourByteHex]"
          : "${contact.name} [$fourByteHex]";
    } else {
      senderName = _resolveContact(connector).name;
    }
    final pathMessage = ChannelMessage(
      senderKey: null,
      senderName: senderName,
      text: message.text,
      wasMcmpCompressed: message.wasMcmpCompressed,
      compressionType: message.compressionType,
      compressionSavingsPercent: message.compressionSavingsPercent,
      compressionOriginalBytes: message.compressionOriginalBytes,
      compressionPayloadBytes: message.compressionPayloadBytes,
      mcmpSignatureStatus: message.mcmpSignatureStatus,
      mcmpTimestamp: message.mcmpTimestamp,
      mcmpSenderName: message.mcmpSenderName,
      mcmpIsSigned: message.mcmpIsSigned,
      mcmpSignature: message.mcmpSignature,
      mcmpReplyAuthorName: message.mcmpReplyAuthorName,
      mcmpReplyTimestamp: message.mcmpReplyTimestamp,
      verifiedSenderKeyHex: message.verifiedSenderKeyHex,
      mcmpNameCollision: message.mcmpNameCollision,
      timestamp: message.timestamp,
      // Room-server posts / outgoing have no receive time → epoch 0 renders
      // as a dash on the path screen; contacts carry the real receivedAt.
      receivedAt: message.receivedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      sentByRadioAt: message.sentByRadioAt,
      sentByRadioWaitSeconds: message.sentByRadioWaitSeconds,
      isOutgoing: message.isOutgoing,
      status: ChannelMessageStatus.sent,
      repeatCount: 0,
      pathLength: message.pathLength,
      pathBytes: message.pathBytes,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChannelMessagePathScreen(message: pathMessage),
      ),
    );
  }

  Future<void> _confirmClearChat(
    BuildContext context,
    MeshCoreConnector connector,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.contact_clearChat),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.l10n.common_delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      connector.clearMessagesForContact(widget.contact);
    }
  }

  Future<void> _showMessageActions(Message message, Contact contact) async {
    final translationService = context.read<TranslationService>();
    final mcoImage = MCOImageMessage.tryDecode(message.text);
    final hasMcoOriginal = mcoImage == null
        ? false
        : await McoImagePackOriginals.instance.hasOriginalForText(message.text);
    if (!mounted) return;
    final settings = context.read<AppSettingsService>().settings;
    final canTranslateMessage =
        translationService.canTranslateIncoming(
          text: message.text,
          isCli: message.isCli,
          isOutgoing: message.isOutgoing,
        ) &&
        (message.translatedText?.trim().isEmpty ?? true);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Can't react to your own messages
                if (!message.isOutgoing)
                  ListTile(
                    leading: const Icon(Icons.add_reaction_outlined),
                    title: Text(context.l10n.chat_addReaction),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showEmojiPicker(message, contact);
                    },
                  ),
                if (PlatformInfo.isDesktop)
                  ListTile(
                    leading: const Icon(Icons.route),
                    title: Text(context.l10n.chat_path),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _openMessagePath(message, contact);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: Text(context.l10n.common_copy),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _copyMessageText(message.text);
                  },
                ),
                if (hasMcoOriginal)
                  ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: Text(
                      _mcoForceLora(
                            message.messageId,
                            settings.showMcoImagePackReplacements,
                          )
                          ? context.l10n.mcogallery_showPacked
                          : context.l10n.mcogallery_showLora,
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _toggleMcoImageVariant(message.messageId);
                    },
                  ),
                if (mcoImage != null)
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: Text(context.l10n.chat_canvasSendToGallery),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_saveMcoImageToGallery(message.text));
                    },
                  ),
                if (mcoImage != null)
                  ListTile(
                    leading: const Icon(Icons.save_alt_outlined),
                    title: Text(context.l10n.chat_canvasSave),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_saveMcoImageMessage(mcoImage));
                    },
                  ),
                if (mcoImage != null && ChannelBinaryDataHelper.isAvailable)
                  ListTile(
                    leading: const Icon(Icons.data_object_outlined),
                    title: Text(context.l10n.chat_canvasSaveBinary),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_saveMcoImageBinaryMessage(message.text));
                    },
                  ),
                if (mcoImage != null && settings.canvasActive)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(context.l10n.chat_canvasSendToEdit),
                    onTap: () {
                      final connector = context.read<MeshCoreConnector>();
                      final maxBytes = _maxContactInputBytes(connector);
                      Navigator.pop(sheetContext);
                      unawaited(
                        _showCanvasEditor(
                          connector,
                          maxBytes,
                          initialImage: mcoImage,
                        ),
                      );
                    },
                  ),
                if (canTranslateMessage)
                  ListTile(
                    leading: const Icon(Icons.translate),
                    title: Text(context.l10n.translation_translateMessage),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(
                        context
                            .read<MeshCoreConnector>()
                            .translateContactMessage(
                              widget.contact.publicKeyHex,
                              message,
                              manualTranslation: true,
                            ),
                      );
                    },
                  ),
                if (!message.isOutgoing)
                  ListTile(
                    leading: const Icon(Icons.mark_chat_unread_outlined),
                    title: Text(context.l10n.chat_markAsUnread),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _markAsUnread(message);
                    },
                  ),
                // Room-server posts only, and only incoming ones. A one-to-one
                // conversation is the contact itself, which is deleted rather
                // than muted; and a post of ours could only be hidden by
                // somebody adopting our own identity, which the author prefix
                // does not allow in the first place.
                if (contact.type == advTypeRoom &&
                    !message.isOutgoing &&
                    !message.isCli &&
                    BlockedSenders.roomAuthorIdOf(message) != null)
                  ListTile(
                    leading: Icon(
                      Icons.block,
                      color: BlockedSenders.instance.isRoomAuthorBlocked(
                        message,
                      )
                          ? null
                          : Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      BlockedSenders.instance.isRoomAuthorBlocked(message)
                          ? context.l10n.chat_unblockSender
                          : context.l10n.chat_blockSender,
                      style: BlockedSenders.instance.isRoomAuthorBlocked(
                        message,
                      )
                          ? null
                          : TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _toggleRoomAuthorBlock(message);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(context.l10n.common_delete),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _deleteMessage(message);
                  },
                ),
                if (message.isOutgoing)
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: Text(context.l10n.common_retry),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _retryMessage(message);
                    },
                  ),
                if (_resolveContact(context.read<MeshCoreConnector>()).type ==
                    advTypeRoom)
                  ListTile(
                    leading: const Icon(Icons.chat),
                    title: Text(context.l10n.contacts_openChat),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _openChat(context, contact);
                    },
                  ),
                if (!message.isOutgoing &&
                    message.mcmpIsSigned &&
                    message.mcmpSignature != null &&
                    _resolveContact(context.read<MeshCoreConnector>()).type ==
                        advTypeRoom)
                  ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: Text(context.l10n.chat_mcmpManualRecheckSign),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_recheckMessageSignature(message));
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: Text(context.l10n.common_cancel),
                  onTap: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _recheckMessageSignature(Message message) async {
    final connector = context.read<MeshCoreConnector>();
    final status = await connector.recheckContactMessageSignature(
      _resolveContact(connector).publicKeyHex,
      message.messageId,
    );
    if (!mounted || status == null) return;
    showDismissibleSnackBar(
      context,
      content: Text(McmpSignatureBadge.statusLabel(context, status)),
    );
  }

  void _copyMessageText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.chat_messageCopied),
    );
  }

  Future<void> _saveMcoImageMessage(MCOImage image) async {
    try {
      await MCOImageFileSaver.savePng(image);
    } catch (error) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(error.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  void _toggleMcoImageVariant(String messageId) {
    setState(() {
      if (!_mcoVariantOverridden.add(messageId)) {
        _mcoVariantOverridden.remove(messageId);
      }
    });
  }

  Future<void> _saveMcoImageToGallery(String text) async {
    try {
      await MCOImageGalleryStore().addFromText(text);
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.chat_canvasSendToGallery),
      );
    } on MCOImageCodecException catch (error) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(error.message),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<void> _saveMcoImageBinaryMessage(String text) async {
    try {
      await MCOImageFileSaver.saveBinaryPayloadFromText(text);
    } catch (error) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(error.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<void> _deleteMessage(Message message) async {
    final connector = context.read<MeshCoreConnector>();
    if (blockIfOffline(context, connector)) return;
    await connector.deleteMessage(message);
    if (!mounted) return;
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.chat_messageDeleted),
    );
  }

  Future<void> _addSharedContact(SharedContactInfo contact) async {
    final connector = context.read<MeshCoreConnector>();
    if (blockIfOffline(context, connector)) return;
    final selfPublicKey = connector.selfPublicKey;
    if (selfPublicKey != null &&
        selfPublicKey.isNotEmpty &&
        contact.publicKeyHex == connector.selfPublicKeyHex) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.chat_contactIsYou),
      );
      return;
    }

    final alreadyExists = connector.contacts.any(
      (existing) => existing.publicKeyHex == contact.publicKeyHex,
    );
    if (alreadyExists) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(context.l10n.chat_sureToReplaceContact),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.l10n.common_ok),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }

    try {
      await connector.addOrUpdateSharedContact(
        publicKey: contact.publicKey,
        type: contact.type,
        name: contact.name,
      );
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.contacts_contactImported),
      );
    } catch (_) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.contacts_contactImportFailed),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  void _retryMessage(Message message) {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    if (blockIfOffline(context, connector)) return;
    connector.cancelPendingContactSend(message.messageId);
    // Retry using the contact's current path override setting
    connector.sendMessage(_resolveContact(connector), message.text);
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.chat_retryingMessage),
    );
  }

  void _showEmojiPicker(Message message, Contact senderContact) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => EmojiPicker(
        onEmojiSelected: (emoji) {
          _sendReaction(message, senderContact, emoji);
        },
      ),
    );
  }

  void _sendReaction(Message message, Contact senderContact, String emoji) {
    final connector = context.read<MeshCoreConnector>();
    if (blockIfOffline(context, connector)) return;
    final emojiIndex = ReactionHelper.emojiToIndex(emoji);
    if (emojiIndex == null) return; // Unknown emoji, skip
    final timestampSecs = message.timestamp.millisecondsSinceEpoch ~/ 1000;

    // For room servers, include sender name (like channels) since multiple users
    // For 1:1 chats, sender is implicit (null)
    final liveContact = _resolveContact(connector);
    final senderName = liveContact.type == advTypeRoom
        ? senderContact.name
        : null;
    final hash = ReactionHelper.computeReactionHash(
      timestampSecs,
      senderName,
      message.text,
    );
    final reactionText = ReactionHelper.encodeReaction(hash, emojiIndex);
    connector.sendMessage(_resolveContact(connector), reactionText);
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final String senderName;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(Message message, String emoji)? onRetryReaction;
  final Future<void> Function(SharedContactInfo contact)? onAddSharedContact;
  final DateTime? pendingSendAt;
  final int? pendingSendDelaySeconds;
  final VoidCallback? onCancelPendingSend;
  final double textScale;
  final String sourceId;
  final bool isHighlighted;

  /// Signature badges are shown only in room-server chats; direct messages
  /// are authenticated by the ECDH transport and show no badge at all.
  final bool isRoomChat;

  /// Per-message override flipping the MCOimg variant away from the default
  /// chosen by the mod setting.
  final bool mcoVariantOverridden;

  /// The user tapped this blocked body to read it. Display only — a revealed
  /// body is still never parsed.
  final bool blockedRevealed;
  final VoidCallback? onToggleBlocked;

  const _MessageBubble({
    required this.message,
    required this.senderName,
    required this.sourceId,
    required this.textScale,
    this.isHighlighted = false,
    this.isRoomChat = false,
    this.mcoVariantOverridden = false,
    this.blockedRevealed = false,
    this.onToggleBlocked,
    this.onTap,
    this.onLongPress,
    this.onRetryReaction,
    this.onAddSharedContact,
    this.pendingSendAt,
    this.pendingSendDelaySeconds,
    this.onCancelPendingSend,
  });

  @override
  Widget build(BuildContext context) {
    final settingsService = context.watch<AppSettingsService>();
    final enableTracing = settingsService.settings.enableMessageTracing;
    // flutter_linkify ignores the ambient MediaQuery scaler, so the message
    // body must apply the global UI scale explicitly (as an additional
    // multiplier for backward compatibility with the untouched system scale).
    final bodyTextScaler = TextScaler.linear(settingsService.settings.uiScale);
    final showCompressionRatio = settingsService.settings.showCompressionRatio;
    final enableTimeSeconds = settingsService.settings.enableTimeSeconds;
    // Default is "show pack original" when replacements are enabled; the
    // per-message override flips it.
    final mcoForceLora =
        !settingsService.settings.showMcoImagePackReplacements !=
        mcoVariantOverridden;
    final isOutgoing = message.isOutgoing;
    final compressionType =
        message.compressionType ??
        (message.wasMcmpCompressed ? MessageCompressionType.mcmp : null);
    final compressionRatioPrefix =
        showCompressionRatio && message.compressionSavingsPercent != null
        ? '${message.compressionSavingsPercent}% '
        : '';
    // MCMP labels carry the format version: "mcmp3" / "mcmp2".
    final compressionTypeLabel = compressionType == null
        ? null
        : compressionType == MessageCompressionType.mcmp
        ? (message.mcmpTimestamp != null ? 'mcmp3' : 'mcmp2')
        : compressionType.label;
    final compressionLabel = compressionTypeLabel == null
        ? null
        : '$compressionRatioPrefix$compressionTypeLabel';
    final scheme = Theme.of(context).colorScheme;
    // A body that arrived while its author was blocked is never parsed: no
    // pin, no image, no shared contact, no coordinate link. Everything below
    // reads `bodyText`, so revealing the text cannot bring those handlers
    // back, and neither can lifting the block — that governs what arrives
    // afterwards.
    final blockedBody = message.wasBlocked ? message.text : null;
    final bodyText = blockedBody == null ? message.text : '';
    final gifId = GifHelper.parseGif(bodyText);
    final mcoImageMetadata = MCOImageMessage.decodeMetadata(bodyText);
    final mcoImage = mcoImageMetadata.image;
    final unsupportedMcoImageVersion = mcoImageMetadata.unsupportedVersion;
    final mcoImageBadgeLabel = MCOImageMessage.buildBadgeLabel(
      metadata: mcoImageMetadata,
      sourceText: bodyText,
      isBinary: false,
      showResolution: settingsService.settings.showMcoImageResolution,
      showFormat: settingsService.settings.showMcoImageFormat,
      showAlgorithm: settingsService.settings.showMcoImageAlgorithm,
      showBytes: settingsService.settings.showMcoImageBytes,
    );
    final isMediaMessage =
        gifId != null || mcoImage != null || unsupportedMcoImageVersion != null;
    final poi = parseMarkerText(bodyText);
    // `del:m:...` matches the marker pattern as well, so the badge is told
    // which one it is rather than guessing from the payload.
    final poiRemoved = SharedMarkerDeletion.targetOf(bodyText) != null;
    final coordinate = parseCoordinateText(bodyText);
    final sharedContact = parseSharedContactText(bodyText);
    final isFailed = message.status == MessageStatus.failed;

    // Bubble colors — outgoing uses MeshPalette.me / meBorder / meInk.
    final bubbleColor = isFailed
        ? scheme.errorContainer
        : isOutgoing
        ? MeshPalette.me
        : scheme.surfaceContainerLow;
    final bubbleBorder = isFailed
        ? scheme.error
        : isOutgoing
        ? MeshPalette.meBorder
        : scheme.outlineVariant;
    final textColor = isFailed
        ? scheme.onErrorContainer
        : (isOutgoing ? MeshPalette.meInk : scheme.onSurface);
    final metaColor = textColor.withValues(alpha: 0.65);
    final outgoingRadioWaitLabel = _outgoingRadioWaitLabel(message);
    const bodyFontSize = 14.0;

    // Asymmetric radius: outgoing — top-left large, others also large; outgoing bottom-right tight.
    final borderRadius = isOutgoing
        ? const BorderRadius.only(
            topLeft: Radius.circular(MeshRadii.lg),
            topRight: Radius.circular(MeshRadii.lg),
            bottomLeft: Radius.circular(MeshRadii.lg),
            bottomRight: Radius.circular(MeshRadii.xs),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(MeshRadii.xs),
            topRight: Radius.circular(MeshRadii.lg),
            bottomLeft: Radius.circular(MeshRadii.lg),
            bottomRight: Radius.circular(MeshRadii.lg),
          );

    // Do not strip room-server author bytes here: the parser stores them in
    // fourByteRoomContactKey, so message.text is safe to render as-is.
    final messageText = bodyText;
    final translatedDisplayText =
        blockedBody == null &&
            message.translatedText != null &&
            message.translatedText!.trim().isNotEmpty
        ? message.translatedText!.trim()
        : messageText;
    final originalDisplayText = isOutgoing
        ? message.originalText
        : (translatedDisplayText != messageText ? messageText : null);
    final sharedHistorySourceName = message.sharedHistorySourceName?.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: isOutgoing
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: PlatformInfo.isDesktop ? null : onTap,
            onLongPress: onLongPress,
            onSecondaryTapUp: PlatformInfo.isDesktop
                ? (_) => onLongPress?.call()
                : null,
            child: Row(
              mainAxisAlignment: isOutgoing
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isOutgoing) ...[
                  _buildAvatar(senderName, scheme),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeInOut,
                    padding: isMediaMessage
                        ? const EdgeInsets.all(4)
                        : const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72,
                    ),
                    decoration: BoxDecoration(
                      color: isHighlighted
                          ? Color.alphaBlend(
                              Colors.green.withValues(alpha: 0.5),
                              bubbleColor,
                            )
                          : bubbleColor,
                      borderRadius: borderRadius,
                      border: Border.all(color: bubbleBorder, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isOutgoing) ...[
                          Padding(
                            padding: isMediaMessage
                                ? const EdgeInsets.only(
                                    left: 8,
                                    top: 4,
                                    bottom: 4,
                                  )
                                : EdgeInsets.zero,
                            child: Text(
                              senderName,
                              style: MeshTheme.mono(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _colorForName(senderName),
                              ),
                            ),
                          ),
                          if (!isMediaMessage) const SizedBox(height: 2),
                        ],
                        if (blockedBody != null)
                          BlockedMessageBody(
                            text: blockedBody,
                            revealed: blockedRevealed,
                            onToggle: onToggleBlocked ?? () {},
                            style: TextStyle(
                              color: textColor,
                              fontSize: bodyFontSize * textScale,
                            ),
                          )
                        else if (poi != null)
                          _buildPoiMessage(
                            context,
                            poi,
                            textColor,
                            metaColor,
                            textScale,
                            senderName,
                            isRemoval: poiRemoved,
                            trailing: (!enableTracing && isOutgoing)
                                ? Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: MessageStatusIcon(
                                      isAcked:
                                          message.status ==
                                              MessageStatus.delivered &&
                                          message.pathBytes.isNotEmpty,
                                      isFailed:
                                          message.status ==
                                          MessageStatus.failed,
                                    ),
                                  )
                                : null,
                          )
                        else if (coordinate != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Flexible(
                                child: _CoordinateMessageLink(
                                  text: messageText.trim(),
                                  coordinate: coordinate,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: bodyFontSize * textScale,
                                    decoration: TextDecoration.underline,
                                    decorationColor: textColor,
                                  ),
                                ),
                              ),
                              if (!enableTracing && isOutgoing) ...[
                                const SizedBox(width: 4),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: MessageStatusIcon(
                                    isAcked:
                                        message.status ==
                                            MessageStatus.delivered &&
                                        message.pathBytes.isNotEmpty,
                                    isFailed:
                                        message.status == MessageStatus.failed,
                                  ),
                                ),
                                // With tracing off the meta row is hidden, so
                                // the signing lock rides next to the inline
                                // status icon (room chats only).
                                if (isRoomChat &&
                                    McmpSignatureBadge.isVisible(
                                      status: message.mcmpSignatureStatus,
                                      isOutgoing: true,
                                      wasMcmpV3: message.mcmpTimestamp != null,
                                    )) ...[
                                  const SizedBox(width: 4),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: McmpSignatureBadge(
                                      status: message.mcmpSignatureStatus,
                                      isOutgoing: true,
                                      isSigned: message.mcmpIsSigned,
                                      wasMcmpV3: message.mcmpTimestamp != null,
                                      verifiedSenderKeyHex:
                                          message.verifiedSenderKeyHex,
                                      nameCollision: message.mcmpNameCollision,
                                      showFingerprint: false,
                                      textScale: textScale,
                                      color: metaColor,
                                      errorColor: scheme.error,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          )
                        else if (unsupportedMcoImageVersion != null)
                          _buildUnsupportedMcoImageMessage(
                            context,
                            unsupportedMcoImageVersion,
                            mcoImageMetadata.currentMaxSupportedVersion,
                            textColor,
                            textScale,
                          )
                        else if (gifId != null)
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: GifMessage(
                                  url:
                                      'https://media.giphy.com/media/$gifId/giphy.gif',
                                  backgroundColor: Colors.transparent,
                                  fallbackTextColor: textColor.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                              if (!enableTracing && isOutgoing)
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: bubbleColor,
                                      borderRadius: const BorderRadius.only(
                                        bottomLeft: Radius.circular(10),
                                        topRight: Radius.circular(12),
                                      ),
                                    ),
                                    child: MessageStatusIcon(
                                      isAcked:
                                          message.status ==
                                              MessageStatus.delivered &&
                                          message.pathBytes.isNotEmpty,
                                      isFailed:
                                          message.status ==
                                          MessageStatus.failed,
                                    ),
                                  ),
                                ),
                            ],
                          )
                        else if (mcoImage != null)
                          Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: MCOImageOriginalOrFallback(
                                    text: message.text,
                                    image: mcoImage,
                                    forceLora: mcoForceLora,
                                  ),
                                ),
                              ),
                              if (!enableTracing && isOutgoing)
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: bubbleColor,
                                      borderRadius: const BorderRadius.only(
                                        bottomLeft: Radius.circular(10),
                                        topRight: Radius.circular(12),
                                      ),
                                    ),
                                    child: MessageStatusIcon(
                                      isAcked:
                                          message.status ==
                                              MessageStatus.delivered &&
                                          message.pathBytes.isNotEmpty,
                                      isFailed:
                                          message.status ==
                                          MessageStatus.failed,
                                    ),
                                  ),
                                ),
                            ],
                          )
                        else if (sharedContact != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Flexible(
                                child: SharedContactMessage(
                                  contact: sharedContact,
                                  textStyle: TextStyle(
                                    color: textColor,
                                    fontSize: bodyFontSize * textScale,
                                  ),
                                  metaColor: metaColor,
                                  textScale: textScale,
                                  onAddContact: () {
                                    final handler = onAddSharedContact;
                                    if (handler != null) {
                                      unawaited(handler(sharedContact));
                                    }
                                  },
                                ),
                              ),
                              if (!enableTracing && isOutgoing) ...[
                                const SizedBox(width: 4),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: MessageStatusIcon(
                                    isAcked:
                                        message.status ==
                                            MessageStatus.delivered &&
                                        message.pathBytes.isNotEmpty,
                                    isFailed:
                                        message.status == MessageStatus.failed,
                                  ),
                                ),
                                // With tracing off the meta row is hidden, so
                                // the signing lock rides next to the inline
                                // status icon (room chats only).
                                if (isRoomChat &&
                                    McmpSignatureBadge.isVisible(
                                      status: message.mcmpSignatureStatus,
                                      isOutgoing: true,
                                      wasMcmpV3: message.mcmpTimestamp != null,
                                    )) ...[
                                  const SizedBox(width: 4),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: McmpSignatureBadge(
                                      status: message.mcmpSignatureStatus,
                                      isOutgoing: true,
                                      isSigned: message.mcmpIsSigned,
                                      wasMcmpV3: message.mcmpTimestamp != null,
                                      verifiedSenderKeyHex:
                                          message.verifiedSenderKeyHex,
                                      nameCollision: message.mcmpNameCollision,
                                      showFingerprint: false,
                                      textScale: textScale,
                                      color: metaColor,
                                      errorColor: scheme.error,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Flexible(
                                child: TranslatedMessageContent(
                                  displayText: translatedDisplayText,
                                  originalText: originalDisplayText,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: bodyFontSize * textScale,
                                  ),
                                  originalStyle: TextStyle(
                                    color: textColor.withValues(alpha: 0.78),
                                    fontSize: bodyFontSize * textScale,
                                  ),
                                  textScaler: bodyTextScaler,
                                  onSecondaryTap: PlatformInfo.isDesktop
                                      ? onLongPress
                                      : null,
                                ),
                              ),
                              if (!enableTracing && isOutgoing) ...[
                                const SizedBox(width: 4),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: MessageStatusIcon(
                                    isAcked:
                                        message.status ==
                                            MessageStatus.delivered &&
                                        message.pathBytes.isNotEmpty,
                                    isFailed:
                                        message.status == MessageStatus.failed,
                                  ),
                                ),
                                // With tracing off the meta row is hidden, so
                                // the signing lock rides next to the inline
                                // status icon (room chats only).
                                if (isRoomChat &&
                                    McmpSignatureBadge.isVisible(
                                      status: message.mcmpSignatureStatus,
                                      isOutgoing: true,
                                      wasMcmpV3: message.mcmpTimestamp != null,
                                    )) ...[
                                  const SizedBox(width: 4),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: McmpSignatureBadge(
                                      status: message.mcmpSignatureStatus,
                                      isOutgoing: true,
                                      isSigned: message.mcmpIsSigned,
                                      wasMcmpV3: message.mcmpTimestamp != null,
                                      verifiedSenderKeyHex:
                                          message.verifiedSenderKeyHex,
                                      nameCollision: message.mcmpNameCollision,
                                      showFingerprint: false,
                                      textScale: textScale,
                                      color: metaColor,
                                      errorColor: scheme.error,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        // Incoming signature badge: room-server chats only,
                        // on its own line above the message time, independent
                        // of the message-tracing setting. Direct messages
                        // never show the badge; outgoing messages show their
                        // lock in the meta row after the compression label.
                        if (isRoomChat &&
                            !isOutgoing &&
                            McmpSignatureBadge.isVisible(
                              status: message.mcmpSignatureStatus,
                              isOutgoing: isOutgoing,
                              wasMcmpV3: message.mcmpTimestamp != null,
                            )) ...[
                          const SizedBox(height: 3),
                          Padding(
                            padding: isMediaMessage
                                ? const EdgeInsets.symmetric(horizontal: 8)
                                : EdgeInsets.zero,
                            child: McmpSignatureBadge(
                              status: message.mcmpSignatureStatus,
                              isOutgoing: isOutgoing,
                              isSigned: message.mcmpIsSigned,
                              wasMcmpV3: message.mcmpTimestamp != null,
                              verifiedSenderKeyHex:
                                  message.verifiedSenderKeyHex,
                              nameCollision: message.mcmpNameCollision,
                              // Direct messages never show a fingerprint;
                              // room posts do.
                              showFingerprint:
                                  message.fourByteRoomContactKey.isNotEmpty,
                              textScale: textScale,
                              color: metaColor,
                              errorColor: scheme.error,
                            ),
                          ),
                        ],
                        if (enableTracing) ...[
                          if (isOutgoing && message.retryCount > 0) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding: isMediaMessage
                                  ? const EdgeInsets.symmetric(horizontal: 8)
                                  : EdgeInsets.zero,
                              child: Text(
                                context.l10n.chat_retryCount(
                                  message.retryCount + 1,
                                  context
                                      .read<AppSettingsService>()
                                      .settings
                                      .maxMessageRetries,
                                ),
                                style: MeshTheme.mono(
                                  fontSize: 9.5 * textScale,
                                  color: metaColor,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 3),
                          // Meta row: timestamp + status icon + optional tracing
                          Padding(
                            padding: isMediaMessage
                                ? const EdgeInsets.only(
                                    left: 8,
                                    right: 8,
                                    bottom: 4,
                                  )
                                : EdgeInsets.zero,
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  _formatTime(
                                    message.timestamp,
                                    enableSeconds: enableTimeSeconds,
                                  ),
                                  style: MeshTheme.mono(
                                    fontSize: 10 * textScale,
                                    color: metaColor,
                                  ),
                                ),
                                if (outgoingRadioWaitLabel != null)
                                  Text(
                                    '($outgoingRadioWaitLabel)',
                                    style: MeshTheme.mono(
                                      fontSize: 10 * textScale,
                                      color: metaColor,
                                    ),
                                  ),
                                if (isOutgoing) ...[
                                  const SizedBox(width: 4),
                                  _buildStatusIcon(metaColor),
                                ],
                                if (message.tripTimeMs != null &&
                                    message.status ==
                                        MessageStatus.delivered) ...[
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.speed,
                                    size: 10,
                                    color: isOutgoing
                                        ? metaColor
                                        : Colors.green[700],
                                  ),
                                  Text(
                                    '${(message.tripTimeMs! / 1000).toStringAsFixed(1)}s',
                                    style: MeshTheme.mono(
                                      fontSize: 9 * textScale,
                                      color: isOutgoing
                                          ? metaColor
                                          : Colors.green[700],
                                    ),
                                  ),
                                ],
                                if (mcoImageBadgeLabel != null) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    mcoImageBadgeLabel,
                                    style: MeshTheme.mono(
                                      fontSize: 10 * textScale,
                                      color: metaColor,
                                    ),
                                  ),
                                ],
                                if (enableTracing &&
                                    compressionLabel != null) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    compressionLabel,
                                    style: MeshTheme.mono(
                                      fontSize: 10 * textScale,
                                      color: metaColor,
                                    ),
                                  ),
                                ],
                                // Outgoing signing lock (room chats), right
                                // after the compression-type label.
                                if (isRoomChat &&
                                    isOutgoing &&
                                    McmpSignatureBadge.isVisible(
                                      status: message.mcmpSignatureStatus,
                                      isOutgoing: true,
                                      wasMcmpV3: message.mcmpTimestamp != null,
                                    )) ...[
                                  const SizedBox(width: 4),
                                  McmpSignatureBadge(
                                    status: message.mcmpSignatureStatus,
                                    isOutgoing: true,
                                    isSigned: message.mcmpIsSigned,
                                    wasMcmpV3: message.mcmpTimestamp != null,
                                    verifiedSenderKeyHex:
                                        message.verifiedSenderKeyHex,
                                    nameCollision: message.mcmpNameCollision,
                                    showFingerprint: false,
                                    textScale: textScale,
                                    color: metaColor,
                                    errorColor: scheme.error,
                                  ),
                                ],
                                if (sharedHistorySourceName != null &&
                                    sharedHistorySourceName.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    'sync $sharedHistorySourceName',
                                    style: MeshTheme.mono(
                                      fontSize: 10 * textScale,
                                      color: metaColor,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (pendingSendAt != null &&
                            pendingSendDelaySeconds != null &&
                            onCancelPendingSend != null)
                          PendingSendCancelBar(
                            sendAt: pendingSendAt!,
                            delaySeconds: pendingSendDelaySeconds!,
                            onCancel: onCancelPendingSend!,
                            foregroundColor: textColor,
                            contentPadding: isMediaMessage
                                ? const EdgeInsets.symmetric(horizontal: 8)
                                : EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (message.reactions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: EdgeInsets.only(left: isOutgoing ? 0 : 42),
              child: _buildReactionsDisplay(context, message, scheme),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUnsupportedMcoImageMessage(
    BuildContext context,
    int received,
    int current,
    Color textColor,
    double textScale,
  ) {
    return Text(
      context.l10n.chat_canvasFormatNotSupported(received, current),
      style: TextStyle(
        color: textColor.withValues(alpha: 0.78),
        fontSize: 12 * textScale,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _buildPoiMessage(
    BuildContext context,
    MarkerPayload poi,
    Color textColor,
    Color metaColor,
    double textScale,
    String senderName, {
    bool isRemoval = false,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(
            isRemoval
                ? Icons.location_off_outlined
                : Icons.location_on_outlined,
            color: textColor,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () async {
            final selfName = context.read<MeshCoreConnector>().selfName ?? 'Me';
            final fromName = message.isOutgoing ? selfName : senderName;
            final key = buildSharedMarkerKey(
              sourceId: sourceId,
              label: poi.label,
              fromName: fromName,
              flags: poi.flags,
              isChannel: false,
            );
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MapScreen(
                  highlightPosition: poi.position,
                  highlightLabel: poi.label,
                  highlightMarkerKey: key,
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isRemoval
                    ? context.l10n.chat_poiRemoved
                    : context.l10n.chat_poiShared,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14 * textScale,
                ),
              ),
              if (poi.label.isNotEmpty)
                Text(
                  poi.label,
                  style: TextStyle(color: metaColor, fontSize: 12 * textScale),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 4), trailing],
      ],
    );
  }

  Widget _buildReactionsDisplay(
    BuildContext context,
    Message message,
    ColorScheme scheme,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: message.reactions.entries.map((entry) {
        final emoji = entry.key;
        final count = entry.value;
        final status = message.reactionStatuses[emoji];
        final isPending =
            status == MessageStatus.pending || status == MessageStatus.sent;
        final isFailed = status == MessageStatus.failed;

        return GestureDetector(
          onTap: isFailed && onRetryReaction != null
              ? () => onRetryReaction!(message, emoji)
              : null,
          child: Opacity(
            opacity: isPending ? 0.5 : 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isFailed
                    ? scheme.errorContainer
                    : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(MeshRadii.pill),
                border: Border.all(
                  color: isFailed ? scheme.error : scheme.outlineVariant,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    emoji,
                    style: MeshTheme.emoji(fontSize: 16),
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                  ),
                  if (count > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: MeshTheme.mono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                  if (isPending) ...[
                    const SizedBox(width: 2),
                    SizedBox(
                      width: 8,
                      height: 8,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                  if (isFailed) ...[
                    const SizedBox(width: 2),
                    Icon(Icons.replay, size: 10, color: scheme.error),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAvatar(String senderName, ColorScheme colorScheme) {
    final initial = _getFirstCharacterOrEmoji(senderName);
    final color = _getColorForName(senderName);

    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withValues(alpha: 0.2),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  String _getFirstCharacterOrEmoji(String name) {
    if (name.isEmpty) return '?';

    final emoji = firstEmoji(name);
    if (emoji != null) return emoji;

    final runes = name.runes.toList();
    if (runes.isEmpty) return '?';
    return String.fromCharCode(runes[0]).toUpperCase();
  }

  Color _getColorForName(String name) {
    // Generate a consistent color based on the name hash
    final hash = name.hashCode;
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.pink,
      Colors.teal,
      Colors.indigo,
      Colors.cyan,
      Colors.amber,
      Colors.deepOrange,
    ];

    return colors[hash.abs() % colors.length];
  }

  Widget _buildStatusIcon(Color color) {
    IconData icon;
    switch (message.status) {
      case MessageStatus.pending:
        icon = Icons.access_time;
        break;
      case MessageStatus.sent:
        icon = Icons.schedule;
        break;
      case MessageStatus.delivered:
        icon = Icons.check;
        break;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        break;
    }

    return Icon(icon, size: 12, color: color);
  }

  String _formatTime(DateTime time, {required bool enableSeconds}) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    if (!enableSeconds) return '$hour:$minute';
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String? _outgoingRadioWaitLabel(Message message) {
    if (!message.isOutgoing) return null;
    if (message.sentByRadioWaitSeconds.isNotEmpty) {
      return message.sentByRadioWaitSeconds.join('/');
    }
    if (message.sentByRadioAt == null) return null;
    final waitSeconds = message.sentByRadioAt!
        .difference(message.timestamp)
        .inSeconds;
    return (waitSeconds < 0 ? 0 : waitSeconds).toString();
  }
}

/// Deterministic name-to-hue mapping consistent with [AvatarCircle].
Color _colorForName(String name) {
  const hues = [
    MeshPalette.blue,
    MeshPalette.magenta,
    MeshPalette.signal,
    MeshPalette.warn,
    Color(0xFF8FA8F0),
    Color(0xFF6FD9CE),
  ];
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return hues[h % hues.length];
}

class _CoordinateMessageLink extends StatelessWidget {
  final String text;
  final MarkerPayload coordinate;
  final TextStyle style;

  const _CoordinateMessageLink({
    required this.text,
    required this.coordinate,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MapScreen(
              highlightPosition: coordinate.position,
              highlightLabel: coordinate.label,
            ),
          ),
        );
      },
      child: Text(text, style: style),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:latlong2/latlong.dart';
import 'package:meshcore_open/screens/region_management_screen.dart';
import 'package:meshcore_open/storage/region_store.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../models/community.dart';
import '../storage/community_store.dart';
import '../utils/platform_info.dart';
import '../helpers/channel_binary_data_helper.dart';
import '../helpers/chat_keyboard_navigation_history.dart';
import '../helpers/chat_scroll_controller.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/contact_share_helper.dart';
import '../helpers/cyr2lat.dart';
import '../helpers/gif_helper.dart';
import '../helpers/mco_image_file_saver.dart';
import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_v3_codec.dart';
import '../helpers/newline_to_space_formatter.dart';
import '../helpers/quick_answers_helper.dart';
import '../helpers/path_helper.dart';
import '../helpers/reaction_helper.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/app_settings.dart';
import '../models/channel.dart';
import '../models/channel_message.dart';
import '../models/message_compression.dart';
import '../models/mco_image_gallery_item.dart';
import '../models/contact.dart';
import '../models/translation_support.dart';
import '../services/app_settings_service.dart';
import '../services/chat_text_scale_service.dart';
import '../services/mco_image_pack_originals.dart';
import '../services/translation_service.dart';
import '../utils/emoji_utils.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/byte_count_input.dart';
import '../widgets/channel_edit_sheet.dart';
import '../widgets/chat_additional_actions_menu.dart';
import '../widgets/chat_zoom_wrapper.dart';
import '../widgets/emoji_picker.dart';
import '../widgets/gif_message.dart';
import '../widgets/jump_to_bottom_button.dart';
import '../widgets/gif_picker.dart';
import '../widgets/mco_image_message.dart';
import '../widgets/mco_image_original.dart';
import '../widgets/mcmp_signature_badge.dart';
import '../widgets/message_translation_button.dart';
import '../widgets/message_status_icon.dart';
import '../widgets/popup_menu_row.dart';
import '../widgets/quick_answers_picker_dialog.dart';
import '../widgets/radio_stats_entry.dart';
import '../widgets/shared_contact_message.dart';
import '../widgets/sync_progress_overlay.dart';
import '../widgets/translated_message_content.dart';
import '../widgets/unread_divider.dart';
import '../theme/mesh_theme.dart';
import '../storage/mco_image_gallery_store.dart';
import 'mco_image_gallery_screen.dart';
import '../widgets/mesh_ui.dart';
import 'channel_message_path_screen.dart';
import 'canvas_editor_screen.dart';
import 'channels_screen.dart';
import 'contacts_screen.dart';
import 'map_screen.dart';
import '../widgets/pending_send_cancel_bar.dart';

class ChannelChatScreen extends StatefulWidget {
  final Channel channel;
  final int initialUnreadCount;

  const ChannelChatScreen({
    super.key,
    required this.channel,
    this.initialUnreadCount = 0,
  });

  @override
  State<ChannelChatScreen> createState() => _ChannelChatScreenState();
}

class _ChannelChatScreenState extends State<ChannelChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ChatScrollController _scrollController = ChatScrollController();
  final FocusNode _textFieldFocusNode = FocusNode();
  final FocusNode _screenFocusNode = FocusNode();
  bool _keyboardNavigationActive = true;
  bool _ignoreNextTextFieldFocus = false;
  String _lastTextFieldText = '';
  ChannelMessage? _replyingToMessage;
  final CommunityStore _communityStore = CommunityStore();
  final CommunityPskIndex _communityIndex = CommunityPskIndex();
  final Map<String, GlobalKey> _messageKeys = {};

  /// Message ids whose MCOimg variant the user flipped away from the default
  /// (the default is "show pack original" when the mod setting is enabled,
  /// otherwise "show received LoRa version").
  final Set<String> _mcoVariantOverridden = {};

  /// Effective "render the received LoRa version" flag for a message,
  /// combining the mod setting default with the per-message override.
  bool _mcoForceLora(String messageId, bool showReplacements) {
    final defaultLora = !showReplacements;
    final overridden = _mcoVariantOverridden.contains(messageId);
    return defaultLora != overridden;
  }
  bool _isLoadingOlder = false;
  bool _communitiesLoaded = false;
  Region region = '';
  String? _highlightedMessageId;
  int _highlightSequence = 0;
  String? _replyReturnMessageId;

  MeshCoreConnector? _connector;
  StreamSubscription<void>? _mcmpSigningFailedSubscription;
  DateTime? _lastChannelSendAt;
  String? _lastChannelSentText;
  bool _channelSkipNextBottomSnap = false;
  String? _unreadDividerMessageId;

  String? _cachedFormatLocale;
  late DateFormat _hmFormat;
  late DateFormat _hmsFormat;
  late DateFormat _mdFormat;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextFieldTextChange);
    _textFieldFocusNode.addListener(_onTextFieldFocusChange);
    if (PlatformInfo.isDesktop) {
      HardwareKeyboard.instance.addHandler(_handleDesktopKeyEvent);
    }
    _scrollController.onScrollNearTop = _loadOlderMessages;
    _scrollController.showJumpToBottom.addListener(_clearDividerAtBottom);
    region = context.read<MeshCoreConnector>().getChannelRegion(
      widget.channel.index,
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final connector = context.read<MeshCoreConnector>();
      final settings = context.read<AppSettingsService>().settings;
      final idx = widget.channel.index;
      final unread = widget.initialUnreadCount;
      final messages = connector.getChannelMessages(widget.channel);
      _loadCommunities();
      ChannelMessage? anchor;
      if (unread > 0) {
        anchor = _findOldestUnreadChannelAnchor(messages, unread);
      }
      setState(() {
        if (anchor != null) _unreadDividerMessageId = anchor.messageId;
      });
      connector.setActiveChannel(idx);
      _connector = connector;
      _mcmpSigningFailedSubscription = connector.mcmpSigningFailures.listen(
        (_) => _showMcmpSigningFailed(),
      );
      if (PlatformInfo.isDesktop) {
        _ignoreNextTextFieldFocus = true;
        _textFieldFocusNode.requestFocus();
        _keyboardNavigationActive = true;
      }
      if (anchor != null && settings.jumpToOldestUnread) {
        _channelSkipNextBottomSnap = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollController.jumpToEstimatedOffset(
            unreadCount: unread,
            totalMessages: messages.length,
            onJumped: () {
              if (!mounted) return;
              _scrollToMessage(anchor!.messageId, quiet: true);
            },
          );
        });
      }
    });
  }

  // TODO: Reload communities when returning from another screen
  Future<void> _loadCommunities() async {
    final connector = context.read<MeshCoreConnector>();
    _communityStore.setPublicKeyHex = connector.selfPublicKeyHex;
    final communities = await _communityStore.loadCommunities();
    if (mounted) {
      setState(() {
        _communityIndex.initialize(communities);
        _communitiesLoaded = true;
      });
    }
  }

  ChannelMessage? _findOldestUnreadChannelAnchor(
    List<ChannelMessage> messages,
    int unreadCount,
  ) {
    if (unreadCount <= 0 || messages.isEmpty) return null;
    var n = 0;
    ChannelMessage? oldest;
    for (final m in messages.reversed) {
      if (m.isOutgoing) continue;
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
    await connector.loadOlderChannelMessages(widget.channel.index);

    if (mounted) {
      setState(() => _isLoadingOlder = false);
    }
  }

  @override
  void dispose() {
    _connector?.setActiveChannel(null);
    _mcmpSigningFailedSubscription?.cancel();
    if (PlatformInfo.isDesktop) {
      HardwareKeyboard.instance.removeHandler(_handleDesktopKeyEvent);
    }
    _scrollController.showJumpToBottom.removeListener(_clearDividerAtBottom);
    _textController.removeListener(_onTextFieldTextChange);
    _textFieldFocusNode.removeListener(_onTextFieldFocusChange);
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

  void _setReplyingTo(ChannelMessage message) {
    setState(() {
      _replyingToMessage = message;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _textFieldFocusNode.requestFocus();
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingToMessage = null;
    });
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

  String _normalizeReplyLookupText(String text) {
    return text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String? _findReplyFallbackMessageId(
    List<ChannelMessage> messages,
    ChannelMessage reply,
  ) {
    final senderName = reply.replyToSenderName?.trim();
    final replyText = reply.replyToText;
    if (senderName == null || senderName.isEmpty || replyText == null) {
      return null;
    }

    final normalizedQuotedText = _normalizeReplyLookupText(replyText);
    if (normalizedQuotedText.isEmpty) {
      return null;
    }

    for (int i = messages.length - 1; i >= 0; i--) {
      final candidate = messages[i];
      if (candidate.senderName.trim() != senderName) continue;

      final normalizedCandidateText = _normalizeReplyLookupText(candidate.text);
      if (normalizedCandidateText.isEmpty) continue;

      if (normalizedCandidateText.contains(normalizedQuotedText) ||
          normalizedQuotedText.contains(normalizedCandidateText)) {
        return candidate.messageId;
      }
    }

    return null;
  }

  BuildContext? _tryGetMessageContext(String messageId) {
    final key = _messageKeys[messageId];
    return key?.currentContext;
  }

  Future<BuildContext?> _materializeMessageContext(String messageId) async {
    final connector = context.read<MeshCoreConnector>();

    while (mounted) {
      final targetContext = _tryGetMessageContext(messageId);
      if (targetContext != null && targetContext.mounted) {
        return targetContext;
      }

      final messages = connector.getChannelMessages(widget.channel);
      final targetIndex = messages.indexWhere(
        (message) => message.messageId == messageId,
      );
      if (targetIndex >= 0 &&
          _scrollController.hasClients &&
          messages.length > 1) {
        final reversedIndex = messages.length - 1 - targetIndex;
        final targetOffset =
            _scrollController.position.maxScrollExtent *
            (reversedIndex / (messages.length - 1));
        _scrollController.jumpTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
        await WidgetsBinding.instance.endOfFrame;
        final materializedContext = _tryGetMessageContext(messageId);
        if (materializedContext != null && materializedContext.mounted) {
          return materializedContext;
        }
      }

      final olderMessages = await connector.loadOlderChannelMessages(
        widget.channel.index,
      );
      if (olderMessages.isEmpty) {
        return null;
      }
      await WidgetsBinding.instance.endOfFrame;
    }

    return null;
  }

  Future<String?> _resolveReplyTargetMessageId(ChannelMessage reply) async {
    final connector = context.read<MeshCoreConnector>();

    while (mounted) {
      final messages = connector.getChannelMessages(widget.channel);
      final directMessageId = reply.replyToMessageId;
      if (directMessageId != null &&
          messages.any((message) => message.messageId == directMessageId)) {
        return directMessageId;
      }

      final fallbackMessageId = _findReplyFallbackMessageId(messages, reply);
      if (fallbackMessageId != null) {
        return fallbackMessageId;
      }

      final olderMessages = await connector.loadOlderChannelMessages(
        widget.channel.index,
      );
      if (olderMessages.isEmpty) {
        return null;
      }
      await WidgetsBinding.instance.endOfFrame;
    }

    return null;
  }

  Future<bool> _scrollToMessage(
    String messageId, {
    bool highlightOnSuccess = false,
    bool quiet = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final originalMessageNotFoundText =
        context.l10n.chat_originalMessageNotFound;
    final targetContext = await _materializeMessageContext(messageId);

    if (!mounted) return false;

    if (targetContext == null) {
      if (quiet) return false;
      messenger.showSnackBar(
        SnackBar(
          content: GestureDetector(
            onTap: messenger.hideCurrentSnackBar,
            child: Text(originalMessageNotFoundText),
          ),
          duration: const Duration(seconds: 2),
          dismissDirection: DismissDirection.down,
          clipBehavior: Clip.hardEdge,
        ),
      );
      return false;
    }

    if (!targetContext.mounted) {
      return false;
    }

    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.3,
    );
    if (highlightOnSuccess) {
      _highlightMessage(messageId);
    }
    return true;
  }

  Future<void> _scrollToReplyTarget(ChannelMessage reply) async {
    final messenger = ScaffoldMessenger.of(context);
    final originalMessageNotFoundText =
        context.l10n.chat_originalMessageNotFound;
    final resolvedMessageId = await _resolveReplyTargetMessageId(reply);

    if (!mounted) return;

    if (resolvedMessageId == null) {
      messenger.showSnackBar(
        SnackBar(
          content: GestureDetector(
            onTap: messenger.hideCurrentSnackBar,
            child: Text(originalMessageNotFoundText),
          ),
          duration: const Duration(seconds: 2),
          dismissDirection: DismissDirection.down,
          clipBehavior: Clip.hardEdge,
        ),
      );
      return;
    }

    final didScroll = await _scrollToMessage(
      resolvedMessageId,
      highlightOnSuccess: true,
    );
    if (!mounted || !didScroll || resolvedMessageId == reply.messageId) return;

    // Escape returns from the quoted message back to the bubble that opened it.
    _replyReturnMessageId = reply.messageId;
    _screenFocusNode.requestFocus();
  }

  Widget _channelIcon(Channel channel) {
    // Determine icon based on channel type
    final ChannelType channelType = Channel.getChannelType(
      channel,
      _communityIndex,
    );
    final bool isCommunityChannel = Channel.isCommunityChannel(channelType);
    IconData icon;
    switch (channelType) {
      case ChannelType.communityPublic:
        icon = Icons.groups;
      case ChannelType.communityHashtag:
        icon = Icons.tag;
      case ChannelType.public:
        icon = Icons.public;
      case ChannelType.hashtag:
        icon = Icons.tag;
      case ChannelType.private:
        icon = Icons.lock;
    }
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: _communitiesLoaded
              ? Icon(icon, size: 20)
              : SizedBox.square(dimension: 20),
        ),
        if (isCommunityChannel)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.purple,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).cardColor,
                  width: 2,
                ),
              ),
              child: const Icon(Icons.people, size: 8, color: Colors.white),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _screenFocusNode,
      autofocus: PlatformInfo.isDesktop,
      child: Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openRegionSelectDialog(widget.channel),
            child: Row(
              children: [
                _channelIcon(widget.channel),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.channel.name.isEmpty
                            ? context.l10n.channels_channelIndex(
                                widget.channel.index,
                              )
                            : widget.channel.name,
                        style: const TextStyle(fontSize: 16),
                      ),
                      Consumer<MeshCoreConnector>(
                        builder: (context, connector, _) {
                          final unreadCount = connector
                              .getUnreadCountForChannelIndex(
                                widget.channel.index,
                              );
                          final regionHeader = region.isNotEmpty
                              ? context.l10n.channels_regionSetTo(region)
                              : context.l10n.channels_regionNotSet;
                          return Text(
                            '$regionHeader • ${context.l10n.chat_unread(unreadCount)}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          centerTitle: false,
          bottom: const SyncProgressAppBarBottom(),
          actions: [
            const RadioStatsIconButton(),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'editChannel') {
                  final connector = context.read<MeshCoreConnector>();
                  showChannelEditSheet(context, connector, widget.channel);
                }
                if (value == 'clearChat') {
                  _confirmClearChat();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'editChannel',
                  child: PopupMenuRow(
                    icon: Icons.edit_outlined,
                    text: context.l10n.channels_editChannel,
                  ),
                ),
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
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: Consumer<MeshCoreConnector>(
                  builder: (context, connector, child) {
                    final messages = [
                      ...connector.getChannelMessages(widget.channel),
                      ...connector.getPendingChannelMessages(
                        widget.channel.index,
                      ),
                    ];

                    if (messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              widget.channel.isPublicChannel
                                  ? Icons.public
                                  : Icons.tag,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              context.l10n.chat_noMessages,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              context.l10n.chat_sendMessageToStart,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Reverse messages so newest appear at bottom with reverse: true
                    final reversedMessages = messages.reversed.toList();
                    final itemCount =
                        reversedMessages.length + (_isLoadingOlder ? 1 : 0);

                    // Prune stale keys (deleted/cleared messages) to avoid
                    // unbounded growth.
                    final liveIds = reversedMessages
                        .map((m) => m.messageId)
                        .toSet();
                    _messageKeys.removeWhere((id, _) => !liveIds.contains(id));

                    // Rare messageId collisions must not reuse the same
                    // GlobalKey in the list.
                    final seenIds = <String>{};
                    final keyedIndices = <int>{};
                    for (var i = 0; i < reversedMessages.length; i++) {
                      if (seenIds.add(reversedMessages[i].messageId)) {
                        keyedIndices.add(i);
                      }
                    }

                    // Auto-scroll to bottom if user is already at bottom
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_channelSkipNextBottomSnap) {
                        _channelSkipNextBottomSnap = false;
                        return;
                      }
                      _scrollController.scrollToBottomIfAtBottom();
                    });

                    return Stack(
                      children: [
                        JumpToBottomReservedPadding(
                          scrollController: _scrollController,
                          basePadding: const EdgeInsets.all(8),
                          builder: (context, padding, bottomReservedExtent) {
                            final hasBottomSpacer = bottomReservedExtent > 0;
                            final spacerItemCount = hasBottomSpacer ? 1 : 0;
                            return ChatZoomWrapper(
                              child: ListView.builder(
                                reverse: true, // List grows from bottom up
                                controller: _scrollController,
                                padding: padding,
                                itemCount: itemCount + spacerItemCount,
                                itemBuilder: (context, index) {
                                  if (hasBottomSpacer && index == 0) {
                                    return SizedBox(
                                      height: bottomReservedExtent,
                                    );
                                  }
                                  final adjustedIndex = index - spacerItemCount;

                                  // Loading indicator now appears at end (bottom) of reversed list
                                  if (_isLoadingOlder &&
                                      adjustedIndex == itemCount - 1) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  final messageIndex = adjustedIndex;
                                  final message =
                                      reversedMessages[messageIndex];
                                  final messageKey =
                                      keyedIndices.contains(messageIndex)
                                      ? _messageKeys.putIfAbsent(
                                          message.messageId,
                                          GlobalKey.new,
                                        )
                                      : GlobalKey();
                                  final isUnreadAnchor =
                                      _unreadDividerMessageId != null &&
                                      message.messageId ==
                                          _unreadDividerMessageId;
                                  return Container(
                                    key: messageKey,
                                    child: Builder(
                                      builder: (context) {
                                        final textScale = context
                                            .select<
                                              ChatTextScaleService,
                                              double
                                            >((service) => service.scale);
                                        final bubble = _buildMessageBubble(
                                          message,
                                          textScale,
                                        );
                                        if (isUnreadAnchor) {
                                          return Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const UnreadDivider(),
                                              bubble,
                                            ],
                                          );
                                        }
                                        return bubble;
                                      },
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                        JumpToBottomButton(scrollController: _scrollController),
                      ],
                    );
                  },
                ),
              ),
              _buildMessageComposer(),
            ],
          ),
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
    return _scrollController.scrollBy(
      _scrollController.position.viewportDimension * 0.85 * direction,
    );
  }

  bool _scrollMessagesByLine(int direction) {
    return _scrollController.scrollBy(72.0 * direction);
  }

  void _markAsUnread(ChannelMessage message) {
    final connector = context.read<MeshCoreConnector>();
    final messages = connector.getChannelMessages(widget.channel);
    var count = 0;
    var found = false;
    for (final m in messages) {
      if (m.messageId == message.messageId) found = true;
      if (found && !m.isOutgoing) count++;
    }
    connector.setChannelUnreadCount(widget.channel.index, count);
  }

  Future<void> _handleEscapeNavigation() async {
    final returnMessageId = _replyReturnMessageId;
    if (returnMessageId != null) {
      _replyReturnMessageId = null;
      final didReturn = await _scrollToMessage(
        returnMessageId,
        highlightOnSuccess: true,
      );
      if (didReturn || !mounted) return;
    }

    ChatKeyboardNavigationHistory.rememberChannel(widget.channel);
    final navigator = Navigator.of(context);
    final didPop = await navigator.maybePop();
    if (!mounted || didPop) return;
    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => const ChannelsScreen(hideBackButton: true),
      ),
    );
  }

  /// Signature status badge shown next to the sender name of incoming
  /// messages: status icon, verified-key fingerprint and the name-collision
  /// warning. Outgoing messages show their signed/unsigned badge in the meta
  /// row instead.
  Widget _buildMcmpSignatureIcon(ChannelMessage message) {
    if (message.isOutgoing ||
        !McmpSignatureBadge.isVisible(
          status: message.mcmpSignatureStatus,
          isOutgoing: false,
          wasMcmpV3: message.mcmpTimestamp != null,
        )) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: McmpSignatureBadge(
        status: message.mcmpSignatureStatus,
        isOutgoing: false,
        isSigned: message.mcmpIsSigned,
        wasMcmpV3: message.mcmpTimestamp != null,
        verifiedSenderKeyHex: message.verifiedSenderKeyHex,
        nameCollision: message.mcmpNameCollision,
        textScale: 1.0,
        color: scheme.onSurface.withValues(alpha: 0.65),
        errorColor: scheme.error,
      ),
    );
  }

  Widget _buildMessageBubble(ChannelMessage message, double textScale) {
    final connector = context.watch<MeshCoreConnector>();
    final settingsService = context.watch<AppSettingsService>();
    final enableTracing = settingsService.settings.enableMessageTracing;
    final noRetransmissionWarningsEnabled =
        settingsService.settings.noRetransmissionWarningSeconds > 0;
    final showCompressionRatio = settingsService.settings.showCompressionRatio;
    final showHops = settingsService.settings.showHops;
    final enableTimeSeconds = settingsService.settings.enableTimeSeconds;
    final incomingQuoteAsMentions =
        settingsService.settings.incomingQuoteAsMentions;
    final simplifiedMentions = settingsService.settings.simplifiedMentions;
    final showMessageRegion = settingsService.settings.showMessageRegion;
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
        : '$compressionRatioPrefix$compressionTypeLabel'
              '${message.wasBinaryTransport ? ' bin' : ''}';
    final scheme = Theme.of(context).colorScheme;
    final gifId = GifHelper.parseGif(message.text);
    final mcoImageMetadata = MCOImageMessage.decodeMetadata(message.text);
    final mcoImage = mcoImageMetadata.image;
    final unsupportedMcoImageVersion = mcoImageMetadata.unsupportedVersion;
    final mcoImageBadgeLabel = MCOImageMessage.buildBadgeLabel(
      metadata: mcoImageMetadata,
      sourceText: message.text,
      isBinary: message.wasBinaryTransport,
      showResolution: settingsService.settings.showMcoImageResolution,
      showFormat: settingsService.settings.showMcoImageFormat,
      showAlgorithm: settingsService.settings.showMcoImageAlgorithm,
      showBytes: settingsService.settings.showMcoImageBytes,
      senderName: message.senderName,
      binaryPacketBytes: message.binaryPacketBytes,
    );
    final isMediaMessage =
        gifId != null || mcoImage != null || unsupportedMcoImageVersion != null;
    final poi = parseMarkerText(message.text);
    final coordinate = parseCoordinateText(message.text);
    final sharedContact = parseSharedContactText(message.text);
    final isPlainTextMessage =
        poi == null &&
        coordinate == null &&
        !isMediaMessage &&
        sharedContact == null;
    final hasReplyContext =
        message.replyToSenderName != null || message.replyToText != null;
    final replyMentionName = message.replyToSenderName?.trim();
    final showIncomingReplyMention =
        !isOutgoing &&
        incomingQuoteAsMentions &&
        hasReplyContext &&
        replyMentionName != null &&
        replyMentionName.isNotEmpty;
    final translatedDisplayText =
        message.translatedText != null &&
            message.translatedText!.trim().isNotEmpty
        ? message.translatedText!.trim()
        : message.text;
    final originalDisplayText = message.isOutgoing
        ? message.originalText
        : (translatedDisplayText != message.text ? message.text : null);
    final sharedHistorySourceName = message.sharedHistorySourceName?.trim();
    final packetRegion = message.packetRegion?.trim();
    final packetRegionLabel = packetRegion != null && packetRegion.isNotEmpty
        ? packetRegion
        : (message.packetRegionInfoAvailable
              ? context.l10n.channels_messageRegionEmpty
              : context.l10n.channels_messageRegionUnknown);
    final displayPath = message.pathBytes.isNotEmpty
        ? message.pathBytes
        : (message.pathVariants.isNotEmpty
              ? message.pathVariants.first
              : Uint8List(0));
    final pendingSendAt = connector.pendingChannelSendAt(message.messageId);
    final pendingSendDelaySeconds = connector.pendingChannelSendDelaySeconds(
      message.messageId,
    );
    final outgoingRadioWaitSeconds = _outgoingRadioWaitSeconds(message);
    final displayPathHashWidth =
        message.pathHashWidth ??
        context.read<MeshCoreConnector>().pathHashByteWidth;
    final displayHopCount = _displayHopCount(
      displayPath,
      displayPathHashWidth,
      message.pathLength,
    );
    final noRetransmissionWarningSeconds = noRetransmissionWarningsEnabled
        ? message.noRetransmissionWarningSeconds
        : null;
    final hasNoRetransmissionWarning =
        noRetransmissionWarningSeconds != null &&
        noRetransmissionWarningSeconds > 0;
    final showFailureVisual =
        message.status == ChannelMessageStatus.failed ||
        hasNoRetransmissionWarning;

    final isHighlighted = _highlightedMessageId == message.messageId;
    final bubbleColor = showFailureVisual
        ? scheme.errorContainer
        : isOutgoing
        ? MeshPalette.me
        : scheme.surfaceContainerLow;
    final bubbleBorder = showFailureVisual
        ? scheme.error
        : isOutgoing
        ? MeshPalette.meBorder
        : scheme.outlineVariant;
    final textColor = showFailureVisual
        ? scheme.onErrorContainer
        : isOutgoing
        ? MeshPalette.meInk
        : scheme.onSurface;
    final metaColor = textColor.withValues(alpha: 0.65);
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
    const maxSwipeOffset = 64.0;
    const replySwipeThreshold = 64.0;
    const bodyFontSize = 14.0;
    final messageBody = LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: isOutgoing
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isOutgoing
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isOutgoing) ...[
                _buildAvatar(message.senderName),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: GestureDetector(
                  onTap: PlatformInfo.isDesktop
                      ? null
                      : () => _showMessagePathInfo(message),
                  onLongPress: () => unawaited(_showMessageActions(message)),
                  onSecondaryTapUp: PlatformInfo.isDesktop
                      ? (_) => unawaited(_showMessageActions(message))
                      : null,
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
                      maxWidth: constraints.maxWidth * 0.72,
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
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    message.senderName,
                                    overflow: TextOverflow.ellipsis,
                                    style: MeshTheme.mono(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _colorForName(message.senderName),
                                    ),
                                  ),
                                ),
                                _buildMcmpSignatureIcon(message),
                              ],
                            ),
                          ),
                          if (!isMediaMessage) const SizedBox(height: 2),
                        ],
                        if (hasReplyContext && !showIncomingReplyMention) ...[
                          _buildReplyPreview(message, textScale),
                          const SizedBox(height: 8),
                        ],
                        if (showIncomingReplyMention &&
                            !isPlainTextMessage) ...[
                          _buildReplyMentionChip(
                            message,
                            replyMentionName,
                            textScale,
                            simplified: simplifiedMentions,
                            textStyle: TextStyle(
                              color: textColor,
                              fontSize: bodyFontSize * textScale,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        if (poi != null)
                          _buildPoiMessage(
                            context,
                            poi,
                            isOutgoing,
                            textScale,
                            message.senderName,
                            trailing: (!enableTracing && isOutgoing)
                                ? Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: MessageStatusIcon(
                                      isAcked:
                                          message.status ==
                                              ChannelMessageStatus.sent &&
                                          displayPath.isNotEmpty,
                                      isFailed: showFailureVisual,
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
                                  text: message.text.trim(),
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
                                            ChannelMessageStatus.sent &&
                                        displayPath.isNotEmpty,
                                    isFailed: showFailureVisual,
                                  ),
                                ),
                                // With tracing off the meta row is hidden, so
                                // the signing lock rides next to the inline
                                // status icon.
                                if (McmpSignatureBadge.isVisible(
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
                                      wasMcmpV3:
                                          message.mcmpTimestamp != null,
                                      verifiedSenderKeyHex:
                                          message.verifiedSenderKeyHex,
                                      nameCollision:
                                          message.mcmpNameCollision,
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
                            textScale,
                          )
                        else if (gifId != null)
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
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
                                              ChannelMessageStatus.sent &&
                                          displayPath.isNotEmpty,
                                      isFailed: showFailureVisual,
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
                                  borderRadius: BorderRadius.circular(8),
                                  child: MCOImageOriginalOrFallback(
                                    text: message.text,
                                    image: mcoImage,
                                    forceLora: _mcoForceLora(
                                      message.messageId,
                                      settingsService
                                          .settings
                                          .showMcoImagePackReplacements,
                                    ),
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
                                              ChannelMessageStatus.sent &&
                                          displayPath.isNotEmpty,
                                      isFailed: showFailureVisual,
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
                                  onAddContact: () => unawaited(
                                    _addSharedContact(sharedContact),
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
                                            ChannelMessageStatus.sent &&
                                        displayPath.isNotEmpty,
                                    isFailed: showFailureVisual,
                                  ),
                                ),
                                // With tracing off the meta row is hidden, so
                                // the signing lock rides next to the inline
                                // status icon.
                                if (McmpSignatureBadge.isVisible(
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
                                      wasMcmpV3:
                                          message.mcmpTimestamp != null,
                                      verifiedSenderKeyHex:
                                          message.verifiedSenderKeyHex,
                                      nameCollision:
                                          message.mcmpNameCollision,
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
                                child: _buildMessageTextContent(
                                  message: message,
                                  displayText: translatedDisplayText,
                                  originalText: originalDisplayText,
                                  textStyle: TextStyle(
                                    color: textColor,
                                    fontSize: bodyFontSize * textScale,
                                  ),
                                  originalStyle: TextStyle(
                                    fontSize: bodyFontSize * textScale,
                                    fontStyle: FontStyle.italic,
                                    color: textColor.withValues(alpha: 0.72),
                                  ),
                                  replyMentionName:
                                      showIncomingReplyMention &&
                                          isPlainTextMessage
                                      ? replyMentionName
                                      : null,
                                  simplifiedMention: simplifiedMentions,
                                  textScale: textScale,
                                ),
                              ),
                              if (!enableTracing && isOutgoing) ...[
                                const SizedBox(width: 4),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: MessageStatusIcon(
                                    isAcked:
                                        message.status ==
                                            ChannelMessageStatus.sent &&
                                        displayPath.isNotEmpty,
                                    isFailed: showFailureVisual,
                                  ),
                                ),
                                // With tracing off the meta row is hidden, so
                                // the signing lock rides next to the inline
                                // status icon.
                                if (McmpSignatureBadge.isVisible(
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
                                      wasMcmpV3:
                                          message.mcmpTimestamp != null,
                                      verifiedSenderKeyHex:
                                          message.verifiedSenderKeyHex,
                                      nameCollision:
                                          message.mcmpNameCollision,
                                      textScale: textScale,
                                      color: metaColor,
                                      errorColor: scheme.error,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        // Standalone textual signing badge for outgoing
                        // messages, kept commented in case it comes back —
                        // the lock icon now lives in the meta row after the
                        // compression label.
                        // if (isOutgoing &&
                        //     McmpSignatureBadge.isVisible(
                        //       status: message.mcmpSignatureStatus,
                        //       isOutgoing: true,
                        //       wasMcmpV3: message.mcmpTimestamp != null,
                        //     )) ...[
                        //   const SizedBox(height: 3),
                        //   Padding(
                        //     padding: isMediaMessage
                        //         ? const EdgeInsets.symmetric(horizontal: 8)
                        //         : EdgeInsets.zero,
                        //     child: McmpSignatureBadge(...),
                        //   ),
                        // ],
                        if (enableTracing) ...[
                          if (showHops && displayPath.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding: isMediaMessage
                                  ? const EdgeInsets.symmetric(horizontal: 8)
                                  : EdgeInsets.zero,
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  RouteChip(
                                    isDirect: (message.pathLength ?? -1) >= 0,
                                    hops: displayHopCount,
                                  ),
                                  Text(
                                    context.l10n.channels_via(
                                      _formatPathPrefixes(
                                        displayPath,
                                        displayPathHashWidth,
                                      ),
                                    ),
                                    style: MeshTheme.mono(
                                      fontSize: 9.5 * textScale,
                                      color: metaColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (showMessageRegion) ...[
                            const SizedBox(height: 3),
                            Padding(
                              padding: isMediaMessage
                                  ? const EdgeInsets.symmetric(horizontal: 8)
                                  : EdgeInsets.zero,
                              child: Text(
                                context.l10n.channels_messageRegion(
                                  packetRegionLabel,
                                ),
                                style: MeshTheme.mono(
                                  fontSize: 10 * textScale,
                                  color: metaColor,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 3),
                          Padding(
                            padding: isMediaMessage
                                ? const EdgeInsets.only(
                                    left: 8,
                                    right: 8,
                                    bottom: 4,
                                  )
                                : EdgeInsets.zero,
                            child: Wrap(
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  _formatTime(
                                    context,
                                    message.timestamp,
                                    enableSeconds: enableTimeSeconds,
                                  ),
                                  style: MeshTheme.mono(
                                    fontSize: 10 * textScale,
                                    color: metaColor,
                                  ),
                                ),
                                if (outgoingRadioWaitSeconds != null) ...[
                                  const SizedBox(width: 3),
                                  Text(
                                    '($outgoingRadioWaitSeconds)',
                                    style: MeshTheme.mono(
                                      fontSize: 10 * textScale,
                                      color: metaColor,
                                    ),
                                  ),
                                ],
                                if (message.repeatCount > 0) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.repeat,
                                    size: 11 * textScale,
                                    color: metaColor,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${message.repeatCount}',
                                    style: MeshTheme.mono(
                                      fontSize: 10 * textScale,
                                      color: metaColor,
                                    ),
                                  ),
                                ],
                                if (isOutgoing) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    showFailureVisual
                                        ? Icons.error_outline
                                        : message.status ==
                                              ChannelMessageStatus.sent
                                        ? Icons.check
                                        : message.status ==
                                              ChannelMessageStatus.pending
                                        ? Icons.schedule
                                        : Icons.error_outline,
                                    size: 12 * textScale,
                                    color: showFailureVisual
                                        ? Colors.red
                                        : metaColor,
                                  ),
                                ],
                                if (mcoImageBadgeLabel != null) ...[
                                  const SizedBox(width: 6),
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
                                  const SizedBox(width: 6),
                                  Text(
                                    compressionLabel,
                                    style: MeshTheme.mono(
                                      fontSize: 10 * textScale,
                                      color: metaColor,
                                    ),
                                  ),
                                ],
                                // Outgoing signing lock, right after the
                                // compression-type label.
                                if (isOutgoing &&
                                    McmpSignatureBadge.isVisible(
                                      status: message.mcmpSignatureStatus,
                                      isOutgoing: true,
                                      wasMcmpV3: message.mcmpTimestamp != null,
                                    )) ...[
                                  const SizedBox(width: 6),
                                  McmpSignatureBadge(
                                    status: message.mcmpSignatureStatus,
                                    isOutgoing: true,
                                    isSigned: message.mcmpIsSigned,
                                    wasMcmpV3: message.mcmpTimestamp != null,
                                    verifiedSenderKeyHex:
                                        message.verifiedSenderKeyHex,
                                    nameCollision: message.mcmpNameCollision,
                                    textScale: textScale,
                                    color: metaColor,
                                    errorColor: scheme.error,
                                  ),
                                ],
                                if (sharedHistorySourceName != null &&
                                    sharedHistorySourceName.isNotEmpty) ...[
                                  const SizedBox(width: 6),
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
                        if (hasNoRetransmissionWarning) ...[
                          const SizedBox(height: 3),
                          Padding(
                            padding: isMediaMessage
                                ? const EdgeInsets.symmetric(horizontal: 8)
                                : EdgeInsets.zero,
                            child: Text(
                              context.l10n.settings_modSettingsNoRetraInfo(
                                noRetransmissionWarningSeconds,
                              ),
                              style: MeshTheme.mono(
                                fontSize: 10 * textScale,
                                color: metaColor,
                              ),
                            ),
                          ),
                        ],
                        if (pendingSendAt != null &&
                            pendingSendDelaySeconds != null)
                          PendingSendCancelBar(
                            sendAt: pendingSendAt,
                            delaySeconds: pendingSendDelaySeconds,
                            onCancel: () => _cancelPendingChannelSend(
                              connector,
                              message.messageId,
                            ),
                            foregroundColor: textColor,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (message.reactions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: EdgeInsets.only(left: isOutgoing ? 0 : 42),
              child: _buildReactionsDisplay(message),
            ),
          ],
        ],
      ),
    );

    if (!isOutgoing && !PlatformInfo.isDesktop) {
      return _SwipeReplyBubble(
        maxSwipeOffset: maxSwipeOffset,
        replySwipeThreshold: replySwipeThreshold,
        onReplyTriggered: () => _setReplyingTo(message),
        hintBuilder: ({required isStart}) =>
            _buildReplySwipeHint(isStart: isStart),
        child: messageBody,
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: messageBody,
      );
    }
  }

  Widget _buildReplySwipeHint({required bool isStart}) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.reply, color: colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          context.l10n.chat_reply,
          style: TextStyle(
            color: colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    return Container(
      alignment: isStart ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: colorScheme.primary.withValues(alpha: 0.08),
      child: isStart
          ? content
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.chat_reply,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.reply, color: colorScheme.primary),
              ],
            ),
    );
  }

  Widget _buildUnsupportedMcoImageMessage(
    BuildContext context,
    int received,
    int current,
    double textScale,
  ) {
    return Text(
      context.l10n.chat_canvasFormatNotSupported(received, current),
      style: TextStyle(
        fontSize: 12 * textScale,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _buildMessageTextContent({
    required ChannelMessage message,
    required String displayText,
    required String? originalText,
    required TextStyle textStyle,
    required TextStyle originalStyle,
    required String? replyMentionName,
    required bool simplifiedMention,
    required double textScale,
  }) {
    // flutter_linkify ignores the ambient MediaQuery scaler, so the message
    // body must apply the global UI scale explicitly (as an additional
    // multiplier for backward compatibility with the untouched system scale).
    final uiScale = context.read<AppSettingsService>().settings.uiScale;
    final bodyTextScaler = TextScaler.linear(uiScale);
    if (replyMentionName == null || replyMentionName.isEmpty) {
      return TranslatedMessageContent(
        displayText: displayText,
        originalText: originalText,
        style: textStyle,
        originalStyle: originalStyle,
        textScaler: bodyTextScaler,
      );
    }

    final trimmedDisplay = displayText.trim();
    final trimmedOriginal = originalText?.trim();
    final shouldShowOriginal =
        trimmedOriginal != null &&
        trimmedOriginal.isNotEmpty &&
        trimmedOriginal != trimmedDisplay;

    final display = _buildInlineReplyMentionText(
      message: message,
      senderName: replyMentionName,
      text: trimmedDisplay,
      style: textStyle,
      textScale: textScale,
      simplifiedMention: simplifiedMention,
    );

    if (!shouldShowOriginal) return display;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        display,
        const SizedBox(height: 6),
        Text(trimmedOriginal, style: originalStyle),
      ],
    );
  }

  Widget _buildInlineReplyMentionText({
    required ChannelMessage message,
    required String senderName,
    required String text,
    required TextStyle style,
    required double textScale,
    required bool simplifiedMention,
  }) {
    return RichText(
      text: TextSpan(
        style: style,
        children: [
          WidgetSpan(
            alignment: simplifiedMention
                ? PlaceholderAlignment.baseline
                : PlaceholderAlignment.middle,
            baseline: simplifiedMention ? TextBaseline.alphabetic : null,
            child: _buildReplyMentionChip(
              message,
              senderName,
              textScale,
              simplified: simplifiedMention,
              textStyle: style,
            ),
          ),
          if (text.isNotEmpty) ...[
            TextSpan(text: simplifiedMention ? ' ' : '  '),
            TextSpan(text: text),
          ],
        ],
      ),
    );
  }

  Widget _buildReplyMentionChip(
    ChannelMessage message,
    String senderName,
    double textScale, {
    required bool simplified,
    required TextStyle textStyle,
  }) {
    return GestureDetector(
      onTap: () => _scrollToReplyTarget(message),
      child: Container(
        constraints: BoxConstraints(maxWidth: 160 * textScale),
        padding: simplified
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: simplified
            ? null
            : BoxDecoration(
                border: Border.all(color: MeshPalette.blue, width: 1),
                borderRadius: BorderRadius.circular(MeshRadii.xs),
              ),
        child: Text(
          '@$senderName',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: simplified
              ? textStyle.copyWith(fontWeight: FontWeight.w700)
              : MeshTheme.mono(
                  fontSize: 12 * textScale,
                  fontWeight: FontWeight.w700,
                  color: MeshPalette.blue,
                ),
        ),
      ),
    );
  }

  Widget _buildReplyPreview(ChannelMessage message, double textScale) {
    final connector = context.read<MeshCoreConnector>();
    final isOwnNode = message.replyToSenderName == connector.selfName;
    final replyText = message.replyToText ?? '';
    final colorScheme = Theme.of(context).colorScheme;
    final previewTextColor = colorScheme.onSurface.withValues(alpha: 0.7);

    final gifId = GifHelper.parseGif(replyText);
    final poi = parseMarkerText(replyText);
    final mcoImageMetadata = MCOImageMessage.decodeMetadata(replyText);
    final mcoImage = mcoImageMetadata.image;
    final unsupportedMcoImageVersion = mcoImageMetadata.unsupportedVersion;

    Widget contentPreview;
    if (gifId != null) {
      contentPreview = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: GifMessage(
          url: 'https://media.giphy.com/media/$gifId/giphy.gif',
          backgroundColor: colorScheme.surfaceContainerHighest,
          fallbackTextColor: previewTextColor,
          maxSize: 80,
        ),
      );
    } else if (poi != null) {
      contentPreview = Row(
        children: [
          Icon(Icons.location_on_outlined, size: 14, color: previewTextColor),
          const SizedBox(width: 4),
          Text(
            context.l10n.chat_location,
            style: TextStyle(fontSize: 12 * textScale, color: previewTextColor),
          ),
        ],
      );
    } else if (mcoImage != null) {
      contentPreview = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: MCOImageMessage(image: mcoImage, maxSize: 80),
      );
    } else if (unsupportedMcoImageVersion != null) {
      contentPreview = _buildUnsupportedMcoImageMessage(
        context,
        unsupportedMcoImageVersion,
        mcoImageMetadata.currentMaxSupportedVersion,
        textScale,
      );
    } else {
      contentPreview = Text(
        replyText,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12 * textScale,
          color: previewTextColor,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return GestureDetector(
      onTap:
          (message.replyToMessageId == null &&
              message.replyToSenderName == null &&
              message.replyToText == null)
          ? null
          : () => _scrollToReplyTarget(message),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(MeshRadii.sm),
          border: Border(
            left: BorderSide(color: colorScheme.primary, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.chat_replyTo(message.replyToSenderName ?? ''),
              style: TextStyle(
                fontSize: 11 * textScale,
                fontWeight: FontWeight.bold,
                color: isOwnNode ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            contentPreview,
          ],
        ),
      ),
    );
  }

  Widget _buildReactionsDisplay(ChannelMessage message) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: message.reactions.entries.map((entry) {
        final emoji = entry.key;
        final count = entry.value;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(MeshRadii.pill),
            border: Border.all(color: scheme.outlineVariant, width: 1),
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
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPoiMessage(
    BuildContext context,
    MarkerPayload poi,
    bool isOutgoing,
    double textScale,
    String senderName, {
    Widget? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textColor = isOutgoing ? MeshPalette.meInk : scheme.onSurface;
    final metaColor = textColor.withValues(alpha: 0.7);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.location_on_outlined, color: scheme.primary),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () {
            final selfName = context.read<MeshCoreConnector>().selfName ?? 'Me';
            final fromName = isOutgoing ? selfName : senderName;
            final key = buildSharedMarkerKey(
              sourceId: 'channel:${widget.channel.index}',
              label: poi.label,
              fromName: fromName,
              flags: poi.flags,
              isChannel: true,
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
                context.l10n.chat_poiShared,
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
          maxBinaryPayloadBytes: ChannelBinaryDataHelper.canSend
              ? _maxChannelBinaryPayloadBytes(
                  context.read<AppSettingsService>().settings,
                )
              : null,
          binarySenderName: context.read<MeshCoreConnector>().selfName,
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
    await _sendMessage(
      skipTranslation: true,
      skipReplyContext: true,
      mcoImageV3: result.mcoImageV3,
    );
  }

  Future<void> _showMcoImageGallery(int maxTextChars) async {
    final result = await showModalBottomSheet<MCOImageGalleryResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const MCOImageGalleryScreen(),
    );
    if (result == null || !mounted) return;
    if (result.action == MCOImageGalleryAction.edit) {
      await _openGalleryItemInCanvas(maxTextChars, result.item);
      return;
    }
    await _sendGalleryItem(result.item);
  }

  Future<void> _openGalleryItemInCanvas(
    int maxTextChars,
    MCOImageGalleryItem item,
  ) async {
    final image = item.showPngFallback ? null : item.tryDecodeImage();
    await _showCanvasEditor(
      maxTextChars,
      initialImage: image,
      initialImageBytes: image == null ? item.pngBytes : null,
      initialImageWidth: item.width,
      initialImageHeight: item.height,
      initialPaletteProfile: item.paletteProfile,
    );
  }

  Future<void> _sendGalleryItem(MCOImageGalleryItem item) async {
    final connector = context.read<MeshCoreConnector>();
    final settings = context.read<AppSettingsService>().settings;
    final text = item.textPayload;
    final binaryPayloadBytes = _channelBinaryPayloadBytes(connector, text);
    final payloadBytes =
        binaryPayloadBytes ??
        utf8
            .encode(
              connector.prepareChannelOutboundText(widget.channel.index, text),
            )
            .length;
    final maxBytes = binaryPayloadBytes == null
        ? _maxChannelInputBytes(connector, settings)
        : _maxChannelBinaryPayloadBytes(settings);
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
    await _sendMessage(skipTranslation: true, skipReplyContext: true);
  }

  Widget _buildAvatar(String senderName) {
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

  Widget _buildReplyBanner(double textScale) {
    final message = _replyingToMessage!;
    final scheme = Theme.of(context).colorScheme;
    final mcoImageMetadata = MCOImageMessage.decodeMetadata(message.text);
    final mcoImage = mcoImageMetadata.image;
    final unsupportedMcoImageVersion = mcoImageMetadata.unsupportedVersion;
    final previewTextColor = scheme.onSecondaryContainer.withValues(alpha: 0.7);

    Widget preview;
    if (mcoImage != null) {
      preview = LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          const maxHeight = 70.0;
          final aspectRatio = mcoImage.width / mcoImage.height;
          var width = maxWidth;
          var height = width / aspectRatio;
          if (height > maxHeight) {
            height = maxHeight;
            width = height * aspectRatio;
          }
          return Align(
            alignment: Alignment.centerLeft,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: width,
                height: height,
                child: MCOImageMessage(
                  image: mcoImage,
                  maxSize: width > height ? width : height,
                ),
              ),
            ),
          );
        },
      );
    } else if (unsupportedMcoImageVersion != null) {
      preview = _buildUnsupportedMcoImageMessage(
        context,
        unsupportedMcoImageVersion,
        mcoImageMetadata.currentMaxSupportedVersion,
        textScale,
      );
    } else {
      preview = Text(
        message.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11 * textScale, color: previewTextColor),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.reply, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.chat_replyingTo(message.senderName),
                  style: MeshTheme.mono(
                    fontSize: 11 * textScale,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                preview,
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: _cancelReply,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageComposer() {
    final connector = context.watch<MeshCoreConnector>();
    final settings = context.watch<AppSettingsService>().settings;
    final scheme = Theme.of(context).colorScheme;
    final maxBytes = _maxChannelComposerBytes(connector, settings);
    final mediaQuery = MediaQuery.of(context);
    final replyBannerHeight = _replyingToMessage != null
        ? (MCOImageMessage.decodeMetadata(_replyingToMessage!.text).image !=
                  null
              ? 106.0
              : 64.0)
        : 0.0;
    final maxInputHeight =
        (mediaQuery.size.height -
                mediaQuery.padding.top -
                kToolbarHeight -
                mediaQuery.viewInsets.bottom -
                replyBannerHeight -
                48)
            .clamp(56.0, 240.0)
            .toDouble();
    final usesChannelEncoding =
        connector.isChannelMcmpEnabled(widget.channel.index) ||
        connector.isChannelSmazEnabled(widget.channel.index) ||
        connector.isChannelCyr2LatEnabled(widget.channel.index);

    String encodeComposerText(String text) {
      final sendText = _applyReplyMention(text);
      final binaryPayloadBytes = _channelBinaryPayloadBytes(
        connector,
        sendText,
      );
      if (binaryPayloadBytes != null) {
        return _byteCountPlaceholder(binaryPayloadBytes);
      }
      return usesChannelEncoding
          ? connector.prepareChannelOutboundText(widget.channel.index, sendText)
          : sendText;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyingToMessage != null)
          Builder(
            builder: (context) {
              final textScale = context.select<ChatTextScaleService, double>(
                (service) => service.scale,
              );
              return _buildReplyBanner(textScale);
            },
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              top: BorderSide(color: scheme.outlineVariant, width: 1),
            ),
          ),
          child: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ChatComposerSideAction(
                  child: ChatAdditionalActionsButton(
                    canvasActive: settings.canvasActive,
                    onSendSelfContact: () => _insertSelfContact(connector),
                    onSendMyLocation: () =>
                        unawaited(_insertMyLocation(connector)),
                    onSendContact: () => _pickAndInsertContact(),
                    onPickLocationFromMap: () =>
                        unawaited(_pickAndInsertLocationFromMap()),
                    onSendGif: () => _showGifPicker(context),
                    onOpenCanvas: () => _showCanvasEditor(maxBytes),
                    onOpenMcoImageGallery: () =>
                        _showMcoImageGallery(maxBytes),
                  ),
                ),
                if (settings.translationEnabled)
                  MessageTranslationButton(
                    enabled: settings.composerTranslationEnabled,
                    languageCode: settings.translationTargetLanguageCode,
                    onPressed: _showTranslationOptions,
                  ),
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _textController,
                    builder: (context, value, child) {
                      final gifId = GifHelper.parseGif(value.text);
                      if (gifId != null) {
                        return Focus(
                          autofocus: true,
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent &&
                                (event.logicalKey == LogicalKeyboardKey.enter ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.numpadEnter)) {
                              _sendMessage();
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
                                        scheme.surfaceContainerHighest,
                                    fallbackTextColor: scheme.onSurface
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
                        maxHeight: maxInputHeight,
                        hintText: context.l10n.chat_typeMessage,
                        onSubmitted: (_) => _sendMessage(),
                        extraFormatters:
                            connector.isChannelMcmpEnabled(widget.channel.index)
                            ? [
                                NewlineToSpaceFormatter(
                                  maxInsertedChars: settings.mcmpTextLimit,
                                ),
                              ]
                            : const [],
                        encoder:
                            _replyingToMessage != null || usesChannelEncoding
                            ? encodeComposerText
                            : null,
                        decoration: InputDecoration(
                          hintText: context.l10n.chat_typeMessage,
                          hintMaxLines: 1,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          filled: true,
                          fillColor: scheme.surfaceContainerLow,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 6),
                ChatComposerSideAction(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _textController,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty;
                      return GestureDetector(
                        onLongPress: _showQuickAnswersPicker,
                        onSecondaryTap: _showQuickAnswersPicker,
                        child: IconButton.filled(
                          icon: const Icon(Icons.send, size: 20),
                          tooltip: context.l10n.chat_sendMessage,
                          style: IconButton.styleFrom(
                            backgroundColor: hasText
                                ? scheme.primary
                                : scheme.surfaceContainerHighest,
                            foregroundColor: hasText
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                            minimumSize: const Size(40, 40),
                            shape: const CircleBorder(),
                          ),
                          onPressed: hasText
                              ? () {
                                  HapticFeedback.lightImpact();
                                  _sendMessage();
                                }
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _applyReplyMention(String text) {
    final replyingTo = _replyingToMessage;
    if (replyingTo == null) return text;
    return '@[${replyingTo.senderName}] $text';
  }

  Future<void> _showQuickAnswersPicker() async {
    final connector = context.read<MeshCoreConnector>();
    final selectedAnswerIds = await connector.loadChannelQuickAnswerIds(
      widget.channel.index,
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
      await _sendMessage(quickAnswerText: answer.text);
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

  Future<void> _sendMessage({
    String? quickAnswerText,
    bool skipTranslation = false,
    bool skipReplyContext = false,
    EncodedMCOImageV3? mcoImageV3,
  }) async {
    final rawText = quickAnswerText ?? _textController.text;
    final text = quickAnswerText == null ? rawText.trim() : rawText;
    if (text.trim().isEmpty) return;

    final now = DateTime.now();
    if (_lastChannelSendAt != null &&
        now.difference(_lastChannelSendAt!) < const Duration(seconds: 1)) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.chat_sendCooldown),
      );
      return;
    }
    _lastChannelSendAt = now;

    final connector = context.read<MeshCoreConnector>();
    final settings = context.read<AppSettingsService>().settings;
    final translationService = context.read<TranslationService>();

    String messageText = text;
    String? originalText;
    String? translatedLanguageCode;
    String? translationModelId;
    if (settings.translationEnabled && !skipTranslation) {
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
          messageText = result.translatedText;
          originalText = text;
          translatedLanguageCode = result.targetLanguageCode;
          translationModelId = result.modelId;
        }
      }
    }
    if (!skipReplyContext) {
      messageText = _applyReplyMention(messageText);
    }
    final compressionSourceText = messageText;

    final outboundText = connector.prepareChannelOutboundText(
      widget.channel.index,
      messageText,
    );
    final textPayloadBytes = utf8.encode(outboundText).length;
    final binaryPayloadBytes = _channelBinaryPayloadBytes(
      connector,
      messageText,
    );
    final payloadBytes = binaryPayloadBytes ?? textPayloadBytes;
    final maxBytes = binaryPayloadBytes == null
        ? _maxChannelInputBytes(connector, settings)
        : _maxChannelBinaryPayloadBytes(settings);
    if (payloadBytes > maxBytes) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.chat_messageTooLong(maxBytes)),
      );
      return;
    }

    // When messageText is transformed with cyr2lat, it (generally) hasn't visual differences,
    // but we getting messages doubles in chat screen (source text and transformed).
    // To prevent, we'll perform transform of source before pass to main sender logic.
    // We can pass whole text, senderName will be kept intact
    if (connector.isChannelCyr2LatEnabled(widget.channel.index) &&
        // Shared contact payloads must stay untouched.
        parseSharedContactText(messageText) == null) {
      messageText = Cyr2Lat.encode(messageText);
    }
    // end transform

    // store last sended msg to resend mechanism
    _lastChannelSentText = messageText;

    final replyTarget = skipReplyContext ? null : _replyingToMessage;
    if (quickAnswerText == null) {
      _textController.clear();
      _textFieldFocusNode.requestFocus();
    }
    _cancelReply();
    if (settings.sendingDelayForCancellationSeconds > 0 &&
        connector.isChannelSendingDelayEnabled(widget.channel.index)) {
      connector.scheduleChannelMessage(
        widget.channel,
        messageText,
        inputText: text,
        uncompressedText: compressionSourceText,
        delaySeconds: settings.sendingDelayForCancellationSeconds,
        originalText: originalText,
        translatedLanguageCode: translatedLanguageCode,
        translationModelId: translationModelId,
        replyToMessageId: replyTarget?.messageId,
        replyToSenderName: replyTarget?.senderName,
        replyToText: replyTarget?.text,
        // Prefer the timestamp transmitted in the quoted MCMP body: for
        // binary transports the outer timestamp is receiver-local and would
        // not resolve on other devices.
        replyToTimestamp: replyTarget == null
            ? null
            : replyTarget.mcmpTimestamp ??
                  replyTarget.timestamp.millisecondsSinceEpoch ~/ 1000,
      );
    } else {
      connector.sendChannelMessage(
        widget.channel,
        messageText,
        mcoImageV3: mcoImageV3,
        uncompressedText: compressionSourceText,
        originalText: originalText,
        translatedLanguageCode: translatedLanguageCode,
        translationModelId: translationModelId,
        replyToMessageId: replyTarget?.messageId,
        replyToSenderName: replyTarget?.senderName,
        replyToText: replyTarget?.text,
        // Prefer the timestamp transmitted in the quoted MCMP body: for
        // binary transports the outer timestamp is receiver-local and would
        // not resolve on other devices.
        replyToTimestamp: replyTarget == null
            ? null
            : replyTarget.mcmpTimestamp ??
                  replyTarget.timestamp.millisecondsSinceEpoch ~/ 1000,
      );
    }
  }

  void _cancelPendingChannelSend(
    MeshCoreConnector connector,
    String messageId,
  ) {
    final text = connector.cancelPendingChannelSend(messageId);
    if (text == null) return;
    _textController.text = text;
    _textController.selection = TextSelection.collapsed(offset: text.length);
    _textFieldFocusNode.requestFocus();
  }

  int _maxChannelComposerBytes(
    MeshCoreConnector connector,
    AppSettings settings,
  ) {
    if (ChannelBinaryDataHelper.canSend &&
        connector.isChannelMcmpEnabled(widget.channel.index)) {
      return _maxChannelBinaryPayloadBytes(settings);
    }
    return _maxChannelInputBytes(connector, settings);
  }

  int _maxChannelBinaryPayloadBytes(AppSettings settings) {
    final outgoingLimit = settings.channelMaxbytesOutgoing;
    if (outgoingLimit > 0) {
      return math.min(maxChannelDataLength, outgoingLimit);
    }
    return maxChannelDataLength;
  }

  int? _channelBinaryPayloadBytes(MeshCoreConnector connector, String text) {
    if (!ChannelBinaryDataHelper.canSend) return null;
    final senderName = connector.selfName ?? 'Me';
    final imagePayloadBytes = ChannelBinaryDataHelper.mcoImagePayloadLength(
      text,
      senderName,
    );
    if (imagePayloadBytes != null) return imagePayloadBytes;
    if (!connector.isChannelMcmpEnabled(widget.channel.index)) return null;
    if (connector.channelMcmpVersion(widget.channel.index) == 3) {
      return ChannelBinaryDataHelper.mcmpV3AppPayloadLength(
        text,
        senderName,
        includeSignature: connector.channelMcmpUseSign(widget.channel.index),
      );
    }
    return ChannelBinaryDataHelper.mcmpPayloadLength(text, senderName);
  }

  Future<void> _confirmClearChat() async {
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
      if (!mounted) return;
      context.read<MeshCoreConnector>().clearMessagesForChannel(
        widget.channel.index,
      );
    }
  }

  String _byteCountPlaceholder(int bytes) => List.filled(bytes, 'x').join();

  int _maxChannelInputBytes(MeshCoreConnector connector, AppSettings settings) {
    var limit = maxChannelMessageBytes(connector.selfName);
    final outgoingLimit = settings.channelMaxbytesOutgoing;
    if (outgoingLimit > 0) {
      // This user limit counts "<sender>: " plus the message bytes.
      final textLimit = outgoingLimit - _channelSenderPrefixBytes(connector);
      limit = math.min(limit, math.max(0, textLimit));
    }
    if (connector.isChannelMcmpEnabled(widget.channel.index)) {
      return math.max(0, limit - 2);
    }
    return limit;
  }

  int _channelSenderPrefixBytes(MeshCoreConnector connector) {
    final senderName = connector.selfName;
    final nameBytes = senderName == null || senderName.isEmpty
        ? maxNameSize - 1
        : math.min(utf8.encode(senderName).length, maxNameSize - 1);
    return nameBytes + 2; // "<name>: "
  }

  String _formatTime(
    BuildContext context,
    DateTime time, {
    required bool enableSeconds,
  }) {
    final now = DateTime.now();
    final diff = now.difference(time);
    final locale = Localizations.localeOf(context).toString();
    if (locale != _cachedFormatLocale) {
      _cachedFormatLocale = locale;
      _hmFormat = DateFormat.Hm(locale);
      _hmsFormat = DateFormat.Hms(locale);
      _mdFormat = DateFormat.Md(locale);
    }
    final hm = enableSeconds ? _hmsFormat.format(time) : _hmFormat.format(time);

    if (diff.inDays > 0) {
      return '${_mdFormat.format(time)} $hm';
    } else {
      return hm;
    }
  }

  int? _outgoingRadioWaitSeconds(ChannelMessage message) {
    if (!message.isOutgoing || message.sentByRadioAt == null) return null;
    final waitSeconds = message.sentByRadioAt!
        .difference(message.timestamp)
        .inSeconds;
    return waitSeconds < 0 ? 0 : waitSeconds;
  }

  void _showMessagePathInfo(ChannelMessage message) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ChannelMessagePathScreen(message: message, channelMessage: true),
      ),
    );
  }

  Future<void> _showMessageActions(ChannelMessage message) async {
    final translationService = context.read<TranslationService>();
    final mcoImage = MCOImageMessage.tryDecode(message.text);
    final hasMcoOriginal = mcoImage == null
        ? false
        : await McoImagePackOriginals.instance.hasOriginalForText(
            message.text,
          );
    if (!mounted) return;
    final settings = context.read<AppSettingsService>().settings;
    final canTranslateMessage =
        translationService.canTranslateIncoming(
          text: message.text,
          isCli: false,
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
                ListTile(
                  leading: const Icon(Icons.reply),
                  title: Text(context.l10n.chat_reply),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _setReplyingTo(message);
                  },
                ),
                if (PlatformInfo.isDesktop)
                  ListTile(
                    leading: const Icon(Icons.route),
                    title: Text(context.l10n.chat_path),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showMessagePathInfo(message);
                    },
                  ),
                // Can't react to your own messages
                if (!message.isOutgoing)
                  ListTile(
                    leading: const Icon(Icons.add_reaction_outlined),
                    title: Text(context.l10n.chat_addReaction),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showEmojiPicker(message);
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
                if (canTranslateMessage)
                  ListTile(
                    leading: const Icon(Icons.translate),
                    title: Text(context.l10n.translation_translateMessage),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(
                        context
                            .read<MeshCoreConnector>()
                            .translateChannelMessage(
                              widget.channel.index,
                              message,
                              manualTranslation: true,
                            ),
                      );
                    },
                  ),
                if (message.isOutgoing)
                  ListTile(
                    leading: const Icon(Icons.send_outlined),
                    title: Text(context.l10n.common_retry),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _resendMessage(message);
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
                if (!message.isOutgoing &&
                    message.mcmpIsSigned &&
                    message.mcmpSignature != null)
                  ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: Text(context.l10n.chat_mcmpManualRecheckSign),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_recheckMessageSignature(message));
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.route_outlined),
                  title: Text(context.l10n.channels_copyPath),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_copyMessagePath(message));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(context.l10n.channels_copyPathExtended),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_copyMessagePath(message, extended: true));
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
                      final maxBytes = _maxChannelInputBytes(
                        connector,
                        settings,
                      );
                      Navigator.pop(sheetContext);
                      unawaited(
                        _showCanvasEditor(maxBytes, initialImage: mcoImage),
                      );
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

  void _showEmojiPicker(ChannelMessage message) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => EmojiPicker(
        onEmojiSelected: (emoji) {
          _sendReaction(message, emoji);
        },
      ),
    );
  }

  void _sendReaction(ChannelMessage message, String emoji) {
    final connector = context.read<MeshCoreConnector>();
    final emojiIndex = ReactionHelper.emojiToIndex(emoji);
    if (emojiIndex == null) return; // Unknown emoji, skip
    final timestampSecs = message.timestamp.millisecondsSinceEpoch ~/ 1000;
    final hash = ReactionHelper.computeReactionHash(
      timestampSecs,
      message.senderName,
      message.text,
    );
    final reactionText = ReactionHelper.encodeReaction(hash, emojiIndex);
    connector.sendChannelMessage(widget.channel, reactionText);
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
    } catch (error) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(error.toString()),
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

  Future<void> _copyMessagePath(
    ChannelMessage message, {
    bool extended = false,
  }) async {
    try {
      final pathText = _messagePathText(message, extended: extended);
      await Clipboard.setData(ClipboardData(text: pathText));
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.channels_copiedPath),
      );
    } catch (_) {
      if (!mounted) return;
      final colorScheme = Theme.of(context).colorScheme;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.channels_copyPathFailed),
        backgroundColor: colorScheme.errorContainer,
      );
    }
  }

  Future<void> _deleteMessage(ChannelMessage message) async {
    await context.read<MeshCoreConnector>().deleteChannelMessage(message);
    if (!mounted) return;
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.chat_messageDeleted),
    );
  }

  Future<void> _addSharedContact(SharedContactInfo contact) async {
    final connector = context.read<MeshCoreConnector>();
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

  Future<void> _recheckMessageSignature(ChannelMessage message) async {
    final connector = context.read<MeshCoreConnector>();
    final status = await connector.recheckChannelMessageSignature(
      widget.channel.index,
      message.messageId,
    );
    if (!mounted || status == null) return;
    showDismissibleSnackBar(
      context,
      content: Text(McmpSignatureBadge.statusLabel(context, status)),
    );
  }

  void _resendMessage(ChannelMessage message) {
    final remainingSeconds = _remainingResendWaitSeconds(message);
    if (remainingSeconds != null) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.chat_retryingMessageWait(remainingSeconds)),
      );
      return;
    }

    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    _lastChannelSendAt = DateTime.now();
    _lastChannelSentText = message.text;
    final mcoImageV3 = _mcoImageV3ForResend(message.text);
    connector.sendChannelMessage(
      widget.channel,
      message.text,
      mcoImageV3: mcoImageV3,
      originalText: message.originalText,
      translatedLanguageCode: message.translatedLanguageCode,
      translationModelId: message.translationModelId,
      replyToMessageId: message.replyToMessageId,
      replyToSenderName: message.replyToSenderName,
      replyToText: message.replyToText,
      // Keep the reply anchor on manual resend (metadata is rebuilt and the
      // message re-signed, but the quoted target stays the same).
      replyToTimestamp: message.mcmpReplyTimestamp,
    );
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.chat_retryingMessage),
    );
  }

  EncodedMCOImageV3? _mcoImageV3ForResend(String text) {
    final trimmedLeft = text.trimLeft();
    if (!MCOImageV3Codec.isTextPayload(trimmedLeft)) {
      return null;
    }
    try {
      final body = MCOImageV3Codec.bodyFromText(trimmedLeft);
      final payloadInfo = MCOImageV3Codec.inspectText(trimmedLeft);
      final candidate = EncodedMCOImage(
        payload: body,
        text: trimmedLeft,
        mode: ImageMode.extended,
        scan: ScanMode.h,
        byteLength: body.length,
        charLength: trimmedLeft.length,
        codecVersion: MCOImageV3Codec.version,
        requestedEncodingVersion: MCOImageEncodingVersion.v3,
        actualEncodingVersion: MCOImageEncodingVersion.v3,
        paletteKind: 'v3',
        container: payloadInfo?.algorithm ?? 'v3',
      );
      return EncodedMCOImageV3(
        body: body,
        byteLength: body.length,
        encodedCandidate: candidate,
      );
    } on MCOImageCodecException {
      return null;
    }
  }

  int? _remainingResendWaitSeconds(ChannelMessage message) {
    final resendTimeoutSeconds = context
        .read<AppSettingsService>()
        .settings
        .channelResendTimeoutSeconds;
    final resendTimeout = Duration(seconds: resendTimeoutSeconds);
    final now = DateTime.now();
    var maxRemainingMs = 0;

    final messageElapsed = now.difference(message.timestamp);
    if (!messageElapsed.isNegative && messageElapsed < resendTimeout) {
      maxRemainingMs = math.max(
        maxRemainingMs,
        resendTimeout.inMilliseconds - messageElapsed.inMilliseconds,
      );
    }

    final lastSentAt = _lastChannelSendAt;
    if (lastSentAt != null && _lastChannelSentText == message.text) {
      final lastSendElapsed = now.difference(lastSentAt);
      if (!lastSendElapsed.isNegative && lastSendElapsed < resendTimeout) {
        maxRemainingMs = math.max(
          maxRemainingMs,
          resendTimeout.inMilliseconds - lastSendElapsed.inMilliseconds,
        );
      }
    }

    if (maxRemainingMs <= 0) return null;
    return ((maxRemainingMs + 999) ~/ 1000).clamp(1, resendTimeoutSeconds);
  }

  String _formatPathPrefixes(Uint8List pathBytes, int pathHashByteWidth) {
    return PathHelper.splitPathBytes(
      pathBytes,
      pathHashByteWidth,
    ).map(PathHelper.formatHopHex).join(', ');
  }

  int _displayHopCount(
    Uint8List pathBytes,
    int pathHashByteWidth,
    int? storedHopCount,
  ) {
    if (pathBytes.isEmpty) {
      return storedHopCount ?? 0;
    }
    return PathHelper.splitPathBytes(pathBytes, pathHashByteWidth).length;
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

  String _messagePathText(ChannelMessage message, {bool extended = false}) {
    final pathBytes = message.pathBytes.isNotEmpty
        ? message.pathBytes
        : (message.pathVariants.isNotEmpty
              ? message.pathVariants.first
              : Uint8List(0));
    if (pathBytes.isEmpty) return 'Direct';
    final pathHashWidth =
        message.pathHashWidth ??
        context.read<MeshCoreConnector>().pathHashByteWidth;
    final hops = PathHelper.splitPathBytes(pathBytes, pathHashWidth);
    if (!extended) {
      return hops.map(PathHelper.formatHopHex).join(', ');
    }
    return _extendedMessagePathText(hops, pathHashWidth, message.senderName);
  }

  String _extendedMessagePathText(
    List<Uint8List> hops,
    int pathHashWidth,
    String senderName,
  ) {
    final connector = context.read<MeshCoreConnector>();
    final contactsByPrefix = <String, List<Contact>>{};
    final width = pathHashWidth.clamp(1, 4).toInt();
    final messageSenderName = senderName.trim();

    for (final contact in connector.allContacts) {
      if (contact.publicKey.isEmpty) continue;
      if (contact.type != advTypeRepeater && contact.type != advTypeRoom) {
        continue;
      }
      final keyBytes = contact.publicKey.sublist(
        0,
        math.min(width, contact.publicKey.length),
      );
      final key = PathHelper.formatHopHex(keyBytes);
      contactsByPrefix.putIfAbsent(key, () => []).add(contact);
    }

    for (final contacts in contactsByPrefix.values) {
      contacts.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    }
    final collidedPrefixes = contactsByPrefix.entries
        .where((entry) => entry.value.length > 1)
        .map((entry) => entry.key)
        .toSet();
    final settings = context.read<AppSettingsService>().settings;
    final template = settings.copyMsgPathTemplate;
    final finalTemplate = settings.copyMsgPathFinalTemplate;

    final pathText = hops.asMap().entries.map((entry) {
      final hopIndex = entry.key + 1;
      final hop = entry.value;
      final isLastHop = entry.key == hops.length - 1;
      final prefix = PathHelper.formatHopHex(hop);
      final candidates = contactsByPrefix[prefix];
      final contact = candidates == null || candidates.isEmpty
          ? null
          : candidates.removeAt(0);
      final contactName = contact?.name.trim() ?? '';
      final name = contactName.isEmpty || contactName.toLowerCase() == 'unknown'
          ? '-'
          : contactName;
      final collisionMarker = collidedPrefixes.contains(prefix) ? '!' : '';
      return _applyMessagePathTemplate(
        template,
        hopKey: prefix,
        hopName: name,
        hopIndex: hopIndex,
        hopCount: hops.length,
        senderName: messageSenderName,
        collisionMarker: collisionMarker,
        divider: isLastHop ? '' : '\n',
      );
    }).join();
    return _applyMessagePathFinalTemplate(
      finalTemplate,
      path: pathText,
      hopCount: hops.length,
      senderName: messageSenderName,
    );
  }

  String _applyMessagePathTemplate(
    String template, {
    required String hopKey,
    required String hopName,
    required int hopIndex,
    required int hopCount,
    required String senderName,
    required String collisionMarker,
    required String divider,
  }) {
    return template
        .replaceAll('%hopKey%', hopKey)
        .replaceAll('%hopName%', hopName)
        .replaceAll('%hopInd%', hopIndex.toString())
        .replaceAll('%hops%', hopCount.toString())
        .replaceAll('%senderName%', senderName)
        .replaceAll('%collisionMarker%', collisionMarker)
        .replaceAll('%div%', divider)
        .replaceAll(r'\n', '\n');
  }

  String _applyMessagePathFinalTemplate(
    String template, {
    required String path,
    required int hopCount,
    required String senderName,
  }) {
    return template
        .replaceAll('%path%', path)
        .replaceAll('%hops%', hopCount.toString())
        .replaceAll('%senderName%', senderName)
        .replaceAll(r'\n', '\n');
  }

  Future<void> openRegionSelectDialog(Channel channel) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) => _RegionSelectDialog(channel: channel),
    );
    if (!mounted) return;
    await _connector?.loadChannelSettings();
    if (!mounted) return;
    setState(() {
      region = _connector?.getChannelRegion(channel.index) ?? '';
    });
  }
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

class _RegionSelectDialog extends StatefulWidget {
  final Channel channel;

  const _RegionSelectDialog({required this.channel});

  @override
  State<_RegionSelectDialog> createState() => _RegionSelectDialogState();
}

class _RegionSelectDialogState extends State<_RegionSelectDialog> {
  final RegionStore regionStore = RegionStore();

  List<Region> regions = [];
  int selectedIndex = -1;

  @override
  void initState() {
    super.initState();
    loadRegions();
  }

  void loadRegions() {
    setState(() {
      regions = regionStore.loadRegions();
      final channelRegion = context.read<MeshCoreConnector>().getChannelRegion(
        widget.channel.index,
      );
      selectedIndex = regions.indexOf(channelRegion);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppBar(
              backgroundColor: Colors.transparent,
              title: AdaptiveAppBarTitle(
                context.l10n.channels_regionSelect_Title,
              ),
              centerTitle: true,
              actions: [
                IconButton(
                  tooltip: context.l10n.channels_clearRegion,
                  icon: const Icon(Icons.backspace_outlined),
                  onPressed: () {
                    context.read<MeshCoreConnector>().setChannelRegion(
                      widget.channel.index,
                      '',
                    );
                    Navigator.pop(context);
                  },
                ),
                IconButton(
                  tooltip: context.l10n.settings_regionSettingsSubtitle,
                  icon: const Icon(Icons.settings),
                  onPressed: () async {
                    await pushRegionManagementScreen(context);
                    if (!mounted) return;
                    loadRegions();
                  },
                ),
              ],
            ),
            const SizedBox(height: 15),
            Expanded(
              child: ListView.builder(
                itemCount: regions.length,
                itemBuilder: (context, index) => ListTile(
                  title: Text(regions[index]),
                  tileColor: selectedIndex == index
                      ? Colors.blue.withValues(alpha: 0.2)
                      : null,
                  onTap: () {
                    context.read<MeshCoreConnector>().setChannelRegion(
                      widget.channel.index,
                      regions[index],
                    );
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeReplyBubble extends StatefulWidget {
  final double maxSwipeOffset;
  final double replySwipeThreshold;
  final VoidCallback onReplyTriggered;
  final Widget Function({required bool isStart}) hintBuilder;
  final Widget child;

  const _SwipeReplyBubble({
    required this.maxSwipeOffset,
    required this.replySwipeThreshold,
    required this.onReplyTriggered,
    required this.hintBuilder,
    required this.child,
  });

  @override
  State<_SwipeReplyBubble> createState() => _SwipeReplyBubbleState();
}

class _SwipeReplyBubbleState extends State<_SwipeReplyBubble> {
  Offset? _swipeStartPosition;
  double _swipeOffset = 0;
  double _maxSwipeDistance = 0;
  int? _swipePointerId;
  bool _swipeLockedToHorizontal = false;

  void _handleSwipeStart(Offset position) {
    _swipeStartPosition = position;
    _maxSwipeDistance = 0;
    if (_swipeOffset != 0) {
      setState(() => _swipeOffset = 0);
    }
  }

  void _handleSwipePointerDown(PointerDownEvent event) {
    _swipePointerId = event.pointer;
    _swipeLockedToHorizontal = false;
    _handleSwipeStart(event.position);
  }

  void _handleSwipePointerMove(PointerMoveEvent event) {
    if (_swipePointerId != event.pointer || _swipeStartPosition == null) {
      return;
    }

    final dx = event.position.dx - _swipeStartPosition!.dx;

    const axisLockThreshold = 12.0;
    if (!_swipeLockedToHorizontal) {
      if (-dx < axisLockThreshold) {
        return;
      }
      _swipeLockedToHorizontal = true;
    }

    _handleSwipeUpdate(event.position);
  }

  void _handleSwipeUpdate(Offset position) {
    if (_swipeStartPosition == null) return;

    final dx = position.dx - _swipeStartPosition!.dx;
    if (dx >= 0) return;

    if (-dx < 6) return;

    if (-dx > _maxSwipeDistance) {
      _maxSwipeDistance = -dx;
    }

    final double clamped = dx.clamp(-widget.maxSwipeOffset, 0.0).toDouble();
    final adjusted = _applySwipeResistance(clamped, widget.maxSwipeOffset);
    if (adjusted != _swipeOffset) {
      setState(() => _swipeOffset = adjusted);
    }
  }

  void _handleSwipePointerUp(Offset position) {
    if (_swipeLockedToHorizontal && _swipeStartPosition != null) {
      final dx = position.dx - _swipeStartPosition!.dx;
      final peak = math.max(
        _maxSwipeDistance,
        (-dx).clamp(0.0, double.infinity),
      );
      if (peak >= widget.replySwipeThreshold) {
        widget.onReplyTriggered();
        HapticFeedback.selectionClick();
      }
    }
    _resetSwipe();
  }

  void _resetSwipe() {
    if (_swipeOffset != 0) {
      setState(() => _swipeOffset = 0);
    }
    _swipeStartPosition = null;
    _maxSwipeDistance = 0;
    _swipePointerId = null;
    _swipeLockedToHorizontal = false;
  }

  double _applySwipeResistance(double rawOffset, double maxOffset) {
    final abs = rawOffset.abs();
    if (abs <= 0) return 0;
    final norm = (abs / maxOffset).clamp(0.0, 1.0);
    const deadZone = 0.18;
    if (norm <= deadZone) {
      return rawOffset.sign * maxOffset * (norm * 0.08);
    }
    final t = ((norm - deadZone) / (1 - deadZone)).clamp(0.0, 1.0);
    final curved = t < 0.5
        ? 16 * math.pow(t, 5)
        : 1 - math.pow(-2 * t + 2, 5) / 2;
    const deadZoneEnd = 0.0144;
    return rawOffset.sign *
        maxOffset *
        (deadZoneEnd + curved * (1 - deadZoneEnd));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handleSwipePointerDown,
      onPointerMove: _handleSwipePointerMove,
      onPointerUp: (event) => _handleSwipePointerUp(event.position),
      onPointerCancel: (_) => _resetSwipe(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: _swipeOffset.abs() / widget.maxSwipeOffset,
                child: widget.hintBuilder(isStart: false),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              transform: Matrix4.translationValues(_swipeOffset, 0, 0),
              curve: Curves.easeOut,
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}

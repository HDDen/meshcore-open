import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meshcore_open/storage/channel_message_store.dart';
import 'package:meshcore_open/utils/keys.dart';
import 'package:meshcore_open/utils/platform_info.dart';
import 'package:meshcore_open/widgets/app_bar.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/chat_keyboard_navigation_history.dart';
import '../l10n/l10n.dart';
import '../services/app_settings_service.dart';
import '../services/ui_view_state_service.dart';
import '../models/app_settings.dart';
import '../models/channel.dart';
import '../models/channel_group.dart';
import '../models/community.dart';
import '../models/contact.dart';
import '../connector/meshcore_protocol.dart';
import '../storage/channel_group_store.dart';
import '../storage/community_store.dart';
import '../theme/mesh_theme.dart';
import '../utils/dialog_utils.dart';
import '../utils/disconnect_navigation_mixin.dart';
import '../utils/route_transitions.dart';
import '../widgets/list_filter_widget.dart';
import '../widgets/mco_image_message.dart';
import '../widgets/channel_widget_color_picker.dart';
import '../widgets/channel_edit_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/qr_code_display.dart';
import '../widgets/quick_switch_bar.dart';
import '../widgets/popup_menu_row.dart';
import '../widgets/sync_progress_overlay.dart';
import '../widgets/unread_badge.dart';
import '../helpers/channel_group_helper.dart';
import '../helpers/gif_helper.dart';
import '../helpers/snack_bar_builder.dart';
import 'channel_chat_screen.dart';
import 'chat_screen.dart';
import 'community_qr_scanner_screen.dart';
import 'contacts_screen.dart';
import 'map_screen.dart';
import 'settings_screen.dart';

class ChannelsScreen extends StatefulWidget {
  final bool hideBackButton;

  const ChannelsScreen({super.key, this.hideBackButton = false});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen>
    with DisconnectNavigationMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ChannelGroupStore _channelGroupStore = ChannelGroupStore();
  final CommunityStore _communityStore = CommunityStore();
  final CommunityPskIndex _communityIndex = CommunityPskIndex();
  final Set<String> _expandedChannelGroups = <String>{};
  List<Community> _communities = [];
  List<ChannelGroup> _channelGroups = [];
  List<String> _manualScreenOrder = [];
  String _loadedChannelGroupsForPublicKey = '';
  bool _isLoadingChannelGroups = false;
  Timer? _searchDebounce;

  ChannelMessageStore get _channelMessageStore {
    final connector = context.read<MeshCoreConnector>();
    return ChannelMessageStore()
      ..setPublicKeyHex = connector.selfPublicKeyHex
      ..replaceChannels(connector.channels);
  }

  @override
  void initState() {
    super.initState();
    if (PlatformInfo.isDesktop) {
      HardwareKeyboard.instance.addHandler(_handleDesktopKeyEvent);
    }
    _searchController.text = context
        .read<UiViewStateService>()
        .channelsSearchText;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MeshCoreConnector>().getChannels();
      _loadChannelGroups();
      _loadCommunities();
    });
  }

  Future<void> _loadChannelGroups() async {
    final connector = context.read<MeshCoreConnector>();
    final publicKeyHex = connector.selfPublicKeyHex;
    if (publicKeyHex.isEmpty ||
        _isLoadingChannelGroups ||
        _loadedChannelGroupsForPublicKey == publicKeyHex) {
      return;
    }

    // Channel groups are stored per node, so wait until SELF_INFO gives us the
    // node public key. Loading with an empty key would make grouped channels
    // appear as a flat list on the initial Channels screen.
    if (mounted) {
      setState(() {
        _isLoadingChannelGroups = true;
      });
    } else {
      _isLoadingChannelGroups = true;
    }

    _channelGroupStore.setPublicKeyHex = publicKeyHex;
    final groups = await _channelGroupStore.loadGroups();
    final expandedGroups = await _channelGroupStore.loadExpandedGroupNames();
    final screenOrder = await _channelGroupStore.loadScreenOrder();
    final currentPublicKeyHex = connector.selfPublicKeyHex;
    if (mounted && currentPublicKeyHex == publicKeyHex) {
      setState(() {
        _channelGroups = orderedChannelGroups(groups);
        _manualScreenOrder = screenOrder;
        _loadedChannelGroupsForPublicKey = publicKeyHex;
        _isLoadingChannelGroups = false;
        _expandedChannelGroups
          ..clear()
          // Restore only groups that still exist after local edits/deletions.
          ..addAll(
            expandedGroups.where(
              (name) => _channelGroups.any((group) => group.name == name),
            ),
          );
      });
    } else {
      _isLoadingChannelGroups = false;
    }
  }

  Future<void> _saveChannelGroups() async {
    _channelGroupStore.setPublicKeyHex = context
        .read<MeshCoreConnector>()
        .selfPublicKeyHex;
    await _channelGroupStore.saveGroups(_channelGroups);
  }

  Future<void> _saveExpandedChannelGroups() async {
    _channelGroupStore.setPublicKeyHex = context
        .read<MeshCoreConnector>()
        .selfPublicKeyHex;
    await _channelGroupStore.saveExpandedGroupNames(_expandedChannelGroups);
  }

  Future<void> _saveManualScreenOrder() async {
    _channelGroupStore.setPublicKeyHex = context
        .read<MeshCoreConnector>()
        .selfPublicKeyHex;
    await _channelGroupStore.saveScreenOrder(_manualScreenOrder);
  }

  Future<void> _loadCommunities() async {
    final connector = context.read<MeshCoreConnector>();
    _communityStore.setPublicKeyHex = connector.selfPublicKeyHex;
    final communities = await _communityStore.loadCommunities();
    if (mounted) {
      setState(() {
        _communities = communities;
        _communityIndex.initialize(communities);
      });
    }
  }

  @override
  void dispose() {
    if (PlatformInfo.isDesktop) {
      HardwareKeyboard.instance.removeHandler(_handleDesktopKeyEvent);
    }
    _searchDebounce?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _handleDesktopKeyEvent(KeyEvent event) {
    if (!PlatformInfo.isDesktop ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return false;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    if (_searchFocusNode.hasFocus) {
      return false;
    }

    final target = ChatKeyboardNavigationHistory.lastTarget;
    if (target?.type != ChatKeyboardNavigationTargetType.channel) {
      return false;
    }
    final rememberedChannel = target!.channel;
    if (rememberedChannel == null) return false;

    final connector = context.read<MeshCoreConnector>();
    final channel = connector.channels.firstWhere(
      (channel) => channel.index == rememberedChannel.index,
      orElse: () => rememberedChannel,
    );
    final unread = connector.getUnreadCountForChannelIndex(channel.index);
    connector.markChannelRead(channel.index);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ChannelChatScreen(channel: channel, initialUnreadCount: unread),
      ),
    );
    return true;
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final connector = context.watch<MeshCoreConnector>();
    final viewState = context.watch<UiViewStateService>();
    final appSettings = context.watch<AppSettingsService>().settings;
    final mutedChannelNames = appSettings.mutedChannels;

    if (connector.selfPublicKeyHex.isNotEmpty &&
        _loadedChannelGroupsForPublicKey != connector.selfPublicKeyHex &&
        !_isLoadingChannelGroups) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_loadChannelGroups());
        }
      });
    }

    final channelMessageStore = ChannelMessageStore();
    channelMessageStore.setPublicKeyHex = connector.selfPublicKeyHex;
    channelMessageStore.replaceChannels(connector.channels);

    // Auto-navigate back to scanner if disconnected
    if (!checkConnectionAndNavigate(connector)) {
      return const SizedBox.shrink();
    }

    final allowBack = !connector.isConnected;

    return PopScope(
      canPop: allowBack,
      child: Scaffold(
        appBar: AppBar(
          title: AppBarTitle(context.l10n.channels_title),
          centerTitle: true,
          automaticallyImplyLeading: false,
          bottom: const SyncProgressAppBarBottom(),
          actions: [
            PopupMenuButton(
              // onTap handlers run after the menu route pops, so they must
              // capture the screen's context — not the itemBuilder's menu
              // context, which is deactivated by then.
              itemBuilder: (menuContext) => [
                PopupMenuItem(
                  child: PopupMenuRow(
                    icon: Icons.logout,
                    iconColor: Theme.of(menuContext).colorScheme.error,
                    text: menuContext.l10n.common_disconnect,
                  ),
                  onTap: () => _disconnect(context),
                ),
                PopupMenuItem(
                  child: PopupMenuRow(
                    icon: Icons.groups,
                    text: menuContext.l10n.community_manageCommunities,
                  ),
                  onTap: () => _showManageCommunitiesDialog(context),
                ),
                PopupMenuItem(
                  child: PopupMenuRow(
                    icon: Icons.settings,
                    text: menuContext.l10n.settings_title,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  ),
                ),
              ],
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await context.read<MeshCoreConnector>().getChannels(force: true);
          },
          child: () {
            final channels = connector.channels;
            final roomServerContacts = _roomServerContactsForChannelsScreen(
              connector,
              appSettings,
              viewState,
            );
            final waitingForInitialChannels =
                !connector.hasLoadedChannels && !connector.isLoadingChannels;
            final waitingForFirstChannel =
                connector.isLoadingChannels && channels.isEmpty;
            final waitingForChannelGroups =
                connector.isConnected &&
                (connector.selfPublicKeyHex.isEmpty ||
                    _loadedChannelGroupsForPublicKey !=
                        connector.selfPublicKeyHex);

            if (waitingForInitialChannels ||
                waitingForFirstChannel ||
                waitingForChannelGroups) {
              return const Center(child: CircularProgressIndicator());
            }

            if (channels.isEmpty && roomServerContacts.isEmpty) {
              return ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height - 200,
                    child: EmptyState(
                      icon: Icons.tag,
                      title: context.l10n.channels_noChannelsConfigured,
                      action: FilledButton.icon(
                        onPressed: () => _addPublicChannel(context, connector),
                        icon: const Icon(Icons.public),
                        label: Text(context.l10n.channels_addPublicChannel),
                      ),
                    ),
                  ),
                ],
              );
            }

            final filteredChannels = _filterAndSortChannels(
              channels,
              connector,
              viewState,
            );
            final sortUnreadFirst = appSettings.channelsUnreadSorting;
            final channelsListDisabled =
                connector.isLoadingChannels || connector.isSyncingChannels;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: context.l10n.channels_searchChannels,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (viewState.channelsSearchText.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchDebounce?.cancel();
                                _searchDebounce = null;
                                _searchController.clear();
                                context
                                    .read<UiViewStateService>()
                                    .setChannelsSearchText('');
                              },
                            ),
                          _buildFilterButton(viewState),
                        ],
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 300),
                        () {
                          if (!mounted) return;
                          context
                              .read<UiViewStateService>()
                              .setChannelsSearchText(value);
                        },
                      );
                    },
                  ),
                ),
                Expanded(
                  child: AnimatedOpacity(
                    opacity: channelsListDisabled ? 0.45 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: AbsorbPointer(
                      absorbing: channelsListDisabled,
                      child: _buildChannelsList(
                        context,
                        connector,
                        channelMessageStore,
                        viewState,
                        filteredChannels,
                        roomServerContacts,
                        mutedChannelNames,
                        hideChannelIndexIndicator:
                            appSettings.hideChannelIndexIndicator,
                        sortUnreadFirst: sortUnreadFirst,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }(),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddChannelDialog(context),
          tooltip: context.l10n.channels_addChannel,
          child: const Icon(Icons.add),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: QuickSwitchBar(
            selectedIndex: 1,
            onDestinationSelected: (index) =>
                _handleQuickSwitch(index, context),
            contactsUnreadCount: connector.getTotalContactsUnreadCount(),
            channelsUnreadCount: connector.getTotalChannelsUnreadCount(),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelTile(
    BuildContext context,
    MeshCoreConnector connector,
    ChannelMessageStore channelMessageStore,
    Channel channel, {
    required bool isMuted,
    required bool hideChannelIndexIndicator,
    bool showDragHandle = false,
    int? dragIndex,
    int listIndex = 0,
    EdgeInsetsGeometry? margin,
  }) {
    final unreadCount = connector.getUnreadCountForChannel(channel);
    final widgetColorValue = connector.getChannelWidgetColor(channel.index);
    final widgetColor = widgetColorValue == null
        ? null
        : Color(widgetColorValue);
    final widgetTextColorValue = connector.getChannelWidgetTextColor(
      channel.index,
    );
    final widgetTextColor = widgetTextColorValue == null
        ? null
        : Color(widgetTextColorValue);
    final compressionLabels = _channelCompressionLabels(connector, channel);
    final scheme = Theme.of(context).colorScheme;

    // Determine icon and colors based on channel type
    IconData icon;
    Color iconColor;
    final ChannelType channelType = Channel.getChannelType(
      channel,
      _communityIndex,
    );
    final bool isCommunityChannel = Channel.isCommunityChannel(channelType);
    final community = isCommunityChannel
        ? _communityIndex.getCommunityForChannel(channel)
        : null;
    final region = connector.hasChannelRegion(channel.index)
        ? context.l10n.channels_regionSetTo(
            connector.getChannelRegion(channel.index),
          )
        : context.l10n.channels_regionNotSet;
    String subtitle = region;
    switch (channelType) {
      case ChannelType.communityPublic:
        icon = Icons.groups;
        iconColor = MeshPalette.magenta;
        if (community != null) {
          subtitle =
              '${context.l10n.community_publicChannel} • ${community.name}';
        }
      case ChannelType.communityHashtag:
        icon = Icons.tag;
        iconColor = MeshPalette.magenta;
        if (community != null) {
          subtitle =
              '${context.l10n.community_hashtagChannel} • ${community.name}';
        }
      case ChannelType.public:
        icon = Icons.public;
        iconColor = MeshPalette.signal;
      case ChannelType.hashtag:
        icon = Icons.tag;
        iconColor = MeshPalette.blue;
      case ChannelType.private:
        icon = Icons.lock;
        iconColor = MeshPalette.blue;
    }

    // Last message preview
    final messages = connector.getChannelMessages(channel);
    final lastMessage = messages.isNotEmpty ? messages.last : null;
    final lastMessageText = lastMessage?.text ?? '';
    final lastPreview =
        lastMessageText.isNotEmpty &&
            GifHelper.parseGif(lastMessageText) != null
        ? context.l10n.chat_receivedGif
        : lastMessageText;
    final lastPreviewImage = lastMessage == null
        ? null
        : MCOImageMessage.tryDecode(lastMessage.text);
    final lastTime = lastMessage?.timestamp;

    final channelLabel = channel.name.isEmpty
        ? context.l10n.channels_channelIndex(channel.index)
        : channel.name;

    return ListEntrance(
      key: ValueKey('channel_entrance_${channel.index}'),
      index: dragIndex ?? listIndex,
      child: MeshCard(
        key: ValueKey('channel_${channel.index}'),
        margin:
            margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: widgetColor,
        onTap: () {
          HapticFeedback.selectionClick();
          final unread = connector.getUnreadCountForChannelIndex(channel.index);
          connector.markChannelRead(channel.index);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChannelChatScreen(
                channel: channel,
                initialUnreadCount: unread,
              ),
            ),
          );
        },
        onLongPress: () => _showChannelActions(
          this.context,
          connector,
          channelMessageStore,
          channel,
        ),
        child: GestureDetector(
          onSecondaryTapUp: PlatformInfo.isDesktop
              ? (_) => _showChannelActions(
                  this.context,
                  connector,
                  channelMessageStore,
                  channel,
                )
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Leading avatar with optional community badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AvatarCircle(
                    name: channelLabel,
                    size: 42,
                    color: iconColor,
                    icon: icon,
                  ),
                  if (isCommunityChannel)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: MeshPalette.magenta,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLow,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.people,
                          size: 8,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Title + subtitle + optional channel index chip
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            channelLabel,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: widgetTextColor,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!hideChannelIndexIndicator) ...[
                          const SizedBox(width: 6),
                          StatusChip(
                            label: 'CH ${channel.index}',
                            color: MeshPalette.blue,
                            fontSize: 10,
                          ),
                        ],
                      ],
                    ),
                    if (lastPreviewImage != null) ...[
                      const SizedBox(height: 2),
                      MCOImageMessage(
                        image: lastPreviewImage,
                        maxSize: max(
                          lastPreviewImage.width,
                          lastPreviewImage.height,
                        ).toDouble(),
                      ),
                    ] else if (lastPreview.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        lastPreview,
                        style: MeshTheme.mono(
                          fontSize: 11.5,
                          color: widgetTextColor ?? scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: widgetTextColor ?? scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Right side: time + unread badge + muted + drag handle
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (lastTime != null)
                    Text(
                      _relativeTime(lastTime),
                      style: MeshTheme.mono(
                        fontSize: 11,
                        color: widgetTextColor ?? scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (unreadCount > 0) ...[
                        Padding(
                          padding: EdgeInsets.only(
                            right: isMuted || compressionLabels.isNotEmpty
                                ? 4
                                : 0,
                          ),
                          child: UnreadBadge(count: unreadCount),
                        ),
                      ],
                      if (isMuted)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.notifications_off,
                            size: 14,
                            color: widgetTextColor ?? scheme.onSurfaceVariant,
                          ),
                        ),
                      for (
                        var index = 0;
                        index < compressionLabels.length;
                        index++
                      ) ...[
                        _buildChannelCompressionIndicator(
                          context,
                          compressionLabels[index],
                          textColor: widgetTextColor,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (showDragHandle && dragIndex != null) ...[
                const SizedBox(width: 4),
                ReorderableDragStartListener(
                  index: dragIndex,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.drag_handle,
                      color:
                          widgetTextColor ??
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomServerTile(
    BuildContext context,
    MeshCoreConnector connector,
    Contact contact, {
    bool showDragHandle = false,
    int? dragIndex,
    int listIndex = 0,
    EdgeInsetsGeometry? margin,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final unreadCount = connector.getUnreadCountForContactKey(
      contact.publicKeyHex,
    );
    final messages = connector.getLoadedMessages(contact);
    final lastMessage = messages.isNotEmpty ? messages.last : null;
    final lastMessageText = lastMessage?.text ?? '';
    final lastPreview =
        lastMessageText.isNotEmpty &&
            GifHelper.parseGif(lastMessageText) != null
        ? context.l10n.chat_receivedGif
        : lastMessageText;
    final lastPreviewImage = lastMessage == null
        ? null
        : MCOImageMessage.tryDecode(lastMessage.text);
    final lastTime = lastMessage?.timestamp ?? contact.lastMessageAt;
    final isRoom = contact.type == advTypeRoom;
    final contactLabel = contact.name.isEmpty
        ? (isRoom
              ? context.l10n.chat_contactTypeRoom
              : context.l10n.chat_contactTypeNode)
        : contact.name;

    return ListEntrance(
      key: ValueKey('contact_chat_entrance_${contact.publicKeyHex}'),
      index: listIndex,
      child: MeshCard(
        key: ValueKey('contact_chat_${contact.publicKeyHex}'),
        margin:
            margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: () {
          HapticFeedback.selectionClick();
          connector.markContactRead(contact.publicKeyHex);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ChatScreen(contact: contact, initialUnreadCount: unreadCount),
            ),
          );
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AvatarCircle(
              name: contactLabel,
              size: 42,
              color: isRoom ? MeshPalette.magenta : MeshPalette.blue,
              icon: isRoom ? Icons.meeting_room : Icons.person,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    contactLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (lastPreviewImage != null) ...[
                    const SizedBox(height: 2),
                    MCOImageMessage(
                      image: lastPreviewImage,
                      maxSize: max(
                        lastPreviewImage.width,
                        lastPreviewImage.height,
                      ).toDouble(),
                    ),
                  ] else if (lastPreview.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      lastPreview,
                      style: MeshTheme.mono(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ] else ...[
                    const SizedBox(height: 2),
                    Text(
                      isRoom
                          ? context.l10n.chat_contactTypeRoom
                          : context.l10n.chat_contactTypeNode,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _relativeTime(lastTime),
                  style: MeshTheme.mono(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                if (unreadCount > 0) UnreadBadge(count: unreadCount),
              ],
            ),
            if (showDragHandle && dragIndex != null) ...[
              const SizedBox(width: 4),
              ReorderableDragStartListener(
                index: dragIndex,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.drag_handle,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _channelCompressionLabels(
    MeshCoreConnector connector,
    Channel channel,
  ) {
    return [
      if (connector.isChannelCyr2LatEnabled(channel.index)) 'C2L',
      if (connector.isChannelMcmpEnabled(channel.index)) 'MC',
      if (connector.isChannelSmazEnabled(channel.index)) 'SZ',
    ];
  }

  Widget _buildChannelCompressionIndicator(
    BuildContext context,
    String label, {
    Color? textColor,
  }) {
    final color = textColor ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(label, style: MeshTheme.mono(fontSize: 11, color: color)),
    );
  }

  void _showChannelActions(
    BuildContext context,
    MeshCoreConnector connector,
    ChannelMessageStore channelMessageStore,
    Channel channel,
  ) {
    final parentContext = context;
    final settingsService = context.read<AppSettingsService>();
    final isMuted = settingsService.isChannelMuted(channel.name);

    showModalBottomSheet(
      context: parentContext,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(sheetContext.l10n.channels_editChannel),
              onTap: () async {
                Navigator.pop(sheetContext);
                await Future.delayed(const Duration(milliseconds: 100));
                if (parentContext.mounted) {
                  showChannelEditSheet(parentContext, connector, channel);
                }
              },
            ),
            ListTile(
              leading: Icon(
                isMuted
                    ? Icons.notifications_outlined
                    : Icons.notifications_off_outlined,
              ),
              title: Text(
                isMuted
                    ? sheetContext.l10n.channels_unmuteChannel
                    : sheetContext.l10n.channels_muteChannel,
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (isMuted) {
                  await settingsService.unmuteChannel(channel.name);
                } else {
                  await settingsService.muteChannel(channel.name);
                }
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                sheetContext.l10n.channels_deleteChannel,
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await Future.delayed(const Duration(milliseconds: 100));
                if (parentContext.mounted) {
                  _confirmDeleteChannel(parentContext, connector, channel);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleQuickSwitch(int index, BuildContext context) {
    if (index == 1) return;
    switch (index) {
      case 0:
        Navigator.pushReplacement(
          context,
          buildQuickSwitchRoute(const ContactsScreen(hideBackButton: true)),
        );
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          buildQuickSwitchRoute(const MapScreen(hideBackButton: true)),
        );
        break;
    }
  }

  Future<void> _disconnect(BuildContext context) async {
    final connector = context.read<MeshCoreConnector>();
    await showDisconnectDialog(context, connector);
  }

  Widget _buildFilterButton(UiViewStateService viewState) {
    return SortFilterMenu<ChannelSortOption>(
      tooltip: context.l10n.listFilter_tooltip,
      sections: [
        SortFilterMenuSection<ChannelSortOption>(
          title: context.l10n.channels_sortBy,
          options: [
            SortFilterMenuOption<ChannelSortOption>(
              value: ChannelSortOption.manual,
              label: context.l10n.channels_sortManual,
              checked: viewState.channelsSortOption == ChannelSortOption.manual,
            ),
            SortFilterMenuOption<ChannelSortOption>(
              value: ChannelSortOption.name,
              label: context.l10n.channels_sortAZ,
              checked: viewState.channelsSortOption == ChannelSortOption.name,
            ),
            SortFilterMenuOption<ChannelSortOption>(
              value: ChannelSortOption.latestMessages,
              label: context.l10n.channels_sortLatestMessages,
              checked:
                  viewState.channelsSortOption ==
                  ChannelSortOption.latestMessages,
            ),
            SortFilterMenuOption<ChannelSortOption>(
              value: ChannelSortOption.unread,
              label: context.l10n.channels_sortUnread,
              checked: viewState.channelsSortOption == ChannelSortOption.unread,
            ),
          ],
        ),
      ],
      onSelected: (sortOption) {
        viewState.setChannelsSortOption(sortOption);
      },
    );
  }

  Widget _buildChannelsList(
    BuildContext context,
    MeshCoreConnector connector,
    ChannelMessageStore channelMessageStore,
    UiViewStateService viewState,
    List<Channel> filteredChannels,
    List<Contact> roomServerContacts,
    Set<String> mutedChannelNames, {
    required bool hideChannelIndexIndicator,
    required bool sortUnreadFirst,
  }) {
    final disableRoomAndContactsSorting = context
        .read<AppSettingsService>()
        .settings
        .roomServerDisableRoomAndContactsSorting;
    if (disableRoomAndContactsSorting) {
      return _buildLegacyChannelsList(
        context,
        connector,
        channelMessageStore,
        viewState,
        filteredChannels,
        roomServerContacts,
        mutedChannelNames,
        hideChannelIndexIndicator: hideChannelIndexIndicator,
        sortUnreadFirst: sortUnreadFirst,
      );
    }

    final groupedItemNames = _groupedItemNames();
    final visibleGroups = _channelGroups.where((group) {
      if (viewState.channelsSearchText.isEmpty) return true;
      final query = viewState.channelsSearchText.toLowerCase();
      return group.name.toLowerCase().contains(query) ||
          _itemsForGroup(
            group,
            filteredChannels,
            roomServerContacts,
          ).isNotEmpty;
    }).toList();
    final ungroupedItems = [
      for (final channel in filteredChannels)
        if (!groupedItemNames.contains(_groupKeyForChannel(channel)))
          _ChannelScreenItem.channel(channel),
      for (final room in roomServerContacts)
        if (!groupedItemNames.contains(_groupKeyForRoom(room)))
          _ChannelScreenItem.room(room),
    ];
    _sortChannelScreenItems(
      ungroupedItems,
      connector,
      viewState.channelsSortOption,
      sortUnreadFirst: sortUnreadFirst,
    );
    final hasVisibleContent =
        visibleGroups.isNotEmpty || ungroupedItems.isNotEmpty;

    if (!hasVisibleContent) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height - 300,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.channels_noChannelsFound,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final canReorder =
        viewState.channelsSortOption == ChannelSortOption.manual &&
        viewState.channelsSearchText.isEmpty;
    if (canReorder) {
      final baseEntries = _buildManualScreenEntries(
        filteredChannels,
        roomServerContacts,
      );
      final entries = sortUnreadFirst
          ? _sortManualScreenEntriesUnreadFirst(baseEntries, connector)
          : baseEntries;
      return ReorderableListView.builder(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 88),
        buildDefaultDragHandles: false,
        itemCount: entries.length,
        onReorderItem: (oldIndex, newIndex) {
          final reordered = List<_ChannelScreenListEntry>.from(entries);
          final item = reordered.removeAt(oldIndex);
          reordered.insert(newIndex, item);
          final persistedEntries = sortUnreadFirst
              ? _restoreUnreadManualScreenEntryPositions(
                  baseEntries,
                  reordered,
                  connector,
                )
              : reordered;
          final reorderedGroups = _channelGroupsFromManualScreenEntries(
            persistedEntries,
          );
          final screenOrder = [
            for (final entry in persistedEntries)
              _screenOrderKeyForEntry(entry),
          ];
          setState(() {
            _channelGroups = reorderedGroups;
            _manualScreenOrder = screenOrder;
          });
          unawaited(_saveChannelGroups());
          unawaited(_saveManualScreenOrder());
        },
        itemBuilder: (context, index) {
          final entry = entries[index];
          final group = entry.group;
          if (group != null) {
            return KeyedSubtree(
              key: ValueKey('channel_group_${group.name}'),
              child: _buildChannelGroupTile(
                context,
                connector,
                channelMessageStore,
                group,
                filteredChannels,
                roomServerContacts,
                mutedChannelNames: mutedChannelNames,
                hideChannelIndexIndicator: hideChannelIndexIndicator,
                sortUnreadFirst: sortUnreadFirst,
                showDragHandle: true,
                dragIndex: index,
              ),
            );
          }
          final item = entry.item!;
          final channel = item.channel;
          final showDragHandle = !_isUnreadSortedItem(
            connector,
            item,
            sortUnreadFirst,
          );
          return _buildChannelScreenItem(
            context,
            connector,
            channelMessageStore,
            item,
            isMuted: channel == null
                ? false
                : mutedChannelNames.contains(channel.name),
            hideChannelIndexIndicator: hideChannelIndexIndicator,
            showDragHandle: showDragHandle,
            dragIndex: index,
            margin: const EdgeInsets.symmetric(vertical: 4),
          );
        },
      );
    }

    final children = <Widget>[
      for (final group in visibleGroups)
        _buildChannelGroupTile(
          context,
          connector,
          channelMessageStore,
          group,
          filteredChannels,
          roomServerContacts,
          mutedChannelNames: mutedChannelNames,
          hideChannelIndexIndicator: hideChannelIndexIndicator,
          sortUnreadFirst: sortUnreadFirst,
          forceExpanded: viewState.channelsSearchText.isNotEmpty,
        ),
    ];

    for (var i = 0; i < ungroupedItems.length; i++) {
      children.add(
        _buildChannelScreenItem(
          context,
          connector,
          channelMessageStore,
          ungroupedItems[i],
          isMuted: ungroupedItems[i].channel == null
              ? false
              : mutedChannelNames.contains(ungroupedItems[i].channel!.name),
          hideChannelIndexIndicator: hideChannelIndexIndicator,
          listIndex: i,
          margin: const EdgeInsets.symmetric(vertical: 4),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 88),
      children: children,
    );
  }

  Widget _buildLegacyChannelsList(
    BuildContext context,
    MeshCoreConnector connector,
    ChannelMessageStore channelMessageStore,
    UiViewStateService viewState,
    List<Channel> filteredChannels,
    List<Contact> roomServerContacts,
    Set<String> mutedChannelNames, {
    required bool hideChannelIndexIndicator,
    required bool sortUnreadFirst,
  }) {
    final groupedChannelNames = channelGroupByChannelName(_channelGroups).keys;
    final visibleGroups = _channelGroups.where((group) {
      if (viewState.channelsSearchText.isEmpty) return true;
      final query = viewState.channelsSearchText.toLowerCase();
      return group.name.toLowerCase().contains(query) ||
          channelsForGroup(group, filteredChannels).isNotEmpty;
    }).toList();
    final ungroupedChannels = filteredChannels
        .where(
          (channel) => !groupedChannelNames.contains(
            channelNameForGroup(channel).toLowerCase(),
          ),
        )
        .toList();
    final displayUngroupedChannels = sortUnreadFirst
        ? _sortUnreadChannelsForDisplay(ungroupedChannels, connector)
        : ungroupedChannels;
    final detachedItems = _sortedDetachedContactItems(roomServerContacts);
    final hasVisibleContent =
        visibleGroups.isNotEmpty ||
        ungroupedChannels.isNotEmpty ||
        detachedItems.isNotEmpty;

    if (!hasVisibleContent) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height - 300,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.channels_noChannelsFound,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final canReorder =
        viewState.channelsSortOption == ChannelSortOption.manual &&
        viewState.channelsSearchText.isEmpty;
    if (canReorder) {
      final baseEntries = buildManualChannelEntries(
        filteredChannels,
        _channelGroups,
      );
      final entries = sortUnreadFirst
          ? _sortManualChannelEntriesUnreadFirst(baseEntries, connector)
          : baseEntries;
      return ListView(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 88),
        children: [
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            buildDefaultDragHandles: false,
            itemCount: entries.length,
            onReorderItem: (oldIndex, newIndex) {
              final reordered = List<ChannelGroupListEntry>.from(entries);
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);
              final persistedEntries = sortUnreadFirst
                  ? _restoreUnreadManualChannelEntryPositions(
                      baseEntries,
                      reordered,
                      connector,
                    )
                  : reordered;
              final reorderedGroups = channelGroupsFromManualEntries(
                persistedEntries,
              );
              final orderedChannelIndexes =
                  manualChannelOrderFromEntriesWithChannels(
                    persistedEntries,
                    filteredChannels,
                  );
              setState(() {
                _channelGroups = reorderedGroups;
              });
              unawaited(_saveChannelGroups());
              unawaited(connector.setChannelOrder(orderedChannelIndexes));
            },
            itemBuilder: (context, index) {
              final entry = entries[index];
              final group = entry.group;
              if (group != null) {
                return KeyedSubtree(
                  key: ValueKey('channel_group_${group.name}'),
                  child: _buildChannelGroupTile(
                    context,
                    connector,
                    channelMessageStore,
                    group,
                    filteredChannels,
                    const <Contact>[],
                    mutedChannelNames: mutedChannelNames,
                    hideChannelIndexIndicator: hideChannelIndexIndicator,
                    sortUnreadFirst: sortUnreadFirst,
                    showDragHandle: true,
                    dragIndex: index,
                  ),
                );
              }
              final channel = entry.channel!;
              final showDragHandle =
                  !sortUnreadFirst ||
                  connector.getUnreadCountForChannel(channel) == 0;
              return _buildChannelTile(
                context,
                connector,
                channelMessageStore,
                channel,
                isMuted: mutedChannelNames.contains(channel.name),
                hideChannelIndexIndicator: hideChannelIndexIndicator,
                showDragHandle: showDragHandle,
                dragIndex: index,
                margin: const EdgeInsets.symmetric(vertical: 4),
              );
            },
          ),
          for (var i = 0; i < detachedItems.length; i++)
            _buildChannelScreenItem(
              context,
              connector,
              channelMessageStore,
              detachedItems[i],
              isMuted: false,
              hideChannelIndexIndicator: hideChannelIndexIndicator,
              listIndex: i,
              margin: const EdgeInsets.symmetric(vertical: 4),
            ),
        ],
      );
    }

    final children = <Widget>[
      for (final group in visibleGroups)
        _buildChannelGroupTile(
          context,
          connector,
          channelMessageStore,
          group,
          filteredChannels,
          const <Contact>[],
          mutedChannelNames: mutedChannelNames,
          hideChannelIndexIndicator: hideChannelIndexIndicator,
          sortUnreadFirst: sortUnreadFirst,
          forceExpanded: viewState.channelsSearchText.isNotEmpty,
        ),
    ];

    for (final channel in displayUngroupedChannels) {
      children.add(
        _buildChannelTile(
          context,
          connector,
          channelMessageStore,
          channel,
          isMuted: mutedChannelNames.contains(channel.name),
          hideChannelIndexIndicator: hideChannelIndexIndicator,
          margin: const EdgeInsets.symmetric(vertical: 4),
        ),
      );
    }
    for (var i = 0; i < detachedItems.length; i++) {
      children.add(
        _buildChannelScreenItem(
          context,
          connector,
          channelMessageStore,
          detachedItems[i],
          isMuted: false,
          hideChannelIndexIndicator: hideChannelIndexIndicator,
          listIndex: i,
          margin: const EdgeInsets.symmetric(vertical: 4),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 88),
      children: children,
    );
  }

  List<_ChannelScreenItem> _sortedDetachedContactItems(
    List<Contact> roomServerContacts,
  ) {
    final rooms = [
      for (final contact in roomServerContacts)
        if (contact.type == advTypeRoom) _ChannelScreenItem.room(contact),
    ]..sort((a, b) => _itemNameForSort(a).compareTo(_itemNameForSort(b)));
    final contacts = [
      for (final contact in roomServerContacts)
        if (contact.type == advTypeChat) _ChannelScreenItem.room(contact),
    ]..sort((a, b) => _itemNameForSort(a).compareTo(_itemNameForSort(b)));
    return [...rooms, ...contacts];
  }

  Set<String> _groupedItemNames() {
    return channelGroupByChannelName(_channelGroups).keys.toSet();
  }

  List<_ChannelScreenListEntry> _buildManualScreenEntries(
    List<Channel> filteredChannels,
    List<Contact> roomServerContacts,
  ) {
    final groupedItemNames = _groupedItemNames();
    final entriesByKey = <String, _ChannelScreenListEntry>{
      for (final group in orderedChannelGroups(_channelGroups))
        _screenOrderKeyForGroup(group): _ChannelScreenListEntry.group(group),
      for (final channel in filteredChannels)
        if (!groupedItemNames.contains(_groupKeyForChannel(channel)))
          _screenOrderKeyForItem(_ChannelScreenItem.channel(channel)):
              _ChannelScreenListEntry.item(_ChannelScreenItem.channel(channel)),
      for (final room in roomServerContacts)
        if (!groupedItemNames.contains(_groupKeyForRoom(room)))
          _screenOrderKeyForItem(_ChannelScreenItem.room(room)):
              _ChannelScreenListEntry.item(_ChannelScreenItem.room(room)),
    };

    final entries = <_ChannelScreenListEntry>[];
    final emittedKeys = <String>{};
    for (final key in _manualScreenOrder) {
      final entry = entriesByKey[key];
      if (entry == null) continue;
      if (emittedKeys.add(key)) entries.add(entry);
    }

    final remaining = [
      for (final entry in entriesByKey.entries)
        if (!emittedKeys.contains(entry.key)) entry.value,
    ];
    remaining.sort(_compareManualScreenEntriesFallback);
    entries.addAll(remaining);
    return entries;
  }

  int _compareManualScreenEntriesFallback(
    _ChannelScreenListEntry a,
    _ChannelScreenListEntry b,
  ) {
    final groupA = a.group;
    final groupB = b.group;
    if (groupA != null && groupB != null) {
      final orderCompare = groupA.sortOrder.compareTo(groupB.sortOrder);
      if (orderCompare != 0) return orderCompare;
      return groupA.name.toLowerCase().compareTo(groupB.name.toLowerCase());
    }
    if (groupA != null) return -1;
    if (groupB != null) return 1;
    return _itemNameForSort(a.item!).compareTo(_itemNameForSort(b.item!));
  }

  List<ChannelGroup> _channelGroupsFromManualScreenEntries(
    List<_ChannelScreenListEntry> entries,
  ) {
    return [
      for (var index = 0; index < entries.length; index++)
        if (entries[index].group != null)
          entries[index].group!.copyWith(sortOrder: index),
    ];
  }

  String _screenOrderKeyForEntry(_ChannelScreenListEntry entry) {
    final group = entry.group;
    if (group != null) return _screenOrderKeyForGroup(group);
    return _screenOrderKeyForItem(entry.item!);
  }

  String _screenOrderKeyForGroup(ChannelGroup group) {
    return 'group:${group.name.trim().toLowerCase()}';
  }

  String _screenOrderKeyForItem(_ChannelScreenItem item) {
    final channel = item.channel;
    if (channel != null) return 'channel:${channel.index}';
    return _groupKeyForRoom(item.room!);
  }

  Widget _buildChannelGroupTile(
    BuildContext context,
    MeshCoreConnector connector,
    ChannelMessageStore channelMessageStore,
    ChannelGroup group,
    List<Channel> filteredChannels,
    List<Contact> roomServerContacts, {
    Set<String> mutedChannelNames = const {},
    required bool hideChannelIndexIndicator,
    required bool sortUnreadFirst,
    bool forceExpanded = false,
    bool showDragHandle = false,
    int? dragIndex,
  }) {
    final isExpanded =
        forceExpanded || _expandedChannelGroups.contains(group.name);
    final baseItems = _itemsForGroup(
      group,
      filteredChannels,
      roomServerContacts,
    );
    final items = List<_ChannelScreenItem>.from(baseItems);
    if (!group.allowOrderingInGroup) {
      _sortChannelScreenItems(
        items,
        connector,
        ChannelSortOption.name,
        sortUnreadFirst: false,
      );
    }
    if (sortUnreadFirst) {
      _sortChannelScreenItems(
        items,
        connector,
        ChannelSortOption.unread,
        sortUnreadFirst: true,
      );
    }
    final groupWidgetColor = group.widgetColor == null
        ? null
        : Color(group.widgetColor!);
    final groupWidgetTextColor = group.widgetTextColor == null
        ? null
        : Color(group.widgetTextColor!);
    final unreadCount = items.fold<int>(
      0,
      (sum, item) => sum + _unreadCountForItem(connector, item),
    );

    return GestureDetector(
      onSecondaryTapUp: PlatformInfo.isDesktop
          ? (_) => _showChannelGroupActions(context, group)
          : null,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: groupWidgetColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              minVerticalPadding: 14,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: const VisualDensity(vertical: -2),
              title: Text(
                group.name,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: groupWidgetTextColor,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (unreadCount > 0) ...[
                    UnreadBadge(count: unreadCount),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    isExpanded ? Icons.remove : Icons.add,
                    color: groupWidgetTextColor,
                  ),
                  if (showDragHandle && dragIndex != null) ...[
                    const SizedBox(width: 8),
                    ReorderableDragStartListener(
                      index: dragIndex,
                      child: Icon(
                        Icons.drag_handle,
                        color:
                            groupWidgetTextColor ??
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedChannelGroups.remove(group.name);
                  } else {
                    _expandedChannelGroups.add(group.name);
                  }
                });
                unawaited(_saveExpandedChannelGroups());
              },
              onLongPress: () => _showChannelGroupActions(context, group),
            ),
            AnimatedCrossFade(
              // Keep the collapsed child full-width so cross-fade sizing does
              // not squeeze channel titles during collapse/expand animation.
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(9, 0, 9, 5),
                child: _buildChannelGroupContent(
                  context,
                  connector,
                  channelMessageStore,
                  group,
                  items,
                  mutedChannelNames: mutedChannelNames,
                  hideChannelIndexIndicator: hideChannelIndexIndicator,
                  canReorder: showDragHandle && group.allowOrderingInGroup,
                  sortUnreadFirst: sortUnreadFirst,
                  emptyTextColor: groupWidgetTextColor,
                ),
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelGroupContent(
    BuildContext context,
    MeshCoreConnector connector,
    ChannelMessageStore channelMessageStore,
    ChannelGroup group,
    List<_ChannelScreenItem> items, {
    Set<String> mutedChannelNames = const {},
    required bool hideChannelIndexIndicator,
    required bool canReorder,
    required bool sortUnreadFirst,
    Color? emptyTextColor,
  }) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            context.l10n.channels_changeGroupEmpty,
            style: TextStyle(color: emptyTextColor),
          ),
        ),
      );
    }

    if (!canReorder) {
      return Column(
        children: [
          for (final channel in items)
            _buildChannelScreenItem(
              context,
              connector,
              channelMessageStore,
              channel,
              isMuted: channel.channel == null
                  ? false
                  : mutedChannelNames.contains(channel.channel!.name),
              hideChannelIndexIndicator: hideChannelIndexIndicator,
              margin: const EdgeInsets.symmetric(vertical: 4),
            ),
        ],
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorderItem: (oldIndex, newIndex) {
        _reorderItemsInGroup(
          connector,
          group,
          items,
          oldIndex,
          newIndex,
          sortUnreadFirst: sortUnreadFirst,
        );
      },
      itemBuilder: (context, index) {
        final item = items[index];
        final channel = item.channel;
        final showDragHandle = !_isUnreadSortedItem(
          connector,
          item,
          sortUnreadFirst,
        );
        return _buildChannelScreenItem(
          context,
          connector,
          channelMessageStore,
          item,
          isMuted: channel == null
              ? false
              : mutedChannelNames.contains(channel.name),
          hideChannelIndexIndicator: hideChannelIndexIndicator,
          showDragHandle: showDragHandle,
          dragIndex: index,
          margin: const EdgeInsets.symmetric(vertical: 4),
        );
      },
    );
  }

  void _reorderItemsInGroup(
    MeshCoreConnector connector,
    ChannelGroup group,
    List<_ChannelScreenItem> displayItems,
    int oldIndex,
    int newIndex, {
    required bool sortUnreadFirst,
  }) {
    final reorderedItems = List<_ChannelScreenItem>.from(displayItems);
    if (oldIndex < 0 || oldIndex >= reorderedItems.length) return;
    final item = reorderedItems.removeAt(oldIndex);
    final insertIndex = max(0, min(newIndex, reorderedItems.length));
    reorderedItems.insert(insertIndex, item);
    final persistedItems = sortUnreadFirst
        ? _restoreUnreadItemPositions(
            _itemsForGroup(group, connector.channels, _visibleRoomServers()),
            reorderedItems,
            connector,
          )
        : reorderedItems;
    final reorderedNames = [
      for (final item in persistedItems) _groupNameForItem(item),
    ];
    final updatedGroups = [
      for (final item in _channelGroups)
        if (item.name == group.name)
          item.copyWith(channelNames: reorderedNames)
        else
          item,
    ];

    setState(() {
      _channelGroups = updatedGroups;
    });
    unawaited(_saveChannelGroups());
    if (context
        .read<AppSettingsService>()
        .settings
        .roomServerDisableRoomAndContactsSorting) {
      unawaited(
        connector.setChannelOrder(
          manualChannelOrderForGroups(connector.channels, updatedGroups),
        ),
      );
    }
  }

  void _showChannelGroupActions(BuildContext context, ChannelGroup group) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(context.l10n.contacts_editGroup),
              onTap: () {
                Navigator.pop(sheetContext);
                _showEditChannelGroupDialog(context, group);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(
                context.l10n.contacts_deleteGroup,
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteChannelGroup(group);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditChannelGroupDialog(BuildContext context, ChannelGroup group) {
    final connector = context.read<MeshCoreConnector>();
    final groupedNames = _groupedItemNames();
    final nameController = TextEditingController(text: group.name);
    final selectedNames = {
      for (final name in group.channelNames) name.trim().toLowerCase(),
    };
    bool allowOrderingInGroup = group.allowOrderingInGroup;
    int? selectedWidgetColor = group.widgetColor;
    int? selectedWidgetTextColor = group.widgetTextColor;
    final editableItems =
        [
          for (final channel in connector.channels)
            if (selectedNames.contains(_groupKeyForChannel(channel)) ||
                !groupedNames.contains(_groupKeyForChannel(channel)))
              _ChannelScreenItem.channel(channel),
          for (final room in _visibleRoomServers())
            if (selectedNames.contains(_groupKeyForRoom(room)) ||
                !groupedNames.contains(_groupKeyForRoom(room)))
              _ChannelScreenItem.room(room),
        ]..sort((a, b) {
          final aSelected = selectedNames.contains(_groupNameForItemKey(a));
          final bSelected = selectedNames.contains(_groupNameForItemKey(b));
          if (aSelected != bSelected) return aSelected ? -1 : 1;
          return _itemDisplayName(
            context,
            a,
          ).toLowerCase().compareTo(_itemDisplayName(context, b).toLowerCase());
        });

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) {
          return AlertDialog(
            title: Text(context.l10n.contacts_editGroup),
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.65,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: context.l10n.contacts_groupName,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.channels_changeWidgetColor),
                      trailing: ChannelWidgetColorValue(
                        colorValue: selectedWidgetColor,
                      ),
                      onTap: () async {
                        final selection = await showChannelWidgetColorPicker(
                          dialogContext,
                          selectedBackgroundColorValue: selectedWidgetColor,
                          selectedTextColorValue: selectedWidgetTextColor,
                        );
                        if (selection == null) return;
                        setDialogState(() {
                          selectedWidgetColor = selection.backgroundColorValue;
                          selectedWidgetTextColor = selection.textColorValue;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.l10n.channels_title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: editableItems.isEmpty
                          ? Center(
                              child: Text(
                                context.l10n.channels_changeGroupEmpty,
                              ),
                            )
                          : ListView.builder(
                              itemCount: editableItems.length,
                              itemBuilder: (context, index) {
                                final item = editableItems[index];
                                final itemNameKey = _groupNameForItemKey(item);
                                final isSelected = selectedNames.contains(
                                  itemNameKey,
                                );
                                return CheckboxListTile(
                                  value: isSelected,
                                  title: Text(_itemDisplayName(context, item)),
                                  secondary: Icon(
                                    item.channel != null
                                        ? Icons.tag
                                        : item.room!.type == advTypeRoom
                                        ? Icons.meeting_room
                                        : Icons.person,
                                  ),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        selectedNames.add(itemNameKey);
                                      } else {
                                        selectedNames.remove(itemNameKey);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: allowOrderingInGroup,
                      title: Text(context.l10n.channels_allowOrderingInGroup),
                      onChanged: (value) {
                        setDialogState(() {
                          allowOrderingInGroup = value ?? false;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(context.l10n.common_cancel),
              ),
              TextButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    showDismissibleSnackBar(
                      context,
                      content: Text(context.l10n.contacts_groupNameRequired),
                    );
                    return;
                  }
                  final exists = _channelGroups.any((item) {
                    if (item.name == group.name) return false;
                    return item.name.toLowerCase() == name.toLowerCase();
                  });
                  if (exists) {
                    showDismissibleSnackBar(
                      context,
                      content: Text(
                        context.l10n.contacts_groupAlreadyExists(name),
                      ),
                    );
                    return;
                  }
                  final syncChannelOrderWithNode = context
                      .read<AppSettingsService>()
                      .settings
                      .roomServerDisableRoomAndContactsSorting;
                  setState(() {
                    _channelGroups = _channelGroups.map((item) {
                      if (item.name != group.name) return item;
                      return item.copyWith(
                        name: name,
                        channelNames: allowOrderingInGroup
                            ? _selectedItemNamesForGroupEdit(
                                group,
                                editableItems,
                                selectedNames,
                              )
                            : _selectedItemNamesForGroupEditSorted(
                                editableItems,
                                selectedNames,
                              ),
                        widgetColor: selectedWidgetColor,
                        widgetTextColor: selectedWidgetTextColor,
                        allowOrderingInGroup: allowOrderingInGroup,
                      );
                    }).toList();
                    if (_expandedChannelGroups.remove(group.name)) {
                      _expandedChannelGroups.add(name);
                    }
                  });
                  await _saveChannelGroups();
                  await _saveExpandedChannelGroups();
                  if (syncChannelOrderWithNode) {
                    unawaited(
                      connector.setChannelOrder(
                        manualChannelOrderForGroups(
                          connector.channels,
                          _channelGroups,
                        ),
                      ),
                    );
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                child: Text(context.l10n.common_save),
              ),
            ],
          );
        },
      ),
    );
  }

  String _channelDisplayName(BuildContext context, Channel channel) {
    return channel.name.isEmpty
        ? context.l10n.channels_channelIndex(channel.index)
        : channel.name;
  }

  Widget _buildChannelScreenItem(
    BuildContext context,
    MeshCoreConnector connector,
    ChannelMessageStore channelMessageStore,
    _ChannelScreenItem item, {
    required bool isMuted,
    required bool hideChannelIndexIndicator,
    bool showDragHandle = false,
    int? dragIndex,
    int listIndex = 0,
    EdgeInsetsGeometry? margin,
  }) {
    final channel = item.channel;
    if (channel != null) {
      return _buildChannelTile(
        context,
        connector,
        channelMessageStore,
        channel,
        isMuted: isMuted,
        hideChannelIndexIndicator: hideChannelIndexIndicator,
        showDragHandle: showDragHandle,
        dragIndex: dragIndex,
        listIndex: listIndex,
        margin: margin,
      );
    }
    return _buildRoomServerTile(
      context,
      connector,
      item.room!,
      showDragHandle: showDragHandle,
      dragIndex: dragIndex,
      listIndex: listIndex,
      margin: margin,
    );
  }

  void _deleteChannelGroup(ChannelGroup group) {
    setState(() {
      _channelGroups = _channelGroups
          .where((item) => item.name != group.name)
          .toList();
      _expandedChannelGroups.remove(group.name);
    });
    unawaited(_saveChannelGroups());
    unawaited(_saveExpandedChannelGroups());
  }

  List<Contact> _visibleRoomServers() {
    final settings = context.read<AppSettingsService>().settings;
    if (settings.roomServerDisableRoomAndContactsSorting) {
      return const <Contact>[];
    }
    if (!settings.roomServerShowNotemptyOnChatscreen &&
        !settings.roomServerShowNotemptyContactsOnChatscreen) {
      return const <Contact>[];
    }
    return context.read<MeshCoreConnector>().contacts.where((contact) {
      if (!contact.hasMessages) return false;
      if (settings.roomServerShowNotemptyOnChatscreen &&
          contact.type == advTypeRoom) {
        return true;
      }
      return settings.roomServerShowNotemptyContactsOnChatscreen &&
          contact.type == advTypeChat;
    }).toList();
  }

  List<_ChannelScreenItem> _itemsForGroup(
    ChannelGroup group,
    List<Channel> filteredChannels,
    List<Contact> roomServerContacts,
  ) {
    final channelsByName = {
      for (final channel in filteredChannels)
        _groupKeyForChannel(channel): _ChannelScreenItem.channel(channel),
    };
    final roomsByName = {
      for (final room in roomServerContacts)
        _groupKeyForRoom(room): _ChannelScreenItem.room(room),
    };
    return [
      for (final name in group.channelNames)
        if (channelsByName[name.trim().toLowerCase()] != null)
          channelsByName[name.trim().toLowerCase()]!
        else if (roomsByName[name.trim().toLowerCase()] != null)
          roomsByName[name.trim().toLowerCase()]!,
    ];
  }

  String _groupKeyForChannel(Channel channel) {
    return channelNameForGroup(channel).toLowerCase();
  }

  String _groupKeyForRoom(Contact room) {
    if (room.type == advTypeRoom) {
      return 'room:${room.publicKeyHex.toLowerCase()}';
    }
    return 'contact:${room.publicKeyHex.toLowerCase()}';
  }

  String _groupNameForItem(_ChannelScreenItem item) {
    final channel = item.channel;
    if (channel != null) return channelNameForGroup(channel);
    return _groupKeyForRoom(item.room!);
  }

  String _groupNameForItemKey(_ChannelScreenItem item) {
    return _groupNameForItem(item).trim().toLowerCase();
  }

  String _itemDisplayName(BuildContext context, _ChannelScreenItem item) {
    final channel = item.channel;
    if (channel != null) return _channelDisplayName(context, channel);
    final room = item.room!;
    if (room.name.isNotEmpty) return room.name;
    return room.type == advTypeRoom
        ? context.l10n.chat_contactTypeRoom
        : context.l10n.chat_contactTypeNode;
  }

  int _unreadCountForItem(
    MeshCoreConnector connector,
    _ChannelScreenItem item,
  ) {
    final channel = item.channel;
    if (channel != null) return connector.getUnreadCountForChannel(channel);
    return connector.getUnreadCountForContactKey(item.room!.publicKeyHex);
  }

  DateTime _latestTimeForItem(
    MeshCoreConnector connector,
    _ChannelScreenItem item,
  ) {
    final channel = item.channel;
    if (channel != null) {
      final messages = connector.getChannelMessages(channel);
      return messages.isEmpty ? DateTime(1970) : messages.last.timestamp;
    }
    final room = item.room!;
    final messages = connector.getLoadedMessages(room);
    return messages.isEmpty ? room.lastMessageAt : messages.last.timestamp;
  }

  void _sortChannelScreenItems(
    List<_ChannelScreenItem> items,
    MeshCoreConnector connector,
    ChannelSortOption sortOption, {
    required bool sortUnreadFirst,
  }) {
    if (sortUnreadFirst) {
      items.sort((a, b) {
        final unreadCompare = _unreadCountForItem(
          connector,
          b,
        ).compareTo(_unreadCountForItem(connector, a));
        if (unreadCompare != 0) return unreadCompare;
        return _itemNameForSort(a).compareTo(_itemNameForSort(b));
      });
      return;
    }

    switch (sortOption) {
      case ChannelSortOption.manual:
        break;
      case ChannelSortOption.latestMessages:
        items.sort((a, b) {
          final timeCompare = _latestTimeForItem(
            connector,
            b,
          ).compareTo(_latestTimeForItem(connector, a));
          if (timeCompare != 0) return timeCompare;
          return _itemNameForSort(a).compareTo(_itemNameForSort(b));
        });
        break;
      case ChannelSortOption.unread:
        items.sort((a, b) {
          final unreadCompare = _unreadCountForItem(
            connector,
            b,
          ).compareTo(_unreadCountForItem(connector, a));
          if (unreadCompare != 0) return unreadCompare;
          return _itemNameForSort(a).compareTo(_itemNameForSort(b));
        });
        break;
      case ChannelSortOption.name:
        items.sort(
          (a, b) => _itemNameForSort(a).compareTo(_itemNameForSort(b)),
        );
        break;
    }
  }

  String _itemNameForSort(_ChannelScreenItem item) {
    final channel = item.channel;
    if (channel != null) return _normalizeChannelName(channel).toLowerCase();
    final room = item.room!;
    return room.name.trim().toLowerCase();
  }

  List<_ChannelScreenItem> _restoreUnreadItemPositions(
    List<_ChannelScreenItem> baseItems,
    List<_ChannelScreenItem> displayItems,
    MeshCoreConnector connector,
  ) {
    final movableItems = displayItems
        .where((item) => _unreadCountForItem(connector, item) == 0)
        .toList();
    var movableIndex = 0;
    return [
      for (final baseItem in baseItems)
        if (_unreadCountForItem(connector, baseItem) > 0)
          baseItem
        else if (movableIndex < movableItems.length)
          movableItems[movableIndex++]
        else
          baseItem,
    ];
  }

  List<String> _selectedItemNamesForGroupEdit(
    ChannelGroup group,
    List<_ChannelScreenItem> editableItems,
    Set<String> selectedNames,
  ) {
    final orderedNames = <String>[
      for (final name in group.channelNames)
        if (selectedNames.contains(name.trim().toLowerCase())) name,
    ];
    final existingNames = orderedNames
        .map((name) => name.trim().toLowerCase())
        .toSet();
    for (final item in editableItems) {
      final name = _groupNameForItem(item);
      final key = name.trim().toLowerCase();
      if (selectedNames.contains(key) && !existingNames.contains(key)) {
        orderedNames.add(name);
      }
    }
    return orderedNames;
  }

  List<String> _selectedItemNamesForGroupEditSorted(
    List<_ChannelScreenItem> editableItems,
    Set<String> selectedNames,
  ) {
    final selectedItems = [
      for (final item in editableItems)
        if (selectedNames.contains(_groupNameForItemKey(item))) item,
    ]..sort((a, b) => _itemNameForSort(a).compareTo(_itemNameForSort(b)));
    return [for (final item in selectedItems) _groupNameForItem(item)];
  }

  List<Contact> _roomServerContactsForChannelsScreen(
    MeshCoreConnector connector,
    AppSettings appSettings,
    UiViewStateService viewState,
  ) {
    if (!appSettings.roomServerShowNotemptyOnChatscreen) {
      if (!appSettings.roomServerShowNotemptyContactsOnChatscreen) {
        return const <Contact>[];
      }
    }
    final query = viewState.channelsSearchText.trim().toLowerCase();
    return connector.contacts.where((contact) {
      final canShowRoom =
          appSettings.roomServerShowNotemptyOnChatscreen &&
          contact.type == advTypeRoom;
      final canShowContact =
          appSettings.roomServerShowNotemptyContactsOnChatscreen &&
          contact.type == advTypeChat;
      if ((!canShowRoom && !canShowContact) || !contact.hasMessages) {
        return false;
      }
      if (query.isEmpty) return true;
      return contact.name.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _removeChannelNamesFromGroups(
    Iterable<String> channelNames,
  ) async {
    final removed = {
      for (final name in channelNames) name.trim().toLowerCase(),
    };
    if (removed.isEmpty) return;
    if (!mounted) return;
    var changed = false;
    setState(() {
      _channelGroups = _channelGroups.map((group) {
        final members = group.channelNames
            .where((name) => !removed.contains(name.toLowerCase()))
            .toList();
        if (members.length != group.channelNames.length) {
          changed = true;
        }
        return group.copyWith(channelNames: members);
      }).toList();
    });
    if (changed) {
      await _saveChannelGroups();
    }
  }

  List<Channel> _filterAndSortChannels(
    List<Channel> channels,
    MeshCoreConnector connector,
    UiViewStateService viewState,
  ) {
    var filtered = channels.where((channel) {
      if (viewState.channelsSearchText.isEmpty) return true;
      final label = _normalizeChannelName(channel);
      return label.toLowerCase().contains(
        viewState.channelsSearchText.toLowerCase(),
      );
    }).toList();

    switch (viewState.channelsSortOption) {
      case ChannelSortOption.manual:
        break;
      case ChannelSortOption.latestMessages:
        filtered.sort((a, b) {
          final aMessages = connector.getChannelMessages(a);
          final bMessages = connector.getChannelMessages(b);
          final aLast = aMessages.isEmpty
              ? DateTime(1970)
              : aMessages.last.timestamp;
          final bLast = bMessages.isEmpty
              ? DateTime(1970)
              : bMessages.last.timestamp;
          final timeCompare = bLast.compareTo(aLast);
          if (timeCompare != 0) return timeCompare;
          return _compareChannelsByName(a, b);
        });
        break;
      case ChannelSortOption.unread:
        filtered.sort((a, b) {
          final aUnread = connector.getUnreadCountForChannel(a);
          final bUnread = connector.getUnreadCountForChannel(b);
          final unreadCompare = bUnread.compareTo(aUnread);
          if (unreadCompare != 0) return unreadCompare;
          return _compareChannelsByName(a, b);
        });
        break;
      case ChannelSortOption.name:
        filtered.sort(_compareChannelsByName);
        break;
    }

    return filtered;
  }

  List<_ChannelScreenListEntry> _sortManualScreenEntriesUnreadFirst(
    List<_ChannelScreenListEntry> entries,
    MeshCoreConnector connector,
  ) {
    final unreadEntries = <_ChannelScreenListEntry>[];
    final rest = <_ChannelScreenListEntry>[];
    for (final entry in entries) {
      if (_unreadCountForScreenEntry(connector, entry) > 0) {
        unreadEntries.add(entry);
      } else {
        rest.add(entry);
      }
    }
    return [...unreadEntries, ...rest];
  }

  List<ChannelGroupListEntry> _sortManualChannelEntriesUnreadFirst(
    List<ChannelGroupListEntry> entries,
    MeshCoreConnector connector,
  ) {
    final unreadEntries = <ChannelGroupListEntry>[];
    final rest = <ChannelGroupListEntry>[];
    for (final entry in entries) {
      if (_unreadCountForChannelEntry(connector, entry) > 0) {
        unreadEntries.add(entry);
      } else {
        rest.add(entry);
      }
    }
    return [...unreadEntries, ...rest];
  }

  List<_ChannelScreenListEntry> _restoreUnreadManualScreenEntryPositions(
    List<_ChannelScreenListEntry> baseEntries,
    List<_ChannelScreenListEntry> displayEntries,
    MeshCoreConnector connector,
  ) {
    final movableEntries = displayEntries
        .where((entry) => _unreadCountForScreenEntry(connector, entry) == 0)
        .toList();
    var movableIndex = 0;
    return [
      for (final baseEntry in baseEntries)
        if (_unreadCountForScreenEntry(connector, baseEntry) > 0)
          baseEntry
        else if (movableIndex < movableEntries.length)
          movableEntries[movableIndex++]
        else
          baseEntry,
    ];
  }

  List<ChannelGroupListEntry> _restoreUnreadManualChannelEntryPositions(
    List<ChannelGroupListEntry> baseEntries,
    List<ChannelGroupListEntry> displayEntries,
    MeshCoreConnector connector,
  ) {
    final movableEntries = displayEntries
        .where((entry) => _unreadCountForChannelEntry(connector, entry) == 0)
        .toList();
    var movableIndex = 0;
    return [
      for (final baseEntry in baseEntries)
        if (_unreadCountForChannelEntry(connector, baseEntry) > 0)
          baseEntry
        else if (movableIndex < movableEntries.length)
          movableEntries[movableIndex++]
        else
          baseEntry,
    ];
  }

  int _unreadCountForChannelEntry(
    MeshCoreConnector connector,
    ChannelGroupListEntry entry,
  ) {
    final group = entry.group;
    if (group != null) {
      return channelsForGroup(group, connector.channels).fold<int>(
        0,
        (sum, channel) => sum + connector.getUnreadCountForChannel(channel),
      );
    }
    final channel = entry.channel;
    if (channel == null) return 0;
    return connector.getUnreadCountForChannel(channel);
  }

  List<Channel> _sortUnreadChannelsForDisplay(
    List<Channel> channels,
    MeshCoreConnector connector,
  ) {
    if (channels.length < 2) return channels;
    final unread = <Channel>[];
    final read = <Channel>[];
    for (final channel in channels) {
      if (connector.getUnreadCountForChannel(channel) > 0) {
        unread.add(channel);
      } else {
        read.add(channel);
      }
    }
    return [...unread, ...read];
  }

  int _unreadCountForScreenEntry(
    MeshCoreConnector connector,
    _ChannelScreenListEntry entry,
  ) {
    final group = entry.group;
    if (group != null) {
      return _itemsForGroup(
        group,
        connector.channels,
        _visibleRoomServers(),
      ).fold<int>(0, (sum, item) => sum + _unreadCountForItem(connector, item));
    }
    return _unreadCountForItem(connector, entry.item!);
  }

  bool _isUnreadSortedItem(
    MeshCoreConnector connector,
    _ChannelScreenItem item,
    bool sortUnreadFirst,
  ) {
    return sortUnreadFirst && _unreadCountForItem(connector, item) > 0;
  }

  int _compareChannelsByName(Channel a, Channel b) {
    final nameA = _normalizeChannelName(a).toLowerCase();
    final nameB = _normalizeChannelName(b).toLowerCase();
    return nameA.compareTo(nameB);
  }

  String _normalizeChannelName(Channel channel) {
    if (channel.name.isEmpty) {
      return 'Channel ${channel.index}'; // Fallback for sorting
    }
    final trimmed = channel.name.trim();
    if (trimmed.startsWith('#') && trimmed.length > 1) {
      return trimmed.substring(1);
    }
    return trimmed;
  }

  void _showAddChannelDialog(BuildContext context) {
    final connector = context.read<MeshCoreConnector>();
    final nextIndex = _findNextAvailableIndex(
      connector.channels,
      connector.maxChannels,
    );
    final hasPublicChannel = connector.channels.any((c) => c.isPublicChannel);
    int? selectedOption;
    final nameController = TextEditingController();
    final pskController = TextEditingController();
    final hashtagController = TextEditingController();
    bool addPublicChannel = true;
    bool isRegularHashtag = true;
    Community? selectedCommunity;

    _communityStore.setPublicKeyHex = connector.selfPublicKeyHex;

    showMeshSheet(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Widget buildOptionCard({
            required int optionIndex,
            required IconData icon,
            required String title,
            String? subtitle,
            bool enabled = true,
          }) {
            final isSelected = selectedOption == optionIndex;
            final cardScheme = Theme.of(sheetContext).colorScheme;
            return MeshCard(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              borderColor: isSelected && enabled ? MeshPalette.blueLine : null,
              color: isSelected && enabled ? MeshPalette.blueBg : null,
              onTap: enabled
                  ? () {
                      setSheetState(() {
                        selectedOption = optionIndex;
                        nameController.clear();
                        pskController.clear();
                        hashtagController.clear();
                      });
                    }
                  : null,
              child: Row(
                children: [
                  AvatarCircle(
                    name: title,
                    size: 38,
                    color: enabled
                        ? (isSelected
                              ? MeshPalette.blue
                              : cardScheme.onSurfaceVariant)
                        : cardScheme.outline,
                    icon: icon,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: Theme.of(sheetContext).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: enabled ? null : cardScheme.outline,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle ?? '',
                          style: Theme.of(sheetContext).textTheme.bodySmall
                              ?.copyWith(
                                color: enabled
                                    ? cardScheme.onSurfaceVariant
                                    : cardScheme.outline,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (enabled)
                    Icon(
                      Icons.chevron_right,
                      color: isSelected
                          ? MeshPalette.blue
                          : cardScheme.onSurfaceVariant,
                      size: 20,
                    ),
                ],
              ),
            );
          }

          Widget? buildExpandedContent(
            ChannelMessageStore channelMessageStore,
          ) {
            switch (selectedOption) {
              case -1: // Create local channel group
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: sheetContext.l10n.contacts_groupName,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                final name = nameController.text.trim();
                                if (name.isEmpty) {
                                  showDismissibleSnackBar(
                                    context,
                                    content: Text(
                                      sheetContext
                                          .l10n
                                          .contacts_groupNameRequired,
                                    ),
                                  );
                                  return;
                                }
                                final exists = _channelGroups.any(
                                  (group) =>
                                      group.name.toLowerCase() ==
                                      name.toLowerCase(),
                                );
                                if (exists) {
                                  showDismissibleSnackBar(
                                    context,
                                    content: Text(
                                      sheetContext.l10n
                                          .contacts_groupAlreadyExists(name),
                                    ),
                                  );
                                  return;
                                }
                                setState(() {
                                  _channelGroups = orderedChannelGroups([
                                    ChannelGroup(
                                      name: name,
                                      channelNames: const <String>[],
                                      sortOrder: 0,
                                    ),
                                    for (final group in _channelGroups)
                                      group.copyWith(
                                        sortOrder: group.sortOrder + 1,
                                      ),
                                  ]);
                                });
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                                unawaited(_saveChannelGroups());
                              },
                              child: Text(sheetContext.l10n.common_create),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

              case 0: // Create Private Channel
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: sheetContext.l10n.channels_channelName,
                          border: const OutlineInputBorder(),
                        ),
                        maxLength: 31,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                final name = nameController.text.trim();
                                if (name.isEmpty) {
                                  showDismissibleSnackBar(
                                    context,
                                    content: Text(
                                      sheetContext
                                          .l10n
                                          .channels_enterChannelName,
                                    ),
                                  );
                                  return;
                                }
                                final psk = randomBytes(16);
                                Navigator.pop(sheetContext);
                                await connector.setChannel(
                                  nextIndex,
                                  name,
                                  psk,
                                );
                                if (context.mounted) {
                                  showDismissibleSnackBar(
                                    context,
                                    content: Text(
                                      context.l10n.channels_channelAdded(name),
                                    ),
                                  );
                                }
                              },
                              child: Text(sheetContext.l10n.common_create),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                );

              case 1: // Join Private Channel
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: sheetContext.l10n.channels_channelName,
                          border: const OutlineInputBorder(),
                        ),
                        maxLength: 31,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        controller: pskController,
                        decoration: InputDecoration(
                          labelText: sheetContext.l10n.channels_pskHex,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                final name = nameController.text.trim();
                                final pskHex = pskController.text.trim();
                                if (name.isEmpty) {
                                  showDismissibleSnackBar(
                                    context,
                                    content: Text(
                                      sheetContext
                                          .l10n
                                          .channels_enterChannelName,
                                    ),
                                  );
                                  return;
                                }
                                Uint8List psk;
                                try {
                                  psk = Channel.parsePskHex(pskHex);
                                } on FormatException {
                                  showDismissibleSnackBar(
                                    context,
                                    content: Text(
                                      sheetContext.l10n.channels_pskMustBe32Hex,
                                    ),
                                  );
                                  return;
                                }
                                Navigator.pop(sheetContext);
                                connector.setChannel(nextIndex, name, psk);
                                if (context.mounted) {
                                  showDismissibleSnackBar(
                                    context,
                                    content: Text(
                                      context.l10n.channels_channelAdded(name),
                                    ),
                                  );
                                }
                              },
                              child: Text(sheetContext.l10n.common_add),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                );

              case 2: // Join Public Channel
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final psk = Channel.parsePskHex(
                              Channel.publicChannelPsk,
                            );
                            Navigator.pop(sheetContext);
                            connector.setChannel(
                              nextIndex,
                              context.l10n.channels_public,
                              psk,
                            );
                            if (context.mounted) {
                              showDismissibleSnackBar(
                                context,
                                content: Text(
                                  context.l10n.channels_publicChannelAdded,
                                ),
                              );
                            }
                          },
                          child: Text(sheetContext.l10n.common_add),
                        ),
                      ),
                    ],
                  ),
                );

              case 3: // Join Hashtag Channel
                return Column(
                  children: [
                    // Only show type selection if user has communities
                    if (_communities.isNotEmpty) ...[
                      RadioGroup<bool>(
                        groupValue: isRegularHashtag,
                        onChanged: (v) => setSheetState(() {
                          if (v == null) return;
                          isRegularHashtag = v;
                          if (isRegularHashtag) {
                            selectedCommunity = null;
                          } else if (selectedCommunity == null &&
                              _communities.isNotEmpty) {
                            selectedCommunity = _communities.first;
                          }
                        }),
                        child: Column(
                          children: [
                            RadioListTile<bool>(
                              value: true,
                              title: Text(
                                sheetContext.l10n.community_regularHashtag,
                              ),
                              subtitle: Text(
                                sheetContext.l10n.community_regularHashtagDesc,
                              ),
                              dense: true,
                            ),
                            RadioListTile<bool>(
                              value: false,
                              title: Text(
                                sheetContext.l10n.community_communityHashtag,
                              ),
                              subtitle: Text(
                                sheetContext
                                    .l10n
                                    .community_communityHashtagDesc,
                              ),
                              dense: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Community dropdown (only if community hashtag selected)
                    if (!isRegularHashtag && _communities.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: DropdownButtonFormField<Community>(
                          initialValue: selectedCommunity,
                          items: _communities
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c.name),
                                ),
                              )
                              .toList(),
                          onChanged: (c) =>
                              setSheetState(() => selectedCommunity = c),
                          decoration: InputDecoration(
                            labelText:
                                sheetContext.l10n.community_selectCommunity,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.groups),
                          ),
                        ),
                      ),
                    // Hashtag name input
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        controller: hashtagController,
                        decoration: InputDecoration(
                          labelText: sheetContext.l10n.channels_enterHashtag,
                          hintText: sheetContext.l10n.channels_hashtagHint,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.tag),
                        ),
                        maxLength: 31,
                      ),
                    ),
                    // Privacy hint for community hashtags
                    if (!isRegularHashtag)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          sheetContext.l10n.community_hashtagPrivacyHint,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              sheetContext,
                            ).colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                var hashtag = hashtagController.text.trim();
                                if (hashtag.isEmpty) {
                                  showDismissibleSnackBar(
                                    context,
                                    content: Text(
                                      sheetContext
                                          .l10n
                                          .channels_enterChannelName,
                                    ),
                                  );
                                  return;
                                }

                                // Normalize hashtag name (remove leading # if present)
                                if (hashtag.startsWith('#')) {
                                  hashtag = hashtag.substring(1);
                                }
                                final String channelName;

                                final Uint8List psk;
                                if (isRegularHashtag) {
                                  channelName = '#$hashtag';
                                  // Regular hashtag - public derivation using SHA256
                                  psk = Channel.derivePskFromHashtag(hashtag);
                                } else {
                                  // Community hashtag - HMAC derivation from community secret
                                  if (selectedCommunity == null) {
                                    showDismissibleSnackBar(
                                      sheetContext,
                                      content: Text(
                                        sheetContext
                                            .l10n
                                            .community_selectCommunity,
                                      ),
                                    );
                                    return;
                                  }
                                  channelName =
                                      '${selectedCommunity!.name} #$hashtag';
                                  psk = selectedCommunity!
                                      .deriveCommunityHashtagPsk(hashtag);
                                  // Track in community's hashtag list
                                  await _communityStore.addHashtagChannel(
                                    selectedCommunity!.id,
                                    hashtag,
                                  );
                                  _loadCommunities();
                                }

                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                                connector.setChannel(
                                  nextIndex,
                                  channelName,
                                  psk,
                                );
                                if (context.mounted) {
                                  showDismissibleSnackBar(
                                    context,
                                    content: Text(
                                      context.l10n.channels_channelAdded(
                                        channelName,
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Text(sheetContext.l10n.common_add),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

              case 4: // Scan Community QR
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            if (context.mounted) {
                              final result = await Navigator.push<Community>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const CommunityQrScannerScreen(),
                                ),
                              );
                              // Result handled by scanner screen
                              if (result != null && context.mounted) {
                                // Community was joined, refresh might be needed
                              }
                            }
                          },
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(sheetContext.l10n.community_scanQr),
                        ),
                      ),
                    ],
                  ),
                );

              case 5: // Create Community
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: sheetContext.l10n.community_name,
                          hintText: sheetContext.l10n.community_enterName,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.groups),
                        ),
                        maxLength: 31,
                      ),
                    ),
                    CheckboxListTile(
                      value: addPublicChannel,
                      onChanged: (value) {
                        setSheetState(() {
                          addPublicChannel = value ?? true;
                        });
                      },
                      title: Text(sheetContext.l10n.community_addPublicChannel),
                      subtitle: Text(
                        sheetContext.l10n.community_addPublicChannelHint,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                final name = nameController.text.trim();
                                final publicLabel =
                                    context.l10n.channels_public;
                                if (name.isEmpty) {
                                  showDismissibleSnackBar(
                                    context,
                                    content: Text(
                                      sheetContext.l10n.community_enterName,
                                    ),
                                  );
                                  return;
                                }

                                // Create community with random secret
                                final community = Community.create(
                                  id: const Uuid().v4(),
                                  name: name,
                                );

                                // Save to store
                                await _communityStore.addCommunity(community);

                                // Optionally add the community public channel to the device
                                if (addPublicChannel) {
                                  final psk = community
                                      .deriveCommunityPublicPsk();
                                  final channelName =
                                      '${community.name} $publicLabel';
                                  connector.setChannel(
                                    nextIndex,
                                    channelName,
                                    psk,
                                  );
                                }

                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }

                                // Refresh communities list
                                _loadCommunities();

                                if (context.mounted) {
                                  showDismissibleSnackBar(
                                    context,
                                    content: Text(
                                      context.l10n.community_created(name),
                                    ),
                                  );

                                  // Show QR code dialog
                                  await QrCodeShareDialog.show(
                                    context: context,
                                    data: community.toQrJson(),
                                    title: context.l10n.community_qrTitle,
                                    instructions: context.l10n
                                        .community_qrInstructions(name),
                                    embeddedImage: Image.asset(
                                      'assets/images/mesh-icon.png',
                                      width: 40,
                                      height: 40,
                                    ),
                                  );
                                }
                              },
                              child: Text(sheetContext.l10n.common_create),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                );

              default:
                return null;
            }
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (_, scrollController) => Column(
              children: [
                BottomSheetHeader(title: sheetContext.l10n.channels_addChannel),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      buildOptionCard(
                        optionIndex: -1,
                        icon: Icons.create_new_folder_outlined,
                        title: sheetContext.l10n.contacts_newGroup,
                      ),
                      if (selectedOption == -1)
                        buildExpandedContent(_channelMessageStore)!,
                      buildOptionCard(
                        optionIndex: 0,
                        icon: Icons.add,
                        title: sheetContext.l10n.channels_createPrivateChannel,
                        subtitle:
                            sheetContext.l10n.channels_createPrivateChannelDesc,
                      ),
                      if (selectedOption == 0)
                        buildExpandedContent(_channelMessageStore)!,
                      buildOptionCard(
                        optionIndex: 1,
                        icon: Icons.lock,
                        title: sheetContext.l10n.channels_joinPrivateChannel,
                        subtitle:
                            sheetContext.l10n.channels_joinPrivateChannelDesc,
                      ),
                      if (selectedOption == 1)
                        buildExpandedContent(_channelMessageStore)!,
                      if (!hasPublicChannel) ...[
                        buildOptionCard(
                          optionIndex: 2,
                          icon: Icons.public,
                          title: sheetContext.l10n.channels_joinPublicChannel,
                          subtitle:
                              sheetContext.l10n.channels_joinPublicChannelDesc,
                        ),
                        if (selectedOption == 2)
                          buildExpandedContent(_channelMessageStore)!,
                      ],
                      buildOptionCard(
                        optionIndex: 3,
                        icon: Icons.tag,
                        title: sheetContext.l10n.channels_joinHashtagChannel,
                        subtitle:
                            sheetContext.l10n.channels_joinHashtagChannelDesc,
                      ),
                      if (selectedOption == 3)
                        buildExpandedContent(_channelMessageStore)!,
                      buildOptionCard(
                        optionIndex: 4,
                        icon: Icons.qr_code_scanner,
                        title: sheetContext.l10n.community_scanQr,
                        subtitle: sheetContext.l10n.community_join,
                      ),
                      if (selectedOption == 4)
                        buildExpandedContent(_channelMessageStore)!,
                      buildOptionCard(
                        optionIndex: 5,
                        icon: Icons.groups,
                        title: sheetContext.l10n.community_create,
                        subtitle: sheetContext.l10n.community_createDesc,
                      ),
                      if (selectedOption == 5)
                        buildExpandedContent(_channelMessageStore)!,
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _confirmDeleteChannel(
    BuildContext context,
    MeshCoreConnector connector,
    Channel channel,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.channels_deleteChannel),
        content: Text(
          dialogContext.l10n.channels_deleteChannelConfirm(channel.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await connector.deleteChannel(channel.index);
                await _removeChannelNamesFromGroups([
                  channelNameForGroup(channel),
                ]);

                if (!context.mounted) return;

                showDismissibleSnackBar(
                  context,
                  content: Text(
                    context.l10n.channels_channelDeleted(channel.name),
                  ),
                );
              } catch (e, st) {
                if (!context.mounted) return;

                showDismissibleSnackBar(
                  context,
                  content: Text(
                    context.l10n.channels_channelDeleteFailed(channel.name),
                  ),
                );

                // Preserve existing logging (if it was there)
                debugPrint('Failed to delete channel: $e\n$st');
              }
            },
            child: Text(
              dialogContext.l10n.common_delete,
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addPublicChannel(BuildContext context, MeshCoreConnector connector) {
    final psk = Channel.parsePskHex(Channel.publicChannelPsk);
    connector.setChannel(0, context.l10n.channels_public, psk);
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.channels_publicChannelAdded),
    );
  }

  int _findNextAvailableIndex(List<Channel> channels, int maxChannels) {
    final usedIndices = channels.map((c) => c.index).toSet();
    for (int i = 0; i < maxChannels; i++) {
      if (!usedIndices.contains(i)) return i;
    }
    return 0;
  }

  void _showManageCommunitiesDialog(BuildContext context) {
    showMeshSheet(
      context,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            BottomSheetHeader(
              title: sheetContext.l10n.community_manageCommunities,
            ),
            const Divider(height: 1),
            Expanded(
              child: _communities.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.groups_outlined,
                            size: 64,
                            color: Theme.of(sheetContext)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            sheetContext.l10n.community_noCommunities,
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(
                                sheetContext,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            sheetContext.l10n.community_scanOrCreate,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(sheetContext)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.8),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _communities.length,
                      itemBuilder: (context, index) {
                        final community = _communities[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: MeshPalette.magentaBg,
                            child: const Icon(
                              Icons.groups,
                              color: MeshPalette.magenta,
                            ),
                          ),
                          title: Text(community.name),
                          subtitle: Text(
                            context.l10n.channels_communityShortId(
                              community.shortCommunityId,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              Navigator.pop(sheetContext);
                              // Use the screen's context: the sheet item's
                              // context is deactivated once the sheet pops.
                              if (value == 'share') {
                                _showCommunityQrDialog(this.context, community);
                              } else if (value == 'leave') {
                                _confirmLeaveCommunity(this.context, community);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'share',
                                child: Row(
                                  children: [
                                    const Icon(Icons.qr_code),
                                    const SizedBox(width: 12),
                                    Text(context.l10n.community_showQr),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'leave',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.exit_to_app,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      context.l10n.community_delete,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _showCommunityQrDialog(context, community);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCommunityQrDialog(BuildContext context, Community community) {
    QrCodeShareDialog.show(
      context: context,
      data: community.toQrJson(),
      title: context.l10n.community_qrTitle,
      instructions: context.l10n.community_qrInstructions(community.name),
      embeddedImage: Image.asset(
        'assets/images/mesh-icon.png',
        width: 40,
        height: 40,
      ),
    );
  }

  void _confirmLeaveCommunity(BuildContext context, Community community) {
    final connector = context.read<MeshCoreConnector>();

    // Find all channels that belong to this community
    List<Channel> communityChannels = [];
    final publicPskHex = Channel.formatPskHex(
      community.deriveCommunityPublicPsk(),
    );

    for (final channel in connector.channels) {
      // Check if it's the public channel
      if (channel.pskHex == publicPskHex) {
        communityChannels.add(channel);
        continue;
      }
      // Check if it's a hashtag channel
      for (final hashtag in community.hashtagChannels) {
        final hashtagPskHex = Channel.formatPskHex(
          community.deriveCommunityHashtagPsk(hashtag),
        );
        if (channel.pskHex == hashtagPskHex) {
          communityChannels.add(channel);
          break;
        }
      }
    }

    final channelCount = communityChannels.length;
    _communityStore.setPublicKeyHex = connector.selfPublicKeyHex;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.community_delete),
        content: Text(
          channelCount > 0
              ? '${dialogContext.l10n.community_deleteConfirm(community.name)}\n\n${dialogContext.l10n.community_deleteChannelsWarning(channelCount)}'
              : dialogContext.l10n.community_deleteConfirm(community.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              // Delete all community channels from the device
              for (final channel in communityChannels) {
                await connector.deleteChannel(channel.index);
              }
              await _removeChannelNamesFromGroups(
                communityChannels.map(channelNameForGroup),
              );

              // Remove community from store
              await _communityStore.removeCommunity(community.id);
              _loadCommunities();

              if (context.mounted) {
                showDismissibleSnackBar(
                  context,
                  content: Text(context.l10n.community_deleted(community.name)),
                );
              }
            },
            child: Text(
              dialogContext.l10n.community_delete,
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelScreenItem {
  const _ChannelScreenItem._({this.channel, this.room});

  const _ChannelScreenItem.channel(Channel channel) : this._(channel: channel);

  const _ChannelScreenItem.room(Contact room) : this._(room: room);

  final Channel? channel;
  final Contact? room;
}

class _ChannelScreenListEntry {
  const _ChannelScreenListEntry._({this.group, this.item});

  const _ChannelScreenListEntry.group(ChannelGroup group)
    : this._(group: group);

  const _ChannelScreenListEntry.item(_ChannelScreenItem item)
    : this._(item: item);

  final ChannelGroup? group;
  final _ChannelScreenItem? item;
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/mcoa_theme_preview_data.dart';
import '../helpers/mcoa_theme_preferences.dart';
import '../l10n/l10n.dart';
import '../models/custom_theme.dart';
import '../models/channel_message.dart';
import '../screens/channel_chat_screen.dart';
import '../screens/channels_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/contacts_screen.dart';
import '../services/app_settings_service.dart';
import '../theme/mesh_theme.dart';
import 'chat_background.dart';
import 'contact_chat_composer.dart';
import 'contact_chat_title.dart';
import 'formatted_message_text.dart';
import 'mention_chip.dart';

/// Interactive tabs around inert, production chat/list widgets.
class McoaThemePreview extends StatefulWidget {
  const McoaThemePreview({
    super.key,
    required this.theme,
    required this.openedAt,
  });

  final CustomTheme theme;
  final DateTime openedAt;

  @override
  State<McoaThemePreview> createState() => _McoaThemePreviewState();
}

class _McoaThemePreviewState extends State<McoaThemePreview> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  int _tab = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final source = context.watch<AppSettingsService>().settings;
    // Providers own isolated fixtures, rebuilt when the locale changes.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Theme(
        data: MeshTheme.fromCustom(widget.theme),
        child: MultiProvider(
          key: ValueKey((Localizations.localeOf(context), widget.openedAt, source, widget.theme.mcoa)),
          providers: [
            ChangeNotifierProvider<AppSettingsService>(
              create: (_) => McoaThemePreviewSettings(
                applyMcoaThemePreferences(source, widget.theme.mcoa),
              ),
            ),
            ChangeNotifierProvider<MeshCoreConnector>(
              create: (_) => McoaThemePreviewData(
                openedAt: widget.openedAt,
                incomingText: l10n.themes_previewIncoming,
                outgoingText: l10n.themes_previewOutgoing,
                defaultSender: l10n.channels_senderNameDefault,
              ),
            ),
          ],
          child: Builder(
            builder: (context) => _scaledPreview(context, source.uiScale, Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(MeshRadii.md),
                border: Border.all(color: Theme.of(context).colorScheme.outline),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DefaultTabController(
                    length: 4,
                    initialIndex: _tab,
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      onTap: (index) => setState(() => _tab = index),
                      tabs: [
                        Tab(
                          key: const ValueKey('theme-preview-tab-0'),
                          text: l10n.themes_previewChannelChat,
                        ),
                        Tab(
                          key: const ValueKey('theme-preview-tab-1'),
                          text: l10n.themes_previewDirectChat,
                        ),
                        Tab(
                          key: const ValueKey('theme-preview-tab-2'),
                          text: l10n.nav_channels,
                        ),
                        Tab(
                          key: const ValueKey('theme-preview-tab-3'),
                          text: l10n.nav_contacts,
                        ),
                      ],
                    ),
                  ),
                  IgnorePointer(
                    child: ExcludeFocus(
                      child: _content(context),
                    ),
                  ),
                ],
              ),
            )),
          ),
        ),
      ),
    );
  }

  Widget _scaledPreview(BuildContext context, double originalScale, Widget child) {
    final media = MediaQuery.of(context);
    final scale = context.read<AppSettingsService>().settings.uiScale;
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(
        media.textScaler.scale(1) * scale / (originalScale > 0 ? originalScale : 1),
      )),
      child: child,
    );
  }

  Widget _content(BuildContext context) {
    final data = context.read<MeshCoreConnector>() as McoaThemePreviewData;
    final l10n = context.l10n;
    final Widget content;
    if (_tab == 0 || _tab == 1) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.theme.mcoa.colors['status_bar'] case final color?)
            SizedBox(height: 8, child: ColoredBox(color: color, child: const SizedBox.expand())),
          ColoredBox(
            color: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).colorScheme.surface,
            child: IconTheme.merge(
              data: IconThemeData(color: Theme.of(context).appBarTheme.foregroundColor),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: Theme.of(context).appBarTheme.foregroundColor),
                child: _header(context, data),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _tab == 0
                ? _channelChatSamples(context, data)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final message in data.directMessages)
                        ContactMessageBubble(
                          message: message,
                          senderName: 'Alice',
                          sourceId: data.alice.publicKeyHex,
                          textScale: 1,
                        ),
                    ],
                  ),
          ),
          ContactChatComposer(
            contactName: _tab == 0 ? '#channel0' : 'Alice',
            controller: _controller,
            focusNode: _focus,
            maxBytes: 150,
            showByteCounterWhenEmpty: true,
            onSend: () {},
            actions: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () {},
            ),
          ),
        ],
      );
    } else if (_tab == 2) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: ChannelsScreen(previewChannels: data.channels),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ContactThemePreviewTile(
              contact: data.alice,
              pathLabel: l10n.chat_hopsCount(2),
              lastSeenText: l10n.contacts_lastSeenDaysAgo(2),
            ),
            ContactThemePreviewTile(
              contact: data.bob,
              pathLabel: l10n.chat_floodAuto,
              lastSeenText: l10n.contacts_lastSeenDaysAgo(2),
            ),
          ],
        ),
      );
    }
    final background = widget.theme.chatBackground;
    if (background == null ||
        (_tab >= 2 && !widget.theme.chatBackgroundEverywhere)) {
      return content;
    }
    return Stack(
      children: [
        Positioned.fill(child: ChatBackgroundLayer(background: background)),
        content,
      ],
    );
  }

  Widget _channelChatSamples(BuildContext context, McoaThemePreviewData data) =>
      ChannelChatScreen(
        channel: data.chatChannel,
        previewMessages: data.channelMessages,
        previewMessageBodyBuilder: (message, style, textScale) =>
            _previewMessageBody(context, message, style, textScale),
      );

  Widget _previewMessageBody(
    BuildContext context,
    ChannelMessage message,
    TextStyle style,
    double textScale,
  ) {
    return FormattedMessageText(
      key: ValueKey(
        message.isOutgoing
            ? 'theme-preview-outgoing-body'
            : 'theme-preview-incoming-body',
      ),
      text: message.text,
      style: style,
      textScale: textScale,
      simplified: false,
      textScaler: TextScaler.linear(
        context.read<AppSettingsService>().settings.uiScale,
      ),
      leadingSpans: [
        for (final simplified in [false, true]) ...[
          WidgetSpan(
            alignment: simplified
                ? PlaceholderAlignment.baseline
                : PlaceholderAlignment.middle,
            baseline: simplified ? TextBaseline.alphabetic : null,
            child: MentionChip(
              senderName: 'senderName',
              textScale: textScale,
              simplified: simplified,
              textStyle: style,
            ),
          ),
          const TextSpan(text: ' '),
        ],
      ],
    );
  }

  Widget _header(BuildContext context, McoaThemePreviewData data) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.arrow_back)),
          Expanded(
            child: _tab == 1
                ? ContactChatTitle(
                    connector: data,
                    contact: data.alice,
                    unreadCount: 0,
                    senderName: l10n.channels_senderNameDefault,
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('#channel0', style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      )),
                      Text(
                        l10n.channels_messageRegion('any-region'),
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        '${l10n.channels_senderNameLabel}: ${l10n.channels_senderNameDefault}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
          ),
          if (_tab == 1)
            const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.route, size: 20),
            ),
          const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.widgets_outlined, size: 20),
          ),
          const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.more_vert, size: 20),
          ),
        ],
      ),
    );
  }
}

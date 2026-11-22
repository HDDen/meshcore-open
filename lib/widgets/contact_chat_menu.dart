import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../l10n/contact_localization.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../screens/telemetry_screen.dart';
import '../services/chat_background_service.dart';
import 'chat_background.dart';
import 'contact_settings_dialog.dart';
import 'popup_menu_row.dart';

/// The same header actions for radio-key and additional-key conversations.
/// History operations are supplied by the chat to retain its identity scope.
class ContactChatMenu extends StatelessWidget {
  const ContactChatMenu({
    super.key,
    required this.connector,
    required this.contact,
    required this.onSearch,
    required this.onClear,
    this.canEditTelemetry = true,
    this.onToggleBookmarks,
    this.bookmarksOnly = false,
  });

  final MeshCoreConnector connector;
  final Contact contact;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  final bool canEditTelemetry;
  final VoidCallback? onToggleBookmarks;
  final bool bookmarksOnly;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    icon: const Icon(Icons.more_vert),
    onSelected: (value) {
      switch (value) {
        case 'showBookmarks':
          onToggleBookmarks?.call();
        case 'searchMessages':
          onSearch();
        case 'info':
          _showContactInfo(context);
        case 'settings':
          unawaited(showContactSettingsDialog(
            context,
            connector: connector,
            contact: contact,
            canEditTelemetry: canEditTelemetry,
          ));
        case 'background':
          unawaited(showChatBackgroundSheet(
            context,
            ChatBackgroundService.contactKey(contact),
          ));
        case 'telemetry':
          Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => TelemetryScreen(contact: contact)),
          );
        case 'clearChat':
          onClear();
      }
    },
    itemBuilder: (context) => [
      if (onToggleBookmarks != null)
        PopupMenuItem(value: 'showBookmarks', child: PopupMenuRow(
          icon: bookmarksOnly ? Icons.bookmark : Icons.bookmark_border,
          text: context.l10n.chat_showBookmarks,
        )),
      PopupMenuItem(
        value: 'searchMessages',
        child: PopupMenuRow(icon: Icons.search, text: context.l10n.chat_searchMessages),
      ),
      if (!connector.isOfflineMode) ...[
        PopupMenuItem(
          value: 'info',
          child: PopupMenuRow(icon: Icons.info_outline, text: context.l10n.contact_info),
        ),
        PopupMenuItem(
          value: 'telemetry',
          child: PopupMenuRow(icon: Icons.bar_chart, text: context.l10n.contact_telemetry),
        ),
        PopupMenuItem(
          value: 'settings',
          child: PopupMenuRow(icon: Icons.settings, text: context.l10n.contact_settings),
        ),
      ],
      if (context.read<ChatBackgroundService?>() != null)
        PopupMenuItem(
          value: 'background',
          child: PopupMenuRow(icon: Icons.wallpaper, text: context.l10n.chatBackground_title),
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

  void _showContactInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: SelectableText(contact.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ContactInfoRow(
                context.l10n.chat_type,
                contact.typeLabel(context.l10n),
              ),
              ContactInfoRow(
                context.l10n.chat_path,
                contact.pathLabel(
                  context.l10n,
                  pathHashByteWidth: connector.pathHashByteWidth,
                ),
              ),
              ContactInfoRow(
                context.l10n.contact_lastSeen,
                _formatContactLastMessage(context, contact.lastMessageAt),
              ),
              if (contact.hasLocation)
                ContactInfoRow(
                  context.l10n.chat_location,
                  '${contact.latitude?.toStringAsFixed(4)}, ${contact.longitude?.toStringAsFixed(4)}',
                ),
              ContactInfoRow(context.l10n.chat_publicKey, contact.publicKeyHex),
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

  String _formatContactLastMessage(BuildContext context, DateTime timestamp) {
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
}

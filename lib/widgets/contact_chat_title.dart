import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/path_helper.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../storage/contact_region_store.dart';
import 'contact_region_dialog.dart';
import 'routing_sheet.dart';

class ContactChatTitle extends StatelessWidget {
  const ContactChatTitle({
    super.key,
    required this.connector,
    required this.contact,
    this.unreadCount,
    this.senderName,
    this.onPickSender,
    this.onOpenRouting,
  });

  final MeshCoreConnector connector;
  final Contact contact;
  final int? unreadCount;
  final String? senderName;
  final VoidCallback? onPickSender;
  final VoidCallback? onOpenRouting;

  static double senderToolbarHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(15) / 15;
    return 76 * scale.clamp(1.0, double.infinity);
  }

  static const _detailStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.normal,
  );
  static const _linkStyle = TextStyle(
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.dotted,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final route = _pathLabel(context);
    final region = _floodRegionLabel(context);
    final hasPath = (contact.pathOverrideBytes ?? contact.path).isNotEmpty;
    final unread = unreadCount;
    final sender = senderName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          contact.name,
          style: region == null && sender == null
              ? null
              : const TextStyle(fontSize: 15),
          maxLines: sender == null ? null : 1,
          overflow: sender == null ? null : TextOverflow.ellipsis,
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpenRouting ??
              () => ContactRoutingSheet.show(context, contact: contact),
          child: Text(
            unread == null ? route : '$route • ${l10n.chat_unread(unread)}',
            overflow: TextOverflow.ellipsis,
            style: hasPath ? _detailStyle.merge(_linkStyle) : _detailStyle,
          ),
        ),
        if (region != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pickFloodRegion(context),
            child: Text(
              region,
              overflow: TextOverflow.ellipsis,
              style: _detailStyle.merge(_linkStyle),
            ),
          ),
        if (sender != null)
          InkWell(
            onTap: onPickSender,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${l10n.channels_senderNameLabel}: '),
                TextSpan(
                  text: sender,
                  style: onPickSender == null ? null : _linkStyle,
                ),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _detailStyle,
            ),
          ),
      ],
    );
  }

  String _pathLabel(BuildContext context) {
    final l10n = context.l10n;
    final override = contact.pathOverride;
    if (override != null) {
      if (override < 0) return l10n.chat_floodForced;
      if (override == 0) return l10n.chat_directForced;
      return l10n.chat_hopsForced(_hopCount(
        contact.pathOverrideBytes ?? const [],
        override,
        connector.pathHashByteWidth,
      ));
    }
    if (contact.pathLength < 0) return l10n.chat_floodAuto;
    if (contact.pathLength == 0) return l10n.chat_direct;
    return l10n.chat_hopsCount(
      _hopCount(contact.path, contact.pathLength, contact.pathHashWidth),
    );
  }

  int _hopCount(List<int> path, int fallback, int hashWidth) =>
      path.isEmpty ? fallback : PathHelper.splitPathBytes(path, hashWidth).length;

  String? _floodRegionLabel(BuildContext context) {
    if ((contact.pathOverride ?? contact.pathLength) >= 0) return null;
    final l10n = context.l10n;
    final region = connector.getContactRegion(contact.publicKeyHex);
    if (ContactRegionStore.isUnscoped(region)) return l10n.chat_floodRegionNone;
    if (region.isNotEmpty) return l10n.channels_messageRegion(region);
    if (!connector.hasLoadedDefaultRegionScope) return l10n.chat_floodRegionNode;
    return l10n.chat_floodRegionNodeWith(
      connector.defaultRegionScopeLabel ?? l10n.channels_messageRegionEmpty,
    );
  }

  Future<void> _pickFloodRegion(BuildContext context) async {
    final region = await ContactRegionDialog.show(
      context,
      selectedRegion: connector.getContactRegion(contact.publicKeyHex),
    );
    if (region == null || !context.mounted) return;
    await connector.setContactRegion(contact.publicKeyHex, region);
  }
}

class ContactChatRoutingButton extends StatelessWidget {
  const ContactChatRoutingButton({
    super.key,
    required this.contact,
    this.onPressed,
  });

  final Contact contact;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(contact.pathOverride == -1 ? Icons.waves : Icons.route),
    tooltip: context.l10n.repeater_routingMode,
    onPressed: onPressed ??
        () => ContactRoutingSheet.show(context, contact: contact),
  );
}

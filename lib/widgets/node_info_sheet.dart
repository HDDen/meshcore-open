import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/offline_mode_helper.dart';
import '../l10n/app_localizations.dart';
import '../l10n/contact_localization.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../screens/chat_screen.dart';
import '../screens/repeater_hub_screen.dart';
import '../theme/mesh_theme.dart';
import 'mesh_ui.dart';
import 'node_memory_prompt.dart';
import 'repeater_login_dialog.dart';
import 'room_login_dialog.dart';

/// Map accent colour for a node type.
Color mapNodeTypeColor(int type) {
  switch (type) {
    case advTypeChat:
      return MapPalette.selected;
    case advTypeRepeater:
      return MapPalette.repeater;
    case advTypeRoom:
      return MapPalette.router;
    case advTypeSensor:
      return MapPalette.sensor;
    default:
      return MapPalette.offline;
  }
}

/// Map icon for a node type.
IconData mapNodeTypeIcon(int type) {
  switch (type) {
    case advTypeChat:
      return Icons.person;
    case advTypeRepeater:
      return Icons.router;
    case advTypeRoom:
      return Icons.meeting_room;
    case advTypeSensor:
      return Icons.sensors;
    default:
      return Icons.device_unknown;
  }
}

String formatNodeLastSeen(AppLocalizations l10n, DateTime lastSeen) {
  final difference = DateTime.now().difference(lastSeen);
  if (difference.inSeconds < 60) {
    return l10n.time_justNow;
  } else if (difference.inMinutes < 60) {
    return l10n.time_minutesAgo(difference.inMinutes);
  } else if (difference.inHours < 24) {
    return l10n.time_hoursAgo(difference.inHours);
  } else {
    return l10n.time_daysAgo(difference.inDays);
  }
}

/// Label above a selectable mono value, as used in node detail sheets.
class NodeInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const NodeInfoRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: MeshTheme.mono(fontSize: 13, color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

/// Repeater login, then the repeater hub on success.
void showRepeaterLoginDialog(BuildContext context, Contact repeater) {
  showDialog(
    context: context,
    builder: (context) => RepeaterLoginDialog(
      repeater: repeater,
      onLogin: (password, isAdmin) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RepeaterHubScreen(
              repeater: repeater,
              password: password,
              isAdmin: isAdmin,
            ),
          ),
        );
      },
    ),
  );
}

/// Room login, then the room chat (or the hub when [manage] is set).
void showRoomLoginDialog(
  BuildContext context,
  Contact room, {
  bool manage = false,
}) {
  showDialog(
    context: context,
    builder: (context) => RoomLoginDialog(
      room: room,
      onLogin: (password, isAdmin) {
        final connector = context.read<MeshCoreConnector>();
        final unread = connector.getUnreadCountForContactKey(room.publicKeyHex);
        if (manage) connector.markContactRead(room.publicKeyHex);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => manage
                ? RepeaterHubScreen(
                    repeater: room,
                    password: password,
                    isAdmin: isAdmin,
                  )
                : ChatScreen(contact: room, initialUnreadCount: unread),
          ),
        );
      },
    ),
  );
}

/// Shared presentation, with actions supplied by its owner. In particular,
/// the map retains its richer repeater menu and wardrive coverage controls.
/// Building this widget only reads the supplied contact; it sends no commands.
class NodeInfoSheet extends StatelessWidget {
  final Contact contact;
  final int pathHashByteWidth;
  final LatLng? guessedPosition;
  final List<Widget> actions;
  final IconData? icon;
  final Color? color;
  final String? lastSeenText;

  const NodeInfoSheet({
    super.key,
    required this.contact,
    required this.pathHashByteWidth,
    this.guessedPosition,
    this.actions = const [],
    this.icon,
    this.color,
    this.lastSeenText,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final estimate = guessedPosition;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BottomSheetHeader(
              title: contact.name,
              subtitle: contact.typeLabel(l10n),
              trailing: Icon(
                icon ?? mapNodeTypeIcon(contact.type),
                color: color ?? mapNodeTypeColor(contact.type),
                size: 20,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NodeInfoRow(
                    label: l10n.map_path,
                    value: contact.pathLabel(
                      l10n,
                      pathHashByteWidth: pathHashByteWidth,
                    ),
                  ),
                  if (contact.hasLocation)
                    NodeInfoRow(
                      label: l10n.map_location,
                      value: '${contact.latitude!.toStringAsFixed(6)}, ${contact.longitude!.toStringAsFixed(6)}',
                    )
                  else if (estimate != null)
                    NodeInfoRow(
                      label: l10n.map_estLocation,
                      value: '~${estimate.latitude.toStringAsFixed(6)}, ${estimate.longitude.toStringAsFixed(6)}',
                    ),
                  NodeInfoRow(
                    label: l10n.map_lastSeen,
                    // Keep owner labels; this fallback is display-only.
                    value: lastSeenText ??
                        formatNodeLastSeen(l10n, contact.lastHeard),
                  ),
                  NodeInfoRow(label: l10n.map_publicKey, value: contact.publicKeyHex),
                  const SizedBox(height: 16),
                  ...actions,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Details opened from the nearby list. Viewing does not import a discovered
/// contact or log in. An explicit action passes through the same confirmation
/// helper as the map before it can use a slot in the node's contact table.
void showNodeInfoSheet(
  BuildContext context,
  Contact contact, {
  required MeshCoreConnector connector,
}) {
  showMeshSheet<void>(
    context,
    builder: (sheetContext) {
      final l10n = sheetContext.l10n;
      void perform(void Function(Contact stored) action) {
        if (blockIfOffline(sheetContext, connector)) return;
        Navigator.pop(sheetContext);
        unawaited(runWithContactOnNode(context, connector, contact, action));
      }

      return NodeInfoSheet(
        contact: contact,
        pathHashByteWidth: connector.pathHashByteWidth,
        actions: [
          if (contact.type == advTypeRepeater)
            FilledButton(
              onPressed: () => perform(
                (stored) => showRepeaterLoginDialog(context, stored),
              ),
              child: Text(l10n.map_manageRepeater),
            ),
          if (contact.type == advTypeRoom) ...[
            FilledButton(
              onPressed: () => perform(
                (stored) => showRoomLoginDialog(context, stored),
              ),
              child: Text(l10n.map_joinRoom),
            ),
            FilledButton(
              onPressed: () => perform(
                (stored) => showRoomLoginDialog(context, stored, manage: true),
              ),
              child: Text(l10n.map_manageServer),
            ),
          ],
        ],
      );
    },
  );
}

/// A short routing prefix is an observation, not proof of a contact's identity.
/// Unknown or ambiguous entries expose only received data and no node actions.
void showHeardRepeaterInfoSheet(
  BuildContext context, {
  required String prefix,
  required double snr,
  required DateTime lastUpdated,
  String? candidateName,
}) {
  showMeshSheet<void>(
    context,
    builder: (sheetContext) {
      final l10n = sheetContext.l10n;
      return SafeArea(
        key: const ValueKey('heard-repeater-info'),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BottomSheetHeader(
                title: prefix,
                subtitle: candidateName == null
                    ? l10n.snrIndicator_unknownRepeater
                    : '(?) $candidateName',
                trailing: Icon(
                  mapNodeTypeIcon(advTypeRepeater),
                  color: mapNodeTypeColor(advTypeRepeater),
                  size: 20,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NodeInfoRow(label: l10n.map_publicKeyPrefix, value: prefix),
                    NodeInfoRow(
                      label: l10n.repeater_lastSnr,
                      value: '${snr.toStringAsFixed(1)} dB',
                    ),
                    NodeInfoRow(
                      label: l10n.map_lastSeen,
                      value: formatNodeLastSeen(l10n, lastUpdated),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      candidateName == null
                          ? l10n.snrIndicator_unknownRepeaterHint
                          : l10n.snrIndicator_ambiguousRepeaterHint,
                      style: TextStyle(
                        fontSize: 15,
                        color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

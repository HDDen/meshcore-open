import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:mco_service/mco_service.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/contact_action_data_helper.dart';
import '../helpers/neighbor_map_focus.dart';
import '../helpers/remove_contact_action.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/app_settings.dart' show SharedMessageHistoryModeValue;
import '../models/contact.dart';
import '../screens/map_screen.dart';
import '../screens/path_trace_map.dart';
import '../screens/repeater_hub_screen.dart';
import '../services/app_settings_service.dart';
import '../services/wardrive_service.dart';
import '../utils/radio_guard.dart';
import 'node_memory_prompt.dart';
import 'repeater_login_dialog.dart';
import 'repeater_options_sheet.dart';

/// Shared repeater actions for the contacts list and known discovery responders.
/// Contacts keeps its existing tracked export/share callbacks.
void showRepeaterActions(
  BuildContext context,
  MeshCoreConnector connector,
  Contact repeater, {
  Future<void> Function(Contact contact)? exportContact,
  Future<void> Function(Contact contact)? shareZeroHop,
  VoidCallback? onDelete,
}) {
  final wardrive = context.read<WardriveService>();
  showRepeaterOptionsSheet(
    context: context,
    repeater: repeater,
    onPing: () {
      final hashByteWidth = connector.pathHashByteWidth;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PathTraceMapScreen(
            title: context.l10n.contacts_repeaterPing,
            path: Uint8List(0),
            flipPathAround: true,
            targetContact: repeater,
            pathHashByteWidth: hashByteWidth,
            useLiveTargetPath: false,
          ),
        ),
      );
    },
    onManage: () => unawaited(
      runWithContactOnNode(
        context,
        connector,
        repeater,
        (stored) => _showRepeaterLogin(context, stored),
      ),
    ),
    onRequestRegions: () => unawaited(
      runWithContactOnNode(
        context,
        connector,
        repeater,
        (stored) =>
            _openRepeaterRegionRequestTrace(context, connector, stored),
      ),
    ),
    onToggleFavorite: () => unawaited(
      runWithContactOnNode(
        context,
        connector,
        repeater,
        (stored) => unawaited(
          connector.setContactFlags(stored, isFavorite: !stored.isFavorite),
        ),
      ),
    ),
    extraTilesBuilder: (sheetContext) => context
        .read<SettingsSectionsService>()
        .contactActionTiles(
          sheetContext,
          navigatorContext: context,
          contactName: repeater.name,
          contactType: repeater.type,
          contactKeyHex: repeater.publicKeyHex,
          spreadingFactor: connector.currentSf,
          loadRecords: ({isCancelled}) => ContactActionDataHelper.loadChannelRecords(
            connector,
            includeSharedHistory: context
                .read<AppSettingsService>()
                .settings
                .sharedMessageHistoryMode
                .includesChannels,
            isCancelled: isCancelled,
          ),
          loadNodes: () => ContactActionDataHelper.nodes(connector),
          openTrace: (pathBytes, hashByteWidth) =>
              _openServiceTrace(context, pathBytes, hashByteWidth),
          openEstimate: (estimate) =>
              _openServiceEstimate(context, estimate),
        ),
    ignoredInWardrive: wardrive.isRepeaterIgnored(repeater.publicKeyHex),
    onWardriveIgnoredChanged: (ignored) => unawaited(
      wardrive.setRepeaterIgnored(repeater.publicKeyHex, ignored),
    ),
    onShare: () => unawaited(
      runWithContactOnNode(
        context,
        connector,
        repeater,
        (stored) => unawaited(exportContact != null
            ? exportContact(stored) : _exportContact(context, connector, stored)),
      ),
    ),
    onShareZeroHop: () => unawaited(
      runWithContactOnNode(
        context,
        connector,
        repeater,
        (stored) => unawaited(shareZeroHop != null
            ? shareZeroHop(stored) : _shareZeroHop(context, connector, stored)),
      ),
    ),
    onDelete: onDelete ?? () => _confirmDelete(context, connector, repeater),
  );
}

void _showRepeaterLogin(BuildContext context, Contact repeater) {
  if (!ensureRadioConnected(context)) return;
  showDialog(
    context: context,
    builder: (context) => RepeaterLoginDialog(
      repeater: repeater,
      onLogin: (password, isAdmin) {
        // Navigate to repeater hub screen after successful login
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

Future<void> _openServiceTrace(
  BuildContext context,
  List<int> pathBytes,
  int hashByteWidth,
) async {
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => MapScreen(
        initialTracePath: Uint8List.fromList(pathBytes),
        initialTraceHashByteWidth: hashByteWidth,
        initializeInitialTraceViewport: true,
      ),
    ),
  );
}

Future<void> _openServiceEstimate(
  BuildContext context,
  McoContactActionEstimate estimate,
) async {
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => MapScreen(
        highlightPosition: LatLng(estimate.latitude, estimate.longitude),
        highlightLabel: estimate.label,
        highlightAsEstimate: true,
        neighborFocus: NeighborMapFocus.focusedRepeaters(
          repeaterKeys: [
            for (final key in estimate.anchorPublicKeys)
              pubKeyToHex(Uint8List.fromList(key)),
          ],
        ),
        highlightLinks: [
          for (var i = 0; i < estimate.anchorLatitudes.length; i++)
            LatLng(
              estimate.anchorLatitudes[i],
              estimate.anchorLongitudes[i],
            ),
        ],
      ),
    ),
  );
}

Uint8List _contactPathPrefix(Contact contact, int hashByteWidth) {
  if (contact.publicKey.isEmpty) return Uint8List(0);
  final width = hashByteWidth
      .clamp(1, pubKeySize)
      .toInt()
      .clamp(1, contact.publicKey.length)
      .toInt();
  return Uint8List.fromList(contact.publicKey.sublist(0, width));
}

void _openRepeaterRegionRequestTrace(
  BuildContext context,
  MeshCoreConnector connector,
  Contact repeater,
) {
  final hashByteWidth = connector.pathHashByteWidth;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MapScreen(
        initialTracePath: _contactPathPrefix(repeater, hashByteWidth),
        initialTraceHashByteWidth: hashByteWidth,
        initializeInitialTraceViewport: true,
        regionRequestTarget: repeater,
      ),
    ),
  );
}

void _confirmDelete(
  BuildContext context,
  MeshCoreConnector connector,
  Contact contact,
) {
  var keepHistory = false;
  showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(context.l10n.contacts_deleteContact),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.contacts_removeConfirm(contact.name)),
            if (connector.autoAddsContactType(contact.type)) ...[
              const SizedBox(height: 12),
              Text(
                context.l10n.contacts_removeAutoAddNote,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            // The conversation stays in the database and comes back with
            // the contact; the node's own record goes either way.
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: keepHistory,
              title: Text(context.l10n.contacts_keepChatHistory),
              onChanged: (value) =>
                  setDialogState(() => keepHistory = value ?? false),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              unawaited(deleteContactWithFeedback(
                context, connector, contact, keepMessages: keepHistory,
              ));
            },
            child: Text(
              context.l10n.common_delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _exportContact(
  BuildContext context, MeshCoreConnector connector, Contact contact,
) async {
  if (!ensureRadioConnected(context)) return;
  final response = Completer<Uint8List>();
  final subscription = connector.receivedFrames.listen((frame) {
    if (frame.isNotEmpty && frame.first == respCodeExportContact && !response.isCompleted) {
      response.complete(Uint8List.fromList(frame.sublist(1)));
    }
  });
  try {
    await connector.sendFrame(buildExportContactFrame(contact.publicKey), waitForGenericAck: true);
    final packet = await response.future.timeout(const Duration(seconds: 5));
    if (packet.length < 98) throw const FormatException('Invalid exported contact packet');
    await Clipboard.setData(ClipboardData(text: 'meshcore://${pubKeyToHex(packet)}'));
    if (context.mounted) {
      showDismissibleSnackBar(context, content: Text(context.l10n.contacts_contactAdvertCopied));
    }
  } catch (_) {
    if (context.mounted) {
      showDismissibleSnackBar(context, content: Text(context.l10n.contacts_contactAdvertCopyFailed));
    }
  } finally {
    await subscription.cancel();
  }
}

Future<void> _shareZeroHop(
  BuildContext context, MeshCoreConnector connector, Contact contact,
) async {
  if (!ensureRadioConnected(context)) return;
  try {
    await connector.sendFrame(buildZeroHopContact(contact.publicKey), waitForGenericAck: true);
    if (context.mounted) {
      showDismissibleSnackBar(context, content: Text(context.l10n.contacts_zeroHopContactAdvertSent));
    }
  } catch (_) {
    if (context.mounted) {
      showDismissibleSnackBar(context, content: Text(context.l10n.contacts_zeroHopContactAdvertFailed));
    }
  }
}

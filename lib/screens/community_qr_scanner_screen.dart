import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/community.dart';
import '../storage/community_store.dart';
import '../theme/mesh_theme.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/qr_scanner_widget.dart';

/// Screen for scanning community QR codes to join communities.
///
/// After successful scan, the user can:
/// 1. Join the community (saves to local storage)
/// 2. Optionally add the Community Public Channel to the device
class CommunityQrScannerScreen extends StatefulWidget {
  const CommunityQrScannerScreen({super.key});

  @override
  State<CommunityQrScannerScreen> createState() =>
      _CommunityQrScannerScreenState();
}

class _CommunityQrScannerScreenState extends State<CommunityQrScannerScreen> {
  final CommunityStore _communityStore = CommunityStore();
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AdaptiveAppBarTitle(context.l10n.community_scanQr),
        centerTitle: true,
      ),
      body: _isProcessing
          ? Container(
              color: Theme.of(context).colorScheme.surface,
              child: const Center(child: CircularProgressIndicator()),
            )
          : QrScannerWidget(
              onScanned: (data) => _handleScannedData(context, data),
              validator: Community.isValidQrData,
              onValidationFailed: (_) => _showInvalidQrError(context),
              instructions: context.l10n.community_scanInstructions,
              overlay: _buildThemedOverlay(context),
            ),
    );
  }

  Widget _buildThemedOverlay(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Dark semi-transparent background with cutout
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.5),
            BlendMode.srcOut,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Center(
                child: Container(
                  height: 250,
                  width: 250,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Corner brackets on top
        const ScannerCornerOverlay(
          scanWindowSize: 250,
          borderColor: MeshPalette.blue,
          borderWidth: 2,
          cornerLength: 24,
        ),
        // Instructions pill below the scan window
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 250 + 24),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(MeshRadii.pill),
                ),
                child: Text(
                  context.l10n.community_scanInstructions,
                  style: const TextStyle(color: MeshPalette.ink2, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleScannedData(BuildContext context, String data) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    final connector = context.read<MeshCoreConnector>();
    _communityStore.setPublicKeyHex = connector.selfPublicKeyHex;

    try {
      // Parse the community data
      final community = Community.fromQrData(const Uuid().v4(), data);

      // Check if this community already exists
      final existing = await _communityStore.findByCommunityId(
        community.communityId,
      );

      if (existing != null) {
        if (context.mounted) {
          _showAlreadyMemberDialog(context, existing);
        }
        return;
      }

      // Show confirmation dialog
      if (context.mounted) {
        await _showJoinConfirmationDialog(context, community);
      }
    } catch (e) {
      if (context.mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.community_invalidQrCode),
          backgroundColor: MeshPalette.alert,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _showInvalidQrError(BuildContext context) {
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.community_invalidQrCode),
      backgroundColor: MeshPalette.warn,
      duration: const Duration(seconds: 2),
    );
  }

  void _showAlreadyMemberDialog(BuildContext context, Community community) {
    showMeshSheet(
      context,
      builder: (sheetContext) {
        final sheetScheme = Theme.of(sheetContext).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BottomSheetHeader(title: context.l10n.community_alreadyMember),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                context.l10n.community_alreadyMemberMessage(community.name),
                style: TextStyle(color: sheetScheme.onSurfaceVariant),
              ),
            ),
            MeshCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.groups,
                    color: MeshPalette.magenta,
                    size: 32,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          community.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'ID: ${community.shortCommunityId}...',
                          style: MeshTheme.mono(
                            fontSize: 11.5,
                            color: sheetScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.pop(context);
                },
                child: Text(context.l10n.common_ok),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showJoinConfirmationDialog(
    BuildContext context,
    Community community,
  ) async {
    bool addPublicChannel = true;
    final completer = Completer<bool>();

    await showMeshSheet<void>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final joinScheme = Theme.of(sheetContext).colorScheme;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BottomSheetHeader(title: context.l10n.community_joinTitle),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  context.l10n.community_joinConfirmation(community.name),
                  style: TextStyle(color: joinScheme.onSurfaceVariant),
                ),
              ),
              MeshCard(
                child: Row(
                  children: [
                    AvatarCircle(
                      name: community.name,
                      icon: Icons.groups,
                      color: MeshPalette.magenta,
                      size: 44,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            community.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            'ID: ${community.shortCommunityId}...',
                            style: MeshTheme.mono(
                              fontSize: 11.5,
                              color: joinScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              CheckboxListTile(
                value: addPublicChannel,
                onChanged: (value) {
                  setSheetState(() {
                    addPublicChannel = value ?? true;
                  });
                },
                title: Text(context.l10n.community_addPublicChannel),
                subtitle: Text(context.l10n.community_addPublicChannelHint),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          completer.complete(false);
                          Navigator.pop(sheetContext);
                        },
                        child: Text(context.l10n.common_cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          completer.complete(true);
                          Navigator.pop(sheetContext);
                        },
                        child: Text(context.l10n.community_join),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    // If sheet was dismissed without a button press, treat as cancel
    if (!completer.isCompleted) {
      completer.complete(false);
    }

    final result = await completer.future;

    if (result && context.mounted) {
      await _joinCommunity(context, community, addPublicChannel);
    } else if (context.mounted) {
      // User cancelled - go back
      Navigator.pop(context);
    }
  }

  Future<void> _joinCommunity(
    BuildContext context,
    Community community,
    bool addPublicChannel,
  ) async {
    // Save community to local storage
    final connector = context.read<MeshCoreConnector>();
    _communityStore.setPublicKeyHex = connector.selfPublicKeyHex;
    await _communityStore.addCommunity(community);

    // Optionally add the community public channel to the device
    if (addPublicChannel && context.mounted) {
      final connector = context.read<MeshCoreConnector>();
      final nextIndex = _findNextAvailableChannelIndex(connector);

      if (nextIndex != null) {
        final psk = community.deriveCommunityPublicPsk();
        final channelName = '${community.name} Public';
        connector.setChannel(nextIndex, channelName, psk);
      }
    }

    if (context.mounted) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.community_joined(community.name)),
        backgroundColor: MeshPalette.signal,
      );

      // Return to previous screen
      Navigator.pop(context, community);
    }
  }

  int? _findNextAvailableChannelIndex(MeshCoreConnector connector) {
    final usedIndices = connector.channels.map((c) => c.index).toSet();
    for (int i = 0; i < connector.maxChannels; i++) {
      if (!usedIndices.contains(i)) return i;
    }
    return null;
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meshcore_open/screens/path_trace_map.dart';
import 'package:meshcore_open/services/notification_service.dart';
import 'package:meshcore_open/utils/app_logger.dart';
import 'package:meshcore_open/utils/platform_info.dart';
import 'package:meshcore_open/widgets/app_bar.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/chat_keyboard_navigation_history.dart';
import '../helpers/contact_share_helper.dart';
import '../helpers/offline_mode_helper.dart';
import '../helpers/path_helper.dart';
import '../l10n/l10n.dart';
import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../l10n/contact_localization.dart';
import '../models/contact_group.dart';
import '../services/app_settings_service.dart';
import '../services/ui_view_state_service.dart';
import '../services/wardrive_service.dart';
import '../theme/mesh_theme.dart';
import '../utils/contact_search.dart';
import '../storage/contact_group_store.dart';
import '../utils/dialog_utils.dart';
import '../utils/disconnect_navigation_mixin.dart';
import '../utils/emoji_utils.dart';
import '../utils/route_transitions.dart';
import '../widgets/list_filter_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/message_search_sheet.dart';
import '../widgets/quick_switch_bar.dart';
import '../widgets/quick_answers_selection_dialog.dart';
import '../widgets/repeater_login_dialog.dart';
import '../widgets/room_login_dialog.dart';
import '../widgets/popup_menu_row.dart';
import '../widgets/sync_progress_overlay.dart';
import '../widgets/unread_badge.dart';
import '../helpers/snack_bar_builder.dart';
import 'channels_screen.dart';
import 'chat_screen.dart';
import 'discovery_screen.dart';
import 'map_screen.dart';
import 'repeater_hub_screen.dart';
import 'settings_screen.dart';

enum RoomLoginDestination { chat, management }

enum ContactOperationType { import, export, zeroHopShare }

enum _BatchContactOperation { delete }

class ContactsBatchOperationsScreen extends StatelessWidget {
  const ContactsBatchOperationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ContactsScreen(batchOperationsMode: true);
  }
}

class ContactsScreen extends StatefulWidget {
  final bool hideBackButton;
  final bool selectionMode;
  final bool batchOperationsMode;

  const ContactsScreen({
    super.key,
    this.hideBackButton = false,
    this.selectionMode = false,
    this.batchOperationsMode = false,
  });

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen>
    with DisconnectNavigationMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ContactGroupStore _groupStore = ContactGroupStore();
  MeshCoreConnector? _scopeSyncConnector;
  List<ContactGroup> _groups = [];
  String _loadedGroupScopeKeyHex = '';
  Timer? _searchDebounce;

  final List<ContactOperationType> _pendingOperations = [];
  final Set<String> _selectedBatchContactKeys = {};
  bool _batchOperationInProgress = false;
  bool _batchOperationCancellationRequested = false;
  bool _allowBatchOperationPop = false;
  String? _activeBatchFailureMessage;

  StreamSubscription<Uint8List>? _frameSubscription;

  @override
  void initState() {
    super.initState();
    if (PlatformInfo.isDesktop) {
      HardwareKeyboard.instance.addHandler(_handleDesktopKeyEvent);
    }
    _searchController.text = context
        .read<UiViewStateService>()
        .contactsSearchText;
    _loadGroups();
    _setupFrameListener();
    _clearAdvertNotifications();
  }

  void _clearAdvertNotifications() {
    final connector = context.read<MeshCoreConnector>();
    final contactIds = connector.contacts.map((c) => c.publicKeyHex).toList();
    NotificationService().clearAdvertNotifications(contactIds);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final connector = context.read<MeshCoreConnector>();
    if (!identical(_scopeSyncConnector, connector)) {
      _scopeSyncConnector?.removeListener(_handleConnectorScopeChange);
      _scopeSyncConnector = connector;
      _scopeSyncConnector?.addListener(_handleConnectorScopeChange);
    }
    _handleConnectorScopeChange();
  }

  @override
  void dispose() {
    _batchOperationCancellationRequested = true;
    if (PlatformInfo.isDesktop) {
      HardwareKeyboard.instance.removeHandler(_handleDesktopKeyEvent);
    }
    _searchDebounce?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _frameSubscription?.cancel();
    _scopeSyncConnector?.removeListener(_handleConnectorScopeChange);
    super.dispose();
  }

  bool _handleDesktopKeyEvent(KeyEvent event) {
    if (!PlatformInfo.isDesktop ||
        widget.selectionMode ||
        widget.batchOperationsMode ||
        event is! KeyDownEvent) {
      return false;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    if ((PlatformInfo.isWindows || PlatformInfo.isLinux) &&
        event.logicalKey == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isControlPressed) {
      unawaited(_showMessageSearch(context));
      return true;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return false;
    }
    if (_searchFocusNode.hasFocus) {
      return false;
    }

    final target = ChatKeyboardNavigationHistory.lastTarget;
    if (target?.type != ChatKeyboardNavigationTargetType.contact) {
      return false;
    }
    final rememberedContact = target!.contact;
    if (rememberedContact == null) return false;

    final connector = context.read<MeshCoreConnector>();
    final contact = connector.contacts.firstWhere(
      (contact) => contact.publicKeyHex == rememberedContact.publicKeyHex,
      orElse: () => rememberedContact,
    );
    if (contact.type == advTypeRepeater) return false;
    final unread = connector.getUnreadCountForContactKey(contact.publicKeyHex);
    connector.markContactRead(contact.publicKeyHex);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ChatScreen(contact: contact, initialUnreadCount: unread),
      ),
    );
    return true;
  }

  Future<void> _showMessageSearch(BuildContext context) {
    return MessageSearchSheet.show(
      context,
      scope: MessageSearchScope.contacts,
      onOpenResult: (result) async {
        if (!context.mounted) return;
        final contact = result.contact;
        if (contact == null) return;
        final connector = context.read<MeshCoreConnector>();
        final unread = connector.getUnreadCountForContactKey(
          contact.publicKeyHex,
        );
        connector.markContactRead(contact.publicKeyHex);
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              contact: contact,
              initialUnreadCount: unread,
              initialMessageId: result.messageId,
            ),
          ),
        );
      },
    );
  }

  void _handleConnectorScopeChange() {
    final connector = _scopeSyncConnector;
    if (connector == null) return;
    _syncGroupScopeIfNeeded(connector);
  }

  Future<void> _loadGroups() async {
    final selfPublicKeyHex = context.read<MeshCoreConnector>().selfPublicKeyHex;
    if (selfPublicKeyHex.isEmpty) {
      return;
    }
    _groupStore.setPublicKeyHex = selfPublicKeyHex;
    final groups = await _groupStore.loadGroups();
    if (!mounted) return;
    setState(() {
      _loadedGroupScopeKeyHex = selfPublicKeyHex;
      _groups = groups;
      _ensureValidSelectedGroup();
    });
  }

  Future<void> _saveGroups() async {
    final selfPublicKeyHex = context.read<MeshCoreConnector>().selfPublicKeyHex;
    if (selfPublicKeyHex.isEmpty) {
      return;
    }
    _groupStore.setPublicKeyHex = selfPublicKeyHex;
    await _groupStore.saveGroups(_groups);
  }

  bool _hasGroupStoreScope(MeshCoreConnector connector) {
    return connector.selfPublicKeyHex.isNotEmpty;
  }

  void _syncGroupScopeIfNeeded(MeshCoreConnector connector) {
    final selfPublicKeyHex = connector.selfPublicKeyHex;
    if (selfPublicKeyHex.isEmpty ||
        selfPublicKeyHex == _loadedGroupScopeKeyHex) {
      return;
    }
    _loadGroups();
  }

  void _collapseContactsSearch(UiViewStateService viewState) {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _searchController.clear();
    viewState.setContactsSearchText('');
    viewState.setContactsSearchExpanded(false);
  }

  void _showGroupsUnavailableMessage(BuildContext context) {
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.common_loading),
    );
  }

  void _setupFrameListener() {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    // Listen for incoming text messages from the repeater
    _frameSubscription = connector.receivedFrames.listen((frame) {
      if (frame.isEmpty) return;
      final frameBuffer = BufferReader(frame);
      try {
        final code = frameBuffer.readUInt8();

        if (code == respCodeExportContact) {
          final advertPacket = frameBuffer.readRemainingBytes();
          // Validate packet has expected minimum size (98+ bytes per protocol)
          if (advertPacket.length < 98) {
            if (mounted) {
              showDismissibleSnackBar(
                context,
                content: Text(context.l10n.contacts_invalidAdvertFormat),
              );
            }
            _pendingOperations.remove(ContactOperationType.export);
            return;
          }
          final hexString = pubKeyToHex(advertPacket);
          Clipboard.setData(ClipboardData(text: "meshcore://$hexString"));
        }

        // Generic OK/ERR acks carry no command correlation, so consume only
        // the oldest pending operation per ack instead of clearing all.
        if (code == respCodeOk) {
          if (!mounted) return;
          if (_pendingOperations.isEmpty) return;
          final op = _pendingOperations.removeAt(0);
          switch (op) {
            case ContactOperationType.import:
              showDismissibleSnackBar(
                context,
                content: Text(context.l10n.contacts_contactImported),
              );
            case ContactOperationType.zeroHopShare:
              showDismissibleSnackBar(
                context,
                content: Text(context.l10n.contacts_zeroHopContactAdvertSent),
              );
            case ContactOperationType.export:
              showDismissibleSnackBar(
                context,
                content: Text(context.l10n.contacts_contactAdvertCopied),
              );
          }
        }

        if (code == respCodeErr) {
          if (!mounted) return;
          if (_pendingOperations.isEmpty) return;
          final op = _pendingOperations.removeAt(0);
          switch (op) {
            case ContactOperationType.import:
              showDismissibleSnackBar(
                context,
                content: Text(context.l10n.contacts_contactImportFailed),
              );
            case ContactOperationType.zeroHopShare:
              showDismissibleSnackBar(
                context,
                content: Text(context.l10n.contacts_zeroHopContactAdvertFailed),
              );
            case ContactOperationType.export:
              showDismissibleSnackBar(
                context,
                content: Text(context.l10n.contacts_contactAdvertCopyFailed),
              );
          }
        }
      } catch (e) {
        appLogger.error(
          'Error processing received frame: $e',
          tag: 'ContactsScreen',
        );
      }
    });
  }

  Future<void> _contactExport(Uint8List pubKey) async {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final exportContactFrame = buildExportContactFrame(pubKey);
    _pendingOperations.add(ContactOperationType.export);
    try {
      await connector.sendFrame(exportContactFrame, expectsGenericAck: true);
    } catch (e) {
      _pendingOperations.remove(ContactOperationType.export);
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_contactAdvertCopyFailed),
        );
      }
    }
  }

  Future<void> _contactZeroHop(Uint8List pubKey) async {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final exportContactZeroHopFrame = buildZeroHopContact(pubKey);
    _pendingOperations.add(ContactOperationType.zeroHopShare);
    try {
      await connector.sendFrame(
        exportContactZeroHopFrame,
        expectsGenericAck: true,
      );
    } catch (e) {
      _pendingOperations.remove(ContactOperationType.zeroHopShare);
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_zeroHopContactAdvertFailed),
        );
      }
    }
  }

  Future<void> _contactImport() async {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData == null || clipboardData.text == null) {
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_clipboardEmpty),
        );
      }
      return;
    }
    final text = clipboardData.text!.trim();
    if (!text.startsWith('meshcore://')) {
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_invalidAdvertFormat),
        );
      }
      return;
    }
    final hexString = text.substring('meshcore://'.length);
    final Uint8List importContactFrame;
    try {
      final bytes = hex2Uint8List(hexString);
      importContactFrame = buildImportContactFrame(bytes);
    } catch (e) {
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_invalidAdvertFormat),
        );
      }
      return;
    }
    _pendingOperations.add(ContactOperationType.import);
    try {
      await connector.sendFrame(importContactFrame, expectsGenericAck: true);
    } catch (e) {
      _pendingOperations.remove(ContactOperationType.import);
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_contactImportFailed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connector = context.watch<MeshCoreConnector>();

    // Auto-navigate back to scanner if disconnected
    if (!checkConnectionAndNavigate(connector)) {
      return const SizedBox.shrink();
    }

    final allowBack = widget.batchOperationsMode || !connector.isConnected;
    final canPop =
        allowBack && (!_batchOperationInProgress || _allowBatchOperationPop);
    final lockContactList =
        _batchOperationInProgress ||
        (connector.isLoadingContacts && connector.contacts.isNotEmpty);
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop &&
            widget.batchOperationsMode &&
            _batchOperationInProgress) {
          _cancelBatchOperationAndPop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: AppBarTitle(
            widget.batchOperationsMode
                ? context.l10n.contacts_batchOperations
                : context.l10n.contacts_title,
          ),
          automaticallyImplyLeading: widget.batchOperationsMode,
          bottom: const SyncProgressAppBarBottom(),
          actions: [
            if (widget.batchOperationsMode)
              PopupMenuButton<_BatchContactOperation>(
                enabled: !_batchOperationInProgress,
                tooltip: context.l10n.contacts_moreOptions,
                onSelected: (operation) {
                  switch (operation) {
                    case _BatchContactOperation.delete:
                      unawaited(_confirmBatchDelete(context, connector));
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _BatchContactOperation.delete,
                    child: PopupMenuRow(
                      icon: Icons.delete_outline,
                      iconColor: Theme.of(context).colorScheme.error,
                      text: context.l10n.common_delete,
                    ),
                  ),
                ],
                icon: const Icon(Icons.more_vert),
              )
            else
              PopupMenuButton(
                tooltip: context.l10n.contacts_moreOptions,
                itemBuilder: (context) {
                  if (connector.isOfflineMode) {
                    return <PopupMenuEntry<dynamic>>[
                      PopupMenuItem(
                        child: PopupMenuRow(
                          icon: Icons.logout,
                          iconColor: Theme.of(context).colorScheme.error,
                          text: context.l10n.common_disconnect,
                        ),
                        onTap: () => _disconnect(context, connector),
                      ),
                      PopupMenuItem(
                        child: PopupMenuRow(
                          icon: Icons.search,
                          text: context.l10n.chat_searchMessages,
                        ),
                        onTap: () => _showMessageSearch(this.context),
                      ),
                    ];
                  }
                  return <PopupMenuEntry<dynamic>>[
                    PopupMenuItem(
                      child: PopupMenuRow(
                        icon: Icons.person_add_rounded,
                        text: context.l10n.discoveredContacts_Title,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DiscoveryScreen(),
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      child: PopupMenuRow(
                        icon: Icons.vpn_key,
                        text: context.l10n.contacts_addContactByPubkey,
                      ),
                      onTap: () => _showAddContactByPubkeyDialog(context),
                    ),
                    PopupMenuItem(
                      child: PopupMenuRow(
                        icon: Icons.paste,
                        text: context.l10n.contacts_addContactFromClipboard,
                      ),
                      onTap: () => _contactImport(),
                    ),
                    PopupMenuItem(
                      child: PopupMenuRow(
                        icon: Icons.checklist,
                        text: context.l10n.contacts_batchOperations,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const ContactsBatchOperationsScreen(),
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      child: PopupMenuRow(
                        icon: Icons.search,
                        text: context.l10n.chat_searchMessages,
                      ),
                      onTap: () => _showMessageSearch(this.context),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      child: PopupMenuRow(
                        icon: Icons.connect_without_contact,
                        text: context.l10n.contacts_zeroHopAdvert,
                      ),
                      onTap: () => {
                        connector.sendSelfAdvert(flood: false),
                        showDismissibleSnackBar(
                          context,
                          content: Text(
                            context.l10n.settings_advertisementSent,
                          ),
                        ),
                      },
                    ),
                    PopupMenuItem(
                      child: PopupMenuRow(
                        icon: Icons.cell_tower,
                        text: context.l10n.contacts_floodAdvert,
                      ),
                      onTap: () => {
                        connector.sendSelfAdvert(flood: true),
                        showDismissibleSnackBar(
                          context,
                          content: Text(
                            context.l10n.settings_advertisementSent,
                          ),
                        ),
                      },
                    ),
                    PopupMenuItem(
                      child: PopupMenuRow(
                        icon: Icons.copy,
                        text: context.l10n.contacts_copyAdvertToClipboard,
                      ),
                      onTap: () => _contactExport(Uint8List.fromList([])),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      child: PopupMenuRow(
                        icon: Icons.logout,
                        iconColor: Theme.of(context).colorScheme.error,
                        text: context.l10n.common_disconnect,
                      ),
                      onTap: () => _disconnect(context, connector),
                    ),
                    PopupMenuItem(
                      child: PopupMenuRow(
                        icon: Icons.settings,
                        text: context.l10n.settings_title,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      ),
                    ),
                  ];
                },
                icon: const Icon(Icons.more_vert),
              ),
          ],
        ),
        body: IgnorePointer(
          ignoring: lockContactList,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: lockContactList ? 0.45 : 1,
                  duration: const Duration(milliseconds: 160),
                  child: _buildContactsBody(context, connector),
                ),
              ),
              if (_batchOperationInProgress)
                const Positioned.fill(
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
        floatingActionButton:
            widget.batchOperationsMode || connector.isOfflineMode
            ? null
            : FloatingActionButton(
                onPressed: connector.isLoadingContacts
                    ? null
                    : () => _showAddContactSheet(context),
                child: const Icon(Icons.person_add),
              ),
        bottomNavigationBar: widget.batchOperationsMode
            ? null
            : SafeArea(
                top: false,
                child: QuickSwitchBar(
                  selectedIndex: 0,
                  onDestinationSelected: (index) =>
                      _handleQuickSwitch(index, context),
                  contactsUnreadCount: connector.getTotalContactsUnreadCount(),
                  channelsUnreadCount: connector.getTotalChannelsUnreadCount(),
                ),
              ),
      ),
    );
  }

  void _toggleBatchContact(Contact contact) {
    if (_batchOperationInProgress) return;
    setState(() {
      if (!_selectedBatchContactKeys.add(contact.publicKeyHex)) {
        _selectedBatchContactKeys.remove(contact.publicKeyHex);
      }
    });
  }

  void _toggleAllFilteredBatchContacts(List<Contact> filteredContacts) {
    if (_batchOperationInProgress || filteredContacts.isEmpty) return;
    final filteredKeys = filteredContacts
        .map((contact) => contact.publicKeyHex)
        .toSet();
    final allFilteredSelected = filteredKeys.every(
      _selectedBatchContactKeys.contains,
    );
    setState(() {
      if (allFilteredSelected) {
        _selectedBatchContactKeys.removeAll(filteredKeys);
      } else {
        _selectedBatchContactKeys.addAll(filteredKeys);
      }
    });
  }

  List<Contact> _selectedBatchContacts(MeshCoreConnector connector) {
    return connector.contacts
        .where(
          (contact) => _selectedBatchContactKeys.contains(contact.publicKeyHex),
        )
        .toList(growable: false);
  }

  Future<void> _confirmBatchDelete(
    BuildContext context,
    MeshCoreConnector connector,
  ) async {
    final selectedContacts = _selectedBatchContacts(connector);
    if (selectedContacts.isEmpty) {
      _showBatchResult(
        context,
        context.l10n.contacts_batchOperations_notSelected,
        isError: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(context.l10n.contacts_batchOperations_removeConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              context.l10n.common_delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final successMessage = context.l10n.contacts_batchOperations_removeSuccess;
    final failureMessage = context.l10n.contacts_batchOperations_removeFail;

    await _runBatchOperation(
      contacts: selectedContacts,
      operation: (contact) =>
          connector.removeContact(contact, waitForAck: true),
      successMessage: successMessage,
      failureMessage: failureMessage,
    );
  }

  Future<void> _runBatchOperation({
    required List<Contact> contacts,
    required Future<void> Function(Contact contact) operation,
    required String successMessage,
    required String failureMessage,
  }) async {
    if (_batchOperationInProgress) return;
    setState(() {
      _batchOperationInProgress = true;
      _batchOperationCancellationRequested = false;
      _allowBatchOperationPop = false;
      _activeBatchFailureMessage = failureMessage;
    });

    final failedKeys = <String>{};
    for (final contact in contacts) {
      if (_batchOperationCancellationRequested) break;
      try {
        await operation(contact);
      } catch (error) {
        failedKeys.add(contact.publicKeyHex);
        appLogger.error(
          'Batch contact operation failed for ${contact.publicKeyHex}: $error',
          tag: 'ContactsScreen',
          noNotify: true,
        );
      }
    }

    if (_batchOperationCancellationRequested) return;
    if (!mounted) return;
    setState(() {
      _batchOperationInProgress = false;
      _activeBatchFailureMessage = null;
      _selectedBatchContactKeys
        ..clear()
        ..addAll(failedKeys);
    });
    _showBatchResult(
      context,
      failedKeys.isEmpty ? successMessage : failureMessage,
      isError: failedKeys.isNotEmpty,
    );
  }

  void _cancelBatchOperationAndPop() {
    if (_batchOperationCancellationRequested || !mounted) return;
    final failureMessage =
        _activeBatchFailureMessage ??
        context.l10n.contacts_batchOperations_commonFail;
    setState(() {
      _batchOperationCancellationRequested = true;
      _allowBatchOperationPop = true;
    });
    _showBatchResult(context, failureMessage, isError: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(Navigator.of(context).maybePop());
    });
  }

  void _showBatchResult(
    BuildContext context,
    String message, {
    required bool isError,
  }) {
    showDismissibleSnackBar(
      context,
      content: Text(message),
      backgroundColor: isError
          ? Theme.of(context).colorScheme.error
          : MeshPalette.signal,
    );
  }

  Future<void> _showAddContactByPubkeyDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final pubkeyController = TextEditingController();
    int selectedType = advTypeChat;
    String? formError;
    bool isSaving = false;

    SharedContactInfo buildContactInfo() {
      final publicKeyHex = pubkeyController.text.replaceAll(
        RegExp(r'[^0-9a-fA-F]'),
        '',
      );
      final publicKey = hexToPubKey(publicKeyHex);
      final name = nameController.text.trim();
      return SharedContactInfo(
        publicKey: publicKey,
        type: selectedType,
        name: name.isEmpty ? publicKeyHex.substring(0, 8) : name,
      );
    }

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> saveContact() async {
              SharedContactInfo contact;
              try {
                contact = buildContactInfo();
              } on FormatException {
                setDialogState(() {
                  formError = dialogContext.l10n.contacts_contactImportFailed;
                });
                return;
              }

              setDialogState(() {
                isSaving = true;
                formError = null;
              });

              final added = await _addSharedContact(contact);
              if (!mounted) return;
              if (added && dialogContext.mounted) {
                Navigator.pop(dialogContext);
                return;
              }
              if (dialogContext.mounted) {
                setDialogState(() {
                  isSaving = false;
                });
              }
            }

            return AlertDialog(
              title: Text(dialogContext.l10n.contacts_addContactByPubkey),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: selectedType,
                      decoration: InputDecoration(
                        labelText: dialogContext
                            .l10n
                            .contacts_addContactByPubkey_contactType,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: advTypeChat,
                          child: Text(dialogContext.l10n.chat_contactTypeNode),
                        ),
                        DropdownMenuItem(
                          value: advTypeRepeater,
                          child: Text(
                            dialogContext.l10n.chat_contactTypeRepeater,
                          ),
                        ),
                        DropdownMenuItem(
                          value: advTypeRoom,
                          child: Text(dialogContext.l10n.chat_contactTypeRoom),
                        ),
                        DropdownMenuItem(
                          value: advTypeSensor,
                          child: Text(
                            dialogContext.l10n.chat_contactTypeSensor,
                          ),
                        ),
                      ],
                      onChanged: isSaving
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() {
                                selectedType = value;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      enabled: !isSaving,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: dialogContext.l10n.settings_nodeName,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pubkeyController,
                      enabled: !isSaving,
                      minLines: 2,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: dialogContext.l10n.chat_publicKey,
                        errorText: formError,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(dialogContext.l10n.common_cancel),
                ),
                TextButton(
                  onPressed: isSaving ? null : saveContact,
                  child: Text(dialogContext.l10n.common_save),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      nameController.dispose();
      pubkeyController.dispose();
    }
  }

  Future<bool> _addSharedContact(SharedContactInfo contact) async {
    final connector = context.read<MeshCoreConnector>();
    final selfPublicKey = connector.selfPublicKey;
    if (selfPublicKey != null &&
        selfPublicKey.isNotEmpty &&
        contact.publicKeyHex == connector.selfPublicKeyHex) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.chat_contactIsYou),
      );
      return false;
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
      if (replace != true || !mounted) return false;
    }

    try {
      await connector.addOrUpdateSharedContact(
        publicKey: contact.publicKey,
        type: contact.type,
        name: contact.name,
      );
      if (!mounted) return false;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.contacts_contactImported),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.contacts_contactImportFailed),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
      return false;
    }
  }

  void _showAddContactSheet(BuildContext context) {
    showMeshSheet(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BottomSheetHeader(title: context.l10n.contacts_title),
              ListTile(
                leading: const Icon(Icons.vpn_key),
                title: Text(context.l10n.contacts_addContactByPubkey),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showAddContactByPubkeyDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.paste),
                title: Text(context.l10n.contacts_addContactFromClipboard),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _contactImport();
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_add_rounded),
                title: Text(context.l10n.discoveredContacts_Title),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DiscoveryScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _disconnect(
    BuildContext context,
    MeshCoreConnector connector,
  ) async {
    await showDisconnectDialog(context, connector);
  }

  ContactGroup? _selectedGroupForName(String selectedGroupName) {
    if (selectedGroupName == contactsAllGroupsValue) return null;
    for (final group in _groups) {
      if (group.name == selectedGroupName) return group;
    }
    return null;
  }

  void _ensureValidSelectedGroup() {
    final viewState = context.read<UiViewStateService>();
    if (viewState.contactsSelectedGroupName == contactsAllGroupsValue) return;
    final exists = _groups.any(
      (group) => group.name == viewState.contactsSelectedGroupName,
    );
    if (!exists) {
      viewState.setContactsSelectedGroupName(contactsAllGroupsValue);
    }
  }

  void _closeDropdownAndRun(BuildContext popupContext, VoidCallback action) {
    final route = ModalRoute.of(popupContext);
    if (route != null && route.isCurrent) {
      Navigator.of(popupContext).pop();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      action();
    });
  }

  Widget _buildFilterButton(
    BuildContext context,
    UiViewStateService viewState,
  ) {
    return ContactsFilterMenu(
      sortOption: viewState.contactsSortOption,
      typeFilter: viewState.contactsTypeFilter,
      showUnreadOnly: viewState.contactsShowUnreadOnly,
      onSortChanged: (value) {
        viewState.setContactsSortOption(value);
      },
      onTypeFilterChanged: (value) {
        viewState.setContactsTypeFilter(value);
      },
      onUnreadOnlyChanged: (value) {
        viewState.setContactsShowUnreadOnly(value);
      },
    );
  }

  Widget _buildGroupButton(
    BuildContext context,
    MeshCoreConnector connector,
    UiViewStateService viewState,
    List<Contact> contacts,
    List<ContactGroup> sortedGroups,
  ) {
    final canManageGroups = _hasGroupStoreScope(connector);
    final selectedGroupName =
        _selectedGroupForName(viewState.contactsSelectedGroupName)?.name ??
        context.l10n.listFilter_all;
    final double menuWidth = (MediaQuery.sizeOf(context).width - 16).clamp(
      0.0,
      double.infinity,
    );

    return PopupMenuButton<String>(
      position: PopupMenuPosition.under,
      constraints: BoxConstraints.tightFor(width: menuWidth),
      onSelected: (String value) {
        viewState.setContactsSelectedGroupName(value);
      },
      itemBuilder: (menuContext) => [
        PopupMenuItem<String>(
          value: contactsAllGroupsValue,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(menuContext.l10n.listFilter_all),
              IconButton(
                tooltip: menuContext.l10n.contacts_newGroup,
                icon: const Icon(Icons.group_add, size: 20),
                onPressed: canManageGroups
                    ? () => _closeDropdownAndRun(
                        menuContext,
                        () => _showGroupEditor(this.context, contacts),
                      )
                    : () => _closeDropdownAndRun(
                        menuContext,
                        () => _showGroupsUnavailableMessage(this.context),
                      ),
              ),
            ],
          ),
        ),
        ...sortedGroups.map((group) {
          return PopupMenuItem<String>(
            value: group.name,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(group.name, overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  tooltip: menuContext.l10n.contacts_editGroup,
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: canManageGroups
                      ? () => _closeDropdownAndRun(
                          menuContext,
                          () => _showGroupEditor(
                            this.context,
                            contacts,
                            group: group,
                          ),
                        )
                      : () => _closeDropdownAndRun(
                          menuContext,
                          () => _showGroupsUnavailableMessage(this.context),
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: menuContext.l10n.contacts_deleteGroup,
                  icon: Icon(
                    Icons.delete,
                    size: 20,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: canManageGroups
                      ? () => _closeDropdownAndRun(
                          menuContext,
                          () => _confirmDeleteGroup(this.context, group),
                        )
                      : () => _closeDropdownAndRun(
                          menuContext,
                          () => _showGroupsUnavailableMessage(this.context),
                        ),
                ),
              ],
            ),
          );
        }),
      ],
      child: SizedBox(
        height: 48,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedGroupName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactsBody(BuildContext context, MeshCoreConnector connector) {
    final viewState = context.watch<UiViewStateService>();
    final contacts = connector.contacts;
    final waitingForInitialContacts =
        connector.isConnected &&
        !connector.hasLoadedContacts &&
        !connector.isLoadingContacts;
    final waitingForFirstContact =
        connector.isLoadingContacts && contacts.isEmpty;

    if (waitingForInitialContacts || waitingForFirstContact) {
      return const Center(child: CircularProgressIndicator());
    }

    if (contacts.isEmpty && _groups.isEmpty) {
      return EmptyState(
        icon: Icons.people_outline,
        title: context.l10n.contacts_noContacts,
        subtitle: context.l10n.contacts_contactsWillAppear,
        action: FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const DiscoveryScreen()),
          ),
          icon: const Icon(Icons.person_add_rounded),
          label: Text(context.l10n.discoveredContacts_Title),
        ),
      );
    }

    final filteredAndSorted = _filterAndSortContacts(
      contacts,
      connector,
      viewState,
    );
    final batchSelectableContacts = _contactsMatchingBatchFilter(
      contacts,
      connector,
      viewState,
    );
    final allFilteredBatchContactsSelected =
        batchSelectableContacts.isNotEmpty &&
        batchSelectableContacts.every(
          (contact) => _selectedBatchContactKeys.contains(contact.publicKeyHex),
        );

    String hintText = "";

    switch (viewState.contactsTypeFilter) {
      case ContactTypeFilter.all:
        hintText = context.l10n.contacts_searchContacts(
          filteredAndSorted.length,
          viewState.contactsShowUnreadOnly
              ? " ${context.l10n.contacts_unread}"
              : "",
        );
        break;
      case ContactTypeFilter.users:
        hintText = context.l10n.contacts_searchUsers(
          filteredAndSorted.length,
          viewState.contactsShowUnreadOnly
              ? " ${context.l10n.contacts_unread}"
              : "",
        );
        break;
      case ContactTypeFilter.repeaters:
        hintText = context.l10n.contacts_searchRepeaters(
          filteredAndSorted.length,
          viewState.contactsShowUnreadOnly
              ? " ${context.l10n.contacts_unread}"
              : "",
        );
        break;
      case ContactTypeFilter.rooms:
        hintText = context.l10n.contacts_searchRoomServers(
          filteredAndSorted.length,
          viewState.contactsShowUnreadOnly
              ? " ${context.l10n.contacts_unread}"
              : "",
        );
        break;
      case ContactTypeFilter.favorites:
        hintText = context.l10n.contacts_searchFavorites(
          filteredAndSorted.length,
          viewState.contactsShowUnreadOnly
              ? " ${context.l10n.contacts_unread}"
              : "",
        );
        break;
    }

    final groupsByName = <String, ContactGroup>{};
    for (final group in _groups) {
      groupsByName.putIfAbsent(group.name, () => group);
    }
    final sortedGroups = groupsByName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final screenWidth = MediaQuery.sizeOf(context).width;
    final searchControlsMinWidth = widget.batchOperationsMode ? 146.0 : 97.0;
    final searchControlsMaxWidth = widget.batchOperationsMode ? 169.0 : 120.0;
    final compactGroupWidth = (screenWidth * 0.21).clamp(76.0, 128.0);
    final searchExpandedWidth = (screenWidth - 24 - compactGroupWidth).clamp(
      searchControlsMinWidth,
      520.0,
    );
    final searchCollapsedWidth = (screenWidth * 0.22).clamp(
      searchControlsMinWidth,
      searchControlsMaxWidth,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: _buildGroupButton(
                  context,
                  connector,
                  viewState,
                  contacts,
                  sortedGroups,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: viewState.contactsSearchExpanded
                    ? searchExpandedWidth
                    : searchCollapsedWidth,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: viewState.contactsSearchExpanded
                            ? TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: hintText,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
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
                                          .setContactsSearchText(value);
                                    },
                                  );
                                },
                              )
                            : const SizedBox.shrink(),
                      ),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          tooltip: viewState.contactsSearchExpanded
                              ? context.l10n.contacts_searchClose
                              : context.l10n.contacts_searchOpen,
                          onPressed: () {
                            if (viewState.contactsSearchExpanded) {
                              _collapseContactsSearch(viewState);
                              return;
                            }
                            viewState.setContactsSearchExpanded(true);
                          },
                          icon: Icon(
                            viewState.contactsSearchExpanded
                                ? Icons.close
                                : Icons.search,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 24,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: _buildFilterButton(context, viewState),
                      ),
                      if (widget.batchOperationsMode) ...[
                        Container(
                          width: 1,
                          height: 24,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: IconButton(
                            tooltip: context.l10n.listFilter_all,
                            isSelected: allFilteredBatchContactsSelected,
                            onPressed: batchSelectableContacts.isEmpty
                                ? null
                                : () => _toggleAllFilteredBatchContacts(
                                    batchSelectableContacts,
                                  ),
                            icon: const Icon(Icons.done_all),
                            selectedIcon: Icon(
                              Icons.done_all,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => connector.getContacts(),
            child: filteredAndSorted.isEmpty
                ? LayoutBuilder(
                    builder: (context, constraints) => ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: EmptyState(
                            icon: Icons.search_off,
                            title: viewState.contactsShowUnreadOnly
                                ? context.l10n.contacts_noUnreadContacts
                                : context.l10n.contacts_noContactsFound,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: filteredAndSorted.length,
                    itemBuilder: (context, index) {
                      final contact = filteredAndSorted[index];
                      final unreadCount = connector.getUnreadCountForContact(
                        contact,
                      );
                      return _ContactTileEntrance(
                        index: index,
                        contact: contact,
                        pathHashByteWidth: connector.pathHashByteWidth,
                        lastSeen: _resolveLastSeen(contact),
                        unreadCount: unreadCount,
                        isFavorite: contact.isFavorite,
                        isSelected: widget.batchOperationsMode
                            ? _selectedBatchContactKeys.contains(
                                contact.publicKeyHex,
                              )
                            : null,
                        onSelectionChanged: widget.batchOperationsMode
                            ? (_) => _toggleBatchContact(contact)
                            : null,
                        onTap: () {
                          if (widget.batchOperationsMode) {
                            _toggleBatchContact(contact);
                          } else if (widget.selectionMode) {
                            Navigator.pop(context, contact);
                          } else {
                            _openChat(context, contact);
                          }
                        },
                        onLongPress: connector.isOfflineMode
                            ? null
                            : () => _showContactOptions(
                                context,
                                connector,
                                contact,
                              ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  List<Contact> _filterAndSortContacts(
    List<Contact> contacts,
    MeshCoreConnector connector,
    UiViewStateService viewState,
  ) {
    var filtered = contacts.where((contact) {
      if (viewState.contactsSearchText.isEmpty) return true;
      return matchesContactQuery(contact, viewState.contactsSearchText);
    }).toList();

    final selectedGroup = _selectedGroupForName(
      viewState.contactsSelectedGroupName,
    );
    if (selectedGroup != null) {
      final memberKeys = selectedGroup.memberKeys.toSet();
      filtered = filtered
          .where((contact) => memberKeys.contains(contact.publicKeyHex))
          .toList();
    }

    // Filter out own node from the list
    if (connector.selfPublicKey != null) {
      final selfPubKeyHex = pubKeyToHex(connector.selfPublicKey!);
      filtered = filtered.where((contact) {
        return contact.publicKeyHex != selfPubKeyHex;
      }).toList();
    }

    if (viewState.contactsTypeFilter != ContactTypeFilter.all) {
      filtered = filtered
          .where(
            (contact) =>
                _matchesTypeFilter(contact, viewState.contactsTypeFilter),
          )
          .toList();
    }

    if (viewState.contactsShowUnreadOnly) {
      filtered = filtered.where((contact) {
        return connector.getUnreadCountForContact(contact) > 0;
      }).toList();
    }

    switch (viewState.contactsSortOption) {
      case ContactSortOption.lastSeen:
        filtered.sort(
          (a, b) => _resolveLastSeen(b).compareTo(_resolveLastSeen(a)),
        );
        break;
      case ContactSortOption.recentMessages:
        filtered.sort((a, b) {
          final aAt = _resolveLastDirectMessageAt(a, connector);
          final bAt = _resolveLastDirectMessageAt(b, connector);
          // Contacts without direct history sort below the ones that have it,
          // whatever their advert activity says.
          if (aAt == null || bAt == null) {
            if (aAt != null) return -1;
            if (bAt != null) return 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          final byTime = bAt.compareTo(aAt);
          if (byTime != 0) return byTime;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;
      case ContactSortOption.name:
        filtered.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
    }

    return filtered;
  }

  List<Contact> _contactsMatchingBatchFilter(
    List<Contact> contacts,
    MeshCoreConnector connector,
    UiViewStateService viewState,
  ) {
    final selfPubKeyHex = connector.selfPublicKey == null
        ? null
        : pubKeyToHex(connector.selfPublicKey!);
    return contacts
        .where((contact) {
          if (contact.publicKeyHex == selfPubKeyHex) return false;
          if (viewState.contactsTypeFilter != ContactTypeFilter.all &&
              !_matchesTypeFilter(contact, viewState.contactsTypeFilter)) {
            return false;
          }
          if (viewState.contactsShowUnreadOnly &&
              connector.getUnreadCountForContact(contact) == 0) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  bool _matchesTypeFilter(Contact contact, ContactTypeFilter typeFilter) {
    switch (typeFilter) {
      case ContactTypeFilter.all:
        return true;
      case ContactTypeFilter.favorites:
        return contact.isFavorite;
      case ContactTypeFilter.users:
        return contact.type == advTypeChat;
      case ContactTypeFilter.repeaters:
        return contact.type == advTypeRepeater;
      case ContactTypeFilter.rooms:
        return contact.type == advTypeRoom;
    }
  }

  /// Timestamp of the newest real direct message for [contact], or null when
  /// no direct history exists.
  ///
  /// Contact.lastMessageAt cannot be used here: it falls back to lastSeen when
  /// a contact has no messages at all, and channel activity advances it for
  /// name-matched contacts, so sorting by it interleaves silent contacts by
  /// advert time. The connector's message-summary cache is built from stored
  /// direct history only, and it already folds in shared history exactly when
  /// that mode covers contacts, so the setting needs no separate check here.
  /// The in-memory conversation is consulted as well, because it can hold a
  /// message that arrived after the summary cache was last rebuilt.
  DateTime? _resolveLastDirectMessageAt(
    Contact contact,
    MeshCoreConnector connector,
  ) {
    final cached = connector.getContactMessagePreview(contact)?.timestamp;
    final loaded = connector.getLoadedMessages(contact);
    final live = loaded.isNotEmpty ? loaded.last.timestamp : null;
    if (cached == null) return live;
    if (live == null) return cached;
    return live.isAfter(cached) ? live : cached;
  }

  DateTime _resolveLastSeen(Contact contact) {
    if (contact.type != advTypeChat) return contact.lastSeen;
    return contact.lastMessageAt.isAfter(contact.lastSeen)
        ? contact.lastMessageAt
        : contact.lastSeen;
  }

  void _openChat(BuildContext context, Contact contact) {
    final connector = context.read<MeshCoreConnector>();
    if (connector.isOfflineMode) {
      if (contact.type == advTypeRepeater) {
        blockIfOffline(context, connector);
        return;
      }
      final unread = connector.getUnreadCountForContactKey(
        contact.publicKeyHex,
      );
      connector.markContactRead(contact.publicKeyHex);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ChatScreen(contact: contact, initialUnreadCount: unread),
        ),
      );
      return;
    }
    // Check if this is a repeater
    if (contact.type == advTypeRepeater) {
      _showRepeaterLogin(context, contact);
    } else if (contact.type == advTypeRoom) {
      _showRoomLogin(context, contact, RoomLoginDestination.chat);
    } else {
      final unread = connector.getUnreadCountForContactKey(
        contact.publicKeyHex,
      );
      connector.markContactRead(contact.publicKeyHex);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ChatScreen(contact: contact, initialUnreadCount: unread),
        ),
      );
    }
  }

  void _handleQuickSwitch(int index, BuildContext context) {
    if (index == 0) return;
    switch (index) {
      case 1:
        Navigator.pushReplacement(
          context,
          buildQuickSwitchRoute(const ChannelsScreen(hideBackButton: true)),
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

  void _showRepeaterLogin(BuildContext context, Contact repeater) {
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

  void _showRoomLogin(
    BuildContext context,
    Contact room,
    RoomLoginDestination destination,
  ) {
    showDialog(
      context: context,
      builder: (context) => RoomLoginDialog(
        room: room,
        onLogin: (password, isAdmin) {
          final connector = context.read<MeshCoreConnector>();
          final unread = connector.getUnreadCountForContactKey(
            room.publicKeyHex,
          );
          connector.markContactRead(room.publicKeyHex);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  destination == RoomLoginDestination.management
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

  void _confirmDeleteGroup(BuildContext context, ContactGroup group) {
    if (!_hasGroupStoreScope(context.read<MeshCoreConnector>())) {
      _showGroupsUnavailableMessage(context);
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.contacts_deleteGroup),
        content: Text(context.l10n.contacts_deleteGroupConfirm(group.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              setState(() {
                _groups.removeWhere((g) => g.name == group.name);
                _ensureValidSelectedGroup();
              });
              await _saveGroups();
            },
            child: Text(
              context.l10n.common_delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showGroupEditor(
    BuildContext context,
    List<Contact> contacts, {
    ContactGroup? group,
  }) {
    if (!_hasGroupStoreScope(context.read<MeshCoreConnector>())) {
      _showGroupsUnavailableMessage(context);
      return;
    }
    final isEditing = group != null;
    final nameController = TextEditingController(text: group?.name ?? '');
    final selectedKeys = <String>{...group?.memberKeys ?? []};
    String filterQuery = '';
    final sortedContacts = List<Contact>.from(contacts)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) {
          final filteredContacts = filterQuery.isEmpty
              ? sortedContacts
              : sortedContacts
                    .where(
                      (contact) => matchesContactQuery(contact, filterQuery),
                    )
                    .toList();
          return AlertDialog(
            title: Text(
              isEditing
                  ? context.l10n.contacts_editGroup
                  : context.l10n.contacts_newGroup,
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
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
                    TextField(
                      decoration: InputDecoration(
                        hintText: context.l10n.contacts_filterContacts,
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          filterQuery = value.toLowerCase();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredContacts.isEmpty
                          ? Center(
                              child: Text(
                                context.l10n.contacts_noContactsMatchFilter,
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredContacts.length,
                              itemBuilder: (context, index) {
                                final contact = filteredContacts[index];
                                final isSelected = selectedKeys.contains(
                                  contact.publicKeyHex,
                                );
                                return CheckboxListTile(
                                  value: isSelected,
                                  title: Text(contact.name),
                                  subtitle: Text(
                                    contact.typeLabel(context.l10n),
                                  ),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        selectedKeys.add(contact.publicKeyHex);
                                      } else {
                                        selectedKeys.remove(
                                          contact.publicKeyHex,
                                        );
                                      }
                                    });
                                  },
                                );
                              },
                            ),
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
                  if (name.toLowerCase() ==
                      contactsAllGroupsValue.toLowerCase()) {
                    showDismissibleSnackBar(
                      context,
                      content: Text(context.l10n.contacts_groupNameReserved),
                    );
                    return;
                  }
                  final exists = _groups.any((g) {
                    if (isEditing && g.name == group.name) return false;
                    return g.name.toLowerCase() == name.toLowerCase();
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
                  setState(() {
                    final viewState = context.read<UiViewStateService>();
                    if (isEditing) {
                      final index = _groups.indexWhere(
                        (g) => g.name == group.name,
                      );
                      if (index != -1) {
                        final wasSelected =
                            viewState.contactsSelectedGroupName == group.name;
                        _groups[index] = ContactGroup(
                          name: name,
                          memberKeys: selectedKeys.toList(),
                        );
                        if (wasSelected) {
                          viewState.setContactsSelectedGroupName(name);
                        }
                      }
                    } else {
                      _groups.add(
                        ContactGroup(
                          name: name,
                          memberKeys: selectedKeys.toList(),
                        ),
                      );
                      viewState.setContactsSelectedGroupName(name);
                    }
                    _ensureValidSelectedGroup();
                  });
                  await _saveGroups();
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                child: Text(
                  isEditing
                      ? context.l10n.common_save
                      : context.l10n.common_create,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showContactOptions(
    BuildContext context,
    MeshCoreConnector connector,
    Contact contact,
  ) {
    final isRepeater = contact.type == advTypeRepeater;
    final isRoom = contact.type == advTypeRoom;
    final isFavorite = contact.isFavorite;
    final wardrive = context.read<WardriveService>();
    bool ignoredInWardrive =
        isRepeater && wardrive.isRepeaterIgnored(contact.publicKeyHex);
    final appSettingsService = isRoom
        ? Provider.of<AppSettingsService>(context, listen: false)
        : null;
    if (isRoom) {
      connector.ensureContactMcmpSettingLoaded(contact.publicKeyHex);
      connector.ensureContactSmazSettingLoaded(contact.publicKeyHex);
      connector.ensureContactCyr2LatSettingLoaded(contact.publicKeyHex);
      connector.ensureContactSendingDelaySettingLoaded(contact.publicKeyHex);
      connector.ensureContactQuickAnswerIdsLoaded(contact.publicKeyHex);
    }
    bool mcmpEnabled =
        isRoom && connector.isContactMcmpEnabled(contact.publicKeyHex);
    int selectedMcmpVersion = isRoom
        ? connector.contactMcmpVersion(contact.publicKeyHex)
        : 2;
    bool mcmpUseSign = isRoom
        ? connector.contactMcmpUseSign(contact.publicKeyHex)
        : true;
    bool smazEnabled =
        isRoom && connector.isContactSmazEnabled(contact.publicKeyHex);
    bool cyr2latEnabled =
        isRoom && connector.isContactCyr2LatEnabled(contact.publicKeyHex);
    bool sendingDelayEnabled =
        isRoom && connector.isContactSendingDelayEnabled(contact.publicKeyHex);
    List<String> selectedQuickAnswerIds = isRoom
        ? connector.getContactQuickAnswerIds(contact.publicKeyHex)
        : const [];
    String? selectedCyr2LatProfileId = isRoom
        ? connector.getContactCyr2LatProfileId(contact.publicKeyHex)
        : null;

    showMeshSheet(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BottomSheetHeader(
                  title: contact.name,
                  subtitle: contact.typeLabel(context.l10n),
                ),
                if (isRepeater) ...[
                  ListTile(
                    leading: Icon(Icons.radar, color: MeshPalette.signal),
                    title: Text(context.l10n.contacts_ping),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      final hw = context
                          .read<MeshCoreConnector>()
                          .pathHashByteWidth;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PathTraceMapScreen(
                            title: context.l10n.contacts_repeaterPing,
                            path: contact.pathBytesForDisplay.isNotEmpty
                                ? contact.pathBytesForDisplay
                                : _contactPathPrefix(contact, hw),
                            flipPathAround: true,
                            targetContact: contact,
                            pathHashByteWidth: hw,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.cell_tower, color: MeshPalette.warn),
                    title: Text(context.l10n.contacts_manageRepeater),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showRepeaterLogin(context, contact);
                    },
                  ),
                ] else if (isRoom) ...[
                  ListTile(
                    leading: Icon(Icons.radar, color: MeshPalette.signal),
                    title: Text(context.l10n.contacts_pathTrace),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      final hw = context
                          .read<MeshCoreConnector>()
                          .pathHashByteWidth;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PathTraceMapScreen(
                            title: contact.pathBytesForDisplay.isNotEmpty
                                ? context.l10n.contacts_roomPathTrace
                                : context.l10n.contacts_roomPing,
                            path: contact.pathBytesForDisplay.isNotEmpty
                                ? contact.pathBytesForDisplay
                                : _contactPathPrefix(contact, hw),
                            flipPathAround: true,
                            targetContact: contact,
                            pathHashByteWidth: hw,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.meeting_room, color: MeshPalette.blue),
                    title: Text(context.l10n.contacts_roomLogin),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showRoomLogin(
                        context,
                        contact,
                        RoomLoginDestination.chat,
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.room_preferences,
                      color: MeshPalette.warn,
                    ),
                    title: Text(context.l10n.room_management),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showRoomLogin(
                        context,
                        contact,
                        RoomLoginDestination.management,
                      );
                    },
                  ),
                  const Divider(height: 8),
                  SwitchListTile(
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
                      setSheetState(() {
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
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: DropdownButtonFormField<int>(
                        initialValue: selectedMcmpVersion,
                        decoration: InputDecoration(
                          labelText: context.l10n.settings_mcmp_version,
                          border: const OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 2,
                            child: Text('v2 (legacy)'),
                          ),
                          DropdownMenuItem(value: 3, child: Text('v3')),
                        ],
                        onChanged: (value) {
                          final normalized = value == 3 ? 3 : 2;
                          connector.setContactMcmpVersion(
                            contact.publicKeyHex,
                            normalized,
                          );
                          setSheetState(() {
                            selectedMcmpVersion = normalized;
                          });
                        },
                      ),
                    ),
                    if (selectedMcmpVersion == 3)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                            setSheetState(() {
                              mcmpUseSign = normalized;
                            });
                          },
                        ),
                      ),
                  ],
                  SwitchListTile(
                    title: Text(context.l10n.channels_smazCompression),
                    subtitle: Text(context.l10n.chat_compressOutgoingMessages),
                    value: smazEnabled,
                    onChanged: (value) {
                      connector.setContactSmazEnabled(
                        contact.publicKeyHex,
                        value,
                      );
                      if (value) {
                        connector.setContactMcmpEnabled(
                          contact.publicKeyHex,
                          false,
                        );
                        connector.setContactCyr2LatEnabled(
                          contact.publicKeyHex,
                          false,
                        );
                      }
                      setSheetState(() {
                        smazEnabled = value;
                        if (smazEnabled) {
                          mcmpEnabled = false;
                          cyr2latEnabled = false;
                        }
                      });
                    },
                  ),
                  SwitchListTile(
                    title: Text(context.l10n.channels_cyr2latCompression),
                    subtitle: Text(
                      context.l10n.channels_cyr2latCompressionDscr,
                    ),
                    value: cyr2latEnabled,
                    onChanged: (value) {
                      connector.setContactCyr2LatEnabled(
                        contact.publicKeyHex,
                        value,
                      );
                      if (value) {
                        connector.setContactMcmpEnabled(
                          contact.publicKeyHex,
                          false,
                        );
                        connector.setContactSmazEnabled(
                          contact.publicKeyHex,
                          false,
                        );
                      }
                      setSheetState(() {
                        cyr2latEnabled = value;
                        if (cyr2latEnabled) {
                          mcmpEnabled = false;
                          smazEnabled = false;
                        }
                      });
                    },
                  ),
                  if (cyr2latEnabled && appSettingsService != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                          setSheetState(() {
                            selectedCyr2LatProfileId = value;
                          });
                        },
                      ),
                    ),
                  ],
                  SwitchListTile(
                    title: Text(context.l10n.settings_useSendingDelay),
                    value: sendingDelayEnabled,
                    onChanged: (value) {
                      connector.setContactSendingDelayEnabled(
                        contact.publicKeyHex,
                        value,
                      );
                      setSheetState(() {
                        sendingDelayEnabled = value;
                      });
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.quickreply_outlined),
                    title: Text(context.l10n.settings_quickAnswersTitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      if (appSettingsService == null) return;
                      final selection = await showQuickAnswersSelectionDialog(
                        sheetContext,
                        settingsService: appSettingsService,
                        selectedAnswerIds: selectedQuickAnswerIds,
                      );
                      if (selection == null) return;
                      await connector.setContactQuickAnswerIds(
                        contact.publicKeyHex,
                        selection,
                      );
                      setSheetState(() {
                        selectedQuickAnswerIds = selection;
                      });
                    },
                  ),
                ] else ...[
                  if (contact.pathLength > 0)
                    ListTile(
                      leading: Icon(Icons.radar, color: MeshPalette.signal),
                      title: Text(context.l10n.contacts_chatTraceRoute),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        final hw = context
                            .read<MeshCoreConnector>()
                            .pathHashByteWidth;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PathTraceMapScreen(
                              title: context.l10n.contacts_pathTraceTo(
                                contact.name,
                              ),
                              path: contact.pathBytesForDisplay,
                              flipPathAround: true,
                              targetContact: contact,
                              pathHashByteWidth: hw,
                            ),
                          ),
                        );
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.chat),
                    title: Text(context.l10n.contacts_openChat),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _openChat(context, contact);
                    },
                  ),
                ],
                ListTile(
                  leading: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    color: MeshPalette.warn,
                  ),
                  title: Text(
                    isFavorite
                        ? context.l10n.listFilter_removeFromFavorites
                        : context.l10n.listFilter_addToFavorites,
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await connector.setContactFlags(
                      contact,
                      isFavorite: !isFavorite,
                    );
                  },
                ),
                if (isRepeater)
                  ListTile(
                    leading: Icon(
                      ignoredInWardrive
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: ignoredInWardrive
                          ? MeshPalette.signal
                          : Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      ignoredInWardrive
                          ? context.l10n.listFilter_returnToWardrive
                          : context.l10n.listFilter_removeFromWardrive,
                    ),
                    onTap: () async {
                      final nextIgnoredInWardrive = !ignoredInWardrive;
                      setSheetState(() {
                        ignoredInWardrive = nextIgnoredInWardrive;
                      });
                      await wardrive.setRepeaterIgnored(
                        contact.publicKeyHex,
                        nextIgnoredInWardrive,
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: Text(context.l10n.contacts_ShareContact),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _contactExport(contact.publicKey);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.connect_without_contact),
                  title: Text(context.l10n.contacts_ShareContactZeroHop),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _contactZeroHop(contact.publicKey);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    context.l10n.contacts_deleteContact,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _confirmDelete(context, connector, contact);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
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

  void _confirmDelete(
    BuildContext context,
    MeshCoreConnector connector,
    Contact contact,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.contacts_deleteContact),
        content: Text(context.l10n.contacts_removeConfirm(contact.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              connector.removeContact(contact);
            },
            child: Text(
              context.l10n.common_delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final Contact contact;
  final int pathHashByteWidth;
  final DateTime lastSeen;
  final int unreadCount;
  final bool isFavorite;
  final bool? isSelected;
  final ValueChanged<bool?>? onSelectionChanged;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ContactTile({
    required this.contact,
    required this.pathHashByteWidth,
    required this.lastSeen,
    required this.unreadCount,
    required this.isFavorite,
    this.isSelected,
    this.onSelectionChanged,
    required this.onTap,
    this.onLongPress,
  });

  /// Node-type avatar color per design language.
  Color _avatarColor() {
    switch (contact.type) {
      case advTypeRepeater:
        return MeshPalette.warn;
      case advTypeRoom:
        return MeshPalette.magenta;
      case advTypeSensor:
        return const Color(0xFF4ACCC4); // teal
      default:
        return MeshPalette
            .blue; // chat — AvatarCircle handles deterministic hue
    }
  }

  /// Node-type avatar icon. Returns null for chat nodes so AvatarCircle shows initials.
  IconData? _avatarIcon() {
    switch (contact.type) {
      case advTypeRepeater:
        return Icons.cell_tower;
      case advTypeRoom:
        return Icons.meeting_room;
      case advTypeSensor:
        return Icons.sensors;
      default:
        return null; // chat uses initials
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final emoji = firstEmoji(contact.name);
    final isChat = contact.type == advTypeChat;
    final pathLen = contact.pathBytesForDisplay.length;
    final isDirect = contact.pathLength >= 0;
    final hasPath = pathLen > 0 || contact.pathLength == 0;
    final displayHopCount = contact.pathLength == 0
        ? 0
        : PathHelper.splitPathBytes(
            contact.pathBytesForDisplay,
            pathHashByteWidth,
          ).length;

    return GestureDetector(
      onSecondaryTapUp: PlatformInfo.isDesktop && onLongPress != null
          ? (_) => onLongPress!()
          : null,
      child: MeshCard(
        onTap: onTap,
        onLongPress: onLongPress,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Avatar
            if (emoji != null)
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerHigh,
                  border: Border.all(color: scheme.outlineVariant),
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 20)),
              )
            else
              AvatarCircle(
                name: contact.name,
                size: 42,
                color: isChat ? null : _avatarColor(),
                icon: _avatarIcon(),
              ),
            const SizedBox(width: 12),
            // Main content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Name row + favorite + unread badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          contact.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: unreadCount > 0
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 15,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      if (isFavorite) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.star, size: 13, color: MeshPalette.warn),
                      ],
                      if (unreadCount > 0) ...[
                        const SizedBox(width: 6),
                        UnreadBadge(count: unreadCount),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  // Public key of the contact, small monospace. When it does
                  // not fit, the middle is elided (start…end) so both ends stay
                  // visible.
                  _MiddleEllipsisText(
                    text: contact.publicKeyHex.toUpperCase(),
                    style: MeshTheme.mono(
                      fontSize: 9,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Path / subtitle row: path label + route chip, then
                  // location marker and last-seen time (right-aligned).
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                contact.pathLabel(
                                  context.l10n,
                                  pathHashByteWidth: pathHashByteWidth,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (hasPath) ...[
                              const SizedBox(width: 6),
                              RouteChip(
                                isDirect: isDirect,
                                hops: isDirect ? displayHopCount : null,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (contact.hasLocation) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.location_on,
                          size: 13,
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Text(
                        _formatLastSeen(context, lastSeen),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MeshTheme.mono(
                          fontSize: 11,
                          color: unreadCount > 0
                              ? MeshPalette.blue
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (onSelectionChanged != null) ...[
              const SizedBox(width: 4),
              Checkbox(
                value: isSelected ?? false,
                onChanged: onSelectionChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatLastSeen(BuildContext context, DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);

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

// Wrap each contact tile with staggered entrance.
class _ContactTileEntrance extends StatelessWidget {
  final int index;
  final Contact contact;
  final int pathHashByteWidth;
  final DateTime lastSeen;
  final int unreadCount;
  final bool isFavorite;
  final bool? isSelected;
  final ValueChanged<bool?>? onSelectionChanged;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ContactTileEntrance({
    required this.index,
    required this.contact,
    required this.pathHashByteWidth,
    required this.lastSeen,
    required this.unreadCount,
    required this.isFavorite,
    this.isSelected,
    this.onSelectionChanged,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListEntrance(
      index: index,
      child: _ContactTile(
        contact: contact,
        pathHashByteWidth: pathHashByteWidth,
        lastSeen: lastSeen,
        unreadCount: unreadCount,
        isFavorite: isFavorite,
        isSelected: isSelected,
        onSelectionChanged: onSelectionChanged,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

/// Single-line text that elides the middle («start…end») when it does not fit
/// the available width, keeping both ends visible.
class _MiddleEllipsisText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _MiddleEllipsisText({required this.text, required this.style});

  static const String _ellipsis = '…';

  double _measure(String value, TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      maxLines: 1,
      textDirection: direction,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || _measure(text, direction) <= maxWidth) {
          return Text(text, maxLines: 1, softWrap: false, style: style);
        }
        // Binary search for the largest number of original characters that fit
        // once the middle is replaced by the ellipsis.
        var lo = 0;
        var hi = text.length;
        var best = _ellipsis;
        while (lo <= hi) {
          final keep = (lo + hi) ~/ 2;
          final head = (keep + 1) ~/ 2;
          final tail = keep ~/ 2;
          final candidate =
              '${text.substring(0, head)}$_ellipsis'
              '${text.substring(text.length - tail)}';
          if (_measure(candidate, direction) <= maxWidth) {
            best = candidate;
            lo = keep + 1;
          } else {
            hi = keep - 1;
          }
        }
        return Text(
          best,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: style,
        );
      },
    );
  }
}

import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/additional_identity_advert.dart';
import '../helpers/utf8_length_limiter.dart';
import '../l10n/l10n.dart';
import '../services/additional_identity_inbox.dart';
import '../services/additional_identity_vault.dart';
import '../storage/message_history_storage.dart';
import '../utils/keys.dart';
import '../widgets/mesh_ui.dart';

class AdditionalIdentityScreen extends StatefulWidget {
  const AdditionalIdentityScreen._(this.vault, this.rememberedUnlock, this.inbox);

  final AdditionalIdentityVault vault;
  final bool rememberedUnlock;
  final AdditionalIdentityInbox? inbox;

  static Future<void> open(BuildContext context) async {
    final storage = MessageHistoryStorage.instance;
    if (!storage.hasDatabase) return;
    try {
      final saved = await storage.readAdditionalIdentityVault();
      if (!context.mounted) return;
      final password = await _askPassword(context, create: saved == null);
      if (!context.mounted || password == null) return;
      final vault = await AdditionalIdentityVault.open(
        password: password,
        saved: saved,
      );
      final remembered = await vault.isUnlockRemembered();
      if (!context.mounted) return;
      final inbox = context.read<MeshCoreConnector?>()?.additionalIdentityInbox;
      inbox?.unlock(vault.entries);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AdditionalIdentityScreen._(vault, remembered, inbox),
        ),
      );
    } catch (_) {
      if (context.mounted) _showError(context, context.l10n.extraKeys_unlockError);
    }
  }

  @override
  State<AdditionalIdentityScreen> createState() =>
      _AdditionalIdentityScreenState();
}

enum _KeyAction { edit, advertise, delete }

enum _VaultAction { add, password, remember }

class _AdditionalIdentityScreenState extends State<AdditionalIdentityScreen> {
  bool _busy = false;
  late bool _rememberedUnlock = widget.rememberedUnlock;

  AdditionalIdentityVault get _vault => widget.vault;

  void _refreshInbox() => widget.inbox?.unlock(_vault.entries);

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) _showError(context, context.l10n.extraKeys_actionError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([AdditionalIdentityEntry? previous]) => _run(() async {
    final entry = await showDialog<AdditionalIdentityEntry>(
      context: context,
      builder: (_) => _EditKeyDialog(previous: previous),
    );
    if (entry == null) return;
    await _vault.save(entry, replacing: previous?.identity.publicKeyHex);
    _refreshInbox();
  });

  Future<void> _changePassword() => _run(() async {
    final password = await _askPassword(context, create: true);
    if (password == null) return;
    await _vault.changePassword(password);
    _rememberedUnlock = await _vault.isUnlockRemembered();
  });

  Future<void> _toggleRememberedUnlock() => _run(() async {
    final remember = !_rememberedUnlock;
    await _vault.setUnlockRemembered(remember);
    _rememberedUnlock = remember;
  });

  Future<void> _chooseAction(AdditionalIdentityEntry entry) async {
    final connector = context.read<MeshCoreConnector?>();
    final l10n = context.l10n;
    final action = await showMeshSheet<_KeyAction>(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.common_edit),
            onTap: () => Navigator.pop(sheetContext, _KeyAction.edit),
          ),
          ListTile(
            enabled: connector?.isConnected == true && !connector!.isOfflineMode,
            leading: const Icon(Icons.campaign_outlined),
            title: Text(l10n.extraKeys_advertise),
            onTap: () => Navigator.pop(sheetContext, _KeyAction.advertise),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.common_delete),
            onTap: () => Navigator.pop(sheetContext, _KeyAction.delete),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _KeyAction.edit:
        await _edit(entry);
      case _KeyAction.advertise:
        await _run(() async {
          if (connector == null ||
              !connector.isConnected ||
              connector.isOfflineMode) {
            return;
          }
          final radio = connector.selfPublicKeyHex;
          final frame = await buildAdditionalIdentityFloodAdvert(
            identity: entry.identity,
            name: entry.name,
            timestampSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            pathHashWidth: connector.pathHashByteWidth,
          );
          if (!connector.isConnected || connector.selfPublicKeyHex != radio) {
            throw StateError('The connected radio changed');
          }
          await connector.sendFrame(frame, waitForGenericAck: true);
        });
      case _KeyAction.delete:
        await _run(() async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              content: Text(l10n.extraKeys_deleteConfirm),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(l10n.common_cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(l10n.common_delete),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await _vault.remove(entry.identity.publicKeyHex);
            _refreshInbox();
          }
        });
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.extraKeys_manage),
        actions: [
          PopupMenuButton<_VaultAction>(
            enabled: !_busy,
            onSelected: (action) => switch (action) {
              _VaultAction.add => _edit(),
              _VaultAction.password => _changePassword(),
              _VaultAction.remember => _toggleRememberedUnlock(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _VaultAction.add,
                child: Text(l10n.common_add),
              ),
              PopupMenuItem(
                value: _VaultAction.password,
                child: Text(l10n.extraKeys_setPassword),
              ),
              CheckedPopupMenuItem(
                value: _VaultAction.remember,
                checked: _rememberedUnlock,
                child: Text(l10n.extraKeys_rememberUnlock),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final entry in _vault.entries)
              MeshCard(
                onTap: _busy ? null : () => _chooseAction(entry),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.name, style: Theme.of(context).textTheme.titleMedium),
                    Text(entry.identity.publicKeyHex),
                    Text(entry.identity.maskedPrivateKey),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void _showError(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<String?> _askPassword(BuildContext context, {required bool create}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PasswordDialog(create: create),
    );

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.create});

  final bool create;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _invalid = false;

  void _submit() {
    if (_password.text.isEmpty ||
        (widget.create && _password.text != _repeat.text)) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context, _password.text);
  }

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.create ? l10n.extraKeys_setPassword : l10n.login_enterPassword),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: l10n.login_enterPassword),
            onSubmitted: widget.create ? null : (_) => _submit(),
          ),
          if (widget.create)
            TextField(
              controller: _repeat,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: l10n.backupChannels_repeatPassword),
              onSubmitted: (_) => _submit(),
            ),
          if (_invalid) Text(l10n.extraKeys_invalidPassword),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.common_cancel)),
        FilledButton(onPressed: _submit, child: Text(l10n.common_ok)),
      ],
    );
  }
}

class _EditKeyDialog extends StatefulWidget {
  const _EditKeyDialog({this.previous});

  final AdditionalIdentityEntry? previous;

  @override
  State<_EditKeyDialog> createState() => _EditKeyDialogState();
}

class _EditKeyDialogState extends State<_EditKeyDialog> {
  late final _name = TextEditingController(text: widget.previous?.name);
  late final _key = TextEditingController(
    text: widget.previous?.identity.privateKeyHex,
  );
  bool _busy = false;
  bool _invalid = false;

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      MCKeyPair pair;
      do {
        pair = await generateKeyPair();
      } while (pair.public.first == 0 || pair.public.first == 0xff);
      if (mounted) {
        _key.text = hex.encode(pair.private);
        _invalid = false;
      }
    } catch (_) {
      if (mounted) _invalid = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final entry = await AdditionalIdentityEntry.parse(_name.text, _key.text);
      if (mounted) Navigator.pop(context, entry);
    } catch (_) {
      if (mounted) setState(() => _invalid = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            inputFormatters: const [Utf8LengthLimitingTextInputFormatter(maxRadioNameBytes)],
            decoration: InputDecoration(labelText: l10n.extraKeys_name),
          ),
          TextField(
            controller: _key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.extraKeys_privateKey,
              suffixIcon: IconButton(
                icon: const Icon(Icons.casino_outlined),
                tooltip: l10n.extraKeys_generate,
                onPressed: _busy ? null : _generate,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(l10n.extraKeys_encrypted, style: Theme.of(context).textTheme.bodySmall),
          if (_invalid) Text(l10n.extraKeys_invalidKey),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.common_cancel)),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(l10n.common_ok)),
      ],
    );
  }
}

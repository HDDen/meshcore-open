import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/utf8_length_limiter.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../services/additional_identity_inbox.dart';

/// An empty string explicitly selects the connected radio identity.
Future<String?> pickAdditionalIdentitySender(
  BuildContext context, {
  required AdditionalIdentityInbox inbox,
  required String? selected,
  required String? radioName,
  required String radioKey,
}) => showDialog<String>(
  context: context,
  builder: (dialogContext) {
    final l10n = dialogContext.l10n;
    return SimpleDialog(
      title: Text(l10n.channels_senderNameLabel),
      children: [
        ListTile(
          selected: selected == null,
          title: Text(radioName ?? l10n.channels_senderNameDefault),
          subtitle: radioKey.isEmpty ? null : Text(radioKey),
          onTap: () => Navigator.pop(dialogContext, ''),
        ),
        for (final entry in inbox.entries)
          if (entry.identity.publicKeyHex != radioKey)
            ListTile(
              selected: selected == entry.identity.publicKeyHex,
              title: Text(entry.name),
              subtitle: Text(entry.identity.publicKeyHex),
              onTap: () => Navigator.pop(dialogContext, entry.identity.publicKeyHex),
            ),
      ],
    );
  },
);

/// Room permissions are checked for the selected identity over the air.
Future<bool> ensureAdditionalIdentityRoomAccess(
  BuildContext context,
  MeshCoreConnector connector,
  String identityKey,
  Contact peer,
) async {
  if (peer.type != advTypeRoom ||
      connector.canPostToRoomAsAdditionalIdentity(identityKey, peer)) {
    return true;
  }
  final entry = connector.additionalIdentityInbox?.entryFor(identityKey);
  if (entry == null || !connector.isConnected) {
    throw StateError('Additional identity or radio is unavailable');
  }
  return await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _AdditionalIdentityRoomLogin(
      identityName: entry.name,
      roomName: peer.name,
      login: (password) => connector.loginToRoomAsAdditionalIdentity(
        identityKey, peer, password,
      ),
    ),
  ) ?? false;
}

class _AdditionalIdentityRoomLogin extends StatefulWidget {
  const _AdditionalIdentityRoomLogin({
    required this.identityName,
    required this.roomName,
    required this.login,
  });

  final String identityName;
  final String roomName;
  final Future<bool> Function(String password) login;

  @override
  State<_AdditionalIdentityRoomLogin> createState() =>
      _AdditionalIdentityRoomLoginState();
}

class _AdditionalIdentityRoomLoginState extends State<_AdditionalIdentityRoomLogin> {
  final _password = TextEditingController();
  bool _waiting = false;
  bool _failed = false;

  Future<void> _submit() async {
    if (_waiting) return;
    setState(() {
      _waiting = true;
      _failed = false;
    });
    var permitted = false;
    try {
      permitted = await widget.login(_password.text);
    } catch (_) {
      // The dialog keeps the input available for another attempt.
    }
    if (!mounted) return;
    if (permitted) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _waiting = false;
        _failed = true;
      });
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.login_roomLogin),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.roomName),
          Text('${l10n.channels_senderNameLabel}: ${widget.identityName}'),
          TextField(
            controller: _password,
            autofocus: true,
            readOnly: _waiting,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: const [Utf8LengthLimitingTextInputFormatter(15)],
            decoration: InputDecoration(
              labelText: l10n.login_password,
              errorText: _failed ? l10n.extraKeys_roomLoginFailed : null,
              errorMaxLines: 4,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.common_cancel),
        ),
        FilledButton(
          onPressed: _waiting ? null : _submit,
          child: _waiting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.common_ok),
        ),
      ],
    );
  }
}

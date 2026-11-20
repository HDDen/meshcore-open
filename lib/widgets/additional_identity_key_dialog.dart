import 'package:convert/convert.dart';
import 'package:flutter/material.dart';

import '../helpers/meshcore_expanded_identity.dart';
import '../helpers/utf8_length_limiter.dart';
import '../l10n/l10n.dart';
import '../services/additional_identity_vault.dart';
import '../utils/keys.dart';
import 'meshcore_key_fields.dart';

class AdditionalIdentityKeyDialog extends StatefulWidget {
  const AdditionalIdentityKeyDialog({super.key, this.previous, this.keyPairSearcher})
      : nodeKey = false, onSave = null;

  const AdditionalIdentityKeyDialog.node({
    super.key, required this.previous, required this.onSave,
  }) : nodeKey = true, keyPairSearcher = null;

  final bool nodeKey;
  final Future<bool> Function(AdditionalIdentityEntry)? onSave;

  final AdditionalIdentityEntry? previous;

  /// Allows deterministic generation and cancellation checks.
  final KeyPairSearcher? keyPairSearcher;

  @override
  State<AdditionalIdentityKeyDialog> createState() => _AdditionalIdentityKeyDialogState();
}

class _AdditionalIdentityKeyDialogState extends State<AdditionalIdentityKeyDialog> {
  late final _name = TextEditingController(text: widget.previous?.name);
  late final _key = TextEditingController(
    text: widget.previous?.identity.privateKeyHex,
  );
  late final _publicKey = TextEditingController(
    text: widget.previous?.identity.publicKeyHex,
  );
  final _prefix = TextEditingController();
  late final _searcher = widget.keyPairSearcher ?? KeyPairSearcher();
  int _generationRevision = 0;
  bool _searching = false;
  int _keyRevision = 0;
  bool _busy = false;
  bool _invalid = false;
  late bool _ackWithoutPath = widget.previous?.ackWithoutPath ?? true;

  @override
  void initState() {
    super.initState();
    _key.addListener(_refreshPublicKey);
  }

  Future<void> _refreshPublicKey() async {
    final revision = ++_keyRevision;
    _publicKey.clear();
    try {
      final identity = await MeshCoreExpandedIdentity.fromHex(_key.text);
      if (!mounted || revision != _keyRevision) return;
      _publicKey.text = identity.publicKeyHex;
    } catch (_) {
      // Incomplete or invalid input has no public key to preview.
    }
  }

  void _stopGenerating() {
    _generationRevision++;
    _searcher.cancel();
    if (mounted) setState(() { _searching = false; _busy = false; });
  }

  Future<void> _generate() async {
    if (_busy) return;
    final prefix = _prefix.text.trim().toLowerCase();
    // These first bytes are reserved by MeshCore and cannot yield valid keys.
    if (prefix.startsWith('00') || prefix.startsWith('ff')) {
      setState(() => _invalid = true);
      return;
    }
    final revision = ++_generationRevision;
    setState(() { _busy = true; _searching = true; _invalid = false; });
    try {
      while (mounted && revision == _generationRevision) {
        final pair = await _searcher.findMatchingKeyPair(prefix, 30);
        if (!mounted || revision != _generationRevision) return;
        if (pair != null && pair.public.first != 0 && pair.public.first != 0xff) {
          _key.text = hex.encode(pair.private);
          _publicKey.text = hex.encode(pair.public);
          break;
        }
        await Future<void>.delayed(Duration.zero);
      }
    } catch (_) {
      if (mounted && revision == _generationRevision) _invalid = true;
    } finally {
      if (mounted && revision == _generationRevision) {
        setState(() { _busy = false; _searching = false; });
      }
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final entry = await AdditionalIdentityEntry.parse(
        _name.text,
        _key.text,
        previous: widget.previous,
        ackWithoutPath: _ackWithoutPath,
      );
      if (!mounted) return;
      if (widget.onSave != null && !await widget.onSave!(entry)) return;
      if (mounted) Navigator.pop(context, widget.nodeKey ? null : entry);
    } catch (_) {
      if (mounted) setState(() => _invalid = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generationRevision++;
    _searcher.cancel();
    _prefix.dispose();
    _key.removeListener(_refreshPublicKey);
    _publicKey.dispose();
    _name.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.nodeKey) TextField(
            controller: _name,
            inputFormatters: const [Utf8LengthLimitingTextInputFormatter(maxRadioNameBytes)],
            decoration: InputDecoration(labelText: l10n.extraKeys_name),
          ),
          if (!widget.nodeKey) const SizedBox(height: 12),
          MeshCoreKeyFields(
            privateKey: _key, publicKey: _publicKey, prefix: _prefix,
            searching: _searching, editable: !_busy, canGenerate: !_busy,
            publicMinLines: 2,
            privateError: _key.text.isNotEmpty && _key.text.length != 128
                ? l10n.repeater_prvKeyLengthError(128) : null,
            onGenerate: _generate, onStop: _stopGenerating,
            onPrivateChanged: (_) => setState(() => _invalid = false),
            onPrefixChanged: (_) => setState(() => _invalid = false),
          ),
          if (!widget.nodeKey) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              key: const ValueKey('additional-key-ack-without-path'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.extraKeys_ackWithoutPath),
              subtitle: Text(l10n.extraKeys_ackWithoutPathHelper,
                style: Theme.of(context).textTheme.bodySmall),
              value: _ackWithoutPath,
              onChanged: _busy ? null : (value) => setState(() => _ackWithoutPath = value),
            ),
            const SizedBox(height: 8),
            Text(l10n.extraKeys_encrypted, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_invalid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.extraKeys_invalidKey),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: widget.nodeKey && _busy && !_searching ? null : () {
            if (_searching) _stopGenerating();
            Navigator.pop(context);
          },
          child: Text(widget.nodeKey ? l10n.common_close : l10n.common_cancel),
        ),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(widget.nodeKey ? l10n.common_save : l10n.common_ok)),
      ],
    );
  }
}

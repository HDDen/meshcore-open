import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/l10n.dart';

/// Key controls shared by repeater settings and the additional identity editor.
class MeshCoreKeyFields extends StatelessWidget {
  const MeshCoreKeyFields({
    super.key, required this.privateKey, required this.publicKey,
    required this.prefix, required this.searching, required this.onGenerate,
    required this.onStop, required this.onPrivateChanged,
    required this.onPrefixChanged, this.privateError, this.publicMinLines = 1,
    this.editable = true, this.canGenerate = true,
  });
  final TextEditingController privateKey, publicKey, prefix;
  final bool searching, editable, canGenerate;
  final VoidCallback onGenerate, onStop;
  final ValueChanged<String> onPrivateChanged, onPrefixChanged;
  final String? privateError;
  final int publicMinLines;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: TextField(
          controller: privateKey, readOnly: !editable, maxLength: 128,
          autocorrect: false, enableSuggestions: false,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]'))],
          decoration: InputDecoration(
            labelText: l10n.repeater_prvKey,
            helper: Text(l10n.repeater_prvKeyHelper, softWrap: true),
            errorText: privateError, errorMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
          onChanged: onPrivateChanged,
        )),
        const SizedBox(width: 8),
        Padding(padding: const EdgeInsets.only(top: 8), child: IconButton(
          icon: Icon(searching ? Icons.cancel : Icons.casino_rounded, size: 24),
          onPressed: searching ? onStop : canGenerate ? onGenerate : null,
          tooltip: searching ? l10n.repeater_stopGeneratingPrvKey : l10n.repeater_generatePrvKey,
          visualDensity: VisualDensity.compact,
        )),
      ]),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: TextField(
          controller: publicKey, readOnly: true, minLines: publicMinLines,
          maxLines: publicMinLines > 1 ? null : 1,
          style: TextStyle(color: Theme.of(context).textTheme.headlineSmall?.color?.withValues(alpha: 0.6)),
          decoration: InputDecoration(
            labelText: l10n.repeater_pubKey,
            helper: Text(l10n.repeater_pubKeyHelper, softWrap: true),
            border: const OutlineInputBorder(),
          ),
        )),
        const SizedBox(width: 16),
        Padding(padding: const EdgeInsets.only(top: 12), child: SizedBox(
          width: 24, height: 24,
          child: searching ? const CircularProgressIndicator(strokeWidth: 2) : null,
        )),
        const SizedBox(width: 8),
      ]),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: TextField(
          controller: prefix, readOnly: !editable, maxLength: 4,
          autocorrect: false, enableSuggestions: false,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]'))],
          onChanged: onPrefixChanged,
          decoration: InputDecoration(
            labelText: l10n.repeater_pubKeyPrefix,
            helper: Text(
              l10n.repeater_pubKeyPrefixHelper(pow(16, prefix.text.length).toInt()),
              softWrap: true,
            ),
            border: const OutlineInputBorder(),
          ),
        )),
        const SizedBox(width: 48),
      ]),
    ]);
  }
}

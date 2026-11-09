import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/manual_trace_input.dart';
import '../helpers/trace_request_limits.dart';
import '../l10n/l10n.dart';
import '../services/ui_view_state_service.dart';
import 'path_trace_map.dart';

class ManualPathTraceScreen extends StatefulWidget {
  const ManualPathTraceScreen({
    super.key,
    this.initialText,
    this.initialRoundTrip,
    this.initialHashWidth,
  });

  final String? initialText;
  final bool? initialRoundTrip;
  final int? initialHashWidth;

  static Future<void> open(
    BuildContext context, {
    String? initialText,
    bool? initialRoundTrip,
    int? initialHashWidth,
  }) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ManualPathTraceScreen(
          initialText: initialText,
          initialRoundTrip: initialRoundTrip,
          initialHashWidth: initialHashWidth,
        ),
      ),
    );
  }

  @override
  State<ManualPathTraceScreen> createState() => _ManualPathTraceScreenState();
}

class _ManualPathTraceScreenState extends State<ManualPathTraceScreen> {
  late final UiViewStateService _view;
  late final String _radioKey;
  late final TextEditingController _controller;
  late final int? _hashWidth;
  late bool _roundTrip;
  bool _unresolvedHop = false;
  bool _traceOpen = false;

  @override
  void initState() {
    super.initState();
    _view = context.read<UiViewStateService>();
    _radioKey = context.read<MeshCoreConnector>().selfPublicKeyHex;
    final saved = _view.manualPathTrace;
    final draft = saved?.radioKey == _radioKey ? saved : null;
    _controller = TextEditingController(text: widget.initialText ?? draft?.text);
    _roundTrip = widget.initialRoundTrip ?? draft?.roundTrip ?? true;
    _hashWidth = widget.initialHashWidth ?? draft?.hashWidth;
  }

  @override
  void dispose() {
    _view.manualPathTrace = (
      radioKey: _radioKey,
      text: _controller.text,
      roundTrip: _roundTrip,
      hashWidth: _hashWidth,
    );
    _controller.dispose();
    super.dispose();
  }

  bool _fits(ManualTraceInput input, int? firmwareCode) {
    final hops = input.bytes.length ~/ input.width;
    return traceRequestFits(
      hopCount: _roundTrip ? 2 * hops - 1 : hops,
      wireHashWidth: traceRequestHashWidth(input.width),
      firmwareCode: firmwareCode,
    );
  }

  Future<void> _run() async {
    final connector = context.read<MeshCoreConnector>();
    if (_traceOpen ||
        _radioKey.isEmpty ||
        !connector.isConnected ||
        connector.selfPublicKeyHex != _radioKey) {
      return;
    }
    final input = parseManualTrace(
      _controller.text, _hashWidth ?? connector.pathHashByteWidth,
    );
    if (input == null || !_fits(input, connector.firmwareVerCode)) return;

    // Resolve names and the fourth hash byte only on an explicit Run.
    final contacts = resolveManualTraceContacts(
      input, connector.allContactsUnfiltered,
    );
    if (contacts == null) {
      setState(() => _unresolvedHop = true);
      return;
    }
    _traceOpen = true;
    final roundTrip = _roundTrip;
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => PathTraceMapScreen(
          title: context.l10n.contacts_pathTrace,
          path: input.bytes,
          pathHashByteWidth: input.width,
          pathContacts: contacts,
          flipPathAround: roundTrip,
          revealMapManually: true,
          deferLocationUntilMapShown: true,
          expectedRadioKey: _radioKey,
        ),
      ),
    );
    _traceOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final radio = context.select((MeshCoreConnector connector) => (
      connected: _radioKey.isNotEmpty &&
          connector.isConnected &&
          connector.selfPublicKeyHex == _radioKey,
      width: _hashWidth ?? connector.pathHashByteWidth,
      firmwareCode: connector.firmwareVerCode,
    ));
    final l10n = context.l10n;
    final input = parseManualTrace(_controller.text, radio.width);
    final fits = input != null && _fits(input, radio.firmwareCode);
    final error = _controller.text.trim().isEmpty
        ? null
        : input == null
        ? l10n.manualTrace_invalidHashes
        : !fits
        ? l10n.manualTrace_requestTooLong
        : _unresolvedHop
        ? l10n.manualTrace_unresolvedHop
        : null;
    final example = switch (radio.width) {
      2 => 'A1B2, C3D4',
      3 => 'A1B2C3, D4E5F6',
      _ => 'A1, B2, C3',
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.manualTrace_title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              minLines: 2,
              maxLines: 5,
              onChanged: (_) => setState(() => _unresolvedHop = false),
              decoration: InputDecoration(
                labelText: l10n.manualTrace_hashes,
                hintText: example,
                errorText: error,
                errorMaxLines: 4,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l10n.map_pathTraceModeRoundTrip),
                  selected: _roundTrip,
                  onSelected: (_) => setState(() => _roundTrip = true),
                ),
                ChoiceChip(
                  label: Text(l10n.map_pathTraceModeAsEntered),
                  selected: !_roundTrip,
                  onSelected: (_) => setState(() => _roundTrip = false),
                ),
              ],
            ),
            Text(_roundTrip
                ? l10n.map_pathTraceModeRoundTripHint
                : l10n.map_pathTraceModeAsEnteredHint),
            if (!radio.connected) ...[
              const SizedBox(height: 8),
              Text(l10n.settings_notConnectedError),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: radio.connected && fits ? _run : null,
              icon: const Icon(Icons.radar),
              label: Text(l10n.map_runTrace),
            ),
          ],
        ),
      ),
    );
  }
}

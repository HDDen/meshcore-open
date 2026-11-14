import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/contact_share_helper.dart';
import '../helpers/gif_helper.dart';
import '../helpers/ipfs_link_attach_flow.dart';
import '../helpers/mcoimg_codec.dart';
import '../helpers/quick_answers_helper.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../models/mco_image_gallery_item.dart';
import '../screens/canvas_editor_screen.dart';
import '../screens/contacts_screen.dart';
import '../screens/map_screen.dart';
import '../screens/mco_image_gallery_screen.dart';
import '../services/app_settings_service.dart';
import 'chat_additional_actions_menu.dart';
import 'gif_picker.dart';
import 'mesh_ui.dart';
import 'quick_answers_picker_dialog.dart';

/// Text and media actions available to both personal-message composers.
class ContactComposerActions extends StatefulWidget {
  const ContactComposerActions({
    super.key,
    required this.connector,
    required this.contact,
    required this.controller,
    required this.focusNode,
    required this.maxBytes,
    required this.onSend,
    this.identityKey,
    this.encoder,
    this.composeIpfsDraft,
  });

  final MeshCoreConnector connector;
  final Contact contact;
  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxBytes;
  final Future<void> Function({String? quickAnswerText, bool standalone}) onSend;
  final String? identityKey;
  final String Function(String)? encoder;
  final String Function(String, String)? composeIpfsDraft;

  static Future<void> showQuickAnswers(
    BuildContext context, {
    required MeshCoreConnector connector,
    required Contact contact,
    required TextEditingController controller,
    required FocusNode focusNode,
    required Future<void> Function(String) send,
  }) async {
    final ids = await connector.loadContactQuickAnswerIds(contact.publicKeyHex);
    if (!context.mounted) return;
    final answer = await showQuickAnswersPickerDialog(
      context,
      answers: filterAvailableQuickAnswers(
        selectedAnswerIds: ids,
        globalAnswers: context.read<AppSettingsService>().settings.quickAnswers,
      ),
    );
    if (!context.mounted || answer == null) return;
    if (answer.sendAtSelect) {
      await send(answer.text);
    } else {
      insertQuickAnswerIntoComposer(
        controller: controller,
        focusNode: focusNode,
        text: answer.text,
      );
    }
  }

  @override
  State<ContactComposerActions> createState() => _ContactComposerActionsState();
}

class _ContactComposerActionsState extends State<ContactComposerActions> {
  bool _ipfsUploading = false;
  TextEditingController get _textController => widget.controller;
  FocusNode get _textFieldFocusNode => widget.focusNode;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsService>().settings;
    final connector = widget.connector;
    return ChatAdditionalActionsButton(
      canvasActive: settings.canvasActive,
      offlineMode: connector.isOfflineMode,
      onSendSelfContact: () => _insertSelfContact(connector),
      onSendMyLocation: () => unawaited(_insertMyLocation(connector)),
      onSendContact: () => unawaited(_pickAndInsertContact()),
      onPickLocationFromMap: () => unawaited(_pickAndInsertLocationFromMap()),
      onOpenQuickAnswers: () => unawaited(ContactComposerActions.showQuickAnswers(
        context,
        connector: connector,
        contact: widget.contact,
        controller: _textController,
        focusNode: _textFieldFocusNode,
        send: (text) => widget.onSend(quickAnswerText: text),
      )),
      onSendGif: _showGifPicker,
      onSendIpfs: settings.uploadIpfsEndpoint.trim().isNotEmpty && !_ipfsUploading
          ? () => unawaited(_attachIpfsLink(connector))
          : null,
      onOpenCanvas: () => unawaited(_showCanvasEditor(widget.maxBytes)),
      onOpenMcoImageGallery: () => unawaited(_showMcoImageGallery(connector)),
    );
  }

  void _showGifPicker() {
    showMeshSheet<void>(
      context,
      builder: (context) => GifPicker(
        onGifSelected: (gifId) {
          if (mounted) _textController.text = GifHelper.encodeGif(gifId);
        },
      ),
    );
  }

  void _insertTextIntoComposer(String text) {
    final value = _textController.value;
    final selection = value.selection;
    final range = selection.isValid
        ? selection
        : TextSelection.collapsed(offset: value.text.length);
    final nextText = value.text.replaceRange(range.start, range.end, text);
    final nextOffset = range.start + text.length;
    _textController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _textFieldFocusNode.requestFocus();
  }

  void _insertSelfContact(MeshCoreConnector connector) {
    final identityKey = widget.identityKey;
    final entry = identityKey == null
        ? null
        : connector.additionalIdentityInbox?.entryFor(identityKey);
    final publicKey = identityKey == null ? connector.selfPublicKey : entry?.identity.publicKey;
    if (publicKey == null || publicKey.isEmpty) return;
    _insertTextIntoComposer(
      formatContactShareText(
        publicKey: publicKey,
        type: advTypeChat,
        name: entry?.name ?? connector.selfName ?? connector.deviceDisplayName,
      ),
    );
  }

  Future<void> _insertMyLocation(MeshCoreConnector connector) async {
    final location = await connector.refreshSelfLocation();
    if (!mounted || location == null) return;
    _insertTextIntoComposer(
      '${location.latitude.toStringAsFixed(6)},'
      '${location.longitude.toStringAsFixed(6)}',
    );
  }

  Future<void> _pickAndInsertLocationFromMap() async {
    final location = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (context) => const MapScreen(locationPickerMode: true),
      ),
    );
    if (!mounted || location == null) return;
    _insertTextIntoComposer(
      '${location.latitude.toStringAsFixed(6)},'
      '${location.longitude.toStringAsFixed(6)}',
    );
  }

  Future<void> _pickAndInsertContact() async {
    final contact = await Navigator.push<Contact>(
      context,
      MaterialPageRoute(
        builder: (_) => const ContactsScreen(selectionMode: true),
      ),
    );
    if (contact == null || !mounted) return;
    _insertTextIntoComposer(formatContactShareTextForContact(contact));
  }

  Future<void> _showCanvasEditor(
    int maxTextChars, {
    MCOImage? initialImage,
    Uint8List? initialImageBytes,
    int? initialImageWidth,
    int? initialImageHeight,
    PaletteProfile? initialPaletteProfile,
  }) async {
    final result = await Navigator.push<CanvasEditorResult>(
      context,
      MaterialPageRoute(
        builder: (context) => CanvasEditorScreen(
          maxTextChars: maxTextChars,
          initialImage: initialImage,
          initialImageBytes: initialImageBytes,
          initialImageWidth: initialImageWidth,
          initialImageHeight: initialImageHeight,
          initialPaletteProfile: initialPaletteProfile,
        ),
      ),
    );
    if (result == null || result.text.isEmpty) return;
    if (!mounted) return;
    final encodedText = result.text;
    _textController.text = encodedText;
    _textController.selection = TextSelection.collapsed(
      offset: encodedText.length,
    );
    await widget.onSend(standalone: true);
  }

  Future<void> _attachIpfsLink(MeshCoreConnector connector) async {
    if (_ipfsUploading || connector.isOfflineMode || !connector.isConnected) return;
    setState(() => _ipfsUploading = true);
    try {
      await attachIpfsLinkToDraft(
        context: context,
        controller: _textController,
        focusNode: _textFieldFocusNode,
        maxBytes: widget.maxBytes,
        encodeOutbound: (text) => widget.encoder?.call(text) ?? text,
        composeDraft: widget.composeIpfsDraft,
      );
    } finally {
      if (mounted) setState(() => _ipfsUploading = false);
    }
  }

  Future<void> _showMcoImageGallery(
    MeshCoreConnector connector,
  ) async {
    final result = await showModalBottomSheet<MCOImageGalleryResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const MCOImageGalleryScreen(),
    );
    if (result == null || !mounted) return;
    if (result.action == MCOImageGalleryAction.edit) {
      await _openGalleryItemInCanvas(result.item);
      return;
    }
    await _sendGalleryItem(connector, result.item);
  }

  Future<void> _openGalleryItemInCanvas(MCOImageGalleryItem item) async {
    final useRasterOriginal = item.showPngFallback && !item.originalIsLottie;
    final image = useRasterOriginal ? null : item.tryDecodeImage();
    await _showCanvasEditor(
      widget.maxBytes,
      initialImage: image,
      initialImageBytes: image == null && !item.originalIsLottie
          ? item.pngBytes
          : null,
      initialImageWidth: item.width,
      initialImageHeight: item.height,
      initialPaletteProfile: item.paletteProfile,
    );
  }

  Future<void> _sendGalleryItem(
    MeshCoreConnector connector,
    MCOImageGalleryItem item,
  ) async {
    final text = item.textPayload;
    final identityKey = widget.identityKey;
    final outboundText = identityKey == null
        ? connector.prepareContactOutboundText(widget.contact, text)
        : connector.prepareAdditionalIdentityOutboundText(widget.contact, identityKey, text);
    final payloadBytes = utf8.encode(outboundText).length;
    final maxBytes = widget.maxBytes;
    if (payloadBytes > maxBytes) {
      showDismissibleSnackBar(
        context,
        content: Text(
          context.l10n.chat_canvasCannotSend(payloadBytes - maxBytes),
        ),
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
      );
      return;
    }
    _textController.text = text;
    _textController.selection = TextSelection.collapsed(offset: text.length);
    await widget.onSend(standalone: true);
  }
}

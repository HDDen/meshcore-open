import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../widgets/image_send_codec_binding.dart';
import '../widgets/image_send_preview_sheet.dart';

typedef ImageSendFilePicker = Future<file_selector.XFile?> Function();

/// Shared "attach an image" flow, used by both the direct-message and channel
/// chat screens so the two surfaces cannot drift apart.
///
/// Picks a photo, then shows [ImageSendPreviewSheet] so the user sees the
/// packet count and airtime *before* committing to a send that may occupy the
/// channel for seconds. Returns null if the user backed out at either step.
///
/// The caller owns the actual transmission: this only produces the payload.
Future<ImageSendPreviewResult?> pickAndPreviewImage({
  required BuildContext context,
  required ImageSendCodec codec,
  ImageSendFilePicker? picker,
}) async {
  final file_selector.XFile? picked;
  try {
    picked = await (picker?.call() ??
        file_selector.openFile(
          acceptedTypeGroups: const [
            file_selector.XTypeGroup(
              label: 'Images',
              extensions: ['png', 'jpg', 'jpeg', 'webp'],
            ),
          ],
        ));
  } on Exception catch (e) {
    debugPrint('image pick failed: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.chat_imagePickFailed)),
      );
    }
    return null;
  }

  if (picked == null) return null; // user cancelled the picker

  final Uint8List bytes;
  int originalBytes;
  try {
    bytes = await picked.readAsBytes();
    originalBytes = await picked.length();
  } on Exception catch (e) {
    debugPrint('image read failed: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.chat_imagePickFailed)),
      );
    }
    return null;
  }

  if (!context.mounted) return null;

  return showImageSendPreviewSheet(
    context: context,
    imageBytes: bytes,
    originalFileBytes: originalBytes,
    codec: codec,
  );
}

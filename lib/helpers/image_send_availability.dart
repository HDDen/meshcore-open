import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../utils/app_logger.dart';
import '../widgets/image_send_codec_binding.dart';

/// Keep the attachment action responsive without bypassing codec/model checks.
/// This runs before opening a native picker or allocating inference resources.
Future<bool> ensureImageSendAvailable(
  BuildContext context, {
  required ImageSendCodec? codec,
  String? statusReason,
}) async {
  if (!context.mounted) {
    return false;
  }
  final availability = codec?.availability ?? ImageCodecAvailability.unavailable;
  if (availability == ImageCodecAvailability.ready) {
    appLogger.info('Codec ready; opening image selection', tag: 'ImageSend');
    return true;
  }

  final l10n = context.l10n;
  final suppliedReason = statusReason?.trim();
  final backendReason = codec?.unavailableReason?.trim();
  final fallback = switch (availability) {
    ImageCodecAvailability.disabled => l10n.imageSend_codecDisabled,
    ImageCodecAvailability.downloading => l10n.imageSend_codecDownloading,
    _ => l10n.imageSend_codecUnavailable,
  };
  final reason = suppliedReason != null && suppliedReason.isNotEmpty
      ? suppliedReason
      : backendReason != null && backendReason.isNotEmpty
      ? backendReason
      : fallback;
  appLogger.warn(
    'Image selection blocked: ${availability.name}; $reason',
    tag: 'ImageSend',
  );
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.imageSend_title),
      content: SingleChildScrollView(child: Text(reason)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.common_close),
        ),
      ],
    ),
  );
  return false;
}

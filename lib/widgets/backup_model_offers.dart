import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../helpers/image_codec_installation.dart';
import '../l10n/l10n.dart';
import '../models/app_settings_backup.dart';
import '../models/image_codec_support.dart';
import '../models/translation_support.dart';
import '../services/image_codec_backend.dart' show kImageCodecFeatureAvailable;
import '../services/image_codec_service.dart';
import '../services/translation_service.dart';

class BackupModelOffers extends StatelessWidget {
  const BackupModelOffers({super.key, required this.backup, required this.busy});

  final AppSettingsBackup backup;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final translationPreset = backup.translationPreset;
    final imagePreset = backup.imageCodecPreset;
    final translation = translationPreset == null
        ? null : context.watch<TranslationService?>();
    final codec = !kImageCodecFeatureAvailable || imagePreset == null
        ? null : context.watch<ImageCodecService?>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (translation != null && translationPreset != null &&
            translation.supportsModelDownload &&
            !translation.availableModels.any((model) =>
                model.localPath.isNotEmpty && model.fileSizeBytes > 0 &&
                (model.id == translationPreset.id || model.name == translationPreset.name)))
          _ModelOffer(
            key: ValueKey(translationPreset.id),
            name: translationModelFriendlyName(translationPreset),
            blocked: busy || translation.isDownloading,
            isDownloading: translation.isDownloading,
            progress: translation.downloadProgress,
            download: () => translation.downloadModel(
              sourceUrl: translationPreset.sourceUrl,
              fileName: translationPreset.name,
              id: translationPreset.id,
            ),
            cancel: translation.cancelDownload,
          ),
        if (codec != null && imagePreset != null && codec.unavailableReason == null &&
            imagePreset.isComplete && !imagePreset.urlsArePlaceholders &&
            !codec.availableModels.any((model) => isImageCodecPresetComplete(imagePreset, model)))
          _ModelOffer(
            key: ValueKey(imagePreset.id),
            name: imagePreset.label,
            blocked: busy || codec.isDownloading,
            isDownloading: codec.isDownloading,
            progress: codec.downloadProgress,
            download: () => codec.downloadPresetModel(imagePreset),
            cancel: codec.cancelDownload,
          ),
      ],
    );
  }
}

class _ModelOffer extends StatefulWidget {
  const _ModelOffer({
    super.key,
    required this.name,
    required this.blocked,
    required this.isDownloading,
    required this.progress,
    required this.download,
    required this.cancel,
  });

  final String name;
  final bool blocked;
  final bool isDownloading;
  final double? progress;
  final Future<void> Function() download;
  final VoidCallback cancel;

  @override
  State<_ModelOffer> createState() => _ModelOfferState();
}

class _ModelOfferState extends State<_ModelOffer> {
  bool _started = false;

  Future<void> _confirmDownload() async {
    final l10n = context.l10n;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(l10n.backupAppSettings_downloadModelConfirm(widget.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.translation_downloadModel),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true || widget.blocked || _started) return;
    setState(() => _started = true);
    try {
      await widget.download();
    } catch (error) {
      if (mounted && error is! TranslationDownloadCancelled &&
          error is! ImageCodecDownloadCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.backupAppSettings_modelDownloadFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _started = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.backupAppSettings_missingModel(widget.name)),
          if (_started) ...[
            LinearProgressIndicator(value: widget.progress),
            TextButton(
              onPressed: widget.isDownloading ? widget.cancel : null,
              child: Text(l10n.common_cancel),
            ),
          ] else
            OutlinedButton(
              onPressed: widget.blocked ? null : _confirmDownload,
              child: Text(l10n.translation_downloadModel),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/l10n.dart';

/// A reusable QR code display widget for sharing data.
///
/// Features:
/// - Configurable size and colors
/// - Optional logo/icon in center
/// - Automatic theming (light/dark mode aware)
/// - Title and instructions
class QrCodeDisplay extends StatelessWidget {
  /// The data to encode in the QR code
  final String data;

  /// Size of the QR code (width and height)
  final double size;

  /// Optional widget to display in the center (e.g., app logo)
  final Widget? embeddedImage;

  /// Size of the embedded image (if provided)
  final double embeddedImageSize;

  /// Title displayed above the QR code
  final String? title;

  /// Instructions displayed below the QR code
  final String? instructions;

  /// Background color of the QR code (defaults to white)
  final Color? backgroundColor;

  /// Foreground color of the QR code modules (defaults to black)
  final Color? foregroundColor;

  /// Padding around the QR code
  final EdgeInsets padding;

  /// Error correction level
  final int errorCorrectionLevel;

  const QrCodeDisplay({
    super.key,
    required this.data,
    this.size = 200,
    this.embeddedImage,
    this.embeddedImageSize = 50,
    this.title,
    this.instructions,
    this.backgroundColor,
    this.foregroundColor,
    this.padding = const EdgeInsets.all(16),
    this.errorCorrectionLevel = QrErrorCorrectLevel.M,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Default colors based on theme
    final bgColor = backgroundColor ?? Colors.white;
    final fgColor = foregroundColor ?? Colors.black;

    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],

          // QR code container with rounded corners
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: embeddedImage != null
                ? _buildQrWithEmbeddedImage(fgColor, bgColor)
                : _buildSimpleQr(fgColor, bgColor),
          ),

          if (instructions != null) ...[
            const SizedBox(height: 16),
            Text(
              instructions!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSimpleQr(Color fgColor, Color bgColor) {
    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      backgroundColor: bgColor,
      errorCorrectionLevel: errorCorrectionLevel,
      eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: fgColor),
      dataModuleStyle: QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: fgColor,
      ),
    );
  }

  Widget _buildQrWithEmbeddedImage(Color fgColor, Color bgColor) {
    return Stack(
      alignment: Alignment.center,
      children: [
        QrImageView(
          data: data,
          version: QrVersions.auto,
          size: size,
          backgroundColor: bgColor,
          // Use higher error correction when embedding image
          errorCorrectionLevel: QrErrorCorrectLevel.H,
          eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: fgColor),
          dataModuleStyle: QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: fgColor,
          ),
        ),
        Container(
          width: embeddedImageSize,
          height: embeddedImageSize,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(4),
          child: embeddedImage,
        ),
      ],
    );
  }
}

/// Dialog to display a QR code for sharing
class QrCodeShareDialog extends StatelessWidget {
  final String data;
  final String? title;
  final String? instructions;
  final Widget? embeddedImage;

  const QrCodeShareDialog({
    super.key,
    required this.data,
    this.title,
    this.instructions,
    this.embeddedImage,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrCodeDisplay(
              data: data,
              size: 250,
              title: title,
              instructions: instructions,
              embeddedImage: embeddedImage,
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.common_done),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Show the dialog
  static Future<void> show({
    required BuildContext context,
    required String data,
    String? title,
    String? instructions,
    Widget? embeddedImage,
  }) {
    return showDialog(
      context: context,
      builder: (context) => QrCodeShareDialog(
        data: data,
        title: title,
        instructions: instructions,
        embeddedImage: embeddedImage,
      ),
    );
  }
}

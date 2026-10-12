import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// A reusable QR code scanner widget that can be embedded anywhere.
///
/// Features:
/// - Configurable scan window overlay
/// - Flash toggle button
/// - Camera switch button (front/back)
/// - Customizable callbacks for scan results
/// - Optional validation function for QR data
/// - Automatic pause when not visible
/// - Debouncing to prevent duplicate scans
class QrScannerWidget extends StatefulWidget {
  /// Called when a valid QR code is scanned
  final void Function(String data) onScanned;

  /// Optional validator - return true if the QR data is valid
  final bool Function(String data)? validator;

  /// Optional error callback when validation fails
  final void Function(String data)? onValidationFailed;

  /// Whether to show the flash toggle button
  final bool showFlashButton;

  /// Whether to show the camera switch button
  final bool showCameraSwitchButton;

  /// Custom overlay widget (defaults to scan window frame)
  final Widget? overlay;

  /// Instructions text shown below the scan window
  final String? instructions;

  /// Whether to continue scanning after first successful scan
  final bool continuousScanning;

  /// Debounce duration to prevent duplicate scans
  final Duration debounceDuration;

  const QrScannerWidget({
    super.key,
    required this.onScanned,
    this.validator,
    this.onValidationFailed,
    this.showFlashButton = true,
    this.showCameraSwitchButton = true,
    this.overlay,
    this.instructions,
    this.continuousScanning = false,
    this.debounceDuration = const Duration(milliseconds: 500),
  });

  @override
  State<QrScannerWidget> createState() => _QrScannerWidgetState();
}

class _QrScannerWidgetState extends State<QrScannerWidget>
    with WidgetsBindingObserver {
  late MobileScannerController _controller;
  bool _hasScanned = false;
  String? _lastScannedData;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes - pause/resume scanner
    if (!_controller.value.hasCameraPermission) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _controller.start();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _controller.stop();
        break;
    }
  }

  void _handleDetection(BarcodeCapture capture) {
    // Prevent duplicate scans
    if (_hasScanned && !widget.continuousScanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue == null || rawValue.isEmpty) continue;

      // Debounce - ignore if same data scanned too quickly
      final now = DateTime.now();
      if (_lastScannedData == rawValue &&
          _lastScanTime != null &&
          now.difference(_lastScanTime!) < widget.debounceDuration) {
        continue;
      }

      _lastScannedData = rawValue;
      _lastScanTime = now;

      // Validate if validator provided
      if (widget.validator != null && !widget.validator!(rawValue)) {
        widget.onValidationFailed?.call(rawValue);
        continue;
      }

      // Mark as scanned to prevent duplicates
      if (!widget.continuousScanning) {
        setState(() {
          _hasScanned = true;
        });
        _controller.stop();
      }

      // Notify callback
      widget.onScanned(rawValue);
      return;
    }
  }

  /// Reset the scanner to allow scanning again
  void resetScanner() {
    setState(() {
      _hasScanned = false;
      _lastScannedData = null;
      _lastScanTime = null;
    });
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    // The camera preview is dark, so keep the system bar icons light, and lift
    // the controls above the navigation bar the app draws behind.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Stack(
        children: [
          // Scanner view
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetection,
            errorBuilder: (context, error) {
              return _buildErrorWidget(context, error);
            },
          ),

          // Overlay
          widget.overlay ?? _buildDefaultOverlay(context),

          // Control buttons
          Positioned(
            bottom: 16 + MediaQuery.viewPaddingOf(context).bottom,
            left: 0,
            right: 0,
            child: _buildControls(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultOverlay(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withValues(alpha: 0.5),
        BlendMode.srcOut,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.black,
              backgroundBlendMode: BlendMode.dstOut,
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 250,
                  width: 250,
                  decoration: BoxDecoration(
                    color: Colors.red, // This color is used for cutout
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                if (widget.instructions != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.instructions!,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.showFlashButton)
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, child) {
              return IconButton.filled(
                onPressed: () => _controller.toggleTorch(),
                icon: Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
              );
            },
          ),
        if (widget.showFlashButton && widget.showCameraSwitchButton)
          const SizedBox(width: 24),
        if (widget.showCameraSwitchButton)
          IconButton.filled(
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
            ),
          ),
      ],
    );
  }

  Widget _buildErrorWidget(BuildContext context, MobileScannerException error) {
    String message;
    IconData icon;

    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        message =
            'Camera permission denied.\nPlease enable camera access in settings.';
        icon = Icons.no_photography;
        break;
      case MobileScannerErrorCode.unsupported:
        message = 'Camera not supported on this device.';
        icon = Icons.videocam_off;
        break;
      default:
        message =
            'Failed to start camera.\n${error.errorDetails?.message ?? ''}';
        icon = Icons.error_outline;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

/// A simpler scanner overlay with just corner brackets
class ScannerCornerOverlay extends StatelessWidget {
  final double scanWindowSize;
  final Color borderColor;
  final double borderWidth;
  final double cornerLength;

  const ScannerCornerOverlay({
    super.key,
    this.scanWindowSize = 250,
    this.borderColor = Colors.white,
    this.borderWidth = 3,
    this.cornerLength = 30,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: scanWindowSize,
        height: scanWindowSize,
        child: CustomPaint(
          painter: _CornerPainter(
            color: borderColor,
            strokeWidth: borderWidth,
            cornerLength: cornerLength,
          ),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double cornerLength;

  _CornerPainter({
    required this.color,
    required this.strokeWidth,
    required this.cornerLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    // Top-left corner
    path.moveTo(0, cornerLength);
    path.lineTo(0, 0);
    path.lineTo(cornerLength, 0);

    // Top-right corner
    path.moveTo(size.width - cornerLength, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, cornerLength);

    // Bottom-right corner
    path.moveTo(size.width, size.height - cornerLength);
    path.lineTo(size.width, size.height);
    path.lineTo(size.width - cornerLength, size.height);

    // Bottom-left corner
    path.moveTo(cornerLength, size.height);
    path.lineTo(0, size.height);
    path.lineTo(0, size.height - cornerLength);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

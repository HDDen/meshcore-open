import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_palette.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';

enum _CanvasTool { pencil, fill }

class CanvasEditorScreen extends StatefulWidget {
  final int maxTextChars;

  const CanvasEditorScreen({super.key, required this.maxTextChars});

  @override
  State<CanvasEditorScreen> createState() => _CanvasEditorScreenState();
}

class _CanvasEditorScreenState extends State<CanvasEditorScreen> {
  static const int _minCanvasSize = 2;
  static const int _maxCanvasSize = 85;
  static const int _defaultSize = 11;
  // Keep a small text budget for a human-readable image marker around the codec payload.
  static const int _humanReadablePrefixReserveChars = 4;
  static const double _compressedCellBudgetMultiplier = 2.0;

  final _widthController = TextEditingController(text: '$_defaultSize');
  final _heightController = TextEditingController(text: '$_defaultSize');
  final _codec = MCOImageCodec();

  int _width = _defaultSize;
  int _height = _defaultSize;
  PaletteProfile _paletteProfile = PaletteProfile.master64;
  int _selectedColor = MCOImagePalette.blackIndex;
  _CanvasTool _selectedTool = _CanvasTool.pencil;
  bool _showGrid = true;
  late List<int> _pixels;

  @override
  void initState() {
    super.initState();
    _pixels = List.filled(_width * _height, MCOImagePalette.whiteIndex);
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(_paletteProfile);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.chat_canvas)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.chat_canvasChangeSize,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildSizeInput(
                      controller: _widthController,
                      label: context.l10n.chat_canvasWidth,
                      onChanged: (value) =>
                          _resize(width: _boundedWidth(value)),
                      onEditingComplete: (value) {
                        final bounded = _boundedWidth(value);
                        _resize(width: bounded);
                        _setControllerValue(_widthController, bounded);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSizeInput(
                      controller: _heightController,
                      label: context.l10n.chat_canvasHeight,
                      onChanged: (value) =>
                          _resize(height: _boundedHeight(value)),
                      onEditingComplete: (value) {
                        final bounded = _boundedHeight(value);
                        _resize(height: bounded);
                        _setControllerValue(_heightController, bounded);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.chat_canvasGridShow),
                value: _showGrid,
                onChanged: (value) {
                  setState(() => _showGrid = value ?? true);
                },
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.chat_canvasPalette,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PaletteProfile>(
                initialValue: _paletteProfile,
                decoration: InputDecoration(
                  labelText: context.l10n.chat_canvasPaletteMode,
                  border: const OutlineInputBorder(),
                ),
                items: PaletteProfile.values
                    .map(
                      (profile) => DropdownMenuItem(
                        value: profile,
                        child: Text(_paletteLabel(profile)),
                      ),
                    )
                    .toList(),
                onChanged: (profile) {
                  if (profile == null) return;
                  _changePaletteProfile(profile);
                },
              ),
              const SizedBox(height: 12),
              _buildPalette(palette),
              const SizedBox(height: 16),
              _buildTools(),
              const SizedBox(height: 20),
              _buildCanvas(palette),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loadCanvasFromFile,
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(_canvasLoadLabel(context)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _saveCanvasToPng,
                    icon: const Icon(Icons.save_alt_outlined),
                    label: Text(context.l10n.chat_canvasSave),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _clearCanvas,
                    child: Text(context.l10n.common_clear),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.common_cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sendCanvas,
                    child: Text(context.l10n.common_send),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSizeInput({
    required TextEditingController controller,
    required String label,
    required ValueChanged<int> onChanged,
    required ValueChanged<int> onEditingComplete,
  }) {
    void commitValue() {
      final parsed = int.tryParse(controller.text) ?? _defaultSize;
      onEditingComplete(parsed);
    }

    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) commitValue();
      },
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) {
          final parsed = int.tryParse(value);
          if (parsed == null) return;
          onChanged(parsed.clamp(_minCanvasSize, _maxCanvasSize).toInt());
        },
        onEditingComplete: commitValue,
      ),
    );
  }

  Widget _buildPalette(List<Color> palette) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var index = 0; index < palette.length; index++)
          _PaletteSwatch(
            color: palette[index],
            selected: index == _selectedColor,
            onTap: () => setState(() => _selectedColor = index),
          ),
      ],
    );
  }

  Widget _buildTools() {
    return SegmentedButton<_CanvasTool>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: _CanvasTool.pencil,
          icon: Icon(Icons.edit_outlined),
        ),
        ButtonSegment(
          value: _CanvasTool.fill,
          icon: Icon(Icons.format_color_fill_outlined),
        ),
      ],
      selected: {_selectedTool},
      onSelectionChanged: (selection) {
        setState(() => _selectedTool = selection.first);
      },
    );
  }

  Widget _buildCanvas(List<Color> palette) {
    final mediaHeight = MediaQuery.of(context).size.height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = mediaHeight * 0.55;
        final canvasWidth = math.min(maxWidth, maxHeight * _width / _height);
        final canvasHeight = canvasWidth * _height / _width;
        final size = Size(canvasWidth, canvasHeight);

        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) => _applyToolAt(details.localPosition, size),
            onPanUpdate: (details) {
              if (_selectedTool == _CanvasTool.pencil) {
                _applyToolAt(details.localPosition, size);
              }
            },
            child: CustomPaint(
              size: size,
              painter: _PixelCanvasPainter(
                width: _width,
                height: _height,
                pixels: _pixels,
                palette: palette,
                showGrid: _showGrid,
              ),
            ),
          ),
        );
      },
    );
  }

  void _resize({int? width, int? height}) {
    final newWidth = width ?? _width;
    final newHeight = height ?? _height;
    if (newWidth == _width && newHeight == _height) return;

    // Keep the old drawing centered when dimensions change; shrinking crops
    // from the edges instead of always losing the right/bottom side.
    final nextPixels = List.filled(
      newWidth * newHeight,
      MCOImagePalette.whiteIndex,
    );
    final copyWidth = math.min(_width, newWidth);
    final copyHeight = math.min(_height, newHeight);
    final oldStartX = math.max(0, (_width - newWidth) ~/ 2);
    final oldStartY = math.max(0, (_height - newHeight) ~/ 2);
    final newStartX = math.max(0, (newWidth - _width) ~/ 2);
    final newStartY = math.max(0, (newHeight - _height) ~/ 2);
    for (var y = 0; y < copyHeight; y++) {
      for (var x = 0; x < copyWidth; x++) {
        nextPixels[(newStartY + y) * newWidth + newStartX + x] =
            _pixels[(oldStartY + y) * _width + oldStartX + x];
      }
    }

    setState(() {
      _width = newWidth;
      _height = newHeight;
      _pixels = nextPixels;
    });
  }

  int get _maxCanvasCells {
    final usablePayload = math.max(
      0,
      widget.maxTextChars - _humanReadablePrefixReserveChars,
    );
    final byCompressedBudget = (usablePayload * _compressedCellBudgetMultiplier)
        .floor();
    return math.max(
      _minCanvasSize * _minCanvasSize,
      math.min(_maxCanvasSize * _maxCanvasSize, byCompressedBudget),
    );
  }

  int _boundedWidth(int width) {
    final maxWidth = math.max(
      _minCanvasSize,
      math.min(_maxCanvasSize, _maxCanvasCells ~/ _height),
    );
    return width.clamp(_minCanvasSize, maxWidth).toInt();
  }

  int _boundedHeight(int height) {
    final maxHeight = math.max(
      _minCanvasSize,
      math.min(_maxCanvasSize, _maxCanvasCells ~/ _width),
    );
    return height.clamp(_minCanvasSize, maxHeight).toInt();
  }

  void _setControllerValue(TextEditingController controller, int value) {
    controller.text = '$value';
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
  }

  void _changePaletteProfile(PaletteProfile profile) {
    final maxColor = _paletteFor(profile).length - 1;
    setState(() {
      _paletteProfile = profile;
      _selectedColor = math.min(_selectedColor, maxColor);
      _pixels = _pixels
          .map(
            (color) => color <= maxColor ? color : MCOImagePalette.whiteIndex,
          )
          .toList();
    });
  }

  void _applyToolAt(Offset position, Size size) {
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx > size.width ||
        position.dy > size.height) {
      return;
    }
    final x = (position.dx / (size.width / _width))
        .floor()
        .clamp(0, _width - 1)
        .toInt();
    final y = (position.dy / (size.height / _height))
        .floor()
        .clamp(0, _height - 1)
        .toInt();
    final index = y * _width + x;
    if (_selectedTool == _CanvasTool.pencil) {
      _paintPixel(index);
    } else {
      _fillArea(index);
    }
  }

  void _paintPixel(int index) {
    if (_pixels[index] == _selectedColor) return;
    setState(() {
      _pixels = List.of(_pixels);
      _pixels[index] = _selectedColor;
    });
  }

  void _fillArea(int startIndex) {
    final targetColor = _pixels[startIndex];
    if (targetColor == _selectedColor) return;

    final nextPixels = List.of(_pixels);
    final queue = <int>[startIndex];
    nextPixels[startIndex] = _selectedColor;

    while (queue.isNotEmpty) {
      final index = queue.removeLast();
      final x = index % _width;
      final y = index ~/ _width;

      void addIfSame(int nextIndex) {
        if (nextPixels[nextIndex] != targetColor) return;
        nextPixels[nextIndex] = _selectedColor;
        queue.add(nextIndex);
      }

      if (x > 0) addIfSame(index - 1);
      if (x < _width - 1) addIfSame(index + 1);
      if (y > 0) addIfSame(index - _width);
      if (y < _height - 1) addIfSame(index + _width);
    }

    setState(() => _pixels = nextPixels);
  }

  void _clearCanvas() {
    setState(() {
      _pixels = List.filled(_width * _height, MCOImagePalette.whiteIndex);
    });
  }

  Future<void> _loadCanvasFromFile() async {
    try {
      final file = await file_selector.openFile(
        acceptedTypeGroups: const [
          file_selector.XTypeGroup(
            label: 'Images',
            extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
            mimeTypes: ['image/png', 'image/jpeg', 'image/webp', 'image/bmp'],
          ),
        ],
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final pixels = await _imageBytesToCanvasPixels(bytes);
      if (!mounted) return;
      setState(() => _pixels = pixels);
    } catch (error) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(error.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<List<int>> _imageBytesToCanvasPixels(Uint8List bytes) async {
    final source = await _decodeImage(bytes);
    final scale = math.min(_width / source.width, _height / source.height);
    final targetWidth = math.max(
      1,
      math.min(_width, (source.width * scale).floor()),
    );
    final targetHeight = math.max(
      1,
      math.min(_height, (source.height * scale).floor()),
    );
    source.dispose();

    final scaled = await _decodeImage(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final rgba = await scaled.toByteData(format: ui.ImageByteFormat.rawRgba);
    scaled.dispose();
    if (rgba == null) {
      throw const MCOImageInvalidInputException('Cannot read image pixels');
    }

    final palette = _paletteFor(_paletteProfile);
    final nextPixels = List.filled(
      _width * _height,
      MCOImagePalette.whiteIndex,
    );
    final startX = (_width - targetWidth) ~/ 2;
    final startY = (_height - targetHeight) ~/ 2;
    for (var y = 0; y < targetHeight; y++) {
      for (var x = 0; x < targetWidth; x++) {
        final offset = (y * targetWidth + x) * 4;
        final colorIndex = _nearestPaletteColor(
          rgba.getUint8(offset),
          rgba.getUint8(offset + 1),
          rgba.getUint8(offset + 2),
          rgba.getUint8(offset + 3),
          palette,
        );
        nextPixels[(startY + y) * _width + startX + x] = colorIndex;
      }
    }
    return nextPixels;
  }

  Future<ui.Image> _decodeImage(
    Uint8List bytes, {
    int? targetWidth,
    int? targetHeight,
  }) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  int _nearestPaletteColor(
    int red,
    int green,
    int blue,
    int alpha,
    List<Color> palette,
  ) {
    if (alpha == 0) return MCOImagePalette.whiteIndex;
    final opacity = alpha / 255;
    final compositeRed = (red * opacity + 255 * (1 - opacity)).round();
    final compositeGreen = (green * opacity + 255 * (1 - opacity)).round();
    final compositeBlue = (blue * opacity + 255 * (1 - opacity)).round();

    var bestIndex = 0;
    var bestDistance = 1 << 62;
    for (var index = 0; index < palette.length; index++) {
      final argb = palette[index].toARGB32();
      final paletteRed = (argb >> 16) & 0xff;
      final paletteGreen = (argb >> 8) & 0xff;
      final paletteBlue = argb & 0xff;
      final redDistance = compositeRed - paletteRed;
      final greenDistance = compositeGreen - paletteGreen;
      final blueDistance = compositeBlue - paletteBlue;
      final distance =
          redDistance * redDistance +
          greenDistance * greenDistance +
          blueDistance * blueDistance;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  Future<void> _saveCanvasToPng() async {
    try {
      final bytes = await _renderCanvasPngBytes();
      final timestamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final fileName = 'meshcore_canvas_$timestamp.png';
      final location = await file_selector.getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          file_selector.XTypeGroup(
            label: 'PNG image',
            extensions: ['png'],
            mimeTypes: ['image/png'],
          ),
        ],
      );
      if (location == null) return;
      await XFile.fromData(
        bytes,
        mimeType: 'image/png',
        name: fileName,
      ).saveTo(location.path);
    } catch (error) {
      if (await _shareCanvasPngFallback()) return;
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(error.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<bool> _shareCanvasPngFallback() async {
    try {
      final bytes = await _renderCanvasPngBytes();
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType: 'image/png',
              name: 'meshcore_canvas.png',
            ),
          ],
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List> _renderCanvasPngBytes() async {
    const cellSize = 16;
    final palette = _paletteFor(_paletteProfile);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = Paint()..isAntiAlias = false;

    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        final colorIndex = _pixels[y * _width + x]
            .clamp(0, palette.length - 1)
            .toInt();
        paint.color = palette[colorIndex];
        canvas.drawRect(
          ui.Rect.fromLTWH(
            (x * cellSize).toDouble(),
            (y * cellSize).toDouble(),
            cellSize.toDouble(),
            cellSize.toDouble(),
          ),
          paint,
        );
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(_width * cellSize, _height * cellSize);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (png == null) {
      throw const MCOImageInvalidInputException('Cannot render PNG');
    }
    return png.buffer.asUint8List();
  }

  void _sendCanvas() {
    final maxChars = math.max(
      0,
      widget.maxTextChars - _humanReadablePrefixReserveChars,
    );
    try {
      final encoded = _codec.encode(
        MCOImage(
          width: _width,
          height: _height,
          paletteProfile: _paletteProfile,
          pixels: _pixels,
        ),
        maxChars: maxChars,
        backgroundColor: MCOImagePalette.whiteIndex,
      );
      Navigator.pop(context, encoded.text);
    } on MCOImageTooLargeException {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.chat_canvasSendPayloadExceed),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    } on MCOImageCodecException catch (error) {
      showDismissibleSnackBar(
        context,
        content: Text(error.message),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  String _paletteLabel(PaletteProfile profile) {
    return switch (profile) {
      PaletteProfile.mono => 'Mono',
      PaletteProfile.master4 => 'Master 4',
      PaletteProfile.master32 => 'Master 32',
      PaletteProfile.master64 => 'Master 64',
    };
  }

  List<Color> _paletteFor(PaletteProfile profile) {
    return switch (profile) {
      PaletteProfile.mono => MCOImagePalette.mono,
      PaletteProfile.master4 => MCOImagePalette.master4,
      PaletteProfile.master32 => MCOImagePalette.master32,
      PaletteProfile.master64 => MCOImagePalette.master64,
    };
  }

  String _canvasLoadLabel(BuildContext context) {
    try {
      return (context.l10n as dynamic).chat_canvasLoad as String;
    } catch (_) {
      return 'Load from file';
    }
  }
}

class _PaletteSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

class _PixelCanvasPainter extends CustomPainter {
  static const Color _gridColor = Color(0xff00ff00);

  final int width;
  final int height;
  final List<int> pixels;
  final List<Color> palette;
  final bool showGrid;

  const _PixelCanvasPainter({
    required this.width,
    required this.height,
    required this.pixels,
    required this.palette,
    required this.showGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / width;
    final cellHeight = size.height / height;
    final paint = Paint()..isAntiAlias = false;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final colorIndex = pixels[y * width + x]
            .clamp(0, palette.length - 1)
            .toInt();
        paint.color = palette[colorIndex];
        canvas.drawRect(
          Rect.fromLTWH(x * cellWidth, y * cellHeight, cellWidth, cellHeight),
          paint,
        );
      }
    }

    if (!showGrid) return;
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 0.6
      ..isAntiAlias = false;
    for (var x = 0; x <= width; x++) {
      final dx = x * cellWidth;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridPaint);
    }
    for (var y = 0; y <= height; y++) {
      final dy = y * cellHeight;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PixelCanvasPainter oldDelegate) {
    return oldDelegate.width != width ||
        oldDelegate.height != height ||
        oldDelegate.pixels != pixels ||
        oldDelegate.palette != palette ||
        oldDelegate.showGrid != showGrid;
  }
}

import 'dart:async';
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
import '../storage/prefs_manager.dart';

enum _CanvasTool { pencil, fill, eyedropper }

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
  // Master64 is the baseline; smaller palettes need fewer bits per cell, so we
  // allow a larger editor grid and still validate the exact encoded payload.
  static const double _master64CellBudgetMultiplier = 2.1;
  static const int _master64BitsPerCell = 6;
  static const Duration _payloadRefreshThrottle = Duration(seconds: 1);
  static const String _prefsWidthKey = 'canvas_editor_width';
  static const String _prefsHeightKey = 'canvas_editor_height';
  static const String _prefsPaletteKey = 'canvas_editor_palette';
  static const List<PaletteProfile> _paletteProfileOptions = [
    PaletteProfile.mono,
    PaletteProfile.grayscale8,
    PaletteProfile.grayscale16,
    PaletteProfile.grayscale32,
    PaletteProfile.master4,
    PaletteProfile.master8,
    PaletteProfile.master16,
    PaletteProfile.master32,
    PaletteProfile.master64,
  ];

  final _widthController = TextEditingController(text: '$_defaultSize');
  final _heightController = TextEditingController(text: '$_defaultSize');
  final _codec = MCOImageCodec();

  int _width = _defaultSize;
  int _height = _defaultSize;
  PaletteProfile _paletteProfile = PaletteProfile.master64;
  int _selectedColor = MCOImagePalette.blackIndexFor(PaletteProfile.master64);
  _CanvasTool _selectedTool = _CanvasTool.pencil;
  bool _showGrid = true;
  late List<int> _pixels;
  Timer? _payloadRefreshTimer;
  DateTime? _lastPayloadRefreshAt;
  bool _payloadRefreshPending = false;
  bool _payloadRefreshInProgress = false;
  bool _isDrawing = false;
  bool _canvasInputLocked = false;
  int _currentPayloadChars = 0;

  @override
  void initState() {
    super.initState();
    _pixels = List.filled(_width * _height, _whiteIndex);
    _currentPayloadChars = _calculatePayloadChars();
    _lastPayloadRefreshAt = DateTime.now();
    _loadSavedCanvasSettings();
  }

  @override
  void dispose() {
    _payloadRefreshTimer?.cancel();
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
          physics: _canvasInputLocked
              ? const NeverScrollableScrollPhysics()
              : null,
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
                      fallbackValue: _width,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSizeInput(
                      controller: _heightController,
                      label: context.l10n.chat_canvasHeight,
                      fallbackValue: _height,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _applyCanvasSize,
                  child: Text(context.l10n.common_apply),
                ),
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
                items: _paletteProfileOptions
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
              const SizedBox(height: 8),
              _buildPayloadInfo(context),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loadCanvasFromFile,
                      icon: const Icon(Icons.file_open_outlined),
                      label: Text(
                        _canvasLoadLabel(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saveCanvasToPng,
                      icon: const Icon(Icons.save_alt_outlined),
                      label: Text(
                        context.l10n.chat_canvasSave,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
    required int fallbackValue,
  }) {
    void commitValue() {
      final parsed = int.tryParse(controller.text) ?? fallbackValue;
      final bounded = parsed.clamp(_minCanvasSize, _maxCanvasSize).toInt();
      _setControllerValue(controller, bounded);
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
        ButtonSegment(
          value: _CanvasTool.eyedropper,
          icon: Icon(Icons.colorize_outlined),
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
            onPanDown: _canvasInputLocked
                ? (details) {
                    _isDrawing = true;
                    _applyToolAt(details.localPosition, size);
                  }
                : null,
            onPanUpdate: _canvasInputLocked
                ? (details) {
                    if (_selectedTool == _CanvasTool.pencil) {
                      _applyToolAt(details.localPosition, size);
                    }
                  }
                : null,
            onPanEnd: _canvasInputLocked ? (_) => _finishDrawing() : null,
            onPanCancel: _canvasInputLocked ? _finishDrawing : null,
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

  Widget _buildPayloadInfo(BuildContext context) {
    final isOverLimit = _currentPayloadChars > _sendPayloadLimit;
    final mediaHeight = MediaQuery.of(context).size.height;
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = mediaHeight * 0.55;
        final contentWidth = math.min(maxWidth, maxHeight * _width / _height);

        return Center(
          child: SizedBox(
            width: contentWidth,
            child: Row(
              children: [
                IconButton.filled(
                  onPressed: () {
                    _finishDrawing();
                    setState(() => _canvasInputLocked = !_canvasInputLocked);
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: _canvasInputLocked
                        ? const Color(0xffb8f5b8)
                        : colorScheme.surfaceContainerHighest,
                    foregroundColor: _canvasInputLocked
                        ? Colors.green.shade900
                        : colorScheme.onSurfaceVariant,
                  ),
                  icon: Icon(
                    _canvasInputLocked
                        ? Icons.lock_outline
                        : Icons.lock_open_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      context.l10n.chat_canvasCurrentPayload(
                        _currentPayloadChars,
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isOverLimit ? colorScheme.error : null,
                      ),
                    ),
                  ),
                ),
              ],
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
    final oldWidth = _width;
    final oldHeight = _height;
    final nextPixels = _resizePixels(
      sourcePixels: _pixels,
      sourceWidth: oldWidth,
      sourceHeight: oldHeight,
      targetWidth: newWidth,
      targetHeight: newHeight,
      fillColor: _whiteIndex,
    );

    setState(() {
      _width = newWidth;
      _height = newHeight;
      _pixels = nextPixels;
    });
    _markPayloadDirty();
  }

  List<int> _resizePixels({
    required List<int> sourcePixels,
    required int sourceWidth,
    required int sourceHeight,
    required int targetWidth,
    required int targetHeight,
    required int fillColor,
  }) {
    if (targetWidth < sourceWidth || targetHeight < sourceHeight) {
      return _scalePixels(
        sourcePixels: sourcePixels,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
    }

    // Keep the old drawing centered when adding new empty space.
    final nextPixels = List.filled(targetWidth * targetHeight, fillColor);
    final copyWidth = math.min(sourceWidth, targetWidth);
    final copyHeight = math.min(sourceHeight, targetHeight);
    final oldStartX = math.max(0, (sourceWidth - targetWidth) ~/ 2);
    final oldStartY = math.max(0, (sourceHeight - targetHeight) ~/ 2);
    final newStartX = math.max(0, (targetWidth - sourceWidth) ~/ 2);
    final newStartY = math.max(0, (targetHeight - sourceHeight) ~/ 2);
    for (var y = 0; y < copyHeight; y++) {
      for (var x = 0; x < copyWidth; x++) {
        nextPixels[(newStartY + y) * targetWidth + newStartX + x] =
            sourcePixels[(oldStartY + y) * sourceWidth + oldStartX + x];
      }
    }
    return nextPixels;
  }

  List<int> _scalePixels({
    required List<int> sourcePixels,
    required int sourceWidth,
    required int sourceHeight,
    required int targetWidth,
    required int targetHeight,
  }) {
    final nextPixels = List<int>.filled(targetWidth * targetHeight, 0);
    for (var y = 0; y < targetHeight; y++) {
      final sourceY = ((y + 0.5) * sourceHeight / targetHeight)
          .floor()
          .clamp(0, sourceHeight - 1)
          .toInt();
      for (var x = 0; x < targetWidth; x++) {
        final sourceX = ((x + 0.5) * sourceWidth / targetWidth)
            .floor()
            .clamp(0, sourceWidth - 1)
            .toInt();
        nextPixels[y * targetWidth + x] =
            sourcePixels[sourceY * sourceWidth + sourceX];
      }
    }
    return nextPixels;
  }

  int _maxCanvasCellsForProfile(PaletteProfile profile) {
    final multiplier =
        _master64CellBudgetMultiplier *
        _master64BitsPerCell /
        _paletteBitsPerCell(profile);
    final byCompressedBudget = (_sendPayloadLimit * multiplier).floor();
    return math.max(
      _minCanvasSize * _minCanvasSize,
      math.min(_maxCanvasSize * _maxCanvasSize, byCompressedBudget),
    );
  }

  int get _sendPayloadLimit =>
      math.max(0, widget.maxTextChars - _humanReadablePrefixReserveChars);

  void _loadSavedCanvasSettings() {
    final prefs = PrefsManager.instance;
    final profileName = prefs.getString(_prefsPaletteKey);
    final profile = PaletteProfile.values.firstWhere(
      (value) => value.name == profileName,
      orElse: () => PaletteProfile.master64,
    );
    final requestedWidth = prefs.getInt(_prefsWidthKey) ?? _defaultSize;
    final requestedHeight = prefs.getInt(_prefsHeightKey) ?? _defaultSize;
    final bounded = _boundedCanvasSizeForProfile(
      requestedWidth,
      requestedHeight,
      profile,
    );
    final width = bounded[0];
    final height = bounded[1];

    _paletteProfile = profile;
    _selectedColor = MCOImagePalette.blackIndexFor(profile);
    _width = width;
    _height = height;
    _setControllerValue(_widthController, width);
    _setControllerValue(_heightController, height);
    _pixels = List.filled(width * height, _whiteIndex);
    _currentPayloadChars = _calculatePayloadChars();
    _lastPayloadRefreshAt = DateTime.now();
  }

  Future<void> _saveCanvasPalette(PaletteProfile profile) async {
    await PrefsManager.instance.setString(_prefsPaletteKey, profile.name);
  }

  Future<void> _saveCanvasSize(int width, int height) async {
    final prefs = PrefsManager.instance;
    await prefs.setInt(_prefsWidthKey, width);
    await prefs.setInt(_prefsHeightKey, height);
  }

  void _applyCanvasSize() {
    final requestedWidth = int.tryParse(_widthController.text) ?? _width;
    final requestedHeight = int.tryParse(_heightController.text) ?? _height;
    final bounded = _boundedCanvasSizeForProfile(
      requestedWidth,
      requestedHeight,
      _paletteProfile,
    );
    final width = bounded[0];
    final height = bounded[1];

    _setControllerValue(_widthController, width);
    _setControllerValue(_heightController, height);
    _resize(width: width, height: height);
    unawaited(_saveCanvasSize(width, height));
  }

  void _finishDrawing() {
    if (!_isDrawing) return;
    _isDrawing = false;
    if (_payloadRefreshPending) {
      _schedulePayloadRefresh();
    }
  }

  void _markPayloadDirty() {
    _payloadRefreshPending = true;
    _schedulePayloadRefresh();
  }

  void _schedulePayloadRefresh() {
    if (!mounted || (_payloadRefreshTimer?.isActive ?? false)) return;

    final now = DateTime.now();
    final lastRefresh = _lastPayloadRefreshAt;
    final elapsed = lastRefresh == null
        ? _payloadRefreshThrottle
        : now.difference(lastRefresh);
    final delay = elapsed >= _payloadRefreshThrottle
        ? Duration.zero
        : _payloadRefreshThrottle - elapsed;

    _payloadRefreshTimer = Timer(delay, _refreshPayloadIfIdle);
  }

  void _refreshPayloadIfIdle() {
    _payloadRefreshTimer = null;
    if (!mounted || !_payloadRefreshPending) return;

    // While the user is actively drawing, keep the canvas responsive and refresh
    // payload size after the gesture settles.
    if (_isDrawing || _payloadRefreshInProgress) {
      _payloadRefreshTimer = Timer(
        _payloadRefreshThrottle,
        _refreshPayloadIfIdle,
      );
      return;
    }

    _payloadRefreshPending = false;
    _payloadRefreshInProgress = true;
    final payloadChars = _calculatePayloadChars();
    _lastPayloadRefreshAt = DateTime.now();
    _payloadRefreshInProgress = false;

    if (!mounted) return;
    setState(() => _currentPayloadChars = payloadChars);
    if (_payloadRefreshPending) {
      _schedulePayloadRefresh();
    }
  }

  int _calculatePayloadChars() {
    final encoded = _codec.encode(
      MCOImage(
        width: _width,
        height: _height,
        paletteProfile: _paletteProfile,
        pixels: _pixels,
      ),
      backgroundColor: _whiteIndex,
    );
    return encoded.charLength;
  }

  List<int> _boundedCanvasSizeForProfile(
    int requestedWidth,
    int requestedHeight,
    PaletteProfile profile,
  ) {
    var width = requestedWidth.clamp(_minCanvasSize, _maxCanvasSize).toInt();
    var height = requestedHeight.clamp(_minCanvasSize, _maxCanvasSize).toInt();
    final maxCanvasCells = _maxCanvasCellsForProfile(profile);
    if (width * height <= maxCanvasCells) {
      return [width, height];
    }

    final scale = math.sqrt(maxCanvasCells / (width * height));
    width = math.max(_minCanvasSize, (width * scale).floor());
    height = math.max(_minCanvasSize, (height * scale).floor());

    // The proportional shrink above can still be one cell over because of
    // rounding; trim the larger requested side first.
    while (width * height > maxCanvasCells) {
      if (width >= height && width > _minCanvasSize) {
        width--;
      } else if (height > _minCanvasSize) {
        height--;
      } else {
        break;
      }
    }
    return [width, height];
  }

  void _setControllerValue(TextEditingController controller, int value) {
    controller.text = '$value';
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
  }

  void _changePaletteProfile(PaletteProfile profile) {
    if (profile == _paletteProfile) return;
    final oldPalette = _paletteFor(_paletteProfile);
    final newPalette = _paletteFor(profile);

    int mapColor(int colorIndex) {
      if (colorIndex < 0 || colorIndex >= oldPalette.length) {
        return MCOImagePalette.whiteIndexFor(profile);
      }
      final argb = oldPalette[colorIndex].toARGB32();
      return _nearestPaletteColor(
        (argb >> 16) & 0xff,
        (argb >> 8) & 0xff,
        argb & 0xff,
        (argb >> 24) & 0xff,
        newPalette,
        whiteIndex: MCOImagePalette.whiteIndexFor(profile),
      );
    }

    final nextSelectedColor = mapColor(_selectedColor);
    final mappedPixels = _pixels.map(mapColor).toList();
    final bounded = _boundedCanvasSizeForProfile(_width, _height, profile);
    final nextWidth = bounded[0];
    final nextHeight = bounded[1];
    final nextPixels = _resizePixels(
      sourcePixels: mappedPixels,
      sourceWidth: _width,
      sourceHeight: _height,
      targetWidth: nextWidth,
      targetHeight: nextHeight,
      fillColor: MCOImagePalette.whiteIndexFor(profile),
    );
    setState(() {
      _paletteProfile = profile;
      _selectedColor = nextSelectedColor;
      _width = nextWidth;
      _height = nextHeight;
      _setControllerValue(_widthController, nextWidth);
      _setControllerValue(_heightController, nextHeight);
      _pixels = nextPixels;
    });
    _markPayloadDirty();
    unawaited(_saveCanvasPalette(profile));
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
    switch (_selectedTool) {
      case _CanvasTool.pencil:
        _paintPixel(index);
        break;
      case _CanvasTool.fill:
        _fillArea(index);
        break;
      case _CanvasTool.eyedropper:
        _pickColor(index);
        break;
    }
  }

  void _paintPixel(int index) {
    if (_pixels[index] == _selectedColor) return;
    setState(() {
      _pixels = List.of(_pixels);
      _pixels[index] = _selectedColor;
    });
    _markPayloadDirty();
  }

  void _pickColor(int index) {
    final color = _pixels[index];
    if (color == _selectedColor) return;
    setState(() => _selectedColor = color);
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
    _markPayloadDirty();
  }

  void _clearCanvas() {
    setState(() {
      _pixels = List.filled(_width * _height, _whiteIndex);
    });
    _markPayloadDirty();
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
      _markPayloadDirty();
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
    final nextPixels = List.filled(_width * _height, _whiteIndex);
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
          whiteIndex: _whiteIndex,
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
    List<Color> palette, {
    required int whiteIndex,
  }) {
    if (alpha == 0) return whiteIndex;
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
    try {
      final encoded = _codec.encode(
        MCOImage(
          width: _width,
          height: _height,
          paletteProfile: _paletteProfile,
          pixels: _pixels,
        ),
        backgroundColor: _whiteIndex,
      );
      _currentPayloadChars = encoded.charLength;
      final overflow = encoded.charLength - _sendPayloadLimit;
      if (overflow > 0) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.chat_canvasSendPayloadExceed(overflow)),
          backgroundColor: Theme.of(context).colorScheme.error,
        );
        setState(() {});
        return;
      }
      Navigator.pop(context, encoded.text);
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
      PaletteProfile.master8 => 'Master 8',
      PaletteProfile.grayscale8 => 'Grayscale 8',
      PaletteProfile.master16 => 'Master 16',
      PaletteProfile.grayscale16 => 'Grayscale 16',
      PaletteProfile.master32 => 'Master 32',
      PaletteProfile.grayscale32 => 'Grayscale 32',
      PaletteProfile.master64 => 'Master 64',
    };
  }

  int _paletteBitsPerCell(PaletteProfile profile) {
    return switch (profile) {
      PaletteProfile.mono => 1,
      PaletteProfile.master4 => 2,
      PaletteProfile.master8 => 3,
      PaletteProfile.grayscale8 => 3,
      PaletteProfile.master16 => 4,
      PaletteProfile.grayscale16 => 4,
      PaletteProfile.master32 => 5,
      PaletteProfile.grayscale32 => 5,
      PaletteProfile.master64 => 6,
    };
  }

  List<Color> _paletteFor(PaletteProfile profile) {
    return switch (profile) {
      PaletteProfile.mono => MCOImagePalette.mono,
      PaletteProfile.master4 => MCOImagePalette.master4,
      PaletteProfile.master8 => MCOImagePalette.master8,
      PaletteProfile.grayscale8 => MCOImagePalette.grayscale8,
      PaletteProfile.master16 => MCOImagePalette.master16,
      PaletteProfile.grayscale16 => MCOImagePalette.grayscale16,
      PaletteProfile.master32 => MCOImagePalette.master32,
      PaletteProfile.grayscale32 => MCOImagePalette.grayscale32,
      PaletteProfile.master64 => MCOImagePalette.master64,
    };
  }

  int get _whiteIndex => MCOImagePalette.whiteIndexFor(_paletteProfile);

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

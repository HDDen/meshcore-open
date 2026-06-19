import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../helpers/channel_binary_data_helper.dart';
import '../helpers/mco_image_file_saver.dart';
import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_palette.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../services/app_settings_service.dart';
import '../storage/prefs_manager.dart';

enum _CanvasTool { pencil, fill, eyedropper, line, oval, rectangle }

enum _PaletteSelectorValue { dynamic }

class _CanvasSnapshot {
  final int width;
  final int height;
  final PaletteProfile paletteProfile;
  final PaletteProfile dynamicPaletteProfile;
  final MCOImageEncodingVersion encodingVersion;
  final int selectedColor;
  final int? transparentColor;
  final List<int> pixels;

  _CanvasSnapshot({
    required this.width,
    required this.height,
    required this.paletteProfile,
    required this.dynamicPaletteProfile,
    required this.encodingVersion,
    required this.selectedColor,
    required this.transparentColor,
    required List<int> pixels,
  }) : pixels = List<int>.unmodifiable(pixels);
}

class _CanvasHistoryEntry {
  final _CanvasSnapshot before;
  final _CanvasSnapshot after;

  const _CanvasHistoryEntry({required this.before, required this.after});
}

class _ImportedCanvasImage {
  final int width;
  final int height;
  final List<int> pixels;

  const _ImportedCanvasImage({
    required this.width,
    required this.height,
    required this.pixels,
  });
}

class CanvasEditorScreen extends StatefulWidget {
  final int maxTextChars;
  final int? maxBinaryPayloadBytes;
  final String? binarySenderName;
  final MCOImage? initialImage;

  const CanvasEditorScreen({
    super.key,
    required this.maxTextChars,
    this.maxBinaryPayloadBytes,
    this.binarySenderName,
    this.initialImage,
  });

  @override
  State<CanvasEditorScreen> createState() => _CanvasEditorScreenState();
}

class _CanvasEditorScreenState extends State<CanvasEditorScreen> {
  static const int _minCanvasSize = 2;
  static const int _maxCanvasSizeV1 = 85;
  static const int _maxCanvasSizeV2 = 256;
  static const int _defaultSize = 11;
  // Keep a small text budget for a human-readable image marker around the codec payload.
  static const int _humanReadablePrefixReserveChars = 4;
  // Master64 is the baseline; smaller palettes need fewer bits per cell, so we
  // allow a larger editor grid and still validate the exact encoded payload.
  static const double _master64CellBudgetMultiplier = 4.0;
  static const int _master64BitsPerCell = 6;
  static const Duration _payloadRefreshThrottle = Duration(seconds: 1);
  static const String _prefsWidthKey = 'canvas_editor_width';
  static const String _prefsHeightKey = 'canvas_editor_height';
  static const String _prefsPaletteKey = 'canvas_editor_palette';
  static const String _prefsUnlockSizeKey = 'canvas_editor_unlock_size';
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
  static const List<PaletteProfile> _dynamicPaletteProfileOptions = [
    PaletteProfile.dynamicGlobal8,
    PaletteProfile.dynamicGlobal16,
    PaletteProfile.dynamicGlobal32,
    PaletteProfile.dynamicGlobal64,
    PaletteProfile.dynamicGlobal128,
    PaletteProfile.dynamicGlobal256,
    PaletteProfile.dynamicGlobal512,
  ];
  static const int _inlineDynamicPaletteMaxColors = 64;
  static const int _historyLimit = 10;
  static const double _canvasRulerExtent = 12;
  static const Object _transparentColorUnchanged = Object();

  final _widthController = TextEditingController(text: '$_defaultSize');
  final _heightController = TextEditingController(text: '$_defaultSize');
  final _toolsScrollController = ScrollController();
  final _sizeActionsScrollController = ScrollController();
  final _codec = MCOImageCodec();

  int _width = _defaultSize;
  int _height = _defaultSize;
  PaletteProfile _paletteProfile = PaletteProfile.master64;
  PaletteProfile _dynamicPaletteProfile = PaletteProfile.dynamicGlobal512;
  int _selectedColor = MCOImagePalette.blackIndexFor(PaletteProfile.master64);
  int? _transparentColor;
  bool _isPickingTransparentColor = false;
  _CanvasTool _selectedTool = _CanvasTool.pencil;
  bool _showGrid = true;
  bool _showRuler = false;
  bool _unlockCanvasSize = false;
  MCOImageEncodingVersion _encodingVersion = MCOImageEncodingVersion.v2;
  late List<int> _pixels;
  Timer? _payloadRefreshTimer;
  DateTime? _lastPayloadRefreshAt;
  bool _payloadRefreshPending = false;
  bool _payloadRefreshInProgress = false;
  bool _isDrawing = false;
  bool _canvasInputLocked = false;
  int? _lineStartIndex;
  int? _ovalFirstIndex;
  int? _ovalSecondIndex;
  int? _rectangleFirstIndex;
  int? _rectangleSecondIndex;
  int _currentPayloadChars = 0;
  EncodedMCOImage? _currentEncodedCandidate;
  final List<_CanvasHistoryEntry> _undoStack = <_CanvasHistoryEntry>[];
  final List<_CanvasHistoryEntry> _redoStack = <_CanvasHistoryEntry>[];

  @override
  void initState() {
    super.initState();
    _pixels = List.filled(_width * _height, _whiteIndex);
    final initialImage = widget.initialImage;
    if (initialImage != null) {
      _loadInitialImage(initialImage);
    } else {
      _currentPayloadChars = _calculatePayloadChars();
      _lastPayloadRefreshAt = DateTime.now();
      _loadSavedCanvasSettings();
    }
  }

  @override
  void dispose() {
    _payloadRefreshTimer?.cancel();
    _widthController.dispose();
    _heightController.dispose();
    _toolsScrollController.dispose();
    _sizeActionsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(_paletteProfile);
    final showLockButton = context
        .watch<AppSettingsService>()
        .settings
        .canvasShowLockButton;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.chat_canvas)),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: showLockButton && _canvasInputLocked
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
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.chat_canvasUnlockSize),
                value: _unlockCanvasSize,
                onChanged: _setCanvasSizeUnlocked,
              ),
              const SizedBox(height: 8),
              _buildSizeActions(),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.chat_canvasGridShow),
                value: _showGrid,
                onChanged: (value) {
                  setState(() => _showGrid = value ?? true);
                },
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.chat_canvasRulerShow),
                value: _showRuler,
                onChanged: (value) {
                  setState(() => _showRuler = value ?? false);
                },
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.chat_canvasFormatVer,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MCOImageEncodingVersion>(
                key: ValueKey(_encodingVersion),
                initialValue: _encodingVersion,
                decoration: InputDecoration(
                  labelText: context.l10n.chat_canvasFormatVer,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final version in MCOImageEncodingVersion.values)
                    DropdownMenuItem(
                      value: version,
                      child: Text(_encodingVersionLabel(version)),
                    ),
                ],
                onChanged: (version) {
                  if (version == null) return;
                  _changeEncodingVersion(version);
                },
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.chat_canvasPalette,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Object>(
                key: ValueKey(
                  _paletteProfile.isDynamic
                      ? _PaletteSelectorValue.dynamic
                      : _paletteProfile,
                ),
                initialValue: _paletteProfile.isDynamic
                    ? _PaletteSelectorValue.dynamic
                    : _paletteProfile,
                decoration: InputDecoration(
                  labelText: context.l10n.chat_canvasPaletteMode,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  if (_supportsDynamicPalettes)
                    DropdownMenuItem<Object>(
                      value: _PaletteSelectorValue.dynamic,
                      child: Text(context.l10n.chat_canvasPaletteDynamic),
                    ),
                  for (final profile in _paletteProfileOptions)
                    DropdownMenuItem<Object>(
                      value: profile,
                      child: Text(_paletteLabel(profile)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  if (value == _PaletteSelectorValue.dynamic) {
                    _changePaletteProfile(_dynamicPaletteProfile);
                    return;
                  }
                  if (value is PaletteProfile) {
                    _changePaletteProfile(value);
                  }
                },
              ),
              const SizedBox(height: 12),
              if (_paletteProfile.isDynamic)
                _buildDynamicPaletteControls()
              else
                _buildPalette(palette),
              if (_supportsAlphaTransparency) ...[
                const SizedBox(height: 12),
                _buildPaletteAlphaControl(),
              ],
              const SizedBox(height: 16),
              _buildTools(),
              const SizedBox(height: 20),
              _buildCanvas(palette, showLockButton: showLockButton),
              const SizedBox(height: 8),
              _buildPayloadInfo(context, showLockButton: showLockButton),
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
              if (ChannelBinaryDataHelper.isAvailable) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _saveCanvasToBinary,
                    icon: const Icon(Icons.data_object_outlined),
                    label: Text(context.l10n.chat_canvasSaveBinary),
                  ),
                ),
              ],
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

  Widget _buildHorizontalScrollableButtonRow({
    required ScrollController controller,
    required Widget child,
  }) {
    return ScrollConfiguration(
      behavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          ui.PointerDeviceKind.touch,
          ui.PointerDeviceKind.mouse,
          ui.PointerDeviceKind.trackpad,
          ui.PointerDeviceKind.stylus,
        },
      ),
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildSizeActions() {
    return _buildHorizontalScrollableButtonRow(
      controller: _sizeActionsScrollController,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            onPressed: _trimEmptyCanvas,
            child: Text(
              context.l10n.chat_canvasTrim,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _cropCanvasSize,
            child: Text(
              context.l10n.chat_canvasCrop,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _applyCanvasSize,
            child: Text(context.l10n.chat_canvasResize),
          ),
        ],
      ),
    );
  }

  Widget _buildSizeInput({
    required TextEditingController controller,
    required String label,
    required int fallbackValue,
  }) {
    void commitValue() {
      final text = controller.text.trim();
      if (text.isEmpty) return;

      final parsed = int.tryParse(text) ?? fallbackValue;
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
        onTapOutside: (_) {
          FocusManager.instance.primaryFocus?.unfocus();
        },
        onEditingComplete: commitValue,
      ),
    );
  }

  Widget _buildPalette(
    List<Color> palette, {
    PaletteProfile? profile,
    void Function(int colorValue)? onColorSelected,
  }) {
    final paletteProfile = profile ?? _paletteProfile;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var index = 0; index < palette.length; index++)
          () {
            final colorValue = _paletteColorValueAtIndex(paletteProfile, index);
            return _PaletteSwatch(
              color: palette[index],
              selected: colorValue == _selectedColor,
              onTap: () {
                if (onColorSelected != null) {
                  onColorSelected(colorValue);
                  return;
                }
                _handlePaletteColorTap(colorValue);
              },
            );
          }(),
      ],
    );
  }

  Widget _buildPaletteAlphaControl() {
    if (!_supportsAlphaTransparency) return const SizedBox.shrink();
    final transparentColor = _transparentColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.l10n.chat_canvasPaletteAlpha,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(width: 8),
        _AlphaSwatch(
          color: transparentColor == null
              ? null
              : _colorForPixelValue(_paletteProfile, transparentColor),
          selected: _isPickingTransparentColor,
          onTap: () {
            setState(() {
              if (_isPickingTransparentColor) {
                if (_transparentColor != null) {
                  _transparentColor = null;
                  _markPayloadDirty();
                }
                _isPickingTransparentColor = false;
              } else {
                _isPickingTransparentColor = true;
              }
            });
          },
        ),
      ],
    );
  }

  void _handlePaletteColorTap(int colorValue) {
    if (_isPickingTransparentColor) {
      if (_transparentColor == colorValue) {
        setState(() => _isPickingTransparentColor = false);
        return;
      }
      setState(() {
        _transparentColor = colorValue;
        _isPickingTransparentColor = false;
      });
      _markPayloadDirty();
      return;
    }
    setState(() => _selectedColor = colorValue);
  }

  Widget _buildDynamicPaletteControls() {
    final palette = _paletteFor(_paletteProfile);
    final shouldInlinePalette =
        palette.length <= _inlineDynamicPaletteMaxColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<PaletteProfile>(
          key: ValueKey(_dynamicPaletteProfile),
          initialValue: _dynamicPaletteProfile,
          decoration: InputDecoration(
            labelText: context.l10n.chat_canvasPaletteDynamicProfile,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final profile in _dynamicPaletteProfileOptions)
              DropdownMenuItem(
                value: profile,
                child: Text(_paletteLabel(profile)),
              ),
          ],
          onChanged: (profile) {
            if (profile == null) return;
            _changePaletteProfile(profile);
          },
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.chat_canvasPaletteDynamicDscr,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (shouldInlinePalette)
          _buildPalette(palette)
        else
          OutlinedButton(
            onPressed: _showDynamicPaletteDialog,
            child: Text(context.l10n.chat_canvasPaletteShow),
          ),
        const SizedBox(height: 16),
        Text(
          context.l10n.chat_canvasPaletteDynamicUsed,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        _buildUsedDynamicPalette(),
      ],
    );
  }

  Widget _buildUsedDynamicPalette() {
    final colorValues = _usedColorValuesForProfile(_paletteProfile);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final colorValue in colorValues)
          _PaletteSwatch(
            color: _colorForPixelValue(_paletteProfile, colorValue),
            selected: colorValue == _selectedColor,
            onTap: () => _handlePaletteColorTap(colorValue),
          ),
      ],
    );
  }

  void _showDynamicPaletteDialog() {
    final profile = _paletteProfile;
    final palette = _paletteFor(profile);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(context.l10n.chat_canvasPaletteDynamicProfile),
          content: SingleChildScrollView(
            child: _buildPalette(
              palette,
              profile: profile,
              onColorSelected: (colorValue) {
                _handlePaletteColorTap(colorValue);
                Navigator.of(dialogContext).pop();
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.l10n.common_close),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTools() {
    Widget moveButton({
      required IconData icon,
      required int dx,
      required int dy,
    }) {
      return IconButton.outlined(
        onPressed: () => _shiftCanvas(dx: dx, dy: dy),
        icon: Icon(icon),
      );
    }

    final toolsRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          onPressed: _undoStack.isEmpty ? null : _undoCanvasAction,
          tooltip: 'Undo',
          icon: const Icon(Icons.undo),
        ),
        const SizedBox(width: 4),
        IconButton.outlined(
          onPressed: _redoStack.isEmpty ? null : _redoCanvasAction,
          tooltip: 'Redo',
          icon: const Icon(Icons.redo),
        ),
        const SizedBox(width: 12),
        SegmentedButton<_CanvasTool>(
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
            ButtonSegment(
              value: _CanvasTool.line,
              icon: Icon(Icons.show_chart_outlined),
            ),
            ButtonSegment(
              value: _CanvasTool.oval,
              icon: Icon(Icons.circle_outlined),
            ),
            ButtonSegment(
              value: _CanvasTool.rectangle,
              icon: Icon(Icons.crop_square),
            ),
          ],
          selected: {_selectedTool},
          onSelectionChanged: (selection) {
            final nextTool = selection.first;
            setState(() {
              if (nextTool != _selectedTool) {
                _lineStartIndex = null;
                _ovalFirstIndex = null;
                _ovalSecondIndex = null;
                _rectangleFirstIndex = null;
                _rectangleSecondIndex = null;
              }
              _selectedTool = nextTool;
            });
          },
        ),
        const SizedBox(width: 12),
        moveButton(icon: Icons.keyboard_arrow_left, dx: -1, dy: 0),
        const SizedBox(width: 4),
        moveButton(icon: Icons.keyboard_arrow_right, dx: 1, dy: 0),
        const SizedBox(width: 4),
        moveButton(icon: Icons.keyboard_arrow_up, dx: 0, dy: -1),
        const SizedBox(width: 4),
        moveButton(icon: Icons.keyboard_arrow_down, dx: 0, dy: 1),
      ],
    );

    return _buildHorizontalScrollableButtonRow(
      controller: _toolsScrollController,
      child: toolsRow,
    );
  }

  Widget _buildCanvas(List<Color> palette, {required bool showLockButton}) {
    final mediaHeight = MediaQuery.of(context).size.height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = mediaHeight * 0.55;
        final availableCanvasWidth = math.max(
          1.0,
          maxWidth - _canvasRulerExtent,
        );
        final availableCanvasHeight = math.max(
          1.0,
          maxHeight - _canvasRulerExtent,
        );
        final canvasWidth = math.min(
          availableCanvasWidth,
          availableCanvasHeight * _width / _height,
        );
        final canvasHeight = canvasWidth * _height / _width;
        final canvasSize = Size(canvasWidth, canvasHeight);
        final totalSize = Size(
          canvasWidth + _canvasRulerExtent,
          canvasHeight + _canvasRulerExtent,
        );
        final canvasOffset = const Offset(
          _canvasRulerExtent,
          _canvasRulerExtent,
        );
        final canDraw = !showLockButton || _canvasInputLocked;

        return Center(
          child: SizedBox(
            width: totalSize.width,
            height: totalSize.height,
            child: Stack(
              children: [
                CustomPaint(
                  size: totalSize,
                  painter: _PixelCanvasPainter(
                    width: _width,
                    height: _height,
                    pixels: _pixels,
                    profile: _paletteProfile,
                    palette: palette,
                    transparentColor: _supportsAlphaTransparency
                        ? _transparentColor
                        : null,
                    showGrid: _showGrid,
                    showRuler: _showRuler,
                    canvasOffset: canvasOffset,
                    canvasSize: canvasSize,
                    rulerExtent: _canvasRulerExtent,
                    lineStartIndex: _selectedTool == _CanvasTool.line
                        ? _lineStartIndex
                        : null,
                    ovalPointIndices: _selectedTool == _CanvasTool.oval
                        ? <int>[?_ovalFirstIndex, ?_ovalSecondIndex]
                        : const <int>[],
                    rectanglePointIndices:
                        _selectedTool == _CanvasTool.rectangle
                        ? <int>[?_rectangleFirstIndex, ?_rectangleSecondIndex]
                        : const <int>[],
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  width: totalSize.width,
                  height: _canvasRulerExtent,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _cancelPendingShape,
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: _canvasRulerExtent,
                  width: _canvasRulerExtent,
                  height: canvasHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _cancelPendingShape,
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  left: _canvasRulerExtent,
                  top: _canvasRulerExtent,
                  width: canvasSize.width,
                  height: canvasSize.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanDown: canDraw
                        ? (details) {
                            _isDrawing = true;
                            _applyToolAt(details.localPosition, canvasSize);
                          }
                        : null,
                    onPanUpdate: canDraw
                        ? (details) {
                            if (_selectedTool == _CanvasTool.pencil) {
                              _applyToolAt(details.localPosition, canvasSize);
                            }
                          }
                        : null,
                    onPanEnd: canDraw ? (_) => _finishDrawing() : null,
                    onPanCancel: canDraw ? _finishDrawing : null,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPayloadInfo(
    BuildContext context, {
    required bool showLockButton,
  }) {
    final isOverLimit = _currentPayloadChars > _effectivePayloadLimit;
    final mediaHeight = MediaQuery.of(context).size.height;
    final colorScheme = Theme.of(context).colorScheme;
    final currentEncodedCandidate = _currentEncodedCandidate;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = mediaHeight * 0.55;
        final contentWidth = math.min(maxWidth, maxHeight * _width / _height);

        return Center(
          child: SizedBox(
            width: contentWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (currentEncodedCandidate != null) ...[
                  Text(
                    _encodingCandidateLabel(currentEncodedCandidate),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Row(
                  children: [
                    if (showLockButton) ...[
                      IconButton.filled(
                        onPressed: () {
                          _finishDrawing();
                          setState(
                            () => _canvasInputLocked = !_canvasInputLocked,
                          );
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
                    ],
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          context.l10n.chat_canvasCurrentPayload(
                            _currentPayloadChars,
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: isOverLimit ? colorScheme.error : null,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _pixelsEqual(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  _CanvasSnapshot _captureCanvasSnapshot({
    int? width,
    int? height,
    PaletteProfile? paletteProfile,
    PaletteProfile? dynamicPaletteProfile,
    MCOImageEncodingVersion? encodingVersion,
    int? selectedColor,
    Object? transparentColor = _transparentColorUnchanged,
    List<int>? pixels,
  }) {
    return _CanvasSnapshot(
      width: width ?? _width,
      height: height ?? _height,
      paletteProfile: paletteProfile ?? _paletteProfile,
      dynamicPaletteProfile: dynamicPaletteProfile ?? _dynamicPaletteProfile,
      encodingVersion: encodingVersion ?? _encodingVersion,
      selectedColor: selectedColor ?? _selectedColor,
      transparentColor: identical(transparentColor, _transparentColorUnchanged)
          ? _transparentColor
          : transparentColor as int?,
      pixels: pixels ?? _pixels,
    );
  }

  bool _snapshotsEqual(_CanvasSnapshot a, _CanvasSnapshot b) {
    return a.width == b.width &&
        a.height == b.height &&
        a.paletteProfile == b.paletteProfile &&
        a.dynamicPaletteProfile == b.dynamicPaletteProfile &&
        a.encodingVersion == b.encodingVersion &&
        a.selectedColor == b.selectedColor &&
        a.transparentColor == b.transparentColor &&
        _pixelsEqual(a.pixels, b.pixels);
  }

  void _applyCanvasSnapshot(_CanvasSnapshot snapshot) {
    setState(() {
      _width = snapshot.width;
      _height = snapshot.height;
      _paletteProfile = snapshot.paletteProfile;
      _dynamicPaletteProfile = snapshot.dynamicPaletteProfile;
      _encodingVersion = snapshot.encodingVersion;
      _selectedColor = snapshot.selectedColor;
      _transparentColor = snapshot.transparentColor;
      _isPickingTransparentColor = false;
      _pixels = List<int>.of(snapshot.pixels);
      _setControllerValue(_widthController, _width);
      _setControllerValue(_heightController, _height);
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
    });
  }

  void _rememberCanvasAction(_CanvasSnapshot before, _CanvasSnapshot after) {
    if (_snapshotsEqual(before, after)) return;
    _undoStack.add(_CanvasHistoryEntry(before: before, after: after));
    if (_undoStack.length > _historyLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _rememberPixelCanvasAction(List<int> before, List<int> after) {
    _rememberCanvasAction(
      _captureCanvasSnapshot(pixels: before),
      _captureCanvasSnapshot(pixels: after),
    );
  }

  void _undoCanvasAction() {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    _redoStack.add(entry);
    if (_redoStack.length > _historyLimit) {
      _redoStack.removeAt(0);
    }
    _applyCanvasSnapshot(entry.before);
    _markPayloadDirty();
  }

  void _redoCanvasAction() {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();
    _undoStack.add(entry);
    if (_undoStack.length > _historyLimit) {
      _undoStack.removeAt(0);
    }
    _applyCanvasSnapshot(entry.after);
    _markPayloadDirty();
  }

  void _clearCanvasHistory() {
    _undoStack.clear();
    _redoStack.clear();
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

    final before = _captureCanvasSnapshot();
    final after = _captureCanvasSnapshot(
      width: newWidth,
      height: newHeight,
      pixels: nextPixels,
    );
    _rememberCanvasAction(before, after);
    setState(() {
      _width = newWidth;
      _height = newHeight;
      _pixels = nextPixels;
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
    });
    _markPayloadDirty();
  }

  void _resizeByCropping({required int width, required int height}) {
    if (width == _width && height == _height) return;
    final nextPixels = _cropOrPadPixels(
      sourcePixels: _pixels,
      sourceWidth: _width,
      sourceHeight: _height,
      targetWidth: width,
      targetHeight: height,
      fillColor: _whiteIndex,
    );

    final before = _captureCanvasSnapshot();
    final after = _captureCanvasSnapshot(
      width: width,
      height: height,
      pixels: nextPixels,
    );
    _rememberCanvasAction(before, after);
    setState(() {
      _width = width;
      _height = height;
      _pixels = nextPixels;
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
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
    return _scalePixels(
      sourcePixels: sourcePixels,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
  }

  List<int> _cropOrPadPixels({
    required List<int> sourcePixels,
    required int sourceWidth,
    required int sourceHeight,
    required int targetWidth,
    required int targetHeight,
    required int fillColor,
  }) {
    final nextPixels = List.filled(targetWidth * targetHeight, fillColor);
    final copyWidth = math.min(sourceWidth, targetWidth);
    final copyHeight = math.min(sourceHeight, targetHeight);
    final sourceStartX = math.max(0, (sourceWidth - targetWidth) ~/ 2);
    final sourceStartY = math.max(0, (sourceHeight - targetHeight) ~/ 2);
    final targetStartX = math.max(0, (targetWidth - sourceWidth) ~/ 2);
    final targetStartY = math.max(0, (targetHeight - sourceHeight) ~/ 2);
    for (var y = 0; y < copyHeight; y++) {
      for (var x = 0; x < copyWidth; x++) {
        nextPixels[(targetStartY + y) * targetWidth + targetStartX + x] =
            sourcePixels[(sourceStartY + y) * sourceWidth + sourceStartX + x];
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

  int _maxCanvasCellsForProfile(
    PaletteProfile profile, {
    MCOImageEncodingVersion? encodingVersion,
  }) {
    final multiplier =
        _master64CellBudgetMultiplier *
        _master64BitsPerCell /
        _paletteBitsPerCell(profile);
    final byCompressedBudget = (_effectivePayloadLimit * multiplier).floor();
    return math.max(
      _minCanvasSize * _minCanvasSize,
      math.min(
        _maxCanvasSizeForEncoding(encodingVersion ?? _encodingVersion) *
            _maxCanvasSizeForEncoding(encodingVersion ?? _encodingVersion),
        byCompressedBudget,
      ),
    );
  }

  int get _textPayloadLimit =>
      math.max(0, widget.maxTextChars - _humanReadablePrefixReserveChars);

  int get _effectivePayloadLimit =>
      widget.maxBinaryPayloadBytes ?? _textPayloadLimit;

  void _loadSavedCanvasSettings() {
    final prefs = PrefsManager.instance;
    final profileName = prefs.getString(_prefsPaletteKey);
    final profile = PaletteProfile.values.firstWhere(
      (value) => value.name == profileName,
      orElse: () => PaletteProfile.master64,
    );
    final requestedWidth = prefs.getInt(_prefsWidthKey) ?? _defaultSize;
    final requestedHeight = prefs.getInt(_prefsHeightKey) ?? _defaultSize;
    final unlockCanvasSize = prefs.getBool(_prefsUnlockSizeKey) ?? false;
    final bounded = _boundedCanvasSizeForProfile(
      requestedWidth,
      requestedHeight,
      profile,
      unlockAdaptiveLimit: unlockCanvasSize,
    );
    final width = bounded[0];
    final height = bounded[1];

    _paletteProfile = profile;
    _unlockCanvasSize = unlockCanvasSize;
    if (profile.isDynamic) {
      _dynamicPaletteProfile = profile;
    }
    _selectedColor = MCOImagePalette.blackIndexFor(profile);
    _width = width;
    _height = height;
    _setControllerValue(_widthController, width);
    _setControllerValue(_heightController, height);
    _pixels = List.filled(width * height, _whiteIndex);
    _currentPayloadChars = _calculatePayloadChars();
    _lastPayloadRefreshAt = DateTime.now();
  }

  void _loadInitialImage(MCOImage image) {
    // Reusing an existing message image should preserve its codec palette and
    // exact canvas dimensions instead of applying the user's last editor preset.
    _unlockCanvasSize =
        PrefsManager.instance.getBool(_prefsUnlockSizeKey) ?? false;
    _encodingVersion = image.encodingVersion;
    _paletteProfile = image.paletteProfile;
    if (image.paletteProfile.isDynamic) {
      _dynamicPaletteProfile = image.paletteProfile;
    }
    _selectedColor = MCOImagePalette.blackIndexFor(image.paletteProfile);
    _transparentColor = image.transparentColor;
    _width = image.width;
    _height = image.height;
    _setControllerValue(_widthController, _width);
    _setControllerValue(_heightController, _height);
    _pixels = List<int>.of(image.pixels);
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

  Future<void> _saveCanvasSizeUnlocked(bool value) async {
    await PrefsManager.instance.setBool(_prefsUnlockSizeKey, value);
  }

  bool get _supportsDynamicPalettes =>
      _encodingVersion == MCOImageEncodingVersion.v2;

  bool get _supportsAlphaTransparency =>
      _encodingVersion == MCOImageEncodingVersion.v2;

  int _maxCanvasSizeForEncoding(MCOImageEncodingVersion version) {
    return version == MCOImageEncodingVersion.v1Legacy
        ? _maxCanvasSizeV1
        : _maxCanvasSizeV2;
  }

  int get _maxCanvasSize => _maxCanvasSizeForEncoding(_encodingVersion);

  String _encodingVersionLabel(MCOImageEncodingVersion version) {
    return switch (version) {
      MCOImageEncodingVersion.v1Legacy => 'v1',
      MCOImageEncodingVersion.v2 => 'v2',
    };
  }

  void _changeEncodingVersion(MCOImageEncodingVersion version) {
    if (version == _encodingVersion) return;

    final before = _captureCanvasSnapshot();
    var nextProfile = _paletteProfile;
    var nextDynamicProfile = _dynamicPaletteProfile;
    var nextSelectedColor = _selectedColor;
    int? nextTransparentColor = _transparentColor;
    var mappedPixels = List<int>.of(_pixels);

    if (version == MCOImageEncodingVersion.v1Legacy) {
      nextTransparentColor = null;
    }

    if (version == MCOImageEncodingVersion.v1Legacy && nextProfile.isDynamic) {
      final oldProfile = _paletteProfile;
      nextProfile = PaletteProfile.master64;
      final newPalette = _paletteFor(nextProfile);

      int mapColor(int colorValue) {
        final argb = _colorForPixelValue(oldProfile, colorValue).toARGB32();
        return _nearestPaletteColorValue(
          (argb >> 16) & 0xff,
          (argb >> 8) & 0xff,
          argb & 0xff,
          (argb >> 24) & 0xff,
          nextProfile,
          newPalette,
          whiteIndex: MCOImagePalette.whiteIndexFor(nextProfile),
        );
      }

      nextSelectedColor = mapColor(_selectedColor);
      nextTransparentColor = nextTransparentColor == null
          ? null
          : mapColor(nextTransparentColor);
      mappedPixels = _pixels.map(mapColor).toList();
    } else if (nextProfile.isDynamic) {
      nextDynamicProfile = nextProfile;
    }

    final bounded = _boundedCanvasSizeForProfile(
      _width,
      _height,
      nextProfile,
      unlockAdaptiveLimit: _unlockCanvasSize,
      encodingVersion: version,
    );
    final nextWidth = bounded[0];
    final nextHeight = bounded[1];
    final nextPixels = _resizePixels(
      sourcePixels: mappedPixels,
      sourceWidth: _width,
      sourceHeight: _height,
      targetWidth: nextWidth,
      targetHeight: nextHeight,
      fillColor: MCOImagePalette.whiteIndexFor(nextProfile),
    );

    final after = _captureCanvasSnapshot(
      width: nextWidth,
      height: nextHeight,
      paletteProfile: nextProfile,
      dynamicPaletteProfile: nextDynamicProfile,
      encodingVersion: version,
      selectedColor: nextSelectedColor,
      transparentColor: nextTransparentColor,
      pixels: nextPixels,
    );
    _rememberCanvasAction(before, after);

    setState(() {
      _encodingVersion = version;
      _paletteProfile = nextProfile;
      _dynamicPaletteProfile = nextDynamicProfile;
      _selectedColor = nextSelectedColor;
      _transparentColor = nextTransparentColor;
      _isPickingTransparentColor = false;
      _width = nextWidth;
      _height = nextHeight;
      _setControllerValue(_widthController, nextWidth);
      _setControllerValue(_heightController, nextHeight);
      _pixels = nextPixels;
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
    });
    _markPayloadDirty();
    unawaited(_saveCanvasSize(nextWidth, nextHeight));
    unawaited(_saveCanvasPalette(nextProfile));
  }

  void _setCanvasSizeUnlocked(bool? value) {
    final unlocked = value ?? false;
    if (unlocked == _unlockCanvasSize) return;

    setState(() => _unlockCanvasSize = unlocked);
    unawaited(_saveCanvasSizeUnlocked(unlocked));

    if (!unlocked) {
      final size = _requestedBoundedCanvasSize();
      final width = size[0];
      final height = size[1];
      _setControllerValue(_widthController, width);
      _setControllerValue(_heightController, height);
      _resize(width: width, height: height);
      unawaited(_saveCanvasSize(width, height));
    }
  }

  void _trimEmptyCanvas() {
    final emptyColor = _whiteIndex;

    var minX = _width;
    var minY = _height;
    var maxX = -1;
    var maxY = -1;

    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        if (_pixels[y * _width + x] == emptyColor) continue;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }

    final targetWidth = maxX < minX
        ? _minCanvasSize
        : math.max(_minCanvasSize, maxX - minX + 1);
    final targetHeight = maxY < minY
        ? _minCanvasSize
        : math.max(_minCanvasSize, maxY - minY + 1);

    final nextPixels = List<int>.filled(targetWidth * targetHeight, emptyColor);

    if (maxX >= minX && maxY >= minY) {
      final copyWidth = maxX - minX + 1;
      final copyHeight = maxY - minY + 1;
      final targetStartX = math.max(0, (targetWidth - copyWidth) ~/ 2);
      final targetStartY = math.max(0, (targetHeight - copyHeight) ~/ 2);

      for (var y = 0; y < copyHeight; y++) {
        for (var x = 0; x < copyWidth; x++) {
          nextPixels[(targetStartY + y) * targetWidth + targetStartX + x] =
              _pixels[(minY + y) * _width + minX + x];
        }
      }
    }

    final before = _captureCanvasSnapshot();
    final after = _captureCanvasSnapshot(
      width: targetWidth,
      height: targetHeight,
      pixels: nextPixels,
    );
    _rememberCanvasAction(before, after);
    if (_snapshotsEqual(before, after)) return;

    setState(() {
      _width = targetWidth;
      _height = targetHeight;
      _setControllerValue(_widthController, targetWidth);
      _setControllerValue(_heightController, targetHeight);
      _pixels = nextPixels;
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
    });
    _markPayloadDirty();
    unawaited(_saveCanvasSize(targetWidth, targetHeight));
  }

  void _applyCanvasSize() {
    final size = _requestedBoundedCanvasResizeSize();
    final width = size[0];
    final height = size[1];

    _setControllerValue(_widthController, width);
    _setControllerValue(_heightController, height);
    _resize(width: width, height: height);
    unawaited(_saveCanvasSize(width, height));
  }

  void _cropCanvasSize() {
    final size = _requestedBoundedCanvasSize();
    final width = size[0];
    final height = size[1];

    _setControllerValue(_widthController, width);
    _setControllerValue(_heightController, height);
    _resizeByCropping(width: width, height: height);
    unawaited(_saveCanvasSize(width, height));
  }

  List<int> _requestedBoundedCanvasResizeSize() {
    final widthText = _widthController.text.trim();
    final heightText = _heightController.text.trim();
    final parsedWidth = int.tryParse(widthText);
    final parsedHeight = int.tryParse(heightText);

    final requestedWidth =
        parsedWidth ??
        (parsedHeight == null
            ? _width
            : math.max(
                _minCanvasSize,
                (parsedHeight * _width / _height).round(),
              ));
    final requestedHeight =
        parsedHeight ??
        (parsedWidth == null
            ? _height
            : math.max(
                _minCanvasSize,
                (parsedWidth * _height / _width).round(),
              ));

    return _boundedCanvasSizeForProfile(
      requestedWidth,
      requestedHeight,
      _paletteProfile,
      unlockAdaptiveLimit: _unlockCanvasSize,
    );
  }

  List<int> _requestedBoundedCanvasSize() {
    final requestedWidth = int.tryParse(_widthController.text) ?? _width;
    final requestedHeight = int.tryParse(_heightController.text) ?? _height;
    return _boundedCanvasSizeForProfile(
      requestedWidth,
      requestedHeight,
      _paletteProfile,
      unlockAdaptiveLimit: _unlockCanvasSize,
    );
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
    final encoded = _encodeCanvas();
    _currentEncodedCandidate = encoded;
    return _payloadSizeForEncoded(encoded);
  }

  String _encodingCandidateLabel(EncodedMCOImage candidate) {
    final parts = <String>[
      'v${candidate.codecVersion}',
      _encodingContainerLabel(candidate),
      'scan ${switch (candidate.scan) {
        ScanMode.h => 'H',
        ScanMode.v => 'V',
        ScanMode.s => 'serp H',
        ScanMode.sv => 'serp V',
      }}',
    ];
    if (candidate.boundsPresent) {
      parts.add(
        'bounds ${candidate.boundsWidth}x${candidate.boundsHeight} '
        '@ ${candidate.boundsX},${candidate.boundsY}',
      );
    }
    parts.add('codec ${candidate.byteLength} B / ${candidate.charLength} chars');
    final localPaletteSize = candidate.localPaletteSize;
    final bitsPerPixel = candidate.bitsPerLocalPixel;
    if (localPaletteSize != null && bitsPerPixel != null) {
      parts.add('local ${localPaletteSize}c/${bitsPerPixel}b');
    }
    final usedBankCount = candidate.usedBankCount;
    if (usedBankCount != null) parts.add('$usedBankCount banks');
    return parts.join(' | ');
  }

  String _encodingContainerLabel(EncodedMCOImage candidate) {
    return switch (candidate.container) {
      'regions' => 'Regions x${candidate.regionCount}',
      'solid-rects' => 'Solid rectangles',
      'compact-bounds' => 'Compact bounds',
      'compact-rle' => 'Compact RLE',
      'compact-rle-bounds' => 'Compact RLE bounds',
      'compact-sparse' => 'Compact sparse',
      'compact-sparse-bounds' => 'Compact sparse bounds',
      'lz-pixels' => 'LZ pixels',
      'lz-pixels-bounds' => 'LZ pixels bounds',
      'quadtree' => 'Quadtree',
      'quadtree-bounds' => 'Quadtree bounds',
      'bitplanes' => 'Bitplanes',
      'bitplanes-bounds' => 'Bitplanes bounds',
      'adaptive-bitplanes' => 'Adaptive bitplanes',
      'adaptive-bitplanes-bounds' => 'Adaptive bitplanes bounds',
      'adaptive-bitplanes-optimized' => 'Adaptive bitplanes optimized',
      'adaptive-bitplanes-optimized-bounds' =>
        'Adaptive bitplanes optimized bounds',
      'direct-grayscale-bitplanes' => 'Direct grayscale bitplanes',
      'direct-grayscale-bitplanes-bounds' =>
        'Direct grayscale bitplanes bounds',
      'compact-row-delta' => 'Compact row delta',
      'compact-row-delta-bounds' => 'Compact row delta bounds',
      'grayscale-row-delta' => 'Grayscale row delta',
      'grayscale-row-delta-bounds' => 'Grayscale row delta bounds',
      _ => switch (candidate.mode) {
        ImageMode.rawGlobal => 'Raw global',
        ImageMode.rawLocal => 'Raw local',
        ImageMode.rleLocal => 'RLE local',
        ImageMode.sparseBg => 'Sparse background',
        ImageMode.regionsBg => 'Regions x${candidate.regionCount}',
        ImageMode.biColorMask => 'Bi-color mask',
        ImageMode.rowDelta => 'Row delta',
        ImageMode.rowRepeat => 'Row repeat',
        ImageMode.extended => 'Extended',
      },
    };
  }

  int _payloadSizeForEncoded(EncodedMCOImage encoded) {
    final binaryLimit = widget.maxBinaryPayloadBytes;
    if (binaryLimit != null) {
      final payloadBytes = ChannelBinaryDataHelper.mcoImagePayloadLength(
        encoded.text,
        widget.binarySenderName ?? 'Me',
      );
      if (payloadBytes != null) return payloadBytes;
    }
    return encoded.charLength;
  }

  List<int> _boundedCanvasSizeForProfile(
    int requestedWidth,
    int requestedHeight,
    PaletteProfile profile, {
    bool unlockAdaptiveLimit = false,
    MCOImageEncodingVersion? encodingVersion,
  }) {
    final maxCanvasSize = _maxCanvasSizeForEncoding(
      encodingVersion ?? _encodingVersion,
    );
    var width = requestedWidth.clamp(_minCanvasSize, maxCanvasSize).toInt();
    var height = requestedHeight.clamp(_minCanvasSize, maxCanvasSize).toInt();

    if (unlockAdaptiveLimit) {
      return [width, height];
    }

    final maxCanvasCells = _maxCanvasCellsForProfile(
      profile,
      encodingVersion: encodingVersion,
    );
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
    if (!_supportsDynamicPalettes && profile.isDynamic) return;
    if (profile == _paletteProfile) return;
    final oldProfile = _paletteProfile;
    final newPalette = _paletteFor(profile);

    int mapColor(int colorValue) {
      final argb = _colorForPixelValue(oldProfile, colorValue).toARGB32();
      return _nearestPaletteColorValue(
        (argb >> 16) & 0xff,
        (argb >> 8) & 0xff,
        argb & 0xff,
        (argb >> 24) & 0xff,
        profile,
        newPalette,
        whiteIndex: MCOImagePalette.whiteIndexFor(profile),
      );
    }

    final nextSelectedColor = mapColor(_selectedColor);
    final nextTransparentColor = _transparentColor == null
        ? null
        : mapColor(_transparentColor!);
    final mappedPixels = _pixels.map(mapColor).toList();
    final bounded = _boundedCanvasSizeForProfile(
      _width,
      _height,
      profile,
      unlockAdaptiveLimit: _unlockCanvasSize,
    );
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
    final before = _captureCanvasSnapshot();
    final nextDynamicProfile = profile.isDynamic
        ? profile
        : _dynamicPaletteProfile;
    final after = _captureCanvasSnapshot(
      width: nextWidth,
      height: nextHeight,
      paletteProfile: profile,
      dynamicPaletteProfile: nextDynamicProfile,
      selectedColor: nextSelectedColor,
      transparentColor: nextTransparentColor,
      pixels: nextPixels,
    );
    _rememberCanvasAction(before, after);
    setState(() {
      _paletteProfile = profile;
      if (profile.isDynamic) {
        _dynamicPaletteProfile = profile;
      }
      _selectedColor = nextSelectedColor;
      _transparentColor = nextTransparentColor;
      _isPickingTransparentColor = false;
      _width = nextWidth;
      _height = nextHeight;
      _setControllerValue(_widthController, nextWidth);
      _setControllerValue(_heightController, nextHeight);
      _pixels = nextPixels;
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
    });
    _markPayloadDirty();
    unawaited(_saveCanvasPalette(profile));
  }

  void _cancelPendingShape() {
    if (_lineStartIndex == null &&
        _ovalFirstIndex == null &&
        _ovalSecondIndex == null &&
        _rectangleFirstIndex == null &&
        _rectangleSecondIndex == null) {
      return;
    }
    setState(() {
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
    });
  }

  void _applyToolAt(Offset position, Size size) {
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx >= size.width ||
        position.dy >= size.height) {
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
      case _CanvasTool.line:
        _handleLineTool(index);
        break;
      case _CanvasTool.oval:
        _handleOvalTool(index);
        break;
      case _CanvasTool.rectangle:
        _handleRectangleTool(index);
        break;
    }
  }

  void _paintPixel(int index) {
    if (_pixels[index] == _selectedColor) return;
    final beforePixels = List<int>.of(_pixels);
    final nextPixels = List<int>.of(_pixels);
    nextPixels[index] = _selectedColor;
    _rememberPixelCanvasAction(beforePixels, nextPixels);
    setState(() => _pixels = nextPixels);
    _markPayloadDirty();
  }

  void _pickColor(int index) {
    final color = _pixels[index];
    setState(() {
      _selectedColor = color;
      // Eyedropper is a one-shot tool: after picking, continue drawing.
      _selectedTool = _CanvasTool.pencil;
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
    });
  }

  void _handleLineTool(int index) {
    final startIndex = _lineStartIndex;
    if (startIndex == null) {
      setState(() => _lineStartIndex = index);
      return;
    }

    if (startIndex == index) {
      setState(() => _lineStartIndex = null);
      return;
    }

    _drawLine(startIndex, index);
  }

  void _drawLine(int startIndex, int endIndex) {
    final startX = startIndex % _width;
    final startY = startIndex ~/ _width;
    final endX = endIndex % _width;
    final endY = endIndex ~/ _width;
    final beforePixels = List<int>.of(_pixels);
    final nextPixels = List<int>.of(_pixels);

    var x0 = startX;
    var y0 = startY;
    final dx = (endX - startX).abs();
    final dy = (endY - startY).abs();
    final sx = startX < endX ? 1 : -1;
    final sy = startY < endY ? 1 : -1;
    var err = dx - dy;
    var changed = false;

    while (true) {
      final pixelIndex = y0 * _width + x0;
      if (nextPixels[pixelIndex] != _selectedColor) {
        nextPixels[pixelIndex] = _selectedColor;
        changed = true;
      }

      if (x0 == endX && y0 == endY) break;

      final e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        x0 += sx;
      }
      if (e2 < dx) {
        err += dx;
        y0 += sy;
      }
    }

    if (changed) {
      _rememberPixelCanvasAction(beforePixels, nextPixels);
    }
    setState(() {
      _pixels = nextPixels;
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
    });
    if (changed) {
      _markPayloadDirty();
    }
  }

  void _handleOvalTool(int index) {
    final firstIndex = _ovalFirstIndex;
    final secondIndex = _ovalSecondIndex;
    if (firstIndex == null) {
      setState(() => _ovalFirstIndex = index);
      return;
    }
    if (secondIndex == null) {
      if (firstIndex == index) {
        setState(() => _ovalFirstIndex = null);
        return;
      }
      setState(() => _ovalSecondIndex = index);
      return;
    }

    if (index == firstIndex || index == secondIndex) {
      setState(() {
        _ovalFirstIndex = null;
        _ovalSecondIndex = null;
        _rectangleFirstIndex = null;
        _rectangleSecondIndex = null;
      });
      return;
    }

    _drawOval(firstIndex, secondIndex, index);
  }

  void _drawOval(int firstIndex, int secondIndex, int widthIndex) {
    final x1 = (firstIndex % _width).toDouble();
    final y1 = (firstIndex ~/ _width).toDouble();
    final x2 = (secondIndex % _width).toDouble();
    final y2 = (secondIndex ~/ _width).toDouble();
    final x3 = (widthIndex % _width).toDouble();
    final y3 = (widthIndex ~/ _width).toDouble();

    final centerX = (x1 + x2) / 2.0;
    final centerY = (y1 + y2) / 2.0;
    final axisDx = x2 - x1;
    final axisDy = y2 - y1;
    final axisLength = math.sqrt(axisDx * axisDx + axisDy * axisDy);
    if (axisLength == 0) {
      setState(() {
        _ovalFirstIndex = null;
        _ovalSecondIndex = null;
        _rectangleFirstIndex = null;
        _rectangleSecondIndex = null;
      });
      return;
    }

    final ux = axisDx / axisLength;
    final uy = axisDy / axisLength;
    final vx = -uy;
    final vy = ux;
    final semiMajor = axisLength / 2.0;
    final relX = x3 - centerX;
    final relY = y3 - centerY;
    final semiMinor = (relX * vx + relY * vy).abs();

    final beforePixels = List<int>.of(_pixels);
    final nextPixels = List<int>.of(_pixels);
    var changed = false;

    void plotLineBetweenPoints(int fromX, int fromY, int toX, int toY) {
      var px = fromX;
      var py = fromY;
      final dx = (toX - fromX).abs();
      final dy = (toY - fromY).abs();
      final sx = fromX < toX ? 1 : -1;
      final sy = fromY < toY ? 1 : -1;
      var err = dx - dy;
      while (true) {
        if (px >= 0 && px < _width && py >= 0 && py < _height) {
          final pixelIndex = py * _width + px;
          if (nextPixels[pixelIndex] != _selectedColor) {
            nextPixels[pixelIndex] = _selectedColor;
            changed = true;
          }
        }
        if (px == toX && py == toY) break;
        final e2 = 2 * err;
        if (e2 > -dy) {
          err -= dy;
          px += sx;
        }
        if (e2 < dx) {
          err += dx;
          py += sy;
        }
      }
    }

    if (semiMinor < 0.5) {
      plotLineBetweenPoints(x1.round(), y1.round(), x2.round(), y2.round());
    } else {
      final steps = math.max(
        24,
        (2 * math.pi * math.max(semiMajor, semiMinor) * 4).ceil(),
      );
      int? prevX;
      int? prevY;
      for (var i = 0; i <= steps; i++) {
        final t = 2 * math.pi * i / steps;
        final cosT = math.cos(t);
        final sinT = math.sin(t);
        final sampleX = centerX + ux * semiMajor * cosT + vx * semiMinor * sinT;
        final sampleY = centerY + uy * semiMajor * cosT + vy * semiMinor * sinT;
        final roundedX = sampleX.round();
        final roundedY = sampleY.round();
        if (prevX != null && prevY != null) {
          plotLineBetweenPoints(prevX, prevY, roundedX, roundedY);
        }
        prevX = roundedX;
        prevY = roundedY;
      }
    }

    if (changed) {
      _rememberPixelCanvasAction(beforePixels, nextPixels);
    }
    setState(() {
      _pixels = nextPixels;
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
    });
    if (changed) {
      _markPayloadDirty();
    }
  }

  void _handleRectangleTool(int index) {
    final firstIndex = _rectangleFirstIndex;
    final secondIndex = _rectangleSecondIndex;
    if (firstIndex == null) {
      setState(() => _rectangleFirstIndex = index);
      return;
    }
    if (secondIndex == null) {
      if (firstIndex == index) {
        setState(() => _rectangleFirstIndex = null);
        return;
      }
      setState(() => _rectangleSecondIndex = index);
      return;
    }

    if (index == firstIndex || index == secondIndex) {
      setState(() {
        _rectangleFirstIndex = null;
        _rectangleSecondIndex = null;
      });
      return;
    }

    _drawRectangle(firstIndex, secondIndex, index);
  }

  void _drawRectangle(int firstIndex, int diagonalIndex, int thirdIndex) {
    final ax = firstIndex % _width;
    final ay = firstIndex ~/ _width;
    final cx = diagonalIndex % _width;
    final cy = diagonalIndex ~/ _width;
    final bx = thirdIndex % _width;
    final by = thirdIndex ~/ _width;
    final dx = ax + cx - bx;
    final dy = ay + cy - by;

    final beforePixels = List<int>.of(_pixels);
    final nextPixels = List<int>.of(_pixels);
    var changed = false;

    void plotLineBetweenPoints(int fromX, int fromY, int toX, int toY) {
      var px = fromX;
      var py = fromY;
      final lineDx = (toX - fromX).abs();
      final lineDy = (toY - fromY).abs();
      final sx = fromX < toX ? 1 : -1;
      final sy = fromY < toY ? 1 : -1;
      var err = lineDx - lineDy;

      while (true) {
        if (px >= 0 && px < _width && py >= 0 && py < _height) {
          final pixelIndex = py * _width + px;
          if (nextPixels[pixelIndex] != _selectedColor) {
            nextPixels[pixelIndex] = _selectedColor;
            changed = true;
          }
        }

        if (px == toX && py == toY) break;

        final e2 = 2 * err;
        if (e2 > -lineDy) {
          err -= lineDy;
          px += sx;
        }
        if (e2 < lineDx) {
          err += lineDx;
          py += sy;
        }
      }
    }

    plotLineBetweenPoints(ax, ay, bx, by);
    plotLineBetweenPoints(bx, by, cx, cy);
    plotLineBetweenPoints(cx, cy, dx, dy);
    plotLineBetweenPoints(dx, dy, ax, ay);

    if (changed) {
      _rememberPixelCanvasAction(beforePixels, nextPixels);
    }
    setState(() {
      _pixels = nextPixels;
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
    });
    if (changed) {
      _markPayloadDirty();
    }
  }

  void _fillArea(int startIndex) {
    final targetColor = _pixels[startIndex];
    if (targetColor == _selectedColor) return;

    final beforePixels = List<int>.of(_pixels);
    final nextPixels = List<int>.of(_pixels);
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

    _rememberPixelCanvasAction(beforePixels, nextPixels);
    setState(() {
      _pixels = nextPixels;
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
    });
    _markPayloadDirty();
  }

  void _shiftCanvas({required int dx, required int dy}) {
    _finishDrawing();
    final nextPixels = List<int>.filled(_width * _height, _whiteIndex);
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        final nextX = x + dx;
        final nextY = y + dy;
        if (nextX < 0 || nextY < 0 || nextX >= _width || nextY >= _height) {
          continue;
        }
        nextPixels[nextY * _width + nextX] = _pixels[y * _width + x];
      }
    }

    _clearCanvasHistory();
    setState(() {
      _pixels = nextPixels;
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
    });
    _markPayloadDirty();
  }

  void _clearCanvas() {
    _clearCanvasHistory();
    setState(() {
      _pixels = List.filled(_width * _height, _whiteIndex);
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
    });
    _markPayloadDirty();
  }

  Future<void> _loadCanvasFromFile() async {
    try {
      final file = await file_selector.openFile(
        acceptedTypeGroups: const [
          file_selector.XTypeGroup(
            label: 'MCO image binary',
            extensions: ['bin'],
            mimeTypes: ['application/octet-stream'],
            uniformTypeIdentifiers: ['public.data'],
          ),
          file_selector.XTypeGroup(
            label: 'Images',
            extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
            mimeTypes: ['image/png', 'image/jpeg', 'image/webp', 'image/bmp'],
            uniformTypeIdentifiers: ['public.image'],
          ),
        ],
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (file.name.toLowerCase().endsWith('.mcoimg.bin')) {
        final image = _codec.decode(MCOImageCodec.textFromBinaryPayload(bytes));
        if (!mounted) return;
        _clearCanvasHistory();
        setState(() {
          _loadInitialImage(image);
          _lineStartIndex = null;
          _ovalFirstIndex = null;
          _ovalSecondIndex = null;
          _rectangleFirstIndex = null;
          _rectangleSecondIndex = null;
        });
        _markPayloadDirty();
        unawaited(_saveCanvasPalette(image.paletteProfile));
        unawaited(_saveCanvasSize(image.width, image.height));
        return;
      }

      final importedImage = await _imageBytesToCanvasPixels(bytes);
      if (!mounted) return;
      _setControllerValue(_widthController, importedImage.width);
      _setControllerValue(_heightController, importedImage.height);
      setState(() {
        _width = importedImage.width;
        _height = importedImage.height;
        _pixels = importedImage.pixels;
        _lineStartIndex = null;
        _ovalFirstIndex = null;
        _ovalSecondIndex = null;
        _rectangleFirstIndex = null;
        _rectangleSecondIndex = null;
      });
      _markPayloadDirty();
      unawaited(_saveCanvasSize(importedImage.width, importedImage.height));
    } catch (error) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(error.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<_ImportedCanvasImage> _imageBytesToCanvasPixels(
    Uint8List bytes,
  ) async {
    final source = await _decodeImage(bytes);
    final sourceWidth = source.width;
    final sourceHeight = source.height;
    source.dispose();

    final canvasWidth = _unlockCanvasSize
        ? math.max(_minCanvasSize, math.min(_maxCanvasSize, sourceWidth))
        : _width;
    final canvasHeight = _unlockCanvasSize
        ? math.max(_minCanvasSize, math.min(_maxCanvasSize, sourceHeight))
        : _height;
    final scale = math.min(
      canvasWidth / sourceWidth,
      canvasHeight / sourceHeight,
    );
    final targetWidth = math.max(
      1,
      math.min(canvasWidth, (sourceWidth * scale).floor()),
    );
    final targetHeight = math.max(
      1,
      math.min(canvasHeight, (sourceHeight * scale).floor()),
    );

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
    final importedPixels = <int>[];
    final importedColorCounts = <int, int>{};
    for (var y = 0; y < targetHeight; y++) {
      for (var x = 0; x < targetWidth; x++) {
        final offset = (y * targetWidth + x) * 4;
        final colorValue = _nearestPaletteColorValue(
          rgba.getUint8(offset),
          rgba.getUint8(offset + 1),
          rgba.getUint8(offset + 2),
          rgba.getUint8(offset + 3),
          _paletteProfile,
          palette,
          whiteIndex: _whiteIndex,
        );
        importedPixels.add(colorValue);
        importedColorCounts[colorValue] =
            (importedColorCounts[colorValue] ?? 0) + 1;
      }
    }

    final optimizedPixels = _paletteProfile.isDynamic
        ? _limitDynamicImportedColors(
            importedPixels,
            importedColorCounts,
            _paletteProfile,
          )
        : importedPixels;

    final nextPixels = List.filled(canvasWidth * canvasHeight, _whiteIndex);
    final startX = (canvasWidth - targetWidth) ~/ 2;
    final startY = (canvasHeight - targetHeight) ~/ 2;
    for (var y = 0; y < targetHeight; y++) {
      for (var x = 0; x < targetWidth; x++) {
        nextPixels[(startY + y) * canvasWidth + startX + x] =
            optimizedPixels[y * targetWidth + x];
      }
    }
    return _ImportedCanvasImage(
      width: canvasWidth,
      height: canvasHeight,
      pixels: nextPixels,
    );
  }

  List<int> _limitDynamicImportedColors(
    List<int> pixels,
    Map<int, int> colorCounts,
    PaletteProfile profile,
  ) {
    if (colorCounts.length <= _inlineDynamicPaletteMaxColors) {
      return pixels;
    }

    final selectedColors = colorCounts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) return countCompare;
        final aIndex = _paletteIndexForColorValue(profile, a.key) ?? 0;
        final bIndex = _paletteIndexForColorValue(profile, b.key) ?? 0;
        return aIndex.compareTo(bIndex);
      });

    final limitedColors = selectedColors
        .take(_inlineDynamicPaletteMaxColors)
        .map((entry) => entry.key)
        .toList(growable: false);
    final limitedColorSet = limitedColors.toSet();

    return pixels
        .map((colorValue) {
          if (limitedColorSet.contains(colorValue)) return colorValue;
          return _nearestColorValueFromCandidates(colorValue, limitedColors);
        })
        .toList(growable: false);
  }

  int _nearestColorValueFromCandidates(
    int colorValue,
    List<int> candidateColorValues,
  ) {
    final sourceColor = MCOImageDynamicPalette.global512[colorValue];
    final sourceArgb = sourceColor.toARGB32();
    final sourceRed = (sourceArgb >> 16) & 0xff;
    final sourceGreen = (sourceArgb >> 8) & 0xff;
    final sourceBlue = sourceArgb & 0xff;

    var bestColorValue = candidateColorValues.first;
    var bestDistance = 1 << 62;
    for (final candidateColorValue in candidateColorValues) {
      final candidateColor =
          MCOImageDynamicPalette.global512[candidateColorValue];
      final candidateArgb = candidateColor.toARGB32();
      final redDistance = sourceRed - ((candidateArgb >> 16) & 0xff);
      final greenDistance = sourceGreen - ((candidateArgb >> 8) & 0xff);
      final blueDistance = sourceBlue - (candidateArgb & 0xff);
      final distance =
          redDistance * redDistance +
          greenDistance * greenDistance +
          blueDistance * blueDistance;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestColorValue = candidateColorValue;
      }
    }
    return bestColorValue;
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

  int _nearestPaletteColorValue(
    int red,
    int green,
    int blue,
    int alpha,
    PaletteProfile profile,
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
    return _paletteColorValueAtIndex(profile, bestIndex);
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
            uniformTypeIdentifiers: ['public.png'],
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

  Future<void> _saveCanvasToBinary() async {
    try {
      // Store the raw MCOimg payload, not the channel B0 transport envelope,
      // so the file can be imported back into the editor directly.
      final encoded = _encodeCanvas();
      await MCOImageFileSaver.saveBinaryPayloadFromText(encoded.text);
    } catch (error) {
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
    final rgba = Uint8List(_width * _height * 4);
    for (var i = 0; i < _pixels.length; i++) {
      final color = _colorForPixelValue(_paletteProfile, _pixels[i]);
      final argb = color.toARGB32();
      final offset = i * 4;
      rgba[offset] = (argb >> 16) & 0xff;
      rgba[offset + 1] = (argb >> 8) & 0xff;
      rgba[offset + 2] = argb & 0xff;
      rgba[offset +
          3] = _supportsAlphaTransparency && _pixels[i] == _transparentColor
          ? 0
          : (argb >> 24) & 0xff;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      _width,
      _height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );

    final image = await completer.future;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) {
      throw const MCOImageInvalidInputException('Cannot render PNG');
    }
    return png.buffer.asUint8List();
  }

  void _sendCanvas() {
    try {
      final encoded = _encodeCanvas();
      _currentEncodedCandidate = encoded;
      final payloadSize = _payloadSizeForEncoded(encoded);
      _currentPayloadChars = payloadSize;
      final overflow = payloadSize - _effectivePayloadLimit;
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

  EncodedMCOImage _encodeCanvas() {
    return _codec.encode(
      MCOImage(
        width: _width,
        height: _height,
        paletteProfile: _paletteProfile,
        pixels: _pixels,
        transparentColor: _supportsAlphaTransparency ? _transparentColor : null,
        encodingVersion: _encodingVersion,
      ),
      backgroundColor: _supportsAlphaTransparency
          ? (_transparentColor ?? _whiteIndex)
          : _whiteIndex,
      encodingVersion: _encodingVersion,
      outputTarget: widget.maxBinaryPayloadBytes != null
          ? MCOImageOutputTarget.binary
          : MCOImageOutputTarget.text,
    );
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
      PaletteProfile.dynamicGlobal8 => 'Dynamic Global 8',
      PaletteProfile.dynamicGlobal16 => 'Dynamic Global 16',
      PaletteProfile.dynamicGlobal32 => 'Dynamic Global 32',
      PaletteProfile.dynamicGlobal64 => 'Dynamic Global 64',
      PaletteProfile.dynamicGlobal128 => 'Dynamic Global 128',
      PaletteProfile.dynamicGlobal256 => 'Dynamic Global 256',
      PaletteProfile.dynamicGlobal512 => 'Dynamic Global 512',
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
      PaletteProfile.dynamicGlobal8 => 3,
      PaletteProfile.dynamicGlobal16 => 4,
      PaletteProfile.dynamicGlobal32 => 5,
      PaletteProfile.dynamicGlobal64 => 6,
      PaletteProfile.dynamicGlobal128 => 7,
      PaletteProfile.dynamicGlobal256 => 8,
      PaletteProfile.dynamicGlobal512 => 9,
    };
  }

  List<Color> _paletteFor(PaletteProfile profile) {
    return MCOImagePalette.colorsFor(profile);
  }

  int get _whiteIndex => MCOImagePalette.whiteIndexFor(_paletteProfile);

  int _paletteColorValueAtIndex(PaletteProfile profile, int paletteIndex) {
    if (profile.isDynamic) {
      return MCOImageDynamicPalette.globalIndexForProfileColorId(
        profile,
        paletteIndex,
      );
    }
    return paletteIndex;
  }

  int? _paletteIndexForColorValue(PaletteProfile profile, int colorValue) {
    if (profile.isDynamic) {
      return MCOImageDynamicPalette.profileColorIdForGlobalIndex(
        profile,
        colorValue,
      );
    }
    final paletteLength = _paletteFor(profile).length;
    if (colorValue < 0 || colorValue >= paletteLength) return null;
    return colorValue;
  }

  Color _colorForPixelValue(PaletteProfile profile, int colorValue) {
    if (profile.isDynamic) {
      if (colorValue < 0 ||
          colorValue >= MCOImageDynamicPalette.global512.length ||
          _paletteIndexForColorValue(profile, colorValue) == null) {
        return _colorForPixelValue(
          profile,
          MCOImagePalette.whiteIndexFor(profile),
        );
      }
      return MCOImageDynamicPalette.global512[colorValue];
    }
    final palette = _paletteFor(profile);
    if (colorValue < 0 || colorValue >= palette.length) {
      return palette[MCOImagePalette.whiteIndexFor(profile)];
    }
    return palette[colorValue];
  }

  List<int> _usedColorValuesForProfile(PaletteProfile profile) {
    final values = <int>{};
    for (final colorValue in _pixels) {
      if (_paletteIndexForColorValue(profile, colorValue) != null) {
        values.add(colorValue);
      }
    }
    final sorted = values.toList()
      ..sort((a, b) {
        final aIndex = _paletteIndexForColorValue(profile, a) ?? 0;
        final bIndex = _paletteIndexForColorValue(profile, b) ?? 0;
        return aIndex.compareTo(bIndex);
      });
    return sorted;
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

class _AlphaSwatch extends StatelessWidget {
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const _AlphaSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).dividerColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: CustomPaint(
        size: const Size(28, 28),
        painter: _AlphaSwatchPainter(
          color: color,
          borderColor: borderColor,
          selected: selected,
        ),
      ),
    );
  }
}

class _AlphaSwatchPainter extends CustomPainter {
  final Color? color;
  final Color borderColor;
  final bool selected;

  const _AlphaSwatchPainter({
    required this.color,
    required this.borderColor,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = BorderRadius.circular(4).toRRect(rect);
    canvas.save();
    canvas.clipRRect(radius);

    if (color == null) {
      final paints = [
        Paint()..color = const Color(0xffffffff),
        Paint()..color = const Color(0xffd6d6d6),
      ];
      final halfWidth = size.width / 2;
      final halfHeight = size.height / 2;
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 2; x++) {
          canvas.drawRect(
            Rect.fromLTWH(x * halfWidth, y * halfHeight, halfWidth, halfHeight),
            paints[(x + y) & 1],
          );
        }
      }
    } else {
      canvas.drawRect(rect, Paint()..color = color!);
    }

    canvas.restore();

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 3 : 1
      ..isAntiAlias = false;
    canvas.drawRRect(radius, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _AlphaSwatchPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.selected != selected;
  }
}

class _PixelCanvasPainter extends CustomPainter {
  static const Color _gridColor = Color(0xff00ff00);
  static const Color _lineStartColor = Color(0xffff9800);
  static const Color _ovalPointColor = Color(0xff03a9f4);
  static const Color _rectanglePointColor = Color(0xff9c27b0);
  static const Color _rulerColor = Color(0xff808080);

  final int width;
  final int height;
  final List<int> pixels;
  final PaletteProfile profile;
  final List<Color> palette;
  final int? transparentColor;
  final bool showGrid;
  final bool showRuler;
  final Offset canvasOffset;
  final Size canvasSize;
  final double rulerExtent;
  final int? lineStartIndex;
  final List<int> ovalPointIndices;
  final List<int> rectanglePointIndices;

  const _PixelCanvasPainter({
    required this.width,
    required this.height,
    required this.pixels,
    required this.profile,
    required this.palette,
    required this.transparentColor,
    required this.showGrid,
    required this.showRuler,
    required this.canvasOffset,
    required this.canvasSize,
    required this.rulerExtent,
    this.lineStartIndex,
    this.ovalPointIndices = const <int>[],
    this.rectanglePointIndices = const <int>[],
  });

  void _paintCheckerboard(Canvas canvas, Rect rect, {double cellSize = 8}) {
    final lightPaint = Paint()
      ..color = const Color(0xffffffff)
      ..isAntiAlias = false;
    final darkPaint = Paint()
      ..color = const Color(0xffd6d6d6)
      ..isAntiAlias = false;

    canvas.drawRect(rect, lightPaint);
    for (var y = rect.top; y < rect.bottom; y += cellSize) {
      for (var x = rect.left; x < rect.right; x += cellSize) {
        final column = ((x - rect.left) / cellSize).floor();
        final row = ((y - rect.top) / cellSize).floor();
        if ((column + row).isEven) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            x,
            y,
            math.min(cellSize, rect.right - x),
            math.min(cellSize, rect.bottom - y),
          ),
          darkPaint,
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = canvasSize.width / width;
    final cellHeight = canvasSize.height / height;
    final paint = Paint()..isAntiAlias = false;
    final canvasRect = Rect.fromLTWH(
      canvasOffset.dx,
      canvasOffset.dy,
      canvasSize.width,
      canvasSize.height,
    );
    if (transparentColor != null) {
      _paintCheckerboard(canvas, canvasRect);
    }

    if (showRuler) {
      _paintRulerLabels(canvas, cellWidth, cellHeight);
    }

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final colorValue = pixels[y * width + x];
        if (transparentColor != null && colorValue == transparentColor) {
          continue;
        }
        if (profile.isDynamic) {
          final safeColorValue =
              colorValue >= 0 &&
                  colorValue < MCOImageDynamicPalette.global512.length &&
                  MCOImageDynamicPalette.profileColorIdForGlobalIndex(
                        profile,
                        colorValue,
                      ) !=
                      null
              ? colorValue
              : MCOImagePalette.whiteIndexFor(profile);
          paint.color = MCOImageDynamicPalette.global512[safeColorValue];
        } else {
          final colorIndex = colorValue.clamp(0, palette.length - 1).toInt();
          paint.color = palette[colorIndex];
        }
        canvas.drawRect(
          Rect.fromLTWH(
            canvasOffset.dx + x * cellWidth,
            canvasOffset.dy + y * cellHeight,
            cellWidth,
            cellHeight,
          ),
          paint,
        );
      }
    }

    if (showGrid) {
      final gridPaint = Paint()
        ..color = _gridColor
        ..strokeWidth = 0.6
        ..isAntiAlias = false;
      for (var x = 0; x <= width; x++) {
        final dx = canvasOffset.dx + x * cellWidth;
        canvas.drawLine(
          Offset(dx, canvasOffset.dy),
          Offset(dx, canvasOffset.dy + canvasSize.height),
          gridPaint,
        );
      }
      for (var y = 0; y <= height; y++) {
        final dy = canvasOffset.dy + y * cellHeight;
        canvas.drawLine(
          Offset(canvasOffset.dx, dy),
          Offset(canvasOffset.dx + canvasSize.width, dy),
          gridPaint,
        );
      }
    }

    void paintPointMarkers(List<int> pointIndices, Color color) {
      if (pointIndices.isEmpty) return;
      final markerPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..isAntiAlias = false;
      for (final pointIndex in pointIndices) {
        if (pointIndex < 0 || pointIndex >= width * height) continue;
        final pointX = pointIndex % width;
        final pointY = pointIndex ~/ width;
        canvas.drawRect(
          Rect.fromLTWH(
            canvasOffset.dx + pointX * cellWidth,
            canvasOffset.dy + pointY * cellHeight,
            cellWidth,
            cellHeight,
          ),
          markerPaint,
        );
      }
    }

    final startIndex = lineStartIndex;
    if (startIndex != null && startIndex >= 0 && startIndex < width * height) {
      final startX = startIndex % width;
      final startY = startIndex ~/ width;
      final markerPaint = Paint()
        ..color = _lineStartColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..isAntiAlias = false;
      canvas.drawRect(
        Rect.fromLTWH(
          canvasOffset.dx + startX * cellWidth,
          canvasOffset.dy + startY * cellHeight,
          cellWidth,
          cellHeight,
        ),
        markerPaint,
      );
    }

    paintPointMarkers(ovalPointIndices, _ovalPointColor);
    paintPointMarkers(rectanglePointIndices, _rectanglePointColor);
  }

  List<int> _rulerCellNumbers(int cellCount) {
    final values = <int>{
      1,
      (cellCount * 0.25).ceil().clamp(1, cellCount).toInt(),
      (cellCount * 0.50).ceil().clamp(1, cellCount).toInt(),
      (cellCount * 0.75).ceil().clamp(1, cellCount).toInt(),
      cellCount,
    }.toList()..sort();
    return values;
  }

  void _paintRulerLabels(Canvas canvas, double cellWidth, double cellHeight) {
    const style = TextStyle(color: _rulerColor, fontSize: 7, height: 1);

    for (final cellNumber in _rulerCellNumbers(width)) {
      final textPainter = TextPainter(
        text: TextSpan(text: '$cellNumber', style: style),
        textDirection: TextDirection.ltr,
      )..layout();

      final x =
          canvasOffset.dx +
          (cellNumber - 0.5) * cellWidth -
          textPainter.width / 2;
      final y = math.max(0.0, rulerExtent - textPainter.height);
      textPainter.paint(canvas, Offset(x, y));
    }

    for (final cellNumber in _rulerCellNumbers(height)) {
      final textPainter = TextPainter(
        text: TextSpan(text: '$cellNumber', style: style),
        textDirection: TextDirection.ltr,
      )..layout();

      final x = math.max(0.0, rulerExtent - textPainter.width - 1);
      final y =
          canvasOffset.dy +
          (cellNumber - 0.5) * cellHeight -
          textPainter.height / 2;
      textPainter.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _PixelCanvasPainter oldDelegate) {
    return oldDelegate.width != width ||
        oldDelegate.height != height ||
        oldDelegate.pixels != pixels ||
        oldDelegate.palette != palette ||
        oldDelegate.transparentColor != transparentColor ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.showRuler != showRuler ||
        oldDelegate.canvasOffset != canvasOffset ||
        oldDelegate.canvasSize != canvasSize ||
        oldDelegate.rulerExtent != rulerExtent ||
        oldDelegate.lineStartIndex != lineStartIndex ||
        oldDelegate.ovalPointIndices != ovalPointIndices ||
        oldDelegate.rectanglePointIndices != rectanglePointIndices;
  }
}

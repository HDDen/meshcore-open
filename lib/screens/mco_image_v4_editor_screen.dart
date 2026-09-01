import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';

import '../helpers/channel_app_data_helper.dart';
import '../helpers/mcoimg_palette.dart';
import '../helpers/mcoimg_types.dart';
import '../helpers/mcoimg_v4_codec.dart';
import '../helpers/mcoimg_v4_model.dart';
import '../l10n/l10n.dart';
import '../models/canvas_editor_result.dart';
import '../storage/prefs_manager.dart';
import '../widgets/mco_image_v4_view.dart';

enum _V4Tool {
  select,
  dot,
  pencil,
  line,
  polyline,
  rect,
  ellipse,
  wave,
}

enum _V4ColorTarget { fill, stroke }

String _v4PaletteLabel(PaletteProfile profile) => switch (profile) {
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

class MCOImageV4EditorScreen extends StatefulWidget {
  final int maxBinaryPayloadBytes;
  final String binarySenderName;
  final PaletteProfile initialPaletteProfile;
  final bool initialShowGrid;
  final MCOImageV4Document? initialDocument;
  final String? replyTargetName;
  final int? replyTimestamp;

  const MCOImageV4EditorScreen({
    super.key,
    required this.maxBinaryPayloadBytes,
    required this.binarySenderName,
    this.initialPaletteProfile = PaletteProfile.master8,
    this.initialShowGrid = true,
    this.initialDocument,
    this.replyTargetName,
    this.replyTimestamp,
  });

  @override
  State<MCOImageV4EditorScreen> createState() =>
      _MCOImageV4EditorScreenState();
}

class _MCOImageV4EditorScreenState extends State<MCOImageV4EditorScreen> {
  static const _historyLimit = 30;
  static const _defaultSize = 128;
  static const _maxCanvasSize = 256;
  static const _prefsShowGridKey = 'canvas_editor_show_grid';
  static const double _pencilSimplifyBaseGridSize = 128;
  static const double _pencilSimplifyMinGridSize = 32;
  static const double _pencilSimplifyMidGridSize = 64;
  static const double _pencilSimplifyMinTolerance = 0.5;
  static const double _pencilSimplifySmallTolerance = 0.25;

  final _codec = const MCOImageV4Codec();
  final _undo = <MCOImageV4Document>[];
  final _redo = <MCOImageV4Document>[];
  final _shapePoints = <MCOImageV4Point>[];
  final _shapeRedoPoints = <MCOImageV4Point>[];

  late MCOImageV4Document _document;
  EncodedMCOImageV4? _encoded;
  Object? _encodeError;
  _V4Tool _tool = _V4Tool.pencil;
  int _fillColor = 0;
  int _strokeColor = 0;
  _V4ColorTarget _colorTarget = _V4ColorTarget.stroke;
  bool _fillEnabled = false;
  bool _strokeEnabled = true;
  late bool _showGrid;
  int _strokeWidth = 1;
  MCOImageV4Document? _styleDragBefore;
  int? _selectedFigureIndex;
  int? _editingFigureIndex;
  MCOImageV4Document? _editingFigureBefore;
  bool _editingFigureVisible = true;
  MCOImageV4Figure? _draftFigure;
  List<MCOImageV4Point>? _pencilPoints;
  MCOImageV4Point? _gestureStart;
  MCOImageV4Document? _moveBefore;
  MCOImageV4Point? _lastMovePoint;
  bool _groupSelectionMode = false;
  final Set<int> _groupSelectionIndexes = <int>{};
  int? _appendGroupIndex;
  Future<void>? _showGridSave;
  Uint8List? _referenceImageBytes;
  ui.Image? _referenceImage;
  bool _referenceImageVisible = true;
  bool _referenceImageLoading = false;
  int _referenceImageRequestId = 0;

  @override
  void initState() {
    super.initState();
    _showGrid = widget.initialShowGrid;
    _document = widget.initialDocument ?? _newDocument(
      _defaultSize,
      _defaultSize,
      widget.initialPaletteProfile,
    );
    final style = _document.initialStyle;
    _fillColor = style.fillColor ?? style.strokeColor ?? 0;
    _strokeColor = style.strokeColor ?? style.fillColor ?? 0;
    _fillEnabled = style.fillColor != null;
    _strokeEnabled = style.strokeColor != null;
    _strokeWidth = style.strokeWidth;
    _calculatePayload();
    if (widget.initialDocument == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSetup());
    }
  }

  @override
  void dispose() {
    _referenceImageRequestId++;
    _referenceImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _previewDocumentWithDraft();
    final selected = _selectedFigureIndex == null ||
            _selectedFigureIndex! >= preview.figures.length
        ? null
        : preview.figures[_selectedFigureIndex!];
    final envelopeBytes = _encoded == null
        ? null
        : ChannelAppDataHelper.envelopeLength(
            bodyLength: _encoded!.body.length,
            senderName: widget.binarySenderName,
          );
    final overBy = envelopeBytes == null
        ? null
        : envelopeBytes - widget.maxBinaryPayloadBytes;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.chat_canvasV4Title),
          leading: BackButton(onPressed: _cancel),
          actions: [
            IconButton(
              tooltip: context.l10n.common_undo,
              onPressed: _shapePoints.isNotEmpty ||
                      _editingFigureBefore != null ||
                      _undo.isNotEmpty
                  ? _undoChange
                  : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: context.l10n.chat_canvasV4Redo,
              onPressed: _shapeRedoPoints.isNotEmpty ||
                      (_editingFigureBefore == null &&
                          _shapePoints.isEmpty &&
                          _redo.isNotEmpty)
                  ? _redoChange
                  : null,
              icon: const Icon(Icons.redo),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              _buildGridSummary(),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.chat_canvasGridShow),
                value: _showGrid,
                onChanged: _setCanvasGridShown,
              ),
              const SizedBox(height: 8),
              _buildReferenceControls(),
              const SizedBox(height: 12),
              _buildPalette(),
              const SizedBox(height: 12),
              _buildStyleControls(),
              const SizedBox(height: 12),
              _buildTools(),
              if (_tool == _V4Tool.wave) ...[
                const SizedBox(height: 8),
                Text(context.l10n.chat_canvasV4WaveHint),
              ],
              if (_tool == _V4Tool.polyline) ...[
                const SizedBox(height: 8),
                Text(context.l10n.chat_canvasV4PolylineHint),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _shapePoints.length >= 2
                          ? () => _finishPolyline(closed: false)
                          : null,
                      icon: const Icon(Icons.done),
                      label: Text(context.l10n.chat_canvasV4FinishOpen),
                    ),
                    FilledButton.icon(
                      onPressed: _shapePoints.length >= 3
                          ? () => _finishPolyline(closed: true)
                          : null,
                      icon: const Icon(Icons.join_full),
                      label: Text(context.l10n.chat_canvasV4FinishClosed),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = math.min(constraints.maxWidth, 640.0);
                  final height = width * _document.height / _document.width;
                  return Center(
                    child: Container(
                      width: width,
                      height: height,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_referenceImageVisible &&
                              _referenceImage != null)
                            Opacity(
                              opacity: 0.45,
                              child: RawImage(
                                image: _referenceImage,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.none,
                              ),
                            ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) => _handleTap(
                              details.localPosition,
                              Size(width, height),
                            ),
                            onPanStart: (details) => _handlePanStart(
                              details.localPosition,
                              Size(width, height),
                            ),
                            onPanUpdate: (details) => _handlePanUpdate(
                              details.localPosition,
                              Size(width, height),
                            ),
                            onPanEnd: (_) => _handlePanEnd(),
                            child: CustomPaint(
                              painter: MCOImageV4Painter(
                                preview,
                                paintBackground: !_referenceImageVisible ||
                                    _referenceImage == null,
                                selectedFigure: selected,
                                selectionColor:
                                    Theme.of(context).colorScheme.primary,
                                guidePoints: List<MCOImageV4Point>.of(
                                  _shapePoints,
                                ),
                                guideStyle: _currentStyle(),
                                showGrid: _showGrid,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildPayloadInfo(envelopeBytes, overBy),
              const SizedBox(height: 16),
              _buildObjects(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _cancel,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: _actionButtonLabel(context.l10n.common_cancel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: 'Открыть в обычном холсте v3',
                      child: OutlinedButton.icon(
                        onPressed: _openAsRasterV3,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(Icons.grid_on),
                        label: const Text(
                          'v3',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _calculatePayload,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.calculate_outlined),
                      label: _actionButtonLabel(
                        context.l10n.chat_canvasV4Calculate,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _encoded != null && (overBy ?? 1) <= 0
                          ? _send
                          : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: _actionButtonLabel(context.l10n.common_send),
                    ),
                  ),
                ],
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  MCOImageV4Document _previewDocumentWithDraft() {
    final draft = _draftFigure;
    if (draft == null) return _document;
    final appendIndex = _appendGroupIndex;
    if (appendIndex != null &&
        appendIndex >= 0 &&
        appendIndex < _document.figures.length &&
        _document.figures[appendIndex] is MCOImageV4Group) {
      final figures = [..._document.figures];
      final group = figures[appendIndex] as MCOImageV4Group;
      figures[appendIndex] = MCOImageV4Group(
        figures: [...group.figures, draft],
        style: group.style,
        visible: group.visible,
      );
      return _document.copyWith(figures: figures);
    }
    return _document.copyWith(figures: [..._document.figures, draft]);
  }

  Widget _actionButtonLabel(String text) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      );

  Widget _buildGridSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _showSetup,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(Icons.grid_4x4),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${context.l10n.chat_canvasV4Grid}: '
                        '${_document.width}×${_document.height}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(context.l10n.chat_canvasV4GridDescription),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showSetup,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.tune),
                label: _actionButtonLabel(
                  context.l10n.chat_canvasV4CanvasSettings,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _trimCanvas,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.content_cut),
                label: _actionButtonLabel(context.l10n.chat_canvasTrim),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReferenceControls() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _referenceImageLoading ? null : _loadReferenceImage,
          icon: _referenceImageLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_photo_alternate_outlined),
          label: Text(context.l10n.chat_canvasV4LoadReference),
        ),
        if (_referenceImage != null) ...[
          IconButton(
            tooltip: _referenceImageVisible
                ? context.l10n.chat_canvasV4HideReference
                : context.l10n.chat_canvasV4ShowReference,
            onPressed: () => setState(
              () => _referenceImageVisible = !_referenceImageVisible,
            ),
            icon: Icon(
              _referenceImageVisible
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
          IconButton(
            tooltip: context.l10n.chat_canvasV4RemoveReference,
            onPressed: _clearReferenceImage,
            icon: const Icon(Icons.delete_outline),
          ),
          Text(context.l10n.chat_canvasV4ReferenceNotEncoded),
        ],
      ],
    );
  }

  void _setCanvasGridShown(bool? value) {
    final showGrid = value ?? true;
    if (showGrid == _showGrid) return;
    setState(() => _showGrid = showGrid);
    _showGridSave = PrefsManager.instance.setBool(
      _prefsShowGridKey,
      showGrid,
    );
    unawaited(_showGridSave);
  }

  Widget _buildPalette() {
    final colors = _document.palette
        .map(
          (color) => _profileColor(
            _document.paletteProfile,
            color,
          ),
        )
        .toList(growable: false);
    final selectedColor = _colorTarget == _V4ColorTarget.fill
        ? (_fillEnabled ? _fillColor : null)
        : (_strokeEnabled ? _strokeColor : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.chat_canvasPaletteMode,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(_v4PaletteLabel(_document.paletteProfile)),
        if (_document.paletteProfile.isDynamic) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _showDynamicPaletteDialog,
            icon: const Icon(Icons.palette_outlined),
            label: Text(context.l10n.chat_canvasPaletteShow),
          ),
        ],
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          leading: const Icon(Icons.format_color_fill_outlined),
          title: Text(context.l10n.chat_canvasV4Background),
          subtitle: Text(
            _document.backgroundColor == null
                ? context.l10n.chat_canvasV4Transparent
                : '#${_document.backgroundColor! + 1}',
          ),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Tooltip(
                    message: context.l10n.chat_canvasV4Transparent,
                    child: InkWell(
                      onTap: () => _setBackground(null),
                      borderRadius: BorderRadius.circular(4),
                      child: _TransparentColorSwatch(
                        selected: _document.backgroundColor == null,
                      ),
                    ),
                  ),
                  for (var i = 0; i < colors.length; i++)
                    InkWell(
                      onTap: () => _setBackground(i),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: colors[i],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _document.backgroundColor == i
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                            width: _document.backgroundColor == i ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<_V4ColorTarget>(
          segments: [
            ButtonSegment(
              value: _V4ColorTarget.fill,
              label: Text(context.l10n.chat_canvasV4Fill),
            ),
            ButtonSegment(
              value: _V4ColorTarget.stroke,
              label: Text(context.l10n.chat_canvasV4Stroke),
            ),
          ],
          selected: {_colorTarget},
          onSelectionChanged: (selection) {
            setState(() => _colorTarget = selection.first);
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Tooltip(
              message: context.l10n.chat_canvasV4Transparent,
              child: InkWell(
                onTap: _setTransparentStyleColor,
                borderRadius: BorderRadius.circular(4),
                child: _TransparentColorSwatch(
                  selected: selectedColor == null,
                ),
              ),
            ),
            for (var i = 0; i < colors.length; i++)
              Tooltip(
                message: '#${i + 1}',
                child: InkWell(
                  onTap: () => _setStyleColor(i),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colors[i],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: i == selectedColor
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                        width: i == selectedColor ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStyleControls() {
    final maxWidth = math.max(_document.width, _document.height);
    final selected = _selectedFigureIndex == null
        ? null
        : _document.figures[_selectedFigureIndex!];
    final canClose = selected is! MCOImageV4Path || selected.points.length >= 3;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(context.l10n.chat_canvasV4StrokeWidth)),
            Text('$_strokeWidth'),
          ],
        ),
        Slider(
          value: _strokeWidth
              .toDouble()
              .clamp(1, maxWidth.toDouble())
              .toDouble(),
          min: 1,
          max: maxWidth.toDouble(),
          divisions: maxWidth > 1 ? maxWidth - 1 : null,
          onChangeStart: (_) => _beginStyleDrag(),
          onChanged: (value) {
            final width = value.round();
            if (width == _strokeWidth) return;
            _updateStyle(
              () => _strokeWidth = width,
              recordUndo: false,
            );
          },
          onChangeEnd: (_) => _endStyleDrag(),
        ),
        if (selected is MCOImageV4Path || selected is MCOImageV4Wave)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.chat_canvasV4Closed),
            value: switch (selected) {
              MCOImageV4Path(:final closed) => closed,
              MCOImageV4Wave(:final closed) => closed,
              _ => false,
            },
            onChanged: canClose ? _setSelectedClosed : null,
          ),
      ],
    );
  }

  Future<void> _showDynamicPaletteDialog() async {
    final profile = _document.paletteProfile;
    if (!profile.isDynamic) return;
    final values = MCOImageDynamicPalette.indicesFor(profile);
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.chat_canvasPaletteDynamicProfile),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final value in values)
                  InkWell(
                    onTap: () => Navigator.pop(dialogContext, value),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: MCOImageDynamicPalette.global512[value],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _document.palette.contains(value)
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                          width: _document.palette.contains(value) ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.common_close),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    var localIndex = _document.palette.indexOf(selected);
    var paletteChanged = false;
    if (localIndex < 0) {
      if (_document.palette.length >= 64) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.chat_canvasV4PaletteFull)),
        );
        return;
      }
      localIndex = _document.palette.length;
      _commit(
        _document.copyWith(
          palette: [..._document.palette, selected],
        ),
      );
      paletteChanged = true;
    }
    _setStyleColor(localIndex);
    if (paletteChanged) await _rebuildReferenceImage();
  }

  Widget _buildTools() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _toolButton(_V4Tool.select, Icons.near_me_outlined,
              context.l10n.chat_canvasV4ToolSelect),
          _cloneToolButton(),
          _mergeToolButton(),
          _appendToGroupToolButton(),
          _ungroupToolButton(),
          _editToolButton(),
          _toolButton(_V4Tool.dot, Icons.fiber_manual_record,
              context.l10n.chat_canvasV4ToolDot),
          _toolButton(_V4Tool.pencil, Icons.edit,
              context.l10n.chat_canvasV4ToolPencil),
          _toolButton(_V4Tool.line, Icons.horizontal_rule,
              context.l10n.chat_canvasV4ToolLine),
          _toolButton(_V4Tool.polyline, Icons.polyline,
              context.l10n.chat_canvasV4ToolPolyline),
          _toolButton(_V4Tool.rect, Icons.crop_square,
              context.l10n.chat_canvasV4ToolRect),
          _toolButton(_V4Tool.ellipse, Icons.circle_outlined,
              context.l10n.chat_canvasV4ToolEllipse),
          _toolButton(_V4Tool.wave, Icons.gesture,
              context.l10n.chat_canvasV4ToolWave),
        ],
      ),
    );
  }

  Widget _cloneToolButton() {
    final canClone = _selectedFigureIndex != null &&
        _selectedFigureIndex! < _document.figures.length;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: IconButton(
        tooltip: context.l10n.common_copy,
        onPressed: canClone ? _cloneSelectedFigure : null,
        icon: const Icon(Icons.content_copy),
      ),
    );
  }

  Widget _mergeToolButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: IconButton(
        tooltip: 'Выбрать фигуры для объединения',
        onPressed: _document.figures.isEmpty ? null : _toggleGroupSelectionMode,
        icon: const Icon(Icons.lock_outline),
        style: _groupSelectionMode
            ? IconButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
              )
            : null,
      ),
    );
  }

  Widget _appendToGroupToolButton() {
    final index = _selectedFigureIndex;
    final canAppend =
        index != null &&
        index < _document.figures.length &&
        _document.figures[index] is MCOImageV4Group;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: IconButton(
        tooltip: 'Добавлять новые фигуры в выбранную группу',
        onPressed: canAppend ? _toggleAppendToSelectedGroup : null,
        icon: const Icon(Icons.lock),
        style: _appendGroupIndex == index
            ? IconButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
              )
            : null,
      ),
    );
  }

  Widget _ungroupToolButton() {
    final index = _selectedFigureIndex;
    final canUngroup =
        index != null &&
        index < _document.figures.length &&
        _document.figures[index] is MCOImageV4Group;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: IconButton(
        tooltip: 'Разгруппировать',
        onPressed: canUngroup ? _ungroupSelectedFigure : null,
        icon: const Icon(Icons.lock_open_outlined),
      ),
    );
  }

  Widget _editToolButton() {
    final canEdit = _selectedFigureIndex != null &&
        _selectedFigureIndex! < _document.figures.length &&
        _document.figures[_selectedFigureIndex!] is! MCOImageV4Group &&
        _document.figures[_selectedFigureIndex!] is! MCOImageV4RasterLayer;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: IconButton(
        tooltip: context.l10n.common_edit,
        onPressed: canEdit ? _editSelectedFigure : null,
        icon: const Icon(Icons.account_tree_outlined),
      ),
    );
  }

  Widget _toolButton(_V4Tool tool, IconData icon, String tooltip) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: IconButton(
        tooltip: tooltip,
        onPressed: () => _selectTool(tool),
        style: IconButton.styleFrom(
          backgroundColor: _tool == tool
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
        ),
        icon: Icon(icon),
      ),
    );
  }

  Widget _buildPayloadInfo(int? bytes, int? overBy) {
    if (_encodeError != null) {
      return Text(
        '$_encodeError',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    if (bytes == null) return const LinearProgressIndicator();
    if ((overBy ?? 0) > 0) {
      return Text(
        context.l10n.chat_canvasV4PayloadTooLarge(overBy!),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    return Text(context.l10n.chat_canvasV4Payload(bytes));
  }

  Widget _buildObjects() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.chat_canvasV4Objects,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_groupSelectionMode) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Выбрано: ${_groupSelectionIndexes.length}'),
              OutlinedButton.icon(
                onPressed: _canMergeCheckedFigures
                    ? _mergeCheckedFigures
                    : null,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Объединить выбранные'),
              ),
              TextButton(
                onPressed: _cancelGroupSelection,
                child: Text(context.l10n.common_cancel),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (_document.figures.isEmpty)
          Text(context.l10n.chat_canvasV4NoObjects)
        else
          for (var i = _document.figures.length - 1; i >= 0; i--)
            ListTile(
              selected:
                  i == _selectedFigureIndex ||
                  _groupSelectionIndexes.contains(i),
              contentPadding: EdgeInsets.zero,
              leading: _groupSelectionMode
                  ? Checkbox(
                      value: _groupSelectionIndexes.contains(i),
                      onChanged: (selected) =>
                          _setFigureCheckedForGroup(i, selected ?? false),
                    )
                  : IconButton(
                      tooltip: _document.figures[i].visible
                          ? context.l10n.chat_canvasV4HideFigure
                          : context.l10n.chat_canvasV4ShowFigure,
                      onPressed: () => _toggleVisibility(i),
                      icon: Icon(
                        _document.figures[i].visible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
              title: Row(
                children: [
                  _V4FigurePreview(
                    document: _document,
                    figure: _document.figures[i],
                    selected:
                        i == _selectedFigureIndex ||
                        i == _appendGroupIndex ||
                        _groupSelectionIndexes.contains(i),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      i == _appendGroupIndex
                          ? '${_figureLabel(_document.figures[i])} +'
                          : _figureLabel(_document.figures[i]),
                    ),
                  ),
                ],
              ),
              onTap: () => _groupSelectionMode
                  ? _toggleFigureCheckedForGroup(i)
                  : _selectFigure(i),
              trailing: _groupSelectionMode
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: context.l10n.chat_canvasV4MoveUp,
                          onPressed: i == _document.figures.length - 1
                              ? null
                              : () => _reorder(i, i + 1),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: context.l10n.chat_canvasV4MoveDown,
                          onPressed: i == 0 ? null : () => _reorder(i, i - 1),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .deleteButtonTooltip,
                          onPressed: () => _deleteFigure(i),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
            ),
      ],
    );
  }

  Future<void> _showSetup() async {
    final result = await showDialog<(int, int, PaletteProfile)>(
      context: context,
      barrierDismissible: widget.initialDocument != null,
      builder: (dialogContext) => _V4CanvasSetupDialog(
        width: _document.width,
        height: _document.height,
        profile: _document.paletteProfile,
      ),
    );
    if (!mounted) return;
    if (result == null) {
      if (widget.initialDocument == null && _document.figures.isEmpty) {
        Navigator.pop(context);
      }
      return;
    }
    final (newWidth, newHeight, newProfile) = result;
    final nextPalette = _paletteForProfileChange(newProfile);
    if (_document.figures.isEmpty) {
      final previousPalette = _document.palette;
      final previousProfile = _document.paletteProfile;
      final background = _remapColor(
        _document.backgroundColor,
        previousPalette,
        previousProfile,
        nextPalette,
        newProfile,
      );
      _fillColor = _remapColor(
        _fillColor,
        previousPalette,
        previousProfile,
        nextPalette,
        newProfile,
      )!;
      _strokeColor = _remapColor(
        _strokeColor,
        previousPalette,
        previousProfile,
        nextPalette,
        newProfile,
      )!;
      _commit(
        _newDocument(newWidth, newHeight, newProfile).copyWith(
          palette: nextPalette,
          backgroundColor: background,
        ),
      );
      await _rebuildReferenceImage();
      return;
    }
    if (newWidth == _document.width &&
        newHeight == _document.height &&
        newProfile == _document.paletteProfile &&
        _listEquals(nextPalette, _document.palette)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.chat_canvasV4Grid),
        content: Text(context.l10n.chat_canvasV4GridDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.common_apply),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final remapped = _rescaleDocument(
      _document,
      newWidth,
      newHeight,
      nextPalette,
      newProfile,
    );
    _fillColor = _remapColor(
      _fillColor,
      _document.palette,
      _document.paletteProfile,
      nextPalette,
      newProfile,
    )!;
    _strokeColor = _remapColor(
      _strokeColor,
      _document.palette,
      _document.paletteProfile,
      nextPalette,
      newProfile,
    )!;
    _commit(remapped);
    await _rebuildReferenceImage();
  }

  Future<void> _loadReferenceImage() async {
    try {
      final file = await file_selector.openFile(
        acceptedTypeGroups: const [
          file_selector.XTypeGroup(
            label: 'Images',
            extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
            mimeTypes: [
              'image/png',
              'image/jpeg',
              'image/webp',
              'image/bmp',
              'image/gif',
            ],
            uniformTypeIdentifiers: ['public.image'],
          ),
        ],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await _adoptReferenceImageCanvasSize(bytes);
      if (!mounted) return;
      setState(() {
        _referenceImageBytes = bytes;
        _referenceImageVisible = true;
      });
      await _rebuildReferenceImage();
    } on Object catch (error) {
      if (!mounted) return;
      _clearReferenceImage();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _adoptReferenceImageCanvasSize(Uint8List bytes) async {
    final source = await _decodeReferenceFrame(bytes);
    final sourceWidth = source.width;
    final sourceHeight = source.height;
    source.dispose();
    if (!mounted) return;

    final width = sourceWidth.clamp(1, _maxCanvasSize).toInt();
    final height = sourceHeight.clamp(1, _maxCanvasSize).toInt();
    if (width == _document.width && height == _document.height) return;

    _commit(
      _rescaleDocument(
        _document,
        width,
        height,
        _document.palette,
        _document.paletteProfile,
      ),
    );
  }

  Future<void> _rebuildReferenceImage() async {
    final bytes = _referenceImageBytes;
    if (bytes == null) return;
    final requestId = ++_referenceImageRequestId;
    if (mounted) setState(() => _referenceImageLoading = true);
    try {
      final image = await _quantizeReferenceImage(bytes);
      if (!mounted || requestId != _referenceImageRequestId) {
        image.dispose();
        return;
      }
      final previous = _referenceImage;
      setState(() {
        _referenceImage = image;
        _referenceImageLoading = false;
      });
      previous?.dispose();
    } on Object {
      if (!mounted || requestId != _referenceImageRequestId) return;
      setState(() => _referenceImageLoading = false);
      rethrow;
    }
  }

  Future<ui.Image> _quantizeReferenceImage(Uint8List bytes) async {
    final source = await _decodeReferenceFrame(bytes);
    final sourceWidth = source.width;
    final sourceHeight = source.height;
    source.dispose();

    final scale = math.min(
      _document.width / sourceWidth,
      _document.height / sourceHeight,
    );
    final targetWidth = math.max(1, (sourceWidth * scale).floor());
    final targetHeight = math.max(1, (sourceHeight * scale).floor());
    final scaled = await _decodeReferenceFrame(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final rgba = await scaled.toByteData(format: ui.ImageByteFormat.rawRgba);
    scaled.dispose();
    if (rgba == null) {
      throw const MCOImageInvalidInputException(
        'Cannot read reference image pixels',
      );
    }

    final output = Uint8List(_document.width * _document.height * 4);
    final palette = _document.palette
        .map(
          (color) => _profileColor(
            _document.paletteProfile,
            color,
          ),
        )
        .toList(growable: false);
    final startX = (_document.width - targetWidth) ~/ 2;
    final startY = (_document.height - targetHeight) ~/ 2;
    for (var y = 0; y < targetHeight; y++) {
      for (var x = 0; x < targetWidth; x++) {
        final sourceOffset = (y * targetWidth + x) * 4;
        final alpha = rgba.getUint8(sourceOffset + 3);
        if (alpha == 0) continue;
        final color = _nearestReferenceColor(
          rgba.getUint8(sourceOffset),
          rgba.getUint8(sourceOffset + 1),
          rgba.getUint8(sourceOffset + 2),
          palette,
        );
        final argb = color.toARGB32();
        final outputOffset =
            ((startY + y) * _document.width + startX + x) * 4;
        output[outputOffset] = (argb >> 16) & 0xff;
        output[outputOffset + 1] = (argb >> 8) & 0xff;
        output[outputOffset + 2] = argb & 0xff;
        output[outputOffset + 3] = alpha;
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      output,
      _document.width,
      _document.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Future<ui.Image> _decodeReferenceFrame(
    Uint8List bytes, {
    int? targetWidth,
    int? targetHeight,
  }) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  Color _nearestReferenceColor(
    int red,
    int green,
    int blue,
    List<Color> palette,
  ) {
    var best = palette.first;
    var bestDistance = 1 << 62;
    for (final color in palette) {
      final argb = color.toARGB32();
      final dr = red - ((argb >> 16) & 0xff);
      final dg = green - ((argb >> 8) & 0xff);
      final db = blue - (argb & 0xff);
      final distance = dr * dr + dg * dg + db * db;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = color;
      }
    }
    return best;
  }

  void _clearReferenceImage() {
    _referenceImageRequestId++;
    final previous = _referenceImage;
    setState(() {
      _referenceImageBytes = null;
      _referenceImage = null;
      _referenceImageLoading = false;
    });
    previous?.dispose();
  }

  void _handleTap(Offset position, Size size) {
    final point = _gridPoint(position, size);
    switch (_tool) {
      case _V4Tool.dot:
        _addFigure(MCOImageV4Dot(point: point, style: _currentStyle()));
      case _V4Tool.pencil:
        _addFigure(MCOImageV4Dot(point: point, style: _currentStyle()));
      case _V4Tool.line:
        final points = _acceptShapePoint(point, requiredCount: 2);
        if (points == null) return;
        _addFigure(
          MCOImageV4Line(
            start: points[0],
            end: points[1],
            style: _currentStyle(),
          ),
        );
      case _V4Tool.polyline:
        if (_shapePoints.length >= 3 && _shapePoints.first == point) {
          _finishPolyline(closed: true);
          return;
        }
        if (_shapePoints.isNotEmpty && _shapePoints.last == point) return;
        setState(() => _addShapePoint(point));
      case _V4Tool.rect:
      case _V4Tool.ellipse:
        final points = _acceptShapePoint(point, requiredCount: 3);
        if (points == null) return;
        _addFigure(_areaDraft(points[0], points[1], points[2], _tool));
      case _V4Tool.wave:
        final points = _acceptShapePoint(point, requiredCount: 3);
        if (points == null) return;
        final start = points[0];
        final end = points[1];
        final handle = points[2];
        final dx = end.x - start.x;
        final dy = end.y - start.y;
        final midpointX = (start.x + end.x) / 2;
        final midpointY = (start.y + end.y) / 2;
        final length = math.sqrt(dx * dx + dy * dy);
        var depth = (((handle.x - midpointX) * -dy +
                    (handle.y - midpointY) * dx) /
                length)
            .round();
        if (depth == 0) depth = 1;
        depth = depth.clamp(
          -math.max(_document.width, _document.height),
          math.max(_document.width, _document.height),
        ).toInt();
        _addFigure(
          MCOImageV4Wave(
            start: start,
            end: end,
            depth: depth,
            closed: false,
            style: _currentStyle(),
          ),
        );
      case _V4Tool.select:
        final index = _hitTest(point);
        if (_groupSelectionMode) {
          if (index != null) _toggleFigureCheckedForGroup(index);
          return;
        }
        if (index != null) _selectFigure(index);
    }
  }

  void _handlePanStart(Offset position, Size size) {
    final point = _gridPoint(
      position,
      size,
      clampToCanvas: _tool != _V4Tool.select,
    );
    switch (_tool) {
      case _V4Tool.pencil:
        _gestureStart = point;
        _pencilPoints = <MCOImageV4Point>[point];
      case _V4Tool.select:
        if (_groupSelectionMode) return;
        _gestureStart = point;
        final index = _hitTest(point);
        final selectedIndex = index ?? _selectedFigureIndexOutsideCanvas();
        if (selectedIndex != null && selectedIndex < _document.figures.length) {
          if (index != null) _selectFigure(index);
          _moveBefore = _document;
          _lastMovePoint = point;
        }
      default:
        break;
    }
  }

  void _handlePanUpdate(Offset position, Size size) {
    final point = _gridPoint(
      position,
      size,
      clampToCanvas: _tool != _V4Tool.select,
    );
    final start = _gestureStart;
    if (start == null) return;
    switch (_tool) {
      case _V4Tool.pencil:
        final points = _pencilPoints;
        if (points != null && points.last != point) {
          points.add(point);
          setState(() {
            _draftFigure = points.length < 2
                ? null
                : MCOImageV4Path(
                    points: points,
                    closed: false,
                    style: _currentStyle(),
                  );
          });
        }
      case _V4Tool.select:
        _moveSelected(point);
      default:
        break;
    }
  }

  void _handlePanEnd() {
    if (_tool == _V4Tool.select) {
      if (_moveBefore != null && !identical(_moveBefore, _document)) {
        _undo.add(_moveBefore!);
        if (_undo.length > _historyLimit) _undo.removeAt(0);
        _redo.clear();
        _calculatePayload();
      }
      _moveBefore = null;
      _lastMovePoint = null;
      _gestureStart = null;
      return;
    }

    MCOImageV4Figure? figure = _draftFigure;
    if (_tool == _V4Tool.pencil) {
      final points = _simplifyPoints(_pencilPoints ?? const []);
      if (points.length == 1) {
        figure = MCOImageV4Dot(point: points.first, style: _currentStyle());
      } else if (points.length >= 2) {
        figure = MCOImageV4Path(
          points: points,
          closed: false,
          style: _currentStyle(),
        );
      }
    }
    _gestureStart = null;
    _pencilPoints = null;
    _draftFigure = null;
    if (figure != null) _addFigure(figure);
  }

  List<MCOImageV4Point>? _acceptShapePoint(
    MCOImageV4Point point, {
    required int requiredCount,
  }) {
    if (_shapePoints.contains(point)) {
      if (_editingFigureBefore != null) {
        _restoreEditedFigure();
      } else {
        setState(_clearDraftState);
      }
      return null;
    }
    _addShapePoint(point);
    if (_shapePoints.length < requiredCount) {
      setState(() {});
      return null;
    }
    final result = List<MCOImageV4Point>.of(_shapePoints);
    _shapePoints.clear();
    _shapeRedoPoints.clear();
    return result;
  }

  void _finishPolyline({required bool closed}) {
    final minimum = closed ? 3 : 2;
    if (_shapePoints.length < minimum) return;
    final points = List<MCOImageV4Point>.of(_shapePoints);
    _shapePoints.clear();
    _shapeRedoPoints.clear();
    _addFigure(
      MCOImageV4Path(
        points: points,
        closed: closed,
        style: _currentStyle(),
      ),
    );
  }

  MCOImageV4Figure _areaDraft(
    MCOImageV4Point first,
    MCOImageV4Point second,
    MCOImageV4Point third,
    _V4Tool tool,
  ) {
    final style = _currentStyle();
    return switch (tool) {
      _V4Tool.rect => MCOImageV4Rect(
          first: first,
          second: second,
          third: third,
          style: style,
        ),
      _V4Tool.ellipse => MCOImageV4Ellipse(
          first: first,
          second: second,
          third: third,
          style: style,
        ),
      _ => throw StateError('Not an area tool'),
    };
  }

  void _moveSelected(MCOImageV4Point point) {
    final index = _selectedFigureIndex;
    final previous = _lastMovePoint;
    if (index == null || previous == null || previous == point) return;
    final dx = point.x - previous.x;
    final dy = point.y - previous.y;
    final figures = [..._document.figures];
    figures[index] = figures[index].translated(dx, dy);
    setState(() {
      _document = _document.copyWith(figures: figures);
      _lastMovePoint = point;
    });
  }

  void _addFigure(MCOImageV4Figure figure) {
    final editingIndex = _editingFigureIndex;
    final editingBefore = _editingFigureBefore;
    if (editingIndex != null && editingBefore != null) {
      final figures = [..._document.figures];
      final insertIndex = math.min(editingIndex, figures.length);
      figures.insert(insertIndex, figure.withVisibility(_editingFigureVisible));
      _undo.add(editingBefore);
      if (_undo.length > _historyLimit) _undo.removeAt(0);
      _redo.clear();
      setState(() {
        _document = _document.copyWith(figures: figures);
        _selectedFigureIndex = insertIndex;
        _clearDraftState();
        _clearEditingState();
      });
      _calculatePayload();
      return;
    }
    final appendIndex = _appendGroupIndex;
    if (appendIndex != null &&
        appendIndex >= 0 &&
        appendIndex < _document.figures.length &&
        _document.figures[appendIndex] is MCOImageV4Group) {
      final figures = [..._document.figures];
      final group = figures[appendIndex] as MCOImageV4Group;
      figures[appendIndex] = MCOImageV4Group(
        figures: [...group.figures, figure],
        style: group.style,
        visible: group.visible,
      );
      _commit(_document.copyWith(figures: figures));
      setState(() {
        _selectedFigureIndex = _tool == _V4Tool.select ? appendIndex : null;
      });
      return;
    }
    _commit(_document.copyWith(figures: [..._document.figures, figure]));
    setState(() => _selectedFigureIndex = _document.figures.length - 1);
  }

  void _cloneSelectedFigure() {
    final index = _selectedFigureIndex;
    if (index == null || index >= _document.figures.length) return;

    final figures = [..._document.figures];
    final cloneIndex = index + 1;
    figures.insert(cloneIndex, figures[index].withVisibility(true));
    _commit(_document.copyWith(figures: figures));
    setState(() {
      _tool = _V4Tool.select;
      _selectedFigureIndex = cloneIndex;
      _clearDraftState();
    });
  }

  void _ungroupSelectedFigure() {
    final index = _selectedFigureIndex;
    if (index == null || index >= _document.figures.length) return;
    final selected = _document.figures[index];
    if (selected is! MCOImageV4Group) return;
    final childFigures = selected.visible
        ? selected.figures
        : selected.figures
            .map((figure) => figure.withVisibility(false))
            .toList(growable: false);
    final figures = [..._document.figures]
      ..removeAt(index)
      ..insertAll(index, childFigures);
    _appendGroupIndex = null;
    _commit(_document.copyWith(figures: figures));
    setState(() {
      _tool = _V4Tool.select;
      _selectedFigureIndex = math.min(
        index + childFigures.length - 1,
        figures.length - 1,
      );
      _clearDraftState();
    });
  }

  void _editSelectedFigure() {
    final index = _selectedFigureIndex;
    if (index == null || index >= _document.figures.length) return;

    final before = _document;
    final figure = before.figures[index];
    final figures = [...before.figures]..removeAt(index);
    setState(() {
      _document = before.copyWith(figures: figures);
      _editingFigureIndex = index;
      _editingFigureBefore = before;
      _editingFigureVisible = figure.visible;
      _tool = _toolForEditedFigure(figure);
      _selectedFigureIndex = null;
      _fillEnabled = figure.style.fillColor != null;
      _strokeEnabled = figure.style.strokeColor != null;
      _fillColor = figure.style.fillColor ?? _fillColor;
      _strokeColor = figure.style.strokeColor ?? _strokeColor;
      _strokeWidth = figure.style.strokeWidth;
      _clearDraftState();
      _shapePoints.addAll(_controlPointsForEditedFigure(figure));
    });
    _calculatePayload();
  }

  _V4Tool _toolForEditedFigure(MCOImageV4Figure figure) => switch (figure) {
        MCOImageV4Dot() => _V4Tool.dot,
        MCOImageV4Line() => _V4Tool.line,
        MCOImageV4Rect() => _V4Tool.rect,
        MCOImageV4Ellipse() => _V4Tool.ellipse,
        MCOImageV4Path() => _V4Tool.polyline,
        MCOImageV4Wave() => _V4Tool.wave,
        MCOImageV4Group() => _V4Tool.select,
        MCOImageV4RasterLayer() => _V4Tool.select,
      };

  List<MCOImageV4Point> _controlPointsForEditedFigure(
    MCOImageV4Figure figure,
  ) =>
      switch (figure) {
        MCOImageV4Dot() => const <MCOImageV4Point>[],
        MCOImageV4Line(:final start) => <MCOImageV4Point>[start],
        MCOImageV4Rect(:final first, :final second) => <MCOImageV4Point>[
            first,
            second,
          ],
        MCOImageV4Ellipse(:final first, :final second) => <MCOImageV4Point>[
            first,
            second,
          ],
        MCOImageV4Path(:final points) => List<MCOImageV4Point>.of(points),
        MCOImageV4Wave(:final start, :final end) => <MCOImageV4Point>[
            start,
            end,
          ],
        MCOImageV4Group() => const <MCOImageV4Point>[],
        MCOImageV4RasterLayer() => const <MCOImageV4Point>[],
      };

  void _selectFigure(int index) {
    final figure = _document.figures[index];
    setState(() {
      _selectedFigureIndex = index;
      if (_appendGroupIndex != index) {
        _appendGroupIndex = null;
      }
      _fillEnabled = figure.style.fillColor != null;
      _strokeEnabled = figure.style.strokeColor != null;
      _fillColor = figure.style.fillColor ?? _fillColor;
      _strokeColor = figure.style.strokeColor ?? _strokeColor;
      _strokeWidth = figure.style.strokeWidth;
    });
  }

  void _setStyleColor(int color) {
    if ((_colorTarget == _V4ColorTarget.fill &&
            _fillEnabled &&
            _fillColor == color) ||
        (_colorTarget == _V4ColorTarget.stroke &&
            _strokeEnabled &&
            _strokeColor == color)) {
      return;
    }
    _updateStyle(() {
      if (_colorTarget == _V4ColorTarget.fill) {
        _fillColor = color;
        _fillEnabled = true;
      } else {
        _strokeColor = color;
        _strokeEnabled = true;
      }
    });
  }

  void _setTransparentStyleColor() {
    if (_colorTarget == _V4ColorTarget.fill) {
      if (!_fillEnabled) return;
      _updateStyle(() => _fillEnabled = false);
      return;
    }
    if (!_strokeEnabled) return;
    _updateStyle(() => _strokeEnabled = false);
  }

  void _selectTool(_V4Tool tool) {
    if (tool == _tool) {
      if (_tool == _V4Tool.polyline && _shapePoints.length >= 2) {
        _finishPolyline(closed: false);
      } else if (_shapePoints.isNotEmpty &&
          (_tool == _V4Tool.line ||
              _tool == _V4Tool.rect ||
              _tool == _V4Tool.ellipse ||
              _tool == _V4Tool.wave)) {
        if (_editingFigureBefore != null) {
          _restoreEditedFigure();
        } else {
          setState(_clearDraftState);
        }
      } else if (_editingFigureBefore != null) {
        _restoreEditedFigure();
      } else if (tool != _V4Tool.select && _selectedFigureIndex != null) {
        setState(() {
          _selectedFigureIndex = null;
          _groupSelectionMode = false;
          _groupSelectionIndexes.clear();
        });
      }
      return;
    }
    if (_tool == _V4Tool.polyline && _shapePoints.length >= 2) {
      _finishPolyline(closed: false);
    } else if (_editingFigureBefore != null) {
      _restoreEditedFigure();
    }
    setState(() {
      _tool = tool;
      if (tool != _V4Tool.select) {
        _selectedFigureIndex = null;
        _groupSelectionMode = false;
        _groupSelectionIndexes.clear();
      }
      _clearDraftState();
    });
  }

  void _addShapePoint(MCOImageV4Point point) {
    _shapePoints.add(point);
    _shapeRedoPoints.clear();
  }

  void _clearDraftState() {
    _shapePoints.clear();
    _shapeRedoPoints.clear();
    _draftFigure = null;
    _pencilPoints = null;
    _gestureStart = null;
    _moveBefore = null;
    _lastMovePoint = null;
  }

  void _clearEditingState() {
    _editingFigureIndex = null;
    _editingFigureBefore = null;
    _editingFigureVisible = true;
  }

  void _restoreEditedFigure() {
    final before = _editingFigureBefore;
    final index = _editingFigureIndex;
    if (before == null) return;
    setState(() {
      _document = before;
      _selectedFigureIndex = index;
      _clearDraftState();
      _clearEditingState();
    });
    _calculatePayload();
  }

  void _updateStyle(
    VoidCallback update, {
    bool recordUndo = true,
  }) {
    final index = _selectedFigureIndex;
    if (index == null || index >= _document.figures.length) {
      setState(update);
      return;
    }
    final before = _document;
    setState(() {
      update();
      final figures = [..._document.figures];
      figures[index] = figures[index].withStyle(_currentStyle());
      _document = _document.copyWith(figures: figures);
    });
    if (recordUndo) _recordUndo(before);
    _calculatePayload();
  }

  void _beginStyleDrag() {
    final index = _selectedFigureIndex;
    _styleDragBefore = index != null && index < _document.figures.length
        ? _document
        : null;
  }

  void _endStyleDrag() {
    final before = _styleDragBefore;
    _styleDragBefore = null;
    if (before == null || identical(before, _document)) return;
    _recordUndo(before);
  }

  void _recordUndo(MCOImageV4Document before) {
    _undo.add(before);
    if (_undo.length > _historyLimit) _undo.removeAt(0);
    _redo.clear();
  }

  void _setSelectedClosed(bool closed) {
    final index = _selectedFigureIndex;
    if (index == null) return;
    final figures = [..._document.figures];
    final figure = figures[index];
    figures[index] = switch (figure) {
      MCOImageV4Path(:final points, :final style, :final visible) =>
        MCOImageV4Path(
          points: points,
          closed: closed,
          style: style,
          visible: visible,
        ),
      MCOImageV4Wave(
        :final start,
        :final end,
        :final depth,
        :final style,
        :final visible,
      ) => MCOImageV4Wave(
          start: start,
          end: end,
          depth: depth,
          closed: closed,
          style: style,
          visible: visible,
        ),
      _ => figure,
    };
    _commit(_document.copyWith(figures: figures));
  }

  void _toggleVisibility(int index) {
    final figures = [..._document.figures];
    figures[index] = figures[index].withVisibility(!figures[index].visible);
    _commit(_document.copyWith(figures: figures));
  }

  void _deleteFigure(int index) {
    final nextGroupSelectionIndexes = _groupSelectionIndexes
        .where((value) => value != index)
        .map((value) => value > index ? value - 1 : value)
        .toSet();
    final figures = [..._document.figures]..removeAt(index);
    _selectedFigureIndex = null;
    _appendGroupIndex = null;
    _groupSelectionIndexes
      ..clear()
      ..addAll(nextGroupSelectionIndexes);
    _commit(_document.copyWith(figures: figures));
  }

  void _reorder(int from, int to) {
    final figures = [..._document.figures];
    final figure = figures.removeAt(from);
    figures.insert(to, figure);
    _selectedFigureIndex = to;
    _appendGroupIndex = null;
    _groupSelectionIndexes.clear();
    _groupSelectionMode = false;
    _commit(_document.copyWith(figures: figures));
  }

  void _normalizeGroupState() {
    _groupSelectionIndexes.removeWhere(
      (index) => index < 0 || index >= _document.figures.length,
    );
    final appendIndex = _appendGroupIndex;
    if (appendIndex == null) return;
    if (appendIndex < 0 ||
        appendIndex >= _document.figures.length ||
        _document.figures[appendIndex] is! MCOImageV4Group) {
      _appendGroupIndex = null;
    }
  }

  void _toggleGroupSelectionMode() {
    setState(() {
      _groupSelectionMode = !_groupSelectionMode;
      if (_groupSelectionMode) {
        _appendGroupIndex = null;
        final selected = _selectedFigureIndex;
        _groupSelectionIndexes
          ..clear()
          ..addAll(
            selected != null &&
                    selected >= 0 &&
                    selected < _document.figures.length
                ? <int>[selected]
                : const <int>[],
          );
      } else {
        _groupSelectionIndexes.clear();
      }
    });
  }

  void _cancelGroupSelection() {
    setState(() {
      _groupSelectionMode = false;
      _groupSelectionIndexes.clear();
    });
  }

  void _setFigureCheckedForGroup(int index, bool selected) {
    setState(() {
      if (selected) {
        _groupSelectionIndexes.add(index);
      } else {
        _groupSelectionIndexes.remove(index);
      }
    });
  }

  void _toggleFigureCheckedForGroup(int index) {
    _setFigureCheckedForGroup(
      index,
      !_groupSelectionIndexes.contains(index),
    );
  }

  bool get _canMergeCheckedFigures =>
      _validGroupSelectionIndexes().length >= 2;

  List<int> _validGroupSelectionIndexes() {
    final indexes = _groupSelectionIndexes
        .where((index) => index >= 0 && index < _document.figures.length)
        .toList();
    indexes.sort();
    return indexes;
  }

  void _mergeCheckedFigures() {
    final selectedIndexes = _validGroupSelectionIndexes();
    if (selectedIndexes.length < 2) return;
    final selectedSet = selectedIndexes.toSet();
    final insertIndex = selectedIndexes.first;
    final groupFigures = <MCOImageV4Figure>[];
    var groupVisible = false;
    for (final index in selectedIndexes) {
      final figure = _document.figures[index];
      groupVisible = groupVisible || figure.visible;
      if (figure is MCOImageV4Group) {
        groupFigures.addAll(figure.figures);
      } else {
        groupFigures.add(figure);
      }
    }
    final figures = <MCOImageV4Figure>[];
    for (var index = 0; index < _document.figures.length; index++) {
      if (index == insertIndex) {
        figures.add(
          MCOImageV4Group(
            figures: groupFigures,
            visible: groupVisible,
          ),
        );
      }
      if (!selectedSet.contains(index)) {
        figures.add(_document.figures[index]);
      }
    }
    _commit(_document.copyWith(figures: figures));
    setState(() {
      _tool = _V4Tool.select;
      _selectedFigureIndex = insertIndex;
      _groupSelectionMode = false;
      _groupSelectionIndexes.clear();
      _appendGroupIndex = null;
      _clearDraftState();
    });
  }

  void _toggleAppendToSelectedGroup() {
    final index = _selectedFigureIndex;
    if (index == null ||
        index < 0 ||
        index >= _document.figures.length ||
        _document.figures[index] is! MCOImageV4Group) {
      return;
    }
    setState(() {
      _groupSelectionMode = false;
      _groupSelectionIndexes.clear();
      _appendGroupIndex = _appendGroupIndex == index ? null : index;
      _tool = _V4Tool.select;
    });
  }

  void _setBackground(int? color) {
    if (_document.backgroundColor == color) return;
    _commit(_document.copyWith(backgroundColor: color));
  }

  void _trimCanvas() {
    Rect? bounds;
    for (final figure in _document.figures.where((figure) => figure.visible)) {
      final figureBounds = MCOImageV4Painter.figureLogicalBounds(figure)
          .intersect(
            Rect.fromLTWH(
              0,
              0,
              _document.width.toDouble(),
              _document.height.toDouble(),
            ),
          );
      if (figureBounds.isEmpty) continue;
      bounds = bounds == null
          ? figureBounds
          : bounds.expandToInclude(figureBounds);
    }
    final trimBounds = bounds;
    if (trimBounds == null) return;

    final minX = trimBounds.left.floor().clamp(0, _document.width - 1).toInt();
    final minY = trimBounds.top.floor().clamp(0, _document.height - 1).toInt();
    final maxX = (trimBounds.right.ceil() - 1)
        .clamp(minX, _document.width - 1)
        .toInt();
    final maxY = (trimBounds.bottom.ceil() - 1)
        .clamp(minY, _document.height - 1)
        .toInt();
    final width = maxX - minX + 1;
    final height = maxY - minY + 1;
    if (width == _document.width && height == _document.height) return;

    _selectedFigureIndex = null;
    _appendGroupIndex = null;
    _groupSelectionMode = false;
    _groupSelectionIndexes.clear();
    _commit(
      _document.copyWith(
        width: width,
        height: height,
        figures: _document.figures
            .map((figure) => figure.translated(-minX, -minY))
            .toList(),
      ),
    );
  }

  void _commit(MCOImageV4Document next) {
    _undo.add(_document);
    if (_undo.length > _historyLimit) _undo.removeAt(0);
    _redo.clear();
    setState(() {
      _document = next;
      _clearDraftState();
      _clearEditingState();
      _normalizeGroupState();
    });
    _calculatePayload();
  }

  void _undoChange() {
    if (_shapePoints.isNotEmpty) {
      setState(() => _shapeRedoPoints.add(_shapePoints.removeLast()));
      return;
    }
    if (_editingFigureBefore != null) {
      _restoreEditedFigure();
      return;
    }
    if (_undo.isEmpty) return;
    _redo.add(_document);
    setState(() {
      _document = _undo.removeLast();
      _selectedFigureIndex = null;
      _clearDraftState();
      _clearEditingState();
      _normalizeGroupState();
    });
    _calculatePayload();
  }

  void _redoChange() {
    if (_shapeRedoPoints.isNotEmpty) {
      setState(() => _shapePoints.add(_shapeRedoPoints.removeLast()));
      return;
    }
    if (_editingFigureBefore != null) return;
    if (_redo.isEmpty) return;
    _undo.add(_document);
    setState(() {
      _document = _redo.removeLast();
      _selectedFigureIndex = null;
      _clearDraftState();
      _clearEditingState();
      _normalizeGroupState();
    });
    _calculatePayload();
  }

  void _calculatePayload() {
    try {
      final encoded = _codec.encode(
        _document,
        nonce: 0,
        targetName: widget.replyTargetName,
        replyTimestamp: widget.replyTimestamp,
      );
      if (!mounted) return;
      setState(() {
        _encoded = encoded;
        _encodeError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _encoded = null;
        _encodeError = error;
      });
    }
  }

  void _send() {
    final encoded = _codec.encode(
      _document,
      targetName: widget.replyTargetName,
      replyTimestamp: widget.replyTimestamp,
    );
    final text = _codec.textFromBody(encoded.body);
    Navigator.pop(
      context,
      CanvasEditorResult.fromV4(text: text, encoded: encoded),
    );
  }

  Future<void> _cancel() async {
    await _showGridSave;
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _openAsRasterV3() async {
    try {
      final image = await _rasterizeForV3();
      await _showGridSave;
      if (!mounted) return;
      Navigator.pop(context, CanvasEditorResult.fromRasterImage(image));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _encodeError = error);
    }
  }

  Future<MCOImage> _rasterizeForV3() async {
    final width = _document.width;
    final height = _document.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    MCOImageV4Painter(_document, antiAlias: false).paint(
      canvas,
      Size(width.toDouble(), height.toDouble()),
    );
    final rendered = await recorder.endRecording().toImage(width, height);
    try {
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) {
        throw StateError('Cannot rasterize MCOimg v4 document');
      }
      final rgba = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final paletteValues = _rasterPaletteValues(_document.paletteProfile);
      final white = MCOImagePalette.whiteIndexFor(_document.paletteProfile);
      final pixels = List<int>.filled(width * height, white);
      final transparentPixels = <int>[];
      final used = <int>{};
      for (var i = 0; i < width * height; i++) {
        final offset = i * 4;
        final alpha = rgba[offset + 3];
        if (alpha < 128) {
          transparentPixels.add(i);
          continue;
        }
        final color = _nearestRasterColorValue(
          rgba[offset],
          rgba[offset + 1],
          rgba[offset + 2],
          _document.paletteProfile,
          paletteValues,
        );
        pixels[i] = color;
        used.add(color);
      }

      int? transparentColor;
      if (transparentPixels.isNotEmpty) {
        for (final color in paletteValues) {
          if (!used.contains(color)) {
            transparentColor = color;
            break;
          }
        }
        if (transparentColor != null) {
          for (final index in transparentPixels) {
            pixels[index] = transparentColor;
          }
        }
      }

      return MCOImage(
        width: width,
        height: height,
        paletteProfile: _document.paletteProfile,
        pixels: pixels,
        transparentColor: transparentColor,
        encodingVersion: MCOImageEncodingVersion.v3,
      );
    } finally {
      rendered.dispose();
    }
  }

  MCOImageV4Style _currentStyle() => MCOImageV4Style(
        fillColor: _fillEnabled ? _fillColor : null,
        strokeColor: _strokeEnabled ? _strokeColor : null,
        strokeWidth: _strokeWidth,
      );

  MCOImageV4Point _gridPoint(
    Offset position,
    Size size, {
    bool clampToCanvas = true,
  }) {
    final rawX = (position.dx / size.width * _document.width).floor();
    final rawY = (position.dy / size.height * _document.height).floor();
    final x = clampToCanvas
        ? rawX.clamp(0, _document.width - 1).toInt()
        : rawX;
    final y = clampToCanvas
        ? rawY.clamp(0, _document.height - 1).toInt()
        : rawY;
    return MCOImageV4Point(x, y);
  }

  int? _hitTest(MCOImageV4Point point) {
    final logical = Offset(point.x + 0.5, point.y + 0.5);
    for (var i = _document.figures.length - 1; i >= 0; i--) {
      final figure = _document.figures[i];
      if (figure.visible &&
          MCOImageV4Painter.figureLogicalBounds(figure)
              .inflate(1)
              .contains(logical)) {
        return i;
      }
    }
    return null;
  }

  int? _selectedFigureIndexOutsideCanvas() {
    final index = _selectedFigureIndex;
    if (index == null || index >= _document.figures.length) return null;
    final figure = _document.figures[index];
    if (!figure.visible) return null;
    final canvasBounds = Rect.fromLTWH(
      0,
      0,
      _document.width.toDouble(),
      _document.height.toDouble(),
    );
    return MCOImageV4Painter.figureLogicalBounds(figure)
            .overlaps(canvasBounds)
        ? null
        : index;
  }

  List<MCOImageV4Point> _simplifyPoints(List<MCOImageV4Point> input) {
    final unique = <MCOImageV4Point>[];
    for (final point in input) {
      if (unique.isEmpty || unique.last != point) unique.add(point);
    }
    if (unique.length < 3) return unique;
    final gridSize = math.max(_document.width, _document.height);
    if (gridSize < _pencilSimplifyMinGridSize) return unique;
    final tolerance = gridSize < _pencilSimplifyMidGridSize
        ? _pencilSimplifySmallTolerance
        : math.max(
            _pencilSimplifyMinTolerance,
            gridSize / _pencilSimplifyBaseGridSize,
          );
    final reduced = _rdp(unique, tolerance);
    var changed = true;
    while (changed && reduced.length >= 3) {
      changed = false;
      for (var i = 1; i < reduced.length - 1; i++) {
        final a = reduced[i - 1];
        final b = reduced[i];
        final c = reduced[i + 1];
        if ((b.x - a.x) * (c.y - b.y) ==
            (b.y - a.y) * (c.x - b.x)) {
          reduced.removeAt(i);
          changed = true;
          break;
        }
      }
    }
    return reduced;
  }

  List<MCOImageV4Point> _rdp(List<MCOImageV4Point> points, double epsilon) {
    if (points.length < 3) return [...points];
    var maxDistance = 0.0;
    var index = 0;
    for (var i = 1; i < points.length - 1; i++) {
      final distance = _segmentDistance(points[i], points.first, points.last);
      if (distance > maxDistance) {
        maxDistance = distance;
        index = i;
      }
    }
    if (maxDistance <= epsilon) return [points.first, points.last];
    final left = _rdp(points.sublist(0, index + 1), epsilon);
    final right = _rdp(points.sublist(index), epsilon);
    return [...left.take(left.length - 1), ...right];
  }

  double _segmentDistance(
    MCOImageV4Point point,
    MCOImageV4Point start,
    MCOImageV4Point end,
  ) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    if (dx == 0 && dy == 0) {
      return math.sqrt(
        math.pow(point.x - start.x, 2) + math.pow(point.y - start.y, 2),
      );
    }
    return ((dy * point.x - dx * point.y + end.x * start.y -
                end.y * start.x)
            .abs()) /
        math.sqrt(dx * dx + dy * dy);
  }

  MCOImageV4Document _rescaleDocument(
    MCOImageV4Document source,
    int width,
    int height,
    List<int> palette,
    PaletteProfile paletteProfile,
  ) {
    int x(int value) => (value * width / source.width)
        .round()
        .clamp(0, width - 1)
        .toInt();
    int y(int value) => (value * height / source.height)
        .round()
        .clamp(0, height - 1)
        .toInt();
    final scale = math.min(width / source.width, height / source.height);
    int scalar(int value) => math.max(1, (value * scale).round());

    List<int> scalePixels(
      List<int> sourcePixels,
      int sourceWidth,
      int sourceHeight,
      int targetWidth,
      int targetHeight,
    ) {
      if (sourceWidth == targetWidth && sourceHeight == targetHeight) {
        return sourcePixels;
      }
      return List<int>.generate(targetWidth * targetHeight, (index) {
        final targetX = index % targetWidth;
        final targetY = index ~/ targetWidth;
        final sourceX = ((targetX + 0.5) * sourceWidth / targetWidth)
            .floor()
            .clamp(0, sourceWidth - 1)
            .toInt();
        final sourceY = ((targetY + 0.5) * sourceHeight / targetHeight)
            .floor()
            .clamp(0, sourceHeight - 1)
            .toInt();
        return sourcePixels[sourceY * sourceWidth + sourceX];
      }, growable: false);
    }

    MCOImageV4RasterLayer rescaleRasterLayer(MCOImageV4RasterLayer layer) {
      final nextWidth = math.max(1, (layer.width * scale).round());
      final nextHeight = math.max(1, (layer.height * scale).round());
      return MCOImageV4RasterLayer(
        x: (layer.x * width / source.width).round(),
        y: (layer.y * height / source.height).round(),
        width: nextWidth,
        height: nextHeight,
        pixels: scalePixels(
          layer.pixels,
          layer.width,
          layer.height,
          nextWidth,
          nextHeight,
        ),
        transparentColor: layer.transparentColor,
        visible: layer.visible,
      );
    }

    MCOImageV4Figure convert(MCOImageV4Figure figure) {
      final style = figure.style.copyWith(
        fillColor: _remapColor(
          figure.style.fillColor,
          source.palette,
          source.paletteProfile,
          palette,
          paletteProfile,
        ),
        strokeColor: _remapColor(
          figure.style.strokeColor,
          source.palette,
          source.paletteProfile,
          palette,
          paletteProfile,
        ),
        strokeWidth: scalar(figure.style.strokeWidth),
      );
      return switch (figure) {
        MCOImageV4Dot(:final point) => MCOImageV4Dot(
            point: MCOImageV4Point(x(point.x), y(point.y)),
            style: style,
            visible: figure.visible,
          ),
        MCOImageV4Line(:final start, :final end) => MCOImageV4Line(
            start: MCOImageV4Point(x(start.x), y(start.y)),
            end: MCOImageV4Point(x(end.x), y(end.y)),
            style: style,
            visible: figure.visible,
          ),
        MCOImageV4Rect() => _rescaleArea(
            figure,
            source.width,
            source.height,
            width,
            height,
            style,
            false,
          ),
        MCOImageV4Ellipse() => _rescaleArea(
            figure,
            source.width,
            source.height,
            width,
            height,
            style,
            true,
          ),
        MCOImageV4Path(:final points, :final closed) => MCOImageV4Path(
            points: points
                .map((point) => MCOImageV4Point(x(point.x), y(point.y)))
                .toList(),
            closed: closed,
            style: style,
            visible: figure.visible,
          ),
        MCOImageV4Group(:final figures) => MCOImageV4Group(
            figures: figures.map(convert).toList(growable: false),
            style: style,
            visible: figure.visible,
          ),
        MCOImageV4Wave(
          :final start,
          :final end,
          :final depth,
          :final closed,
        ) => MCOImageV4Wave(
            start: MCOImageV4Point(x(start.x), y(start.y)),
            end: MCOImageV4Point(x(end.x), y(end.y)),
            depth: depth.sign * scalar(depth.abs()),
            closed: closed,
            style: style,
            visible: figure.visible,
          ),
        MCOImageV4RasterLayer() && final layer => rescaleRasterLayer(layer),
      };
    }

    return MCOImageV4Document(
      width: width,
      height: height,
      paletteProfile: paletteProfile,
      palette: palette,
      backgroundColor: _remapColor(
        source.backgroundColor,
        source.palette,
        source.paletteProfile,
        palette,
        paletteProfile,
      ),
      initialStyle: source.initialStyle.copyWith(
        fillColor: _remapColor(
          source.initialStyle.fillColor,
          source.palette,
          source.paletteProfile,
          palette,
          paletteProfile,
        ),
        strokeColor: _remapColor(
          source.initialStyle.strokeColor,
          source.palette,
          source.paletteProfile,
          palette,
          paletteProfile,
        ),
        strokeWidth: scalar(source.initialStyle.strokeWidth),
      ),
      figures: source.figures.map(convert).toList(),
    );
  }

  MCOImageV4Figure _rescaleArea(
    MCOImageV4AreaFigure figure,
    int sourceWidth,
    int sourceHeight,
    int canvasWidth,
    int canvasHeight,
    MCOImageV4Style style,
    bool ellipse,
  ) {
    MCOImageV4Point point(MCOImageV4Point value) => MCOImageV4Point(
          (value.x * canvasWidth / sourceWidth)
              .round()
              .clamp(0, canvasWidth - 1)
              .toInt(),
          (value.y * canvasHeight / sourceHeight)
              .round()
              .clamp(0, canvasHeight - 1)
              .toInt(),
        );
    return ellipse
        ? MCOImageV4Ellipse(
            first: point(figure.first),
            second: point(figure.second),
            third: point(figure.third),
            style: style,
            visible: figure.visible,
          )
        : MCOImageV4Rect(
            first: point(figure.first),
            second: point(figure.second),
            third: point(figure.third),
            style: style,
            visible: figure.visible,
          );
  }

  int? _remapColor(
    int? value,
    List<int> oldPalette,
    PaletteProfile oldProfile,
    List<int> newPalette,
    PaletteProfile newProfile,
  ) {
    if (value == null) return null;
    final wanted = _profileColor(oldProfile, oldPalette[value]);
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < newPalette.length; i++) {
      final candidate = _profileColor(newProfile, newPalette[i]);
      final wantedArgb = wanted.toARGB32();
      final candidateArgb = candidate.toARGB32();
      final dr = ((wantedArgb >> 16) & 0xff) -
          ((candidateArgb >> 16) & 0xff);
      final dg = ((wantedArgb >> 8) & 0xff) -
          ((candidateArgb >> 8) & 0xff);
      final db = (wantedArgb & 0xff) - (candidateArgb & 0xff);
      final distance = (dr * dr + dg * dg + db * db).toDouble();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  static MCOImageV4Document _newDocument(
    int width,
    int height,
    PaletteProfile profile,
  ) {
    final palette = _documentPaletteFor(profile);
    final blackValue = profile.isDynamic
        ? MCOImageDynamicPalette.blackGlobalIndexFor(profile)
        : MCOImagePalette.blackIndexFor(profile);
    final whiteValue = profile.isDynamic
        ? MCOImageDynamicPalette.whiteGlobalIndexFor(profile)
        : MCOImagePalette.whiteIndexFor(profile);
    final black = palette.indexOf(blackValue);
    final white = palette.indexOf(whiteValue);
    return MCOImageV4Document(
      width: width,
      height: height,
      paletteProfile: profile,
      palette: palette,
      backgroundColor: white >= 0 ? white : null,
      initialStyle: MCOImageV4Style(
        strokeColor: black >= 0 ? black : palette.length - 1,
      ),
      figures: const [],
    );
  }

  static List<int> _documentPaletteFor(PaletteProfile profile) {
    if (!profile.isDynamic) {
      return List<int>.generate(
        MCOImagePalette.colorsFor(profile).length,
        (index) => index,
        growable: false,
      );
    }
    final colors = MCOImageDynamicPalette.indicesFor(profile);
    if (colors.length <= 64) return List<int>.of(colors, growable: false);
    return <int>[
      MCOImageDynamicPalette.whiteGlobalIndexFor(profile),
      MCOImageDynamicPalette.blackGlobalIndexFor(profile),
    ];
  }

  List<int> _paletteForProfileChange(PaletteProfile profile) {
    final base = _documentPaletteFor(profile);
    if (!profile.isDynamic ||
        MCOImageDynamicPalette.indicesFor(profile).length <= 64) {
      return base;
    }
    final available = MCOImageDynamicPalette.indicesFor(profile);
    final result = List<int>.of(base);
    for (final oldValue in _document.palette) {
      final wanted = _profileColor(_document.paletteProfile, oldValue);
      var nearest = available.first;
      var bestDistance = 1 << 62;
      final wantedArgb = wanted.toARGB32();
      for (final candidate in available) {
        final candidateArgb =
            MCOImageDynamicPalette.global512[candidate].toARGB32();
        final dr = ((wantedArgb >> 16) & 0xff) -
            ((candidateArgb >> 16) & 0xff);
        final dg = ((wantedArgb >> 8) & 0xff) -
            ((candidateArgb >> 8) & 0xff);
        final db = (wantedArgb & 0xff) - (candidateArgb & 0xff);
        final distance = dr * dr + dg * dg + db * db;
        if (distance < bestDistance) {
          bestDistance = distance;
          nearest = candidate;
        }
      }
      if (!result.contains(nearest)) result.add(nearest);
      if (result.length == 64) break;
    }
    return result;
  }

  static Color _profileColor(PaletteProfile profile, int color) {
    return profile.isDynamic
        ? MCOImageDynamicPalette.global512[color]
        : MCOImagePalette.colorsFor(profile)[color];
  }

  static List<int> _rasterPaletteValues(PaletteProfile profile) {
    if (profile.isDynamic) {
      return List<int>.of(MCOImageDynamicPalette.indicesFor(profile));
    }
    return List<int>.generate(
      MCOImagePalette.colorsFor(profile).length,
      (index) => index,
      growable: false,
    );
  }

  static int _nearestRasterColorValue(
    int red,
    int green,
    int blue,
    PaletteProfile profile,
    List<int> paletteValues,
  ) {
    var best = paletteValues.first;
    var bestDistance = 1 << 62;
    for (final value in paletteValues) {
      final argb = _profileColor(profile, value).toARGB32();
      final dr = red - ((argb >> 16) & 0xff);
      final dg = green - ((argb >> 8) & 0xff);
      final db = blue - (argb & 0xff);
      final distance = dr * dr + dg * dg + db * db;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = value;
      }
    }
    return best;
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String _figureLabel(MCOImageV4Figure figure) => switch (figure) {
        MCOImageV4Dot() => context.l10n.chat_canvasV4ToolDot,
        MCOImageV4Line() => context.l10n.chat_canvasV4ToolLine,
        MCOImageV4Rect() => context.l10n.chat_canvasV4ToolRect,
        MCOImageV4Ellipse() => context.l10n.chat_canvasV4ToolEllipse,
        MCOImageV4Path() => context.l10n.chat_canvasV4ToolPolyline,
        MCOImageV4Wave() => context.l10n.chat_canvasV4ToolWave,
        MCOImageV4Group() => 'Группа',
        MCOImageV4RasterLayer() => 'Растр',
      };
}

class _TransparentColorSwatch extends StatelessWidget {
  final bool selected;

  const _TransparentColorSwatch({required this.selected});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: const Size(34, 34),
      painter: _AlphaSwatchPainter(
        borderColor: selected ? colorScheme.primary : colorScheme.outline,
        selected: selected,
      ),
    );
  }
}

class _V4FigurePreview extends StatelessWidget {
  final MCOImageV4Document document;
  final MCOImageV4Figure figure;
  final bool selected;

  const _V4FigurePreview({
    required this.document,
    required this.figure,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final previewFigure = figure.withVisibility(true);
    final bounds = MCOImageV4Painter.figureLogicalBounds(previewFigure);
    final longestSide = math.max(bounds.width, bounds.height);
    final padding = math.max(1.0, longestSide * 0.18);
    final viewport = bounds.inflate(padding);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: CustomPaint(
          painter: MCOImageV4Painter(
            document.copyWith(
              figures: [previewFigure],
            ),
            logicalViewport: viewport,
          ),
        ),
      ),
    );
  }
}

class _AlphaSwatchPainter extends CustomPainter {
  final Color borderColor;
  final bool selected;

  const _AlphaSwatchPainter({
    required this.borderColor,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = BorderRadius.circular(4).toRRect(rect);
    canvas.save();
    canvas.clipRRect(radius);

    final paints = [
      Paint()..color = const Color(0xffffffff),
      Paint()..color = const Color(0xffd6d6d6),
    ];
    final halfWidth = size.width / 2;
    final halfHeight = size.height / 2;
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 2; x++) {
        canvas.drawRect(
          Rect.fromLTWH(
            x * halfWidth,
            y * halfHeight,
            halfWidth,
            halfHeight,
          ),
          paints[(x + y) & 1],
        );
      }
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
  bool shouldRepaint(_AlphaSwatchPainter oldDelegate) =>
      oldDelegate.borderColor != borderColor ||
      oldDelegate.selected != selected;
}

class _V4CanvasSetupDialog extends StatefulWidget {
  final int width;
  final int height;
  final PaletteProfile profile;

  const _V4CanvasSetupDialog({
    required this.width,
    required this.height,
    required this.profile,
  });

  @override
  State<_V4CanvasSetupDialog> createState() =>
      _V4CanvasSetupDialogState();
}

class _V4CanvasSetupDialogState extends State<_V4CanvasSetupDialog> {
  static const _maxCanvasSize = 256;
  static const _profiles = <PaletteProfile>[
    PaletteProfile.mono,
    PaletteProfile.master4,
    PaletteProfile.master8,
    PaletteProfile.grayscale8,
    PaletteProfile.master16,
    PaletteProfile.grayscale16,
    PaletteProfile.master32,
    PaletteProfile.grayscale32,
    PaletteProfile.master64,
    PaletteProfile.dynamicGlobal8,
    PaletteProfile.dynamicGlobal16,
    PaletteProfile.dynamicGlobal32,
    PaletteProfile.dynamicGlobal64,
    PaletteProfile.dynamicGlobal128,
    PaletteProfile.dynamicGlobal256,
    PaletteProfile.dynamicGlobal512,
  ];

  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late PaletteProfile _profile;
  bool _invalidSize = false;

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController(text: '${widget.width}');
    _heightController = TextEditingController(text: '${widget.height}');
    _profile = widget.profile;
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.chat_canvasV4CanvasSettings),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.chat_canvasV4GridDescription),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _widthController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.l10n.chat_canvasWidth,
                      errorText: _invalidSize
                          ? context.l10n.chat_canvasV4InvalidSize
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _heightController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.l10n.chat_canvasHeight,
                      errorText: _invalidSize
                          ? context.l10n.chat_canvasV4InvalidSize
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PaletteProfile>(
              initialValue: _profile,
              decoration: InputDecoration(
                labelText: context.l10n.chat_canvasPaletteMode,
              ),
              items: [
                for (final profile in _profiles)
                  DropdownMenuItem(
                    value: profile,
                    child: Text(_v4PaletteLabel(profile)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _profile = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.common_cancel),
        ),
        FilledButton(
          onPressed: _apply,
          child: Text(context.l10n.common_apply),
        ),
      ],
    );
  }

  void _apply() {
    final widthText = _widthController.text.trim();
    final heightText = _heightController.text.trim();
    var width = int.tryParse(widthText);
    var height = int.tryParse(heightText);
    if (widthText.isEmpty && height != null) {
      width = math.max(1, (height * widget.width / widget.height).round());
    } else if (heightText.isEmpty && width != null) {
      height = math.max(1, (width * widget.height / widget.width).round());
    }
    if (width == null ||
        height == null ||
        width < 1 ||
        height < 1 ||
        width > _maxCanvasSize ||
        height > _maxCanvasSize) {
      setState(() => _invalidSize = true);
      return;
    }
    Navigator.pop(context, (width, height, _profile));
  }
}

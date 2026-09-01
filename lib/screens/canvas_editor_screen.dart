import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../helpers/cancellable_compute.dart';
import '../helpers/channel_binary_data_helper.dart';
import '../helpers/channel_app_data_helper.dart';
import '../helpers/mco_image_file_saver.dart';
import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_palette.dart';
import '../helpers/mcoimg_v3_codec.dart';
import '../helpers/mcoimg_v4_codec.dart';
import '../helpers/mcoimg_v4_model.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../services/app_settings_service.dart';
import '../storage/prefs_manager.dart';
import '../utils/platform_info.dart';
import '../widgets/mco_image_v4_view.dart';
import '../models/canvas_editor_result.dart';
import 'mco_image_v4_editor_screen.dart';

export '../models/canvas_editor_result.dart';

enum _CanvasTool {
  select,
  dot,
  pencil,
  fill,
  eyedropper,
  line,
  polyline,
  oval,
  rectangle,
  wave,
}

enum _PaletteSelectorValue { dynamic }

enum _EncodingSelectorAction { separateV4 }

enum _V4ColorTarget { fill, stroke }

class _CanvasSnapshot {
  final int width;
  final int height;
  final PaletteProfile paletteProfile;
  final PaletteProfile dynamicPaletteProfile;
  final MCOImageEncodingVersion encodingVersion;
  final int selectedColor;
  final int? transparentColor;
  final List<int> pixels;
  final MCOImageV4Document? vectorDocument;
  final List<int>? vectorReferencePixels;
  final PaletteProfile? vectorReferencePaletteProfile;
  final int? vectorReferenceTransparentColor;
  final bool vectorReferenceVisible;

  _CanvasSnapshot({
    required this.width,
    required this.height,
    required this.paletteProfile,
    required this.dynamicPaletteProfile,
    required this.encodingVersion,
    required this.selectedColor,
    required this.transparentColor,
    required List<int> pixels,
    this.vectorDocument,
    List<int>? vectorReferencePixels,
    this.vectorReferencePaletteProfile,
    this.vectorReferenceTransparentColor,
    required this.vectorReferenceVisible,
  }) : pixels = List<int>.unmodifiable(pixels),
       vectorReferencePixels = vectorReferencePixels == null
           ? null
           : List<int>.unmodifiable(vectorReferencePixels);
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

class _MCOImageEncodeRequest {
  final int width;
  final int height;
  final PaletteProfile paletteProfile;
  final List<int> pixels;
  final int? transparentColor;
  final MCOImageEncodingVersion encodingVersion;
  final int backgroundColor;
  final MCOImageOutputTarget outputTarget;
  final int compressionLevel;
  final List<MCOImageBackgroundCandidate>? backgroundCandidates;
  final List<ScanMode>? scanModes;
  final bool includeNonScanCandidates;

  _MCOImageEncodeRequest({
    required this.width,
    required this.height,
    required this.paletteProfile,
    required List<int> pixels,
    required this.transparentColor,
    required this.encodingVersion,
    required this.backgroundColor,
    required this.outputTarget,
    required this.compressionLevel,
    this.backgroundCandidates,
    this.scanModes,
    this.includeNonScanCandidates = true,
  }) : pixels = List<int>.unmodifiable(pixels);
}

class _MCOImageEncodeCacheKey {
  final int width;
  final int height;
  final PaletteProfile paletteProfile;
  final List<int> pixels;
  final int? transparentColor;
  final MCOImageEncodingVersion encodingVersion;
  final int backgroundColor;
  final MCOImageOutputTarget outputTarget;
  final int compressionLevel;

  _MCOImageEncodeCacheKey._({
    required this.width,
    required this.height,
    required this.paletteProfile,
    required this.pixels,
    required this.transparentColor,
    required this.encodingVersion,
    required this.backgroundColor,
    required this.outputTarget,
    required this.compressionLevel,
  });

  factory _MCOImageEncodeCacheKey.fromRequest(_MCOImageEncodeRequest request) {
    return _MCOImageEncodeCacheKey._(
      width: request.width,
      height: request.height,
      paletteProfile: request.paletteProfile,
      pixels: List<int>.unmodifiable(request.pixels),
      transparentColor: request.transparentColor,
      encodingVersion: request.encodingVersion,
      backgroundColor: request.backgroundColor,
      outputTarget: request.outputTarget,
      compressionLevel: request.compressionLevel,
    );
  }

  bool matches(_MCOImageEncodeRequest request) {
    return width == request.width &&
        height == request.height &&
        paletteProfile == request.paletteProfile &&
        transparentColor == request.transparentColor &&
        encodingVersion == request.encodingVersion &&
        backgroundColor == request.backgroundColor &&
        outputTarget == request.outputTarget &&
        compressionLevel == request.compressionLevel &&
        listEquals(pixels, request.pixels);
  }
}

class _ImportedMcoBinary {
  final MCOImage image;
  final EncodedMCOImage encoded;

  const _ImportedMcoBinary({required this.image, required this.encoded});
}

class _ExtremeEncodeSlice {
  final _MCOImageEncodeRequest request;
  final String label;

  const _ExtremeEncodeSlice({required this.request, required this.label});
}

@pragma('vm:entry-point')
EncodedMCOImage _encodeMCOImageRequest(_MCOImageEncodeRequest request) {
  final image = MCOImage(
    width: request.width,
    height: request.height,
    paletteProfile: request.paletteProfile,
    pixels: request.pixels,
    transparentColor: request.transparentColor,
    encodingVersion: request.encodingVersion,
  );
  if (request.encodingVersion == MCOImageEncodingVersion.v3) {
    return MCOImageV3Codec()
        .encode(
          image,
          backgroundColor: request.backgroundColor,
          backgroundCandidates: request.backgroundCandidates,
          scanModes: request.scanModes,
          includeNonScanCandidates: request.includeNonScanCandidates,
          compressionLevel: request.compressionLevel,
        )
        .encodedCandidate;
  }
  return MCOImageCodec().encode(
    image,
    backgroundColor: request.backgroundColor,
    backgroundCandidates: request.backgroundCandidates,
    scanModes: request.scanModes,
    includeNonScanCandidates: request.includeNonScanCandidates,
    encodingVersion: request.encodingVersion,
    outputTarget: request.outputTarget,
    compressionLevel: request.compressionLevel,
  );
}

@pragma('vm:entry-point')
MCOImageEncodeDiagnostics _debugEncodeMCOImageRequest(
  _MCOImageEncodeRequest request,
) {
  final image = MCOImage(
    width: request.width,
    height: request.height,
    paletteProfile: request.paletteProfile,
    pixels: request.pixels,
    transparentColor: request.transparentColor,
    encodingVersion: request.encodingVersion,
  );
  if (request.encodingVersion == MCOImageEncodingVersion.v3) {
    return MCOImageV3Codec().debugEncode(
      image,
      backgroundColor: request.backgroundColor,
      backgroundCandidates: request.backgroundCandidates,
      scanModes: request.scanModes,
      includeNonScanCandidates: request.includeNonScanCandidates,
      compressionLevel: request.compressionLevel,
    );
  }
  return MCOImageCodec().debugEncode(
    image,
    backgroundColor: request.backgroundColor,
    backgroundCandidates: request.backgroundCandidates,
    scanModes: request.scanModes,
    includeNonScanCandidates: request.includeNonScanCandidates,
    encodingVersion: request.encodingVersion,
    outputTarget: request.outputTarget,
    compressionLevel: request.compressionLevel,
  );
}

MCOImage _imageFromEncodeRequest(_MCOImageEncodeRequest request) {
  return MCOImage(
    width: request.width,
    height: request.height,
    paletteProfile: request.paletteProfile,
    pixels: request.pixels,
    transparentColor: request.transparentColor,
    encodingVersion: request.encodingVersion,
  );
}

_MCOImageEncodeRequest _encodeRequestWithBackgroundCandidates(
  _MCOImageEncodeRequest request,
  List<MCOImageBackgroundCandidate> backgroundCandidates,
  List<ScanMode>? scanModes,
  bool includeNonScanCandidates,
) {
  return _MCOImageEncodeRequest(
    width: request.width,
    height: request.height,
    paletteProfile: request.paletteProfile,
    pixels: request.pixels,
    transparentColor: request.transparentColor,
    encodingVersion: request.encodingVersion,
    backgroundColor: request.backgroundColor,
    outputTarget: request.outputTarget,
    compressionLevel: request.compressionLevel,
    backgroundCandidates: backgroundCandidates,
    scanModes: scanModes,
    includeNonScanCandidates: includeNonScanCandidates,
  );
}

class CanvasEditorScreen extends StatefulWidget {
  final int maxTextChars;
  final int? maxBinaryPayloadBytes;
  final String? binarySenderName;
  final MCOImage? initialImage;
  final Uint8List? initialImageBytes;
  final int? initialImageWidth;
  final int? initialImageHeight;
  final PaletteProfile? initialPaletteProfile;
  final String? replyTargetName;
  final int? replyTimestamp;

  const CanvasEditorScreen({
    super.key,
    required this.maxTextChars,
    this.maxBinaryPayloadBytes,
    this.binarySenderName,
    this.initialImage,
    this.initialImageBytes,
    this.initialImageWidth,
    this.initialImageHeight,
    this.initialPaletteProfile,
    this.replyTargetName,
    this.replyTimestamp,
  });

  @override
  State<CanvasEditorScreen> createState() => _CanvasEditorScreenState();
}

class _CanvasEditorScreenState extends State<CanvasEditorScreen> {
  static const int _minCanvasSize = 2;
  static const int _maxCanvasSizeV1 = 85;
  static const int _maxCanvasSizeV2 = 256;
  static const int _defaultSize = 11;
  static const int _defaultVectorSize = 128;
  // Keep a small text budget for a human-readable image marker around the codec payload.
  static const int _humanReadablePrefixReserveChars = 4;
  // Master64 is the baseline; smaller palettes need fewer bits per cell, so we
  // allow a larger editor grid and still validate the exact encoded payload.
  static const double _master64CellBudgetMultiplier = 4.0;
  static const int _master64BitsPerCell = 6;
  static const Duration _payloadRefreshDebounce = Duration(milliseconds: 1200);
  static const int _mobileExtremeEncodeWorkerLimit = 6;
  static const double _desktopExtremeEncodeCpuShare = 0.85;
  static const String _prefsWidthKey = 'canvas_editor_width';
  static const String _prefsHeightKey = 'canvas_editor_height';
  static const String _prefsPaletteKey = 'canvas_editor_palette';
  static const String _prefsUnlockSizeKey = 'canvas_editor_unlock_size';
  static const String _prefsShowGridKey = 'canvas_editor_show_grid';
  static const String _prefsShowRulerKey = 'canvas_editor_show_ruler';
  static const String _prefsEncodingVersionKey =
      'canvas_editor_encoding_version';
  static const String _prefsCompressionLevelKey =
      'canvas_editor_compression_level';
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
  final _v4Codec = const MCOImageV4Codec();

  int _width = _defaultSize;
  int _height = _defaultSize;
  PaletteProfile _paletteProfile = PaletteProfile.master64;
  PaletteProfile _dynamicPaletteProfile = PaletteProfile.dynamicGlobal512;
  int _selectedColor = MCOImagePalette.blackIndexFor(PaletteProfile.master64);
  int? _transparentColor;
  int _encodingSelectorReset = 0;
  bool _isPickingTransparentColor = false;
  bool _paletteExpanded = true;
  _CanvasTool _selectedTool = _CanvasTool.pencil;
  bool _showGrid = true;
  bool _showRuler = false;
  bool _unlockCanvasSize = false;
  MCOImageEncodingVersion _encodingVersion = MCOImageEncodingVersion.v3;
  int _compressionLevel = MCOImageCodec.defaultCompressionLevel;
  late List<int> _pixels;
  Timer? _payloadRefreshTimer;
  bool _payloadRefreshPending = false;
  bool _payloadRefreshInProgress = false;
  int? _payloadRefreshProgressPercent;
  Stopwatch? _payloadRefreshStopwatch;
  Duration? _payloadRefreshElapsed;
  Timer? _payloadRefreshElapsedTimer;
  int _payloadRefreshRequestId = 0;
  Completer<void>? _payloadRefreshCompletion;
  final Set<CancellableComputeTask<dynamic>> _activeEncodeTasks =
      <CancellableComputeTask<dynamic>>{};
  bool _isDisposed = false;
  bool _isDrawing = false;
  bool _canvasInputLocked = false;
  int? _lineStartIndex;
  int? _ovalFirstIndex;
  int? _ovalSecondIndex;
  int? _rectangleFirstIndex;
  int? _rectangleSecondIndex;
  int _currentPayloadChars = 0;
  EncodedMCOImage? _currentEncodedCandidate;
  EncodedMCOImageV4? _currentEncodedV4;
  Object? _v4EncodeError;
  _MCOImageEncodeCacheKey? _currentEncodedCacheKey;
  MCOImageV4Document? _v4Document;
  MCOImageV4Figure? _v4DraftFigure;
  List<MCOImageV4Point>? _v4PencilPoints;
  final List<MCOImageV4Point> _v4ShapePoints = <MCOImageV4Point>[];
  MCOImageV4Point? _v4GestureStart;
  MCOImageV4Point? _v4LastMovePoint;
  MCOImageV4Document? _v4MoveBefore;
  int? _selectedV4FigureIndex;
  bool _v4GroupSelectionMode = false;
  final Set<int> _v4GroupSelectionIndexes = <int>{};
  int? _v4AppendGroupIndex;
  int? _editingV4FigureIndex;
  MCOImageV4Document? _editingV4FigureBefore;
  bool _editingV4FigureVisible = true;
  _V4ColorTarget _v4ColorTarget = _V4ColorTarget.stroke;
  int? _v4FillColor;
  int? _v4StrokeColor;
  int _v4StrokeWidth = 1;
  MCOImageV4Document? _v4StyleDragBefore;
  List<int>? _v4ReferencePixels;
  PaletteProfile? _v4ReferencePaletteProfile;
  int? _v4ReferenceTransparentColor;
  bool _v4ReferenceVisible = true;
  final List<_CanvasHistoryEntry> _undoStack = <_CanvasHistoryEntry>[];
  final List<_CanvasHistoryEntry> _redoStack = <_CanvasHistoryEntry>[];

  @override
  void initState() {
    super.initState();
    _pixels = List.filled(_width * _height, _whiteIndex);
    final initialImage = widget.initialImage;
    if (initialImage is MCOImageV4Preview) {
      _loadSavedCanvasSettings();
      _loadInitialVectorDocument(initialImage.document);
    } else if (initialImage != null) {
      _loadInitialImage(initialImage);
    } else if (widget.initialImageBytes != null) {
      _loadInitialImageBytes(
        widget.initialImageBytes!,
        width: widget.initialImageWidth,
        height: widget.initialImageHeight,
        paletteProfile: widget.initialPaletteProfile,
      );
    } else {
      _loadSavedCanvasSettings();
    }
    _queueInitialPayloadRefresh();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _payloadRefreshRequestId++;
    _payloadRefreshPending = false;
    _payloadRefreshTimer?.cancel();
    _payloadRefreshTimer = null;
    _stopPayloadRefreshElapsedTimer();
    _cancelActiveEncodeTasksNow();
    final refreshCompletion = _payloadRefreshCompletion;
    _payloadRefreshCompletion = null;
    if (refreshCompletion != null && !refreshCompletion.isCompleted) {
      refreshCompletion.complete();
    }
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
    // Drawing strokes must not trigger the platform back-swipe gesture and
    // close the editor; leaving is via the app bar button or Cancel/Send.
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.chat_canvas),
          leading: BackButton(onPressed: () => Navigator.pop(context)),
        ),
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
                  onChanged: _setCanvasGridShown,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.chat_canvasRulerShow),
                  value: _showRuler,
                  onChanged: _setCanvasRulerShown,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Object>(
                  key: ValueKey((_encodingVersion, _encodingSelectorReset)),
                  initialValue: _encodingVersion,
                  decoration: InputDecoration(
                    labelText: context.l10n.chat_canvasFormatVer,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final version in _availableEncodingVersions)
                      DropdownMenuItem<Object>(
                        value: version,
                        child: Text(_encodingVersionLabel(version)),
                      ),
                    if (_canOpenSeparateV4Editor)
                      const DropdownMenuItem<Object>(
                        value: _EncodingSelectorAction.separateV4,
                        child: Text('v4 Vector (separate screen)'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    if (value == _EncodingSelectorAction.separateV4) {
                      setState(() => _encodingSelectorReset++);
                      unawaited(_openSeparateV4Editor());
                      return;
                    }
                    if (value is MCOImageEncodingVersion) {
                      _changeEncodingVersion(value);
                    }
                  },
                ),
                if (_supportsCompressionLevelSelection) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    key: ValueKey(_compressionLevel),
                    initialValue: _compressionLevel,
                    decoration: InputDecoration(
                      labelText: context.l10n.chat_canvasCompressionLevel,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<int>(
                        value: MCOImageCodec.compressionLevelExtreme,
                        child: Text(
                          context.l10n.chat_canvasCompressionLevelExtreme,
                        ),
                      ),
                      DropdownMenuItem<int>(
                        value: MCOImageCodec.compressionLevelHigh,
                        child: Text(
                          context.l10n.chat_canvasCompressionLevelHigh,
                        ),
                      ),
                      DropdownMenuItem<int>(
                        value: MCOImageCodec.compressionLevelNormal,
                        child: Text(
                          context.l10n.chat_canvasCompressionLevelNormal,
                        ),
                      ),
                    ],
                    onChanged: _setCompressionLevel,
                  ),
                ],
                const SizedBox(height: 16),
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
                if (_isVectorV4) ...[
                  _buildVectorStyleControls(),
                  if (_paletteProfile.isDynamic) ...[
                    const SizedBox(height: 12),
                    _buildDynamicPaletteControls(),
                  ],
                ] else if (_paletteProfile.isDynamic)
                  _buildDynamicPaletteControls()
                else
                  _buildPalette(palette),
                const SizedBox(height: 16),
                Text(
                  context.l10n.chat_canvasPaletteDynamicUsed,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _buildUsedPalette(),
                if (_supportsAlphaTransparency) ...[
                  const SizedBox(height: 12),
                  _buildPaletteAlphaControl(),
                ],
                const SizedBox(height: 16),
                _buildTools(),
                if (_isVectorV4 && _v4ReferencePixels != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: _toggleVectorReferenceVisibility,
                      icon: Icon(
                        _v4ReferenceVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      label: Text(
                        _v4ReferenceVisible
                            ? context.l10n.chat_canvasV4HideReference
                            : context.l10n.chat_canvasV4ShowReference,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _buildCanvas(palette, showLockButton: showLockButton),
                const SizedBox(height: 8),
                _buildPayloadInfo(context, showLockButton: showLockButton),
                if (_isVectorV4) ...[
                  const SizedBox(height: 16),
                  _buildVectorObjects(),
                ],
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
                    if (_isVectorV4) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openVectorAsRasterV3,
                          icon: const Icon(Icons.grid_on_outlined),
                          label: const Text(
                            'v3',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
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
    bool collapsible = true,
  }) {
    final paletteProfile = profile ?? _paletteProfile;
    Widget swatchAt(int index) {
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
    }

    if (!collapsible) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var index = 0; index < palette.length; index++) swatchAt(index),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const itemExtent = 28.0;
        const spacing = 6.0;
        final itemsPerRow = constraints.maxWidth.isFinite
            ? ((constraints.maxWidth + spacing) / (itemExtent + spacing))
                  .floor()
                  .clamp(1, palette.length)
                  .toInt()
            : palette.length;
        final canCollapse = palette.length > itemsPerRow;
        var visibleIndices = List<int>.generate(
          !canCollapse || _paletteExpanded
              ? palette.length
              : (itemsPerRow - 1).clamp(1, palette.length).toInt(),
          (index) => index,
        );
        if (canCollapse && !_paletteExpanded) {
          int? selectedIndex;
          for (var index = 0; index < palette.length; index++) {
            if (_paletteColorValueAtIndex(paletteProfile, index) ==
                _selectedColor) {
              selectedIndex = index;
              break;
            }
          }
          if (selectedIndex != null &&
              !visibleIndices.contains(selectedIndex)) {
            visibleIndices = List<int>.of(visibleIndices)
              ..[visibleIndices.length - 1] = selectedIndex;
          }
        }

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final index in visibleIndices) swatchAt(index),
            if (canCollapse)
              IconButton(
                onPressed: () {
                  setState(() => _paletteExpanded = !_paletteExpanded);
                },
                tooltip: _paletteExpanded
                    ? context.l10n.pathMap_collapsePanel
                    : context.l10n.pathMap_expandPanel,
                icon: Icon(_paletteExpanded ? Icons.remove : Icons.add),
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: itemExtent,
                  height: itemExtent,
                ),
              ),
          ],
        );
      },
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

  Widget _buildVectorStyleControls() {
    final document = _v4Document;
    if (document == null) return const SizedBox.shrink();
    final selectedColor = _v4ColorTarget == _V4ColorTarget.fill
        ? _v4FillColor
        : _v4StrokeColor;
    final stylePaletteValues = _vectorStylePaletteValues(document);
    final maxStrokeWidth = math.max(document.width, document.height);
    final selectedFigure = _selectedV4Figure;
    final canClose =
        selectedFigure == null ||
        selectedFigure is! MCOImageV4Path ||
        selectedFigure.points.length >= 3;

    Widget colorSwatch({
      required int? colorValue,
      required bool selected,
      required VoidCallback onTap,
    }) {
      final color = colorValue == null
          ? null
          : _profileColor(document.paletteProfile, colorValue);
      final profileIndex = colorValue == null
          ? null
          : _paletteIndexForColorValue(document.paletteProfile, colorValue);
      return Tooltip(
        message: colorValue == null
            ? context.l10n.chat_canvasV4Transparent
            : '#${(profileIndex ?? colorValue) + 1}',
        child: _AlphaSwatch(color: color, selected: selected, onTap: onTap),
      );
    }

    Widget colorWrap({
      required int? selectedLocalIndex,
      required void Function(int? colorValue) onSelected,
    }) {
      final selectedColorValue = _vectorColorValueForLocalIndex(
        document,
        selectedLocalIndex,
      );
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          colorSwatch(
            colorValue: null,
            selected: selectedLocalIndex == null,
            onTap: () => onSelected(null),
          ),
          for (final colorValue in stylePaletteValues)
            colorSwatch(
              colorValue: colorValue,
              selected: selectedColorValue == colorValue,
              onTap: () => onSelected(colorValue),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          leading: const Icon(Icons.format_color_fill_outlined),
          title: Text(context.l10n.chat_canvasV4Background),
          subtitle: Text(
            document.backgroundColor == null
                ? context.l10n.chat_canvasV4Transparent
                : '#${document.backgroundColor! + 1}',
          ),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: colorWrap(
                selectedLocalIndex: document.backgroundColor,
                onSelected: _setVectorBackgroundProfileColor,
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
          selected: {_v4ColorTarget},
          onSelectionChanged: (selection) {
            setState(() => _v4ColorTarget = selection.first);
          },
        ),
        const SizedBox(height: 8),
        colorWrap(
          selectedLocalIndex: selectedColor,
          onSelected: _setVectorStyleProfileColor,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text(context.l10n.chat_canvasV4StrokeWidth)),
            Text('$_v4StrokeWidth'),
          ],
        ),
        Slider(
          value: _v4StrokeWidth
              .toDouble()
              .clamp(1, maxStrokeWidth.toDouble())
              .toDouble(),
          min: 1,
          max: maxStrokeWidth.toDouble(),
          divisions: maxStrokeWidth > 1 ? maxStrokeWidth - 1 : null,
          onChangeStart: (_) => _beginVectorStyleDrag(),
          onChanged: (value) {
            final width = value.round();
            if (width == _v4StrokeWidth) return;
            _setVectorStrokeWidth(width, recordUndo: false);
          },
          onChangeEnd: (_) => _endVectorStyleDrag(),
        ),
        if (_showsCurrentVectorFinishButtons) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _canFinishCurrentVectorToolOpen
                    ? () => _finishCurrentVectorToolOpen()
                    : null,
                child: Text(context.l10n.chat_canvasV4FinishOpen),
              ),
              OutlinedButton(
                onPressed: _canFinishCurrentVectorPolylineClosed
                    ? () => _finishVectorPolyline(closed: true)
                    : null,
                child: Text(context.l10n.chat_canvasV4FinishClosed),
              ),
            ],
          ),
        ],
        if (selectedFigure is MCOImageV4Path || selectedFigure is MCOImageV4Wave)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.chat_canvasV4Closed),
            value: selectedFigure is MCOImageV4Path
                ? selectedFigure.closed
                : (selectedFigure as MCOImageV4Wave).closed,
            onChanged: canClose ? _setSelectedVectorClosed : null,
          ),
      ],
    );
  }

  Widget _buildVectorObjects() {
    final document = _v4Document;
    if (document == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.chat_canvasV4Objects,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_v4GroupSelectionMode) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Выбрано: ${_v4GroupSelectionIndexes.length}'),
              OutlinedButton.icon(
                onPressed: _canMergeCheckedV4Figures
                    ? _mergeCheckedV4Figures
                    : null,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Объединить выбранные'),
              ),
              TextButton(
                onPressed: _cancelV4GroupSelection,
                child: Text(context.l10n.common_cancel),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (document.figures.isEmpty)
          Text(context.l10n.chat_canvasV4NoObjects)
        else
          for (var i = document.figures.length - 1; i >= 0; i--)
            ListTile(
              selected:
                  i == _selectedV4FigureIndex ||
                  _v4GroupSelectionIndexes.contains(i),
              contentPadding: EdgeInsets.zero,
              leading: _v4GroupSelectionMode
                  ? Checkbox(
                      value: _v4GroupSelectionIndexes.contains(i),
                      onChanged: (selected) =>
                          _setV4FigureCheckedForGroup(i, selected ?? false),
                    )
                  : IconButton(
                      tooltip: document.figures[i].visible
                          ? context.l10n.chat_canvasV4HideFigure
                          : context.l10n.chat_canvasV4ShowFigure,
                      onPressed: () => _toggleVectorFigureVisibility(i),
                      icon: Icon(
                        document.figures[i].visible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
              title: Row(
                children: [
                  _V4FigurePreview(
                    document: document,
                    figure: document.figures[i],
                    selected:
                        i == _selectedV4FigureIndex ||
                        i == _v4AppendGroupIndex ||
                        _v4GroupSelectionIndexes.contains(i),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      i == _v4AppendGroupIndex
                          ? '${_vectorFigureLabel(document.figures[i])} +'
                          : _vectorFigureLabel(document.figures[i]),
                    ),
                  ),
                ],
              ),
              onTap: () => _v4GroupSelectionMode
                  ? _toggleV4FigureCheckedForGroup(i)
                  : _selectVectorFigure(i),
              trailing: _v4GroupSelectionMode
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: context.l10n.chat_canvasV4MoveUp,
                          onPressed: i == document.figures.length - 1
                              ? null
                              : () => _reorderVectorFigure(i, i + 1),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: context.l10n.chat_canvasV4MoveDown,
                          onPressed: i == 0
                              ? null
                              : () => _reorderVectorFigure(i, i - 1),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .deleteButtonTooltip,
                          onPressed: () => _deleteVectorFigure(i),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
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
    if (_isVectorV4) {
      _setVectorStyleProfileColor(colorValue);
      return;
    }
    setState(() {
      _selectedColor = colorValue;
    });
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
      ],
    );
  }

  Widget _buildUsedPalette() {
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
              collapsible: false,
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
    if (_isVectorV4) {
      return _buildVectorV4Tools();
    }

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

    const toolSegments = <ButtonSegment<_CanvasTool>>[
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
    ];
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
          segments: toolSegments,
          selected: {_selectedTool},
          onSelectionChanged: (selection) {
            if (selection.isEmpty) {
              _selectCanvasTool(_selectedTool);
              return;
            }
            _selectCanvasTool(selection.first);
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

  Widget _buildVectorV4Tools() {
    const buttonSize = 48.0;
    const gap = SizedBox(width: 4);
    final colorScheme = Theme.of(context).colorScheme;

    ButtonStyle? selectedStyle(bool selected) => selected
        ? IconButton.styleFrom(
            backgroundColor: colorScheme.primaryContainer,
            foregroundColor: colorScheme.onPrimaryContainer,
          )
        : null;

    Widget fixedButton({
      required Widget child,
    }) {
      return SizedBox.square(
        dimension: buttonSize,
        child: Center(child: child),
      );
    }

    Widget actionButton({
      required VoidCallback? onPressed,
      required String tooltip,
      required IconData icon,
      bool selected = false,
    }) {
      return fixedButton(
        child: IconButton.outlined(
          onPressed: onPressed,
          tooltip: tooltip,
          icon: Icon(icon),
          style: selectedStyle(selected),
        ),
      );
    }

    Widget toolButton({
      required _CanvasTool tool,
      required String tooltip,
      required IconData icon,
    }) {
      return actionButton(
        onPressed: () => _selectCanvasTool(tool),
        tooltip: tooltip,
        icon: icon,
        selected: _selectedTool == tool,
      );
    }

    Widget emptyCell() => fixedButton(child: const SizedBox.shrink());

    final topRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        actionButton(
          onPressed: _undoStack.isEmpty ? null : _undoCanvasAction,
          tooltip: context.l10n.common_undo,
          icon: Icons.undo,
        ),
        gap,
        actionButton(
          onPressed: _canCloneSelectedV4Figure ? _cloneSelectedV4Figure : null,
          tooltip: context.l10n.common_copy,
          icon: Icons.content_copy,
        ),
        gap,
        actionButton(
          onPressed: _canEditSelectedV4Figure ? _editSelectedV4Figure : null,
          tooltip: context.l10n.common_edit,
          icon: Icons.account_tree_outlined,
        ),
        gap,
        actionButton(
          onPressed: _canAppendToSelectedV4Group
              ? _toggleV4AppendToSelectedGroup
              : null,
          tooltip: 'Добавлять новые фигуры в выбранную группу',
          icon: Icons.lock,
          selected: _isAppendingToSelectedV4Group,
        ),
        gap,
        toolButton(
          tool: _CanvasTool.select,
          tooltip: context.l10n.chat_canvasV4ToolSelect,
          icon: Icons.near_me_outlined,
        ),
        gap,
        toolButton(
          tool: _CanvasTool.pencil,
          tooltip: context.l10n.chat_canvasV4ToolPencil,
          icon: Icons.edit_outlined,
        ),
        gap,
        toolButton(
          tool: _CanvasTool.polyline,
          tooltip: context.l10n.chat_canvasV4ToolPolyline,
          icon: Icons.polyline,
        ),
        gap,
        toolButton(
          tool: _CanvasTool.rectangle,
          tooltip: context.l10n.chat_canvasV4ToolRect,
          icon: Icons.crop_square,
        ),
      ],
    );

    final bottomRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        actionButton(
          onPressed: _redoStack.isEmpty ? null : _redoCanvasAction,
          tooltip: context.l10n.chat_canvasV4Redo,
          icon: Icons.redo,
        ),
        gap,
        actionButton(
          onPressed: _toggleV4GroupSelectionMode,
          tooltip: 'Выбрать фигуры для объединения',
          icon: Icons.lock_outline,
          selected: _v4GroupSelectionMode,
        ),
        gap,
        actionButton(
          onPressed: _canUngroupSelectedV4Figure
              ? _ungroupSelectedV4Figure
              : null,
          tooltip: 'Разгруппировать',
          icon: Icons.lock_open_outlined,
        ),
        gap,
        emptyCell(),
        gap,
        toolButton(
          tool: _CanvasTool.dot,
          tooltip: context.l10n.chat_canvasV4ToolDot,
          icon: Icons.fiber_manual_record,
        ),
        gap,
        toolButton(
          tool: _CanvasTool.line,
          tooltip: context.l10n.chat_canvasV4ToolLine,
          icon: Icons.horizontal_rule,
        ),
        gap,
        toolButton(
          tool: _CanvasTool.wave,
          tooltip: context.l10n.chat_canvasV4ToolWave,
          icon: Icons.gesture,
        ),
        gap,
        toolButton(
          tool: _CanvasTool.oval,
          tooltip: context.l10n.chat_canvasV4ToolEllipse,
          icon: Icons.circle_outlined,
        ),
      ],
    );

    return _buildHorizontalScrollableButtonRow(
      controller: _toolsScrollController,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          topRow,
          const SizedBox(height: 4),
          bottomRow,
        ],
      ),
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
        final canvasOffset = Offset(
          _canvasRulerExtent,
          _canvasRulerExtent,
        );
        final drawingOffset = Offset(
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
                  painter: _isVectorV4
                      ? _VectorCanvasPainter(
                          document: _activeVectorDocument,
                          selectedFigure: _selectedV4Figure,
                          referencePixels:
                              _v4ReferenceVisible ? _v4ReferencePixels : null,
                          referenceProfile: _v4ReferencePaletteProfile,
                          referenceTransparentColor:
                              _v4ReferenceTransparentColor,
                          guidePoints: List<MCOImageV4Point>.of(
                            _v4ShapePoints,
                          ),
                          guideStyle: _currentVectorStyle(),
                          showGrid: _showGrid,
                          showRuler: _showRuler,
                          canvasOffset: canvasOffset,
                          canvasSize: canvasSize,
                          rulerExtent: _canvasRulerExtent,
                        )
                      : _PixelCanvasPainter(
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
                  left: drawingOffset.dx,
                  top: drawingOffset.dy,
                  width: canvasSize.width,
                  height: canvasSize.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: canDraw && _isVectorV4
                        ? (details) => _handleVectorTap(
                            details.localPosition,
                            canvasSize,
                          )
                        : null,
                    onPanStart: canDraw && _isVectorV4
                        ? (details) => _handleVectorPanStart(
                            details.localPosition,
                            canvasSize,
                          )
                        : null,
                    onPanDown: canDraw && !_isVectorV4
                        ? (details) {
                            _isDrawing = true;
                            _applyToolAt(details.localPosition, canvasSize);
                          }
                        : null,
                    onPanUpdate: canDraw
                        ? (details) {
                            if (_isVectorV4) {
                              _handleVectorPanUpdate(
                                details.localPosition,
                                canvasSize,
                              );
                            } else if (_selectedTool == _CanvasTool.pencil) {
                              _applyToolAt(details.localPosition, canvasSize);
                            }
                          }
                        : null,
                    onPanEnd: canDraw
                        ? (_) {
                            if (_isVectorV4) {
                              _handleVectorPanEnd();
                            } else {
                              _finishDrawing();
                            }
                          }
                        : null,
                    onPanCancel: canDraw
                        ? () {
                            if (_isVectorV4) {
                              _handleVectorPanEnd();
                            } else {
                              _finishDrawing();
                            }
                          }
                        : null,
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
    final isOverLimit =
        !_payloadRefreshPending &&
        !_payloadRefreshInProgress &&
        _currentPayloadChars > _effectiveDisplayedPayloadLimit;
    final mediaHeight = MediaQuery.of(context).size.height;
    final colorScheme = Theme.of(context).colorScheme;
    final currentEncodedCandidate = _isVectorV4 ? null : _currentEncodedCandidate;
    final v4EncodeError = _isVectorV4 ? _v4EncodeError : null;
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
                if (v4EncodeError != null) ...[
                  Text(
                    v4EncodeError.toString(),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
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
                          _payloadRefreshPending || _payloadRefreshInProgress
                              ? _payloadCalculatingLabel(
                                  context,
                                  progressPercent:
                                      _payloadRefreshProgressPercent,
                                  elapsed: _payloadRefreshElapsed,
                                )
                              : _payloadReadyLabel(
                                  context,
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
    MCOImageV4Document? vectorDocument,
    Object? vectorReferencePixels = _transparentColorUnchanged,
    Object? vectorReferencePaletteProfile = _transparentColorUnchanged,
    Object? vectorReferenceTransparentColor = _transparentColorUnchanged,
    bool? vectorReferenceVisible,
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
      vectorDocument: vectorDocument ?? _v4Document,
      vectorReferencePixels: identical(
        vectorReferencePixels,
        _transparentColorUnchanged,
      )
          ? _v4ReferencePixels
          : vectorReferencePixels as List<int>?,
      vectorReferencePaletteProfile: identical(
        vectorReferencePaletteProfile,
        _transparentColorUnchanged,
      )
          ? _v4ReferencePaletteProfile
          : vectorReferencePaletteProfile as PaletteProfile?,
      vectorReferenceTransparentColor: identical(
        vectorReferenceTransparentColor,
        _transparentColorUnchanged,
      )
          ? _v4ReferenceTransparentColor
          : vectorReferenceTransparentColor as int?,
      vectorReferenceVisible:
          vectorReferenceVisible ?? _v4ReferenceVisible,
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
        identical(a.vectorDocument, b.vectorDocument) &&
        a.vectorReferencePaletteProfile == b.vectorReferencePaletteProfile &&
        a.vectorReferenceTransparentColor ==
            b.vectorReferenceTransparentColor &&
        a.vectorReferenceVisible == b.vectorReferenceVisible &&
        _nullablePixelsEqual(
          a.vectorReferencePixels,
          b.vectorReferencePixels,
        ) &&
        _pixelsEqual(a.pixels, b.pixels);
  }

  bool _nullablePixelsEqual(List<int>? a, List<int>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return _pixelsEqual(a, b);
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
      _v4Document = snapshot.vectorDocument;
      _v4ReferencePixels = snapshot.vectorReferencePixels == null
          ? null
          : List<int>.of(snapshot.vectorReferencePixels!);
      _v4ReferencePaletteProfile = snapshot.vectorReferencePaletteProfile;
      _v4ReferenceTransparentColor = snapshot.vectorReferenceTransparentColor;
      _v4ReferenceVisible = snapshot.vectorReferenceVisible;
      if (_v4Document == null) {
        _selectedV4FigureIndex = null;
        _clearVectorEditingState();
      } else {
        _selectedV4FigureIndex = null;
        _adoptVectorStyle(_v4Document!.initialStyle);
      }
      _v4GroupSelectionMode = false;
      _v4GroupSelectionIndexes.clear();
      _v4AppendGroupIndex = null;
      _setControllerValue(_widthController, _width);
      _setControllerValue(_heightController, _height);
      _clearRasterDraftState();
      _clearVectorDraftState();
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

  void _resizeVectorCanvas(
    int width,
    int height, {
    required bool rescaleFigures,
  }) {
    final document = _v4Document;
    if (document == null) return;
    _cancelPayloadCalculationBeforeCanvasReplacement();
    final nextDocument = rescaleFigures
        ? _rescaleVectorDocument(document, width, height)
        : document.copyWith(width: width, height: height);
    final referencePixels = _v4ReferencePixels;
    final nextReferencePixels =
        referencePixels != null &&
            referencePixels.length == document.width * document.height
        ? rescaleFigures
              ? _resizePixels(
                  sourcePixels: referencePixels,
                  sourceWidth: document.width,
                  sourceHeight: document.height,
                  targetWidth: width,
                  targetHeight: height,
                  fillColor: MCOImagePalette.whiteIndexFor(
                    _v4ReferencePaletteProfile ?? _paletteProfile,
                  ),
                )
              : _cropOrPadPixels(
                  sourcePixels: referencePixels,
                  sourceWidth: document.width,
                  sourceHeight: document.height,
                  targetWidth: width,
                  targetHeight: height,
                  fillColor: MCOImagePalette.whiteIndexFor(
                    _v4ReferencePaletteProfile ?? _paletteProfile,
                  ),
                )
        : null;
    final nextPixels = List<int>.filled(width * height, _whiteIndex);
    final before = _captureCanvasSnapshot();
    final after = _captureCanvasSnapshot(
      width: width,
      height: height,
      pixels: nextPixels,
      vectorDocument: nextDocument,
      vectorReferencePixels: nextReferencePixels,
      vectorReferencePaletteProfile:
          nextReferencePixels == null ? null : _v4ReferencePaletteProfile,
      vectorReferenceTransparentColor: nextReferencePixels == null
          ? null
          : _v4ReferenceTransparentColor,
    );
    _rememberCanvasAction(before, after);
    setState(() {
      _v4Document = nextDocument;
      _width = width;
      _height = height;
      _setControllerValue(_widthController, _width);
      _setControllerValue(_heightController, _height);
      _pixels = nextPixels;
      _v4ReferencePixels = nextReferencePixels;
      _clearVectorDraftState();
    });
    _markPayloadDirty();
    unawaited(_saveCanvasSize(width, height));
  }

  MCOImageV4Document _rescaleVectorDocument(
    MCOImageV4Document source,
    int width,
    int height,
  ) {
    if (source.width == width && source.height == height) return source;

    int x(int value) => (value * width / source.width)
        .round()
        .clamp(0, width - 1)
        .toInt();
    int y(int value) => (value * height / source.height)
        .round()
        .clamp(0, height - 1)
        .toInt();
    final scalarScale =
        math.max(width, height) / math.max(source.width, source.height);

    MCOImageV4Point mapPoint(MCOImageV4Point value) =>
        MCOImageV4Point(x(value.x), y(value.y));

    MCOImageV4Figure convert(MCOImageV4Figure figure) {
      return switch (figure) {
        MCOImageV4Dot(:final point, :final style, :final visible) =>
          MCOImageV4Dot(
            point: mapPoint(point),
            style: style,
            visible: visible,
          ),
        MCOImageV4Line(
          :final start,
          :final end,
          :final style,
          :final visible,
        ) =>
          MCOImageV4Line(
            start: mapPoint(start),
            end: mapPoint(end),
            style: style,
            visible: visible,
          ),
        MCOImageV4Rect(
          :final first,
          :final second,
          :final third,
          :final style,
          :final visible,
        ) =>
          MCOImageV4Rect(
            first: mapPoint(first),
            second: mapPoint(second),
            third: mapPoint(third),
            style: style,
            visible: visible,
          ),
        MCOImageV4Ellipse(
          :final first,
          :final second,
          :final third,
          :final style,
          :final visible,
        ) =>
          MCOImageV4Ellipse(
            first: mapPoint(first),
            second: mapPoint(second),
            third: mapPoint(third),
            style: style,
            visible: visible,
          ),
        MCOImageV4Path(
          :final points,
          :final closed,
          :final style,
          :final visible,
        ) =>
          MCOImageV4Path(
            points: points.map(mapPoint).toList(growable: false),
            closed: closed,
            style: style,
            visible: visible,
          ),
        MCOImageV4Group(:final figures, :final style, :final visible) =>
          MCOImageV4Group(
            figures: figures.map(convert).toList(growable: false),
            style: style,
            visible: visible,
          ),
        MCOImageV4Wave(
          :final start,
          :final end,
          :final depth,
          :final closed,
          :final style,
          :final visible,
        ) =>
          MCOImageV4Wave(
            start: mapPoint(start),
            end: mapPoint(end),
            depth: (depth * scalarScale).round().clamp(
              -math.max(width, height),
              math.max(width, height),
            ).toInt(),
            closed: closed,
            style: style,
            visible: visible,
          ),
      };
    }

    return source.copyWith(
      width: width,
      height: height,
      figures: source.figures.map(convert).toList(growable: false),
    );
  }

  void _resize({int? width, int? height}) {
    final newWidth = width ?? _width;
    final newHeight = height ?? _height;
    if (newWidth == _width && newHeight == _height) return;
    if (_isVectorV4) {
      _resizeVectorCanvas(newWidth, newHeight, rescaleFigures: true);
      return;
    }
    _cancelPayloadCalculationBeforeCanvasReplacement();
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
      if (!_isRasterTool(_selectedTool)) {
        _selectedTool = _CanvasTool.pencil;
      }
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
    if (_isVectorV4) {
      _resizeVectorCanvas(width, height, rescaleFigures: false);
      return;
    }
    _cancelPayloadCalculationBeforeCanvasReplacement();
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

  List<int> _cropPixelsFromOrigin({
    required List<int> sourcePixels,
    required int sourceWidth,
    required int sourceHeight,
    required int sourceStartX,
    required int sourceStartY,
    required int targetWidth,
    required int targetHeight,
    required int fillColor,
  }) {
    final nextPixels = List<int>.filled(targetWidth * targetHeight, fillColor);
    for (var y = 0; y < targetHeight; y++) {
      final sourceY = sourceStartY + y;
      if (sourceY < 0 || sourceY >= sourceHeight) continue;
      for (var x = 0; x < targetWidth; x++) {
        final sourceX = sourceStartX + x;
        if (sourceX < 0 || sourceX >= sourceWidth) continue;
        nextPixels[y * targetWidth + x] =
            sourcePixels[sourceY * sourceWidth + sourceX];
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

  int get _effectiveDisplayedPayloadLimit {
    return _effectivePayloadLimit;
  }

  void _loadSavedCanvasSettings() {
    final prefs = PrefsManager.instance;
    final profileName = prefs.getString(_prefsPaletteKey);
    final profile = PaletteProfile.values.firstWhere(
      (value) => value.name == profileName,
      orElse: () => PaletteProfile.master64,
    );
    final unlockCanvasSize = prefs.getBool(_prefsUnlockSizeKey) ?? false;
    final showGrid = prefs.getBool(_prefsShowGridKey) ?? true;
    final showRuler = prefs.getBool(_prefsShowRulerKey) ?? false;
    final encodingVersion = _loadSavedEncodingVersion();
    final defaultSize = encodingVersion == MCOImageEncodingVersion.v4
        ? _defaultVectorSize
        : _defaultSize;
    final requestedWidth = prefs.getInt(_prefsWidthKey) ?? defaultSize;
    final requestedHeight = prefs.getInt(_prefsHeightKey) ?? defaultSize;
    final compressionLevel = _loadSavedCompressionLevel();
    final bounded = _boundedCanvasSizeForProfile(
      requestedWidth,
      requestedHeight,
      profile,
      unlockAdaptiveLimit: unlockCanvasSize,
      encodingVersion: encodingVersion,
    );
    final width = bounded[0];
    final height = bounded[1];

    _paletteProfile = profile;
    _unlockCanvasSize = unlockCanvasSize;
    _showGrid = showGrid;
    _showRuler = showRuler;
    _encodingVersion = encodingVersion;
    _compressionLevel = compressionLevel;
    if (profile.isDynamic) {
      _dynamicPaletteProfile = profile;
    }
    _selectedColor =
        encodingVersion == MCOImageEncodingVersion.v4 && profile.isDynamic
        ? MCOImageDynamicPalette.blackGlobalIndexFor(profile)
        : MCOImagePalette.blackIndexFor(profile);
    _width = width;
    _height = height;
    _setControllerValue(_widthController, width);
    _setControllerValue(_heightController, height);
    _pixels = List.filled(width * height, _whiteIndex);
    if (encodingVersion == MCOImageEncodingVersion.v4) {
      _v4Document = _newVectorDocument(width, height, profile);
      _adoptVectorStyle(_v4Document!.initialStyle);
    }
  }

  void _loadInitialImage(MCOImage image) {
    // Reusing an existing message image should preserve its codec palette and
    // exact canvas dimensions instead of applying the user's last editor preset.
    _unlockCanvasSize =
        PrefsManager.instance.getBool(_prefsUnlockSizeKey) ?? false;
    _showGrid = PrefsManager.instance.getBool(_prefsShowGridKey) ?? true;
    _showRuler = PrefsManager.instance.getBool(_prefsShowRulerKey) ?? false;
    _compressionLevel = _loadSavedCompressionLevel();
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
    _v4Document = null;
    _currentEncodedV4 = null;
    _v4EncodeError = null;
    _selectedV4FigureIndex = null;
    _v4ReferencePixels = null;
    _v4ReferencePaletteProfile = null;
    _v4ReferenceTransparentColor = null;
    _v4ReferenceVisible = true;
  }

  Future<void> _loadInitialImageBytes(
    Uint8List bytes, {
    int? width,
    int? height,
    PaletteProfile? paletteProfile,
  }) async {
    _unlockCanvasSize =
        PrefsManager.instance.getBool(_prefsUnlockSizeKey) ?? false;
    _showGrid = PrefsManager.instance.getBool(_prefsShowGridKey) ?? true;
    _showRuler = PrefsManager.instance.getBool(_prefsShowRulerKey) ?? false;
    final savedEncodingVersion = _loadSavedEncodingVersion();
    _encodingVersion = savedEncodingVersion == MCOImageEncodingVersion.v4
        ? MCOImageEncodingVersion.v3
        : savedEncodingVersion;
    _compressionLevel = _loadSavedCompressionLevel();
    if (paletteProfile != null) {
      _paletteProfile = paletteProfile;
      if (paletteProfile.isDynamic) {
        _dynamicPaletteProfile = paletteProfile;
      }
      _selectedColor = MCOImagePalette.blackIndexFor(paletteProfile);
    }
    if (width != null && height != null) {
      _width = width.clamp(_minCanvasSize, _maxCanvasSize).toInt();
      _height = height.clamp(_minCanvasSize, _maxCanvasSize).toInt();
      _setControllerValue(_widthController, _width);
      _setControllerValue(_heightController, _height);
      _pixels = List.filled(_width * _height, _whiteIndex);
    }
    try {
      final importedImage = await _imageBytesToCanvasPixels(bytes);
      if (!mounted) return;
      setState(() {
        _width = importedImage.width;
        _height = importedImage.height;
        _setControllerValue(_widthController, _width);
        _setControllerValue(_heightController, _height);
        _pixels = importedImage.pixels;
        _currentEncodedCandidate = null;
        _currentEncodedCacheKey = null;
      });
      _markPayloadDirty();
    } on MCOImageCodecException {
      _markPayloadDirty();
    }
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

  int _loadSavedCompressionLevel() {
    final saved = PrefsManager.instance.getInt(_prefsCompressionLevelKey);
    return switch (saved) {
      MCOImageCodec.compressionLevelNormal =>
        MCOImageCodec.compressionLevelNormal,
      MCOImageCodec.compressionLevelExtreme =>
        MCOImageCodec.compressionLevelExtreme,
      _ => MCOImageCodec.compressionLevelHigh,
    };
  }

  MCOImageEncodingVersion _loadSavedEncodingVersion() {
    final saved = PrefsManager.instance.getString(_prefsEncodingVersionKey);
    return switch (saved) {
      'v1Legacy' => MCOImageEncodingVersion.v1Legacy,
      'v2' => MCOImageEncodingVersion.v2,
      'v3' => MCOImageEncodingVersion.v3,
      'v4' when widget.maxBinaryPayloadBytes != null &&
              widget.binarySenderName != null =>
        MCOImageEncodingVersion.v4,
      _ => MCOImageEncodingVersion.v3,
    };
  }

  Future<void> _saveEncodingVersion(MCOImageEncodingVersion version) {
    return PrefsManager.instance.setString(
      _prefsEncodingVersionKey,
      version.name,
    );
  }

  void _setCompressionLevel(int? value) {
    final nextLevel = switch (value) {
      MCOImageCodec.compressionLevelNormal =>
        MCOImageCodec.compressionLevelNormal,
      MCOImageCodec.compressionLevelExtreme =>
        MCOImageCodec.compressionLevelExtreme,
      _ => MCOImageCodec.compressionLevelHigh,
    };
    if (nextLevel == _compressionLevel) return;

    setState(() => _compressionLevel = nextLevel);
    unawaited(
      PrefsManager.instance.setInt(_prefsCompressionLevelKey, nextLevel),
    );

    // _markPayloadDirty() now performs cancellation and restart for every
    // setting or canvas mutation.
    _markPayloadDirty();
  }

  void _setCanvasGridShown(bool? value) {
    final showGrid = value ?? true;
    if (showGrid == _showGrid) return;
    setState(() => _showGrid = showGrid);
    unawaited(PrefsManager.instance.setBool(_prefsShowGridKey, showGrid));
  }

  void _setCanvasRulerShown(bool? value) {
    final showRuler = value ?? false;
    if (showRuler == _showRuler) return;
    setState(() => _showRuler = showRuler);
    unawaited(PrefsManager.instance.setBool(_prefsShowRulerKey, showRuler));
  }

  bool get _supportsDynamicPalettes =>
      _encodingVersion == MCOImageEncodingVersion.v2 ||
      _encodingVersion == MCOImageEncodingVersion.v3 ||
      _encodingVersion == MCOImageEncodingVersion.v4;

  bool get _supportsAlphaTransparency =>
      _encodingVersion == MCOImageEncodingVersion.v2 ||
      _encodingVersion == MCOImageEncodingVersion.v3;

  bool get _supportsCompressionLevelSelection =>
      _encodingVersion != MCOImageEncodingVersion.v1Legacy &&
      _encodingVersion != MCOImageEncodingVersion.v4;

  bool get _canOpenSeparateV4Editor =>
      widget.maxBinaryPayloadBytes != null && widget.binarySenderName != null;

  List<MCOImageEncodingVersion> get _availableEncodingVersions {
    return [
      MCOImageEncodingVersion.v1Legacy,
      MCOImageEncodingVersion.v2,
      MCOImageEncodingVersion.v3,
      if (_isVectorV4 ||
          (widget.maxBinaryPayloadBytes != null &&
              widget.binarySenderName != null))
        MCOImageEncodingVersion.v4,
    ];
  }

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
      MCOImageEncodingVersion.v3 => 'v3',
      MCOImageEncodingVersion.v4 => 'v4 Vector',
    };
  }

  void _changeEncodingVersion(MCOImageEncodingVersion version) {
    if (version == _encodingVersion) return;

    if (version == MCOImageEncodingVersion.v4) {
      _enterVectorV4Mode();
      return;
    }
    if (_isVectorV4) {
      unawaited(_switchVectorToRasterVersion(version));
      return;
    }

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
      _clearVectorDraftState();
    });
    _markPayloadDirty();
    unawaited(_saveEncodingVersion(version));
    unawaited(_saveCanvasSize(nextWidth, nextHeight));
    unawaited(_saveCanvasPalette(nextProfile));
  }

  bool _isRasterTool(_CanvasTool tool) {
    return switch (tool) {
      _CanvasTool.pencil ||
      _CanvasTool.fill ||
      _CanvasTool.eyedropper ||
      _CanvasTool.line ||
      _CanvasTool.oval ||
      _CanvasTool.rectangle => true,
      _CanvasTool.select ||
      _CanvasTool.dot ||
      _CanvasTool.polyline ||
      _CanvasTool.wave => false,
    };
  }

  bool get _isVectorV4 => _encodingVersion == MCOImageEncodingVersion.v4;

  void _enterVectorV4Mode({
    MCOImageV4Document? document,
    bool recordHistory = true,
  }) {
    _cancelPayloadCalculationBeforeCanvasReplacement();
    final before = _captureCanvasSnapshot();
    final enteringFromRaster = !_isVectorV4 && document == null;
    final referencePixels = enteringFromRaster
        ? List<int>.of(_pixels)
        : _v4ReferencePixels;
    final referenceProfile = enteringFromRaster
        ? _paletteProfile
        : _v4ReferencePaletteProfile;
    final referenceTransparentColor = enteringFromRaster
        ? (_supportsAlphaTransparency ? _transparentColor : null)
        : _v4ReferenceTransparentColor;
    final referenceVisible = enteringFromRaster ? true : _v4ReferenceVisible;
    final nextDocument = document ??
        _v4Document ??
        _newVectorDocument(
          enteringFromRaster ? _width : _defaultVectorSize,
          enteringFromRaster ? _height : _defaultVectorSize,
          _paletteProfile,
        );
    final nextProfile = nextDocument.paletteProfile;
    final nextDynamicProfile = nextProfile.isDynamic
        ? nextProfile
        : _dynamicPaletteProfile;
    final nextSelectedColor = nextProfile.isDynamic
        ? MCOImageDynamicPalette.blackGlobalIndexFor(nextProfile)
        : MCOImagePalette.blackIndexFor(nextProfile);
    final nextPixels = List<int>.filled(
      nextDocument.width * nextDocument.height,
      MCOImagePalette.whiteIndexFor(nextProfile),
    );
    final after = _captureCanvasSnapshot(
      width: nextDocument.width,
      height: nextDocument.height,
      paletteProfile: nextProfile,
      dynamicPaletteProfile: nextDynamicProfile,
      encodingVersion: MCOImageEncodingVersion.v4,
      selectedColor: nextSelectedColor,
      transparentColor: null,
      pixels: nextPixels,
      vectorDocument: nextDocument,
      vectorReferencePixels: referencePixels,
      vectorReferencePaletteProfile: referenceProfile,
      vectorReferenceTransparentColor: referenceTransparentColor,
      vectorReferenceVisible: referenceVisible,
    );
    if (recordHistory) {
      _rememberCanvasAction(before, after);
    }
    setState(() {
      _encodingVersion = MCOImageEncodingVersion.v4;
      _paletteProfile = nextProfile;
      _dynamicPaletteProfile = nextDynamicProfile;
      _selectedColor = nextSelectedColor;
      _transparentColor = null;
      _isPickingTransparentColor = false;
      _width = nextDocument.width;
      _height = nextDocument.height;
      _setControllerValue(_widthController, _width);
      _setControllerValue(_heightController, _height);
      _pixels = nextPixels;
      _v4Document = nextDocument;
      _v4ReferencePixels = referencePixels;
      _v4ReferencePaletteProfile = referenceProfile;
      _v4ReferenceTransparentColor = referenceTransparentColor;
      _v4ReferenceVisible = referenceVisible;
      _selectedTool = _CanvasTool.pencil;
      _selectedV4FigureIndex = null;
      _adoptVectorStyle(nextDocument.initialStyle);
      _clearRasterDraftState();
      _clearVectorDraftState();
      _clearVectorEditingState();
    });
    _markPayloadDirty();
    unawaited(_saveEncodingVersion(MCOImageEncodingVersion.v4));
    unawaited(_saveCanvasSize(nextDocument.width, nextDocument.height));
    unawaited(_saveCanvasPalette(nextProfile));
  }

  void _loadInitialVectorDocument(MCOImageV4Document document) {
    final profile = document.paletteProfile;
    final dynamicProfile = profile.isDynamic ? profile : _dynamicPaletteProfile;
    final selectedColor = profile.isDynamic
        ? MCOImageDynamicPalette.blackGlobalIndexFor(profile)
        : MCOImagePalette.blackIndexFor(profile);
    _encodingVersion = MCOImageEncodingVersion.v4;
    _paletteProfile = profile;
    _dynamicPaletteProfile = dynamicProfile;
    _selectedColor = selectedColor;
    _transparentColor = null;
    _width = document.width;
    _height = document.height;
    _setControllerValue(_widthController, _width);
    _setControllerValue(_heightController, _height);
    _pixels = List<int>.filled(_width * _height, _whiteIndex);
    _v4Document = document;
    _v4ReferencePixels = null;
    _v4ReferencePaletteProfile = null;
    _v4ReferenceTransparentColor = null;
    _v4ReferenceVisible = true;
    _selectedTool = _CanvasTool.pencil;
    _selectedV4FigureIndex = null;
    _adoptVectorStyle(document.initialStyle);
  }

  Future<void> _openVectorAsRasterV3() async {
    try {
      final image = await _rasterizeVectorForV3();
      if (!mounted) return;
      _applyV4RasterTransfer(image);
    } on Object catch (error) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(error.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<void> _openSeparateV4Editor() async {
    final maxBinaryPayloadBytes = widget.maxBinaryPayloadBytes;
    final binarySenderName = widget.binarySenderName;
    if (maxBinaryPayloadBytes == null || binarySenderName == null) return;

    final result = await Navigator.push<CanvasEditorResult>(
      context,
      MaterialPageRoute(
        builder: (context) => MCOImageV4EditorScreen(
          maxBinaryPayloadBytes: maxBinaryPayloadBytes,
          binarySenderName: binarySenderName,
          initialPaletteProfile: _paletteProfile,
          initialShowGrid: _showGrid,
          initialDocument: _v4Document,
          replyTargetName: widget.replyTargetName,
          replyTimestamp: widget.replyTimestamp,
        ),
      ),
    );
    if (result == null || !mounted) return;

    final rasterImage = result.rasterImage;
    if (rasterImage != null) {
      _applyV4RasterTransfer(rasterImage);
      return;
    }
    if (result.text.isNotEmpty) {
      Navigator.pop(context, result);
    }
  }

  Future<void> _switchVectorToRasterVersion(
    MCOImageEncodingVersion version,
  ) async {
    try {
      final image = await _rasterizeVectorForV3();
      if (!mounted) return;
      _applyV4RasterTransfer(image);
      if (version != MCOImageEncodingVersion.v3) {
        _changeEncodingVersion(version);
      }
    } on Object catch (error) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(error.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<MCOImage> _rasterizeVectorForV3() async {
    final document = _v4Document;
    if (document == null) {
      throw const MCOImageInvalidInputException(
        'MCOimg v4 vector document is not initialized',
      );
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    MCOImageV4Painter(document, antiAlias: false).paint(
      canvas,
      Size(document.width.toDouble(), document.height.toDouble()),
    );
    final rendered = await recorder.endRecording().toImage(
      document.width,
      document.height,
    );
    try {
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) {
        throw const MCOImageInvalidInputException('Cannot render MCOimg v4');
      }
      final rgba = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final paletteValues = _rasterPaletteValues(document.paletteProfile);
      final white = MCOImagePalette.whiteIndexFor(document.paletteProfile);
      final pixels = List<int>.filled(document.width * document.height, white);
      final transparentPixels = <int>[];
      final used = <int>{};
      for (var i = 0; i < pixels.length; i++) {
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
          document.paletteProfile,
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
        width: document.width,
        height: document.height,
        paletteProfile: document.paletteProfile,
        pixels: pixels,
        transparentColor: transparentColor,
        encodingVersion: MCOImageEncodingVersion.v3,
      );
    } finally {
      rendered.dispose();
    }
  }

  void _applyV4RasterTransfer(MCOImage image) {
    final before = _captureCanvasSnapshot();
    final profile = image.paletteProfile;
    final dynamicProfile = profile.isDynamic ? profile : _dynamicPaletteProfile;
    final selectedColor = MCOImagePalette.blackIndexFor(profile);
    final after = _captureCanvasSnapshot(
      width: image.width,
      height: image.height,
      paletteProfile: profile,
      dynamicPaletteProfile: dynamicProfile,
      encodingVersion: MCOImageEncodingVersion.v3,
      selectedColor: selectedColor,
      transparentColor: image.transparentColor,
      pixels: image.pixels,
      vectorDocument: null,
      vectorReferencePixels: null,
      vectorReferencePaletteProfile: null,
      vectorReferenceTransparentColor: null,
      vectorReferenceVisible: true,
    );
    _rememberCanvasAction(before, after);
    setState(() {
      _encodingVersion = MCOImageEncodingVersion.v3;
      _paletteProfile = profile;
      _dynamicPaletteProfile = dynamicProfile;
      _selectedColor = selectedColor;
      _transparentColor = image.transparentColor;
      _isPickingTransparentColor = false;
      _width = image.width;
      _height = image.height;
      _setControllerValue(_widthController, _width);
      _setControllerValue(_heightController, _height);
      _pixels = List<int>.of(image.pixels);
      _selectedTool = _CanvasTool.pencil;
      _selectedV4FigureIndex = null;
      _v4Document = null;
      _v4ReferencePixels = null;
      _v4ReferencePaletteProfile = null;
      _v4ReferenceTransparentColor = null;
      _v4ReferenceVisible = true;
      _currentEncodedV4 = null;
      _v4EncodeError = null;
      _lineStartIndex = null;
      _ovalFirstIndex = null;
      _ovalSecondIndex = null;
      _rectangleFirstIndex = null;
      _rectangleSecondIndex = null;
      _currentEncodedCandidate = null;
      _currentEncodedCacheKey = null;
    });
    _markPayloadDirty();
    unawaited(_saveEncodingVersion(MCOImageEncodingVersion.v3));
    unawaited(_saveCanvasSize(image.width, image.height));
    unawaited(_saveCanvasPalette(profile));
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
    if (_isVectorV4) {
      _trimVectorCanvas();
      return;
    }

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

  void _trimVectorCanvas() {
    final document = _v4Document;
    if (document == null) return;

    Rect? bounds;
    final canvasBounds = Rect.fromLTWH(
      0,
      0,
      document.width.toDouble(),
      document.height.toDouble(),
    );
    for (final figure in document.figures.where((figure) => figure.visible)) {
      final figureBounds =
          MCOImageV4Painter.figureLogicalBounds(figure).intersect(canvasBounds);
      if (figureBounds.isEmpty) continue;
      bounds = bounds == null
          ? figureBounds
          : bounds.expandToInclude(figureBounds);
    }

    final trimBounds = bounds;
    if (trimBounds == null) return;

    final minX = trimBounds.left.floor().clamp(0, document.width - 1).toInt();
    final minY = trimBounds.top.floor().clamp(0, document.height - 1).toInt();
    final maxX = (trimBounds.right.ceil() - 1)
        .clamp(minX, document.width - 1)
        .toInt();
    final maxY = (trimBounds.bottom.ceil() - 1)
        .clamp(minY, document.height - 1)
        .toInt();
    final targetWidth = math.max(_minCanvasSize, maxX - minX + 1);
    final targetHeight = math.max(_minCanvasSize, maxY - minY + 1);
    if (targetWidth == document.width && targetHeight == document.height) {
      return;
    }

    _cancelPayloadCalculationBeforeCanvasReplacement();
    final nextDocument = document.copyWith(
      width: targetWidth,
      height: targetHeight,
      figures: document.figures
          .map((figure) => figure.translated(-minX, -minY))
          .toList(),
    );
    final referencePixels = _v4ReferencePixels;
    final nextReferencePixels =
        referencePixels != null &&
            referencePixels.length == document.width * document.height
        ? _cropPixelsFromOrigin(
            sourcePixels: referencePixels,
            sourceWidth: document.width,
            sourceHeight: document.height,
            sourceStartX: minX,
            sourceStartY: minY,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            fillColor: MCOImagePalette.whiteIndexFor(
              _v4ReferencePaletteProfile ?? _paletteProfile,
            ),
          )
        : null;
    final nextPixels = List<int>.filled(targetWidth * targetHeight, _whiteIndex);
    final before = _captureCanvasSnapshot();
    final after = _captureCanvasSnapshot(
      width: targetWidth,
      height: targetHeight,
      pixels: nextPixels,
      vectorDocument: nextDocument,
      vectorReferencePixels: nextReferencePixels,
      vectorReferencePaletteProfile:
          nextReferencePixels == null ? null : _v4ReferencePaletteProfile,
      vectorReferenceTransparentColor: nextReferencePixels == null
          ? null
          : _v4ReferenceTransparentColor,
    );
    _rememberCanvasAction(before, after);
    if (_snapshotsEqual(before, after)) return;

    setState(() {
      _width = targetWidth;
      _height = targetHeight;
      _setControllerValue(_widthController, targetWidth);
      _setControllerValue(_heightController, targetHeight);
      _pixels = nextPixels;
      _v4Document = nextDocument;
      _v4ReferencePixels = nextReferencePixels;
      if (nextReferencePixels == null) {
        _v4ReferencePaletteProfile = null;
        _v4ReferenceTransparentColor = null;
      }
      _selectedV4FigureIndex = null;
      _clearVectorDraftState();
      _clearVectorEditingState();
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
    if (_isVectorV4) {
      _payloadRefreshRequestId++;
      _currentEncodedCacheKey = null;
      _currentEncodedCandidate = null;
      _payloadRefreshTimer?.cancel();
      _payloadRefreshTimer = null;
      unawaited(_cancelCurrentEncoding());
      _calculateVectorPayload();
      return;
    }
    _payloadRefreshRequestId++;
    _currentEncodedCacheKey = null;

    if (!_payloadRefreshPending && mounted) {
      setState(() {
        _payloadRefreshPending = true;
        _payloadRefreshProgressPercent = null;
        _payloadRefreshElapsed = null;
      });
    } else {
      _payloadRefreshPending = true;
      _payloadRefreshProgressPercent = null;
      _payloadRefreshElapsed = null;
    }

    // Stop the workers that are encoding the previous canvas/settings state.
    // There is no need to await cancellation here: if the debounce expires
    // before the old refresh has fully unwound, _refreshPayloadIfIdle() will
    // see _payloadRefreshInProgress and reschedule itself.
    unawaited(_cancelCurrentEncoding(preservePendingRefresh: true));

    // Reuse the existing debounce. Every subsequent canvas/settings change
    // resets this timer, so only one encoding starts after the user pauses.
    _schedulePayloadRefresh();
  }

  void _calculateVectorPayload() {
    final document = _v4Document;
    if (document == null) return;
    try {
      final encoded = _v4Codec.encode(
        document,
        nonce: 0,
        targetName: widget.replyTargetName,
        replyTimestamp: widget.replyTimestamp,
      );
      final payloadSize = _payloadSizeForEncodedV4(encoded);
      if (!mounted) {
        _currentEncodedV4 = encoded;
        _currentPayloadChars = payloadSize;
        _v4EncodeError = null;
        return;
      }
      setState(() {
        _currentEncodedV4 = encoded;
        _currentPayloadChars = payloadSize;
        _v4EncodeError = null;
        _payloadRefreshPending = false;
        _payloadRefreshInProgress = false;
        _payloadRefreshProgressPercent = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        _currentEncodedV4 = null;
        _v4EncodeError = error;
        return;
      }
      setState(() {
        _currentEncodedV4 = null;
        _v4EncodeError = error;
        _payloadRefreshPending = false;
        _payloadRefreshInProgress = false;
        _payloadRefreshProgressPercent = null;
      });
    }
  }

  bool _cancelPayloadCalculationBeforeCanvasReplacement() {
    final hadPendingRefresh = _payloadRefreshPending;
    _currentEncodedCacheKey = null;
    _payloadRefreshProgressPercent = null;
    _payloadRefreshElapsed = null;

    // File loading and other whole-canvas replacements can spend noticeable
    // time before _markPayloadDirty() is reached. Stop stale encoders now so
    // their progress/debug output does not continue for the previous canvas.
    unawaited(_cancelCurrentEncoding(preservePendingRefresh: true));
    return hadPendingRefresh;
  }

  void _queueInitialPayloadRefresh() {
    if (_isVectorV4) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _calculateVectorPayload();
      });
      return;
    }
    _payloadRefreshPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _schedulePayloadRefresh();
    });
  }

  void _schedulePayloadRefresh() {
    if (!mounted) return;
    _payloadRefreshTimer?.cancel();
    _payloadRefreshTimer = Timer(
      _payloadRefreshDebounce,
      () => unawaited(_refreshPayloadIfIdle()),
    );
  }

  Future<void> _refreshPayloadIfIdle() async {
    _payloadRefreshTimer = null;
    if (!mounted || !_payloadRefreshPending) return;

    // While the user is actively drawing, keep the canvas responsive and refresh
    // payload size after the gesture settles.
    if (_isDrawing || _payloadRefreshInProgress) {
      _schedulePayloadRefresh();
      return;
    }

    _payloadRefreshPending = false;
    final requestId = _payloadRefreshRequestId;
    final refreshCompletion = Completer<void>();
    _payloadRefreshCompletion = refreshCompletion;
    setState(() {
      _payloadRefreshInProgress = true;
      _payloadRefreshProgressPercent = 0;
      _payloadRefreshStopwatch = Stopwatch()..start();
      _payloadRefreshElapsed = Duration.zero;
    });
    _startPayloadRefreshElapsedTimer(requestId);

    final encodeRequest = _buildEncodeRequest();
    EncodedMCOImage? encoded;
    try {
      encoded = await _encodeCanvasInBackground(
        request: encodeRequest,
        onProgress: (progressPercent) {
          _setPayloadRefreshProgress(requestId, progressPercent);
        },
      );
    } on CancellableComputeCancelledException {
      // Cancellation is expected when the canvas/settings change or when this
      // screen is being disposed.
    } on MCOImageCodecException catch (error, stackTrace) {
      // Keep the last valid payload value. A later canvas change will schedule
      // another calculation.
      debugPrint('[MCOimg] Background encode failed: $error');
      debugPrintStack(
        label: '[MCOimg] Background encode stack trace',
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      // Preserve the last valid value if a worker fails unexpectedly. Log the
      // real error instead of silently leaving the initial counter at zero.
      debugPrint('[MCOimg] Background worker failed: $error');
      debugPrintStack(
        label: '[MCOimg] Background worker stack trace',
        stackTrace: stackTrace,
      );
    }

    // The widget may have been disposed while the background isolate was
    // finishing. Do not touch State after that point.
    if (!mounted) {
      _completePayloadRefreshCycle(refreshCompletion);
      return;
    }

    final isCurrentResult = requestId == _payloadRefreshRequestId;
    final elapsed = _payloadRefreshStopwatch?.elapsed ?? Duration.zero;
    _stopPayloadRefreshElapsedTimer();
    setState(() {
      if (isCurrentResult && encoded != null) {
        _currentEncodedCandidate = encoded;
        _currentEncodedCacheKey = _MCOImageEncodeCacheKey.fromRequest(
          encodeRequest,
        );
        _currentPayloadChars = _displayPayloadSizeForEncoded(encoded);
      }

      // This flag belongs to the only active refresh operation. It must be
      // cleared even when its result became stale while the user was drawing.
      _payloadRefreshInProgress = false;
      _payloadRefreshProgressPercent = null;
      _payloadRefreshElapsed = isCurrentResult ? elapsed : null;
      _payloadRefreshStopwatch = null;
    });
    if (isCurrentResult && encoded != null) {
      _logPayloadRefreshComplete(encoded, encodeRequest, elapsed);
    }

    // If the canvas changed during this calculation, _markPayloadDirty()
    // has normally already started the debounce timer. Only create one here
    // when that timer has already fired while the previous refresh was still
    // unwinding.
    if (_payloadRefreshPending && _payloadRefreshTimer == null) {
      _schedulePayloadRefresh();
    }

    _completePayloadRefreshCycle(refreshCompletion);
  }

  void _completePayloadRefreshCycle(Completer<void> completion) {
    if (identical(_payloadRefreshCompletion, completion)) {
      _payloadRefreshCompletion = null;
    }
    if (!completion.isCompleted) {
      completion.complete();
    }
  }

  void _logPayloadRefreshComplete(
    EncodedMCOImage encoded,
    _MCOImageEncodeRequest request,
    Duration elapsed,
  ) {
    debugPrint(
      '[MCOimg][${_compressionLevelDebugLabel(request.compressionLevel)}] '
      'CANVAS COMPLETE; '
      'version=v${encoded.codecVersion}; '
      'size=${request.width}x${request.height}; '
      'payload=${_displayPayloadSizeForEncoded(encoded)}; '
      'bytes=${encoded.byteLength}; '
      'chars=${encoded.charLength}; '
      'elapsed=${_formatPayloadRefreshElapsed(elapsed)}; '
      'algorithm=${_encodingAlgorithmLabel(encoded)}; '
      'container=${encoded.container}; '
      'mode=${encoded.mode.name}; '
      'scan=${encoded.scan.name}; '
      'bg=${encoded.backgroundColor ?? -1}; '
      'bgRank=${encoded.backgroundRank}; '
      'regions=${encoded.regionCount}; '
      'bounds=${encoded.boundsPresent};',
    );
  }

  void _startPayloadRefreshElapsedTimer(int requestId) {
    _payloadRefreshElapsedTimer?.cancel();
    _payloadRefreshElapsedTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updatePayloadRefreshElapsed(requestId),
    );
  }

  void _stopPayloadRefreshElapsedTimer() {
    _payloadRefreshElapsedTimer?.cancel();
    _payloadRefreshElapsedTimer = null;
  }

  void _updatePayloadRefreshElapsed(int requestId) {
    if (!mounted ||
        requestId != _payloadRefreshRequestId ||
        !_payloadRefreshInProgress) {
      _stopPayloadRefreshElapsedTimer();
      return;
    }
    final elapsed = _payloadRefreshStopwatch?.elapsed;
    if (elapsed == null || _payloadRefreshElapsed == elapsed) return;
    setState(() => _payloadRefreshElapsed = elapsed);
  }

  void _setPayloadRefreshProgress(int requestId, int progressPercent) {
    if (!mounted ||
        requestId != _payloadRefreshRequestId ||
        !_payloadRefreshInProgress) {
      return;
    }
    final clamped = progressPercent.clamp(0, 100).toInt();
    final elapsed = _payloadRefreshStopwatch?.elapsed;
    if (_payloadRefreshProgressPercent == clamped &&
        _payloadRefreshElapsed == elapsed) {
      return;
    }
    setState(() {
      _payloadRefreshProgressPercent = clamped;
      _payloadRefreshElapsed = elapsed;
    });
  }

  String _payloadCalculatingLabel(
    BuildContext context, {
    int? progressPercent,
    Duration? elapsed,
  }) {
    const placeholder = -987654321;
    final label = context.l10n
        .chat_canvasCurrentPayload(placeholder)
        .replaceFirst('$placeholder', '...');
    final details = <String>[];
    if (progressPercent != null) details.add('$progressPercent%');
    if (elapsed != null) details.add(_formatPayloadRefreshElapsed(elapsed));
    if (details.isEmpty) return label;
    return '$label (${details.join(', ')})';
  }

  String _payloadReadyLabel(BuildContext context, int payloadSize) {
    final label = context.l10n.chat_canvasCurrentPayload(payloadSize);
    final elapsed = _payloadRefreshElapsed;
    if (elapsed == null) return label;
    return '$label (${_formatPayloadRefreshElapsed(elapsed)})';
  }

  String _formatPayloadRefreshElapsed(Duration elapsed) {
    final milliseconds = elapsed.inMilliseconds;
    if (milliseconds < 1000) return '${milliseconds}ms';
    final seconds = milliseconds / 1000;
    if (seconds < 10) return '${seconds.toStringAsFixed(1)}s';
    return '${seconds.round()}s';
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
    parts.add(
      'codec ${candidate.byteLength} B / ${candidate.charLength} chars',
    );
    final localPaletteSize = candidate.localPaletteSize;
    final bitsPerPixel = candidate.bitsPerLocalPixel;
    if (localPaletteSize != null && bitsPerPixel != null) {
      final paletteLabel = candidate.container.startsWith('direct-dynamic')
          ? 'profile'
          : 'local';
      parts.add('$paletteLabel ${localPaletteSize}c/${bitsPerPixel}b');
    }
    final usedBankCount = candidate.usedBankCount;
    if (usedBankCount != null) parts.add('$usedBankCount banks');
    if (candidate.paletteKind == 'dynamic' &&
        _paletteProfile.isDynamic &&
        candidate.backgroundColor ==
            MCOImageDynamicPalette.whiteGlobalIndexFor(_paletteProfile)) {
      parts.add('implicit white bg');
    }
    switch (candidate.dynamicReferenceEncoding) {
      case DynamicPaletteReferenceEncoding.sortedDelta:
        parts.add('palette delta');
        break;
      case DynamicPaletteReferenceEncoding.rangeRuns:
        parts.add('palette ranges');
        break;
      case DynamicPaletteReferenceEncoding.profileBitmap:
        parts.add('palette bitmap');
        break;
      case DynamicPaletteReferenceEncoding.bankBitmaps:
        parts.add('palette bank bitmaps');
        break;
      case DynamicPaletteReferenceEncoding.flat:
      case DynamicPaletteReferenceEncoding.banked8x64:
      case null:
        break;
    }
    return parts.join(' | ');
  }

  String _encodingAlgorithmLabel(EncodedMCOImage candidate) {
    const importedPrefix = 'imported-bin:';
    if (candidate.container.startsWith(importedPrefix)) {
      return candidate.container.substring(importedPrefix.length);
    }
    if (candidate.actualEncodingVersion == MCOImageEncodingVersion.v3) {
      try {
        return MCOImageV3Codec.inspectBody(candidate.payload).algorithm;
      } on MCOImageCodecException {
        return candidate.mode.name;
      }
    }
    return candidate.container;
  }

  String _encodingContainerLabel(EncodedMCOImage candidate) {
    final container = candidate.container;
    const importedPrefix = 'imported-bin:';
    if (container.startsWith(importedPrefix)) {
      return container.substring(importedPrefix.length);
    }
    if (container.startsWith('compactRegionsStream')) {
      final suffix = container.substring('compactRegionsStream'.length);
      final details = suffix.isEmpty
          ? ''
          : ' ${suffix.substring(1).replaceAll('-', ' ')}';
      return 'Regions compact$details x${candidate.regionCount}';
    }
    if (candidate.actualEncodingVersion == MCOImageEncodingVersion.v3) {
      final algorithm = _encodingAlgorithmLabel(candidate);
      return algorithm == 'Regions'
          ? 'Regions x${candidate.regionCount}'
          : algorithm;
    }
    return switch (candidate.container) {
      'regions' => 'Regions x${candidate.regionCount}',
      'regions-beam' => 'Regions beam x${candidate.regionCount}',
      'regions-extended' => 'Regions extended x${candidate.regionCount}',
      'regions-beam-extended' =>
        'Regions beam extended x${candidate.regionCount}',
      'regions-shared-fixed' =>
        'Regions shared palette x${candidate.regionCount}',
      'regions-beam-shared-fixed' =>
        'Regions beam shared palette x${candidate.regionCount}',
      'regions-shared-fixed-extended' =>
        'Regions shared palette extended x${candidate.regionCount}',
      'regions-beam-shared-fixed-extended' =>
        'Regions beam shared palette extended x${candidate.regionCount}',
      'solid-bg' => 'Solid background',
      'solid-rects' => 'Solid rectangles',
      'compact-bounds' => 'Compact bounds',
      'compact-rle' => 'Compact RLE',
      'compact-rle-bounds' => 'Compact RLE bounds',
      'compact-sparse' => 'Compact sparse',
      'compact-sparse-bounds' => 'Compact sparse bounds',
      'lz-pixels' => 'LZ pixels',
      'lz-pixels-bounds' => 'LZ pixels bounds',
      'lz-pixels-optimal' => 'LZ pixels optimal',
      'lz-pixels-optimal-bounds' => 'LZ pixels optimal bounds',
      'quadtree' => 'Quadtree',
      'quadtree-bounds' => 'Quadtree bounds',
      'bitplanes' => 'Bitplanes',
      'bitplanes-bounds' => 'Bitplanes bounds',
      'adaptive-bitplanes' => 'Adaptive bitplanes',
      'adaptive-bitplanes-bounds' => 'Adaptive bitplanes bounds',
      'adaptive-bitplanes-optimized' => 'Adaptive bitplanes optimized',
      'adaptive-bitplanes-optimized-bounds' =>
        'Adaptive bitplanes optimized bounds',
      'adaptive-bitplanes-profile-order' => 'Adaptive bitplanes profile order',
      'adaptive-bitplanes-profile-order-bounds' =>
        'Adaptive bitplanes profile order bounds',
      'adaptive-bitplanes-rgb-order' => 'Adaptive bitplanes RGB order',
      'adaptive-bitplanes-rgb-order-bounds' =>
        'Adaptive bitplanes RGB order bounds',
      'adaptive-bitplanes-transition-order' =>
        'Adaptive bitplanes transition order',
      'adaptive-bitplanes-transition-order-bounds' =>
        'Adaptive bitplanes transition order bounds',
      'adaptive-bitplanes-multistart' => 'Adaptive bitplanes multi-start',
      'adaptive-bitplanes-multistart-bounds' =>
        'Adaptive bitplanes multi-start bounds',
      'direct-grayscale-bitplanes' => 'Direct grayscale bitplanes',
      'direct-grayscale-bitplanes-bounds' =>
        'Direct grayscale bitplanes bounds',
      'direct-dynamic-bitplanes' => 'Direct dynamic bitplanes',
      'direct-dynamic-bitplanes-bounds' => 'Direct dynamic bitplanes bounds',
      'compact-row-delta' => 'Compact row delta',
      'compact-row-delta-bounds' => 'Compact row delta bounds',
      'compact-row-delta-palette-optimized' =>
        'Compact row delta optimized palette',
      'compact-row-delta-palette-exhaustive' =>
        'Compact row delta exhaustive palette',
      'compact-row-delta-palette-optimized-bounds' =>
        'Compact row delta optimized palette bounds',
      'compact-row-delta-palette-exhaustive-bounds' =>
        'Compact row delta exhaustive palette bounds',
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
      final payloadBytes =
          encoded.actualEncodingVersion == MCOImageEncodingVersion.v3
          ? ChannelBinaryDataHelper.appBinaryEnvelopeLength(
              bodyLength: encoded.payload.length,
              senderName: widget.binarySenderName ?? 'Me',
            )
          : ChannelBinaryDataHelper.binaryEnvelopeLength(
              bodyLength: encoded.payload.length,
              senderName: widget.binarySenderName ?? 'Me',
            );
      return payloadBytes;
    }
    if (encoded.actualEncodingVersion == MCOImageEncodingVersion.v3) {
      return MCOImageV3Codec.textFromBody(encoded.payload).length;
    }
    return encoded.charLength;
  }

  int _payloadSizeForEncodedV4(EncodedMCOImageV4 encoded) {
    final binaryLimit = widget.maxBinaryPayloadBytes;
    if (binaryLimit != null) {
      return ChannelBinaryDataHelper.appBinaryEnvelopeLength(
        bodyLength: encoded.body.length,
        senderName: widget.binarySenderName ?? 'Me',
      );
    }
    return _v4Codec.textFromBody(encoded.body).length;
  }

  int _displayPayloadSizeForEncoded(EncodedMCOImage encoded) {
    return _payloadSizeForEncoded(encoded);
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

    if (unlockAdaptiveLimit ||
        !_usesRasterAdaptiveCanvasLimit(
          encodingVersion ?? _encodingVersion,
        )) {
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

  bool _usesRasterAdaptiveCanvasLimit(MCOImageEncodingVersion version) {
    return version != MCOImageEncodingVersion.v4;
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
    if (_isVectorV4) {
      _changeVectorPaletteProfile(profile);
      return;
    }
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

  void _changeVectorPaletteProfile(PaletteProfile profile) {
    final document = _v4Document;
    if (document == null) return;
    final newPaletteColors = _paletteFor(profile);
    final newDocumentPalette = _vectorDocumentPaletteFor(profile);

    int mapColorValue(int colorValue) {
      final argb = _profileColor(document.paletteProfile, colorValue).toARGB32();
      return _nearestPaletteColorValue(
        (argb >> 16) & 0xff,
        (argb >> 8) & 0xff,
        argb & 0xff,
        (argb >> 24) & 0xff,
        profile,
        newPaletteColors,
        whiteIndex: MCOImagePalette.whiteIndexFor(profile),
      );
    }

    int? mapLocalColor(int? localIndex) {
      if (localIndex == null) return null;
      if (localIndex < 0 || localIndex >= document.palette.length) return null;
      final mappedValue = mapColorValue(document.palette[localIndex]);
      var nextIndex = newDocumentPalette.indexOf(mappedValue);
      if (nextIndex < 0) {
        newDocumentPalette.add(mappedValue);
        nextIndex = newDocumentPalette.length - 1;
      }
      return nextIndex;
    }

    MCOImageV4Figure mapFigure(MCOImageV4Figure figure) {
      final style = figure.style;
      if (figure is MCOImageV4Group) {
        return MCOImageV4Group(
          figures: figure.figures.map(mapFigure).toList(growable: false),
          style: style.copyWith(
            fillColor: mapLocalColor(style.fillColor),
            strokeColor: mapLocalColor(style.strokeColor),
          ),
          visible: figure.visible,
        );
      }
      return figure.withStyle(
        style.copyWith(
          fillColor: mapLocalColor(style.fillColor),
          strokeColor: mapLocalColor(style.strokeColor),
        ),
      );
    }

    final nextDocument = document.copyWith(
      paletteProfile: profile,
      palette: newDocumentPalette,
      backgroundColor: mapLocalColor(document.backgroundColor),
      initialStyle: document.initialStyle.copyWith(
        fillColor: mapLocalColor(document.initialStyle.fillColor),
        strokeColor: mapLocalColor(document.initialStyle.strokeColor),
      ),
      figures: document.figures.map(mapFigure).toList(growable: false),
    );
    final nextDynamicProfile = profile.isDynamic
        ? profile
        : _dynamicPaletteProfile;
    final nextSelectedColor = mapColorValue(_selectedColor);
    final nextFillColor = mapLocalColor(_v4FillColor);
    final nextStrokeColor = mapLocalColor(_v4StrokeColor);
    final before = _captureCanvasSnapshot();
    final nextPixels = List<int>.filled(
      nextDocument.width * nextDocument.height,
      MCOImagePalette.whiteIndexFor(profile),
    );
    final after = _captureCanvasSnapshot(
      paletteProfile: profile,
      dynamicPaletteProfile: nextDynamicProfile,
      selectedColor: nextSelectedColor,
      pixels: nextPixels,
      vectorDocument: nextDocument,
    );
    _rememberCanvasAction(before, after);
    setState(() {
      _paletteProfile = profile;
      _dynamicPaletteProfile = nextDynamicProfile;
      _selectedColor = nextSelectedColor;
      _v4FillColor = nextFillColor;
      _v4StrokeColor = nextStrokeColor;
      _transparentColor = null;
      _pixels = nextPixels;
      _v4Document = nextDocument;
      _clearVectorDraftState();
    });
    _markPayloadDirty();
    unawaited(_saveCanvasPalette(profile));
  }

  void _cancelPendingShape() {
    if (_isVectorV4) {
      if (_v4ShapePoints.isEmpty &&
          _v4DraftFigure == null &&
          _v4PencilPoints == null) {
        return;
      }
      setState(_clearVectorDraftState);
      return;
    }
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

  void _clearRasterDraftState() {
    _lineStartIndex = null;
    _ovalFirstIndex = null;
    _ovalSecondIndex = null;
    _rectangleFirstIndex = null;
    _rectangleSecondIndex = null;
  }

  void _clearVectorDraftState() {
    _v4ShapePoints.clear();
    _v4DraftFigure = null;
    _v4PencilPoints = null;
    _v4GestureStart = null;
    _v4LastMovePoint = null;
    _v4MoveBefore = null;
  }

  void _clearVectorEditingState() {
    _editingV4FigureIndex = null;
    _editingV4FigureBefore = null;
    _editingV4FigureVisible = true;
  }

  int? _vectorColorValueForLocalIndex(
    MCOImageV4Document document,
    int? localIndex,
  ) {
    if (localIndex == null ||
        localIndex < 0 ||
        localIndex >= document.palette.length) {
      return null;
    }
    return document.palette[localIndex];
  }

  List<int> _vectorStylePaletteValues(MCOImageV4Document document) {
    final profile = document.paletteProfile;
    if (!profile.isDynamic) {
      return List<int>.generate(
        MCOImagePalette.colorsFor(profile).length,
        (index) => index,
        growable: false,
      );
    }
    final profileColors = MCOImageDynamicPalette.indicesFor(profile);
    if (profileColors.length <= _inlineDynamicPaletteMaxColors) {
      return List<int>.of(profileColors, growable: false);
    }
    final colors = document.palette.where((colorValue) {
      return _paletteIndexForColorValue(profile, colorValue) != null;
    }).toSet().toList();
    colors.sort((a, b) {
      final aIndex = _paletteIndexForColorValue(profile, a) ?? 0;
      final bIndex = _paletteIndexForColorValue(profile, b) ?? 0;
      return aIndex.compareTo(bIndex);
    });
    return colors;
  }

  void _adoptVectorStyle(MCOImageV4Style style) {
    _v4FillColor = style.fillColor;
    _v4StrokeColor = style.strokeColor;
    _v4StrokeWidth = math.max(1, style.strokeWidth);
    _v4ColorTarget = style.strokeColor == null && style.fillColor != null
        ? _V4ColorTarget.fill
        : _V4ColorTarget.stroke;
    final document = _v4Document;
    final localIndex = style.strokeColor ?? style.fillColor;
    if (document != null &&
        localIndex != null &&
        localIndex >= 0 &&
        localIndex < document.palette.length) {
      _selectedColor = document.palette[localIndex];
    }
  }

  void _recordVectorDocumentChange(
    MCOImageV4Document before,
    MCOImageV4Document after,
  ) {
    _rememberCanvasAction(
      _captureCanvasSnapshot(vectorDocument: before),
      _captureCanvasSnapshot(
        width: after.width,
        height: after.height,
        pixels: List<int>.filled(after.width * after.height, _whiteIndex),
        vectorDocument: after,
      ),
    );
  }

  void _updateVectorStyle(
    VoidCallback update, {
    bool recordUndo = true,
    MCOImageV4Document? undoBefore,
  }) {
    final before = undoBefore ?? _v4Document;
    final index = _selectedV4FigureIndex;
    if (before == null || index == null || index >= before.figures.length) {
      setState(update);
      return;
    }
    MCOImageV4Document? after;
    setState(() {
      update();
      final current = _v4Document ?? before;
      final figures = [...current.figures];
      if (index < figures.length) {
        figures[index] = figures[index].withStyle(_currentVectorStyle());
        after = current.copyWith(figures: figures);
        _v4Document = after;
      }
    });
    final next = after;
    if (next == null) return;
    if (recordUndo) _recordVectorDocumentChange(before, next);
    _markPayloadDirty();
  }

  void _beginVectorStyleDrag() {
    final document = _v4Document;
    final index = _selectedV4FigureIndex;
    _v4StyleDragBefore =
        document != null && index != null && index < document.figures.length
        ? document
        : null;
  }

  void _endVectorStyleDrag() {
    final before = _v4StyleDragBefore;
    final after = _v4Document;
    _v4StyleDragBefore = null;
    if (before == null || after == null || identical(before, after)) return;
    _recordVectorDocumentChange(before, after);
  }

  void _setVectorBackground(int? localIndex) {
    final document = _v4Document;
    if (document == null || document.backgroundColor == localIndex) return;
    _commitVectorDocument(document.copyWith(backgroundColor: localIndex));
  }

  void _setVectorBackgroundProfileColor(int? colorValue) {
    final localIndex = colorValue == null
        ? null
        : _vectorLocalColorIndex(colorValue, mutate: true);
    _setVectorBackground(localIndex);
  }

  void _toggleVectorReferenceVisibility() {
    if (_v4ReferencePixels == null) return;
    setState(() => _v4ReferenceVisible = !_v4ReferenceVisible);
  }

  void _setVectorStyleColor(int? localIndex, {MCOImageV4Document? undoBefore}) {
    final document = _v4Document;
    if (document == null) return;
    _updateVectorStyle(
      () {
        if (_v4ColorTarget == _V4ColorTarget.fill) {
          _v4FillColor = localIndex;
        } else {
          _v4StrokeColor = localIndex;
        }
        if (localIndex != null && localIndex < document.palette.length) {
          _selectedColor = document.palette[localIndex];
        }
      },
      undoBefore: undoBefore ?? document,
    );
  }

  void _setVectorStyleProfileColor(int? colorValue) {
    final before = _v4Document;
    final localIndex = colorValue == null
        ? null
        : _vectorLocalColorIndex(colorValue, mutate: true);
    _setVectorStyleColor(localIndex, undoBefore: before);
    if (before != null && _selectedV4FigureIndex == null) {
      _markPayloadDirty();
    }
  }

  void _setVectorStrokeWidth(int width, {bool recordUndo = true}) {
    _updateVectorStyle(
      () => _v4StrokeWidth = math.max(1, width),
      recordUndo: recordUndo,
    );
  }

  void _setSelectedVectorClosed(bool closed) {
    final document = _v4Document;
    final index = _selectedV4FigureIndex;
    if (document == null || index == null || index >= document.figures.length) {
      return;
    }
    final figures = [...document.figures];
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
    _commitVectorDocument(document.copyWith(figures: figures));
  }

  void _selectVectorFigure(int? index) {
    final document = _v4Document;
    if (document == null ||
        index == null ||
        index < 0 ||
        index >= document.figures.length) {
      setState(() {
        _selectedV4FigureIndex = null;
        _v4AppendGroupIndex = null;
      });
      return;
    }
    setState(() {
      _selectedV4FigureIndex = index;
      if (_v4AppendGroupIndex != index) {
        _v4AppendGroupIndex = null;
      }
      _adoptVectorStyle(document.figures[index].style);
    });
  }

  void _toggleVectorFigureVisibility(int index) {
    final document = _v4Document;
    if (document == null || index < 0 || index >= document.figures.length) {
      return;
    }
    final figures = [...document.figures];
    figures[index] = figures[index].withVisibility(!figures[index].visible);
    _commitVectorDocument(document.copyWith(figures: figures));
  }

  void _deleteVectorFigure(int index) {
    final document = _v4Document;
    if (document == null || index < 0 || index >= document.figures.length) {
      return;
    }
    final nextGroupSelectionIndexes = _v4GroupSelectionIndexes
        .where((value) => value != index)
        .map((value) => value > index ? value - 1 : value)
        .toSet();
    final figures = [...document.figures]..removeAt(index);
    _selectedV4FigureIndex = null;
    _v4AppendGroupIndex = null;
    _v4GroupSelectionIndexes
      ..clear()
      ..addAll(nextGroupSelectionIndexes);
    _commitVectorDocument(document.copyWith(figures: figures));
  }

  void _reorderVectorFigure(int from, int to) {
    final document = _v4Document;
    if (document == null ||
        from < 0 ||
        from >= document.figures.length ||
        to < 0 ||
        to >= document.figures.length) {
      return;
    }
    final figures = [...document.figures];
    final figure = figures.removeAt(from);
    figures.insert(to, figure);
    _selectedV4FigureIndex = to;
    _v4AppendGroupIndex = null;
    _v4GroupSelectionIndexes.clear();
    _v4GroupSelectionMode = false;
    _commitVectorDocument(document.copyWith(figures: figures));
  }

  void _normalizeV4GroupState(MCOImageV4Document document) {
    _v4GroupSelectionIndexes.removeWhere(
      (index) => index < 0 || index >= document.figures.length,
    );
    final appendIndex = _v4AppendGroupIndex;
    if (appendIndex == null) return;
    if (appendIndex < 0 ||
        appendIndex >= document.figures.length ||
        document.figures[appendIndex] is! MCOImageV4Group) {
      _v4AppendGroupIndex = null;
    }
  }

  void _toggleV4GroupSelectionMode() {
    final document = _v4Document;
    if (document == null || document.figures.isEmpty) return;
    setState(() {
      _v4GroupSelectionMode = !_v4GroupSelectionMode;
      if (_v4GroupSelectionMode) {
        _v4AppendGroupIndex = null;
        final selected = _selectedV4FigureIndex;
        _v4GroupSelectionIndexes
          ..clear()
          ..addAll(
            selected != null &&
                    selected >= 0 &&
                    selected < document.figures.length
                ? <int>[selected]
                : const <int>[],
          );
      } else {
        _v4GroupSelectionIndexes.clear();
      }
    });
  }

  void _cancelV4GroupSelection() {
    setState(() {
      _v4GroupSelectionMode = false;
      _v4GroupSelectionIndexes.clear();
    });
  }

  void _setV4FigureCheckedForGroup(int index, bool selected) {
    setState(() {
      if (selected) {
        _v4GroupSelectionIndexes.add(index);
      } else {
        _v4GroupSelectionIndexes.remove(index);
      }
    });
  }

  void _toggleV4FigureCheckedForGroup(int index) {
    _setV4FigureCheckedForGroup(
      index,
      !_v4GroupSelectionIndexes.contains(index),
    );
  }

  bool get _canMergeCheckedV4Figures {
    final document = _v4Document;
    if (document == null) return false;
    return _validV4GroupSelectionIndexes(document).length >= 2;
  }

  List<int> _validV4GroupSelectionIndexes(MCOImageV4Document document) {
    final indexes = _v4GroupSelectionIndexes
        .where((index) => index >= 0 && index < document.figures.length)
        .toList();
    indexes.sort();
    return indexes;
  }

  void _mergeCheckedV4Figures() {
    final document = _v4Document;
    if (document == null) return;
    final selectedIndexes = _validV4GroupSelectionIndexes(document);
    if (selectedIndexes.length < 2) return;
    final selectedSet = selectedIndexes.toSet();
    final insertIndex = selectedIndexes.first;
    final groupFigures = <MCOImageV4Figure>[];
    var groupVisible = false;
    for (final index in selectedIndexes) {
      final figure = document.figures[index];
      groupVisible = groupVisible || figure.visible;
      if (figure is MCOImageV4Group) {
        groupFigures.addAll(figure.figures);
      } else {
        groupFigures.add(figure);
      }
    }
    final figures = <MCOImageV4Figure>[];
    for (var index = 0; index < document.figures.length; index++) {
      if (index == insertIndex) {
        figures.add(
          MCOImageV4Group(
            figures: groupFigures,
            visible: groupVisible,
          ),
        );
      }
      if (!selectedSet.contains(index)) {
        figures.add(document.figures[index]);
      }
    }
    _commitVectorDocument(document.copyWith(figures: figures));
    setState(() {
      _selectedV4FigureIndex = insertIndex;
      _v4GroupSelectionMode = false;
      _v4GroupSelectionIndexes.clear();
      _v4AppendGroupIndex = null;
      _selectedTool = _CanvasTool.select;
    });
  }

  MCOImageV4Document get _activeVectorDocument {
    final document = _v4Document;
    if (document == null) {
      throw StateError('MCOimg v4 vector document is not initialized');
    }
    final draft = _v4DraftFigure;
    if (draft == null) return document;
    final appendIndex = _v4AppendGroupIndex;
    if (appendIndex != null &&
        appendIndex >= 0 &&
        appendIndex < document.figures.length &&
        document.figures[appendIndex] is MCOImageV4Group) {
      final figures = [...document.figures];
      final group = figures[appendIndex] as MCOImageV4Group;
      figures[appendIndex] = MCOImageV4Group(
        figures: [...group.figures, draft],
        style: group.style,
        visible: group.visible,
      );
      return document.copyWith(figures: figures);
    }
    return document.copyWith(figures: [...document.figures, draft]);
  }

  MCOImageV4Figure? get _selectedV4Figure {
    final document = _v4Document;
    final index = _selectedV4FigureIndex;
    if (document == null || index == null || index >= document.figures.length) {
      return null;
    }
    return document.figures[index];
  }

  bool get _canCloneSelectedV4Figure => _selectedV4Figure != null;

  bool get _canEditSelectedV4Figure =>
      _selectedV4Figure != null && _selectedV4Figure is! MCOImageV4Group;

  bool get _canUngroupSelectedV4Figure => _selectedV4Figure is MCOImageV4Group;

  bool get _canAppendToSelectedV4Group =>
      _selectedV4Figure is MCOImageV4Group;

  bool get _isAppendingToSelectedV4Group =>
      _selectedV4FigureIndex != null &&
      _selectedV4FigureIndex == _v4AppendGroupIndex;

  void _toggleV4AppendToSelectedGroup() {
    final index = _selectedV4FigureIndex;
    final selected = _selectedV4Figure;
    if (index == null || selected is! MCOImageV4Group) return;
    setState(() {
      _v4GroupSelectionMode = false;
      _v4GroupSelectionIndexes.clear();
      _v4AppendGroupIndex = _v4AppendGroupIndex == index ? null : index;
      _selectedTool = _CanvasTool.select;
    });
  }

  bool get _showsCurrentVectorFinishButtons =>
      _v4ShapePoints.isNotEmpty &&
      (_selectedTool == _CanvasTool.polyline ||
          _isCurrentVectorAreaTool);

  bool get _isCurrentVectorAreaTool =>
      _selectedTool == _CanvasTool.rectangle ||
      _selectedTool == _CanvasTool.oval;

  bool get _canFinishCurrentVectorToolOpen =>
      _canFinishCurrentVectorPolylineOpen ||
      (_isCurrentVectorAreaTool && _v4ShapePoints.length >= 2);

  bool get _canFinishCurrentVectorPolylineOpen =>
      _selectedTool == _CanvasTool.polyline && _v4ShapePoints.length >= 2;

  bool get _canFinishCurrentVectorPolylineClosed =>
      _selectedTool == _CanvasTool.polyline && _v4ShapePoints.length >= 3;

  void _selectCanvasTool(_CanvasTool nextTool) {
    if (_isVectorV4) {
      _selectVectorTool(nextTool);
      return;
    }
    setState(() {
      if (nextTool != _selectedTool) {
        _clearRasterDraftState();
      }
      _selectedTool = nextTool;
    });
  }

  void _selectVectorTool(_CanvasTool nextTool) {
    final isSameTool = nextTool == _selectedTool;
    final finishedDraft = _finishCurrentVectorToolOpen();
    if (isSameTool && finishedDraft) {
      return;
    }
    if (!isSameTool && finishedDraft) {
      setState(() {
        if (nextTool != _CanvasTool.select) {
          _selectedV4FigureIndex = null;
          _v4GroupSelectionMode = false;
          _v4GroupSelectionIndexes.clear();
        }
        _selectedTool = nextTool;
      });
      return;
    }
    setState(() {
      if (nextTool == _selectedTool) {
        if (_selectedTool == _CanvasTool.line ||
            _selectedTool == _CanvasTool.rectangle ||
            _selectedTool == _CanvasTool.oval ||
            _selectedTool == _CanvasTool.wave) {
          _clearVectorDraftState();
        }
        return;
      }
      _clearVectorDraftState();
      if (nextTool != _CanvasTool.select) {
        _selectedV4FigureIndex = null;
        _v4GroupSelectionMode = false;
        _v4GroupSelectionIndexes.clear();
      }
      _selectedTool = nextTool;
    });
  }

  bool _finishCurrentVectorToolOpen() {
    switch (_selectedTool) {
      case _CanvasTool.polyline:
        if (_canFinishCurrentVectorPolylineOpen) {
          _finishVectorPolyline(closed: false);
          return true;
        }
        return false;
      case _CanvasTool.rectangle:
      case _CanvasTool.oval:
        if (_v4ShapePoints.length >= 2) {
          return _finishVectorArea(_selectedTool);
        }
        return false;
      case _CanvasTool.line:
      case _CanvasTool.wave:
        if (_v4ShapePoints.isNotEmpty) {
          setState(_clearVectorDraftState);
          return true;
        }
        return false;
      case _CanvasTool.select:
      case _CanvasTool.dot:
      case _CanvasTool.pencil:
      case _CanvasTool.fill:
      case _CanvasTool.eyedropper:
        return false;
    }
  }

  void _handleVectorTap(Offset position, Size size) {
    final point = _vectorGridPoint(
      position,
      size,
      clampToCanvas: false,
    );
    switch (_selectedTool) {
      case _CanvasTool.dot:
      case _CanvasTool.pencil:
        _addVectorFigure(
          MCOImageV4Dot(point: point, style: _currentVectorStyle()),
        );
      case _CanvasTool.line:
        final points = _acceptVectorShapePoint(point, requiredCount: 2);
        if (points == null) return;
        _addVectorFigure(
          MCOImageV4Line(
            start: points[0],
            end: points[1],
            style: _currentVectorStyle(),
          ),
        );
      case _CanvasTool.polyline:
        if (_v4ShapePoints.length >= 3 && _v4ShapePoints.first == point) {
          _finishVectorPolyline(closed: true);
          return;
        }
        if (_v4ShapePoints.isNotEmpty && _v4ShapePoints.last == point) return;
        setState(() => _addVectorShapePoint(point));
      case _CanvasTool.rectangle:
      case _CanvasTool.oval:
        final points = _acceptVectorShapePoint(point, requiredCount: 3);
        if (points == null) return;
        _addVectorFigure(
          _vectorAreaDraft(points[0], points[1], points[2], _selectedTool),
        );
      case _CanvasTool.wave:
        final points = _acceptVectorShapePoint(point, requiredCount: 3);
        if (points == null) return;
        _addVectorFigure(_vectorWave(points[0], points[1], points[2]));
      case _CanvasTool.select:
        final index = _hitTestVectorFigure(point);
        if (_v4GroupSelectionMode) {
          if (index != null) _toggleV4FigureCheckedForGroup(index);
          return;
        }
        _selectVectorFigure(index);
      case _CanvasTool.fill:
      case _CanvasTool.eyedropper:
        break;
    }
  }

  void _handleVectorPanStart(Offset position, Size size) {
    final point = _vectorGridPoint(
      position,
      size,
      clampToCanvas: false,
    );
    switch (_selectedTool) {
      case _CanvasTool.pencil:
        _v4GestureStart = point;
        _v4PencilPoints = <MCOImageV4Point>[point];
      case _CanvasTool.select:
        if (_v4GroupSelectionMode) return;
        _v4GestureStart = point;
        final index = _hitTestVectorFigure(point);
        final selectedIndex = index ?? _selectedV4FigureIndex;
        final document = _v4Document;
        if (document != null &&
            selectedIndex != null &&
            selectedIndex < document.figures.length) {
          if (index != null) {
            _selectedV4FigureIndex = index;
            _adoptVectorStyle(document.figures[index].style);
          }
          _v4MoveBefore = document;
          _v4LastMovePoint = point;
        }
      default:
        break;
    }
  }

  void _handleVectorPanUpdate(Offset position, Size size) {
    final point = _vectorGridPoint(
      position,
      size,
      clampToCanvas: false,
    );
    if (_v4GestureStart == null) return;
    switch (_selectedTool) {
      case _CanvasTool.pencil:
        final points = _v4PencilPoints;
        if (points != null && points.last != point) {
          points.add(point);
          setState(() {
            _v4DraftFigure = points.length < 2
                ? null
                : MCOImageV4Path(
                    points: points,
                    closed: false,
                    style: _currentVectorStyle(),
                  );
          });
        }
      case _CanvasTool.select:
        _moveSelectedVectorFigure(point);
      default:
        break;
    }
  }

  void _handleVectorPanEnd() {
    if (_selectedTool == _CanvasTool.select) {
      final before = _v4MoveBefore;
      final document = _v4Document;
      if (before != null && document != null && !identical(before, document)) {
        _rememberCanvasAction(
          _captureCanvasSnapshot(vectorDocument: before),
          _captureCanvasSnapshot(vectorDocument: document),
        );
        _markPayloadDirty();
      }
      _v4MoveBefore = null;
      _v4LastMovePoint = null;
      _v4GestureStart = null;
      return;
    }

    MCOImageV4Figure? figure;
    if (_selectedTool == _CanvasTool.pencil) {
      final points = _simplifyVectorPoints(_v4PencilPoints ?? const []);
      if (points.length == 1) {
        figure = MCOImageV4Dot(
          point: points.first,
          style: _currentVectorStyle(),
        );
      } else if (points.length >= 2) {
        figure = MCOImageV4Path(
          points: points,
          closed: false,
          style: _currentVectorStyle(),
        );
      }
    }
    _v4GestureStart = null;
    _v4PencilPoints = null;
    _v4DraftFigure = null;
    if (figure != null) _addVectorFigure(figure);
  }

  List<MCOImageV4Point>? _acceptVectorShapePoint(
    MCOImageV4Point point, {
    required int requiredCount,
  }) {
    if (_v4ShapePoints.contains(point)) {
      setState(_clearVectorDraftState);
      return null;
    }
    _addVectorShapePoint(point);
    if (_v4ShapePoints.length < requiredCount) {
      setState(() {});
      return null;
    }
    final result = List<MCOImageV4Point>.of(_v4ShapePoints);
    _v4ShapePoints.clear();
    return result;
  }

  void _addVectorShapePoint(MCOImageV4Point point) {
    _v4ShapePoints.add(point);
    if (_selectedTool == _CanvasTool.rectangle ||
        _selectedTool == _CanvasTool.oval) {
      if (_v4ShapePoints.length >= 3) {
        _v4DraftFigure = _vectorAreaDraft(
          _v4ShapePoints[0],
          _v4ShapePoints[1],
          _v4ShapePoints[2],
          _selectedTool,
        );
      }
    } else if (_selectedTool == _CanvasTool.wave &&
        _v4ShapePoints.length == 3) {
      _v4DraftFigure = _vectorWave(
        _v4ShapePoints[0],
        _v4ShapePoints[1],
        _v4ShapePoints[2],
      );
    }
  }

  void _finishVectorPolyline({required bool closed}) {
    final minimum = closed ? 3 : 2;
    if (_v4ShapePoints.length < minimum) return;
    final points = List<MCOImageV4Point>.of(_v4ShapePoints);
    _v4ShapePoints.clear();
    _addVectorFigure(
      MCOImageV4Path(
        points: points,
        closed: closed,
        style: _currentVectorStyle(),
      ),
    );
  }

  bool _finishVectorArea(_CanvasTool tool) {
    if (_v4ShapePoints.length < 2) return false;
    final first = _v4ShapePoints[0];
    final second = _v4ShapePoints[1];
    if (first.x == second.x || first.y == second.y) return false;
    final third = _v4ShapePoints.length >= 3
        ? _v4ShapePoints[2]
        : _axisAlignedVectorAreaThirdPoint(first, second);
    _v4ShapePoints.clear();
    _v4DraftFigure = null;
    _addVectorFigure(_vectorAreaDraft(first, second, third, tool));
    return true;
  }

  MCOImageV4Point _axisAlignedVectorAreaThirdPoint(
    MCOImageV4Point first,
    MCOImageV4Point second,
  ) {
    return MCOImageV4Point(first.x, second.y);
  }

  MCOImageV4Figure _vectorAreaDraft(
    MCOImageV4Point first,
    MCOImageV4Point second,
    MCOImageV4Point third,
    _CanvasTool tool,
  ) {
    final style = _currentVectorStyle();
    return switch (tool) {
      _CanvasTool.rectangle => MCOImageV4Rect(
          first: first,
          second: second,
          third: third,
          style: style,
        ),
      _CanvasTool.oval => MCOImageV4Ellipse(
          first: first,
          second: second,
          third: third,
          style: style,
        ),
      _ => throw StateError('Not a v4 area tool'),
    };
  }

  MCOImageV4Wave _vectorWave(
    MCOImageV4Point start,
    MCOImageV4Point end,
    MCOImageV4Point handle,
  ) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final length = math.sqrt(dx * dx + dy * dy);
    var depth = 1;
    if (length > 0) {
      final midpointX = (start.x + end.x) / 2;
      final midpointY = (start.y + end.y) / 2;
      depth = (((handle.x - midpointX) * -dy +
                  (handle.y - midpointY) * dx) /
              length)
          .round();
      if (depth == 0) depth = 1;
    }
    final maxDepth = math.max(_width, _height);
    return MCOImageV4Wave(
      start: start,
      end: end,
      depth: depth.clamp(-maxDepth, maxDepth).toInt(),
      closed: false,
      style: _currentVectorStyle(),
    );
  }

  void _addVectorFigure(MCOImageV4Figure figure) {
    final document = _v4Document;
    if (document == null) return;
    final editingIndex = _editingV4FigureIndex;
    final editingBefore = _editingV4FigureBefore;
    if (editingIndex != null && editingBefore != null) {
      final figures = [...document.figures];
      final insertIndex = math.min(editingIndex, figures.length);
      figures.insert(insertIndex, figure.withVisibility(_editingV4FigureVisible));
      _commitVectorDocument(document.copyWith(figures: figures));
      setState(() {
        _selectedV4FigureIndex = insertIndex;
        _adoptVectorStyle(figure.style);
        _clearVectorEditingState();
      });
      return;
    }
    final appendIndex = _v4AppendGroupIndex;
    if (appendIndex != null &&
        appendIndex >= 0 &&
        appendIndex < document.figures.length &&
        document.figures[appendIndex] is MCOImageV4Group) {
      final figures = [...document.figures];
      final group = figures[appendIndex] as MCOImageV4Group;
      figures[appendIndex] = MCOImageV4Group(
        figures: [...group.figures, figure],
        style: group.style,
        visible: group.visible,
      );
      _commitVectorDocument(document.copyWith(figures: figures));
      setState(() {
        _selectedV4FigureIndex =
            _selectedTool == _CanvasTool.select ? appendIndex : null;
        _adoptVectorStyle(figure.style);
      });
      return;
    }
    _commitVectorDocument(document.copyWith(figures: [...document.figures, figure]));
    setState(() {
      _selectedV4FigureIndex = document.figures.length;
      _adoptVectorStyle(figure.style);
    });
  }

  void _commitVectorDocument(MCOImageV4Document next) {
    final before = _v4Document;
    if (before == null || identical(before, next)) return;
    _rememberCanvasAction(
      _captureCanvasSnapshot(vectorDocument: before),
      _captureCanvasSnapshot(
        width: next.width,
        height: next.height,
        pixels: List<int>.filled(next.width * next.height, _whiteIndex),
        vectorDocument: next,
      ),
    );
    setState(() {
      _v4Document = next;
      _width = next.width;
      _height = next.height;
      _setControllerValue(_widthController, _width);
      _setControllerValue(_heightController, _height);
      _pixels = List<int>.filled(_width * _height, _whiteIndex);
      _clearVectorDraftState();
      _normalizeV4GroupState(next);
    });
    _markPayloadDirty();
  }

  void _moveSelectedVectorFigure(MCOImageV4Point point) {
    final document = _v4Document;
    final index = _selectedV4FigureIndex;
    final previous = _v4LastMovePoint;
    if (document == null ||
        index == null ||
        previous == null ||
        previous == point ||
        index >= document.figures.length) {
      return;
    }
    final figures = [...document.figures];
    figures[index] = figures[index].translated(
      point.x - previous.x,
      point.y - previous.y,
    );
    setState(() {
      _v4Document = document.copyWith(figures: figures);
      _v4LastMovePoint = point;
    });
  }

  void _cloneSelectedV4Figure() {
    final document = _v4Document;
    final index = _selectedV4FigureIndex;
    final selected = _selectedV4Figure;
    if (document == null ||
        index == null ||
        index < 0 ||
        index >= document.figures.length ||
        selected == null) {
      return;
    }
    final clone = selected.translated(1, 1);
    final figures = [...document.figures]..insert(index + 1, clone);
    _commitVectorDocument(document.copyWith(figures: figures));
    setState(() {
      _selectedV4FigureIndex = index + 1;
      _selectedTool = _CanvasTool.select;
      _adoptVectorStyle(clone.style);
    });
  }

  void _ungroupSelectedV4Figure() {
    final document = _v4Document;
    final index = _selectedV4FigureIndex;
    final selected = _selectedV4Figure;
    if (document == null || index == null || selected is! MCOImageV4Group) {
      return;
    }
    final childFigures = selected.visible
        ? selected.figures
        : selected.figures
            .map((figure) => figure.withVisibility(false))
            .toList(growable: false);
    final figures = [...document.figures]
      ..removeAt(index)
      ..insertAll(index, childFigures);
    _commitVectorDocument(document.copyWith(figures: figures));
    setState(() {
      _selectedV4FigureIndex = math.min(
        index + childFigures.length - 1,
        figures.length - 1,
      );
      _selectedTool = _CanvasTool.select;
    });
  }

  void _editSelectedV4Figure() {
    final document = _v4Document;
    final index = _selectedV4FigureIndex;
    if (document == null || index == null || index >= document.figures.length) {
      return;
    }
    final figure = document.figures[index];
    final figures = [...document.figures]..removeAt(index);
    setState(() {
      _editingV4FigureIndex = index;
      _editingV4FigureBefore = document;
      _editingV4FigureVisible = figure.visible;
      _v4Document = document.copyWith(figures: figures);
      _selectedV4FigureIndex = null;
      _selectedTool = _toolForVectorFigure(figure);
      _adoptVectorStyle(figure.style);
      _v4ShapePoints
        ..clear()
        ..addAll(_controlPointsForVectorFigure(figure));
      _v4DraftFigure = figure is MCOImageV4Rect || figure is MCOImageV4Ellipse
          ? figure.withVisibility(true)
          : null;
    });
    _markPayloadDirty();
  }

  _CanvasTool _toolForVectorFigure(MCOImageV4Figure figure) => switch (figure) {
        MCOImageV4Dot() => _CanvasTool.dot,
        MCOImageV4Line() => _CanvasTool.line,
        MCOImageV4Rect() => _CanvasTool.rectangle,
        MCOImageV4Ellipse() => _CanvasTool.oval,
        MCOImageV4Path() => _CanvasTool.polyline,
        MCOImageV4Wave() => _CanvasTool.wave,
        MCOImageV4Group() => _CanvasTool.select,
      };

  List<MCOImageV4Point> _controlPointsForVectorFigure(
    MCOImageV4Figure figure,
  ) =>
      switch (figure) {
        MCOImageV4Dot() => const <MCOImageV4Point>[],
        MCOImageV4Line(:final start) => <MCOImageV4Point>[start],
        MCOImageV4Rect(:final first, :final second, :final third) =>
          <MCOImageV4Point>[
            first,
            second,
            third,
          ],
        MCOImageV4Ellipse(:final first, :final second, :final third) =>
          <MCOImageV4Point>[
            first,
            second,
            third,
          ],
        MCOImageV4Path(:final points) => List<MCOImageV4Point>.of(points),
        MCOImageV4Wave(:final start, :final end) => <MCOImageV4Point>[
            start,
            end,
          ],
        MCOImageV4Group() => const <MCOImageV4Point>[],
      };

  MCOImageV4Point _vectorGridPoint(
    Offset position,
    Size size, {
    bool clampToCanvas = true,
  }) {
    final rawX = (position.dx / size.width * _width).floor();
    final rawY = (position.dy / size.height * _height).floor();
    final xMargin = MCOImageV4Codec.coordinateMarginForCanvasSize(_width);
    final yMargin = MCOImageV4Codec.coordinateMarginForCanvasSize(_height);
    final x = clampToCanvas
        ? rawX.clamp(0, _width - 1).toInt()
        : rawX.clamp(-xMargin, _width + xMargin - 1).toInt();
    final y = clampToCanvas
        ? rawY.clamp(0, _height - 1).toInt()
        : rawY.clamp(-yMargin, _height + yMargin - 1).toInt();
    return MCOImageV4Point(x, y);
  }

  int? _hitTestVectorFigure(MCOImageV4Point point) {
    final document = _v4Document;
    if (document == null) return null;
    for (var i = document.figures.length - 1; i >= 0; i--) {
      final figure = document.figures[i];
      if (!figure.visible) continue;
      if (MCOImageV4Painter.figureLogicalBounds(figure)
          .inflate(2)
          .contains(Offset(point.x + 0.5, point.y + 0.5))) {
        return i;
      }
    }
    return null;
  }

  MCOImageV4Style _currentVectorStyle() {
    return MCOImageV4Style(
      fillColor: _v4FillColor,
      strokeColor: _v4StrokeColor,
      strokeWidth: _v4StrokeWidth,
    );
  }

  int _vectorLocalColorIndex(int colorValue, {required bool mutate}) {
    final document = _v4Document;
    if (document == null) return 0;
    final existing = document.palette.indexOf(colorValue);
    if (existing >= 0) return existing;
    if (!mutate || document.palette.length >= 64) {
      final black = document.paletteProfile.isDynamic
          ? MCOImageDynamicPalette.blackGlobalIndexFor(document.paletteProfile)
          : MCOImagePalette.blackIndexFor(document.paletteProfile);
      return math.max(0, document.palette.indexOf(black));
    }
    _v4Document = document.copyWith(palette: [...document.palette, colorValue]);
    return document.palette.length;
  }

  List<MCOImageV4Point> _simplifyVectorPoints(List<MCOImageV4Point> input) {
    final unique = <MCOImageV4Point>[];
    for (final point in input) {
      if (unique.isEmpty || unique.last != point) unique.add(point);
    }
    final gridSize = math.max(_width, _height);
    final epsilon = switch (gridSize) {
      < 32 => 0.0,
      < 64 => 0.25,
      < 128 => 0.5,
      < 256 => 1.0,
      _ => 2.0,
    };
    if (epsilon <= 0 || unique.length <= 2) return unique;
    return _rdpVectorPoints(unique, epsilon);
  }

  List<MCOImageV4Point> _rdpVectorPoints(
    List<MCOImageV4Point> points,
    double epsilon,
  ) {
    if (points.length <= 2) return points;
    var maxDistance = 0.0;
    var index = 0;
    for (var i = 1; i < points.length - 1; i++) {
      final distance = _perpendicularVectorDistance(
        points[i],
        points.first,
        points.last,
      );
      if (distance > maxDistance) {
        index = i;
        maxDistance = distance;
      }
    }
    if (maxDistance <= epsilon) return [points.first, points.last];
    final left = _rdpVectorPoints(points.sublist(0, index + 1), epsilon);
    final right = _rdpVectorPoints(points.sublist(index), epsilon);
    return [...left.take(left.length - 1), ...right];
  }

  double _perpendicularVectorDistance(
    MCOImageV4Point point,
    MCOImageV4Point start,
    MCOImageV4Point end,
  ) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    if (dx == 0 && dy == 0) {
      final px = point.x - start.x;
      final py = point.y - start.y;
      return math.sqrt(px * px + py * py);
    }
    return ((dy * point.x -
                dx * point.y +
                end.x * start.y -
                end.y * start.x)
            .abs()) /
        math.sqrt(dx * dx + dy * dy);
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
      case _CanvasTool.select:
      case _CanvasTool.dot:
      case _CanvasTool.polyline:
      case _CanvasTool.wave:
        break;
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
    if (_isVectorV4) {
      final document = _v4Document;
      if (document == null) return;
      _commitVectorDocument(document.copyWith(figures: const []));
      setState(() => _selectedV4FigureIndex = null);
      return;
    }
    _cancelPayloadCalculationBeforeCanvasReplacement();
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
    var shouldRestorePendingRefreshOnError = false;
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
          file_selector.XTypeGroup(
            label: 'MCO image binary',
            extensions: ['bin'],
            mimeTypes: ['application/octet-stream'],
            uniformTypeIdentifiers: ['public.data'],
          ),
        ],
      );
      if (file == null) return;

      shouldRestorePendingRefreshOnError =
          _cancelPayloadCalculationBeforeCanvasReplacement();
      final bytes = await file.readAsBytes();
      if (file.name.toLowerCase().endsWith('.bin')) {
        final appPayload =
            ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(bytes);
        if (appPayload?.subtypeVersion ==
            ChannelAppDataHelper.mcoImageV4SubtypeVersion) {
          final decoded = const MCOImageV4Codec().decodeBody(appPayload!.body);
          await _cancelCurrentEncoding();
          if (!mounted) return;
          shouldRestorePendingRefreshOnError = false;
          _clearCanvasHistory();
          _enterVectorV4Mode(
            document: decoded.document,
            recordHistory: false,
          );
          return;
        }
        final imported = _decodeMcoImageBinaryForImport(bytes);

        // The imported payload is already the winning encoded candidate. Wait
        // until any encoder for the previous canvas has fully stopped, then
        // adopt the payload directly instead of scheduling another candidate
        // search. For v3 the helper below changes only the one-byte packet
        // nonce; the compressed image bitstream remains byte-for-byte intact.
        await _cancelCurrentEncoding();
        if (!mounted) return;

        _clearCanvasHistory();
        shouldRestorePendingRefreshOnError = false;
        setState(() {
          _loadInitialImage(imported.image);
          _lineStartIndex = null;
          _ovalFirstIndex = null;
          _ovalSecondIndex = null;
          _rectangleFirstIndex = null;
          _rectangleSecondIndex = null;
          _payloadRefreshPending = false;
          _payloadRefreshInProgress = false;
          _payloadRefreshProgressPercent = null;
          _payloadRefreshElapsed = null;
          _payloadRefreshStopwatch = null;
          _currentEncodedCandidate = imported.encoded;
          _currentEncodedCacheKey = _MCOImageEncodeCacheKey.fromRequest(
            _buildEncodeRequest(),
          );
          _currentPayloadChars = _displayPayloadSizeForEncoded(
            imported.encoded,
          );
        });
        unawaited(_saveCanvasPalette(imported.image.paletteProfile));
        unawaited(_saveCanvasSize(imported.image.width, imported.image.height));
        return;
      }

      final importedImage = await _imageBytesToCanvasPixels(bytes);
      if (!mounted) return;
      _setControllerValue(_widthController, importedImage.width);
      _setControllerValue(_heightController, importedImage.height);
      setState(() {
        if (_isVectorV4) {
          _encodingVersion = MCOImageEncodingVersion.v3;
          _v4Document = null;
          _v4ReferencePixels = null;
          _v4ReferencePaletteProfile = null;
          _v4ReferenceTransparentColor = null;
          _v4ReferenceVisible = true;
          _currentEncodedV4 = null;
          _v4EncodeError = null;
          _selectedTool = _CanvasTool.pencil;
        }
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
      unawaited(_saveEncodingVersion(_encodingVersion));
      unawaited(_saveCanvasSize(importedImage.width, importedImage.height));
    } catch (error) {
      if (shouldRestorePendingRefreshOnError && mounted) {
        _schedulePayloadRefresh();
      }
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(error.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  _ImportedMcoBinary _decodeMcoImageBinaryForImport(Uint8List payload) {
    final appPayload = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
      payload,
    );
    if (appPayload != null &&
        appPayload.subtypeId == MCOImageV3Codec.subtypeId &&
        appPayload.version == MCOImageV3Codec.version) {
      try {
        // A v3 .bin already contains the selected compressed representation.
        // Refresh only the transport-uniqueness byte used to avoid identical
        // retransmission payloads; do not invoke the image encoder.
        final body = MCOImageV3Codec.refreshPacketNonce(appPayload.body);
        final image = MCOImageV3Codec().decodeBody(body);
        final info = MCOImageV3Codec.inspectBody(body);
        final text = MCOImageV3Codec.textFromBody(body);
        final scanId = (body[1] >> 4) & 0x03;
        final scan = ScanMode.values[scanId];
        return _ImportedMcoBinary(
          image: image,
          encoded: EncodedMCOImage(
            payload: body,
            text: text,
            mode: ImageMode.extended,
            scan: scan,
            byteLength: body.length,
            charLength: text.length,
            transparentColor: image.transparentColor,
            codecVersion: MCOImageV3Codec.version,
            requestedEncodingVersion: MCOImageEncodingVersion.v3,
            actualEncodingVersion: MCOImageEncodingVersion.v3,
            paletteKind: image.paletteProfile.isDynamic ? 'dynamic' : 'fixed',
            container: 'imported-bin:${info.algorithm}',
          ),
        );
      } on MCOImageCodecException {
        // A legacy v1/v2 payload may coincidentally start with 0x13. Preserve
        // the old fallback behaviour and try the legacy decoder below.
      }
    }

    final binaryPayload = Uint8List.fromList(payload);
    final text = MCOImageCodec.textFromBinaryPayload(binaryPayload);
    final image = _codec.decode(text);
    final info = MCOImageCodec.inspectPayload(text);
    if (info == null) {
      throw const MCOImageInvalidPayloadException(
        'Invalid MCOimg binary payload',
      );
    }
    return _ImportedMcoBinary(
      image: image,
      encoded: EncodedMCOImage(
        payload: binaryPayload,
        text: text,
        mode: ImageMode.extended,
        scan: ScanMode.h,
        byteLength: binaryPayload.length,
        charLength: text.length,
        transparentColor: image.transparentColor,
        codecVersion: info.version,
        requestedEncodingVersion: image.encodingVersion,
        actualEncodingVersion: image.encodingVersion,
        paletteKind: image.paletteProfile.isDynamic ? 'dynamic' : 'fixed',
        container: 'imported-bin:${info.algorithm}',
      ),
    );
  }

  Future<_ImportedCanvasImage> _imageBytesToCanvasPixels(
    Uint8List bytes,
  ) async {
    final source = await _decodeImage(bytes);
    final sourceWidth = source.width;
    final sourceHeight = source.height;
    source.dispose();

    final adoptImageSize =
        _encodingVersion == MCOImageEncodingVersion.v2 ||
        _encodingVersion == MCOImageEncodingVersion.v3 ||
        _unlockCanvasSize;
    final canvasWidth = adoptImageSize
        ? math.max(_minCanvasSize, math.min(_maxCanvasSize, sourceWidth))
        : _width;
    final canvasHeight = adoptImageSize
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

  /// Animated sources (GIF, animated WebP) decode to their first frame: the
  /// canvas edits a single still, and the first frame is what the user saw in
  /// the file picker.
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
      final fileName = MCOImageFileSaver.pngFileName();
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
      if (_isVectorV4) {
        final payload = ChannelAppDataHelper.appPayloadWithoutSender(
          subtypeId: ChannelAppDataHelper.mcoImageSubtype,
          version: ChannelAppDataHelper.mcoImageV4Version,
          body: _encodedVectorForCurrentState().body,
        );
        await MCOImageFileSaver.saveBinaryPayload(payload);
        return;
      }
      final encoded = await _encodedCanvasForCurrentState();
      final rasterPayload =
          encoded.actualEncodingVersion == MCOImageEncodingVersion.v3
          ? ChannelAppDataHelper.appPayloadWithoutSender(
              subtypeId: ChannelAppDataHelper.mcoImageSubtype,
              version: ChannelAppDataHelper.mcoImageV3Version,
              body: encoded.payload,
            )
          : encoded.payload;
      await MCOImageFileSaver.saveBinaryPayload(rasterPayload);
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
      final fileName = MCOImageFileSaver.pngFileName();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/png', name: fileName)],
          fileNameOverrides: [fileName],
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List> _renderCanvasPngBytes() async {
    if (_isVectorV4) {
      final document = _activeVectorDocument;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      MCOImageV4Painter(document, antiAlias: true).paint(
        canvas,
        Size(document.width.toDouble(), document.height.toDouble()),
      );
      final rendered = await recorder.endRecording().toImage(
        document.width,
        document.height,
      );
      final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      if (png == null) {
        throw const MCOImageInvalidInputException('Cannot render PNG');
      }
      return png.buffer.asUint8List();
    }
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

  Future<void> _sendCanvas() async {
    try {
      if (_isVectorV4) {
        final encoded = _encodedVectorForCurrentState(refreshNonce: true);
        if (!mounted) return;
        final payloadSize = _payloadSizeForEncodedV4(encoded);
        _currentEncodedV4 = encoded;
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
        final text = _v4Codec.textFromBody(encoded.body);
        Navigator.pop(
          context,
          CanvasEditorResult.fromV4(text: text, encoded: encoded),
        );
        return;
      }
      final encoded = await _encodedCanvasForCurrentState();
      if (!mounted) return;
      _currentEncodedCandidate = encoded;
      _currentEncodedCacheKey = _MCOImageEncodeCacheKey.fromRequest(
        _buildEncodeRequest(),
      );
      final payloadSize = _payloadSizeForEncoded(encoded);
      _currentPayloadChars = _displayPayloadSizeForEncoded(encoded);
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
      Navigator.pop(context, CanvasEditorResult.fromEncoded(encoded));
    } on CancellableComputeCancelledException {
      // The route was closed while encoding. Its isolate has already been
      // terminated, so no UI feedback is needed.
      return;
    } on MCOImageCodecException catch (error) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(error.message),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  EncodedMCOImageV4 _encodedVectorForCurrentState({
    bool refreshNonce = false,
  }) {
    final document = _v4Document;
    if (document == null) {
      throw const MCOImageInvalidInputException(
        'MCOimg v4 vector document is not initialized',
      );
    }
    if (!refreshNonce) {
      final cached = _currentEncodedV4;
      if (cached != null && identical(cached.document, document)) {
        return cached;
      }
    }
    return _v4Codec.encode(
      document,
      nonce: refreshNonce ? null : 0,
      targetName: widget.replyTargetName,
      replyTimestamp: widget.replyTimestamp,
    );
  }

  Future<EncodedMCOImage> _encodedCanvasForCurrentState() async {
    var request = _buildEncodeRequest();
    final cached = _cachedEncodedForRequest(request);
    if (cached != null) return cached;

    final refreshCompletion = _payloadRefreshCompletion?.future;
    if (_payloadRefreshInProgress && refreshCompletion != null) {
      await refreshCompletion;
      request = _buildEncodeRequest();
      final refreshed = _cachedEncodedForRequest(request);
      if (refreshed != null) return refreshed;
    }

    final encoded = await _encodeCanvasInBackground(request: request);
    _currentEncodedCandidate = encoded;
    _currentEncodedCacheKey = _MCOImageEncodeCacheKey.fromRequest(request);
    return encoded;
  }

  EncodedMCOImage? _cachedEncodedForRequest(_MCOImageEncodeRequest request) {
    final cached = _currentEncodedCandidate;
    final cacheKey = _currentEncodedCacheKey;
    if (cached == null || cacheKey == null || !cacheKey.matches(request)) {
      return null;
    }
    return cached;
  }

  Future<EncodedMCOImage> _encodeCanvasInBackground({
    _MCOImageEncodeRequest? request,
    void Function(int progressPercent)? onProgress,
  }) {
    if (_isDisposed) {
      return Future<EncodedMCOImage>.error(
        const CancellableComputeCancelledException(),
      );
    }

    final effectiveRequest = request ?? _buildEncodeRequest();
    if (_shouldUseParallelEncode(effectiveRequest)) {
      return _encodeCanvasInParallel(effectiveRequest, onProgress: onProgress);
    }

    final task = _startEncodeTask(
      _encodeMCOImageRequest,
      effectiveRequest,
      debugLabel: 'MCOimg encode',
    );
    return _awaitEncodeTask(task);
  }

  bool _shouldUseParallelEncode(_MCOImageEncodeRequest request) {
    return (request.encodingVersion == MCOImageEncodingVersion.v2 ||
            request.encodingVersion == MCOImageEncodingVersion.v3) &&
        request.compressionLevel == MCOImageCodec.compressionLevelExtreme;
  }

  String _compressionLevelDebugLabel(int compressionLevel) {
    return switch (compressionLevel) {
      MCOImageCodec.compressionLevelNormal => 'Normal',
      MCOImageCodec.compressionLevelExtreme => 'Extreme',
      _ => 'High',
    };
  }

  Future<EncodedMCOImage> _encodeCanvasInParallel(
    _MCOImageEncodeRequest request, {
    void Function(int progressPercent)? onProgress,
  }) async {
    final image = _imageFromEncodeRequest(request);
    final backgroundCandidates =
        request.encodingVersion == MCOImageEncodingVersion.v3
        ? MCOImageV3Codec.backgroundCandidatesFor(
            image,
            backgroundColor: request.backgroundColor,
            compressionLevel: request.compressionLevel,
          )
        : MCOImageCodec.backgroundCandidatesFor(
            image,
            backgroundColor: request.backgroundColor,
            compressionLevel: request.compressionLevel,
          );
    final slices = <_ExtremeEncodeSlice>[];

    // Start the heavier non-scan slices (regions/solid rectangles/quadtree)
    // first. If all region slices sit at the end of the queue, the worker pool
    // can finish the light scan work first and then spend the tail of the
    // encode with only a few busy isolates.
    for (final backgroundCandidate in backgroundCandidates) {
      slices.add(
        _ExtremeEncodeSlice(
          request: _encodeRequestWithBackgroundCandidates(
            request,
            [backgroundCandidate],
            const <ScanMode>[],
            true,
          ),
          label:
              'non-scan/regions, bg=${backgroundCandidate.color}, '
              'rank=${backgroundCandidate.rank}',
        ),
      );
    }
    for (final backgroundCandidate in backgroundCandidates) {
      final backgroundSlice = [backgroundCandidate];
      for (final scan in ScanMode.values) {
        slices.add(
          _ExtremeEncodeSlice(
            request: _encodeRequestWithBackgroundCandidates(
              request,
              backgroundSlice,
              [scan],
              false,
            ),
            label:
                'scan=${scan.name}, bg=${backgroundCandidate.color}, '
                'rank=${backgroundCandidate.rank}',
          ),
        );
      }
    }

    final workerCount = math.min(_extremeEncodeWorkerLimit(), slices.length);
    final selectionTarget =
        request.encodingVersion == MCOImageEncodingVersion.v3
        ? MCOImageOutputTarget.binary
        : request.outputTarget;
    final candidates = <EncodedMCOImage>[];
    final runningTasks = <CancellableComputeTask<MCOImageEncodeDiagnostics>>{};
    var nextSliceIndex = 0;
    var completedSlices = 0;
    final compressionLabel = _compressionLevelDebugLabel(
      request.compressionLevel,
    );

    Future<void> cancelAndAwaitRunningTasks() async {
      final tasks = runningTasks.toList(growable: false);
      for (final task in tasks) {
        task.cancel();
      }
      await Future.wait<void>(
        tasks.map((task) async {
          try {
            await task.result;
          } catch (_) {
            // The worker owning this task will remove it from the active sets.
          }
        }),
      );
    }

    debugPrint(
      '[MCOimg][$compressionLabel] START; '
      'size=${request.width}x${request.height}; '
      'palette=${request.paletteProfile.name}; '
      'slices=${slices.length}; '
      'workers=$workerCount;',
    );
    onProgress?.call(0);

    Future<void> runWorker(int workerIndex) async {
      while (true) {
        if (nextSliceIndex >= slices.length) return;
        final sliceIndex = nextSliceIndex;
        nextSliceIndex++;
        final slice = slices[sliceIndex];
        final stopwatch = Stopwatch()..start();
        final completedBefore = completedSlices;
        final startPercentage = slices.isEmpty
            ? 100.0
            : completedBefore * 100 / slices.length;

        debugPrint(
          '[MCOimg][$compressionLabel][W${workerIndex + 1}] '
          'START ${sliceIndex + 1}/${slices.length} '
          '(${startPercentage.toStringAsFixed(1)}% complete); '
          '${slice.label};',
        );

        final task = _startComputeTask(
          _debugEncodeMCOImageRequest,
          slice.request,
          debugLabel:
              'MCOimg $compressionLabel ${sliceIndex + 1}/${slices.length}',
        );
        runningTasks.add(task);
        try {
          final diagnostics = await _awaitComputeTask(task);
          final result = diagnostics.result;
          candidates.addAll(diagnostics.candidates);
          completedSlices++;
          stopwatch.stop();
          final percentage = completedSlices * 100 / slices.length;
          onProgress?.call(percentage.round().clamp(0, 100).toInt());
          final currentBest = MCOImageCodec.selectBestCandidate(
            candidates,
            selectionTarget,
          );
          final isBest = identical(currentBest, result);
          debugPrint(
            '[MCOimg][$compressionLabel][W${workerIndex + 1}] '
            '$completedSlices/${slices.length} '
            '(${percentage.toStringAsFixed(1)}%); '
            'bytes=${result.byteLength}; '
            'chars=${result.charLength}; '
            '${stopwatch.elapsedMilliseconds} ms; '
            'candidates=${diagnostics.candidates.length}; '
            '${isBest ? 'BEST' : 'not-best'}; '
            '${slice.label}; '
            'algorithm=${_encodingAlgorithmLabel(result)}; '
            'container=${result.container}; '
            'mode=${result.mode.name}; '
            'scan=${result.scan.name}; '
            'bg=${result.backgroundColor ?? -1}; '
            'bgRank=${result.backgroundRank}; '
            'bounds=${result.boundsPresent};',
          );
        } on CancellableComputeCancelledException {
          stopwatch.stop();
          debugPrint(
            '[MCOimg][$compressionLabel][W${workerIndex + 1}] '
            'CANCELLED ${sliceIndex + 1}/${slices.length}; '
            '${stopwatch.elapsedMilliseconds} ms; '
            '${slice.label};',
          );
          rethrow;
        } on MCOImageInvalidInputException catch (error) {
          if (request.encodingVersion != MCOImageEncodingVersion.v3 ||
              error.message != 'No MCOimg v3 candidate') {
            rethrow;
          }
          completedSlices++;
          stopwatch.stop();
          final percentage = completedSlices * 100 / slices.length;
          onProgress?.call(percentage.round().clamp(0, 100).toInt());
          debugPrint(
            '[MCOimg][$compressionLabel][W${workerIndex + 1}] '
            '$completedSlices/${slices.length} '
            '(${percentage.toStringAsFixed(1)}%); '
            'SKIP; '
            '${stopwatch.elapsedMilliseconds} ms; '
            '${slice.label}; '
            'error=$error;',
          );
        } on MCOImageTooLargeException catch (error) {
          // A fine-grained slice may have no viable candidate. Count it as
          // processed and continue with the remaining slices.
          completedSlices++;
          stopwatch.stop();
          final percentage = completedSlices * 100 / slices.length;
          onProgress?.call(percentage.round().clamp(0, 100).toInt());
          debugPrint(
            '[MCOimg][$compressionLabel][W${workerIndex + 1}] '
            '$completedSlices/${slices.length} '
            '(${percentage.toStringAsFixed(1)}%); '
            'SKIP; '
            '${stopwatch.elapsedMilliseconds} ms; '
            '${slice.label}; '
            'error=$error;',
          );
        } finally {
          runningTasks.remove(task);
        }
      }
    }

    try {
      await Future.wait<void>(
        List.generate(workerCount, runWorker),
        eagerError: true,
      );
      final best = MCOImageCodec.selectBestCandidate(
        candidates,
        selectionTarget,
      );
      debugPrint(
        '[MCOimg][$compressionLabel] '
        '${slices.length}/${slices.length} (100.0%); '
        'bytes=${best.byteLength}; '
        'chars=${best.charLength}; '
        'COMPLETE; '
        'algorithm=${_encodingAlgorithmLabel(best)}; '
        'container=${best.container}; '
        'mode=${best.mode.name}; '
        'scan=${best.scan.name}; '
        'bg=${best.backgroundColor ?? -1}; '
        'bgRank=${best.backgroundRank}; '
        'bounds=${best.boundsPresent};',
      );
      onProgress?.call(100);
      return best;
    } on CancellableComputeCancelledException {
      // If one worker fails or the route/settings change, stop all remaining
      // workers instead of letting them continue consuming CPU.
      await cancelAndAwaitRunningTasks();
      rethrow;
    } on MCOImageCodecException catch (error) {
      await cancelAndAwaitRunningTasks();
      debugPrint(
        '[MCOimg][$compressionLabel] parallel fallback to single encode; '
        'error=$error;',
      );
      final task = _startEncodeTask(
        _encodeMCOImageRequest,
        request,
        debugLabel: 'MCOimg $compressionLabel fallback',
      );
      return _awaitEncodeTask(task);
    } catch (_) {
      await cancelAndAwaitRunningTasks();
      rethrow;
    }
  }

  CancellableComputeTask<R> _startComputeTask<M, R>(
    FutureOr<R> Function(M message) callback,
    M message, {
    required String debugLabel,
  }) {
    final task = startCancellableCompute<M, R>(
      callback,
      message,
      debugLabel: debugLabel,
    );

    if (_isDisposed) {
      task.cancel();
    } else {
      _activeEncodeTasks.add(task);
    }
    return task;
  }

  CancellableComputeTask<EncodedMCOImage> _startEncodeTask<M>(
    FutureOr<EncodedMCOImage> Function(M message) callback,
    M message, {
    required String debugLabel,
  }) {
    return _startComputeTask<M, EncodedMCOImage>(
      callback,
      message,
      debugLabel: debugLabel,
    );
  }

  Future<R> _awaitComputeTask<R>(CancellableComputeTask<R> task) async {
    try {
      return await task.result;
    } finally {
      _activeEncodeTasks.remove(task);
    }
  }

  Future<EncodedMCOImage> _awaitEncodeTask(
    CancellableComputeTask<EncodedMCOImage> task,
  ) {
    return _awaitComputeTask(task);
  }

  List<CancellableComputeTask<dynamic>> _cancelActiveEncodeTasksNow() {
    final tasks = _activeEncodeTasks.toList(growable: false);
    _activeEncodeTasks.clear();
    for (final task in tasks) {
      task.cancel();
    }
    return tasks;
  }

  /// Stops every currently running encoder worker and waits until the active
  /// payload refresh method has observed the cancellation.
  ///
  /// Returns true when no calculation from the previous request remains.
  /// Interactive canvas/settings changes normally call this without awaiting
  /// it and let the existing debounce decide when the next encode may start.
  Future<bool> _cancelCurrentEncoding({
    bool preservePendingRefresh = false,
  }) async {
    _payloadRefreshRequestId++;
    if (!preservePendingRefresh) {
      _payloadRefreshPending = false;
    }
    _payloadRefreshTimer?.cancel();
    _payloadRefreshTimer = null;
    _stopPayloadRefreshElapsedTimer();

    final refreshCompletion = _payloadRefreshCompletion?.future;
    final tasks = _cancelActiveEncodeTasksNow();

    // Await the worker futures so cancellation has propagated through
    // _encodeCanvasInBackground() and _refreshPayloadIfIdle().
    await Future.wait<void>(
      tasks.map((task) async {
        try {
          await task.result;
        } catch (_) {
          // A cancelled worker completes with
          // CancellableComputeCancelledException. A worker that had already
          // completed or failed is also no longer consuming CPU.
        }
      }),
    );

    if (refreshCompletion != null) {
      await refreshCompletion;
    }

    if (!mounted) return true;

    return _activeEncodeTasks.isEmpty && !_payloadRefreshInProgress;
  }

  int _extremeEncodeWorkerLimit() {
    final processors = math.max(1, PlatformInfo.numberOfProcessors);
    if (PlatformInfo.isMobile) {
      return math.min(_mobileExtremeEncodeWorkerLimit, processors);
    }
    if (PlatformInfo.isDesktop) {
      return math.max(1, (processors * _desktopExtremeEncodeCpuShare).floor());
    }
    return 1;
  }

  _MCOImageEncodeRequest _buildEncodeRequest() {
    return _MCOImageEncodeRequest(
      width: _width,
      height: _height,
      paletteProfile: _paletteProfile,
      pixels: _pixels,
      transparentColor: _supportsAlphaTransparency ? _transparentColor : null,
      encodingVersion: _encodingVersion,
      backgroundColor: _supportsAlphaTransparency
          ? (_transparentColor ?? _whiteIndex)
          : _whiteIndex,
      outputTarget: widget.maxBinaryPayloadBytes != null
          ? MCOImageOutputTarget.binary
          : MCOImageOutputTarget.text,
      compressionLevel: _compressionLevel,
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

  String _vectorFigureLabel(MCOImageV4Figure figure) {
    return switch (figure) {
      MCOImageV4Dot() => context.l10n.chat_canvasV4ToolDot,
      MCOImageV4Line() => context.l10n.chat_canvasV4ToolLine,
      MCOImageV4Rect() => context.l10n.chat_canvasV4ToolRect,
      MCOImageV4Ellipse() => context.l10n.chat_canvasV4ToolEllipse,
      MCOImageV4Path() => context.l10n.chat_canvasV4ToolPolyline,
      MCOImageV4Wave() => context.l10n.chat_canvasV4ToolWave,
      MCOImageV4Group() => 'Группа',
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

  MCOImageV4Document _newVectorDocument(
    int width,
    int height,
    PaletteProfile profile,
  ) {
    final palette = _vectorDocumentPaletteFor(profile);
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

  List<int> _vectorDocumentPaletteFor(PaletteProfile profile) {
    if (!profile.isDynamic) {
      return List<int>.generate(
        MCOImagePalette.colorsFor(profile).length,
        (index) => index,
        growable: true,
      );
    }
    final colors = MCOImageDynamicPalette.indicesFor(profile);
    if (colors.length <= 64) return List<int>.of(colors, growable: true);
    return <int>[
      MCOImageDynamicPalette.whiteGlobalIndexFor(profile),
      MCOImageDynamicPalette.blackGlobalIndexFor(profile),
    ];
  }

  Color _profileColor(PaletteProfile profile, int colorValue) {
    return profile.isDynamic
        ? MCOImageDynamicPalette.global512[colorValue]
        : MCOImagePalette.colorsFor(profile)[colorValue];
  }

  List<int> _rasterPaletteValues(PaletteProfile profile) {
    if (profile.isDynamic) {
      return List<int>.of(MCOImageDynamicPalette.indicesFor(profile));
    }
    return List<int>.generate(
      MCOImagePalette.colorsFor(profile).length,
      (index) => index,
      growable: false,
    );
  }

  int _nearestRasterColorValue(
    int red,
    int green,
    int blue,
    PaletteProfile profile,
    List<int> paletteValues,
  ) {
    var best = paletteValues.first;
    var bestDistance = 1 << 62;
    for (final value in paletteValues) {
      final color = _profileColor(profile, value);
      final argb = color.toARGB32();
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
    final vectorDocument = _v4Document;
    if (_isVectorV4 && vectorDocument != null) {
      final values = <int>{};
      void addLocal(int? localIndex) {
        if (localIndex == null ||
            localIndex < 0 ||
            localIndex >= vectorDocument.palette.length) {
          return;
        }
        values.add(vectorDocument.palette[localIndex]);
      }

      addLocal(vectorDocument.backgroundColor);
      for (final figure in vectorDocument.figures.where(
        (figure) => figure.visible,
      )) {
        addLocal(figure.style.fillColor);
        addLocal(figure.style.strokeColor);
      }
      final sorted = values.toList()
        ..sort((a, b) {
          final aIndex = _paletteIndexForColorValue(profile, a) ?? 0;
          final bIndex = _paletteIndexForColorValue(profile, b) ?? 0;
          return aIndex.compareTo(bIndex);
        });
      return sorted;
    }
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
            document.copyWith(figures: [previewFigure]),
            logicalViewport: viewport,
          ),
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

class _VectorCanvasPainter extends CustomPainter {
  static const Color _rulerColor = Color(0xff808080);
  static const double _referenceOpacity = 0.45;

  final MCOImageV4Document document;
  final MCOImageV4Figure? selectedFigure;
  final List<int>? referencePixels;
  final PaletteProfile? referenceProfile;
  final int? referenceTransparentColor;
  final List<MCOImageV4Point> guidePoints;
  final MCOImageV4Style guideStyle;
  final bool showGrid;
  final bool showRuler;
  final Offset canvasOffset;
  final Size canvasSize;
  final double rulerExtent;

  const _VectorCanvasPainter({
    required this.document,
    required this.selectedFigure,
    required this.referencePixels,
    required this.referenceProfile,
    required this.referenceTransparentColor,
    required this.guidePoints,
    required this.guideStyle,
    required this.showGrid,
    required this.showRuler,
    required this.canvasOffset,
    required this.canvasSize,
    required this.rulerExtent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (showRuler) {
      _paintRulerLabels(canvas);
    }

    canvas.save();
    canvas.translate(canvasOffset.dx, canvasOffset.dy);
    final hasReference =
        referencePixels != null &&
        referencePixels!.length == document.width * document.height &&
        referenceProfile != null;
    if (hasReference) {
      _paintReference(canvas, referencePixels!, referenceProfile!);
    }
    MCOImageV4Painter(
      document,
      selectedFigure: selectedFigure,
      selectionColor: const Color(0xff00aaff),
      guidePoints: const [],
      guideStyle: guideStyle,
      paintBackground: !hasReference,
      showGrid: showGrid,
    ).paint(canvas, canvasSize);
    _paintGuidePoints(canvas);
    canvas.restore();
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

  void _paintRulerLabels(Canvas canvas) {
    const style = TextStyle(color: _rulerColor, fontSize: 7, height: 1);
    final cellWidth = canvasSize.width / document.width;
    final cellHeight = canvasSize.height / document.height;

    for (final cellNumber in _rulerCellNumbers(document.width)) {
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

    for (final cellNumber in _rulerCellNumbers(document.height)) {
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

  void _paintGuidePoints(Canvas canvas) {
    if (guidePoints.isEmpty) return;
    final cellWidth = canvasSize.width / document.width;
    final cellHeight = canvasSize.height / document.height;
    final radius = math.max(
      3.0,
      math.min(6.0, math.min(cellWidth, cellHeight)),
    );
    final fillPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = const Color(0xff00aaff);
    final outlinePaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xffffffff);
    for (final point in guidePoints) {
      final center = Offset(
        (point.x + 0.5) * cellWidth,
        (point.y + 0.5) * cellHeight,
      );
      canvas
        ..drawCircle(center, radius, fillPaint)
        ..drawCircle(center, radius, outlinePaint);
    }
  }

  void _paintReference(
    Canvas canvas,
    List<int> pixels,
    PaletteProfile profile,
  ) {
    final cellWidth = canvasSize.width / document.width;
    final cellHeight = canvasSize.height / document.height;
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < document.height; y++) {
      for (var x = 0; x < document.width; x++) {
        final colorValue = pixels[y * document.width + x];
        if (referenceTransparentColor != null &&
            colorValue == referenceTransparentColor) {
          continue;
        }
        paint.color = _referenceColor(
          profile,
          colorValue,
        ).withValues(alpha: _referenceOpacity);
        canvas.drawRect(
          Rect.fromLTWH(
            x * cellWidth,
            y * cellHeight,
            cellWidth,
            cellHeight,
          ),
          paint,
        );
      }
    }
  }

  Color _referenceColor(PaletteProfile profile, int colorValue) {
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
      return MCOImageDynamicPalette.global512[safeColorValue];
    }
    final colors = MCOImagePalette.colorsFor(profile);
    final colorIndex = colorValue.clamp(0, colors.length - 1).toInt();
    return colors[colorIndex];
  }

  @override
  bool shouldRepaint(covariant _VectorCanvasPainter oldDelegate) {
    return oldDelegate.document != document ||
        oldDelegate.selectedFigure != selectedFigure ||
        oldDelegate.referencePixels != referencePixels ||
        oldDelegate.referenceProfile != referenceProfile ||
        oldDelegate.referenceTransparentColor != referenceTransparentColor ||
        oldDelegate.guidePoints != guidePoints ||
        oldDelegate.guideStyle != guideStyle ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.showRuler != showRuler ||
        oldDelegate.canvasOffset != canvasOffset ||
        oldDelegate.canvasSize != canvasSize ||
        oldDelegate.rulerExtent != rulerExtent;
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

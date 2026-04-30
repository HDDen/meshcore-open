import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../screens/channels_screen.dart';
import '../screens/contacts_screen.dart';
import '../models/app_settings.dart';
import '../services/app_settings_service.dart';
import '../services/line_of_sight_service.dart';
import '../services/map_tile_cache_service.dart';
import '../utils/route_transitions.dart';
import '../connector/meshcore_connector.dart';
import '../widgets/app_bar.dart';
import '../widgets/quick_switch_bar.dart';
import '../icons/los_icon.dart';

class LineOfSightEndpoint {
  final String label;
  final LatLng point;
  final Color color;
  final IconData icon;
  final bool isCustom;

  const LineOfSightEndpoint({
    required this.label,
    required this.point,
    this.color = Colors.green,
    this.icon = Icons.location_on,
    this.isCustom = false,
  });
}

class LineOfSightMapScreen extends StatefulWidget {
  final String title;
  final List<LineOfSightEndpoint> candidates;

  const LineOfSightMapScreen({
    super.key,
    required this.title,
    required this.candidates,
  });

  @override
  State<LineOfSightMapScreen> createState() => _LineOfSightMapScreenState();
}

class _LineOfSightMapScreenState extends State<LineOfSightMapScreen> {
  static const String _errorSelectStartEnd = 'los_error_select_start_end';
  static const double _metersToFeet = 3.28084;
  static const double _kmToMiles = 0.621371;
  static const double _maxAntennaFeet = 400.0;
  static const double _maxAntennaMeters = _maxAntennaFeet / _metersToFeet;
  static const double _labelZoomThreshold = 8.5;
  static const double _mapMinZoom = 2.0;
  static const double _mapMaxZoom = 18.0;

  final LineOfSightService _lineOfSightService = LineOfSightService();
  final MapController _mapController = MapController();

  bool _loading = false;
  String? _error;
  LineOfSightPathResult? _result;
  LineOfSightObstruction? _selectedObstruction;
  LineOfSightEndpoint? _start;
  LineOfSightEndpoint? _end;
  final List<LineOfSightEndpoint> _customEndpoints = [];
  double _startAntennaHeight = 5.0;
  double _endAntennaHeight = 5.0;
  bool _showHud = true;
  bool _menuExpanded = true;
  bool _showDisplayNodes = true;
  bool _showMarkerLabels = true;
  bool _didReceivePositionUpdate = false;
  int _losRequestNonce = 0;
  bool _initialLosScheduled = false;

  @override
  void initState() {
    super.initState();
    if (widget.candidates.isNotEmpty) {
      _start = widget.candidates.first;
      if (widget.candidates.length > 1) {
        _end = widget.candidates[1];
      }
    }
    _scheduleInitialRun();
  }

  void _scheduleInitialRun() {
    if (_initialLosScheduled) return;
    _initialLosScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runLos();
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    _lineOfSightService.dispose();
    super.dispose();
  }

  bool _isDesktopPlatform(TargetPlatform platform) {
    return platform == TargetPlatform.linux ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS;
  }

  void _zoomMapBy(double delta) {
    final camera = _mapController.camera;
    final nextZoom = (camera.zoom + delta)
        .clamp(_mapMinZoom, _mapMaxZoom)
        .toDouble();
    _mapController.move(camera.center, nextZoom);
  }

  void _resetMapView({
    required LatLng initialCenter,
    required double initialZoom,
    required LatLngBounds? bounds,
  }) {
    if (bounds != null) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(64),
          maxZoom: 16,
        ),
      );
      return;
    }
    _mapController.move(initialCenter, initialZoom);
  }

  Widget _buildDesktopMapControls({
    required LatLng initialCenter,
    required double initialZoom,
    required LatLngBounds? bounds,
  }) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topOffset = _showHud
        ? math.min(screenHeight * 0.52 + 24, screenHeight - 220)
        : 12.0;
    return Positioned(
      top: topOffset,
      left: 12,
      child: Card(
        elevation: 4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Zoom in',
              onPressed: () => _zoomMapBy(1),
            ),
            IconButton(
              icon: const Icon(Icons.remove),
              tooltip: 'Zoom out',
              onPressed: () => _zoomMapBy(-1),
            ),
            IconButton(
              icon: const Icon(Icons.my_location),
              tooltip: 'Center map',
              onPressed: () => _resetMapView(
                initialCenter: initialCenter,
                initialZoom: initialZoom,
                bounds: bounds,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runLos() async {
    final start = _start;
    final end = _end;
    final startAntenna = _startAntennaHeight;
    final endAntenna = _endAntennaHeight;
    final requestId = ++_losRequestNonce;
    if (start == null || end == null) {
      setState(() {
        _result = null;
        _selectedObstruction = null;
        _error = _errorSelectStartEnd;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final connector = context.read<MeshCoreConnector>();
      final frequencyMHz = _normalizeFrequencyMHz(connector.currentFreqHz);
      final result = await _lineOfSightService.analyzePath(
        [start.point, end.point],
        startAntennaHeightMeters: startAntenna,
        endAntennaHeightMeters: endAntenna,
        frequencyMHz: frequencyMHz,
      );
      if (!mounted) return;
      if (!_isRunRequestCurrent(
        requestId: requestId,
        start: start,
        end: end,
        startAntenna: startAntenna,
        endAntenna: endAntenna,
      )) {
        return;
      }
      setState(() {
        _result = result;
        _selectedObstruction = _defaultObstructionFor(result);
      });
    } catch (e) {
      if (!mounted) return;
      if (!_isRunRequestCurrent(
        requestId: requestId,
        start: start,
        end: end,
        startAntenna: startAntenna,
        endAntenna: endAntenna,
      )) {
        return;
      }
      setState(() {
        _result = null;
        _selectedObstruction = null;
        _error = context.l10n.losRunFailed(e.toString());
      });
    } finally {
      if (mounted && requestId == _losRequestNonce) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  bool _isRunRequestCurrent({
    required int requestId,
    required LineOfSightEndpoint start,
    required LineOfSightEndpoint end,
    required double startAntenna,
    required double endAntenna,
  }) {
    return requestId == _losRequestNonce &&
        identical(_start, start) &&
        identical(_end, end) &&
        _startAntennaHeight == startAntenna &&
        _endAntennaHeight == endAntenna;
  }

  void _selectFromMap(LineOfSightEndpoint endpoint) {
    setState(() {
      _result = null;
      _selectedObstruction = null;
      _error = null;
      if (_start == null || (_start != null && _end != null)) {
        _start = endpoint;
        if (_end == endpoint) _end = null;
      } else {
        _end = endpoint;
        if (_start == endpoint) _start = null;
      }
    });

    if (_start != null && _end != null) {
      _runLos();
    }
  }

  void _addCustomPoint(LatLng point) {
    final endpoint = LineOfSightEndpoint(
      label: context.l10n.losCustomPointLabel(_customEndpoints.length + 1),
      point: point,
      color: Colors.orange,
      icon: Icons.push_pin,
      isCustom: true,
    );
    setState(() {
      _customEndpoints.add(endpoint);
    });
    _selectFromMap(endpoint);
  }

  List<LineOfSightEndpoint> _visibleEndpoints() {
    return [if (_showDisplayNodes) ...widget.candidates, ..._customEndpoints];
  }

  bool _hasEndpoint(
    List<LineOfSightEndpoint> endpoints,
    LineOfSightEndpoint? e,
  ) {
    if (e == null) return false;
    return endpoints.any((item) => identical(item, e));
  }

  void _sanitizeSelection() {
    final visible = _visibleEndpoints();
    if (!_hasEndpoint(visible, _start)) {
      _start = null;
    }
    if (!_hasEndpoint(visible, _end)) {
      _end = null;
    }
  }

  void _clearAllPoints() {
    setState(() {
      _customEndpoints.clear();
      _start = null;
      _end = null;
      _result = null;
      _selectedObstruction = null;
      _error = _errorSelectStartEnd;
    });
  }

  void _deleteCustomPoint(LineOfSightEndpoint endpoint) {
    setState(() {
      _customEndpoints.removeWhere((e) => identical(e, endpoint));
      if (identical(_start, endpoint)) _start = null;
      if (identical(_end, endpoint)) _end = null;
      _result = null;
      _selectedObstruction = null;
    });
  }

  Future<void> _renameCustomPoint(LineOfSightEndpoint endpoint) async {
    final controller = TextEditingController(text: endpoint.label);
    final newLabel = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.losRenameCustomPoint),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: context.l10n.losPointName,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              Navigator.pop(dialogContext, value);
            },
            child: Text(context.l10n.common_save),
          ),
        ],
      ),
    );

    if (newLabel == null || newLabel.isEmpty) return;
    final index = _customEndpoints.indexWhere((e) => identical(e, endpoint));
    if (index < 0) return;
    final renamed = LineOfSightEndpoint(
      label: newLabel,
      point: endpoint.point,
      color: endpoint.color,
      icon: endpoint.icon,
      isCustom: endpoint.isCustom,
    );
    setState(() {
      _customEndpoints[index] = renamed;
      if (identical(_start, endpoint)) _start = renamed;
      if (identical(_end, endpoint)) _end = renamed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsService>().settings;
    final isImperial = settings.unitSystem == UnitSystem.imperial;
    final tileCache = context.read<MapTileCacheService>();
    final endpoints = _visibleEndpoints();
    final mapPoints = [
      if (_start != null) _start!.point,
      if (_end != null) _end!.point,
    ];
    final initialCenter = mapPoints.isNotEmpty
        ? mapPoints.first
        : const LatLng(0, 0);
    final bounds = mapPoints.length > 1
        ? LatLngBounds.fromPoints(mapPoints)
        : null;
    final initialZoom = mapPoints.length > 1 ? 13.0 : 2.0;
    final isDesktop = _isDesktopPlatform(defaultTargetPlatform);
    if (!_didReceivePositionUpdate) {
      _showMarkerLabels = initialZoom >= _labelZoomThreshold;
    }

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(widget.title),
        centerTitle: true,
        actions: [
          IconButton(
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            onPressed: _loading ? null : _clearAllPoints,
            tooltip: context.l10n.losClearAllPoints,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: initialZoom,
              initialCameraFit: bounds == null
                  ? null
                  : CameraFit.bounds(
                      bounds: bounds,
                      padding: const EdgeInsets.all(64),
                      maxZoom: 16,
                    ),
              interactionOptions: InteractionOptions(
                flags: ~InteractiveFlag.rotate,
                scrollWheelVelocity: isDesktop ? 0.012 : 0.005,
                cursorKeyboardRotationOptions:
                    CursorKeyboardRotationOptions.disabled(),
                keyboardOptions: isDesktop
                    ? const KeyboardOptions(
                        enableArrowKeysPanning: true,
                        enableWASDPanning: true,
                        enableRFZooming: true,
                      )
                    : const KeyboardOptions.disabled(),
              ),
              minZoom: _mapMinZoom,
              maxZoom: _mapMaxZoom,
              onLongPress: (_, point) => _addCustomPoint(point),
              onPositionChanged: (camera, hasGesture) {
                final shouldShow = camera.zoom >= _labelZoomThreshold;
                if (!_didReceivePositionUpdate ||
                    shouldShow != _showMarkerLabels) {
                  setState(() {
                    _didReceivePositionUpdate = true;
                    _showMarkerLabels = shouldShow;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: kMapTileUrlTemplate,
                tileProvider: tileCache.tileProvider,
                userAgentPackageName: MapTileCacheService.userAgentPackageName,
                maxZoom: 19,
              ),
              if (_result != null && _result!.segments.isNotEmpty)
                PolylineLayer(polylines: _buildSegmentPolylines(_result!)),
              MarkerLayer(
                markers: _buildMarkers(endpoints, _primaryObstructions()),
              ),
            ],
          ),
          if (isDesktop)
            _buildDesktopMapControls(
              initialCenter: initialCenter,
              initialZoom: initialZoom,
              bounds: bounds,
            ),
          if (_showHud)
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.52,
                ),
                child: _buildControlPanel(isImperial),
              ),
            ),
          if (!_showHud && _result != null && _result!.segments.isNotEmpty)
            Positioned(
              left: 12,
              bottom: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    context.l10n.losElevationAttribution,
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _showHud = !_showHud;
          });
        },
        tooltip: _showHud
            ? context.l10n.losHidePanelTooltip
            : context.l10n.losShowPanelTooltip,
        child: Icon(_showHud ? Icons.visibility_off : Icons.tune),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: QuickSwitchBar(
          selectedIndex: 2,
          onDestinationSelected: (index) => _handleQuickSwitch(index, context),
        ),
      ),
    );
  }

  Widget _buildControlPanel(bool isImperial) {
    _sanitizeSelection();
    final segment = _primarySegmentResult();
    final connector = context.read<MeshCoreConnector>();
    final reportedFrequencyMHz = _normalizeFrequencyMHz(
      connector.currentFreqHz,
    );
    final displayFrequencyMHz = segment?.frequencyMHz ?? reportedFrequencyMHz;
    final kFactorUsed = segment?.usedKFactor;
    final obstructions =
        segment?.obstructions ?? const <LineOfSightObstruction>[];
    final endpoints = _visibleEndpoints();
    final distanceUnit = isImperial ? 'mi' : 'km';
    final heightUnit = isImperial ? 'ft' : 'm';
    final antennaAMeters = _startAntennaHeight;
    final antennaBMeters = _endAntennaHeight;
    final antennaADisplay = _toDisplayHeight(antennaAMeters, isImperial);
    final antennaBDisplay = _toDisplayHeight(antennaBMeters, isImperial);
    final antennaSliderMax = isImperial ? _maxAntennaFeet : _maxAntennaMeters;
    final antennaSliderDivisions = isImperial ? 400 : 122;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (segment != null)
                _buildProfileView(segment, distanceUnit, heightUnit, isImperial)
              else
                SizedBox(
                  height: 44,
                  child: Center(
                    child: Text(
                      context.l10n.losRunToViewElevationProfile,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              if (segment != null) ...[
                const SizedBox(height: 8),
                _LosLegend(
                  terrainLabel: context.l10n.losLegendTerrain,
                  losBeamLabel: context.l10n.losLegendLosBeam,
                  radioHorizonLabel: context.l10n.losLegendRadioHorizon,
                ),
              ],
              const SizedBox(height: 8),
              Text(
                segment != null
                    ? _profileStats(segment, isImperial)
                    : _statusText(),
                style: TextStyle(
                  fontSize: 12,
                  color: segment != null
                      ? (segment.isClear ? Colors.green : Colors.red)
                      : _statusColor(),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (obstructions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  context.l10n.losBlockedSpotsTitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.losBlockedSpotsHint,
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final obstruction in obstructions)
                      ChoiceChip(
                        label: Text(
                          _obstructionChipLabel(obstruction, isImperial),
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected:
                            _selectedObstruction?.sampleIndex ==
                            obstruction.sampleIndex,
                        onSelected: (_) => _selectObstruction(obstruction),
                      ),
                  ],
                ),
                if (_selectedObstruction != null) ...[
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.deepOrangeAccent.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.losSelectedObstructionTitle,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.l10n.losSelectedObstructionDetails(
                              _formatHeightValue(
                                _selectedObstruction!.obstructionMeters,
                                isImperial,
                              ),
                              heightUnit,
                              _formatDistanceValue(
                                _selectedObstruction!.distanceMeters,
                                isImperial,
                              ),
                              distanceUnit,
                              _formatDistanceValue(
                                segment!.totalDistanceMeters -
                                    _selectedObstruction!.distanceMeters,
                                isImperial,
                              ),
                            ),
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_selectedObstruction!.point.latitude.toStringAsFixed(5)}, '
                            '${_selectedObstruction!.point.longitude.toStringAsFixed(5)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 4),
              if (displayFrequencyMHz != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: Row(
                    children: [
                      Text(
                        context.l10n.losFrequencyLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${displayFrequencyMHz.toStringAsFixed(3)} MHz',
                        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                      ),
                      if (kFactorUsed != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          'k=${kFactorUsed.toStringAsFixed(3)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.info_outline, size: 16),
                          color: Colors.grey[600],
                          tooltip: context.l10n.losFrequencyInfoTooltip,
                          onPressed: () {
                            _showFrequencyInfoDialog(
                              context,
                              displayFrequencyMHz,
                              kFactorUsed,
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              Text(
                context.l10n.losElevationAttribution,
                style: TextStyle(fontSize: 10, color: Colors.grey[700]),
              ),
              const SizedBox(height: 6),
              ExpansionTile(
                initiallyExpanded: _menuExpanded,
                onExpansionChanged: (value) {
                  setState(() {
                    _menuExpanded = value;
                  });
                },
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  context.l10n.losMenuTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  context.l10n.losMenuSubtitle,
                  style: const TextStyle(fontSize: 11),
                ),
                children: [
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.l10n.losShowDisplayNodes,
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: _showDisplayNodes,
                    onChanged: (value) {
                      setState(() {
                        _showDisplayNodes = value;
                        _sanitizeSelection();
                        _result = null;
                        _selectedObstruction = null;
                      });
                    },
                  ),
                  if (_customEndpoints.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.losCustomPoints,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    for (final point in _customEndpoints)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          point.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          '${point.point.latitude.toStringAsFixed(5)}, ${point.point.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () => _renameCustomPoint(point),
                              tooltip: context.l10n.common_edit,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => _deleteCustomPoint(point),
                              tooltip: context.l10n.common_delete,
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  _buildEndpointRow(
                    label: context.l10n.losPointA,
                    value: _start,
                    candidates: endpoints,
                    onChanged: (value) {
                      setState(() {
                        _start = value;
                        _result = null;
                        _selectedObstruction = null;
                      });
                      if (_start != null && _end != null) {
                        _runLos();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildEndpointRow(
                    label: context.l10n.losPointB,
                    value: _end,
                    candidates: endpoints,
                    onChanged: (value) {
                      setState(() {
                        _end = value;
                        _result = null;
                        _selectedObstruction = null;
                      });
                      if (_start != null && _end != null) {
                        _runLos();
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.losAntennaA(
                      antennaADisplay.toStringAsFixed(1),
                      heightUnit,
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                  Slider(
                    value: antennaADisplay,
                    min: 0,
                    max: antennaSliderMax,
                    divisions: antennaSliderDivisions,
                    onChanged: (value) {
                      setState(() {
                        _startAntennaHeight = _toMetersHeight(
                          value,
                          isImperial,
                        );
                      });
                    },
                  ),
                  Text(
                    context.l10n.losAntennaB(
                      antennaBDisplay.toStringAsFixed(1),
                      heightUnit,
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                  Slider(
                    value: antennaBDisplay,
                    min: 0,
                    max: antennaSliderMax,
                    divisions: antennaSliderDivisions,
                    onChanged: (value) {
                      setState(() {
                        _endAntennaHeight = _toMetersHeight(value, isImperial);
                      });
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _runLos,
                      icon: const LosIcon(),
                      label: Text(context.l10n.losRun),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEndpointRow({
    required String label,
    required LineOfSightEndpoint? value,
    required List<LineOfSightEndpoint> candidates,
    required ValueChanged<LineOfSightEndpoint?> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: DropdownButton<LineOfSightEndpoint>(
            value: value,
            isExpanded: true,
            items: candidates
                .map(
                  (e) => DropdownMenuItem<LineOfSightEndpoint>(
                    value: e,
                    child: Text(e.label, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  LineOfSightResult? _primarySegmentResult() {
    if (_result == null || _result!.segments.isEmpty) return null;
    return _result!.segments.first.result;
  }

  List<LineOfSightObstruction> _primaryObstructions() {
    return _primarySegmentResult()?.obstructions ?? const [];
  }

  LineOfSightObstruction? _defaultObstructionFor(
    LineOfSightPathResult? result,
  ) {
    if (result == null || result.segments.isEmpty) return null;
    final obstructions = result.segments.first.result.obstructions;
    if (obstructions.isEmpty) return null;
    return obstructions.reduce(
      (current, next) =>
          next.obstructionMeters > current.obstructionMeters ? next : current,
    );
  }

  void _selectObstruction(LineOfSightObstruction obstruction) {
    setState(() {
      _selectedObstruction = obstruction;
    });
  }

  String _formatDistanceValue(double meters, bool isImperial) {
    final value = isImperial ? (meters / 1000.0) * _kmToMiles : meters / 1000.0;
    return value.toStringAsFixed(2);
  }

  String _formatHeightValue(double meters, bool isImperial) {
    final value = isImperial ? meters * _metersToFeet : meters;
    return value.toStringAsFixed(1);
  }

  String _obstructionChipLabel(
    LineOfSightObstruction obstruction,
    bool isImperial,
  ) {
    final distanceUnit = isImperial ? 'mi' : 'km';
    final heightUnit = isImperial ? 'ft' : 'm';
    return context.l10n.losBlockedSpotChip(
      _formatDistanceValue(obstruction.distanceMeters, isImperial),
      distanceUnit,
      _formatHeightValue(obstruction.obstructionMeters, isImperial),
      heightUnit,
    );
  }

  Widget _buildProfileView(
    LineOfSightResult segment,
    String distanceUnit,
    String heightUnit,
    bool isImperial,
  ) {
    if (segment.samples.length < 2) {
      return SizedBox(
        height: 160,
        width: double.infinity,
        child: CustomPaint(
          painter: _LosProfilePainter(
            samples: segment.samples,
            distanceUnit: distanceUnit,
            heightUnit: heightUnit,
            badgeTextStyle:
                Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ) ??
                const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
            terrainLabel: context.l10n.losLegendTerrain,
            losBeamLabel: context.l10n.losLegendLosBeam,
            radioHorizonLabel: context.l10n.losLegendRadioHorizon,
            selectedSampleIndex: _selectedObstruction?.sampleIndex,
          ),
        ),
      );
    }
    return SizedBox(
      height: 160,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, 160);
          final geometry = _LosProfileGeometry(
            samples: segment.samples,
            size: size,
          );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _LosProfilePainter(
                    samples: segment.samples,
                    distanceUnit: distanceUnit,
                    heightUnit: heightUnit,
                    badgeTextStyle:
                        Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ) ??
                        const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                    terrainLabel: context.l10n.losLegendTerrain,
                    losBeamLabel: context.l10n.losLegendLosBeam,
                    radioHorizonLabel: context.l10n.losLegendRadioHorizon,
                    selectedSampleIndex: _selectedObstruction?.sampleIndex,
                  ),
                ),
              ),
              for (final obstruction in segment.obstructions)
                Builder(
                  builder: (context) {
                    final sample = segment.samples[obstruction.sampleIndex];
                    final position = geometry.mapPoint(
                      sample.distanceMeters,
                      sample.terrainMeters,
                    );
                    final isSelected =
                        _selectedObstruction?.sampleIndex ==
                        obstruction.sampleIndex;
                    final markerSize = isSelected ? 18.0 : 14.0;
                    final left = (position.dx - markerSize / 2)
                        .clamp(0.0, math.max(0.0, size.width - markerSize))
                        .toDouble();
                    final top = (position.dy - markerSize / 2)
                        .clamp(0.0, math.max(0.0, size.height - markerSize))
                        .toDouble();
                    return Positioned(
                      left: left,
                      top: top,
                      child: Tooltip(
                        message: _obstructionChipLabel(obstruction, isImperial),
                        child: GestureDetector(
                          onTap: () => _selectObstruction(obstruction),
                          child: Container(
                            width: markerSize,
                            height: markerSize,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.amberAccent
                                  : Colors.deepOrangeAccent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black87,
                                width: isSelected ? 2 : 1.5,
                              ),
                              boxShadow: const [
                                BoxShadow(color: Colors.black45, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  String _profileStats(LineOfSightResult result, bool isImperial) {
    final distance = isImperial
        ? (result.totalDistanceMeters / 1000.0) * _kmToMiles
        : result.totalDistanceMeters / 1000.0;
    final distanceUnit = isImperial ? 'mi' : 'km';
    final heightUnit = isImperial ? 'ft' : 'm';
    final minClearance = result.samples.isEmpty
        ? 0.0
        : result.samples.map((s) => s.clearanceMeters).reduce(math.min);
    final minClearanceDisplay = isImperial
        ? minClearance * _metersToFeet
        : minClearance;
    final maxObstructionDisplay = isImperial
        ? result.maxObstructionMeters * _metersToFeet
        : result.maxObstructionMeters;
    if (!result.hasData) {
      return _localizedLosError(result.errorMessage);
    }
    if (result.isClear) {
      return context.l10n.losProfileClear(
        distance.toStringAsFixed(1),
        distanceUnit,
        minClearanceDisplay.toStringAsFixed(1),
        heightUnit,
      );
    }
    return context.l10n.losProfileBlocked(
      distance.toStringAsFixed(1),
      distanceUnit,
      maxObstructionDisplay.toStringAsFixed(1),
      heightUnit,
    );
  }

  List<Polyline> _buildSegmentPolylines(LineOfSightPathResult result) {
    final polylines = <Polyline>[];
    for (final segment in result.segments) {
      final color = !segment.result.hasData
          ? Colors.grey
          : (segment.result.isClear ? Colors.green : Colors.red);
      polylines.add(
        Polyline(
          points: [segment.start, segment.end],
          strokeWidth: 4,
          color: color,
        ),
      );
    }
    return polylines;
  }

  List<Marker> _buildMarkers(
    List<LineOfSightEndpoint> endpoints,
    List<LineOfSightObstruction> obstructions,
  ) {
    return [
      for (final obstruction in obstructions)
        Marker(
          point: obstruction.point,
          width: 52,
          height: 52,
          child: GestureDetector(
            onTap: () => _selectObstruction(obstruction),
            child: Center(
              child: Container(
                width:
                    _selectedObstruction?.sampleIndex == obstruction.sampleIndex
                    ? 36
                    : 24,
                height:
                    _selectedObstruction?.sampleIndex == obstruction.sampleIndex
                    ? 36
                    : 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                  border: Border.all(
                    color:
                        _selectedObstruction?.sampleIndex ==
                            obstruction.sampleIndex
                        ? Colors.amberAccent
                        : Colors.deepOrangeAccent,
                    width:
                        _selectedObstruction?.sampleIndex ==
                            obstruction.sampleIndex
                        ? 4
                        : 3,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      for (final endpoint in endpoints)
        Marker(
          point: endpoint.point,
          width: 36,
          height: 36,
          child: GestureDetector(
            onTap: () => _selectFromMap(endpoint),
            child: Container(
              decoration: BoxDecoration(
                color: endpoint.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4),
                ],
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(endpoint.icon, color: Colors.white, size: 16),
                  ),
                  if (endpoint == _start || endpoint == _end)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          endpoint == _start ? 'A' : 'B',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      for (final endpoint in endpoints)
        if (_showMarkerLabels)
          Marker(
            point: endpoint.point,
            width: 120,
            height: 24,
            alignment: Alignment.topCenter,
            child: IgnorePointer(
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      endpoint.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
    ];
  }

  String _statusText() {
    if (_loading) return context.l10n.losStatusChecking;
    if (_error == _errorSelectStartEnd) {
      return context.l10n.losSelectStartEnd;
    }
    if (_error != null) return _error!;
    if (_result == null) return context.l10n.losStatusNoData;
    final total = _result!.segments.length;
    return context.l10n.losStatusSummary(
      _result!.clearSegments,
      total,
      _result!.blockedSegments,
      _result!.unknownSegments,
    );
  }

  Color _statusColor() {
    if (_error != null) return Colors.red;
    if (_loading) return Colors.orange;
    if (_result == null) return Colors.grey;
    if (_result!.blockedSegments > 0) return Colors.red;
    if (_result!.clearSegments > 0) return Colors.green;
    return Colors.grey;
  }

  double _toDisplayHeight(double meters, bool isImperial) {
    return isImperial ? meters * _metersToFeet : meters;
  }

  double _toMetersHeight(double displayHeight, bool isImperial) {
    return isImperial ? displayHeight / _metersToFeet : displayHeight;
  }

  String _localizedLosError(String? message) {
    if (message == LineOfSightService.errorElevationUnavailable) {
      return context.l10n.losErrorElevationUnavailable;
    }
    if (message == LineOfSightService.errorInvalidInput) {
      return context.l10n.losErrorInvalidInput;
    }
    return context.l10n.losNoElevationData;
  }

  void _handleQuickSwitch(int index, BuildContext context) {
    if (index == 2) {
      Navigator.pop(context);
      return;
    }
    switch (index) {
      case 0:
        Navigator.pushReplacement(
          context,
          buildQuickSwitchRoute(const ContactsScreen(hideBackButton: true)),
        );
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          buildQuickSwitchRoute(const ChannelsScreen(hideBackButton: true)),
        );
        break;
    }
  }

  void _showFrequencyInfoDialog(
    BuildContext context,
    double frequencyMHz,
    double kFactor,
  ) {
    final baselineFreq = LineOfSightService.baselineFrequencyMHz;
    final baselineK = LineOfSightService.baselineKFactor;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.losFrequencyDialogTitle),
        content: Text(
          context.l10n.losFrequencyDialogDescription(
            baselineK,
            baselineFreq,
            frequencyMHz,
            kFactor,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.common_ok),
          ),
        ],
      ),
    );
  }

  double? _normalizeFrequencyMHz(int? frequencyKHz) {
    if (frequencyKHz == null || frequencyKHz <= 0) return null;
    return frequencyKHz / 1000.0;
  }
}

class _LosProfileGeometry {
  static const horizontalPadding = 12.0;
  static const verticalPadding = 12.0;

  final List<LineOfSightSample> samples;
  final Size size;
  late final double minY = samples
      .map(
        (s) => math.min(
          math.min(s.terrainMeters, s.lineHeightMeters),
          s.refractedHeightMeters,
        ),
      )
      .reduce(math.min);
  late final double maxY = samples
      .map(
        (s) => math.max(
          math.max(s.terrainMeters, s.lineHeightMeters),
          s.refractedHeightMeters,
        ),
      )
      .reduce(math.max);
  late final double ySpan = math.max(1.0, maxY - minY);
  late final double maxDist = math.max(1.0, samples.last.distanceMeters);
  late final double chartWidth = math.max(
    1.0,
    size.width - horizontalPadding * 2,
  );
  late final double chartHeight = math.max(
    1.0,
    size.height - verticalPadding * 2,
  );

  _LosProfileGeometry({required this.samples, required this.size});

  Offset mapPoint(double distanceMeters, double elevationMeters) {
    final px = horizontalPadding + (distanceMeters / maxDist) * chartWidth;
    final py =
        size.height -
        verticalPadding -
        ((elevationMeters - minY) / ySpan) * chartHeight;
    return Offset(px, py);
  }
}

class _LosProfilePainter extends CustomPainter {
  final List<LineOfSightSample> samples;
  final String distanceUnit;
  final String heightUnit;
  final TextStyle badgeTextStyle;
  final String terrainLabel;
  final String losBeamLabel;
  final String radioHorizonLabel;
  final int? selectedSampleIndex;

  const _LosProfilePainter({
    required this.samples,
    required this.distanceUnit,
    required this.heightUnit,
    required this.badgeTextStyle,
    required this.terrainLabel,
    required this.losBeamLabel,
    required this.radioHorizonLabel,
    this.selectedSampleIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF243A63);
    canvas.drawRect(Offset.zero & size, bg);
    _drawUnitBadge(canvas, size);

    if (samples.length < 2) return;

    final minY = samples
        .map(
          (s) => math.min(
            math.min(s.terrainMeters, s.lineHeightMeters),
            s.refractedHeightMeters,
          ),
        )
        .reduce(math.min);
    final maxY = samples
        .map(
          (s) => math.max(
            math.max(s.terrainMeters, s.lineHeightMeters),
            s.refractedHeightMeters,
          ),
        )
        .reduce(math.max);
    final ySpan = math.max(1.0, maxY - minY);
    final maxDist = math.max(1.0, samples.last.distanceMeters);
    const horizontalPadding = 12.0;
    const verticalPadding = 12.0;
    final chartWidth = math.max(1.0, size.width - horizontalPadding * 2);
    final chartHeight = math.max(1.0, size.height - verticalPadding * 2);

    Offset mapPoint(double x, double y) {
      final px = horizontalPadding + (x / maxDist) * chartWidth;
      final py =
          size.height - verticalPadding - ((y - minY) / ySpan) * chartHeight;
      return Offset(px, py);
    }

    final firstTerrainPoint = mapPoint(
      samples.first.distanceMeters,
      samples.first.terrainMeters,
    );
    final lastTerrainPoint = mapPoint(
      samples.last.distanceMeters,
      samples.last.terrainMeters,
    );

    double distanceForCanvasX(double x) {
      final normalized = ((x - horizontalPadding) / chartWidth).clamp(0.0, 1.0);
      return normalized * maxDist;
    }

    double elevationToPixel(double elevation) {
      final normalized = ((elevation - minY) / ySpan).clamp(0.0, 1.0);
      return size.height - verticalPadding - normalized * chartHeight;
    }

    double extrapolateTerrain(double distance, bool isLeft) {
      final samplesForSlope = isLeft
          ? samples.sublist(0, math.min(2, samples.length))
          : samples.sublist(samples.length - math.min(2, samples.length));
      if (samplesForSlope.length < 2) {
        return samplesForSlope.first.terrainMeters;
      }
      final a = samplesForSlope.first;
      final b = samplesForSlope.last;
      final dx = b.distanceMeters - a.distanceMeters;
      if (dx.abs() < 1e-6) return a.terrainMeters;
      final slope = (b.terrainMeters - a.terrainMeters) / dx;
      return a.terrainMeters + slope * (distance - a.distanceMeters);
    }

    final leftDistance = distanceForCanvasX(0.0);
    final rightDistance = distanceForCanvasX(size.width);
    final leftEdgeTerrain = extrapolateTerrain(leftDistance, true);
    final rightEdgeTerrain = extrapolateTerrain(rightDistance, false);
    final leftEdgePoint = Offset(0.0, elevationToPixel(leftEdgeTerrain));
    final rightEdgePoint = Offset(
      size.width,
      elevationToPixel(rightEdgeTerrain),
    );

    final terrainPath = ui.Path()
      ..moveTo(0, size.height)
      ..lineTo(leftEdgePoint.dx, leftEdgePoint.dy)
      ..lineTo(firstTerrainPoint.dx, firstTerrainPoint.dy);
    for (final sample in samples) {
      final p = mapPoint(sample.distanceMeters, sample.terrainMeters);
      terrainPath.lineTo(p.dx, p.dy);
    }
    terrainPath
      ..lineTo(lastTerrainPoint.dx, lastTerrainPoint.dy)
      ..lineTo(rightEdgePoint.dx, rightEdgePoint.dy)
      ..lineTo(size.width, size.height)
      ..close();

    const terrainFillColor = Color(0xCC7C6F5D);
    const terrainLineColor = Color(0xFF9FE870);
    const losLineColor = Color(0xFFE0E7FF);
    canvas.drawPath(terrainPath, Paint()..color = terrainFillColor);

    final terrainLine = ui.Path()..moveTo(leftEdgePoint.dx, leftEdgePoint.dy);
    for (final sample in samples) {
      final p = mapPoint(sample.distanceMeters, sample.terrainMeters);
      terrainLine.lineTo(p.dx, p.dy);
    }
    terrainLine.lineTo(rightEdgePoint.dx, rightEdgePoint.dy);
    canvas.drawPath(
      terrainLine,
      Paint()
        ..color = terrainLineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final losLine = ui.Path();
    for (int i = 0; i < samples.length; i++) {
      final p = mapPoint(
        samples[i].distanceMeters,
        samples[i].lineHeightMeters,
      );
      if (i == 0) {
        losLine.moveTo(p.dx, p.dy);
      } else {
        losLine.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      losLine,
      Paint()
        ..color = losLineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    const refractedLineColor = Color(0xFFFFD57F);
    final refractedLine = ui.Path();
    for (int i = 0; i < samples.length; i++) {
      final p = mapPoint(
        samples[i].distanceMeters,
        samples[i].refractedHeightMeters,
      );
      if (i == 0) {
        refractedLine.moveTo(p.dx, p.dy);
      } else {
        refractedLine.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      refractedLine,
      Paint()
        ..color = refractedLineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final capPath = ui.Path();
    for (int i = 0; i < samples.length; i++) {
      final p = mapPoint(
        samples[i].distanceMeters,
        samples[i].refractedHeightMeters,
      );
      if (i == 0) {
        capPath.moveTo(p.dx, p.dy);
      } else {
        capPath.lineTo(p.dx, p.dy);
      }
    }
    for (int i = samples.length - 1; i >= 0; i--) {
      final p = mapPoint(
        samples[i].distanceMeters,
        samples[i].lineHeightMeters,
      );
      capPath.lineTo(p.dx, p.dy);
    }
    capPath.close();
    const horizonFillColor = Color(0x40FFD57F);
    canvas.drawPath(
      capPath,
      Paint()
        ..color = horizonFillColor
        ..style = PaintingStyle.fill,
    );

    if (selectedSampleIndex != null &&
        selectedSampleIndex! >= 0 &&
        selectedSampleIndex! < samples.length) {
      final selectedSample = samples[selectedSampleIndex!];
      final selectedPoint = mapPoint(
        selectedSample.distanceMeters,
        selectedSample.terrainMeters,
      );
      canvas.drawLine(
        Offset(selectedPoint.dx, verticalPadding),
        Offset(selectedPoint.dx, size.height - verticalPadding),
        Paint()
          ..color = Colors.amberAccent.withValues(alpha: 0.7)
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(selectedPoint, 7, Paint()..color = Colors.amberAccent);
      canvas.drawCircle(
        selectedPoint,
        8.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LosProfilePainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.distanceUnit != distanceUnit ||
        oldDelegate.heightUnit != heightUnit ||
        oldDelegate.badgeTextStyle != badgeTextStyle ||
        oldDelegate.terrainLabel != terrainLabel ||
        oldDelegate.losBeamLabel != losBeamLabel ||
        oldDelegate.radioHorizonLabel != radioHorizonLabel ||
        oldDelegate.selectedSampleIndex != selectedSampleIndex;
  }

  void _drawUnitBadge(Canvas canvas, Size size) {
    final span = TextSpan(
      text: '$heightUnit / $distanceUnit',
      style: badgeTextStyle,
    );
    final painter = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();
    painter.paint(canvas, Offset(size.width - painter.width - 8, 8));
  }
}

class _LosLegend extends StatelessWidget {
  static const _terrainColor = Color(0xFF9FE870);
  static const _losColor = Color(0xFFE0E7FF);
  static const _radioColor = Color(0xFFFFD57F);

  final String terrainLabel;
  final String losBeamLabel;
  final String radioHorizonLabel;

  const _LosLegend({
    required this.terrainLabel,
    required this.losBeamLabel,
    required this.radioHorizonLabel,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle =
        Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ) ??
        const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        );

    final entries = [
      _LegendEntry(terrainLabel, _terrainColor),
      _LegendEntry(losBeamLabel, _losColor),
      _LegendEntry(radioHorizonLabel, _radioColor),
    ];

    const swatchSize = 10.0;

    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: entries
          .map(
            (entry) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: swatchSize,
                  height: swatchSize,
                  decoration: BoxDecoration(
                    color: entry.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(entry.label, style: textStyle),
              ],
            ),
          )
          .toList(),
    );
  }
}

class _LegendEntry {
  final String label;
  final Color color;

  const _LegendEntry(this.label, this.color);
}

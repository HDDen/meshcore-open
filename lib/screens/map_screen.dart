import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:meshcore_open/helpers/path_helper.dart';
import 'package:meshcore_open/screens/path_trace_map.dart';
import 'package:meshcore_open/widgets/app_bar.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../l10n/l10n.dart';
import '../models/app_settings.dart';
import '../models/channel.dart';
import '../models/contact.dart';
import '../l10n/contact_localization.dart';
import '../services/app_settings_service.dart';
import '../services/path_history_service.dart';
import '../services/map_marker_service.dart';
import '../services/map_tile_cache_service.dart';
import '../services/wardrive_service.dart';
import '../services/wardrive_sample_store.dart';
import '../services/wardrive_upload_service.dart';
import '../utils/contact_search.dart';
import '../utils/app_route_observer.dart';
import '../utils/disconnect_navigation_mixin.dart';
import '../utils/route_transitions.dart';
import '../helpers/wardrive_coverage_helper.dart';
import '../widgets/quick_switch_bar.dart';
import '../widgets/sync_progress_overlay.dart';
import '../widgets/themed_map_tile_layer.dart';
import '../widgets/wardrive_status_panel.dart';
import '../icons/los_icon.dart';
import 'channels_screen.dart';
import 'chat_screen.dart';
import 'contacts_screen.dart';
import '../theme/mesh_theme.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/repeater_login_dialog.dart';
import '../widgets/room_login_dialog.dart';
import '../helpers/snack_bar_builder.dart';
import 'repeater_hub_screen.dart';
import 'settings_screen.dart';
import 'line_of_sight_map_screen.dart';

class MapScreen extends StatefulWidget {
  final LatLng? highlightPosition;
  final String? highlightLabel;
  final String? highlightMarkerKey;
  final double highlightZoom;
  final bool hideBackButton;

  const MapScreen({
    super.key,
    this.highlightPosition,
    this.highlightLabel,
    this.highlightMarkerKey,
    this.highlightZoom = 15.0,
    this.hideBackButton = false,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with DisconnectNavigationMixin, RouteAware {
  // Zoom level at which node labels start to appear
  static const double _labelZoomThreshold = 14.0;
  // Below this zoom, nearby nodes collapse into clusters.
  static const double _clusterOffZoom = 12.5;
  // Guessed (estimated) locations only render at closer zooms to avoid a
  // carpet of approximate markers at city-wide scale.
  static const double _guessedZoomThreshold = 12.0;
  static const double _mapMinZoom = 2.0;
  static const double _mapMaxZoom = 18.0;
  static const double _wardrivePanelBottomInset = 16.0;
  static const Duration _wardriveDiscoveryRetryDelay = Duration(seconds: 10);

  final MapController _mapController = MapController();
  final GlobalKey _mapBodyKey = GlobalKey();
  final GlobalKey _wardrivePanelKey = GlobalKey();
  final MapMarkerService _markerService = MapMarkerService();
  final WardriveUploadService _wardriveUploadService = WardriveUploadService();
  final Set<String> _hiddenMarkerIds = {};
  Set<String> _removedMarkerIds = {};
  bool _isBuildingPathTrace = false;
  bool _isSelectingPoi = false;
  bool _hasInitializedMap = false;
  bool _removedMarkersLoaded = false;
  final List<int> _pathTrace = [];
  final List<int> _pathTraceHopWidths = [];
  final List<Contact> _pathTraceContacts = [];
  final List<LatLng> _points = [];
  final List<Polyline> _polylines = [];
  bool _mapControlsCollapsed = true;
  bool _statsExpanded = false;
  bool _showNodeLabels = true;
  double _zoom = 10.0;
  String? _selectedKey;
  LatLng? _selectedGuessPos;
  _Freshness _freshness = _Freshness.all;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';
  bool _wardrivePanelCollapsed = false;
  List<_GuessedLocation> _cachedGuessedLocations = [];
  String _guessedLocationsCacheKey = '';
  int? _sharedMarkersCacheSignature;
  Locale? _sharedMarkersCacheLocale;
  List<_SharedMarker> _cachedSharedMarkers = const [];
  _NodeMarkersCacheKey? _nodeMarkersCacheKey;
  List<Marker> _cachedNodeMarkers = const [];
  WardriveService? _wardriveService;
  VoidCallback? _wardriveServiceListener;
  PageRoute<dynamic>? _observedRoute;
  bool _isCurrentRouteActive = false;
  bool _wardriveScreenWakelockActive = false;
  DateTime? _wardriveDiscoveryRetryAt;
  DateTime? _lastFollowedWardriveLocationAt;
  // Non-null means the map is showing responders for a tapped coverage block
  // instead of the latest live discovery request.
  String? _selectedWardriveCoverageHash;
  int? _selectedWardriveCoveragePrecision;
  final Set<String> _wardriveCoverageRepeaterKeys = {};

  @override
  void initState() {
    super.initState();
    _loadRemovedMarkers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<MeshCoreConnector>().getChannels();
        if (widget.highlightPosition != null) {
          _mapController.move(widget.highlightPosition!, widget.highlightZoom);
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && _observedRoute != route) {
      if (_observedRoute != null) {
        appRouteObserver.unsubscribe(this);
      }
      _observedRoute = route;
      _isCurrentRouteActive = route.isCurrent;
      appRouteObserver.subscribe(this, route);
    }
    final wardriveService = context.read<WardriveService>();
    if (_wardriveService != wardriveService) {
      if (_wardriveServiceListener != null) {
        _wardriveService?.removeListener(_wardriveServiceListener!);
      }
      _wardriveService = wardriveService;
      _wardriveServiceListener = () {
        _syncWardriveScreenWakelock();
        _syncWardriveFollowMe();
        if (mounted) {
          setState(() {});
        }
      };
      wardriveService.addListener(_wardriveServiceListener!);
    }
    _syncWardriveScreenWakelock();
    _syncWardriveFollowMe();
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _searchController.dispose();
    _searchFocus.dispose();
    _disableWardriveScreenWakelock();
    if (_wardriveServiceListener != null) {
      _wardriveService?.removeListener(_wardriveServiceListener!);
    }
    _wardriveService?.clearMapState();
    super.dispose();
  }

  _NodeAge _ageOf(Contact contact) {
    final d = DateTime.now().difference(contact.lastSeen);
    if (d.inMinutes <= 60) return _NodeAge.online;
    if (d.inHours <= 24) return _NodeAge.recent;
    return _NodeAge.stale;
  }

  void _selectNode(Contact contact, {LatLng? guessedPosition}) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedKey = contact.publicKeyHex;
      _selectedGuessPos = guessedPosition;
      _searchQuery = '';
      _searchController.clear();
      _searchFocus.unfocus();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedKey = null;
      _selectedGuessPos = null;
    });
  }

  @override
  void didPush() {
    _isCurrentRouteActive = true;
    _syncWardriveScreenWakelock();
    _syncWardriveFollowMe();
  }

  @override
  void didPopNext() {
    _isCurrentRouteActive = true;
    _syncWardriveScreenWakelock();
    _syncWardriveFollowMe();
  }

  @override
  void didPushNext() {
    _isCurrentRouteActive = false;
    _syncWardriveScreenWakelock();
  }

  @override
  void didPop() {
    _isCurrentRouteActive = false;
    _syncWardriveScreenWakelock();
  }

  void _syncWardriveScreenWakelock() {
    final wardrive = _wardriveService;
    final shouldEnable =
        _isCurrentRouteActive &&
        (wardrive?.isRunning ?? false) &&
        (wardrive?.screenWakelockEnabled ?? false);
    if (_wardriveScreenWakelockActive == shouldEnable) return;
    _wardriveScreenWakelockActive = shouldEnable;
    // Wakelock is screen-local: wardrive may keep running in background, but
    // the display is kept awake only while the map route is actually visible.
    final action = shouldEnable
        ? WakelockPlus.enable()
        : WakelockPlus.disable();
    unawaited(action.catchError((_) {}));
  }

  void _disableWardriveScreenWakelock() {
    if (!_wardriveScreenWakelockActive) return;
    _wardriveScreenWakelockActive = false;
    unawaited(WakelockPlus.disable().catchError((_) {}));
  }

  void _syncWardriveFollowMe({bool force = false}) {
    final wardrive = _wardriveService;
    final locationAt = wardrive?.lastPhoneLocationAt;
    final latitude = wardrive?.lastPhoneLatitude;
    final longitude = wardrive?.lastPhoneLongitude;
    if (!_isCurrentRouteActive ||
        !(wardrive?.isRunning ?? false) ||
        !(wardrive?.followMeEnabled ?? false) ||
        locationAt == null ||
        latitude == null ||
        longitude == null) {
      return;
    }
    if (!force && _lastFollowedWardriveLocationAt == locationAt) return;
    _lastFollowedWardriveLocationAt = locationAt;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentWardrive = _wardriveService;
      if (!_isCurrentRouteActive ||
          !(currentWardrive?.isRunning ?? false) ||
          !(currentWardrive?.followMeEnabled ?? false)) {
        return;
      }
      _moveMapToWardrivePoint(LatLng(latitude, longitude));
    });
  }

  Future<void> _loadRemovedMarkers() async {
    final ids = await _markerService.loadRemovedIds();
    if (!mounted) return;
    setState(() {
      _removedMarkerIds = ids;
      _removedMarkersLoaded = true;
    });
    // If this screen was opened to highlight a marker, and that marker
    // was previously removed, re-enable it now that we've loaded the saved
    // removed IDs.
    if (widget.highlightMarkerKey != null &&
        _removedMarkerIds.contains(widget.highlightMarkerKey)) {
      final updated = Set<String>.from(_removedMarkerIds);
      updated.remove(widget.highlightMarkerKey);
      if (!mounted) return;
      setState(() {
        _removedMarkerIds = updated;
      });
      await _markerService.saveRemovedIds(updated);
    }
  }

  bool _checkLocationPlausibility(double lat, double lon) {
    const double epsilon = 1e-6;
    return (lat.abs() > epsilon || lon.abs() > epsilon) &&
        lat >= -90.0 &&
        lat <= 90.0 &&
        lon >= -180.0 &&
        lon <= 180.0;
  }

  double _standardDeviation(List<double> values) {
    if (values.length <= 1) {
      return 0.0;
    }

    final mean = values.reduce((a, b) => a + b) / values.length;

    double sumSquaredDiff = 0.0;
    for (final value in values) {
      final diff = value - mean;
      sumSquaredDiff += diff * diff;
    }

    // Sample standard deviation (n-1) — most appropriate here
    final variance = sumSquaredDiff / (values.length - 1);

    return sqrt(variance);
  }

  // Calculate zoom level based on the spread of points (std deviation in degrees)
  double _zoomFromStdDev(double latStdDev, double lonStdDev) {
    final maxSpread = max(latStdDev, lonStdDev);
    if (maxSpread <= 0) return 13.0;
    // Approximate: each zoom level halves the visible area
    // ~0.01 degrees spread -> zoom 13, ~0.1 -> zoom 10, ~1.0 -> zoom 7
    final zoom = 10.0 - log(maxSpread * 10 + 1) / ln10 * 3;
    return zoom.clamp(4.0, 15.0);
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

  Widget _buildMapControls(
    BuildContext context, {
    required LatLng center,
    required double zoom,
    required MeshCoreConnector connector,
  }) {
    final hasSelf =
        connector.selfLatitude != null && connector.selfLongitude != null;
    final toggleIcon = _mapControlsCollapsed
        ? Icons.add_location_alt_outlined
        : Icons.remove;
    final expandedButtonCount = hasSelf ? 5 : 4;
    final expandedHeight = expandedButtonCount * 48.0;
    return Positioned(
      right: 12,
      bottom: 188,
      child: SizedBox(
        height: expandedHeight,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 4,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(toggleIcon),
                    tooltip: _mapControlsCollapsed
                        ? context.l10n.pathMap_expandPanel
                        : context.l10n.pathMap_collapsePanel,
                    onPressed: () {
                      setState(() {
                        _mapControlsCollapsed = !_mapControlsCollapsed;
                      });
                    },
                  ),
                  if (!_mapControlsCollapsed) ...[
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: context.l10n.map_zoomIn,
                      onPressed: () => _zoomMapBy(1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove),
                      tooltip: context.l10n.map_zoomOut,
                      onPressed: () => _zoomMapBy(-1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.crop_free),
                      tooltip: context.l10n.map_centerMap,
                      onPressed: () => _mapController.move(center, zoom),
                    ),
                    if (hasSelf)
                      IconButton(
                        icon: const Icon(Icons.my_location),
                        tooltip: context.l10n.map_setAsMyLocation,
                        onPressed: () => _mapController.move(
                          LatLng(
                            connector.selfLatitude!,
                            connector.selfLongitude!,
                          ),
                          max(_zoom, 14),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<MeshCoreConnector, AppSettingsService, PathHistoryService>(
      builder: (context, connector, settingsService, pathHistory, child) {
        if (!checkConnectionAndNavigate(connector)) {
          return const SizedBox.shrink();
        }

        final tileCache = context.read<MapTileCacheService>();
        final isDesktop = _isDesktopPlatform(defaultTargetPlatform);
        final settings = settingsService.settings;
        final connectorSnapshot = _MapConnectorSnapshot.fromConnector(
          connector,
        );
        final pathHistoryVersion = pathHistory.version;
        final allContacts = connector.allContacts;

        final contacts = settings.mapShowDiscoveryContacts
            ? allContacts
            : allContacts.where((c) => c.isActive).toList();

        final highlightPosition = widget.highlightPosition;
        final sharedMarkers = settings.mapShowMarkers
            ? _collectSharedMarkers(
                    connector,
                    connectorSnapshot.markerSignature,
                  )
                  .where(
                    (marker) =>
                        !_hiddenMarkerIds.contains(marker.id) &&
                        !_removedMarkerIds.contains(marker.id),
                  )
                  .toList()
            : <_SharedMarker>[];

        // Filter by time
        final now = DateTime.now();
        final filteredByTime = settings.mapTimeFilterHours == 0
            ? contacts
            : contacts.where((c) {
                final hoursSinceLastSeen = now.difference(c.lastSeen).inHours;
                return hoursSinceLastSeen <= settings.mapTimeFilterHours;
              }).toList();

        // Quick activity filter (search bar chips)
        final filteredByFreshness = switch (_freshness) {
          _Freshness.all => filteredByTime,
          _Freshness.online =>
            filteredByTime.where((c) => _ageOf(c) == _NodeAge.online).toList(),
          _Freshness.recent =>
            filteredByTime.where((c) => _ageOf(c) != _NodeAge.stale).toList(),
          _Freshness.stale =>
            filteredByTime.where((c) => _ageOf(c) == _NodeAge.stale).toList(),
        };

        // Filter by key prefix
        final keyPrefix = settings.mapKeyPrefix.trim();
        final filteredByKeyPrefix =
            (settings.mapKeyPrefixEnabled && keyPrefix.isNotEmpty)
            ? filteredByFreshness.where((c) {
                return c.publicKeyHex.toLowerCase().startsWith(
                  keyPrefix.toLowerCase(),
                );
              }).toList()
            : filteredByFreshness;

        // Filter by location
        final contactsWithLocation = filteredByKeyPrefix.where((c) {
          return c.hasLocation;
        }).toList();

        // All contacts with a known location — used as anchors regardless of
        // time/key-prefix filters so that repeaters are always available.
        final allContactsWithLocation = allContacts
            .where((c) => c.hasLocation)
            .toList();

        // Guessed markers represent the same node types as known-location
        // markers, so apply the node-type filters before estimating positions.
        final guessCandidates = _filterContactsBySettings(
          filteredByKeyPrefix,
          settings,
          noLocations: true,
        );

        // Compute guessed locations with caching
        final maxRangeKm = _estimateLoRaRangeKm(connector);
        final pathHashByteWidth = connector.pathHashByteWidth
            .clamp(1, 4)
            .toInt();
        final filteredKeys = guessCandidates
            .map((c) => '${c.publicKeyHex}:${c.path.join("-")}')
            .join(',');
        final anchorKeys = allContactsWithLocation
            .map(
              (c) =>
                  '${c.publicKeyHex}:${c.latitude}:${c.longitude}:${PathHelper.formatHopHex(c.path.isNotEmpty ? c.path.sublist(max(0, c.path.length - pathHashByteWidth)) : const [])}',
            )
            .join(',');
        final cacheKey =
            '$filteredKeys|$anchorKeys|$pathHistoryVersion:$pathHashByteWidth:${connector.currentFreqHz}:${connector.currentSf}:${connector.currentBwHz}:${connector.currentTxPower}:${settings.mapShowGuessedLocations}';
        if (cacheKey != _guessedLocationsCacheKey) {
          _guessedLocationsCacheKey = cacheKey;
          _cachedGuessedLocations = settings.mapShowGuessedLocations
              ? _computeGuessedLocations(
                  guessCandidates,
                  allContactsWithLocation,
                  pathHistory,
                  maxRangeKm,
                  pathHashByteWidth,
                )
              : [];
        }
        final guessedLocations = settings.mapShowGuessedLocations
            ? _cachedGuessedLocations
            : <_GuessedLocation>[];

        _polylines.clear();
        _polylines.addAll(
          _points.length > 1
              ? [
                  Polyline(
                    points: _points,
                    strokeWidth: 4,
                    color: MapPalette.selected,
                  ),
                ]
              : <Polyline>[],
        );

        // Collect polylines for shared markers' history with dashed lines
        final List<Polyline> sharedMarkerPolylines = [];
        for (final marker in sharedMarkers) {
          if (marker.history.isNotEmpty) {
            final points = List<LatLng>.from(marker.history);
            points.add(marker.position);
            sharedMarkerPolylines.add(
              Polyline(
                points: points,
                color: marker.isChannel
                    ? (marker.isPublicChannel
                          ? MapPalette.cluster
                          : MapPalette.router)
                    : MapPalette.shared,
                strokeWidth: 3,
              ),
            );
          }
        }
        final wardrive = _wardriveService!;
        final selectedCoverageSamples = _selectedWardriveCoverageSamples(
          wardrive,
        );
        final hasSelectedCoverage = selectedCoverageSamples.isNotEmpty;
        final wardriveAnsweredKeys = hasSelectedCoverage
            ? _wardriveResponderKeysFromSamples(selectedCoverageSamples)
            : wardrive.currentDiscoveryPublicKeys
                  .map((key) => key.toLowerCase())
                  .toSet();
        final wardriveHighlightActive =
            hasSelectedCoverage || wardrive.lastDiscoveryRequestAt != null;
        final selfDisplayPosition = _selfDisplayPosition(connector, wardrive);
        final wardriveDiscoveryPolylines = hasSelectedCoverage
            ? _buildWardriveCoveragePolylines(
                selectedCoverageSamples,
                contactsWithLocation,
              )
            : _buildWardriveDiscoveryPolylines(
                selfDisplayPosition,
                contactsWithLocation,
                wardriveAnsweredKeys,
                wardrive,
              );
        final wardriveCoveragePolygons = wardrive.hasMapState
            ? WardriveCoverageHelper.buildPolygons(
                wardrive.recentSamples,
                coveragePrecision: wardrive.coveragePrecision,
              )
            : const <Polygon>[];
        final repeaterCoverageSamples = _wardriveRepeaterCoverageSamples(
          wardrive,
        );
        final repeaterCoveragePolygons = repeaterCoverageSamples.isEmpty
            ? const <Polygon>[]
            : WardriveCoverageHelper.buildFixedColorPolygons(
                repeaterCoverageSamples,
                color: MapPalette.selected,
                coveragePrecision: wardrive.coveragePrecision,
              );
        final repeaterCoveragePolylines = repeaterCoverageSamples.isEmpty
            ? const <Polyline>[]
            : _buildWardriveRepeaterCoveragePolylines(
                repeaterCoverageSamples,
                contactsWithLocation,
              );

        // Calculate center and zoom of all nodes, or default to (0, 0)
        LatLng center = const LatLng(0, 0);
        double initialZoom = 10.0;
        final wardriveSamplePoints = wardrive.hasMapState
            ? wardrive.recentSamples
                  .map((sample) => LatLng(sample.latitude, sample.longitude))
                  .toList()
            : const <LatLng>[];
        final hasMapContent =
            contactsWithLocation.isNotEmpty ||
            sharedMarkers.isNotEmpty ||
            wardriveSamplePoints.isNotEmpty ||
            selfDisplayPosition != null ||
            _isSelectingPoi ||
            highlightPosition != null;
        if (contactsWithLocation.isNotEmpty ||
            sharedMarkers.isNotEmpty ||
            wardriveSamplePoints.isNotEmpty ||
            selfDisplayPosition != null) {
          final allPoints = <LatLng>[
            ...contactsWithLocation.map(
              (c) => LatLng(c.latitude!, c.longitude!),
            ),
            ...sharedMarkers.map((m) => m.position),
            ...wardriveSamplePoints,
            ?selfDisplayPosition,
          ];
          if (allPoints.length >= 3) {
            final latValues = allPoints.map((p) => p.latitude).toList();
            final lonValues = allPoints.map((p) => p.longitude).toList();

            final meanLat =
                latValues.reduce((a, b) => a + b) / latValues.length;
            final meanLon =
                lonValues.reduce((a, b) => a + b) / lonValues.length;
            final latStdDev = _standardDeviation(latValues);
            final lonStdDev = _standardDeviation(lonValues);

            final filteredPoints = allPoints
                .where(
                  (p) =>
                      (p.latitude - meanLat).abs() <= latStdDev * 2 &&
                      (p.longitude - meanLon).abs() <= lonStdDev * 2,
                )
                .toList();

            if (filteredPoints.isNotEmpty) {
              final filteredLatValues = filteredPoints
                  .map((p) => p.latitude)
                  .toList();
              final filteredLonValues = filteredPoints
                  .map((p) => p.longitude)
                  .toList();
              final avgLat = filteredLatValues.reduce((a, b) => a + b);
              final avgLon = filteredLonValues.reduce((a, b) => a + b);
              center = LatLng(
                avgLat / filteredPoints.length,
                avgLon / filteredPoints.length,
              );
              // Use std deviation of filtered points for zoom
              final filteredLatStdDev = _standardDeviation(filteredLatValues);
              final filteredLonStdDev = _standardDeviation(filteredLonValues);
              initialZoom = _zoomFromStdDev(
                filteredLatStdDev,
                filteredLonStdDev,
              );
            } else {
              center = LatLng(meanLat, meanLon);
              initialZoom = _zoomFromStdDev(latStdDev, lonStdDev);
            }
          } else {
            double avgLat = 0.0;
            double avgLon = 0.0;
            for (final point in allPoints) {
              avgLat += point.latitude;
              avgLon += point.longitude;
            }
            center = LatLng(
              avgLat / allPoints.length,
              avgLon / allPoints.length,
            );
            initialZoom = 12.0;
          }
        }
        if (highlightPosition != null) {
          center = highlightPosition;
          initialZoom = widget.highlightZoom;
        }

        // Re center map after removed markers have loaded
        if (!_hasInitializedMap && _removedMarkersLoaded) {
          _hasInitializedMap = true;
          _showNodeLabels = initialZoom >= _labelZoomThreshold;
          _zoom = initialZoom;
          if (hasMapContent) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _mapController.move(center, initialZoom);
              }
            });
          }
        }

        final allowBack = !connector.isConnected;

        final visibleContacts = _filterContactsBySettings(
          contactsWithLocation,
          settings,
        );
        Contact? selectedContact;
        if (_selectedKey != null) {
          for (final c in allContacts) {
            if (c.publicKeyHex == _selectedKey) {
              selectedContact = c;
              break;
            }
          }
        }
        final locatedTotal = allContacts.where((c) => c.hasLocation).length;
        final hiddenCount = max(0, locatedTotal - visibleContacts.length);
        final onlineCount = visibleContacts
            .where((c) => _ageOf(c) == _NodeAge.online)
            .length;
        final repeaterCount = visibleContacts
            .where((c) => c.type == advTypeRepeater)
            .length;

        return PopScope(
          canPop: allowBack,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: MapPalette.panelDark,
              foregroundColor: MapPalette.textPrimary,
              title: AppBarTitle(context.l10n.map_title),
              centerTitle: true,
              automaticallyImplyLeading: false,
              bottom: const SyncProgressAppBarBottom(),
              actions: [
                if (!_isBuildingPathTrace)
                  IconButton(
                    icon: const Icon(Icons.radar),
                    onPressed: selfDisplayPosition == null
                        ? null
                        : () => _startPath(selfDisplayPosition),
                    tooltip: context.l10n.contacts_pathTrace,
                  ),
                if (!_isBuildingPathTrace)
                  IconButton(
                    icon: const LosIcon(),
                    onPressed: () {
                      final candidates = <LineOfSightEndpoint>[];
                      if (selfDisplayPosition != null) {
                        candidates.add(
                          LineOfSightEndpoint(
                            label: context.l10n.pathTrace_you,
                            point: selfDisplayPosition,
                            color: Colors.teal,
                            icon: Icons.person_pin_circle,
                          ),
                        );
                      }
                      for (final c in contactsWithLocation) {
                        candidates.add(
                          LineOfSightEndpoint(
                            label: c.name,
                            point: LatLng(c.latitude!, c.longitude!),
                            color: _getNodeColor(c.type),
                            icon: _getNodeIcon(c.type),
                          ),
                        );
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LineOfSightMapScreen(
                            title: context.l10n.map_losScreenTitle,
                            candidates: candidates,
                          ),
                        ),
                      );
                    },
                    tooltip: context.l10n.map_lineOfSight,
                  ),
                PopupMenuButton(
                  itemBuilder: (context) => [
                    if (!_isBuildingPathTrace &&
                        connector.selfLatitude != null &&
                        connector.selfLongitude != null)
                      PopupMenuItem(
                        child: Row(
                          children: [
                            const Icon(Icons.radar),
                            const SizedBox(width: 8),
                            Text(context.l10n.contacts_pathTrace),
                          ],
                        ),
                        onTap: () => _startPath(
                          LatLng(
                            connector.selfLatitude!,
                            connector.selfLongitude!,
                          ),
                        ),
                      ),
                    if (!_isBuildingPathTrace)
                      PopupMenuItem(
                        child: Row(
                          children: [
                            const LosIcon(),
                            const SizedBox(width: 8),
                            Text(context.l10n.map_lineOfSight),
                          ],
                        ),
                        onTap: () {
                          final candidates = <LineOfSightEndpoint>[];
                          if (connector.selfLatitude != null &&
                              connector.selfLongitude != null) {
                            candidates.add(
                              LineOfSightEndpoint(
                                label: context.l10n.pathTrace_you,
                                point: LatLng(
                                  connector.selfLatitude!,
                                  connector.selfLongitude!,
                                ),
                                color: MapPalette.selected,
                                icon: Icons.person_pin_circle,
                              ),
                            );
                          }
                          for (final c in contactsWithLocation) {
                            candidates.add(
                              LineOfSightEndpoint(
                                label: c.name,
                                point: LatLng(c.latitude!, c.longitude!),
                                color: _getNodeColor(c.type),
                                icon: _getNodeIcon(c.type),
                              ),
                            );
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LineOfSightMapScreen(
                                title: context.l10n.map_losScreenTitle,
                                candidates: candidates,
                              ),
                            ),
                          );
                        },
                      ),
                    PopupMenuItem(
                      child: Row(
                        children: [
                          Icon(
                            Icons.logout,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Text(context.l10n.common_disconnect),
                        ],
                      ),
                      onTap: () => _disconnect(context, connector),
                    ),
                    PopupMenuItem(
                      child: Row(
                        children: [
                          const Icon(Icons.settings),
                          const SizedBox(width: 8),
                          Text(context.l10n.settings_title),
                        ],
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert),
                ),
              ],
            ),
            body: Stack(
              key: _mapBodyKey,
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: initialZoom,
                    minZoom: _mapMinZoom,
                    maxZoom: _mapMaxZoom,
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
                    onTap: (_, latLng) {
                      if (_isSelectingPoi) {
                        setState(() {
                          _isSelectingPoi = false;
                        });
                        _shareMarker(
                          context: context,
                          connector: connector,
                          position: latLng,
                          defaultLabel: context.l10n.map_pointOfInterest,
                          flags: 'poi',
                        );
                        return;
                      }

                      _selectWardriveCoverageAt(wardrive, latLng);
                    },
                    onSecondaryTap: (tapPosition, latLng) {
                      unawaited(
                        _showWardriveCoverageBlockMenu(
                          wardrive: wardrive,
                          point: latLng,
                          globalPosition: tapPosition.global,
                        ),
                      );
                    },
                    onLongPress: (tapPosition, latLng) {
                      if (_isSelectingPoi) {
                        setState(() {
                          _isSelectingPoi = false;
                        });
                        _shareMarker(
                          context: context,
                          connector: connector,
                          position: latLng,
                          defaultLabel: context.l10n.map_pointOfInterest,
                          flags: 'poi',
                        );
                        return;
                      }

                      unawaited(
                        _handleMapLongPress(
                          connector: connector,
                          wardrive: wardrive,
                          point: latLng,
                          globalPosition: tapPosition.global,
                        ),
                      );
                    },
                    onPositionChanged: (camera, hasGesture) {
                      // Track zoom in half-step buckets so cluster/marker
                      // detail levels update without rebuilding every frame.
                      final bucket = (camera.zoom * 2).roundToDouble() / 2;
                      final shouldShow = camera.zoom >= _labelZoomThreshold;
                      if ((bucket != _zoom || shouldShow != _showNodeLabels) &&
                          mounted) {
                        setState(() {
                          _zoom = bucket;
                          _showNodeLabels = shouldShow;
                        });
                      }
                    },
                  ),
                  children: [
                    ThemedMapTileLayer(tileCache: tileCache),
                    if (_polylines.isNotEmpty && _isBuildingPathTrace)
                      PolylineLayer(polylines: _polylines),
                    if (sharedMarkerPolylines.isNotEmpty)
                      PolylineLayer(polylines: sharedMarkerPolylines),
                    if (wardriveCoveragePolygons.isNotEmpty)
                      PolygonLayer(polygons: wardriveCoveragePolygons),
                    if (repeaterCoveragePolygons.isNotEmpty)
                      PolygonLayer(polygons: repeaterCoveragePolygons),
                    if (wardriveDiscoveryPolylines.isNotEmpty)
                      PolylineLayer(polylines: wardriveDiscoveryPolylines),
                    if (repeaterCoveragePolylines.isNotEmpty)
                      PolylineLayer(polylines: repeaterCoveragePolylines),
                    MarkerLayer(
                      markers: [
                        if (highlightPosition != null)
                          Marker(
                            point: highlightPosition,
                            width: 44,
                            height: 44,
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: MapPalette.batteryLow,
                                  border: Border.all(
                                    color: MapPalette.markerOutline,
                                    width: 3,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: MapPalette.markerShadow,
                                      blurRadius: 8,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.white,
                                  size: 25,
                                ),
                              ),
                            ),
                          ),
                        if (!settings.mapShowOverlaps &&
                            (_zoom >= _guessedZoomThreshold ||
                                _isBuildingPathTrace))
                          ..._buildGuessedMarker(
                            guessedLocations,
                            showLabels: _showNodeLabels,
                            wardriveHighlightActive: wardriveHighlightActive,
                            wardriveAnsweredKeys: wardriveAnsweredKeys,
                          ),
                        ..._buildNodeMarkersCached(
                          visibleContacts,
                          settings,
                          connectorSnapshot.contactsSignature,
                          connectorSnapshot.batterySignature,
                          _freshness,
                          settings.mapTimeFilterHours,
                          settings.mapKeyPrefixEnabled,
                          settings.mapKeyPrefix,
                          settings.mapShowDiscoveryContacts,
                          Object.hashAllUnordered(
                            settings.batteryChemistryByRepeaterId.entries.map(
                              (entry) => Object.hash(entry.key, entry.value),
                            ),
                          ),
                          showLabels: _showNodeLabels,
                          wardriveHighlightActive: wardriveHighlightActive,
                          wardriveAnsweredKeys: wardriveAnsweredKeys,
                        ),
                        ...sharedMarkers.map(_buildSharedMarker),
                        if (selfDisplayPosition != null)
                          Marker(
                            point: selfDisplayPosition,
                            width: 40,
                            height: 40,
                            child: IgnorePointer(
                              ignoring: true,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: MapPalette.panelDark,
                                  border: Border.all(
                                    color: MapPalette.markerOutline,
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    const BoxShadow(
                                      color: MapPalette.markerShadow,
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.person_pin_circle,
                                  color: MapPalette.selected,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        if (_showNodeLabels && selfDisplayPosition != null)
                          _buildNodeLabelMarker(
                            point: selfDisplayPosition,
                            label: context.l10n.pathTrace_you,
                          ),
                      ],
                    ),
                  ],
                ),
                if (!settings.hideMapZoomControls)
                  _buildMapControls(
                    context,
                    center: center,
                    zoom: initialZoom,
                    connector: connector,
                  ),
                if (!_isBuildingPathTrace && wardrive.hasMapState)
                  WardriveStatusPanel(
                    wardrive: wardrive,
                    panelKey: _wardrivePanelKey,
                    collapsed: _wardrivePanelCollapsed,
                    autoUploadEnabled:
                        _wardriveUploadService.isAutoUploadEnabledSync,
                    screenWakelockEnabled: wardrive.screenWakelockEnabled,
                    inBackgroundEnabled: wardrive.runInBackgroundEnabled,
                    continuousGpsEnabled: wardrive.continuousGpsEnabled,
                    followMeEnabled: wardrive.followMeEnabled,
                    repeaterNames: _wardriveUploadRepeaterNames(),
                    onToggleCollapsed: () {
                      setState(() {
                        _wardrivePanelCollapsed = !_wardrivePanelCollapsed;
                      });
                    },
                    onDataAction: (action) {
                      unawaited(_handleWardriveDataAction(action, wardrive));
                    },
                    onResultSelected: (result) =>
                        _focusWardriveResponder(connector, result),
                    onIntervalSubmitted: (value) =>
                        _updateWardriveAutoDiscoveryInterval(wardrive, value),
                    formatLastSeen: _formatLastSeen,
                  ),
                if (!_isBuildingPathTrace)
                  _buildTopOverlay(
                    context,
                    connector: connector,
                    settingsService: settingsService,
                    allContacts: allContacts,
                    guessedLocations: guessedLocations,
                    visibleCount:
                        visibleContacts.length +
                        ((settings.mapShowGuessedLocations &&
                                _zoom >= _guessedZoomThreshold)
                            ? guessedLocations.length
                            : 0),
                    onlineCount: onlineCount,
                    repeaterCount: repeaterCount,
                    hiddenCount: hiddenCount,
                    pinCount: sharedMarkers.length,
                  ),
                if (_isBuildingPathTrace) _buildPathTraceOverlay(),
                if (selectedContact != null && !_isBuildingPathTrace)
                  _buildSelectedNodeCard(context, selectedContact, connector),
              ],
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: QuickSwitchBar(
                selectedIndex: 2,
                onDestinationSelected: (index) =>
                    _handleQuickSwitch(index, context),
                contactsUnreadCount: connector.getTotalContactsUnreadCount(),
                channelsUnreadCount: connector.getTotalChannelsUnreadCount(),
                highContrast: true,
              ),
            ),
            floatingActionButton: AnimatedBuilder(
              animation: wardrive,
              builder: (context, _) => _buildMapActionButtons(
                context: context,
                connector: connector,
                settingsService: settingsService,
                wardrive: wardrive,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapActionButtons({
    required BuildContext context,
    required MeshCoreConnector connector,
    required AppSettingsService settingsService,
    required WardriveService wardrive,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'wardrive_toggle',
          onPressed: () => _openWardrivePanel(wardrive),
          tooltip: context.l10n.map_wardrive,
          child: const Icon(Icons.directions_car_filled),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.small(
          heroTag: 'wardrive_discovery',
          onPressed: connector.isConnected
              ? () => _sendWardriveDiscovery(wardrive)
              : null,
          tooltip: context.l10n.map_wardriveZeroHopDiscovery,
          child: wardrive.isSendingDiscovery
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.radar),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          onPressed: () => _showFilterDialog(context, settingsService),
          tooltip: context.l10n.map_filterNodes,
          child: const Icon(Icons.filter_list),
        ),
      ],
    );
  }

  void _openWardrivePanel(WardriveService wardrive) {
    setState(() {
      _wardrivePanelCollapsed = false;
    });
    wardrive.showMapState();
  }

  Future<void> _sendWardriveDiscovery(WardriveService wardrive) async {
    if (wardrive.isSendingDiscovery) return;

    final waitSeconds = _wardriveDiscoveryWaitSeconds();
    if (waitSeconds != null) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.map_wardriveDiscoveryWait(waitSeconds)),
      );
      return;
    }

    try {
      await wardrive.sendZeroHopDiscoveryRequest(
        startWardrive: wardrive.isRunning,
      );
      if (!mounted) return;
      setState(() {
        _wardriveDiscoveryRetryAt = DateTime.now().add(
          _wardriveDiscoveryRetryDelay,
        );
        _clearSelectedWardriveCoverage();
      });
    } catch (error) {
      debugPrint('[Wardrive] Discovery request failed: $error');
    }
  }

  int? _wardriveDiscoveryWaitSeconds() {
    final retryAt = _wardriveDiscoveryRetryAt;
    if (retryAt == null) return null;
    final remaining = retryAt.difference(DateTime.now());
    if (remaining.inMicroseconds <= 0) {
      _wardriveDiscoveryRetryAt = null;
      return null;
    }
    return (remaining.inMilliseconds / Duration.millisecondsPerSecond)
        .ceil()
        .clamp(1, _wardriveDiscoveryRetryDelay.inSeconds)
        .toInt();
  }

  void _updateWardriveAutoDiscoveryInterval(
    WardriveService wardrive,
    String value,
  ) {
    final seconds = int.tryParse(value);
    if (seconds == null) return;
    wardrive.setAutoDiscoveryIntervalSeconds(seconds);
  }

  Future<void> _handleWardriveDataAction(
    WardriveDataAction action,
    WardriveService wardrive,
  ) async {
    switch (action) {
      case WardriveDataAction.start:
        wardrive.start();
        break;
      case WardriveDataAction.stop:
        wardrive.stop();
        break;
      case WardriveDataAction.upload:
        await _uploadWardriveSamples(wardrive);
        break;
      case WardriveDataAction.uploadSites:
        await _manageWardriveUploadSites();
        break;
      case WardriveDataAction.autoUpload:
        await _toggleWardriveAutoUpload(wardrive);
        break;
      case WardriveDataAction.screenWakelock:
        await _toggleWardriveScreenWakelock(wardrive);
        break;
      case WardriveDataAction.inBackground:
        await _toggleWardriveInBackground(wardrive);
        break;
      case WardriveDataAction.continuousGps:
        await _toggleWardriveContinuousGps(wardrive);
        break;
      case WardriveDataAction.followMe:
        await _toggleWardriveFollowMe(wardrive);
        break;
      case WardriveDataAction.coverageResolution:
        await _setWardriveCoverageResolution(wardrive);
        break;
      case WardriveDataAction.exportSamples:
        await _exportWardriveSamples(wardrive);
        break;
      case WardriveDataAction.importSamples:
        await _showImportWardriveSamplesDialog(wardrive);
        break;
      case WardriveDataAction.clear:
        await _confirmClearWardriveSamples(wardrive);
        break;
    }
  }

  Future<void> _toggleWardriveAutoUpload(WardriveService wardrive) async {
    final enabled = !_wardriveUploadService.isAutoUploadEnabledSync;
    await _wardriveUploadService.setAutoUploadEnabled(enabled);
    if (enabled) {
      unawaited(wardrive.runAutoUpload());
    }
    if (!mounted) return;
    setState(() {});
    showDismissibleSnackBar(
      context,
      content: Text(
        enabled
            ? context.l10n.map_wardriveAutoUploadEnabled
            : context.l10n.map_wardriveAutoUploadDisabled,
      ),
    );
  }

  Future<void> _toggleWardriveScreenWakelock(WardriveService wardrive) async {
    await wardrive.setScreenWakelockEnabled(!wardrive.screenWakelockEnabled);
    _syncWardriveScreenWakelock();
  }

  Future<void> _toggleWardriveInBackground(WardriveService wardrive) async {
    try {
      await wardrive.setRunInBackgroundEnabled(
        !wardrive.runInBackgroundEnabled,
      );
    } catch (error) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(error.toString()),
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _toggleWardriveContinuousGps(WardriveService wardrive) async {
    await wardrive.setContinuousGpsEnabled(!wardrive.continuousGpsEnabled);
  }

  Future<void> _toggleWardriveFollowMe(WardriveService wardrive) async {
    await wardrive.setFollowMeEnabled(!wardrive.followMeEnabled);
    _syncWardriveFollowMe(force: wardrive.followMeEnabled);
  }

  Future<void> _setWardriveCoverageResolution(WardriveService wardrive) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.map_wardriveCoverageResolution),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.map_wardriveCoverageResolutionPrompt),
            const SizedBox(height: 16),
            for (final option in _wardriveCoverageResolutionOptions())
              ListTile(
                title: Text(option.title),
                subtitle: Text(option.subtitle),
                trailing: option.precision == wardrive.coveragePrecision
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(dialogContext).pop(option.precision),
              ),
          ],
        ),
      ),
    );

    if (selected == null) return;
    await wardrive.setCoveragePrecision(selected);
    if (!mounted) return;
    setState(_clearSelectedWardriveCoverage);
  }

  List<_WardriveCoverageResolutionOption> _wardriveCoverageResolutionOptions() {
    return [
      _WardriveCoverageResolutionOption(
        precision: 4,
        title: context.l10n.map_wardriveCoverageRegional,
        subtitle: context.l10n.map_wardriveCoverageRegionalSubtitle,
      ),
      _WardriveCoverageResolutionOption(
        precision: 5,
        title: context.l10n.map_wardriveCoverageCity,
        subtitle: context.l10n.map_wardriveCoverageCitySubtitle,
      ),
      _WardriveCoverageResolutionOption(
        precision: 6,
        title: context.l10n.map_wardriveCoverageNeighborhood,
        subtitle: context.l10n.map_wardriveCoverageNeighborhoodSubtitle,
      ),
      _WardriveCoverageResolutionOption(
        precision: 7,
        title: context.l10n.map_wardriveCoverageStreet,
        subtitle: context.l10n.map_wardriveCoverageStreetSubtitle,
      ),
      _WardriveCoverageResolutionOption(
        precision: 8,
        title: context.l10n.map_wardriveCoverageBuilding,
        subtitle: context.l10n.map_wardriveCoverageBuildingSubtitle,
      ),
    ];
  }

  Future<void> _uploadWardriveSamples(
    WardriveService wardrive, {
    bool includeUploaded = false,
  }) async {
    if (wardrive.savedSamplesCount == 0) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.map_wardriveNoSamplesToUpload),
      );
      return;
    }

    var currentSite = '';
    var currentBatch = 0;
    var totalBatches = 0;
    WardriveUploadProgress? uploadProgress;
    WardriveUploadProgress effectiveUploadProgress() {
      return uploadProgress ??
          WardriveUploadProgress(
            siteName: currentSite,
            currentBatch: currentBatch,
            totalBatches: totalBatches,
            phase: WardriveUploadStatusPhase.waitingForConnection,
            sentSamples: 0,
            totalSamples: wardrive.savedSamplesCount,
          );
    }

    var uploadDialogOpen = true;
    StateSetter? setUploadState;
    final cancelToken = WardriveUploadCancelToken();
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    void closeUploadDialog() {
      if (!uploadDialogOpen) return;
      uploadDialogOpen = false;
      rootNavigator.pop();
    }

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) {
            setUploadState = setState;
            final progress = effectiveUploadProgress();
            return AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    currentSite.isEmpty
                        ? context.l10n.map_wardriveUploadingSamples
                        : context.l10n.map_wardriveUploadingTo(currentSite),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (progress.totalBatches > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        context.l10n.map_wardriveUploadBatch(
                          progress.currentBatch,
                          progress.totalBatches,
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      children: [
                        Text(
                          context.l10n.map_wardriveUploadSamplesProgress(
                            progress.sentSamples,
                            progress.totalSamples,
                          ),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatWardriveUploadProgress(context, progress),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    cancelToken.cancel();
                    closeUploadDialog();
                  },
                  child: Text(context.l10n.common_cancel),
                ),
              ],
            );
          },
        ),
      ).whenComplete(() {
        uploadDialogOpen = false;
        setUploadState = null;
      }),
    );

    try {
      final results = await _wardriveUploadService.uploadToSelectedSites(
        repeaterNames: _wardriveUploadRepeaterNames(),
        cancelToken: cancelToken,
        includeUploaded: includeUploaded,
        onProgress: (siteName, current, total) {
          setUploadState?.call(() {
            currentSite = siteName;
            currentBatch = current;
            totalBatches = total;
          });
        },
        onUploadProgress: (progress) {
          setUploadState?.call(() {
            currentSite = progress.siteName;
            currentBatch = progress.currentBatch;
            totalBatches = progress.totalBatches;
            uploadProgress = progress;
          });
        },
      );

      if (!mounted) return;
      closeUploadDialog();
      final reuploadRequested = await _showWardriveUploadResults(results);
      if (reuploadRequested && mounted) {
        await _uploadWardriveSamples(wardrive, includeUploaded: true);
      }
    } on WardriveUploadCancelledException {
      if (!mounted) return;
      closeUploadDialog();
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.map_wardriveUploadCancelled),
      );
    } catch (error) {
      if (!mounted) return;
      closeUploadDialog();
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.map_wardriveUploadFailed(error.toString())),
        backgroundColor: Colors.red,
      );
    }
  }

  String _formatWardriveUploadProgress(
    BuildContext context,
    WardriveUploadProgress progress,
  ) {
    switch (progress.phase) {
      case WardriveUploadStatusPhase.waitingForConnection:
        return context.l10n.map_wardriveUploadWaitingConnection;
      case WardriveUploadStatusPhase.uploading:
        return context.l10n.map_wardriveUploadConnectionEstablished;
      case WardriveUploadStatusPhase.processingServer:
        return context.l10n.map_wardriveUploadProcessingServer;
      case WardriveUploadStatusPhase.serverResponse:
        return context.l10n.map_wardriveUploadServerResponse(
          progress.statusCode ?? 200,
        );
      case WardriveUploadStatusPhase.timeoutTreatedAsSuccess:
        return context.l10n.map_wardriveUploadTimeoutTreatedAsSuccess;
      case WardriveUploadStatusPhase.serverError:
        return context.l10n.map_wardriveUploadServerError(
          progress.statusCode ?? 0,
        );
      case WardriveUploadStatusPhase.requestError:
        return context.l10n.map_wardriveUploadRequestError(
          progress.error ?? '',
        );
    }
  }

  Future<bool> _showWardriveUploadResults(
    Map<String, WardriveUploadResult> results,
  ) async {
    final allSuccess = results.values.every((result) => result.success);
    final canReupload = _canReuploadWardriveResults(results);
    final reuploadRequested = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          allSuccess
              ? context.l10n.map_wardriveUploadComplete
              : context.l10n.map_wardriveUploadResults,
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: results.entries
                .map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      entry.value.success
                          ? Icons.check_circle
                          : Icons.error_outline,
                      color: entry.value.success ? Colors.green : Colors.red,
                    ),
                    title: Text(entry.key),
                    subtitle: Text(_formatWardriveUploadResult(entry.value)),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          if (canReupload)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.l10n.map_wardriveReUpload),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.common_ok),
          ),
        ],
      ),
    );
    return reuploadRequested ?? false;
  }

  bool _canReuploadWardriveResults(Map<String, WardriveUploadResult> results) {
    return results.isNotEmpty &&
        results.values.every(
          (result) =>
              result.success &&
              result.uploadedCount == null &&
              result.noNewSamples,
        );
  }

  String _formatWardriveUploadResult(WardriveUploadResult result) {
    if (!result.success) return result.message;
    if (result.noNewSamples) return context.l10n.map_wardriveSamplesNoNew;
    final count = result.uploadedCount;
    if (count == null) return result.message;
    return context.l10n.map_wardriveSamplesUploaded(count);
  }

  Future<void> _manageWardriveUploadSites() async {
    final sites = List<WardriveUploadSite>.from(
      await _wardriveUploadService.loadSites(),
    );
    final selectedNames = (await _wardriveUploadService.loadSelectedSiteNames())
        .toSet();

    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.map_wardriveManageUploadSites),
          content: SizedBox(
            width: 460,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.65,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.map_wardriveSelectUploadSites,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: sites.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              context.l10n.map_wardriveNoUploadSitesConfigured,
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: sites.length,
                            itemBuilder: (context, index) {
                              final site = sites[index];
                              final selected = selectedNames.contains(
                                site.name,
                              );
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).dividerColor.withValues(alpha: 0.45),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      10,
                                      6,
                                      6,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                site.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                site.url,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                [
                                                  '${context.l10n.map_wardriveUploadBatchSize}: ${site.uploadBatchSize}',
                                                  if (site
                                                      .treatTimeoutAsSuccess)
                                                    context
                                                        .l10n
                                                        .map_wardriveTreatTimeoutAsSuccess,
                                                ].join(' • '),
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  IconButton(
                                                    tooltip: context
                                                        .l10n
                                                        .common_edit,
                                                    icon: const Icon(
                                                      Icons.edit,
                                                      size: 20,
                                                    ),
                                                    onPressed: () async {
                                                      final edited =
                                                          await _showWardriveUploadSiteDialog(
                                                            site: site,
                                                            existingSites:
                                                                sites,
                                                          );
                                                      if (edited == null) {
                                                        return;
                                                      }
                                                      setDialogState(() {
                                                        sites[index] = edited;
                                                        if (selectedNames
                                                            .remove(
                                                              site.name,
                                                            )) {
                                                          selectedNames.add(
                                                            edited.name,
                                                          );
                                                        }
                                                      });
                                                    },
                                                  ),
                                                  IconButton(
                                                    tooltip: context
                                                        .l10n
                                                        .common_delete,
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                      size: 20,
                                                    ),
                                                    onPressed: () async {
                                                      final confirmed =
                                                          await _confirmDeleteWardriveUploadSite(
                                                            site,
                                                          );
                                                      if (confirmed != true) {
                                                        return;
                                                      }
                                                      setDialogState(() {
                                                        sites.removeAt(index);
                                                        selectedNames.remove(
                                                          site.name,
                                                        );
                                                      });
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        Checkbox(
                                          value: selected,
                                          onChanged: (value) {
                                            setDialogState(() {
                                              if (value == true) {
                                                selectedNames.add(site.name);
                                              } else {
                                                selectedNames.remove(site.name);
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final site = await _showWardriveUploadSiteDialog(
                  existingSites: sites,
                );
                if (site == null) return;
                setDialogState(() {
                  sites.add(site);
                  selectedNames.add(site.name);
                });
              },
              icon: const Icon(Icons.add),
              label: Text(context.l10n.map_wardriveAddSite),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.common_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.l10n.common_save),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    await _wardriveUploadService.saveSites(sites);
    await _wardriveUploadService.saveSelectedSiteNames(selectedNames.toList());
    if (!mounted) return;
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.map_wardriveUploadSitesUpdated),
    );
  }

  Future<WardriveUploadSite?> _showWardriveUploadSiteDialog({
    WardriveUploadSite? site,
    required List<WardriveUploadSite> existingSites,
  }) async {
    var nameValue = site?.name ?? '';
    var urlValue = site?.url ?? '';
    var batchSizeValue =
        (site?.uploadBatchSize ?? WardriveUploadService.defaultUploadBatchSize)
            .toString();
    var treatTimeoutAsSuccess = site?.treatTimeoutAsSuccess ?? false;
    final result = await showDialog<WardriveUploadSite>(
      context: context,
      builder: (dialogContext) {
        String? nameError;
        String? urlError;
        String? batchSizeError;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              site == null
                  ? context.l10n.map_wardriveAddUploadSite
                  : context.l10n.map_wardriveEditUploadSite,
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: nameValue,
                      onChanged: (value) => nameValue = value,
                      decoration: InputDecoration(
                        labelText: context.l10n.map_wardriveNameLabel,
                        errorText: nameError,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: urlValue,
                      onChanged: (value) => urlValue = value,
                      decoration: InputDecoration(
                        labelText: context.l10n.map_wardriveUrlLabel,
                        errorText: urlError,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: batchSizeValue,
                      onChanged: (value) => batchSizeValue = value,
                      decoration: InputDecoration(
                        labelText: context.l10n.map_wardriveUploadBatchSize,
                        errorText: batchSizeError,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: treatTimeoutAsSuccess,
                      onChanged: (value) {
                        setDialogState(() {
                          treatTimeoutAsSuccess = value ?? false;
                        });
                      },
                      title: Text(
                        context.l10n.map_wardriveTreatTimeoutAsSuccess,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(context.l10n.common_cancel),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameValue.trim();
                  final url = urlValue.trim();
                  final batchSize = int.tryParse(batchSizeValue);
                  final parsedUri = Uri.tryParse(url);
                  final duplicateName = existingSites.any(
                    (existing) =>
                        existing.name != site?.name &&
                        existing.name.toLowerCase() == name.toLowerCase(),
                  );
                  setDialogState(() {
                    nameError = name.isEmpty
                        ? context.l10n.map_wardriveNameRequired
                        : duplicateName
                        ? context.l10n.map_wardriveNameExists
                        : null;
                    urlError =
                        parsedUri == null ||
                            !parsedUri.hasScheme ||
                            !parsedUri.hasAuthority
                        ? context.l10n.map_wardriveValidUrlRequired
                        : null;
                    batchSizeError =
                        batchSize == null ||
                            batchSize <
                                WardriveUploadService.minUploadBatchSize ||
                            batchSize > WardriveUploadService.maxUploadBatchSize
                        ? context.l10n.map_wardriveUploadBatchSizeInvalid(
                            WardriveUploadService.minUploadBatchSize,
                            WardriveUploadService.maxUploadBatchSize,
                          )
                        : null;
                  });
                  if (nameError != null ||
                      urlError != null ||
                      batchSizeError != null) {
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    WardriveUploadSite(
                      name: name,
                      url: url,
                      treatTimeoutAsSuccess: treatTimeoutAsSuccess,
                      uploadBatchSize: batchSize!,
                    ),
                  );
                },
                child: Text(context.l10n.common_save),
              ),
            ],
          ),
        );
      },
    );
    return result;
  }

  Future<bool?> _confirmDeleteWardriveUploadSite(
    WardriveUploadSite site,
  ) async {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.map_wardriveDeleteSite),
        content: Text(context.l10n.map_wardriveDeleteSiteConfirm(site.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.common_delete),
          ),
        ],
      ),
    );
  }

  Map<String, String> _wardriveUploadRepeaterNames() {
    final names = <String, String>{};
    final contacts = context.read<MeshCoreConnector>().allContactsUnfiltered;
    for (final contact in contacts) {
      final key = contact.publicKeyHex.toUpperCase();
      if (key.isNotEmpty && contact.name.isNotEmpty) {
        names[key] = contact.name;
      }
    }
    return names;
  }

  Future<void> _exportWardriveSamples(WardriveService wardrive) async {
    if (wardrive.savedSamplesCount == 0) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.map_wardriveNoSamplesToExport),
      );
      return;
    }

    final json = wardrive.exportSamplesJson();
    try {
      final fileName = 'meshcore_wardrive_${_wardriveExportTimestamp()}.json';
      final shareText = context.l10n.map_wardriveExportShareText;
      await Clipboard.setData(ClipboardData(text: json));
      await SharePlus.instance.share(
        ShareParams(
          subject: shareText,
          text: shareText,
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(json)),
              mimeType: 'application/json',
              name: fileName,
            ),
          ],
        ),
      );
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.map_wardriveSamplesExported),
      );
    } catch (error) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.map_wardriveExportFailed(error.toString())),
        backgroundColor: Colors.red,
      );
    }
  }

  String _wardriveExportTimestamp() {
    return DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .replaceAll('T', '_')
        .replaceAll('Z', '');
  }

  Future<void> _showImportWardriveSamplesDialog(
    WardriveService wardrive,
  ) async {
    final clipboardData = await Clipboard.getData('text/plain');
    final clipboardText = clipboardData?.text;
    var importText = '';
    if (clipboardText != null &&
        (clipboardText.contains('meshcore_wardrive_data') ||
            clipboardText.contains('meshcore-open-wardrive-samples'))) {
      importText = clipboardText;
    }

    if (!mounted) return;

    final rawJson = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(context.l10n.map_wardriveImportSamples),
          content: SizedBox(
            width: 420,
            child: TextFormField(
              initialValue: importText,
              minLines: 6,
              maxLines: 10,
              onChanged: (value) => importText = value,
              decoration: InputDecoration(
                hintText: context.l10n.map_wardriveImportHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.l10n.common_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(importText),
              child: Text(context.l10n.map_wardriveImport),
            ),
          ],
        );
      },
    );

    if (!mounted || rawJson == null) return;
    try {
      final imported = await wardrive.importSamplesJson(rawJson);
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(
          imported == 0
              ? context.l10n.map_wardriveNoNewSamplesImported
              : context.l10n.map_wardriveSamplesImported(imported),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.map_wardriveImportFailed(error.toString())),
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _confirmClearWardriveSamples(WardriveService wardrive) async {
    if (wardrive.savedSamplesCount == 0) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.map_wardriveNoSamplesToClear),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.map_wardriveClearSamplesTitle),
        content: Text(
          context.l10n.map_wardriveClearSamplesConfirm(
            wardrive.savedSamplesCount,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.common_clear),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await wardrive.clearSamples();
    if (!mounted) return;
    setState(_clearSelectedWardriveCoverage);
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.map_wardriveSamplesCleared),
    );
  }

  List<_GuessedLocation> _computeGuessedLocations(
    List<Contact> allContacts,
    List<Contact> withLocation,
    PathHistoryService pathHistory,
    double? maxRangeKm,
    int pathHashByteWidth,
  ) {
    final result = <_GuessedLocation>[];
    final hopWidth = pathHashByteWidth.clamp(1, 4).toInt();
    final anchorsByPrefix = <String, List<Contact>>{};
    for (final repeater in withLocation) {
      if (repeater.type != advTypeRepeater) continue;
      if (repeater.publicKey.length < hopWidth) continue;
      final prefix = PathHelper.formatHopHex(
        repeater.publicKey.sublist(0, hopWidth),
      );
      anchorsByPrefix.putIfAbsent(prefix, () => []).add(repeater);
    }

    for (final contact in allContacts) {
      if (contact.hasLocation) continue;
      if (contact.lastSeen.isBefore(
        DateTime.now().subtract(const Duration(hours: 24)),
      )) {
        continue; // skip stale contacts
      }

      final anchorSet = <LatLng>{};

      // Collect the contact-side (last-hop) repeater from every known path.
      // path = [device-side hop, ..., contact-side hop]
      // Only the last hop chunk is actually within radio range of the contact.
      final pathSets = <List<int>>[
        contact.path.toList(),
        ...pathHistory
            .getRecentPaths(contact.publicKeyHex)
            .map((r) => r.pathBytes),
      ];
      for (final pathBytes in pathSets) {
        if (pathBytes.isEmpty) continue;
        final lastHop = pathBytes.sublist(max(0, pathBytes.length - hopWidth));
        if (lastHop.isEmpty) continue;

        final repeaters = anchorsByPrefix[PathHelper.formatHopHex(lastHop)];
        if (repeaters != null && repeaters.isNotEmpty) {
          final repeater = repeaters.first;
          anchorSet.add(LatLng(repeater.latitude!, repeater.longitude!));
        }
      }

      // Filter anchors that are geometrically inconsistent with radio range.
      // Two anchors more than 2 * maxRange apart cannot both be in direct radio
      // range of the same node, so isolated outliers are removed.
      final anchors = maxRangeKm != null && anchorSet.length > 1
          ? _filterConsistentAnchors(anchorSet.toList(), maxRangeKm)
          : anchorSet.toList();

      if (anchors.isEmpty) continue;

      final LatLng position;
      if (anchors.length == 1) {
        // Spread single-anchor guesses around the anchor so they remain visible.
        position = _offsetGuessedPosition(
          anchors[0],
          contact,
          radiusMeters: 330,
        );
        if (!_checkLocationPlausibility(
          position.latitude,
          position.longitude,
        )) {
          continue; // discard implausible guesses near (0, 0)
        }
      } else {
        double lat = 0, lon = 0, weight = 1.0;
        int counted = 0;
        for (final a in anchors) {
          if (counted == 0) {
            lat = a.latitude;
            lon = a.longitude;
          } else {
            lat += a.latitude * weight;
            lon += a.longitude * weight;
          }
          // weight subsequent anchors less to create a bias towards the first (if more than 2)
          weight = weight / 2;
          counted++;
        }
        position = _offsetGuessedPosition(
          LatLng(lat / anchors.length, lon / anchors.length),
          contact,
          radiusMeters: anchors.length >= 3 ? 80 : 120,
        );
        if (!_checkLocationPlausibility(
          position.latitude,
          position.longitude,
        )) {
          continue; // discard implausible guesses near (0, 0
        }
      }
      result.add(
        _GuessedLocation(
          contact: contact,
          position: position,
          highConfidence: anchors.length >= 2,
        ),
      );
    }

    return result;
  }

  LatLng _offsetGuessedPosition(
    LatLng anchor,
    Contact contact, {
    required double radiusMeters,
  }) {
    final seed = _guessSeed(contact.publicKey);
    final angle = ((seed & 0xFFFF) / 0x10000) * 2 * pi;
    final latOffsetDeg = (radiusMeters / 111320.0) * cos(angle);
    final lonScale = max(cos(anchor.latitude * pi / 180.0).abs(), 0.2);
    final lonOffsetDeg = (radiusMeters / (111320.0 * lonScale)) * sin(angle);
    return LatLng(
      anchor.latitude + latOffsetDeg,
      anchor.longitude + lonOffsetDeg,
    );
  }

  int _guessSeed(Uint8List publicKey) {
    var seed = 0x811C9DC5;
    for (final byte in publicKey) {
      seed ^= byte;
      seed = (seed * 0x01000193) & 0x7FFFFFFF;
    }
    return seed;
  }

  /// Estimates the free-space maximum LoRa range in km from the connected
  /// device's current radio parameters.  Returns null if parameters are unknown.
  double? _estimateLoRaRangeKm(MeshCoreConnector connector) {
    final freqHz = connector.currentFreqHz;
    final bwHz = connector.currentBwHz;
    final sf = connector.currentSf;
    final txPower = connector.currentTxPower;
    if (freqHz == null || bwHz == null || sf == null || txPower == null) {
      return null;
    }
    // LoRa receiver sensitivity = thermal noise + NF + required demod SNR
    const noiseFigureDb = 6.0;
    final thermalNoiseDbm = -174.0 + 10 * log(bwHz.toDouble()) / ln10;
    final sensitivityDbm =
        thermalNoiseDbm + noiseFigureDb + _sfToRequiredSnrDb(sf);
    // FSPL at max range equals link budget:
    //   FSPL = 20*log10(d_m) + 20*log10(f_hz) - 147.55
    final linkBudgetDb = txPower.toDouble() - sensitivityDbm;
    final exponent =
        (linkBudgetDb + 147.55 - 20 * log(freqHz.toDouble()) / ln10) / 20;
    return pow(10, exponent) / 1000;
  }

  double _sfToRequiredSnrDb(int sf) {
    switch (sf) {
      case 5:
        return -2.5;
      case 6:
        return -5.0;
      case 7:
        return -7.5;
      case 8:
        return -10.0;
      case 9:
        return -12.5;
      case 10:
        return -15.0;
      case 11:
        return -17.5;
      case 12:
        return -20.0;
      default:
        return -10.0;
    }
  }

  /// Removes anchors that have no neighbour within 2 * maxRangeKm.
  /// A node cannot be simultaneously in radio range of two points farther apart
  /// than twice the expected maximum range.
  List<LatLng> _filterConsistentAnchors(
    List<LatLng> anchors,
    double maxRangeKm,
  ) {
    const distance = Distance();
    final maxDistM = maxRangeKm * 2000;
    return anchors
        .where((a) => anchors.any((b) => b != a && distance(a, b) <= maxDistM))
        .toList();
  }

  List<Marker> _buildGuessedMarker(
    List<_GuessedLocation> guessed, {
    required bool showLabels,
    bool wardriveHighlightActive = false,
    Set<String> wardriveAnsweredKeys = const <String>{},
  }) {
    final markers = <Marker>[];
    final foregroundMarkers = <Marker>[];

    for (final guess in guessed) {
      if (guess.contact.type == advTypeChat && _isBuildingPathTrace) {
        continue;
      }

      final color = _getNodeColor(guess.contact.type);
      final opacity = _wardriveNodeOpacity(
        guess.contact,
        active: wardriveHighlightActive,
        answeredKeys: wardriveAnsweredKeys,
      );
      final marker = Marker(
        point: guess.position,
        width: 48,
        height: 48,
        child: GestureDetector(
          onLongPress: () => _isBuildingPathTrace
              ? _showNodeInfo(context, guess.contact)
              : null,
          onTap: () => _isBuildingPathTrace
              ? _addToPath(context, guess.contact, position: guess.position)
              : _showNodeInfo(
                  context,
                  guess.contact,
                  guessedPosition: guess.position,
                ),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withValues(
                alpha: (guess.highConfidence ? 0.55 : 0.30) * opacity,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: opacity),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3 * opacity),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.not_listed_location,
              color: Colors.white.withValues(alpha: opacity),
              size: 20,
            ),
          ),
        ),
      );

      final targetMarkers =
          _isWardriveAnswered(guess.contact, answeredKeys: wardriveAnsweredKeys)
          ? foregroundMarkers
          : markers;
      targetMarkers.add(marker);

      if (showLabels) {
        targetMarkers.add(
          _buildNodeLabelMarker(
            point: guess.position,
            label: guess.contact.name,
          ),
        );
      }
    }
    return [...markers, ...foregroundMarkers];
  }

  List<Contact> _filterContactsBySettings(
    List<Contact> contacts,
    dynamic settings, {
    bool noLocations = false,
  }) {
    List<Contact> filtered = [];
    bool addContact = false;

    for (final contact in contacts) {
      addContact = false;
      if (!contact.hasLocation && !noLocations) {
        continue;
      }

      // Apply node type filters. The overlaps toggle is purely a visual
      // highlight (applied in _buildNodeMarkers) and no longer affects which
      // nodes are shown.
      if (contact.type == advTypeRepeater &&
          (settings.mapShowRepeaters || _isBuildingPathTrace)) {
        addContact = true;
      }
      if (contact.type == advTypeChat &&
          (settings.mapShowChatNodes || _isBuildingPathTrace)) {
        addContact = true;
      }
      if (contact.type != advTypeChat &&
          contact.type != advTypeRepeater &&
          (settings.mapShowOtherNodes || _isBuildingPathTrace)) {
        addContact = true;
      }

      if (contact.type == advTypeChat && _isBuildingPathTrace) {
        addContact = false;
      }

      if (addContact) {
        filtered.add(contact);
      }
    }
    return filtered;
  }

  List<Marker> _buildNodeMarkersCached(
    List<Contact> contacts,
    AppSettings settings,
    int contactsSignature,
    int batterySignature,
    _Freshness freshness,
    double timeFilterHours,
    bool keyPrefixEnabled,
    String keyPrefix,
    bool showDiscoveryContacts,
    int batteryChemistrySignature, {
    required bool showLabels,
    bool wardriveHighlightActive = false,
    Set<String> wardriveAnsweredKeys = const <String>{},
  }) {
    final wardriveAnsweredSignature = wardriveHighlightActive
        ? Object.hashAllUnordered(wardriveAnsweredKeys)
        : 0;
    final visibleContactsSignature = Object.hashAll(
      contacts.map(
        (contact) =>
            Object.hash(_mapContactSignature(contact), _ageOf(contact)),
      ),
    );
    final key = _NodeMarkersCacheKey(
      contactsSignature: contactsSignature,
      visibleContactsSignature: visibleContactsSignature,
      batterySignature: batterySignature,
      freshness: freshness,
      timeFilterHours: timeFilterHours,
      keyPrefixEnabled: keyPrefixEnabled,
      keyPrefix: keyPrefix,
      showDiscoveryContacts: showDiscoveryContacts,
      batteryChemistrySignature: batteryChemistrySignature,
      showLabels: showLabels,
      selectedKey: _selectedKey,
      zoom: _zoom,
      overlapsMode: settings.mapShowOverlaps,
      showRepeaters: settings.mapShowRepeaters,
      showChatNodes: settings.mapShowChatNodes,
      showOtherNodes: settings.mapShowOtherNodes,
      isBuildingPathTrace: _isBuildingPathTrace,
      wardriveHighlightActive: wardriveHighlightActive,
      wardriveAnsweredSignature: wardriveAnsweredSignature,
    );
    if (key != _nodeMarkersCacheKey) {
      _nodeMarkersCacheKey = key;
      _cachedNodeMarkers = List.unmodifiable(
        _buildNodeMarkers(
          contacts,
          settings,
          showLabels: showLabels,
          wardriveHighlightActive: wardriveHighlightActive,
          wardriveAnsweredKeys: wardriveAnsweredKeys,
        ),
      );
    }
    return _cachedNodeMarkers;
  }

  List<Marker> _buildNodeMarkers(
    List<Contact> contacts,
    settings, {
    required bool showLabels,
    bool wardriveHighlightActive = false,
    Set<String> wardriveAnsweredKeys = const <String>{},
  }) {
    final markers = <Marker>[];
    final foregroundMarkers = <Marker>[];
    final filteredContacts = _filterContactsBySettings(contacts, settings);
    final overlapsMode = settings.mapShowOverlaps && !_isBuildingPathTrace;

    final overlapPrefixes = <String>{};
    if (overlapsMode) {
      final hopWidth = context
          .read<MeshCoreConnector>()
          .pathHashByteWidth
          .clamp(1, pubKeySize)
          .toInt();
      final counts = <String, int>{};
      for (final contact in filteredContacts) {
        if ((contact.type == advTypeRepeater || contact.type == advTypeRoom) &&
            contact.publicKey.length >= hopWidth) {
          final prefix = PathHelper.formatHopHex(
            contact.publicKey.sublist(0, hopWidth),
          );
          counts[prefix] = (counts[prefix] ?? 0) + 1;
        }
      }
      counts.forEach((prefix, count) {
        if (count > 1) overlapPrefixes.add(prefix);
      });
    }

    final overlapHopWidth = context
        .read<MeshCoreConnector>()
        .pathHashByteWidth
        .clamp(1, pubKeySize)
        .toInt();
    bool isOverlap(Contact contact) =>
        overlapsMode &&
        (contact.type == advTypeRepeater || contact.type == advTypeRoom) &&
        contact.publicKey.length >= overlapHopWidth &&
        overlapPrefixes.contains(
          PathHelper.formatHopHex(
            contact.publicKey.sublist(0, overlapHopWidth),
          ),
        );

    void addNode(Contact contact, {bool dot = false}) {
      final targetMarkers =
          _isWardriveAnswered(contact, answeredKeys: wardriveAnsweredKeys)
          ? foregroundMarkers
          : markers;
      final overlap = isOverlap(contact);
      targetMarkers.add(
        _nodeMarker(
          contact,
          overlapsMode: overlap,
          dot: dot,
          wardriveHighlightActive: wardriveHighlightActive,
          wardriveAnsweredKeys: wardriveAnsweredKeys,
        ),
      );
      if (showLabels) {
        targetMarkers.add(
          _buildNodeLabelMarker(
            point: LatLng(contact.latitude!, contact.longitude!),
            label: overlap
                ? "${contact.publicKeyHex.substring(0, 2)}:${contact.name}"
                : contact.name,
          ),
        );
      }
    }

    if (_zoom >= _clusterOffZoom ||
        overlapsMode ||
        _isBuildingPathTrace ||
        wardriveHighlightActive) {
      for (final contact in filteredContacts) {
        addNode(contact);
      }
    } else {
      // Grid clustering: bucket markers into roughly 64px screen cells at the
      // current zoom; cells with 2+ nodes render as a numbered cluster.
      final cellDeg = 360.0 / (256.0 * pow(2.0, _zoom)) * 64.0;
      final cells = <String, List<Contact>>{};
      for (final contact in filteredContacts) {
        final key =
            '${(contact.latitude! / cellDeg).floor()}:${(contact.longitude! / cellDeg).floor()}';
        (cells[key] ??= []).add(contact);
      }
      for (final cell in cells.values) {
        if (cell.length == 1) {
          addNode(cell.first, dot: true);
        } else {
          markers.add(_clusterMarker(cell));
        }
      }
    }

    return [...markers, ...foregroundMarkers];
  }

  double _wardriveNodeOpacity(
    Contact contact, {
    required bool active,
    required Set<String> answeredKeys,
  }) {
    if (!active) return 1.0;
    return _isWardriveAnswered(contact, answeredKeys: answeredKeys) ? 1.0 : 0.3;
  }

  bool _isWardriveAnswered(
    Contact contact, {
    required Set<String> answeredKeys,
  }) {
    return answeredKeys.any(
      (answeredKey) => _publicKeysMatch(contact.publicKeyHex, answeredKey),
    );
  }

  bool _publicKeysMatch(String first, String second) {
    final firstKey = first.toLowerCase();
    final secondKey = second.toLowerCase();
    if (firstKey == secondKey) return true;
    final shortest = min(firstKey.length, secondKey.length);
    if (shortest < 8) return false;
    return firstKey.startsWith(secondKey) || secondKey.startsWith(firstKey);
  }

  List<WardriveSample> _selectedWardriveCoverageSamples(
    WardriveService wardrive,
  ) {
    final selectedHash = _selectedWardriveCoverageHash;
    final selectedPrecision = _selectedWardriveCoveragePrecision;
    if (selectedHash == null ||
        selectedPrecision == null ||
        selectedPrecision != wardrive.coveragePrecision) {
      return const <WardriveSample>[];
    }

    return wardrive.recentSamples
        .where(
          (sample) =>
              WardriveCoverageHelper.coverageHashForSample(
                sample,
                precision: selectedPrecision,
              ) ==
              selectedHash,
        )
        .toList();
  }

  Set<String> _wardriveResponderKeysFromSamples(List<WardriveSample> samples) {
    return samples
        .where((sample) => sample.pingSuccess == true)
        .map(_wardriveResponderKeyFromSample)
        .where((key) => key.isNotEmpty)
        .map((key) => key.toLowerCase())
        .toSet();
  }

  String _wardriveResponderKeyFromSample(WardriveSample sample) {
    if (sample.publicKeyHex.isNotEmpty) return sample.publicKeyHex;
    return sample.path ?? '';
  }

  bool _isWardriveRepeaterCoverageVisible(Contact repeater) {
    return _wardriveCoverageRepeaterKeys.any(
      (key) => _publicKeysMatch(repeater.publicKeyHex, key),
    );
  }

  void _toggleWardriveRepeaterCoverage(
    Contact repeater,
    WardriveService wardrive,
  ) {
    final key = repeater.publicKeyHex.toLowerCase();
    var shouldShowWardrivePanel = false;
    setState(() {
      _clearSelectedWardriveCoverage();
      if (_isWardriveRepeaterCoverageVisible(repeater)) {
        _wardriveCoverageRepeaterKeys.removeWhere(
          (selected) => _publicKeysMatch(selected, key),
        );
      } else {
        _wardriveCoverageRepeaterKeys.add(key);
        _wardrivePanelCollapsed = true;
        shouldShowWardrivePanel = true;
      }
    });
    if (shouldShowWardrivePanel) {
      wardrive.showMapState();
    }
  }

  List<WardriveSample> _wardriveRepeaterCoverageSamples(
    WardriveService wardrive,
  ) {
    if (_wardriveCoverageRepeaterKeys.isEmpty) {
      return const <WardriveSample>[];
    }
    return wardrive.recentSamples.where((sample) {
      if (sample.pingSuccess != true) return false;
      final sampleKey = _wardriveResponderKeyFromSample(sample);
      if (sampleKey.isEmpty) return false;
      return _wardriveCoverageRepeaterKeys.any(
        (selectedKey) => _publicKeysMatch(sampleKey, selectedKey),
      );
    }).toList();
  }

  List<Polyline> _buildWardriveRepeaterCoveragePolylines(
    List<WardriveSample> samples,
    List<Contact> contacts,
  ) {
    final repeaters = contacts
        .where(
          (contact) =>
              contact.type == advTypeRepeater &&
              contact.hasLocation &&
              _isWardriveRepeaterCoverageVisible(contact),
        )
        .toList();
    if (repeaters.isEmpty) return const <Polyline>[];

    final polylines = <Polyline>[];
    for (final sample in samples) {
      final sampleKey = _wardriveResponderKeyFromSample(sample);
      if (sampleKey.isEmpty) continue;
      final repeater = repeaters
          .where((contact) => _publicKeysMatch(contact.publicKeyHex, sampleKey))
          .firstOrNull;
      if (repeater == null) continue;

      polylines.add(
        Polyline(
          points: [
            LatLng(repeater.latitude!, repeater.longitude!),
            LatLng(sample.latitude, sample.longitude),
          ],
          strokeWidth: 2.5,
          color: MapPalette.online.withValues(alpha: 0.9),
        ),
      );
    }
    return polylines;
  }

  void _selectWardriveCoverageAt(WardriveService wardrive, LatLng point) {
    final block = _wardriveCoverageBlockAt(wardrive, point);
    if (block == null) {
      if (_selectedWardriveCoverageHash != null) {
        setState(_clearSelectedWardriveCoverage);
      }
      return;
    }

    setState(() {
      _selectedWardriveCoverageHash = block.hash;
      _selectedWardriveCoveragePrecision = block.precision;
    });
  }

  Future<void> _handleMapLongPress({
    required MeshCoreConnector connector,
    required WardriveService wardrive,
    required LatLng point,
    required Offset globalPosition,
  }) async {
    final handled = await _showWardriveCoverageBlockMenu(
      wardrive: wardrive,
      point: point,
      globalPosition: globalPosition,
    );
    if (handled || !mounted) return;

    _showShareMarkerAtPositionSheet(
      context: context,
      connector: connector,
      position: point,
    );
  }

  Future<bool> _showWardriveCoverageBlockMenu({
    required WardriveService wardrive,
    required LatLng point,
    required Offset globalPosition,
  }) async {
    final block = _wardriveCoverageBlockAt(wardrive, point);
    if (block == null) return false;

    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return false;
    final selected = await showMenu<_WardriveCoverageBlockAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _WardriveCoverageBlockAction.delete,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(context.l10n.map_wardriveDeleteBlock),
            ],
          ),
        ),
      ],
    );
    if (!mounted || selected == null) return true;

    switch (selected) {
      case _WardriveCoverageBlockAction.delete:
        final removed = await wardrive.deleteSamplesForCoverageHash(
          coverageHash: block.hash,
          coveragePrecision: block.precision,
        );
        if (!mounted) return true;
        if (removed > 0) {
          setState(_clearSelectedWardriveCoverage);
        }
        return true;
    }
  }

  _WardriveCoverageBlock? _wardriveCoverageBlockAt(
    WardriveService wardrive,
    LatLng point,
  ) {
    if (!wardrive.hasMapState || wardrive.recentSamples.isEmpty) return null;

    final precision = wardrive.coveragePrecision;
    final hash = WardriveCoverageHelper.coverageHashForCoordinates(
      point.latitude,
      point.longitude,
      precision: precision,
    );
    final samples = wardrive.recentSamples.where(
      (sample) =>
          sample.pingSuccess != null &&
          WardriveCoverageHelper.coverageHashForSample(
                sample,
                precision: precision,
              ) ==
              hash,
    );
    if (samples.isEmpty) return null;
    return _WardriveCoverageBlock(hash: hash, precision: precision);
  }

  void _clearSelectedWardriveCoverage() {
    _selectedWardriveCoverageHash = null;
    _selectedWardriveCoveragePrecision = null;
  }

  void _focusWardriveResponder(
    MeshCoreConnector connector,
    WardriveDiscoveryResult result,
  ) {
    final contact = connector.allContactsUnfiltered
        .where(
          (contact) =>
              _publicKeysMatch(contact.publicKeyHex, result.publicKeyHex),
        )
        .firstOrNull;
    if (contact == null || !contact.hasLocation) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.map_wardriveRepNoLocation),
      );
      return;
    }

    _moveMapToWardrivePoint(LatLng(contact.latitude!, contact.longitude!));
  }

  void _moveMapToWardrivePoint(LatLng point) {
    final zoom = _mapController.camera.zoom;
    final offsetPixels = _wardriveVisibleAreaOffsetPixels();

    _mapController.move(
      _latLngWithVerticalPixelOffset(point, zoom, offsetPixels),
      zoom,
    );
  }

  double _wardriveVisibleAreaOffsetPixels() {
    final mapHeight = _heightForKey(_mapBodyKey);
    final panelHeight = _heightForKey(_wardrivePanelKey);
    if (mapHeight == null || panelHeight == null) return 0;
    final coveredBottom = (panelHeight + _wardrivePanelBottomInset)
        .clamp(0.0, mapHeight)
        .toDouble();
    // Center the selected point in the visible vertical area above the panel.
    return coveredBottom / 2;
  }

  double? _heightForKey(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.size.height;
    }
    return null;
  }

  LatLng _latLngWithVerticalPixelOffset(
    LatLng point,
    double zoom,
    double offsetPixels,
  ) {
    const tileSize = 256.0;
    final scale = tileSize * pow(2.0, zoom);
    final sinLat = sin(point.latitude * pi / 180).clamp(-0.9999, 0.9999);
    final pointY = (0.5 - log((1 + sinLat) / (1 - sinLat)) / (4 * pi)) * scale;

    // Move the map center south in Mercator pixels, so the selected responder
    // appears above center and not hidden behind the wardrive panel.
    final centerY = pointY + offsetPixels;
    final mercatorN = pi - 2 * pi * centerY / scale;
    final centerLat = 180 / pi * atan((exp(mercatorN) - exp(-mercatorN)) / 2);
    return LatLng(centerLat, point.longitude);
  }

  LatLng? _selfDisplayPosition(
    MeshCoreConnector connector,
    WardriveService wardrive,
  ) {
    final phoneLat = wardrive.lastPhoneLatitude;
    final phoneLon = wardrive.lastPhoneLongitude;
    if (wardrive.usesPhoneLocationForDisplay &&
        phoneLat != null &&
        phoneLon != null) {
      // Wardrive/manual discovery use phone GPS only as a local map position;
      // do not write it into the node advert or persisted node coordinates.
      return LatLng(phoneLat, phoneLon);
    }

    final selfLat = connector.selfLatitude;
    final selfLon = connector.selfLongitude;
    if (selfLat == null || selfLon == null) return null;
    return LatLng(selfLat, selfLon);
  }

  List<Polyline> _buildWardriveDiscoveryPolylines(
    LatLng? selfPoint,
    List<Contact> contacts,
    Set<String> answeredKeys,
    WardriveService wardrive,
  ) {
    if (selfPoint == null || answeredKeys.isEmpty) {
      return const <Polyline>[];
    }

    final polylines = <Polyline>[];
    for (final contact in contacts.where(
      (contact) =>
          contact.hasLocation &&
          _isWardriveAnswered(contact, answeredKeys: answeredKeys),
    )) {
      final contactPoint = LatLng(contact.latitude!, contact.longitude!);
      final isIgnored = wardrive.isRepeaterIgnored(contact.publicKeyHex);
      polylines.addAll(
        _buildWardriveResponderLine(
          selfPoint,
          contactPoint,
          isIgnored: isIgnored,
        ),
      );
    }
    return polylines;
  }

  List<Polyline> _buildWardriveResponderLine(
    LatLng from,
    LatLng to, {
    required bool isIgnored,
  }) {
    if (!isIgnored) {
      return [
        Polyline(
          points: [from, to],
          strokeWidth: 2.5,
          color: Colors.purpleAccent.withValues(alpha: 0.85),
        ),
      ];
    }

    final polylines = <Polyline>[];
    const segments = 16;
    for (var i = 0; i < segments; i += 2) {
      final start = i / segments;
      final end = (i + 1) / segments;
      polylines.add(
        Polyline(
          points: [
            _interpolateLatLng(from, to, start),
            _interpolateLatLng(from, to, end),
          ],
          strokeWidth: 2.5,
          color: Colors.redAccent.withValues(alpha: 0.9),
        ),
      );
    }
    return polylines;
  }

  LatLng _interpolateLatLng(LatLng from, LatLng to, double t) {
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  Marker _nodeMarker(
    Contact contact, {
    bool overlapsMode = false,
    bool dot = false,
    bool selected = false,
    bool wardriveHighlightActive = false,
    Set<String> wardriveAnsweredKeys = const <String>{},
  }) {
    final age = _ageOf(contact);
    final baseColor = overlapsMode
        ? MapPalette.batteryLow
        : _markerColor(contact);
    final stale = age == _NodeAge.stale;
    final online = age == _NodeAge.online;
    final opacity = _wardriveNodeOpacity(
      contact,
      active: wardriveHighlightActive,
      answeredKeys: wardriveAnsweredKeys,
    );
    final size = selected ? 46.0 : (dot ? 22.0 : 40.0);
    return Marker(
      point: LatLng(contact.latitude!, contact.longitude!),
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () =>
            _isBuildingPathTrace ? _showNodeInfo(context, contact) : null,
        onTap: () => _isBuildingPathTrace
            ? _addToPath(context, contact)
            : _showNodeInfo(context, contact),
        child: Center(
          child: dot && !selected
              ? Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: baseColor.withValues(alpha: opacity),
                    border: Border.all(
                      color: MapPalette.markerOutline.withValues(
                        alpha: opacity,
                      ),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: MapPalette.markerShadow.withValues(
                          alpha: opacity,
                        ),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                )
              : Opacity(
                  opacity: opacity,
                  child: _buildNodeMarkerWidget(
                    color: baseColor,
                    icon: _getNodeIcon(contact.type),
                    selected: selected,
                    stale: stale,
                    online: online,
                  ),
                ),
        ),
      ),
    );
  }

  Marker _clusterMarker(List<Contact> members) {
    final count = members.length;
    double lat = 0, lon = 0;
    var online = 0;
    for (final member in members) {
      lat += member.latitude!;
      lon += member.longitude!;
      if (_ageOf(member) == _NodeAge.online) online++;
    }
    final center = LatLng(lat / count, lon / count);
    final size = count >= 50
        ? 54.0
        : count >= 16
        ? 50.0
        : count >= 6
        ? 46.0
        : 42.0;
    return Marker(
      point: center,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _zoomToCluster(members),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MapPalette.cluster,
            border: Border.all(color: MapPalette.markerOutline, width: 3),
            boxShadow: const [
              BoxShadow(
                color: MapPalette.markerShadow,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$count',
                style: MeshTheme.mono(
                  fontSize: count >= 100 ? 11.5 : 13.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              if (online > 0)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MapPalette.online,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _zoomToCluster(List<Contact> members) {
    HapticFeedback.selectionClick();
    var minLat = double.infinity, maxLat = -double.infinity;
    var minLon = double.infinity, maxLon = -double.infinity;
    for (final member in members) {
      minLat = min(minLat, member.latitude!);
      maxLat = max(maxLat, member.latitude!);
      minLon = min(minLon, member.longitude!);
      maxLon = max(maxLon, member.longitude!);
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon)),
        padding: const EdgeInsets.all(72),
        maxZoom: 16,
      ),
    );
  }

  Widget _buildNodeMarkerWidget({
    required Color color,
    required IconData icon,
    bool selected = false,
    bool stale = false,
    bool online = false,
  }) {
    final statusColor = online
        ? MapPalette.online
        : stale
        ? MapPalette.offline
        : MapPalette.stale;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          width: selected ? 44 : 36,
          height: selected ? 44 : 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? MapPalette.selected : color,
            border: Border.all(
              color: MapPalette.markerOutline,
              width: selected ? 3 : 2.5,
            ),
            boxShadow: [
              const BoxShadow(
                color: MapPalette.markerShadow,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
              if (selected)
                BoxShadow(
                  color: MapPalette.selected.withValues(alpha: 0.75),
                  blurRadius: 14,
                  spreadRadius: 3,
                ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: selected ? 22 : 19),
        ),
        Positioned(
          right: selected ? -1 : -2,
          bottom: selected ? 0 : -2,
          child: Container(
            width: selected ? 13 : 12,
            height: selected ? 13 : 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
              border: Border.all(color: MapPalette.panelDark, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  List<Polyline> _buildWardriveCoveragePolylines(
    List<WardriveSample> samples,
    List<Contact> contacts,
  ) {
    final latestSampleByResponder = <String, WardriveSample>{};
    for (final sample in samples) {
      if (sample.pingSuccess != true) continue;
      final key = _wardriveResponderKeyFromSample(sample).toLowerCase();
      if (key.isEmpty) continue;
      final existing = latestSampleByResponder[key];
      if (existing == null || sample.timestamp.isAfter(existing.timestamp)) {
        latestSampleByResponder[key] = sample;
      }
    }

    final polylines = <Polyline>[];
    for (final entry in latestSampleByResponder.entries) {
      final contact = contacts
          .where(
            (contact) =>
                contact.hasLocation &&
                _publicKeysMatch(contact.publicKeyHex, entry.key),
          )
          .firstOrNull;
      if (contact == null) continue;

      final sample = entry.value;
      polylines.add(
        Polyline(
          points: [
            LatLng(sample.latitude, sample.longitude),
            LatLng(contact.latitude!, contact.longitude!),
          ],
          strokeWidth: 2.5,
          color: Colors.purpleAccent.withValues(alpha: 0.85),
        ),
      );
    }
    return polylines;
  }

  Marker _buildNodeLabelMarker({required LatLng point, required String label}) {
    return Marker(
      point: point,
      width: 120,
      height: 24,
      alignment: Alignment.topCenter,
      child: IgnorePointer(
        child: Transform.translate(
          offset: const Offset(0, -20),
          child: FittedBox(
            fit: BoxFit.contain,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: MapPalette.panelDark,
                borderRadius: BorderRadius.circular(MeshRadii.xs),
                border: Border.all(color: MapPalette.border),
                boxShadow: const [
                  BoxShadow(
                    color: MapPalette.markerShadow,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MeshTheme.mono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MapPalette.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getNodeColor(int type) {
    switch (type) {
      case advTypeChat:
        return MapPalette.selected;
      case advTypeRepeater:
        return MapPalette.repeater;
      case advTypeRoom:
        return MapPalette.router;
      case advTypeSensor:
        return MapPalette.sensor;
      default:
        return MapPalette.offline;
    }
  }

  Color _markerColor(Contact contact) {
    switch (contact.type) {
      case advTypeRepeater:
        return MapPalette.repeater;
      case advTypeRoom:
        return MapPalette.router;
      case advTypeSensor:
        return MapPalette.sensor;
      default:
        return _ageColor(_ageOf(contact));
    }
  }

  IconData _getNodeIcon(int type) {
    switch (type) {
      case advTypeChat:
        return Icons.person;
      case advTypeRepeater:
        return Icons.router;
      case advTypeRoom:
        return Icons.meeting_room;
      case advTypeSensor:
        return Icons.sensors;
      default:
        return Icons.device_unknown;
    }
  }

  Widget _buildLegendItem(IconData icon, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MapPalette.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _ageColor(_NodeAge age) {
    switch (age) {
      case _NodeAge.online:
        return MapPalette.online;
      case _NodeAge.recent:
        return MapPalette.stale;
      case _NodeAge.stale:
        return MapPalette.textMuted;
    }
  }

  String _ageLabel(_NodeAge age) {
    switch (age) {
      case _NodeAge.online:
        return context.l10n.map_online;
      case _NodeAge.recent:
        return context.l10n.map_recent;
      case _NodeAge.stale:
        return context.l10n.map_stale;
    }
  }

  Widget _buildTopOverlay(
    BuildContext context, {
    required MeshCoreConnector connector,
    required AppSettingsService settingsService,
    required List<Contact> allContacts,
    required List<_GuessedLocation> guessedLocations,
    required int visibleCount,
    required int onlineCount,
    required int repeaterCount,
    required int hiddenCount,
    required int pinCount,
  }) {
    final settings = settingsService.settings;
    final hasQuery = _searchQuery.trim().isNotEmpty;
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Material(
                  color: MapPalette.panelDark,
                  shape: StadiumBorder(
                    side: const BorderSide(color: MapPalette.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      hintText: context.l10n.map_searchHint,
                      hintStyle: const TextStyle(
                        color: MapPalette.textSecondary,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 20,
                        color: MapPalette.textPrimary,
                      ),
                      suffixIcon: hasQuery
                          ? IconButton(
                              color: MapPalette.textPrimary,
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                setState(() {
                                  _searchQuery = '';
                                  _searchController.clear();
                                });
                              },
                            )
                          : null,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 12,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      color: MapPalette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    cursorColor: MapPalette.selected,
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: MapPalette.panelDark,
                shape: StadiumBorder(
                  side: const BorderSide(color: MapPalette.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() => _statsExpanded = !_statsExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.hub,
                          size: 15,
                          color: MapPalette.selected,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$visibleCount',
                          style: MeshTheme.mono(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: MapPalette.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        AnimatedRotation(
                          turns: _statsExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(
                            Icons.expand_more,
                            size: 16,
                            color: MapPalette.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final chips = <Widget>[
                _mapChip(
                  label: context.l10n.time_allTime,
                  selected: _freshness == _Freshness.all,
                  onTap: () => setState(() => _freshness = _Freshness.all),
                ),
                _mapChip(
                  label: context.l10n.map_online,
                  selected: _freshness == _Freshness.online,
                  color: MapPalette.online,
                  onTap: () => setState(() => _freshness = _Freshness.online),
                ),
                _mapChip(
                  label: context.l10n.map_recent,
                  selected: _freshness == _Freshness.recent,
                  color: MapPalette.stale,
                  onTap: () => setState(() => _freshness = _Freshness.recent),
                ),
                _mapChip(
                  label: context.l10n.map_stale,
                  selected: _freshness == _Freshness.stale,
                  color: MapPalette.offline,
                  onTap: () => setState(() => _freshness = _Freshness.stale),
                ),
                _mapChip(
                  label: context.l10n.map_repeaters,
                  selected: settings.mapShowRepeaters,
                  color: MapPalette.repeater,
                  onTap: () => settingsService.setMapShowRepeaters(
                    !settings.mapShowRepeaters,
                  ),
                ),
                _mapChip(
                  label: context.l10n.map_chatNodes,
                  selected: settings.mapShowChatNodes,
                  color: MapPalette.selected,
                  onTap: () => settingsService.setMapShowChatNodes(
                    !settings.mapShowChatNodes,
                  ),
                ),
              ];

              if (constraints.maxWidth < 600) {
                return Wrap(runSpacing: 6, children: chips);
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: chips),
              );
            },
          ),
          if (hasQuery)
            _buildSearchResults(context, allContacts, guessedLocations)
          else if (_statsExpanded)
            Align(
              alignment: Alignment.centerRight,
              child: _buildStatsCard(
                context,
                settings: settings,
                visibleCount: visibleCount,
                onlineCount: onlineCount,
                repeaterCount: repeaterCount,
                hiddenCount: hiddenCount,
                pinCount: pinCount,
                guessedCount: guessedLocations.length,
              ),
            ),
        ],
      ),
    );
  }

  Widget _mapChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? color,
  }) {
    final accent = color ?? MapPalette.selected;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected
            ? Color.alphaBlend(
                accent.withValues(alpha: 0.34),
                MapPalette.panelDark,
              )
            : MapPalette.panelDark,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? accent : MapPalette.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(
                    Icons.check,
                    size: 13,
                    color: MapPalette.textPrimary,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? MapPalette.textPrimary
                        : MapPalette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(
    BuildContext context,
    List<Contact> allContacts,
    List<_GuessedLocation> guessedLocations,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    final matches =
        allContacts.where((c) => matchesContactQuery(c, query)).toList()
          ..sort((a, b) {
            if (a.hasLocation != b.hasLocation) {
              return a.hasLocation ? -1 : 1;
            }
            return b.lastSeen.compareTo(a.lastSeen);
          });
    final results = matches.take(8).toList();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: MapPalette.panelDark,
        borderRadius: BorderRadius.circular(MeshRadii.md),
        border: Border.all(color: MapPalette.border),
        boxShadow: const [
          BoxShadow(
            color: MapPalette.markerShadow,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: results.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.map_noResults,
                style: const TextStyle(
                  color: MapPalette.textSecondary,
                  fontSize: 13,
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: results.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: MapPalette.border),
              itemBuilder: (context, index) {
                final c = results[index];
                final color = _getNodeColor(c.type);
                return InkWell(
                  onTap: () => _onSearchResultTap(c, guessedLocations),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(_getNodeIcon(c.type), size: 18, color: color),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.name,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: MapPalette.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                c.publicKeyHex.substring(0, 12),
                                style: MeshTheme.mono(
                                  fontSize: 10.5,
                                  color: MapPalette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (c.hasLocation)
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: MapPalette.textSecondary,
                          )
                        else
                          Text(
                            context.l10n.map_noGps.toUpperCase(),
                            style: MeshTheme.accentLabel(
                              color: MapPalette.textMuted,
                              fontSize: 8.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _onSearchResultTap(
    Contact contact,
    List<_GuessedLocation> guessedLocations,
  ) {
    if (contact.hasLocation) {
      _selectNode(contact);
      _mapController.move(
        LatLng(contact.latitude!, contact.longitude!),
        max(_zoom, 14),
      );
      return;
    }
    _GuessedLocation? guess;
    for (final g in guessedLocations) {
      if (g.contact.publicKeyHex == contact.publicKeyHex) {
        guess = g;
        break;
      }
    }
    if (guess != null) {
      _selectNode(contact, guessedPosition: guess.position);
      _mapController.move(guess.position, max(_zoom, 13));
    } else {
      setState(() {
        _searchQuery = '';
        _searchController.clear();
        _searchFocus.unfocus();
      });
      _showNodeInfo(context, contact);
    }
  }

  Widget _buildStatsCard(
    BuildContext context, {
    required dynamic settings,
    required int visibleCount,
    required int onlineCount,
    required int repeaterCount,
    required int hiddenCount,
    required int pinCount,
    required int guessedCount,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      width: 230,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: MapPalette.panelDark,
        borderRadius: BorderRadius.circular(MeshRadii.md),
        border: Border.all(color: MapPalette.border),
        boxShadow: const [
          BoxShadow(
            color: MapPalette.markerShadow,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _statRow(context.l10n.map_visible, visibleCount, MapPalette.selected),
          _statRow(context.l10n.map_online, onlineCount, MapPalette.online),
          _statRow(
            context.l10n.map_repeaters,
            repeaterCount,
            MapPalette.repeater,
          ),
          _statRow(context.l10n.map_hidden, hiddenCount, MapPalette.offline),
          _statRow(context.l10n.map_markers, pinCount, MapPalette.shared),
          const Divider(height: 16, color: MapPalette.border),
          _buildLegendItem(
            Icons.person,
            context.l10n.map_chat,
            MapPalette.selected,
          ),
          _buildLegendItem(
            Icons.router,
            context.l10n.map_repeater,
            MapPalette.repeater,
          ),
          _buildLegendItem(
            Icons.meeting_room,
            context.l10n.map_room,
            MapPalette.router,
          ),
          _buildLegendItem(
            Icons.sensors,
            context.l10n.map_sensor,
            MapPalette.sensor,
          ),
          _buildLegendItem(
            Icons.flag,
            context.l10n.map_pinDm,
            MapPalette.shared,
          ),
          if (settings.mapShowGuessedLocations && guessedCount > 0)
            _buildLegendItem(
              Icons.not_listed_location,
              context.l10n.map_guessedLocation,
              MapPalette.textMuted,
            ),
        ],
      ),
    );
  }

  Widget _statRow(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: MapPalette.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$value',
            style: MeshTheme.mono(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: MapPalette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedNodeCard(
    BuildContext context,
    Contact contact,
    MeshCoreConnector connector,
  ) {
    final color = _markerColor(contact);
    final age = _ageOf(contact);
    final pos = contact.hasLocation
        ? LatLng(contact.latitude!, contact.longitude!)
        : _selectedGuessPos;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Transform.translate(
          offset: Offset(0, 32 * t),
          child: Opacity(opacity: 1 - t, child: child),
        ),
        child: MeshCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          color: MapPalette.panelDark,
          borderColor: MapPalette.border,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AvatarCircle(
                    name: contact.name,
                    size: 38,
                    color: color,
                    icon: _getNodeIcon(contact.type),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                contact.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: MapPalette.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (contact.isFavorite) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.star,
                                size: 14,
                                color: MapPalette.stale,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            StatusChip(
                              label: _ageLabel(age),
                              color: _ageColor(age),
                              fontSize: 9.5,
                              pulse: age == _NodeAge.online,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                contact.typeLabel(context.l10n),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: MapPalette.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (pos != null)
                    IconButton(
                      color: MapPalette.textPrimary,
                      icon: const Icon(Icons.center_focus_strong, size: 20),
                      tooltip: context.l10n.map_centerOnNode,
                      onPressed: () => _mapController.move(pos, max(_zoom, 15)),
                    ),
                  IconButton(
                    color: MapPalette.textPrimary,
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: _clearSelection,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _miniMeta(
                    context.l10n.map_lastSeen,
                    _formatLastSeen(contact.lastSeen),
                  ),
                  _miniMeta(
                    context.l10n.map_path,
                    contact.pathLabel(
                      context.l10n,
                      pathHashByteWidth: connector.pathHashByteWidth,
                    ),
                  ),
                  _miniMeta('ID', contact.publicKeyHex.substring(0, 12)),
                  if (pos != null)
                    _miniMeta(
                      context.l10n.map_location,
                      '${contact.hasLocation ? '' : '~'}${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._selectedNodeActions(context, contact, connector),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: MapPalette.selected,
                    ),
                    onPressed: () => _showNodeInfo(
                      context,
                      contact,
                      guessedPosition: contact.hasLocation
                          ? null
                          : _selectedGuessPos,
                    ),
                    child: Text(context.l10n.map_details),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniMeta(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: MeshTheme.accentLabel(
            color: MapPalette.textMuted,
            fontSize: 8,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: MeshTheme.mono(fontSize: 11.5, color: MapPalette.textPrimary),
        ),
      ],
    );
  }

  List<Widget> _selectedNodeActions(
    BuildContext context,
    Contact contact,
    MeshCoreConnector connector,
  ) {
    Widget action(String label, IconData icon, VoidCallback onPressed) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 12.5)),
        ),
      );
    }

    switch (contact.type) {
      case advTypeChat:
        return [
          action(context.l10n.contacts_openChat, Icons.chat_bubble_outline, () {
            if (!contact.isActive) {
              connector.importDiscoveredContact(contact);
            }
            final unread = connector.getUnreadCountForContactKey(
              contact.publicKeyHex,
            );
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ChatScreen(contact: contact, initialUnreadCount: unread),
              ),
            );
          }),
        ];
      case advTypeRepeater:
        final wardrive = context.read<WardriveService>();
        final coverageVisible = _isWardriveRepeaterCoverageVisible(contact);
        return [
          action(context.l10n.map_manageRepeater, Icons.cell_tower, () {
            if (!contact.isActive) {
              connector.importDiscoveredContact(contact);
            }
            _showRepeaterLogin(context, contact);
          }),
          action(
            coverageVisible
                ? context.l10n.map_wardriveHideRepeaterCoverage
                : context.l10n.map_wardriveShowRepeaterCoverage,
            coverageVisible
                ? Icons.layers_clear_outlined
                : Icons.layers_outlined,
            () => _toggleWardriveRepeaterCoverage(contact, wardrive),
          ),
        ];
      case advTypeRoom:
        return [
          action(context.l10n.map_joinRoom, Icons.meeting_room, () {
            if (!contact.isActive) {
              connector.importDiscoveredContact(contact);
            }
            _showRoomLogin(context, contact);
          }),
        ];
      default:
        return const [];
    }
  }

  List<_SharedMarker> _collectSharedMarkers(
    MeshCoreConnector connector,
    int markerSignature,
  ) {
    final locale = Localizations.localeOf(context);
    if (_sharedMarkersCacheSignature == markerSignature &&
        _sharedMarkersCacheLocale == locale) {
      return _cachedSharedMarkers;
    }

    // Build a _SharedMarker per message (history empty), grouped by dedupe key.
    // Afterwards pick the latest per key and fill its history from older ones.
    final updatesByKey = <String, List<_SharedMarker>>{};
    final selfName = connector.selfName ?? 'Me';

    void addUpdate(_SharedMarker update) {
      (updatesByKey[update.id] ??= <_SharedMarker>[]).add(update);
    }

    for (final contact in connector.contacts) {
      final messages = connector.getMessages(contact);
      for (final message in messages) {
        final payload = parseMarkerText(message.text);
        if (payload == null) continue;
        final fromName = message.isOutgoing ? selfName : contact.name;
        final key = buildSharedMarkerKey(
          sourceId: contact.publicKeyHex,
          label: payload.label,
          fromName: fromName,
          flags: payload.flags,
          isChannel: false,
        );
        addUpdate(
          _SharedMarker(
            id: key,
            position: payload.position,
            label: payload.label.isEmpty
                ? context.l10n.map_sharedPin
                : payload.label,
            flags: payload.flags,
            fromName: fromName,
            sourceLabel: contact.name,
            timestamp: message.timestamp,
            isChannel: false,
            isPublicChannel: false,
          ),
        );
      }
    }

    for (final channel in connector.channels.where((c) => !c.isEmpty)) {
      final isPublic = _isPublicChannel(channel);
      final messages = connector.getChannelMessages(channel);
      for (final message in messages) {
        final payload = parseMarkerText(message.text);
        if (payload == null) continue;
        final key = buildSharedMarkerKey(
          sourceId: 'channel:${channel.index}',
          label: payload.label,
          fromName: message.senderName,
          flags: payload.flags,
          isChannel: true,
        );
        addUpdate(
          _SharedMarker(
            id: key,
            position: payload.position,
            label: payload.label.isEmpty
                ? context.l10n.map_sharedPin
                : payload.label,
            flags: payload.flags,
            fromName: message.senderName,
            sourceLabel: channel.name.isEmpty
                ? 'Channel ${channel.index}'
                : channel.name,
            timestamp: message.timestamp,
            isChannel: true,
            isPublicChannel: isPublic,
          ),
        );
      }
    }

    final markers = <_SharedMarker>[];
    updatesByKey.forEach((_, updates) {
      updates.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final latest = updates.last;
      // History: older positions, drop consecutive duplicates at same position.
      final history = <LatLng>[];
      for (var i = 0; i < updates.length - 1; i++) {
        final p = updates[i].position;
        if (history.isEmpty ||
            history.last.latitude != p.latitude ||
            history.last.longitude != p.longitude) {
          history.add(p);
        }
      }
      markers.add(latest.copyWithHistory(history));
    });

    markers.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _sharedMarkersCacheSignature = markerSignature;
    _sharedMarkersCacheLocale = locale;
    _cachedSharedMarkers = List.unmodifiable(markers);
    return _cachedSharedMarkers;
  }

  Marker _buildSharedMarker(_SharedMarker marker) {
    final markerColor = marker.isChannel
        ? (marker.isPublicChannel ? MapPalette.cluster : MapPalette.router)
        : MapPalette.shared;
    return Marker(
      point: marker.position,
      width: 60,
      height: 60,
      child: GestureDetector(
        onTap: () async {
          if (_removedMarkerIds.contains(marker.id)) {
            setState(() {
              _removedMarkerIds.remove(marker.id);
            });
            await _markerService.saveRemovedIds(_removedMarkerIds);
          }
          _showMarkerInfo(marker);
        },
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: markerColor,
                border: Border.all(color: MapPalette.markerOutline, width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: MapPalette.markerShadow,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.flag, color: Colors.white, size: 19),
            ),
          ],
        ),
      ),
    );
  }

  void _showRepeaterLogin(BuildContext context, Contact repeater) {
    showDialog(
      context: context,
      builder: (context) => RepeaterLoginDialog(
        repeater: repeater,
        onLogin: (password, isAdmin) {
          // Navigate to repeater hub screen after successful login
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RepeaterHubScreen(
                repeater: repeater,
                password: password,
                isAdmin: isAdmin,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showRoomLogin(BuildContext context, Contact room) {
    showDialog(
      context: context,
      builder: (context) => RoomLoginDialog(
        room: room,
        // onLogin(password, isAdmin) isAdmin not used for room caht screen
        onLogin: (password, _) {
          final connector = context.read<MeshCoreConnector>();
          final unread = connector.getUnreadCountForContactKey(
            room.publicKeyHex,
          );
          connector.markContactRead(room.publicKeyHex);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ChatScreen(contact: room, initialUnreadCount: unread),
            ),
          );
        },
      ),
    );
  }

  void _showNodeInfo(
    BuildContext context,
    Contact contact, {
    LatLng? guessedPosition,
  }) {
    final connector = context.read<MeshCoreConnector>();
    final wardrive = context.read<WardriveService>();
    showMeshSheet(
      context,
      builder: (sheetContext) {
        final actions = <Widget>[];
        if (contact.type == advTypeChat) {
          actions.add(
            FilledButton(
              onPressed: () {
                if (!contact.isActive) {
                  connector.importDiscoveredContact(contact);
                }
                final unread = connector.getUnreadCountForContactKey(
                  contact.publicKeyHex,
                );
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      contact: contact,
                      initialUnreadCount: unread,
                    ),
                  ),
                );
              },
              child: Text(context.l10n.contacts_openChat),
            ),
          );
        }
        if (contact.type == advTypeRepeater) {
          final coverageVisible = _isWardriveRepeaterCoverageVisible(contact);
          actions.add(
            FilledButton(
              onPressed: () {
                if (!contact.isActive) {
                  connector.importDiscoveredContact(contact);
                }
                Navigator.pop(sheetContext);
                _showRepeaterLogin(context, contact);
              },
              child: Text(context.l10n.map_manageRepeater),
            ),
          );
          actions.add(
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _toggleWardriveRepeaterCoverage(contact, wardrive);
                },
                icon: Icon(
                  coverageVisible
                      ? Icons.layers_clear_outlined
                      : Icons.layers_outlined,
                  size: 16,
                ),
                label: Text(
                  coverageVisible
                      ? context.l10n.map_wardriveHideRepeaterCoverage
                      : context.l10n.map_wardriveShowRepeaterCoverage,
                ),
              ),
            ),
          );
        }
        if (contact.type == advTypeRoom) {
          actions.add(
            FilledButton(
              onPressed: () {
                if (!contact.isActive) {
                  connector.importDiscoveredContact(contact);
                }
                Navigator.pop(sheetContext);
                _showRoomLogin(context, contact);
              },
              child: Text(context.l10n.map_joinRoom),
            ),
          );
        }
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BottomSheetHeader(
                  title: contact.name,
                  subtitle: contact.typeLabel(context.l10n),
                  trailing: Icon(
                    _getNodeIcon(contact.type),
                    color: _getNodeColor(contact.type),
                    size: 20,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(
                        context.l10n.map_path,
                        contact.pathLabel(
                          context.l10n,
                          pathHashByteWidth: connector.pathHashByteWidth,
                        ),
                      ),
                      if (contact.hasLocation)
                        _buildInfoRow(
                          context.l10n.map_location,
                          '${contact.latitude!.toStringAsFixed(6)}, ${contact.longitude!.toStringAsFixed(6)}',
                        )
                      else if (guessedPosition != null)
                        _buildInfoRow(
                          context.l10n.map_estLocation,
                          '~${guessedPosition.latitude.toStringAsFixed(6)}, ${guessedPosition.longitude.toStringAsFixed(6)}',
                        ),
                      _buildInfoRow(
                        context.l10n.map_lastSeen,
                        _formatLastSeen(contact.lastSeen),
                      ),
                      _buildInfoRow(
                        context.l10n.map_publicKey,
                        contact.publicKeyHex,
                      ),
                      const SizedBox(height: 16),
                      ...actions,
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleQuickSwitch(int index, BuildContext context) {
    if (index == 2) return;
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

  Future<void> _disconnect(
    BuildContext context,
    MeshCoreConnector connector,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.common_disconnect),
        content: Text(context.l10n.map_disconnectConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.common_disconnect),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await connector.disconnect();
    }
  }

  void _showMarkerInfo(_SharedMarker marker) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          marker.label.isEmpty ? context.l10n.map_sharedPin : marker.label,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(context.l10n.map_from, marker.fromName),
            _buildInfoRow(context.l10n.map_source, marker.sourceLabel),
            _buildInfoRow(
              context.l10n.map_sharedAt,
              _formatLastSeen(marker.timestamp),
            ),
            _buildInfoRow(
              context.l10n.map_location,
              '${marker.position.latitude.toStringAsFixed(6)}, ${marker.position.longitude.toStringAsFixed(6)}',
            ),
            if (marker.flags.isNotEmpty)
              _buildInfoRow(context.l10n.map_flags, marker.flags),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _hiddenMarkerIds.add(marker.id);
              });
              Navigator.pop(dialogContext);
            },
            child: Text(context.l10n.common_hide),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              setState(() {
                _hiddenMarkerIds.add(marker.id);
                _removedMarkerIds.add(marker.id);
              });
              await _markerService.saveRemovedIds(_removedMarkerIds);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: Text(context.l10n.common_remove),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.common_close),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: MeshTheme.mono(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inSeconds < 60) {
      return context.l10n.time_justNow;
    } else if (difference.inMinutes < 60) {
      return context.l10n.time_minutesAgo(difference.inMinutes);
    } else if (difference.inHours < 24) {
      return context.l10n.time_hoursAgo(difference.inHours);
    } else {
      return context.l10n.time_daysAgo(difference.inDays);
    }
  }

  void _showShareMarkerAtPositionSheet({
    required BuildContext context,
    required MeshCoreConnector connector,
    required LatLng position,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.place),
              title: Text(context.l10n.map_shareMarkerHere),
              onTap: () {
                Navigator.pop(sheetContext);
                _shareMarker(
                  context: context,
                  connector: connector,
                  position: position,
                  defaultLabel: context.l10n.map_pointOfInterest,
                  flags: 'poi',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.my_location),
              title: Text(context.l10n.map_setAsMyLocation),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final successMsg = context.l10n.settings_locationUpdated;
                Navigator.pop(sheetContext);
                if (!connector.isConnected) return;
                await connector.setNodeLocation(
                  lat: position.latitude,
                  lon: position.longitude,
                );
                await connector.refreshDeviceInfo();
                if (!mounted) return;
                messenger.showSnackBar(SnackBar(content: Text(successMsg)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(context.l10n.common_cancel),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareMarker({
    required BuildContext context,
    required MeshCoreConnector connector,
    required LatLng position,
    required String defaultLabel,
    required String flags,
  }) async {
    if (!connector.isConnected) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.map_connectToShareMarkers),
      );
      return;
    }

    final label = await _promptForLabel(context, defaultLabel);
    if (label == null || !mounted) return;

    final markerText = _formatMarkerMessage(position, label, flags);
    if (!mounted) return;

    await _showRecipientSheet(
      // ignore: use_build_context_synchronously
      context: context,
      connector: connector,
      markerText: markerText,
    );
  }

  Future<String?> _promptForLabel(
    BuildContext context,
    String defaultLabel,
  ) async {
    final controller = TextEditingController(text: defaultLabel);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.map_pinLabel),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: context.l10n.map_label,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () {
              final label = controller.text.trim().replaceAll('|', '/');
              Navigator.pop(
                dialogContext,
                label.isEmpty ? defaultLabel : label,
              );
            },
            child: Text(context.l10n.common_continue),
          ),
        ],
      ),
    );
  }

  String _formatMarkerMessage(LatLng position, String label, String flags) {
    final lat = position.latitude.toStringAsFixed(6);
    final lon = position.longitude.toStringAsFixed(6);
    return 'm:$lat,$lon|$label|$flags';
  }

  Future<void> _showRecipientSheet({
    required BuildContext context,
    required MeshCoreConnector connector,
    required String markerText,
  }) async {
    if (!connector.isLoadingChannels && connector.channels.isEmpty) {
      connector.getChannels();
    }
    String query = '';

    await showModalBottomSheet(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Consumer<MeshCoreConnector>(
            builder: (consumerContext, liveConnector, child) {
              final allContacts = liveConnector.contacts
                  .where(
                    (contact) =>
                        contact.type != advTypeRepeater &&
                        contact.type != advTypeRoom,
                  )
                  .toList();
              return SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          context.l10n.map_sendToContact,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: TextField(
                          decoration: InputDecoration(
                            hintText:
                                context.l10n.contacts_searchContactsNoNumber,
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onChanged: (value) {
                            setSheetState(() {
                              query = value.toLowerCase();
                            });
                          },
                        ),
                      ),
                      ...allContacts
                          .where(
                            (contact) =>
                                query.isEmpty ||
                                matchesContactQuery(contact, query),
                          )
                          .map((contact) {
                            return ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(contact.name),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                liveConnector.sendMessage(contact, markerText);
                              },
                            );
                          }),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          context.l10n.map_sendToChannel,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (liveConnector.isLoadingChannels)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: LinearProgressIndicator(),
                        )
                      else if (liveConnector.channels
                          .where((c) => !c.isEmpty)
                          .isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(context.l10n.map_noChannelsAvailable),
                        )
                      else
                        ...liveConnector.channels.where((c) => !c.isEmpty).map((
                          channel,
                        ) {
                          final isPublic = _isPublicChannel(channel);
                          final label = channel.name.isEmpty
                              ? 'Channel ${channel.index}'
                              : channel.name;
                          return ListTile(
                            leading: Icon(
                              isPublic ? Icons.public : Icons.tag,
                              color: isPublic
                                  ? MapPalette.cluster
                                  : MapPalette.repeater,
                            ),
                            title: Text(label),
                            onTap: () async {
                              Navigator.pop(sheetContext);
                              final canSend = isPublic
                                  ? await _confirmPublicShare(context, label)
                                  : true;
                              if (canSend) {
                                liveConnector.sendChannelMessage(
                                  channel,
                                  markerText,
                                );
                              }
                            },
                          );
                        }),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  bool _isPublicChannel(Channel channel) {
    return channel.isPublicChannel;
  }

  Future<bool> _confirmPublicShare(
    BuildContext context,
    String channelLabel,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.map_publicLocationShare),
        content: Text(
          context.l10n.map_publicLocationShareConfirm(channelLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.common_share),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showFilterDialog(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    _showFilterSheet(context, settingsService);
  }

  void _showFilterSheet(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    showMeshSheet(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Consumer<AppSettingsService>(
            builder: (consumerContext, service, child) {
              final settings = service.settings;
              final scheme = Theme.of(sheetContext).colorScheme;

              Widget freshnessChip(_Freshness value, String label) {
                final selected = _freshness == value;
                final accent = switch (value) {
                  _Freshness.all => MapPalette.selected,
                  _Freshness.online => MapPalette.online,
                  _Freshness.recent => MapPalette.stale,
                  _Freshness.stale => MapPalette.offline,
                };
                return FilterChip(
                  label: Text(label),
                  selected: selected,
                  showCheckmark: true,
                  checkmarkColor: accent,
                  backgroundColor: scheme.surfaceContainerLow,
                  selectedColor: Color.alphaBlend(
                    accent.withValues(alpha: 0.22),
                    scheme.surfaceContainerHigh,
                  ),
                  side: BorderSide(
                    color: selected ? accent : scheme.outline,
                    width: selected ? 1.5 : 1,
                  ),
                  labelStyle: TextStyle(
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                  onSelected: (_) {
                    setSheetState(() {});
                    setState(() => _freshness = value);
                  },
                );
              }

              return SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BottomSheetHeader(
                          title: sheetContext.l10n.map_filterNodes,
                        ),
                        SectionHeader(sheetContext.l10n.map_activity),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              freshnessChip(
                                _Freshness.all,
                                sheetContext.l10n.time_allTime,
                              ),
                              freshnessChip(
                                _Freshness.online,
                                sheetContext.l10n.map_online,
                              ),
                              freshnessChip(
                                _Freshness.recent,
                                sheetContext.l10n.map_recent,
                              ),
                              freshnessChip(
                                _Freshness.stale,
                                sheetContext.l10n.map_stale,
                              ),
                            ],
                          ),
                        ),
                        SectionHeader(
                          sheetContext.l10n.map_lastSeenTime,
                          trailing: Text(
                            _getTimeFilterLabel(settings.mapTimeFilterHours),
                            style: MeshTheme.mono(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Slider(
                            value: _hoursToSliderValue(
                              settings.mapTimeFilterHours,
                            ),
                            min: 0,
                            max: 100,
                            divisions: 100,
                            onChanged: (value) {
                              final hours = _sliderValueToHours(value);
                              service.setMapTimeFilterHours(hours);
                            },
                          ),
                        ),
                        SectionHeader(sheetContext.l10n.map_nodeTypes),
                        SwitchListTile(
                          title: Text(sheetContext.l10n.map_chatNodes),
                          value: settings.mapShowChatNodes,
                          dense: true,
                          onChanged: (value) =>
                              service.setMapShowChatNodes(value),
                        ),
                        SwitchListTile(
                          title: Text(sheetContext.l10n.map_repeaters),
                          value: settings.mapShowRepeaters,
                          dense: true,
                          onChanged: (value) =>
                              service.setMapShowRepeaters(value),
                        ),
                        SwitchListTile(
                          title: Text(sheetContext.l10n.map_otherNodes),
                          value: settings.mapShowOtherNodes,
                          dense: true,
                          onChanged: (value) =>
                              service.setMapShowOtherNodes(value),
                        ),
                        SectionHeader(sheetContext.l10n.map_markers),
                        SwitchListTile(
                          title: Text(sheetContext.l10n.map_showSharedMarkers),
                          value: settings.mapShowMarkers,
                          dense: true,
                          onChanged: (value) =>
                              service.setMapShowMarkers(value),
                        ),
                        SwitchListTile(
                          title: Text(
                            sheetContext.l10n.map_showGuessedLocations,
                          ),
                          value: settings.mapShowGuessedLocations,
                          dense: true,
                          onChanged: (value) =>
                              service.setMapShowGuessedLocations(value),
                        ),
                        SwitchListTile(
                          title: Text(
                            sheetContext.l10n.map_showDiscoveryContacts,
                          ),
                          value: settings.mapShowDiscoveryContacts,
                          dense: true,
                          onChanged: (value) =>
                              service.setMapShowDiscoveryContacts(value),
                        ),
                        SwitchListTile(
                          title: Text(sheetContext.l10n.map_showOverlaps),
                          value: settings.mapShowOverlaps,
                          dense: true,
                          onChanged: (value) =>
                              service.setMapShowOverlaps(value),
                        ),
                        SectionHeader(sheetContext.l10n.map_keyPrefix),
                        SwitchListTile(
                          title: Text(sheetContext.l10n.map_filterByKeyPrefix),
                          value: settings.mapKeyPrefixEnabled,
                          dense: true,
                          onChanged: (value) =>
                              service.setMapKeyPrefixEnabled(value),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          child: TextFormField(
                            initialValue: settings.mapKeyPrefix,
                            enabled: settings.mapKeyPrefixEnabled,
                            decoration: InputDecoration(
                              labelText: sheetContext.l10n.map_publicKeyPrefix,
                              hintText:
                                  sheetContext.l10n.map_publicKeyPrefixHint,
                              isDense: true,
                            ),
                            style: MeshTheme.mono(fontSize: 13),
                            onChanged: (value) =>
                                service.setMapKeyPrefix(value),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Convert hours to slider value (0-100) with exponential scaling
  double _hoursToSliderValue(double hours) {
    if (hours == 0) return 100; // All time

    // Map hours exponentially
    // 0-24h: 0-40
    // 24h-7d: 40-60
    // 7d-30d: 60-80
    // 30d-6mo: 80-99
    // All time: 100

    if (hours <= 24) {
      return (hours / 24) * 40;
    } else if (hours <= 168) {
      // 7 days
      return 40 + ((hours - 24) / (168 - 24)) * 20;
    } else if (hours <= 720) {
      // 30 days
      return 60 + ((hours - 168) / (720 - 168)) * 20;
    } else if (hours <= 4380) {
      // 6 months
      return 80 + ((hours - 720) / (4380 - 720)) * 19;
    } else {
      return 100;
    }
  }

  // Convert slider value (0-100) to hours with exponential scaling
  double _sliderValueToHours(double value) {
    if (value >= 99.5) return 0; // All time

    if (value <= 40) {
      return (value / 40) * 24; // 0-24 hours
    } else if (value <= 60) {
      return 24 + ((value - 40) / 20) * (168 - 24); // 1-7 days
    } else if (value <= 80) {
      return 168 + ((value - 60) / 20) * (720 - 168); // 7-30 days
    } else {
      return 720 + ((value - 80) / 19) * (4380 - 720); // 30 days - 6 months
    }
  }

  String _getTimeFilterLabel(double hours) {
    if (hours == 0) return context.l10n.time_allTime;

    if (hours < 1) {
      return '${(hours * 60).round()} ${context.l10n.time_minutes}';
    } else if (hours < 24) {
      final h = hours.round();
      return '$h ${h == 1 ? context.l10n.time_hour : context.l10n.time_hours}';
    } else if (hours < 168) {
      final days = (hours / 24).round();
      return '$days ${days == 1 ? context.l10n.time_day : context.l10n.time_days}';
    } else if (hours < 720) {
      final weeks = (hours / 168).round();
      return '$weeks ${weeks == 1 ? context.l10n.time_week : context.l10n.time_weeks}';
    } else if (hours < 4380) {
      final months = (hours / 730).round();
      return '$months ${months == 1 ? context.l10n.time_month : context.l10n.time_months}';
    } else {
      return context.l10n.time_allTime;
    }
  }

  void _addToPath(BuildContext context, Contact contact, {LatLng? position}) {
    final connector = context.read<MeshCoreConnector>();
    final hopWidth = min(
      connector.pathHashByteWidth.clamp(1, pubKeySize),
      contact.publicKey.length,
    ).toInt();
    final hopPrefix = contact.publicKey.sublist(0, hopWidth);
    for (final existingHop in PathHelper.splitPathBytes(
      _pathTrace,
      connector.pathHashByteWidth,
    )) {
      if (listEquals(existingHop, hopPrefix)) {
        return;
      }
    }
    setState(() {
      _pathTrace.addAll(hopPrefix); // Add the hop-width pubkey prefix.
      _pathTraceHopWidths.add(hopWidth);
      _pathTraceContacts.add(
        contact.copyWith(
          latitude: position?.latitude ?? contact.latitude,
          longitude: position?.longitude ?? contact.longitude,
        ),
      ); // Add contact to path trace contacts
      _points.add(position ?? LatLng(contact.latitude!, contact.longitude!));
    });
  }

  void _startPath(LatLng position) {
    setState(() {
      _isBuildingPathTrace = true;
      _pathTrace.clear();
      _pathTraceHopWidths.clear();
      _pathTraceContacts.clear();
      _points.clear();
      _polylines.clear();
      _points.add(position);
    });
  }

  void _removePath() {
    setState(() {
      final recordedHopWidth = _pathTraceHopWidths.isNotEmpty
          ? _pathTraceHopWidths.removeLast()
          : context.read<MeshCoreConnector>().pathHashByteWidth.clamp(
              1,
              pubKeySize,
            );
      final hopByteCount = min(recordedHopWidth, _pathTrace.length).toInt();
      _pathTraceContacts.removeLast();
      // A path trace hop can be wider than one byte; remove the full hash prefix.
      _pathTrace.removeRange(
        _pathTrace.length - hopByteCount,
        _pathTrace.length,
      );
      _points.removeLast(); // Remove last point from points list
      _polylines.clear(); // Clear polylines
    });
  }

  void _openPathTraceResult({required bool flipPathAround}) {
    final hashW = context.read<MeshCoreConnector>().pathHashByteWidth;
    // Keep the path editor active behind the result screen, so returning from
    // the trace map restores the selected repeaters for quick adjustments.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PathTraceMapScreen(
          title: context.l10n.contacts_pathTrace,
          path: Uint8List.fromList(_pathTrace),
          flipPathAround: flipPathAround,
          pathHashByteWidth: hashW,
          pathContacts: _pathTraceContacts,
        ),
      ),
    );
  }

  Widget _buildPathTraceOverlay() {
    final l10n = context.l10n;
    final isImperial =
        context.read<AppSettingsService>().settings.unitSystem ==
        UnitSystem.imperial;
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MapPalette.panelDark,
          borderRadius: BorderRadius.circular(MeshRadii.md),
          border: Border.all(color: MapPalette.border),
          boxShadow: const [
            BoxShadow(
              color: MapPalette.markerShadow,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(MeshRadii.md),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.contacts_pathTrace,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (_pathTrace.isEmpty) const SizedBox(height: 8),
                if (_pathTrace.isEmpty)
                  Text(l10n.map_tapToAdd, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                if (_pathTrace.isNotEmpty)
                  Text(
                    '${l10n.path_currentPathLabel} ${formatDistance(getPathDistanceMeters(_points), isImperial: isImperial)}',
                    style: MeshTheme.mono(
                      fontSize: 12,
                      color: MapPalette.textSecondary,
                    ),
                  ),
                SelectableText(
                  PathHelper.splitPathBytes(
                    _pathTrace,
                    context.read<MeshCoreConnector>().pathHashByteWidth,
                  ).map(PathHelper.formatHopHex).join(','),
                  style: MeshTheme.mono(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: MapPalette.selected,
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 1,
                  runSpacing: 1,
                  children: [
                    if (_pathTrace.isNotEmpty)
                      IconButton(
                        onPressed: () =>
                            _openPathTraceResult(flipPathAround: false),
                        tooltip: l10n.map_runTrace,
                        icon: const Icon(Icons.arrow_forward_outlined),
                      ),
                    if (_pathTrace.isNotEmpty)
                      IconButton(
                        onPressed: () =>
                            _openPathTraceResult(flipPathAround: true),
                        tooltip: l10n.map_runTraceWithReturnPath,
                        icon: const Icon(Icons.replay),
                      ),
                    if (_pathTrace.isNotEmpty)
                      IconButton(
                        onPressed: _removePath,
                        tooltip: l10n.map_removeLast,
                        icon: const Icon(Icons.undo),
                      ),
                    if (_pathTrace.isEmpty)
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isBuildingPathTrace = false;
                            _pathTrace.clear();
                            _pathTraceHopWidths.clear();
                            _points.clear();
                            _polylines.clear();
                          });
                          showDismissibleSnackBar(
                            context,
                            content: Text(l10n.map_pathTraceCancelled),
                          );
                        },
                        tooltip: l10n.common_cancel,
                        icon: const Icon(Icons.close),
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
}

enum _NodeAge { online, recent, stale }

enum _Freshness { all, online, recent, stale }

int _bytesSignature(Iterable<int>? bytes) {
  if (bytes == null) return 0;
  return Object.hashAll(bytes);
}

int _mapContactSignature(Contact contact) {
  return Object.hash(
    contact.publicKeyHex,
    contact.name,
    contact.type,
    contact.flags,
    contact.pathLength,
    _bytesSignature(contact.path),
    contact.pathOverride,
    _bytesSignature(contact.pathOverrideBytes),
    contact.latitude,
    contact.longitude,
    contact.lastSeen.millisecondsSinceEpoch,
    contact.lastMessageAt.millisecondsSinceEpoch,
    contact.isActive,
    contact.wasPulled,
  );
}

class _MapConnectorSnapshot {
  final MeshCoreConnector connector;
  final int contactsSignature;
  final int markerSignature;
  final int batterySignature;
  final int uiSignature;

  const _MapConnectorSnapshot({
    required this.connector,
    required this.contactsSignature,
    required this.markerSignature,
    required this.batterySignature,
    required this.uiSignature,
  });

  factory _MapConnectorSnapshot.fromConnector(MeshCoreConnector connector) {
    final allContacts = connector.allContacts;
    final contactsSignature = Object.hashAll(
      allContacts.map(_mapContactSignature),
    );
    final batterySignature = Object.hashAll(
      allContacts
          .where((contact) => contact.type == advTypeRepeater)
          .map(
            (contact) => Object.hash(
              contact.publicKeyHex,
              connector.getRepeaterBatteryMillivolts(contact.publicKeyHex),
            ),
          ),
    );

    final markerParts = <Object?>[connector.selfName];
    for (final contact in connector.contacts) {
      markerParts.add(contact.publicKeyHex);
      markerParts.add(contact.name);
      for (final message in connector.getMessages(contact)) {
        if (!message.text.trimLeft().startsWith('m:')) continue;
        markerParts.add(
          Object.hash(
            message.messageId,
            message.text,
            message.timestamp.millisecondsSinceEpoch,
            message.isOutgoing,
          ),
        );
      }
    }
    for (final channel in connector.channels) {
      markerParts.add(
        Object.hash(
          channel.index,
          channel.name,
          channel.isPublicChannel,
          channel.isEmpty,
        ),
      );
      for (final message in connector.getChannelMessages(channel)) {
        if (!message.text.trimLeft().startsWith('m:')) continue;
        markerParts.add(
          Object.hash(
            message.messageId,
            message.text,
            message.senderName,
            message.timestamp.millisecondsSinceEpoch,
          ),
        );
      }
    }

    return _MapConnectorSnapshot(
      connector: connector,
      contactsSignature: contactsSignature,
      markerSignature: Object.hashAll(markerParts),
      batterySignature: batterySignature,
      uiSignature: Object.hash(
        connector.isConnected,
        connector.selfLatitude,
        connector.selfLongitude,
        connector.currentFreqHz,
        connector.currentBwHz,
        connector.currentSf,
        connector.currentTxPower,
        connector.getTotalContactsUnreadCount(),
        connector.getTotalChannelsUnreadCount(),
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _MapConnectorSnapshot &&
        contactsSignature == other.contactsSignature &&
        markerSignature == other.markerSignature &&
        batterySignature == other.batterySignature &&
        uiSignature == other.uiSignature;
  }

  @override
  int get hashCode => Object.hash(
    contactsSignature,
    markerSignature,
    batterySignature,
    uiSignature,
  );
}

class _NodeMarkersCacheKey {
  final int contactsSignature;
  final int visibleContactsSignature;
  final int batterySignature;
  final _Freshness freshness;
  final double timeFilterHours;
  final bool keyPrefixEnabled;
  final String keyPrefix;
  final bool showDiscoveryContacts;
  final int batteryChemistrySignature;
  final bool showLabels;
  final String? selectedKey;
  final double zoom;
  final bool overlapsMode;
  final bool showRepeaters;
  final bool showChatNodes;
  final bool showOtherNodes;
  final bool isBuildingPathTrace;
  final bool wardriveHighlightActive;
  final int wardriveAnsweredSignature;

  const _NodeMarkersCacheKey({
    required this.contactsSignature,
    required this.visibleContactsSignature,
    required this.batterySignature,
    required this.freshness,
    required this.timeFilterHours,
    required this.keyPrefixEnabled,
    required this.keyPrefix,
    required this.showDiscoveryContacts,
    required this.batteryChemistrySignature,
    required this.showLabels,
    required this.selectedKey,
    required this.zoom,
    required this.overlapsMode,
    required this.showRepeaters,
    required this.showChatNodes,
    required this.showOtherNodes,
    required this.isBuildingPathTrace,
    required this.wardriveHighlightActive,
    required this.wardriveAnsweredSignature,
  });

  @override
  bool operator ==(Object other) {
    return other is _NodeMarkersCacheKey &&
        contactsSignature == other.contactsSignature &&
        visibleContactsSignature == other.visibleContactsSignature &&
        batterySignature == other.batterySignature &&
        freshness == other.freshness &&
        timeFilterHours == other.timeFilterHours &&
        keyPrefixEnabled == other.keyPrefixEnabled &&
        keyPrefix == other.keyPrefix &&
        showDiscoveryContacts == other.showDiscoveryContacts &&
        batteryChemistrySignature == other.batteryChemistrySignature &&
        showLabels == other.showLabels &&
        selectedKey == other.selectedKey &&
        zoom == other.zoom &&
        overlapsMode == other.overlapsMode &&
        showRepeaters == other.showRepeaters &&
        showChatNodes == other.showChatNodes &&
        showOtherNodes == other.showOtherNodes &&
        isBuildingPathTrace == other.isBuildingPathTrace &&
        wardriveHighlightActive == other.wardriveHighlightActive &&
        wardriveAnsweredSignature == other.wardriveAnsweredSignature;
  }

  @override
  int get hashCode => Object.hashAll([
    contactsSignature,
    visibleContactsSignature,
    batterySignature,
    freshness,
    timeFilterHours,
    keyPrefixEnabled,
    keyPrefix,
    showDiscoveryContacts,
    batteryChemistrySignature,
    showLabels,
    selectedKey,
    zoom,
    overlapsMode,
    showRepeaters,
    showChatNodes,
    showOtherNodes,
    isBuildingPathTrace,
    wardriveHighlightActive,
    wardriveAnsweredSignature,
  ]);
}

class _GuessedLocation {
  final Contact contact;
  final LatLng position;
  final bool highConfidence;

  _GuessedLocation({
    required this.contact,
    required this.position,
    required this.highConfidence,
  });
}

class MarkerPayload {
  final LatLng position;
  final String label;
  final String flags;

  MarkerPayload({
    required this.position,
    required this.label,
    required this.flags,
  });
}

/// Parse a shared marker text message of the form
/// `m:<lat>,<lon>|<label>|<flags>` and return a [MarkerPayload].
MarkerPayload? parseMarkerText(String text) {
  final trimmed = text.trim();
  final match = RegExp(
    r'm:([\-0-9.]+),([\-0-9.]+)\|([^|]*)\|(.*)',
  ).firstMatch(trimmed);
  if (match == null) return null;
  final lat = double.tryParse(match.group(1) ?? '');
  final lon = double.tryParse(match.group(2) ?? '');
  if (lat == null || lon == null) return null;
  final label = (match.group(3) ?? '').trim();
  final flags = (match.group(4) ?? '').trim();
  return MarkerPayload(position: LatLng(lat, lon), label: label, flags: flags);
}

/// Build a normalized dedupe key for shared markers.
/// Keeps the same algorithm previously present in both chat and map screens.
String buildSharedMarkerKey({
  required String sourceId,
  required String label,
  required String fromName,
  required String flags,
  required bool isChannel,
}) {
  final normalizedLabel = label.trim().toLowerCase();
  final normalizedFrom = fromName.trim().toLowerCase();
  final normalizedFlags = flags.trim().toLowerCase();
  final scope = isChannel ? 'ch' : 'dm';
  return '$scope|$sourceId|$normalizedFrom|$normalizedLabel|$normalizedFlags';
}

class _WardriveCoverageResolutionOption {
  final int precision;
  final String title;
  final String subtitle;

  const _WardriveCoverageResolutionOption({
    required this.precision,
    required this.title,
    required this.subtitle,
  });
}

enum _WardriveCoverageBlockAction { delete }

class _WardriveCoverageBlock {
  final String hash;
  final int precision;

  const _WardriveCoverageBlock({required this.hash, required this.precision});
}

class _SharedMarker {
  final String id;
  final LatLng position;
  final String label;
  final String flags;
  final String fromName;
  final String sourceLabel;
  final DateTime timestamp;
  final bool isChannel;
  final bool isPublicChannel;
  final List<LatLng> history;

  _SharedMarker({
    required this.id,
    required this.position,
    required this.label,
    required this.flags,
    required this.fromName,
    required this.sourceLabel,
    required this.timestamp,
    required this.isChannel,
    required this.isPublicChannel,
    this.history = const [],
  });

  _SharedMarker copyWithHistory(List<LatLng> newHistory) {
    return _SharedMarker(
      id: id,
      position: position,
      label: label,
      flags: flags,
      fromName: fromName,
      sourceLabel: sourceLabel,
      timestamp: timestamp,
      isChannel: isChannel,
      isPublicChannel: isPublicChannel,
      history: newHistory,
    );
  }
}

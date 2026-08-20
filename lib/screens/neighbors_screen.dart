import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meshcore_open/utils/app_logger.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../models/path_selection.dart';
import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../services/repeater_command_service.dart';
import '../theme/mesh_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/routing_sheet.dart';
import '../helpers/snack_bar_builder.dart';
import '../helpers/neighbor_map_focus.dart';
import 'map_screen.dart';

class NeighborsScreen extends StatefulWidget {
  final Contact repeater;
  final String password;

  const NeighborsScreen({
    super.key,
    required this.repeater,
    required this.password,
  });

  @override
  State<NeighborsScreen> createState() => _NeighborsScreenState();
}

class _NeighborsScreenState extends State<NeighborsScreen> {
  static const int _reqNeighborsKeyLen = 4;

  /// Neighbours asked for per request. The repeater answers out of a fixed
  /// 130-byte buffer, so with a 4-byte key prefix it fits 14 and truncates the
  /// page — which is why paging advances by what actually arrived, never by
  /// what was requested.
  static const int _neighborsPageSize = 15;

  /// Backstop against a repeater that keeps reporting more neighbours than it
  /// ever returns; 8 pages already covers the firmware's 50-entry table.
  static const int _maxNeighborPages = 8;

  static const Duration _sentResponseFallbackTimeout = Duration(seconds: 10);
  static const Duration _responseTimeoutPadding = Duration(seconds: 2);
  Uint8List _tagData = Uint8List(4);
  int _neighborCount = 0;
  final List<Map<String, dynamic>> _collectedNeighbors = [];
  int _pagesFetched = 0;

  bool _isLoading = false;
  bool _isLoaded = false;
  bool _hasData = false;
  Timer? _statusTimeout;
  StreamSubscription<Uint8List>? _frameSubscription;
  RepeaterCommandService? _commandService;
  PathSelection? _pendingStatusSelection;
  List<Map<String, dynamic>>? _parsedNeighbors;

  int _resolveRepeaterIndex = -1;

  Contact _resolveRepeater(MeshCoreConnector connector) {
    if (_resolveRepeaterIndex >= 0 &&
        _resolveRepeaterIndex < connector.contacts.length &&
        connector.contacts[_resolveRepeaterIndex].publicKeyHex ==
            widget.repeater.publicKeyHex) {
      return connector.contacts[_resolveRepeaterIndex];
    }
    _resolveRepeaterIndex = connector.contacts.indexWhere(
      (c) => c.publicKeyHex == widget.repeater.publicKeyHex,
    );
    if (_resolveRepeaterIndex == -1) {
      return widget.repeater;
    }
    return connector.contacts[_resolveRepeaterIndex];
  }

  @override
  void initState() {
    super.initState();
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    _commandService = RepeaterCommandService(connector);
    _setupMessageListener();
    _loadNeighbors();
    _hasData = false;
  }

  void _setupMessageListener() {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);

    // Listen for incoming text messages from the repeater
    _frameSubscription = connector.receivedFrames.listen((frame) {
      if (frame.isEmpty) return;

      if (frame[0] == respCodeSent) {
        if (frame.length >= 6) {
          _tagData = frame.sublist(2, 6);
        }
        if (_isLoading && frame.length >= 10) {
          final estimatedTimeoutMs = readUint32LE(frame, 6);
          _startStatusTimeout(
            estimatedTimeoutMs > 0
                ? Duration(milliseconds: estimatedTimeoutMs) +
                      _responseTimeoutPadding
                : _sentResponseFallbackTimeout,
          );
        }
      }

      // Check if it's a binary response
      if (frame.length >= 6 &&
          frame[0] == pushCodeBinaryResponse &&
          listEquals(frame.sublist(2, 6), _tagData)) {
        _handleNeighborsResponse(connector, frame.sublist(6));
      }
    });
  }

  String fmtDuration(double seconds) {
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(1)}s';
    }

    final int m = (seconds ~/ 60).toInt();
    final double s = seconds - (60 * m);

    if (m < 60) {
      return '${m}m ${s.toStringAsFixed(0)}s';
    }

    final int h = m ~/ 60;
    final int m2 = m % 60;

    return '${h}h ${m2}m';
  }

  static List<Map<String, dynamic>> parseNeighborsData(
    BufferReader buffer,
    int resultsCount,
  ) {
    final Map<int, Map<String, dynamic>> neighbors = {};
    try {
      for (var i = 0; i < resultsCount; i++) {
        final neighborData = neighbors.putIfAbsent(
          i,
          () => {
            'contact': null,
            'publicKey': <Uint8List>{},
            'lastHeard': <int>{},
            'snr': <double>{},
          },
        );
        neighborData['publicKey'] = buffer.readBytes(_reqNeighborsKeyLen);
        neighborData['lastHeard'] = buffer.readUInt32LE();
        neighborData['snr'] = buffer.readInt8() / 4.0;
      }

      return neighbors.values.toList();
    } catch (e) {
      appLogger.error(
        'Error parsing neighbors data: $e',
        tag: 'NeighborsScreen',
      );
      return [];
    }
  }

  void _handleNeighborsResponse(MeshCoreConnector connector, Uint8List frame) {
    final buffer = BufferReader(frame);
    final contacts = connector.allContactsUnfiltered;
    try {
      final neighborCount = buffer.readUInt16LE();
      final pageNeighbors = parseNeighborsData(buffer, buffer.readUInt16LE());
      contacts.where((c) => c.type == advTypeRepeater).forEach((repeater) {
        for (var neighborData in pageNeighbors) {
          final publicKey = neighborData['publicKey'];
          if (listEquals(
            repeater.publicKey.sublist(0, _reqNeighborsKeyLen),
            publicKey,
          )) {
            neighborData['contact'] = repeater;
          }
        }
      });

      _statusTimeout?.cancel();
      _recordStatusResult(true);
      if (!mounted) return;

      _collectedNeighbors.addAll(pageNeighbors);
      _pagesFetched++;

      // The repeater reports how many neighbours it knows separately from how
      // many fit in this answer, so keep paging until the two agree. An empty
      // page means it has nothing more to give, whatever the total claims.
      final hasMore =
          pageNeighbors.isNotEmpty &&
          _collectedNeighbors.length < neighborCount &&
          _pagesFetched < _maxNeighborPages;

      setState(() {
        _parsedNeighbors = List.of(_collectedNeighbors);
        _neighborCount = neighborCount;
        _isLoading = hasMore;
        _isLoaded = !hasMore;
        _hasData = true;
      });

      if (hasMore) {
        unawaited(_requestNeighborsPage(_collectedNeighbors.length));
        return;
      }

      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.neighbors_receivedData),
        backgroundColor: Theme.of(context).colorScheme.tertiary,
      );
    } catch (e) {
      appLogger.error('Error handling neighbors response: $e');
    }
  }

  Future<void> _loadNeighbors() async {
    if (_commandService == null) return;

    _collectedNeighbors.clear();
    _pagesFetched = 0;
    setState(() {
      _isLoading = true;
      _isLoaded = false;
    });
    await _requestNeighborsPage(0);
  }

  Future<void> _requestNeighborsPage(int offset) async {
    try {
      final connector = Provider.of<MeshCoreConnector>(context, listen: false);
      final repeater = _resolveRepeater(connector);
      final selection = await connector.preparePathForContactSend(repeater);
      _pendingStatusSelection = selection;

      // [req type][version][count][offset_16bit][order by]
      // [pubkey prefix length]
      final frame = buildSendBinaryReq(
        repeater.publicKey,
        payload: Uint8List.fromList([
          reqTypeGetNeighbors,
          0x00,
          _neighborsPageSize,
          offset & 0xFF,
          (offset >> 8) & 0xFF,
          0x00,
          _reqNeighborsKeyLen,
        ]),
      );
      _startStatusTimeout(_sentResponseFallbackTimeout);
      await connector.sendFrame(frame);
    } catch (e) {
      _statusTimeout?.cancel();
      if (mounted) {
        // Whatever arrived before the failure is still worth showing.
        setState(() {
          _isLoading = false;
          _isLoaded = _collectedNeighbors.isNotEmpty;
        });

        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.neighbors_errorLoading(e.toString())),
          backgroundColor: Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  void _startStatusTimeout(Duration duration) {
    _statusTimeout?.cancel();
    _statusTimeout = Timer(duration, _handleStatusTimeout);
  }

  void _handleStatusTimeout() {
    if (!mounted) return;
    // A later page timing out should not throw away the earlier ones.
    setState(() {
      _isLoading = false;
      _isLoaded = _collectedNeighbors.isNotEmpty;
    });
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.neighbors_requestTimedOut),
      backgroundColor: Theme.of(context).colorScheme.error,
    );
    _recordStatusResult(false);
  }

  void _recordStatusResult(bool success) {
    final selection = _pendingStatusSelection;
    if (selection == null) return;
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final repeater = _resolveRepeater(connector);
    connector.recordRepeaterPathResult(repeater, selection, success, null);
    _pendingStatusSelection = null;
  }

  void _openNeighborsMap(Contact repeater) {
    final neighborKeys = <String>{};
    for (final data in _parsedNeighbors ?? const <Map<String, dynamic>>[]) {
      final contact = data['contact'];
      if (contact is Contact && contact.type == advTypeRepeater) {
        neighborKeys.add(contact.publicKeyHex);
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapScreen(
          neighborFocus: NeighborMapFocus(
            repeaterKey: repeater.publicKeyHex,
            neighborKeys: neighborKeys,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _frameSubscription?.cancel();
    _commandService?.dispose();
    _statusTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final connector = context.watch<MeshCoreConnector>();
    final repeater = _resolveRepeater(connector);
    final isFloodMode = repeater.pathOverride == -1;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.neighbors_repeatersNeighbors,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              repeater.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (_hasData)
            IconButton(
              icon: const Icon(Icons.map_outlined),
              tooltip: l10n.channelPath_viewMap,
              onPressed: () => _openNeighborsMap(repeater),
            ),
          IconButton(
            icon: Icon(isFloodMode ? Icons.waves : Icons.route),
            tooltip: l10n.repeater_routingMode,
            onPressed: () =>
                ContactRoutingSheet.show(context, contact: repeater),
          ),
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadNeighbors,
            tooltip: l10n.repeater_refresh,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadNeighbors,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (!_isLoaded &&
                  !_hasData &&
                  (_parsedNeighbors == null || _parsedNeighbors!.isEmpty))
                EmptyState(icon: Icons.wifi_find, title: l10n.neighbors_noData),
              if (_isLoaded ||
                  _hasData &&
                      !(_parsedNeighbors == null || _parsedNeighbors!.isEmpty))
                _buildNeighborsList(connector),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNeighborsList(MeshCoreConnector connector) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          '${l10n.repeater_neighbors} — $_neighborCount',
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        ),
        for (var i = 0; i < _parsedNeighbors!.length; i++)
          ListEntrance(
            index: i,
            child: _buildNeighborRow(_parsedNeighbors![i], connector.currentSf),
          ),
      ],
    );
  }

  Widget _buildNeighborRow(Map<String, dynamic> data, int? spreadingFactor) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final Contact? contact = data['contact'] as Contact?;
    final double snr = data['snr'] as double;
    final int lastHeardSeconds = data['lastHeard'] as int;

    // Straight from the repeater's answer, never rebuilt from a matched
    // contact: this is the identity the repeater actually reported, and the
    // name above it is only our local guess at who owns it.
    final keyPrefix = pubKeyToHex(data['publicKey'] as Uint8List);
    final name = contact != null
        ? contact.name
        : l10n.neighbors_unknownContact('<$keyPrefix>');

    final snrColor = MeshTheme.snrColor(snr, blocked: false);
    final heardLabel = l10n.neighbors_heardAgo(
      fmtDuration(lastHeardSeconds + 0.0),
    );

    return MeshCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          AvatarCircle(
            name: name,
            size: 40,
            color: contact != null ? MeshPalette.warn : scheme.onSurfaceVariant,
            icon: contact != null ? Icons.cell_tower : Icons.device_unknown,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  keyPrefix,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MeshTheme.mono(
                    fontSize: 11,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  heardLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              SignalBars(snr: snr, height: 16),
              const SizedBox(height: 4),
              Text(
                '${snr.toStringAsFixed(1)} dB',
                style: MeshTheme.mono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: snrColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

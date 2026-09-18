import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mco_service/mco_service.dart';

import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../theme/mesh_theme.dart';
import 'neighbor_map_focus.dart';

/// A line a discovery response draws to a marker that stands on an estimate.
typedef EstimatedResponderLink = ({
  LatLng from,
  LatLng to,
  String responderKey,
});

/// Map side of repeaters that are on the map by estimate rather than by their
/// own advert: the prefix-only ones, known by nothing but the hop prefix they
/// left in channel routes (`McoEstimatedContactLocation.isPrefixOnly`), and the
/// lines a zero-hop discovery or wardrive response draws to any estimated
/// marker. Kept out of `map_screen.dart`, which only holds the hooks.
class EstimatedRepeaterMap {
  const EstimatedRepeaterMap._();

  /// The prefix-only estimates the map shows. One is dropped as soon as a known
  /// repeater or room server begins with its prefix: from then on that node is
  /// what every hop list names the hop as, and the next recalculation gives it
  /// a marker of its own instead.
  static List<McoEstimatedContactLocation> visiblePrefixRepeaters(
    List<McoEstimatedContactLocation> estimates, {
    required Iterable<Contact> knownNodes,
    required String keyPrefixFilter,
  }) {
    if (estimates.isEmpty) return const [];
    final claimed = <String>{};
    for (final node in knownNodes) {
      if (node.type != advTypeRepeater && node.type != advTypeRoom) continue;
      final head = _hex(node.publicKey.take(4));
      for (var length = 2; length <= head.length; length += 2) {
        claimed.add(head.substring(0, length));
      }
    }
    final filter = keyPrefixFilter.trim().toLowerCase();
    return [
      for (final estimate in estimates)
        if (estimate.isPrefixOnly &&
            !claimed.contains(estimate.publicKeyHex) &&
            (filter.isEmpty ||
                estimate.publicKeyHex.startsWith(filter) ||
                filter.startsWith(estimate.publicKeyHex)))
          estimate,
    ];
  }

  /// Whether one of the discovery responders is the repeater behind a
  /// prefix-only estimate. The prefix is all that is known of its key, so this
  /// cannot ask for the four bytes `NeighborMapFocus.publicKeysMatch` wants.
  static bool prefixAnswered(
    McoEstimatedContactLocation estimate,
    Iterable<String> answeredKeys,
  ) => answeredKeys.any(
    (key) => key.toLowerCase().startsWith(estimate.publicKeyHex),
  );

  /// The pin of a prefix-only repeater, drawn like any other estimated node.
  static Marker prefixMarker(
    McoEstimatedContactLocation estimate, {
    required double opacity,
    required VoidCallback onTap,
  }) => Marker(
    point: LatLng(estimate.latitude, estimate.longitude),
    width: 48,
    height: 48,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: MapPalette.repeater.withValues(
            alpha: (estimate.highConfidence ? 0.55 : 0.30) * opacity,
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

  /// The rays a tap on an estimated repeater shows, named or prefix-only: one
  /// to every repeater its estimate rests on, the neighbours its routes were
  /// seen to go on through. They end where those repeaters stood when the
  /// estimate was made, since that is what it was computed from.
  static List<Polyline> linkPolylines(McoEstimatedContactLocation estimate) {
    final from = LatLng(estimate.latitude, estimate.longitude);
    return [
      for (
        var index = 0;
        index < estimate.anchorLatitudes.length &&
            index < estimate.anchorLongitudes.length;
        index++
      )
        Polyline(
          points: [
            from,
            LatLng(
              estimate.anchorLatitudes[index],
              estimate.anchorLongitudes[index],
            ),
          ],
          strokeWidth: 2.5,
          color: MapPalette.online.withValues(alpha: 0.9),
        ),
    ];
  }

  /// One link per responder that has an estimated marker. [origins] says where
  /// each responder's line starts: this node for a live discovery, the sample's
  /// own position for a selected coverage cell. A named estimate wins over a
  /// prefix-only one, and among those the longest prefix does.
  static List<EstimatedResponderLink> responderLinks({
    required Map<String, LatLng> origins,
    required Iterable<({String publicKeyHex, LatLng position})> named,
    required Iterable<McoEstimatedContactLocation> prefixOnly,
  }) {
    final links = <EstimatedResponderLink>[];
    for (final origin in origins.entries) {
      final responderKey = origin.key.toLowerCase();
      LatLng? target;
      for (final estimate in named) {
        if (NeighborMapFocus.publicKeysMatch(
          estimate.publicKeyHex,
          responderKey,
        )) {
          target = estimate.position;
          break;
        }
      }
      if (target == null) {
        var matchedLength = 0;
        for (final estimate in prefixOnly) {
          final prefix = estimate.publicKeyHex;
          if (prefix.length > matchedLength &&
              responderKey.startsWith(prefix)) {
            matchedLength = prefix.length;
            target = LatLng(estimate.latitude, estimate.longitude);
          }
        }
      }
      if (target != null) {
        links.add((
          from: origin.value,
          to: target,
          responderKey: responderKey,
        ));
      }
    }
    return links;
  }

  static String _hex(Iterable<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

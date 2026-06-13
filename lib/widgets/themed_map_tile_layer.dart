import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../services/map_tile_cache_service.dart';

/// Shared cached map tiles with an automatic dark-mode treatment.
///
/// The dark style transforms the existing OpenStreetMap raster tiles, so light
/// and dark maps share the same offline cache and network requests.
class ThemedMapTileLayer extends StatelessWidget {
  final MapTileCacheService tileCache;
  final double opacity;

  const ThemedMapTileLayer({
    super.key,
    required this.tileCache,
    this.opacity = 1,
  });

  static const ColorFilter _darkMapFilter = ColorFilter.matrix([
    -0.0850,
    -0.2861,
    -0.0289,
    0,
    120,
    -0.0957,
    -0.3218,
    -0.0325,
    0,
    140,
    -0.1169,
    -0.3934,
    -0.0397,
    0,
    170,
    0,
    0,
    0,
    1,
    0,
  ]);

  @override
  Widget build(BuildContext context) {
    Widget layer = TileLayer(
      urlTemplate: kMapTileUrlTemplate,
      tileProvider: tileCache.tileProvider,
      userAgentPackageName: MapTileCacheService.userAgentPackageName,
      maxZoom: 19,
    );

    if (Theme.of(context).brightness == Brightness.dark) {
      layer = ColorFiltered(colorFilter: _darkMapFilter, child: layer);
    }
    if (opacity < 1) {
      layer = Opacity(opacity: opacity, child: layer);
    }
    return layer;
  }
}

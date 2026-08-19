import 'package:flutter/material.dart';

/// How markers shared into a channel are drawn on the map, and whether they
/// are drawn at all.
@immutable
class ChannelMarkerStyle {
  const ChannelMarkerStyle({
    this.enabled = true,
    this.colorKey = ChannelMarkerPalette.defaultColorKey,
    this.iconKey = ChannelMarkerPalette.defaultIconKey,
  });

  /// Style a channel gets before anyone edits it. [order] is its place in the
  /// picker, so colours are handed out down the palette in order — Public sits
  /// first and keeps green.
  factory ChannelMarkerStyle.defaultsFor(int order) {
    return ChannelMarkerStyle(
      colorKey: ChannelMarkerPalette.defaultColorKeyFor(order),
    );
  }

  final bool enabled;
  final String colorKey;
  final String iconKey;

  static const ChannelMarkerStyle fallback = ChannelMarkerStyle();

  Color get color => ChannelMarkerPalette.colorFor(colorKey);
  IconData get icon => ChannelMarkerPalette.iconFor(iconKey);

  ChannelMarkerStyle copyWith({
    bool? enabled,
    String? colorKey,
    String? iconKey,
  }) {
    return ChannelMarkerStyle(
      enabled: enabled ?? this.enabled,
      colorKey: colorKey ?? this.colorKey,
      iconKey: iconKey ?? this.iconKey,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'color': colorKey,
    'icon': iconKey,
  };

  factory ChannelMarkerStyle.fromJson(Map<String, dynamic> json) {
    return ChannelMarkerStyle(
      enabled: json['enabled'] as bool? ?? true,
      colorKey: ChannelMarkerPalette.normalizeColorKey(json['color']),
      iconKey: ChannelMarkerPalette.normalizeIconKey(json['icon']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChannelMarkerStyle &&
      other.enabled == enabled &&
      other.colorKey == colorKey &&
      other.iconKey == iconKey;

  @override
  int get hashCode => Object.hash(enabled, colorKey, iconKey);
}

/// The choices offered when styling a channel's markers.
///
/// Colours and icons are stored by key rather than by value: a `Color` int
/// would be fine, but an icon code point would not — building `IconData` at
/// runtime defeats the icon tree-shaker and blows up the bundled font.
class ChannelMarkerPalette {
  ChannelMarkerPalette._();

  static const String defaultColorKey = 'green';
  static const String defaultIconKey = 'place';

  static const Map<String, Color> colors = {
    'green': Color(0xFF22C55E),
    'orange': Color(0xFFF97316),
    'red': Color(0xFFEF4444),
    'pink': Color(0xFFEC4899),
    'purple': Color(0xFF7C3AED),
    'blue': Color(0xFF2563EB),
    'lightBlue': Color(0xFF0EA5E9),
    'teal': Color(0xFF0F766E),
    'yellow': Color(0xFFEAB308),
    'brown': Color(0xFF92400E),
    'grey': Color(0xFF6B7280),
    'black': Color(0xFF111827),
  };

  /// Each entry costs one glyph in the tree-shaken Material font — a couple of
  /// hundred bytes — so the list can be generous. Grouped roughly by what a
  /// pin marks: general, places, outdoors, travel, radio, hazards.
  static const Map<String, IconData> icons = {
    'place': Icons.place,
    'flag': Icons.flag,
    'star': Icons.star,
    'favorite': Icons.favorite,
    'bookmark': Icons.bookmark,
    'groups': Icons.groups,
    'home': Icons.home,
    'tent': Icons.cabin,
    'apartment': Icons.apartment,
    'church': Icons.church,
    'store': Icons.storefront,
    'food': Icons.restaurant,
    'cafe': Icons.local_cafe,
    'fuel': Icons.local_gas_station,
    'parking': Icons.local_parking,
    'pharmacy': Icons.local_pharmacy,
    'medical': Icons.medical_services,
    'terrain': Icons.terrain,
    'forest': Icons.forest,
    'park': Icons.park,
    'water': Icons.water_drop,
    'beach': Icons.beach_access,
    'snow': Icons.ac_unit,
    'sun': Icons.wb_sunny,
    'hiking': Icons.hiking,
    'ski': Icons.downhill_skiing,
    'walk': Icons.directions_walk,
    'car': Icons.directions_car,
    'bike': Icons.directions_bike,
    'moto': Icons.two_wheeler,
    'boat': Icons.directions_boat,
    'sailing': Icons.sailing,
    'kayak': Icons.kayaking,
    'train': Icons.train,
    'flight': Icons.flight,
    'anchor': Icons.anchor,
    'luggage': Icons.luggage,
    'radio': Icons.cell_tower,
    'router': Icons.router,
    'wifi': Icons.wifi,
    'satellite': Icons.satellite_alt,
    'power': Icons.bolt,
    'warning': Icons.warning_amber,
    'fire': Icons.local_fire_department,
    'construction': Icons.construction,
    'build': Icons.build,
    'key': Icons.key,
    'watch': Icons.visibility,
    'camera': Icons.photo_camera,
    'pets': Icons.pets,
  };

  /// Walks the palette in order and wraps around, so a short channel list
  /// gets a distinct colour per channel instead of a shuffle with repeats.
  static String defaultColorKeyFor(int order) {
    if (order < 0) return defaultColorKey;
    return colors.keys.elementAt(order % colors.length);
  }

  static Color colorFor(String key) => colors[key] ?? colors[defaultColorKey]!;

  static IconData iconFor(String key) => icons[key] ?? icons[defaultIconKey]!;

  static String normalizeColorKey(Object? value) {
    final key = value is String ? value : '';
    return colors.containsKey(key) ? key : defaultColorKey;
  }

  static String normalizeIconKey(Object? value) {
    final key = value is String ? value : '';
    return icons.containsKey(key) ? key : defaultIconKey;
  }
}

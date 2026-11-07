import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../helpers/theme_media.dart';

export '../helpers/theme_media.dart' show isThemeAssetPath, kThemeAssetDir;

/// The app icons a theme can replace. [key] is what themes store, so it must
/// never change once released.
enum ThemeIconSlot {
  contacts('contacts', Icons.people_outline, Icons.people),
  channels('channels', Icons.tag, Icons.tag),
  map('map', Icons.map_outlined, Icons.map),
  send('send', Icons.send, Icons.send),
  settings('settings', Icons.settings, Icons.settings),
  repeater('repeater', Icons.cell_tower, Icons.cell_tower),
  room('room', Icons.meeting_room, Icons.meeting_room),
  sensor('sensor', Icons.sensors, Icons.sensors),

  // Map markers.
  mapChat('map_chat', Icons.person, Icons.person),
  mapRepeater('map_repeater', Icons.router, Icons.router),
  mapRoom('map_room', Icons.meeting_room, Icons.meeting_room),
  mapSensor('map_sensor', Icons.sensors, Icons.sensors),
  mapSelf('map_self', Icons.person_pin_circle, Icons.person_pin_circle);

  /// Whether this slot is a marker on the map (grouped apart in the editor).
  bool get isMapMarker => key.startsWith('map_');

  /// The slot showing the same node type elsewhere: list avatar <-> map
  /// marker. Null when there is none.
  ThemeIconSlot? get partner => switch (this) {
    ThemeIconSlot.repeater => ThemeIconSlot.mapRepeater,
    ThemeIconSlot.room => ThemeIconSlot.mapRoom,
    ThemeIconSlot.sensor => ThemeIconSlot.mapSensor,
    ThemeIconSlot.mapRepeater => ThemeIconSlot.repeater,
    ThemeIconSlot.mapRoom => ThemeIconSlot.room,
    ThemeIconSlot.mapSensor => ThemeIconSlot.sensor,
    _ => null,
  };

  final String key;
  final IconData icon;

  /// Variant shown when the slot is selected (e.g. the active nav tab).
  final IconData selectedIcon;

  const ThemeIconSlot(this.key, this.icon, this.selectedIcon);
}

/// A replacement for one theme slot. Stored image data remains encoded until
/// a renderer requests the bytes.
@immutable
class ThemeIconOverride {
  static final _decodedImages = Expando<Uint8List>();

  final String? icon;
  final String? image;
  final String? asset;

  const ThemeIconOverride.icon(String this.icon) : image = null, asset = null;

  factory ThemeIconOverride.image(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxThemeIconBytes) {
      throw ArgumentError.value(bytes.length, 'bytes', 'Invalid theme icon size');
    }
    return ThemeIconOverride._image(base64Encode(bytes));
  }

  const ThemeIconOverride._image(String this.image) : icon = null, asset = null;

  const ThemeIconOverride.asset(String this.asset) : icon = null, image = null;

  bool get isPicture => image != null || asset != null;

  Uint8List? get imageBytes {
    final encoded = image;
    if (encoded == null) return null;
    return _decodedImages[this] ??= base64Decode(encoded).asUnmodifiableView();
  }

  Map<String, dynamic> toJson() => {
    if (icon != null) 'icon': icon,
    if (image != null) 'image': image,
    if (asset != null) 'asset': asset,
  };

  static ThemeIconOverride? fromJson(Object? json) {
    if (json is! Map) return null;
    final encoded = json['image'];
    if (encoded is String && encoded.isNotEmpty) {
      final image = normalizeThemeImageData(encoded, maxBytes: maxThemeIconBytes);
      return image == null ? null : ThemeIconOverride._image(image);
    }
    final asset = json['asset'];
    if (asset is String && isThemeAssetPath(asset)) {
      return ThemeIconOverride.asset(asset);
    }
    final icon = json['icon'];
    if (icon is String && kThemeIconCatalog.containsKey(icon)) {
      return ThemeIconOverride.icon(icon);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeIconOverride &&
      other.icon == icon &&
      other.image == image &&
      other.asset == asset;

  @override
  int get hashCode => Object.hash(icon, image, asset);
}

/// Reads known slots in a fixed order and ignores unsupported replacements.
Map<String, ThemeIconOverride> parseThemeIcons(Object? json) {
  if (json is! Map || json.isEmpty) return const {};
  final result = <String, ThemeIconOverride>{};
  for (final slot in ThemeIconSlot.values) {
    final replacement = ThemeIconOverride.fromJson(json[slot.key]);
    if (replacement != null) result[slot.key] = replacement;
  }
  return result.isEmpty ? const {} : Map.unmodifiable(result);
}

/// Icons offered in the picker, by the name themes store.
const Map<String, IconData> kThemeIconCatalog = {
  'people': Icons.people,
  'person': Icons.person,
  'groups': Icons.groups,
  'contacts': Icons.contacts,
  'forum': Icons.forum,
  'chat': Icons.chat,
  'chat_bubble': Icons.chat_bubble,
  'mail': Icons.mail,
  'tag': Icons.tag,
  'campaign': Icons.campaign,
  'podcasts': Icons.podcasts,
  'radio': Icons.radio,
  'map': Icons.map,
  'public': Icons.public,
  'explore': Icons.explore,
  'place': Icons.place,
  'near_me': Icons.near_me,
  'terrain': Icons.terrain,
  'send': Icons.send,
  'rocket_launch': Icons.rocket_launch,
  'arrow_upward': Icons.arrow_upward,
  'north_east': Icons.north_east,
  'flight': Icons.flight,
  'bolt': Icons.bolt,
  'settings': Icons.settings,
  'tune': Icons.tune,
  'build': Icons.build,
  'menu': Icons.menu,
  'cell_tower': Icons.cell_tower,
  'router': Icons.router,
  'wifi_tethering': Icons.wifi_tethering,
  'satellite_alt': Icons.satellite_alt,
  'meeting_room': Icons.meeting_room,
  'home': Icons.home,
  'cabin': Icons.cabin,
  'castle': Icons.castle,
  'sensors': Icons.sensors,
  'thermostat': Icons.thermostat,
  'water_drop': Icons.water_drop,
  'eco': Icons.eco,
  'star': Icons.star,
  'favorite': Icons.favorite,
  'pets': Icons.pets,
  'hiking': Icons.hiking,
  'sailing': Icons.sailing,
  'anchor': Icons.anchor,
  'local_fire_department': Icons.local_fire_department,
  'shield': Icons.shield,
  'emoji_emotions': Icons.emoji_emotions,
  'auto_awesome': Icons.auto_awesome,
  'nightlight': Icons.nightlight,
  'wb_sunny': Icons.wb_sunny,
  'park': Icons.park,
  'diamond': Icons.diamond,
};

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:koni_jxl_flutter/koni_jxl_flutter.dart';

import '../connector/meshcore_protocol.dart';
import '../theme/theme_icons.dart';

ImageProvider themePictureProvider(Uint8List bytes, {required int maxSide}) =>
    looksLikeJxl(bytes)
        ? JxlImageProvider.memory(bytes)
        : ResizeImage.resizeIfNeeded(maxSide, null, MemoryImage(bytes));

/// The map marker slot for a node type, or null for unknown types.
ThemeIconSlot? mapMarkerSlotForNodeType(int type) {
  switch (type) {
    case advTypeChat:
      return ThemeIconSlot.mapChat;
    case advTypeRepeater:
      return ThemeIconSlot.mapRepeater;
    case advTypeRoom:
      return ThemeIconSlot.mapRoom;
    case advTypeSensor:
      return ThemeIconSlot.mapSensor;
    default:
      return null;
  }
}

/// Icon overrides carried by the active theme.
@immutable
class MeshIconTheme extends ThemeExtension<MeshIconTheme> {
  final Map<String, ThemeIconOverride> overrides;

  const MeshIconTheme(this.overrides);

  static const none = MeshIconTheme({});

  static MeshIconTheme of(BuildContext context) =>
      Theme.of(context).extension<MeshIconTheme>() ?? none;

  /// The replacement for [slot]. A node type's list avatar and its map
  /// marker stand for the same thing, so when a theme sets only one of the
  /// pair the other uses it too.
  ThemeIconOverride? operator [](ThemeIconSlot slot) {
    final partner = slot.partner;
    return overrides[slot.key] ??
        (partner == null ? null : overrides[partner.key]);
  }

  @override
  MeshIconTheme copyWith({Map<String, ThemeIconOverride>? overrides}) =>
      MeshIconTheme(overrides ?? this.overrides);

  @override
  MeshIconTheme lerp(MeshIconTheme? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// Shows the active theme's icon or picture for [slot], or the default icon.
///
/// Named icons take [color] / the ambient [IconTheme] like a normal [Icon];
/// pictures are drawn in their own colors at the same size.
class ThemedIcon extends StatelessWidget {
  final ThemeIconSlot slot;
  final bool selected;
  final double? size;
  final Color? color;
  final IconData? fallback;

  /// Explicit replacement, bypassing the theme (used for editor previews).
  final ThemeIconOverride? forced;
  final bool useForced;

  const ThemedIcon(
    this.slot, {
    super.key,
    this.selected = false,
    this.size,
    this.color,
    this.fallback,
  }) : forced = null,
       useForced = false;

  const ThemedIcon.preview(
    this.slot,
    this.forced, {
    super.key,
    this.size,
    this.color,
  }) : fallback = null,
       selected = false,
       useForced = true;

  @override
  Widget build(BuildContext context) {
    final effective = useForced ? forced : MeshIconTheme.of(context)[slot];
    final bytes = effective?.imageBytes;
    final asset = effective?.asset;
    if (effective?.isPicture == true) {
      // Pictures are usually round badges with a rim, so at plain icon size
      // their detail is too small to make out. Draw them well above it.
      final iconTheme = IconTheme.of(context);
      final baseSide = size ?? iconTheme.size ?? 24;
      final side = (iconTheme.applyTextScaling == true
              ? MediaQuery.textScalerOf(context).scale(baseSide)
              : baseSide) * kThemePictureIconScale;
      return SizedBox.square(
        dimension: side,
        child: Image(
          image: bytes != null
              ? themePictureProvider(bytes, maxSide: 128)
              : JxlImageProvider.asset(asset!),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => Icon(
            fallback ?? (selected ? slot.selectedIcon : slot.icon),
            size: size,
            color: color,
          ),
        ),
      );
    }
    final named = effective?.icon == null
        ? null
        : kThemeIconCatalog[effective!.icon];
    return Icon(
      named ?? fallback ?? (selected ? slot.selectedIcon : slot.icon),
      size: size,
      color: color,
    );
  }
}

/// How much larger than a plain icon a picture icon is drawn.
const double kThemePictureIconScale = 1.6;

import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/channel_marker_style.dart';
import '../storage/channel_marker_style_store.dart';

/// Per-channel appearance of shared markers, loaded once per node and looked
/// up while drawing.
///
/// Everything the feature needs at the map's side lives here, so the map
/// screen only holds one field and asks three questions: is this marker's
/// channel visible, how should it look, and which channels go in the picker.
class ChannelMarkerStyles {
  ChannelMarkerStyles({this.onChanged});

  /// Called after a style is edited, so the map can repaint. Set once where
  /// the controller is created rather than passed through every call site.
  final VoidCallback? onChanged;

  final ChannelMarkerStyleStore _store = ChannelMarkerStyleStore();

  Map<String, ChannelMarkerStyle> _styles = const {};
  Map<String, int> _order = const {};
  String _scope = '';

  /// Reloads when the connected node changes. Cheap and synchronous, so it can
  /// be called from `build` — the store reads straight out of prefs.
  void syncTo(String publicKeyHex) {
    if (publicKeyHex.isEmpty || _scope == publicKeyHex) return;
    _store.setPublicKeyHex = publicKeyHex;
    _scope = publicKeyHex;
    _styles = _store.load();
  }

  /// Records the channel order the picker shows, which is also the order
  /// default colours are handed out in. Cheap enough to call from `build`.
  void trackChannels(Iterable<Channel> channels) {
    final ordered = orderChannels(channels);
    _order = {
      for (var i = 0; i < ordered.length; i++)
        ChannelMarkerStyleStore.normalizeChannelName(ordered[i].name): i,
    };
  }

  /// A stored style wins; otherwise the default for this channel's position.
  ChannelMarkerStyle styleFor(String? channelName) {
    if (channelName == null) return ChannelMarkerStyle.fallback;
    final key = ChannelMarkerStyleStore.normalizeChannelName(channelName);
    final stored = _styles[key];
    if (stored != null) return stored;
    return ChannelMarkerStyle.defaultsFor(_order[key] ?? 0);
  }

  /// Direct-chat markers have no channel and are never hidden here.
  bool isVisible(String? channelName) =>
      channelName == null || styleFor(channelName).enabled;

  Future<void> update(String channelName, ChannelMarkerStyle style) async {
    final updated = Map<String, ChannelMarkerStyle>.from(_styles);
    updated[ChannelMarkerStyleStore.normalizeChannelName(channelName)] = style;
    _styles = updated;
    onChanged?.call();
    await _store.save(updated);
  }

  /// Channels offered in the picker: Public first, then alphabetical.
  static List<Channel> orderChannels(Iterable<Channel> channels) {
    final result = channels.where((c) => !c.isEmpty).toList();
    result.sort((a, b) {
      if (a.isPublicChannel != b.isPublicChannel) {
        return a.isPublicChannel ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  static String displayName(Channel channel) =>
      channel.name.isEmpty ? 'Channel ${channel.index}' : channel.name;
}

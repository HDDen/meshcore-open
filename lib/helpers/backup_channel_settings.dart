import 'dart:convert';

import '../models/channel.dart';
import '../storage/region_store.dart' show kUnscopedRegion;

enum BackupChannelOption {
  smaz('channel_smaz_', codecFlag: true),
  mcmp('channel_mcmp_', codecFlag: true),
  mcmpVersion('channel_mcmp_version_', codec: true),
  mcmpUseSign('channel_mcmp_use_sign_', codec: true),
  mcotxt('channel_mcotxt_', codecFlag: true),
  mcotxtPlainWhenSmaller('channel_mcotxt_plain_when_smaller_', codec: true),
  cyr2lat('channel_cyr2lat_', codecFlag: true),
  cyr2latProfile('channel_cyr2lat_', infix: 'profile_', codec: true),
  sendingDelay('channel_sending_delay_'),
  urlImages('channel_url_images_'),
  region('channel_region_');

  const BackupChannelOption(
    this.prefix, {
    this.infix = '',
    this.codec = false,
    this.codecFlag = false,
  });

  final String prefix;
  final String infix;
  final bool codec;
  final bool codecFlag;
  bool get isCodecOption => codec || codecFlag;

  bool isUpstreamValue(Object value) => switch (this) {
    smaz || cyr2lat || cyr2latProfile || urlImages => true,
    region => value != kUnscopedRegion,
    _ => false,
  };

  String localPrefix(String scope) => '$prefix$scope$infix';
  String backupPrefix(String scope) => '$prefix${scope}_$infix';

  Object? decode(Object? value) => switch (this) {
    mcmpVersion => value is int && (value == 2 || value == 3) ? value : null,
    cyr2latProfile => value is String && value.isNotEmpty ? value : null,
    region => value is String ? value.trim() : null,
    _ => value is bool ? value : null,
  };
}

typedef BackupChannelSettingKey = (String id, BackupChannelOption option);
typedef BackupChannelBinding = ({int slot, String id, String name});
typedef BackupChannelWriteKey = (BackupChannelBinding channel, BackupChannelOption option);

/// The destination preferences are name-keyed. Exclude ambiguous PSK IDs
/// and names before associating a preference with a physical channel.
Map<String, BackupChannelBinding> backupChannelBindings(Iterable<Channel> channels) {
  final byId = <String, BackupChannelBinding>{};
  final seenIds = <String>{};
  final seenNames = <String>{};
  final duplicateIds = <String>{};
  final duplicateNames = <String>{};
  for (final channel in channels) {
    final id = channel.storageId;
    final name = channel.name.trim();
    if (id != null && !seenIds.add(id)) duplicateIds.add(id);
    if (name.isEmpty) continue;
    final normalizedName = name.toLowerCase();
    if (!seenNames.add(normalizedName)) duplicateNames.add(normalizedName);
    if (id == null) continue;
    byId[id] = (slot: channel.index, id: id, name: name);
  }
  byId.removeWhere((id, binding) =>
      duplicateIds.contains(id) || duplicateNames.contains(binding.name.toLowerCase()));
  return byId;
}

class BackupChannelSettings {
  static const extensionSection = 'mcoaChannelSettings';

  BackupChannelSettings(Map<BackupChannelSettingKey, Object> values, Iterable<String> order)
    : values = Map.unmodifiable(values),
      order = List.unmodifiable(order);

  factory BackupChannelSettings.fromPreferences(
    Map<String, Object?> preferences,
    String scope,
  ) {
    final values = <BackupChannelSettingKey, Object>{};
    for (final entry in preferences.entries) {
      for (final option in BackupChannelOption.values) {
        final prefix = option.backupPrefix(scope);
        if (!entry.key.startsWith(prefix)) continue;
        final id = entry.key.substring(prefix.length).toLowerCase();
        if (!_channelId.hasMatch(id)) continue;
        final value = option.decode(entry.value);
        if (value == null) continue;
        final key = (id, option);
        if (values.containsKey(key) && values[key] != value) {
          throw const FormatException('Ambiguous backup channel setting');
        }
        values[key] = value;
        break;
      }
    }
    final rawOrder = preferences['channel_order_$scope'];
    final Object? decoded;
    try {
      decoded = rawOrder is String ? jsonDecode(rawOrder) : rawOrder;
    } on FormatException {
      throw const FormatException('Invalid backup channel order');
    }
    final order = <String>{
      if (decoded is List<Object?>)
        for (final id in decoded.whereType<String>())
          if (_channelId.hasMatch(id.toLowerCase())) id.toLowerCase(),
    };
    return BackupChannelSettings(values, order);
  }

  static final _channelId = RegExp(r'^[0-9a-f]{16}$');
  final Map<BackupChannelSettingKey, Object> values;
  final List<String> order;
  bool get isEmpty => values.isEmpty && order.isEmpty;

  Map<String, Object> toPreferences(String scope, {bool forkOnly = false}) => {
    for (final MapEntry(key: (id, option), :value) in values.entries)
      if (option.isUpstreamValue(value) != forkOnly)
        '${option.backupPrefix(scope)}$id': value,
    if (!forkOnly && order.isNotEmpty) 'channel_order_$scope': jsonEncode(order),
  };

  BackupChannelSettingsPreview preview({
    required Object session,
    required Map<String, BackupChannelBinding> bindings,
    required Map<BackupChannelSettingKey, Object> current,
    required bool canRestoreOrder,
    required bool Function(String) hasCyr2LatProfile,
    required bool Function(String) hasRegion,
  }) {
    final configuredCodecs = {
      for (final (id, option) in current.keys)
        if (option.isCodecOption) id,
    };
    final enabledCodecCounts = <String, int>{};
    for (final MapEntry(key: (id, option), :value) in values.entries) {
      if (option.codecFlag && value == true) {
        enabledCodecCounts.update(id, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final writes = <BackupChannelWriteKey, Object>{};
    for (final MapEntry(key: (id, option), :value) in values.entries) {
      final channel = bindings[id];
      if (channel == null || current.containsKey((id, option))) continue;
      if (option.isCodecOption &&
          (configuredCodecs.contains(id) || (enabledCodecCounts[id] ?? 0) > 1)) {
        continue;
      }
      if (option == BackupChannelOption.cyr2latProfile && !hasCyr2LatProfile(value as String)) {
        continue;
      }
      if (option == BackupChannelOption.region && !hasRegion(value as String)) continue;
      writes[(channel, option)] = value;
    }
    final orderBindings = [
      if (canRestoreOrder)
        for (final id in order) ?bindings[id],
    ];
    return BackupChannelSettingsPreview(
      session: session,
      source: this,
      writes: Map.unmodifiable(writes),
      order: List.unmodifiable(orderBindings),
      skipped: values.length - writes.length +
          (order.isNotEmpty && orderBindings.isEmpty ? 1 : 0),
    );
  }
}

class BackupChannelSettingsPreview {
  const BackupChannelSettingsPreview({
    required this.session,
    required this.source,
    required this.writes,
    required this.order,
    required this.skipped,
  });

  final Object session;
  final BackupChannelSettings source;
  final Map<BackupChannelWriteKey, Object> writes;
  final List<BackupChannelBinding> order;
  final int skipped;
  int get count => writes.length + (order.isEmpty ? 0 : 1);
}

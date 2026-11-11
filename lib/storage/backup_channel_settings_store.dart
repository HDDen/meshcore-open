import '../helpers/backup_channel_settings.dart';
import '../models/channel.dart';
import 'channel_name_keyed_store.dart';
import 'prefs_manager.dart';

/// Backup reads the same name keys as the active channel stores, without
/// triggering migration. Export reads only settings owned by this node.
class BackupChannelSettingsStore with ChannelNameKeyedStore {
  BackupChannelSettingsStore(this.scope, Iterable<Channel> channels) {
    replaceChannels(channels);
  }

  final String scope;

  Map<BackupChannelSettingKey, Object> read(
    Iterable<BackupChannelBinding> bindings, {
    required bool includeInherited,
  }) {
    final prefs = PrefsManager.instance;
    final values = <BackupChannelSettingKey, Object>{};
    for (final channel in bindings) {
      for (final option in BackupChannelOption.values) {
        final prefix = option.localPrefix(scope);
        final keys = includeInherited
            ? [
                ChannelNameKeyedStore.nameStorageKey(prefix, channel.name),
                ...channelInheritedKeys(
                  keyPrefix: prefix,
                  scope: scope,
                  channelIndex: channel.slot,
                ),
              ]
            : channelStorageKeys(prefix, channel.slot);
        for (final key in keys) {
          final value = prefs.get(key);
          if (value == null) continue;
          final decoded = includeInherited ? value : option.decode(value);
          if (decoded != null) values[(channel.id, option)] = decoded;
          break;
        }
      }
    }
    return values;
  }

  Future<bool> writeIfMissing(BackupChannelWriteKey target, Object value) async {
    final (channel, option) = target;
    final key = ChannelNameKeyedStore.nameStorageKey(option.localPrefix(scope), channel.name);
    final prefs = PrefsManager.instance;
    if (prefs.containsKey(key)) return false;
    return switch (value) {
      final bool flag => prefs.setBool(key, flag),
      final int number => prefs.setInt(key, number),
      final String text => prefs.setString(key, text),
      _ => throw ArgumentError('Invalid backup channel setting'),
    };
  }
}

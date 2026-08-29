import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_manager.dart';

enum MessageHistoryKind { direct, channel }

class MessageHistoryMigrationConflict implements Exception {
  const MessageHistoryMigrationConflict(this.dataPath);

  final String dataPath;

  @override
  String toString() =>
      'Message history migration cannot continue because legacy history and '
      'separate history files both exist.';
}

class MessageHistoryStorage {
  MessageHistoryStorage._();

  static final MessageHistoryStorage instance = MessageHistoryStorage._();

  static const String directFileName = 'direct_message_history.json';
  static const String channelFileName = 'channel_message_history.json';
  static const String _directPrefix = 'messages_';
  static const String _channelPrefix = 'channel_messages_';
  static final RegExp _directKeyPattern = RegExp(
    r'^messages_(?:[0-9a-fA-F]{10}(?:[0-9a-fA-F]{64})?|[0-9a-fA-F]{64})$',
  );
  static final RegExp _channelKeyPattern = RegExp(
    r'^channel_messages_(?:[0-9a-fA-F]{10}(?:\d+|name_[A-Za-z0-9_-]+)|\d+)$',
  );

  _JsonHistoryFile? _directFile;
  _JsonHistoryFile? _channelFile;
  bool _initialized = false;

  bool get usesSeparateFiles =>
      !Platform.isAndroid &&
      !Platform.isIOS &&
      (Platform.isWindows || Platform.isLinux);

  Future<bool> initializeAndMigrate({
    Future<void> Function()? onMigrationStarted,
  }) async {
    if (_initialized) return false;
    if (!usesSeparateFiles) {
      _initialized = true;
      return false;
    }

    final directory = await getApplicationSupportDirectory();
    final directFile = _JsonHistoryFile(
      File('${directory.path}${Platform.pathSeparator}$directFileName'),
    );
    final channelFile = _JsonHistoryFile(
      File('${directory.path}${Platform.pathSeparator}$channelFileName'),
    );
    final prefs = PrefsManager.instance;
    final directKeys = prefs
        .getKeys()
        .where(_directKeyPattern.hasMatch)
        .toList();
    final channelKeys = prefs
        .getKeys()
        .where(_channelKeyPattern.hasMatch)
        .toList();
    final hasLegacyHistory = directKeys.isNotEmpty || channelKeys.isNotEmpty;
    final hasDirectFile = await directFile.exists();
    final hasChannelFile = await channelFile.exists();

    if (hasLegacyHistory && (hasDirectFile || hasChannelFile)) {
      throw MessageHistoryMigrationConflict(directory.path);
    }

    if (hasLegacyHistory) {
      await onMigrationStarted?.call();
      await directFile.createFromLegacy(
        _readLegacyEntries(prefs, directKeys),
      );
      await channelFile.createFromLegacy(
        _readLegacyEntries(prefs, channelKeys),
      );

      // Keep removal sequential. The preferences plugin rewrites its JSON file
      // per mutation; concurrent removals can corrupt that file.
      for (final key in [...directKeys, ...channelKeys]) {
        await prefs.remove(key);
      }
      _directFile = directFile;
      _channelFile = channelFile;
      _initialized = true;
      return true;
    }

    await directFile.loadOrCreate();
    await channelFile.loadOrCreate();
    _directFile = directFile;
    _channelFile = channelFile;
    _initialized = true;
    return false;
  }

  Map<String, String> _readLegacyEntries(
    SharedPreferences prefs,
    Iterable<String> keys,
  ) {
    final result = <String, String>{};
    for (final key in keys) {
      final value = prefs.getString(key);
      if (value == null) {
        throw FormatException('History entry is not a string: $key');
      }
      result[key] = value;
    }
    return result;
  }

  Future<Never> restartAfterMigration() async {
    if (!usesSeparateFiles) {
      throw StateError('Automatic restart is only available on desktop.');
    }
    await Process.start(
      Platform.resolvedExecutable,
      Platform.executableArguments,
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  String? getString(MessageHistoryKind kind, String key) {
    _requireInitialized();
    if (!usesSeparateFiles) return PrefsManager.instance.getString(key);
    return _fileFor(kind).getString(key);
  }

  Set<String> getKeys(MessageHistoryKind kind) {
    _requireInitialized();
    if (!usesSeparateFiles) {
      final prefix = kind == MessageHistoryKind.direct
          ? _directPrefix
          : _channelPrefix;
      return PrefsManager.instance
          .getKeys()
          .where((key) => key.startsWith(prefix))
          .toSet();
    }
    return _fileFor(kind).keys;
  }

  Future<void> setString(
    MessageHistoryKind kind,
    String key,
    String value,
  ) async {
    _requireInitialized();
    if (!usesSeparateFiles) {
      await PrefsManager.instance.setString(key, value);
      return;
    }
    await _fileFor(kind).setString(key, value);
  }

  Future<void> remove(MessageHistoryKind kind, String key) async {
    _requireInitialized();
    if (!usesSeparateFiles) {
      await PrefsManager.instance.remove(key);
      return;
    }
    await _fileFor(kind).remove(key);
  }

  _JsonHistoryFile _fileFor(MessageHistoryKind kind) {
    return switch (kind) {
      MessageHistoryKind.direct => _directFile!,
      MessageHistoryKind.channel => _channelFile!,
    };
  }

  void _requireInitialized() {
    if (!_initialized) {
      throw StateError('MessageHistoryStorage is not initialized.');
    }
  }
}

class _JsonHistoryFile {
  _JsonHistoryFile(this.file);

  static const int _formatVersion = 1;

  final File file;
  final Map<String, Object?> _entries = {};
  Future<void> _writeTail = Future.value();

  Future<bool> exists() async {
    return await file.exists() ||
        await File('${file.path}.previous').exists() ||
        await File('${file.path}.tmp').exists();
  }

  Set<String> get keys => Set.unmodifiable(_entries.keys);

  String? getString(String key) {
    final value = _entries[key];
    return value == null ? null : jsonEncode(value);
  }

  Future<void> loadOrCreate() async {
    await _recoverInterruptedWrite();
    if (!await file.exists()) {
      await createFromLegacy(const {});
      return;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != _formatVersion ||
        decoded['entries'] is! Map<String, dynamic>) {
      throw const FormatException('Unsupported message history file format');
    }
    _entries
      ..clear()
      ..addAll(decoded['entries'] as Map<String, dynamic>);
  }

  Future<void> _recoverInterruptedWrite() async {
    if (await file.exists()) return;
    final previous = File('${file.path}.previous');
    if (await previous.exists()) {
      await previous.rename(file.path);
      return;
    }
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) {
      await temporary.rename(file.path);
    }
  }

  Future<void> createFromLegacy(Map<String, String> legacyEntries) async {
    _entries
      ..clear()
      ..addEntries(
        legacyEntries.entries.map(
          (entry) {
            final decoded = jsonDecode(entry.value);
            if (decoded is! List) {
              throw FormatException(
                'History entry is not a JSON array: ${entry.key}',
              );
            }
            return MapEntry(entry.key, decoded);
          },
        ),
      );
    await _persist();
  }

  Future<void> setString(String key, String value) {
    return _enqueue(() async {
      _entries[key] = jsonDecode(value);
      await _persist();
    });
  }

  Future<void> remove(String key) {
    return _enqueue(() async {
      if (_entries.remove(key) == null) return;
      await _persist();
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _writeTail.then((_) => operation());
    _writeTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<void> _persist() async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    final previous = File('${file.path}.previous');
    await temporary.writeAsString(
      jsonEncode({'version': _formatVersion, 'entries': _entries}),
      flush: true,
    );
    if (await previous.exists()) await previous.delete();
    if (await file.exists()) await file.rename(previous.path);
    try {
      await temporary.rename(file.path);
      if (await previous.exists()) await previous.delete();
    } catch (_) {
      if (!await file.exists() && await previous.exists()) {
        await previous.rename(file.path);
      }
      rethrow;
    }
  }
}

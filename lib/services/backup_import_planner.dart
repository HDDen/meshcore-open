import 'dart:convert';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import '../helpers/backup_channel_restore.dart';
import '../models/channel.dart';
import '../models/contact.dart';
import 'backup_file_codec.dart';

/// Radio lists recovered from a backup before choosing a restore destination.
class BackupImportPlan {
  BackupImportPlan._({
    required this.isOfficial,
    required this.sourcePublicKey,
    required List<Contact>? contacts,
    required List<Channel>? channels,
  }) : contacts = contacts == null ? null : List.unmodifiable(contacts),
       channels = channels == null ? null : List.unmodifiable(channels);

  final bool isOfficial;
  final String? sourcePublicKey;

  /// Null means that the file supplies no list. An empty list is explicit.
  final List<Contact>? contacts;
  final List<Channel>? channels;

  /// Keeps the node's slot for an existing PSK and proposes the backup name.
  List<BackupChannelDecision> resolveChannels({
    required Iterable<Channel> destination,
    required int capacity,
    required Set<int> unconfirmedSlots,
  }) => resolveBackupChannels(
    channels ?? const [],
    destination: destination,
    capacity: capacity,
    unconfirmedSlots: unconfirmedSlots,
  );
}

class BackupImportPlanner {
  const BackupImportPlanner();

  Future<BackupImportPlan> inspect(
    String contents, {
    required String password,
  }) async {
    final document = _readDocument(contents);
    final official = _isOfficial(document);
    final payload = official
        ? document
        : await const BackupFileCodec().decodeEnvelope(
            document,
            password: password,
          );
    final rawKey = payload[official ? 'public_key' : 'sourcePublicKey'];
    final publicKey = !official && (rawKey == null || rawKey == '')
        ? null
        : pubKeyToHex(_readHex(rawKey, length: pubKeySize));
    final contacts = official
        ? _officialList(payload, 'contacts')
        : _upstreamList(payload, 'contacts', publicKey);
    final channels = official
        ? _officialList(payload, 'channels')
        : _upstreamList(payload, 'channels', publicKey);

    final contactKeys = <String>{};
    final channelSlots = <int>{};
    return BackupImportPlan._(
      isOfficial: official,
      sourcePublicKey: publicKey,
      contacts: contacts == null
          ? null
          : [
              for (final row in contacts)
                _readContact(_readObject(row), official, contactKeys),
            ],
      channels: channels == null
          ? null
          : [
              for (final (index, row) in channels.indexed)
                if (!official || row != null)
                  _readChannel(_readObject(row), official, index, channelSlots),
            ].where((channel) => !channel.isEmpty).toList(),
    );
  }

  static Map<String, Object?> _readDocument(String contents) {
    try {
      return _readObject(jsonDecode(contents));
    } on FormatException {
      // Some official exports omit the comma between name and public_key.
      final repaired = contents.replaceFirstMapped(
        RegExp(r'("name"\s*:\s*"(?:\\.|[^"\\])*"\s*)(?="public_key"\s*:)'),
        (match) => '${match[1]},',
      );
      if (repaired != contents) {
        try {
          final document = _readObject(jsonDecode(repaired));
          if (_isOfficial(document)) return document;
        } on FormatException {
          // The original input can contain secrets.
        }
      }
      throw const FormatException('Invalid backup JSON');
    }
  }

  static bool _isOfficial(Map<String, Object?> document) =>
      !document.containsKey('format') && document.containsKey('public_key');

  static List<Object?>? _officialList(
    Map<String, Object?> payload,
    String key,
  ) => payload.containsKey(key) ? _readList(payload[key]) : null;

  static List<Object?>? _upstreamList(
    Map<String, Object?> payload,
    String name,
    String? publicKey,
  ) {
    if (!_readList(payload['items']).contains(name)) return null;
    final section = _readObject(payload['sections'])[name];
    if (section == null) return null;
    final rawPreferences = _readObject(section)['preferences'];
    if (rawPreferences == null) return null;
    final preferences = _readObject(rawPreferences);
    if (preferences.isEmpty) return null;
    if (publicKey == null) {
      throw const FormatException('Missing backup source public key');
    }
    final key = '$name${publicKey.substring(0, 10).toLowerCase()}';
    final entries = preferences.entries.where(
      (entry) => entry.key.toLowerCase() == key,
    );
    if (entries.isEmpty) return null;
    if (entries.length != 1) {
      throw const FormatException('Ambiguous backup list');
    }
    final value = entries.single.value;
    if (value is! String) return _readList(value);
    try {
      return _readList(jsonDecode(value));
    } on FormatException {
      throw const FormatException('Invalid backup list');
    }
  }

  static Contact _readContact(
    Map<String, Object?> row,
    bool official,
    Set<String> keys,
  ) {
    final key = official
        ? _readHex(row['public_key'], length: pubKeySize)
        : _readBase64(row['publicKey'], maxLength: pubKeySize);
    if (key.length != pubKeySize || !keys.add(pubKeyToHex(key))) {
      throw const FormatException('Invalid or duplicate backup contact key');
    }
    final customName = row['custom_name'];
    final name = official && customName is String && customName.isNotEmpty
        ? customName
        : row['name'];
    final path = official
        ? _officialPath(row['out_path_list'])
        : _upstreamPath(row);
    final lastSeen = row[official ? 'last_advert' : 'lastSeen'];
    return Contact(
      publicKey: key.asUnmodifiableView(),
      name: _readName(name ?? ''),
      type: _readInt(row['type'] ?? 0),
      flags: _readInt(row['flags'] ?? 0),
      pathLength: path.hops,
      pathHashWidth: path.width,
      path: path.bytes.asUnmodifiableView(),
      latitude: _readCoordinate(row['latitude'], 90),
      longitude: _readCoordinate(row['longitude'], 180),
      lastSeen: _readTime(lastSeen ?? 0, seconds: official),
      lastModified: _readOptionalTime(
        row[official ? 'last_modified' : 'lastModified'],
        seconds: official,
      ),
    );
  }

  static Channel _readChannel(
    Map<String, Object?> row,
    bool official,
    int position,
    Set<int> slots,
  ) {
    final index = _readInt(official ? position : row['index']);
    if (!slots.add(index)) throw const FormatException('Duplicate backup slot');
    final name = _readName(row['name']);
    final psk = official
        ? _readHex(row['secret'], length: 16)
        : _readBase64(row['psk'], maxLength: 16);
    if (psk.length != 16 || (psk.every((byte) => byte == 0) && name.isNotEmpty)) {
      throw const FormatException('Invalid backup channel secret');
    }
    return Channel(index: index, name: name, psk: psk.asUnmodifiableView());
  }

  static ({int hops, int width, Uint8List bytes}) _officialPath(Object? value) {
    if (value == null || value == '') {
      return (hops: value == null ? -1 : 0, width: 1, bytes: Uint8List(0));
    }
    if (value is! String || value.length > maxPathSize * 3) {
      throw const FormatException('Invalid backup contact path');
    }
    final hashes = value.split(',');
    final width = hashes.first.length ~/ 2;
    if (width < 1 ||
        width > maxPathHashWidth ||
        hashes.length > 63 ||
        hashes.length * width > maxPathSize) {
      throw const FormatException('Invalid backup contact path');
    }
    final bytes = Uint8List.fromList([
      for (final hash in hashes) ..._readHex(hash, length: width),
    ]);
    return (hops: hashes.length, width: width, bytes: bytes);
  }

  static ({int hops, int width, Uint8List bytes}) _upstreamPath(
    Map<String, Object?> row,
  ) {
    final raw = _readInt(row['pathLength'] ?? -1, min: -1);
    final bytes = _readBase64(row['path'] ?? '', maxLength: maxPathSize);
    if (raw == -1 || raw == 255) {
      return (hops: -1, width: 1, bytes: Uint8List(0));
    }
    final hops = raw & 63;
    final width = raw >= 64
        ? (raw >> 6) + 1
        : _readInt(
            row['pathHashWidth'] ?? Contact.inferPathHashWidth(hops, bytes.length),
            min: 1,
            max: maxPathHashWidth,
          );
    if (width > maxPathHashWidth || bytes.length != hops * width) {
      throw const FormatException('Invalid backup contact path');
    }
    return (hops: hops, width: width, bytes: bytes);
  }

  static final _nonHex = RegExp(r'[^0-9a-fA-F]');

  static Uint8List _readHex(Object? value, {required int length}) {
    if (value is! String ||
        value.length != length * 2 ||
        _nonHex.hasMatch(value)) {
      throw const FormatException('Invalid backup hex value');
    }
    return hex2Uint8List(value);
  }

  static Uint8List _readBase64(Object? value, {required int maxLength}) {
    const invalid = FormatException('Invalid backup binary value');
    if (value is! String || value.length > ((maxLength + 2) ~/ 3) * 4) {
      throw invalid;
    }
    try {
      final bytes = base64Decode(value);
      if (bytes.length <= maxLength) return bytes;
    } on FormatException {
      throw invalid;
    }
    throw invalid;
  }

  static String _readName(Object? value) {
    if (value is! String ||
        value.contains('\u0000') ||
        value.length >= maxNameSize ||
        utf8.encode(value).length >= maxNameSize) {
      throw const FormatException('Invalid backup radio name');
    }
    return value;
  }

  static int _readInt(Object? value, {int min = 0, int max = 255}) {
    final number = value is String ? int.tryParse(value, radix: 10) : value;
    if (number is! int || number < min || number > max) {
      throw const FormatException('Invalid backup integer');
    }
    return number;
  }

  static double? _readCoordinate(Object? value, int limit) {
    if (value == null) return null;
    final number = value is String ? double.tryParse(value) : value;
    if (number is! num || !number.isFinite || number.abs() > limit) {
      throw const FormatException('Invalid backup coordinate');
    }
    return number.toDouble();
  }

  static DateTime? _readOptionalTime(Object? value, {required bool seconds}) =>
      value == null ? null : _readTime(value, seconds: seconds);

  static DateTime _readTime(Object value, {required bool seconds}) {
    const maxSeconds = 0xffffffff;
    final ticks = _readInt(
      value,
      max: seconds ? maxSeconds : maxSeconds * 1000 + 999,
    );
    return DateTime.fromMillisecondsSinceEpoch(seconds ? ticks * 1000 : ticks);
  }

  static Map<String, Object?> _readObject(Object? value) {
    if (value is Map<String, Object?>) return value;
    throw const FormatException('Invalid backup object');
  }

  static List<Object?> _readList(Object? value) {
    if (value is List<Object?>) return value;
    throw const FormatException('Invalid backup list');
  }
}

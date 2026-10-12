import 'dart:convert';
import 'dart:typed_data';

import '../models/contact.dart';
import '../utils/app_logger.dart';
import 'message_history_storage.dart';
import 'prefs_manager.dart';

/// Nodes the app has heard of but no radio stores. The list is one for the
/// whole app, not one per node like the other stores: only the app knows
/// these nodes, whichever radio it heard them through.
///
/// It lives in the `discovered_contacts` table of the message-history
/// database, one row per node holding the JSON [_toJson] writes. The web
/// build, which has no database, and a process that never opened it, such as
/// a unit test, keep the whole list in preferences under the same name.
class ContactDiscoveryStore {
  static const String _keyPrefix = 'discovered_contacts';

  /// The rows the database holds, as the very contacts last loaded or
  /// written. The connector saves its whole list on every advert it hears,
  /// and an update always replaces a contact rather than changing it, so a
  /// save writes only the contacts that are not identical to these. Null
  /// until the first load, and nothing is deleted before it: the list handed
  /// in then need not hold what is stored.
  Map<String, Contact>? _stored;

  /// Database writes run one after another, each measured against what the
  /// one before it left.
  Future<void> _writes = Future.value();

  Future<List<Contact>> loadContacts() async {
    final storage = MessageHistoryStorage.instance;
    if (!storage.hasDatabase) {
      return _decodeList(PrefsManager.instance.getString(_keyPrefix));
    }
    await _writes;
    final contacts = <Contact>[];
    for (final row in await storage.loadDiscoveredContacts()) {
      try {
        contacts.add(_fromJson(jsonDecode(row) as Map<String, dynamic>));
      } catch (e) {
        appLogger.warn('Skipping malformed discovered contact: $e');
      }
    }
    _stored = {for (final contact in contacts) contact.publicKeyHex: contact};
    return contacts;
  }

  Future<void> saveContacts(List<Contact> contacts) {
    if (!MessageHistoryStorage.instance.hasDatabase) {
      final jsonList = contacts.map(_toJson).toList();
      return PrefsManager.instance.setString(_keyPrefix, jsonEncode(jsonList));
    }
    // The caller hands in its live list, which may change before this write
    // gets its turn.
    final snapshot = List<Contact>.of(contacts);
    final write = _writes.then((_) => _writeRows(snapshot));
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<void> _writeRows(List<Contact> contacts) async {
    final stored = _stored;
    final next = {
      for (final contact in contacts) contact.publicKeyHex: contact,
    };
    await MessageHistoryStorage.instance.writeDiscoveredContacts(
      upserts: {
        for (final entry in next.entries)
          if (!identical(stored?[entry.key], entry.value))
            entry.key: jsonEncode(_toJson(entry.value)),
      },
      deleteKeys: [
        if (stored != null)
          for (final key in stored.keys)
            if (!next.containsKey(key)) key,
      ],
    );
    _stored = next;
  }

  List<Contact> _decodeList(String? jsonStr) {
    if (jsonStr == null) return [];
    final List<dynamic> jsonList;
    try {
      jsonList = jsonDecode(jsonStr) as List<dynamic>;
    } catch (e) {
      appLogger.warn('Stored discovered contacts are unreadable: $e');
      return [];
    }
    final contacts = <Contact>[];
    for (final entry in jsonList) {
      try {
        contacts.add(_fromJson(entry as Map<String, dynamic>));
      } catch (e) {
        appLogger.warn('Skipping malformed discovered contact: $e');
      }
    }
    return contacts;
  }

  /// Exports [contacts] for sharing. Routing paths are left out: a path is
  /// the route from this radio and is meaningless on another one.
  String exportContactsJson(List<Contact> contacts) {
    final jsonList = contacts.map((contact) {
      final json = _toJson(contact);
      for (final key in _pathKeys) {
        json.remove(key);
      }
      return json;
    }).toList();
    return jsonEncode(jsonList);
  }

  static const List<String> _pathKeys = [
    'pathLength',
    'path',
    'pathHashWidth',
    'pathOverride',
    'pathOverrideBytes',
  ];

  /// Merges an export file into [existingContacts], each entry on its own:
  /// a malformed entry is counted as invalid instead of failing the file.
  ///
  /// Skips radio contacts ([knownContactKeys]), discovered contacts already
  /// present (they are fresher), duplicates within the file, and the
  /// connected radio's own key. Imported paths are dropped (they belong to the
  /// exporting radio) and timestamps are clamped to [now].
  ///
  /// Throws [FormatException] when the file is not a JSON list.
  DiscoveredContactsImportResult importContactsJson({
    required String json,
    required List<Contact> existingContacts,
    required Set<String> knownContactKeys,
    String? selfPublicKeyHex,
    DateTime? now,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Not valid JSON: $e');
    }
    if (decoded is! List) {
      throw const FormatException('Expected a list of contacts');
    }

    final clampTo = now ?? DateTime.now();
    final seenKeys = {for (final c in existingContacts) c.publicKeyHex};
    var imported = 0;
    var skipped = 0;
    var invalid = 0;

    for (final entry in decoded) {
      final Contact contact;
      try {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Entry is not an object');
        }
        contact = _fromJson(entry, importing: true, clampTo: clampTo);
        if (contact.publicKey.length != _pubKeySize) {
          throw const FormatException('Public key must be 32 bytes');
        }
      } catch (e) {
        appLogger.warn('Skipping invalid imported discovered contact: $e');
        invalid++;
        continue;
      }

      final keyHex = contact.publicKeyHex;
      if (keyHex == selfPublicKeyHex ||
          knownContactKeys.contains(keyHex) ||
          !seenKeys.add(keyHex)) {
        skipped++;
        continue;
      }
      existingContacts.add(contact);
      imported++;
    }

    return DiscoveredContactsImportResult(
      total: decoded.length,
      imported: imported,
      skipped: skipped,
      invalid: invalid,
    );
  }

  static const int _pubKeySize = 32;

  Map<String, dynamic> _toJson(Contact contact) {
    return {
      'publicKey': base64Encode(contact.publicKey),
      'name': contact.name,
      'type': contact.type,
      'flags': contact.flags,
      'pathLength': contact.pathLength,
      'path': base64Encode(contact.path),
      'pathHashWidth': contact.pathHashWidth,
      'pathOverride': contact.pathOverride,
      'pathOverrideBytes': contact.pathOverrideBytes != null
          ? base64Encode(contact.pathOverrideBytes!)
          : null,
      'latitude': contact.latitude,
      'longitude': contact.longitude,
      'lastSeen': contact.lastSeen.millisecondsSinceEpoch,
      'lastModified': contact.lastModified?.millisecondsSinceEpoch,
      'lastMessageAt': contact.lastMessageAt.millisecondsSinceEpoch,
      'hasMessages': contact.hasMessages,
      'isActive': contact.isActive,
      'rawPacket': contact.rawPacket != null
          ? base64Encode(contact.rawPacket!)
          : null,
    };
  }

  Contact _fromJson(
    Map<String, dynamic> json, {
    bool importing = false,
    DateTime? clampTo,
  }) {
    int? clampMs(int? ms) {
      if (ms == null || clampTo == null) return ms;
      final limit = clampTo.millisecondsSinceEpoch;
      return ms > limit ? limit : ms;
    }

    final lastSeenMs = clampMs((json['lastSeen'] as num?)?.toInt()) ?? 0;
    final lastMessageMs = clampMs((json['lastMessageAt'] as num?)?.toInt());
    final lastModifiedMs = clampMs((json['lastModified'] as num?)?.toInt());

    // An imported path is the exporting radio's route: never reuse it.
    final rawPathLength = importing ? -1 : json['pathLength'] as int? ?? -1;
    final rawPath = !importing && json['path'] != null
        ? Uint8List.fromList(base64Decode(json['path'] as String))
        : Uint8List(0);

    int decodedPathLength = rawPathLength;
    Uint8List decodedPath = rawPath;
    int? decodedPathHashWidth = importing
        ? null
        : json['pathHashWidth'] as int?;

    if (rawPathLength == 0xFF || rawPathLength < 0) {
      decodedPathLength = -1;
      decodedPath = Uint8List(0);
    } else if (rawPathLength >= 64) {
      final mode = (rawPathLength & 0xC0) >> 6;
      final hopCount = rawPathLength & 0x3F;
      final width = mode + 1;
      final byteLen = hopCount * width;
      decodedPathLength = hopCount;
      decodedPathHashWidth = width;
      if (byteLen <= rawPath.length) {
        decodedPath = rawPath.sublist(0, byteLen);
      } else {
        decodedPath = Uint8List(0);
      }
    } else if (rawPathLength == 0) {
      decodedPath = Uint8List(0);
    }

    return Contact(
      publicKey: Uint8List.fromList(base64Decode(json['publicKey'] as String)),
      name: json['name'] as String? ?? 'Unknown',
      type: json['type'] as int? ?? 0,
      flags: json['flags'] as int? ?? 0,
      pathLength: decodedPathLength,
      path: decodedPath,
      pathHashWidth:
          decodedPathHashWidth ??
          Contact.inferPathHashWidth(decodedPathLength, decodedPath.length),
      pathOverride: importing ? null : json['pathOverride'] as int?,
      pathOverrideBytes: !importing && json['pathOverrideBytes'] != null
          ? Uint8List.fromList(
              base64Decode(json['pathOverrideBytes'] as String),
            )
          : null,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(lastSeenMs),
      lastModified: lastModifiedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastModifiedMs),
      lastMessageAt: DateTime.fromMillisecondsSinceEpoch(
        lastMessageMs ?? lastSeenMs,
      ),
      hasMessages: json['hasMessages'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? false,
      rawPacket: json['rawPacket'] != null
          ? Uint8List.fromList(base64Decode(json['rawPacket'] as String))
          : null,
    );
  }
}

/// Outcome of [ContactDiscoveryStore.importContactsJson].
class DiscoveredContactsImportResult {
  const DiscoveredContactsImportResult({
    required this.total,
    required this.imported,
    required this.skipped,
    required this.invalid,
  });

  static const empty = DiscoveredContactsImportResult(
    total: 0,
    imported: 0,
    skipped: 0,
    invalid: 0,
  );

  /// Entries in the file.
  final int total;

  /// Entries added as new discovered contacts.
  final int imported;

  /// Valid entries already known (contact, discovered, duplicate, or self).
  final int skipped;

  /// Entries that could not be read.
  final int invalid;
}

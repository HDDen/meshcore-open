import 'dart:convert';
import 'dart:typed_data';

import '../models/contact.dart';
import '../utils/app_logger.dart';
import 'message_history_storage.dart';
import 'node_state.dart';
import 'prefs_manager.dart';

/// The contacts a node holds. They live in the `node_contacts` table of the
/// database, one row per contact holding the JSON [_toJson] writes; the web
/// build, and a process that never opened the database such as a unit test,
/// keep the whole list in preferences under `contacts<node>` as before.
class ContactStore {
  static const String _keyPrefix = 'contacts';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length > 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';

  /// Per node, the rows the database holds, as the very contacts last loaded
  /// or written. The connector saves its whole list on every advert it hears
  /// and every message it stores, and an update replaces a contact rather
  /// than changing it, so a save writes only the contacts that are not
  /// identical to these, and deletes only against a list a load had seen.
  final Map<String, Map<String, Contact>> _stored = {};

  /// Database writes run one after another, each measured against what the
  /// one before it left.
  Future<void> _writes = Future.value();

  Future<List<Contact>> loadContacts({bool allowLegacyMigration = true}) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot load contacts.');
      return [];
    }
    final storage = MessageHistoryStorage.instance;
    if (!storage.hasDatabase) {
      return _loadFromPreferences(allowLegacyMigration: allowLegacyMigration);
    }
    final node = publicKeyHex;
    await _writes;
    final contacts = <Contact>[];
    for (final row in await storage.loadNodeContacts(node)) {
      try {
        contacts.add(_fromJson(jsonDecode(row) as Map<String, dynamic>));
      } catch (e) {
        appLogger.warn('Skipping malformed stored contact: $e');
      }
    }
    _stored[node] = {for (final contact in contacts) contact.publicKeyHex: contact};
    return contacts;
  }

  Future<void> saveContacts(List<Contact> contacts) {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot save contacts.');
      return Future.value();
    }
    if (!MessageHistoryStorage.instance.hasDatabase) {
      final jsonList = contacts.map(_toJson).toList();
      return PrefsManager.instance.setString(keyFor, jsonEncode(jsonList));
    }
    // The node and the list as they are now: the caller hands in its live
    // list, and the node may change before this write gets its turn.
    final node = publicKeyHex;
    final snapshot = List<Contact>.of(contacts);
    final write = _writes.then((_) => _writeRows(node, snapshot));
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<void> _writeRows(String node, List<Contact> contacts) async {
    final stored = _stored[node];
    final next = {
      for (final contact in contacts) contact.publicKeyHex: contact,
    };
    await MessageHistoryStorage.instance.writeNodeContacts(
      nodeKey: node,
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
    _stored[node] = next;
  }

  Future<List<Contact>> _loadFromPreferences({
    required bool allowLegacyMigration,
  }) async {
    final prefs = PrefsManager.instance;
    String? jsonString = prefs.getString(keyFor);
    if ((jsonString == null || jsonString.isEmpty) && allowLegacyMigration) {
      jsonString = await NodeState.takeOverLegacyPreference(
        legacyKey: _keyPrefix,
        preferenceKey: keyFor,
      );
    }
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    final List<dynamic> jsonList;
    try {
      jsonList = jsonDecode(jsonString) as List<dynamic>;
    } catch (e) {
      appLogger.warn('Stored contacts are unreadable: $e');
      return [];
    }
    final contacts = <Contact>[];
    for (final entry in jsonList) {
      try {
        contacts.add(_fromJson(entry as Map<String, dynamic>));
      } catch (e) {
        appLogger.warn('Skipping malformed stored contact: $e');
      }
    }
    return contacts;
  }

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

  Contact _fromJson(Map<String, dynamic> json) {
    final lastSeenMs = json['lastSeen'] as int? ?? 0;
    final lastMessageMs = json['lastMessageAt'] as int?;
    final lastModifiedMs = json['lastModified'] as int?;

    final rawPathLength = json['pathLength'] as int? ?? -1;
    final rawPath = json['path'] != null
        ? Uint8List.fromList(base64Decode(json['path'] as String))
        : Uint8List(0);

    int decodedPathLength = rawPathLength;
    Uint8List decodedPath = rawPath;
    int? decodedPathHashWidth = json['pathHashWidth'] as int?;

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
      pathOverride: json['pathOverride'] as int?,
      pathOverrideBytes: json['pathOverrideBytes'] != null
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
      isActive: json['isActive'] as bool? ?? true,
      rawPacket: json['rawPacket'] != null
          ? Uint8List.fromList(base64Decode(json['rawPacket'] as String))
          : null,
    );
  }
}

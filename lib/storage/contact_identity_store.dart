import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';
import 'message_history_database.dart' show ContactIdentityRow;
import 'message_history_storage.dart';
import 'prefs_manager.dart';

/// Which public keys are one contact.
///
/// A contact's history is keyed by its public key, so a node re-flashed with
/// a new identity under the same name is a new contact with an empty chat,
/// its history staying under the old key. This table records the keys the
/// user has linked as one person, in groups: a key with no row is a group of
/// itself. The message store reads a contact's history under every key of
/// its group and writes under the contact's own.
///
/// Links are made by hand only (`MeshCoreConnector.linkContactHistory`): a
/// name proves nothing, two people, or one person's phone and base, carry the
/// same one. App-wide, like the channel identities: one person is the same
/// person on every node of the owner.
class ContactIdentities extends ChangeNotifier {
  ContactIdentities._();

  static final ContactIdentities instance = ContactIdentities._();

  /// The preference form, for the web build and a process without the
  /// database: the rows as one JSON array.
  static const String preferenceKey = 'contact_identities_v1';

  final Map<String, int> _groupOf = {};
  final Map<int, Set<String>> _members = {};
  int _nextGroupId = 1;
  int _revision = 0;
  bool _loaded = false;

  /// Moves on every change, for caches keyed on what a contact's history
  /// consists of.
  int get revision => _revision;

  bool get isLoaded => _loaded;

  bool get isEmpty => _groupOf.isEmpty;

  static String normalizeKey(String publicKeyHex) =>
      publicKeyHex.trim().toLowerCase();

  /// Reads the table; the lookups are synchronous afterwards.
  Future<void> load() async {
    _groupOf.clear();
    _members.clear();
    _nextGroupId = 1;
    try {
      final rows = MessageHistoryStorage.instance.hasDatabase
          ? await MessageHistoryStorage.instance.readContactIdentities()
          : _rowsFromPreferences();
      for (final row in rows) {
        _add(row.groupId, normalizeKey(row.publicKeyHex));
      }
    } catch (e) {
      appLogger.warn(
        'Contact identities could not be read: $e',
        tag: 'ContactIdentity',
      );
    }
    _loaded = true;
    _revision++;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTesting() {
    _groupOf.clear();
    _members.clear();
    _nextGroupId = 1;
    _loaded = false;
    _revision++;
  }

  int? groupIdOf(String publicKeyHex) => _groupOf[normalizeKey(publicKeyHex)];

  /// Every key of the contact [publicKeyHex] belongs to, its own first.
  List<String> keysOf(String publicKeyHex) {
    final own = normalizeKey(publicKeyHex);
    final group = _groupOf[own];
    if (group == null) return [own];
    return [own, for (final key in _members[group]!) if (key != own) key];
  }

  bool sameContact(String a, String b) {
    final keyA = normalizeKey(a);
    final keyB = normalizeKey(b);
    if (keyA == keyB) return true;
    final group = _groupOf[keyA];
    return group != null && group == _groupOf[keyB];
  }

  /// Records that [a] and [b] are one contact. Returns false when the table
  /// already said so.
  Future<bool> link(String a, String b) async {
    final keyA = normalizeKey(a);
    final keyB = normalizeKey(b);
    if (keyA == keyB || keyA.isEmpty || keyB.isEmpty) return false;
    final groupA = _groupOf[keyA];
    final groupB = _groupOf[keyB];
    if (groupA != null && groupA == groupB) return false;
    if (groupA == null && groupB == null) {
      final id = _nextGroupId++;
      _add(id, keyA);
      _add(id, keyB);
    } else if (groupA == null) {
      _add(groupB!, keyA);
    } else if (groupB == null) {
      _add(groupA, keyB);
    } else {
      final (keep, drop) = _members[groupA]!.length >= _members[groupB]!.length
          ? (groupA, groupB)
          : (groupB, groupA);
      for (final member in _members.remove(drop)!) {
        _add(keep, member);
      }
    }
    appLogger.info(
      'Contact ${keyA.substring(0, 8)} is now also ${keyB.substring(0, 8)}',
      tag: 'ContactIdentity',
    );
    await _persist();
    return true;
  }

  /// Forgets the whole group of [publicKeyHex]; nothing to do for a key of
  /// itself.
  Future<void> forget(String publicKeyHex) async {
    final group = _groupOf[normalizeKey(publicKeyHex)];
    if (group == null) return;
    for (final member in _members.remove(group)!) {
      _groupOf.remove(member);
    }
    await _persist();
  }

  List<ContactIdentityRow> get rows => [
    for (final entry in _groupOf.entries)
      (groupId: entry.value, publicKeyHex: entry.key),
  ];

  void _add(int groupId, String key) {
    if (key.isEmpty) return;
    _groupOf[key] = groupId;
    (_members[groupId] ??= <String>{}).add(key);
    if (groupId >= _nextGroupId) _nextGroupId = groupId + 1;
  }

  Future<void> _persist() async {
    _revision++;
    notifyListeners();
    try {
      final rows = this.rows;
      if (MessageHistoryStorage.instance.hasDatabase) {
        await MessageHistoryStorage.instance.replaceContactIdentities(rows);
      } else {
        await PrefsManager.instance.setString(
          preferenceKey,
          jsonEncode([
            for (final row in rows) {'g': row.groupId, 'k': row.publicKeyHex},
          ]),
        );
      }
    } catch (e) {
      appLogger.warn(
        'Contact identities could not be written: $e',
        tag: 'ContactIdentity',
      );
    }
  }

  List<ContactIdentityRow> _rowsFromPreferences() {
    final raw = PrefsManager.instance.getString(preferenceKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded)
        if (entry is Map && entry['g'] is int && entry['k'] is String)
          (groupId: entry['g'] as int, publicKeyHex: entry['k'] as String),
    ];
  }
}

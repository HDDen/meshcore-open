import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mco_service/mco_service.dart';

import 'message_history_database.dart';
import 'message_history_storage.dart';
import 'prefs_manager.dart';

class ContactLocationEstimateStore {
  static const String _webPrefsKey = 'contact_location_cache_v1';

  Future<List<McoEstimatedContactLocation>> loadEstimates() async {
    if (kIsWeb) return _loadWebEstimates();
    final rows = await _loadNativeRows();
    final result = <McoEstimatedContactLocation>[];
    for (final row in rows) {
      final estimate = _estimateFromRow(row);
      if (estimate != null) result.add(estimate);
    }
    return List<McoEstimatedContactLocation>.unmodifiable(result);
  }

  Future<void> saveContactLocations({
    required Iterable<McoContactLocationCandidate> candidates,
    required Iterable<McoEstimatedContactLocation> estimates,
    required Iterable<String> clearEstimateKeys,
  }) async {
    if (kIsWeb) {
      await _saveWebEstimates(estimates, clearEstimateKeys);
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final estimatesByKey = {
      for (final estimate in estimates) estimate.publicKeyHex.toLowerCase(): estimate,
    };
    final clearKeys = clearEstimateKeys
        .map((key) => key.toLowerCase())
        .where((key) => key.isNotEmpty)
        .toSet();
    final rows = <ContactLocationCacheUpsert>[];
    for (final candidate in candidates) {
      final key = _hex(candidate.publicKey).toLowerCase();
      final hasRealLocation = candidate.hasRealLocation;
      final estimate = estimatesByKey[key];
      if (!hasRealLocation && estimate == null && !clearKeys.contains(key)) {
        continue;
      }
      rows.add(
        ContactLocationCacheUpsert(
          publicKeyHex: key,
          name: estimate?.name ?? candidate.name,
          contactType: estimate?.contactType ?? candidate.contactType,
          realLatitude: hasRealLocation ? candidate.latitude : null,
          realLongitude: hasRealLocation ? candidate.longitude : null,
          estimatedLatitude: hasRealLocation ? null : estimate?.latitude,
          estimatedLongitude: hasRealLocation ? null : estimate?.longitude,
          anchorPublicKeysJson: jsonEncode(estimate?.anchorPublicKeys ?? const []),
          anchorLatitudesJson: jsonEncode(estimate?.anchorLatitudes ?? const []),
          anchorLongitudesJson: jsonEncode(estimate?.anchorLongitudes ?? const []),
          highConfidence: !hasRealLocation && (estimate?.highConfidence ?? false),
          updatedAtMs: estimate?.updatedAt.millisecondsSinceEpoch ?? nowMs,
        ),
      );
    }
    await _upsertNativeRows(rows);
  }

  Future<void> clearEstimatesForKeys(Iterable<String> publicKeyHexes) async {
    final keys = publicKeyHexes
        .map((key) => key.toLowerCase())
        .where((key) => key.isNotEmpty)
        .toSet();
    if (keys.isEmpty) return;
    if (kIsWeb) {
      final estimates = _loadWebEstimates()
          .where((estimate) => !keys.contains(estimate.publicKeyHex.toLowerCase()))
          .map((estimate) => estimate.toJson())
          .toList();
      await PrefsManager.instance.setString(_webPrefsKey, jsonEncode(estimates));
      return;
    }
    await _clearNativeEstimateKeys(keys);
  }

  Future<List<ContactLocationCacheRecord>> _loadNativeRows() async {
    try {
      return await MessageHistoryStorage.instance.loadContactLocationCache();
    } on StateError {
      return const [];
    }
  }

  Future<void> _upsertNativeRows(List<ContactLocationCacheUpsert> rows) async {
    if (rows.isEmpty) return;
    try {
      await MessageHistoryStorage.instance.upsertContactLocationCache(rows);
    } on StateError {
      return;
    }
  }

  Future<void> _clearNativeEstimateKeys(Set<String> keys) async {
    try {
      await MessageHistoryStorage.instance.clearContactLocationEstimatesForKeys(
        keys,
      );
    } on StateError {
      return;
    }
  }

  McoEstimatedContactLocation? _estimateFromRow(
    ContactLocationCacheRecord row,
  ) {
    final latitude = row.estimatedLatitude;
    final longitude = row.estimatedLongitude;
    if (latitude == null || longitude == null) return null;
    try {
      return McoEstimatedContactLocation.fromJson({
        'publicKeyHex': row.publicKeyHex,
        'name': row.name,
        'contactType': row.contactType,
        'latitude': latitude,
        'longitude': longitude,
        'updatedAt': row.updatedAtMs,
        'anchorPublicKeys': jsonDecode(row.anchorPublicKeysJson),
        'anchorLatitudes': jsonDecode(row.anchorLatitudesJson),
        'anchorLongitudes': jsonDecode(row.anchorLongitudesJson),
        'highConfidence': row.highConfidence,
      });
    } catch (_) {
      return null;
    }
  }

  List<McoEstimatedContactLocation> _loadWebEstimates() {
    final value = PrefsManager.instance.getString(_webPrefsKey);
    if (value == null || value.isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return decoded
          .map(McoEstimatedContactLocation.fromJson)
          .whereType<McoEstimatedContactLocation>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveWebEstimates(
    Iterable<McoEstimatedContactLocation> estimates,
    Iterable<String> clearEstimateKeys,
  ) async {
    final clearKeys = clearEstimateKeys
        .map((key) => key.toLowerCase())
        .where((key) => key.isNotEmpty)
        .toSet();
    final byKey = {
      for (final estimate in _loadWebEstimates())
        if (!clearKeys.contains(estimate.publicKeyHex.toLowerCase()))
          estimate.publicKeyHex.toLowerCase(): estimate,
    };
    for (final estimate in estimates) {
      byKey[estimate.publicKeyHex.toLowerCase()] = estimate;
    }
    await PrefsManager.instance.setString(
      _webPrefsKey,
      jsonEncode(byKey.values.map((estimate) => estimate.toJson()).toList()),
    );
  }

  String _hex(Iterable<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

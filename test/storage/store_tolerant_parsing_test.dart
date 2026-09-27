import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/community.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/storage/community_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _device = 'abcdef012345';

Future<void> _init(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  PrefsManager.reset();
  await PrefsManager.initialize();
}

void main() {
  test('community store keeps valid communities next to a bad one', () async {
    final community = Community.create(id: 'c1', name: 'Ops');
    await _init({
      'communities_v1${_device.substring(0, 10)}': jsonEncode([
        community.toJson(),
        {'id': 'broken'},
      ]),
    });
    final store = CommunityStore()..setPublicKeyHex = _device;
    final communities = await store.loadCommunities();
    expect(communities.map((c) => c.id), ['c1']);
  });

  test('delivery observations skip malformed entries', () async {
    await _init({
      'delivery_observations': jsonEncode([
        {
          'contact_key': 'k',
          'path_length': 1,
          'message_bytes': 10,
          'delivery_ms': 500,
          'timestamp': DateTime(2026).toIso8601String(),
        },
        {'contact_key': 'bad'},
      ]),
    });
    final observations = await StorageService().loadDeliveryObservations();
    expect(observations, hasLength(1));
    expect(observations.single.isFlood, isFalse);
  });

  test('community hashtag normalization trims before stripping #', () {
    final community = Community.create(id: 'c1', name: 'Ops');
    expect(
      community.deriveCommunityHashtagPsk(' #ops'),
      community.deriveCommunityHashtagPsk('#ops'),
    );
  });
}

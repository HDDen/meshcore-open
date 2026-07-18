import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/contact_merge_helper.dart';
import 'package:meshcore_open/models/contact.dart';

void main() {
  Contact contact({
    required Uint8List publicKey,
    required String name,
    required DateTime lastSeen,
    DateTime? lastModified,
    DateTime? lastMessageAt,
    bool hasMessages = false,
    int? pathOverride,
    Uint8List? pathOverrideBytes,
    double? latitude,
    double? longitude,
  }) {
    return Contact(
      publicKey: publicKey,
      name: name,
      type: 1,
      pathLength: -1,
      path: Uint8List(0),
      lastSeen: lastSeen,
      lastModified: lastModified,
      lastMessageAt: lastMessageAt,
      hasMessages: hasMessages,
      pathOverride: pathOverride,
      pathOverrideBytes: pathOverrideBytes,
      latitude: latitude,
      longitude: longitude,
    );
  }

  test('deduplicates contacts while preserving local and history state', () {
    final publicKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final older = contact(
      publicKey: publicKey,
      name: 'Old name',
      lastSeen: DateTime(2026, 1, 1),
      lastMessageAt: DateTime(2026, 2, 1),
      hasMessages: true,
      pathOverride: 2,
      pathOverrideBytes: Uint8List.fromList([1, 2]),
    );
    final newer = contact(
      publicKey: publicKey,
      name: 'New name',
      lastSeen: DateTime(2026, 3, 1),
      lastModified: DateTime(2026, 3, 2),
      lastMessageAt: DateTime(2026, 1, 15),
      latitude: 45.1,
      longitude: 38.8,
    );

    final merged = deduplicateContactsByPublicKey([older, newer]);

    expect(merged, hasLength(1));
    expect(merged.single.name, 'New name');
    expect(merged.single.hasMessages, isTrue);
    expect(merged.single.lastMessageAt, DateTime(2026, 2, 1));
    expect(merged.single.pathOverride, 2);
    expect(merged.single.pathOverrideBytes, orderedEquals([1, 2]));
    expect(merged.single.latitude, 45.1);
    expect(merged.single.longitude, 38.8);
  });

  test('repairs a stale sync index after an out-of-band contact add', () {
    final publicKey = Uint8List.fromList(List<int>.filled(32, 7));
    final otherContact = contact(
      publicKey: Uint8List.fromList(List<int>.filled(32, 8)),
      name: 'Other contact',
      lastSeen: DateTime(2026, 1, 1),
    );
    final addedDuringSync = contact(
      publicKey: publicKey,
      name: 'Added during sync',
      lastSeen: DateTime(2026, 1, 1),
    );
    final contacts = <Contact>[otherContact, addedDuringSync];
    final syncIndexes = <String, int>{addedDuringSync.publicKeyHex: 0};

    final index = findAndRepairContactIndex(
      contacts: contacts,
      indexesByPublicKey: syncIndexes,
      publicKeyHex: addedDuringSync.publicKeyHex,
    );

    expect(index, 1);
    expect(syncIndexes[addedDuringSync.publicKeyHex], 1);
  });
}

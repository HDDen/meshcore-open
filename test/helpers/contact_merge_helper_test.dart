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

  test('U11a: a newer record without GPS keeps coordinates and local state', () {
    final key = Uint8List.fromList(List<int>.filled(32, 7));
    final oldAdvert = DateTime.utc(2026, 1, 1);
    final newAdvert = DateTime.utc(2026, 1, 2);
    final messageAt = DateTime.utc(2026, 1, 3);
    final existing = contact(
      publicKey: key,
      name: 'Before',
      lastSeen: oldAdvert,
      lastMessageAt: messageAt,
      hasMessages: true,
      latitude: 55.75,
      longitude: 37.62,
      pathOverride: 2,
      pathOverrideBytes: Uint8List.fromList([0x10, 0x20]),
    );
    final incoming = contact(
      publicKey: key,
      name: 'After',
      lastSeen: newAdvert,
    );

    final merged = mergeDuplicateContacts(existing, incoming);
    expect(merged.name, 'After');
    expect(merged.latitude, 55.75);
    expect(merged.longitude, 37.62);
    expect(merged.lastSeen, newAdvert);
    expect(merged.lastMessageAt, messageAt);
    expect(merged.hasMessages, isTrue);
    expect(merged.pathOverride, 2);
    expect(merged.pathOverrideBytes, orderedEquals([0x10, 0x20]));
    // A merge must not mutate either source or invent phone-clock freshness.
    expect(existing.lastSeen, oldAdvert);
    expect(incoming.latitude, isNull);
  });

  test('U11a: an older duplicate cannot replace a newer advertised position', () {
    final key = Uint8List.fromList(List<int>.filled(32, 9));
    final oldAdvert = DateTime.utc(2026, 1, 1);
    final newAdvert = DateTime.utc(2026, 1, 2);
    final older = contact(
      publicKey: key,
      name: 'Older',
      lastSeen: oldAdvert,
      latitude: 1.0,
      longitude: -2.0,
    );
    final newer = contact(
      publicKey: key,
      name: 'Newer',
      lastSeen: newAdvert,
      latitude: -3.0,
      longitude: 4.0,
    );
    for (final records in [[older, newer], [newer, older]]) {
      final merged = deduplicateContactsByPublicKey(records).single;
      expect(merged.name, 'Newer');
      expect(merged.latitude, -3.0);
      expect(merged.longitude, 4.0);
      expect(merged.lastSeen, newAdvert);
    }
  });

  test('U11a: changing only coordinates does not advance advert or message time', () {
    final advertAt = DateTime.utc(2026, 1, 1);
    final modifiedAt = DateTime.utc(2026, 1, 2);
    final messageAt = DateTime.utc(2026, 1, 3);
    final original = contact(
      publicKey: Uint8List.fromList(List<int>.filled(32, 7)),
      name: 'GPS contact',
      lastSeen: advertAt,
      lastModified: modifiedAt,
      lastMessageAt: messageAt,
      pathOverride: -1,
    );
    final positioned = original.copyWith(latitude: 1.0, longitude: -2.0);

    // lastSeen is sent back as last_advert in contact writes. Adding a local
    // GPS source later must not replace it with DateTime.now().
    expect(positioned.lastSeen, advertAt);
    expect(positioned.lastModified, modifiedAt);
    expect(positioned.lastMessageAt, messageAt);
    expect(positioned.pathOverride, -1);
    expect(positioned.publicKeyHex, original.publicKeyHex);
    expect(original.latitude, isNull);
    expect(positioned.hasLocation, isTrue);
  });
}

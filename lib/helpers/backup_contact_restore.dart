import 'dart:async';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';

enum BackupContactAction { add, alreadyPresent, self, unsupportedType, noRoom }

typedef BackupContactDecision = ({
  Contact contact,
  BackupContactAction action,
  bool usesFloodFallback,
});

enum BackupContactRestoreStatus {
  completed,
  destinationChanged,
  overwriteUnsafe,
  writeUnconfirmed,
  syncFailed,
}

typedef BackupContactRestoreResult = ({
  int confirmed,
  BackupContactRestoreStatus status,
});

class BackupContactRestorePreview {
  BackupContactRestorePreview({
    required this.nodeKey,
    required this.session,
    required this.capacity,
    required this.supportsWidePaths,
    required Iterable<String> currentKeys,
    required String? sourcePublicKey,
    required Iterable<Contact> contacts,
  }) : _currentKeys = Set.unmodifiable(currentKeys) {
    var free = capacity - _currentKeys.length;
    final decisions = <BackupContactDecision>[];
    final seen = <String>{};
    for (final contact in contacts) {
      final key = contact.publicKeyHex;
      if (!seen.add(key)) continue;
      final BackupContactAction action;
      if (key == nodeKey) {
        action = BackupContactAction.self;
      } else if (_currentKeys.contains(key)) {
        action = BackupContactAction.alreadyPresent;
      } else if (contact.type < advTypeChat || contact.type > advTypeSensor) {
        action = BackupContactAction.unsupportedType;
      } else if (free <= 0) {
        action = BackupContactAction.noRoom;
      } else {
        action = BackupContactAction.add;
        free--;
      }
      final fallback = action == BackupContactAction.add &&
          contact.pathLength >= 0 &&
          (sourcePublicKey != nodeKey ||
              (contact.pathHashWidth > 1 && !supportsWidePaths));
      final target = action == BackupContactAction.add
          ? contact.copyWith(
              publicKey: Uint8List.fromList(contact.publicKey).asUnmodifiableView(),
              path: fallback
                  ? Uint8List(0).asUnmodifiableView()
                  : Uint8List.fromList(contact.path).asUnmodifiableView(),
              pathLength: fallback ? -1 : contact.pathLength,
              pathHashWidth: fallback ? 1 : contact.pathHashWidth,
            )
          : contact;
      decisions.add((contact: target, action: action, usesFloodFallback: fallback));
    }
    this.decisions = List.unmodifiable(decisions);
  }

  final String nodeKey;
  final Object session;
  final int capacity;
  final bool supportsWidePaths;
  final Set<String> _currentKeys;
  late final List<BackupContactDecision> decisions;

  bool matchesInventory(Iterable<String> keys, int capacity) =>
      capacity == this.capacity &&
      keys.length == _currentKeys.length &&
      keys.every(_currentKeys.contains);
}

/// Tracks the explicitly requested full list until END_OF_CONTACTS.
class BackupContactInventoryRead {
  final done = Completer<Map<String, Contact>?>();
  final _contacts = <String, Contact>{};
  int? _expected;
  int _received = 0;

  void start(int? count) {
    _expected = count;
    _received = 0;
    _contacts.clear();
  }

  void add(Contact contact) {
    _received++;
    _contacts[contact.publicKeyHex] = contact;
  }

  Map<String, Contact>? get verifiedContacts =>
      _expected == _received && _received == _contacts.length
      ? Map.unmodifiable(_contacts)
      : null;
}

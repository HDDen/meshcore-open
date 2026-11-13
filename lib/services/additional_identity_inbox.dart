import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show ChangeNotifier, VoidCallback, setEquals;

import '../connector/meshcore_protocol.dart';
import '../helpers/additional_identity_text_packet.dart';
import '../helpers/direct_echo_recovery.dart';
import '../helpers/message_text_codec.dart';
import '../models/additional_identity_message.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../models/path_selection.dart';
import '../storage/message_history_storage.dart';
import 'additional_identity_vault.dart';

typedef AdditionalIdentityReceipt = ({
  Contact contact,
  DirectEchoPlaintext plaintext,
  bool Function() isCurrent,
  Uint8List? roomRecipientKey,
});

typedef _PendingRoomLogin = ({
  Contact room,
  bool Function() isCurrent,
  Completer<bool> result,
});

class _PendingIdentitySend {
  _PendingIdentitySend({
    required this.identityKey,
    required this.peer,
    required this.timestamp,
    required this.isCurrent,
    required this.flood,
    required this.timeout,
  });

  final String identityKey;
  final Contact peer;
  final int timestamp;
  final bool Function() isCurrent;
  final bool flood;
  final Timer timeout;
  int? dispatchedAtMs;
  final elapsed = Stopwatch();
  int? airtimeMs;
}

typedef _Match = ({
  String recipientKey,
  Contact contact,
  DirectEchoPlaintext plaintext,
  String wireText,
  Uint8List? roomAuthor,
  Uint8List? roomRecipientKey,
});

/// Keeps the unlocked identities and their derived secrets for this process.
class AdditionalIdentityInbox extends ChangeNotifier {
  AdditionalIdentityInbox({MessageHistoryStorage? storage})
    : _storage = storage ?? MessageHistoryStorage.instance;

  final MessageHistoryStorage _storage;
  final _recipients = <int, List<_Recipient>>{};
  final _ownKeys = <String>{};
  final _recentAcks = <(String, String, String), DateTime>{};
  final _pending = <int, _PendingIdentitySend>{};
  final _lastSendTimestamp = <String, int>{};
  final _roomLogins = <(String, String), _PendingRoomLogin>{};
  final _roomPostAccess = <(String, String)>{};
  final _lastRoomResponse = <(String, String), int>{};
  int _revision = 0;
  bool _disposed = false;
  List<AdditionalIdentityEntry> _entries = const [];

  bool get isUnlocked => _recipients.isNotEmpty;
  List<AdditionalIdentityEntry> get entries => _entries;

  AdditionalIdentityEntry? entryFor(String key) => entries
      .where((entry) => entry.identity.publicKeyHex == key)
      .firstOrNull;

  Future<String?> preferredSender(String peerKey) =>
      _storage.readAdditionalIdentitySender(peerKey);

  Future<void> setPreferredSender(String peerKey, String? identityKey) {
    if (identityKey != null && entryFor(identityKey) == null) {
      throw StateError('Additional identity is unavailable');
    }
    return _storage.writeAdditionalIdentitySender(peerKey, identityKey);
  }

  int get historyRevision => _revision + _messageRevision;

  bool canPostToRoom(String identityKey, String roomKey) =>
      _roomPostAccess.contains((identityKey, roomKey));

  int _messageRevision = 0;
  int _deletionRevision = 0;
  int get deletionRevision => _deletionRevision;

  final _visibleChats = <String, Set<bool Function(String)>>{};

  VoidCallback trackChat(
    String recipientKey,
    String senderKey,
    bool Function() isVisible,
  ) {
    return trackPeerChat(
      senderKey,
      (key) => key == recipientKey && isVisible(),
    );
  }

  VoidCallback trackPeerChat(
    String senderKey,
    bool Function(String) isVisible,
  ) {
    final routes = _visibleChats.putIfAbsent(senderKey, () => {});
    routes.add(isVisible);
    return () {
      routes.remove(isVisible);
      if (routes.isEmpty) _visibleChats.remove(senderKey);
    };
  }

  Future<List<AdditionalIdentityThread>> threads(String recipientKey) =>
      _storage.readAdditionalIdentityThreads(recipientKey);

  Future<List<AdditionalIdentityMessage>> sharedMessages(String senderKey) async {
    final keys = [for (final entry in entries) entry.identity.publicKeyHex];
    if (keys.isEmpty) return const [];
    return _storage.readAdditionalIdentityMessagesForSender(senderKey, keys);
  }

  Future<List<AdditionalIdentityMessage>> messages(
    String recipientKey,
    String senderKey, {
    (int, int)? before,
  }) => _storage.readAdditionalIdentityMessages(
    recipientKey,
    senderKey: senderKey,
    before: before,
  );

  Future<void> deleteMessage(String messageId) async {
    final parts = messageId.split(':');
    final rowId = parts.length == 3 ? int.tryParse(parts[2]) : null;
    if (_disposed ||
        rowId == null ||
        rowId <= 0 ||
        parts.first != 'identity' ||
        !_ownKeys.contains(parts[1])) {
      throw StateError('Additional identity message is unavailable');
    }
    if (await _storage.deleteAdditionalIdentityMessage(parts[1], rowId)) {
      _deletionRevision++;
      _historyChanged();
    }
  }

  Future<void> clearMessages(String senderKey, {String? recipientKey}) async {
    if (_disposed || (recipientKey != null && !_ownKeys.contains(recipientKey))) {
      throw StateError('Additional identity history is unavailable');
    }
    final keys = recipientKey == null ? _ownKeys.toList() : [recipientKey];
    if (keys.isEmpty) return;
    if (await _storage.clearAdditionalIdentityMessages(senderKey, keys)) {
      _deletionRevision++;
      _historyChanged();
    }
  }

  Future<void> markRead(String recipientKey, String senderKey) async {
    final changed = await _storage.markAdditionalIdentityThreadRead(
      recipientKey,
      senderKey,
    );
    if (changed && !_disposed) notifyListeners();
  }

  Future<void> send({
    required String identityKey,
    required Contact peer,
    required String text,
    required DateTime requestedAt,
    required PathSelection route,
    required int pathHashWidth,
    required String region,
    required FutureOr<String> Function(AdditionalIdentityEntry, int) encode,
    required bool cyr2Lat,
    required int? Function(int packetBytes) estimateAirtime,
    required bool Function() isCurrent,
    required Future<void> Function(Uint8List, bool Function()) write,
  }) async {
    final entry = entries.where((entry) =>
        entry.identity.publicKeyHex == identityKey).firstOrNull;
    if (entry == null || _disposed || !isCurrent()) {
      throw StateError('Additional identity is unavailable');
    }
    final peerKey = peer.publicKeyHex;
    if (peerKey == identityKey) throw ArgumentError('Cannot send to this identity');
    bool valid() => !_disposed &&
        _ownKeys.contains(identityKey) &&
        (peer.type != advTypeRoom || canPostToRoom(identityKey, peerKey)) &&
        isCurrent();

    final timestamp = await _nextTimestamp(identityKey, requestedAt, valid);
    final wireText = await encode(entry, timestamp);
    if (!valid()) throw StateError('Radio session or identity changed');
    if (peer.type == advTypeRoom &&
        utf8.encode(wireText).length > maxRoomServerTextBytes) {
      throw const FormatException('Invalid additional identity message size');
    }
    final packet = AdditionalIdentityTextPacket.build(
      identity: entry.identity,
      peer: peer.publicKey,
      timestamp: timestamp,
      text: wireText,
      route: route,
      pathHashWidth: pathHashWidth,
      region: region,
    );
    final hash = packet.ackHash;
    if (_pending.containsKey(hash)) throw StateError('ACK hash is already in use');
    final pending = _PendingIdentitySend(
      identityKey: identityKey,
      peer: peer,
      timestamp: timestamp,
      isCurrent: valid,
      flood: route.useFlood,
      timeout: Timer(const Duration(seconds: 45), () {
        _persistInBackground(_finishSend(hash, MessageStatus.failed));
      }),
    );
    _pending[hash] = pending;
    var stored = false;
    try {
      stored = await _storage.insertAdditionalIdentityMessage((
        recipientKey: identityKey,
        senderKey: peerKey,
        senderName: peer.name,
        peerType: peer.type,
        roomAuthorHex: null,
        timestampSeconds: timestamp,
        receivedAtMs: requestedAt.millisecondsSinceEpoch,
        text: text,
        wireText: wireText,
        isUnread: false,
        isOutgoing: true,
        status: MessageStatus.pending,
        rowId: 0,
        sentByFlood: route.useFlood,
        region: region.isEmpty ? null : region,
        path: Uint8List.fromList(route.pathBytes),
        dispatchedAtMs: null,
        tripTimeMs: null,
        airtimeMs: null,
        usedCyr2Lat: cyr2Lat && wireText != text,
      ));
      if (!stored) throw StateError('Identity message already exists');
      _historyChanged();
      bool canWrite() => valid() && identical(_pending[hash], pending);
      if (!canWrite()) throw StateError('Radio session or identity changed');
      pending.airtimeMs = estimateAirtime(packet.frame.length - 2);
      pending.dispatchedAtMs = DateTime.now().millisecondsSinceEpoch;
      pending.elapsed.start();
      await write(packet.frame, canWrite);
      if (identical(_pending[hash], pending)) {
        await _updateSend(pending, MessageStatus.sent);
      }
    } catch (_) {
      if (identical(_pending[hash], pending)) {
        await _finishSend(hash, MessageStatus.failed);
      } else if (stored && pending.dispatchedAtMs == null) {
        await _updateSend(pending, MessageStatus.failed);
      }
      rethrow;
    }
  }

  Future<int> _nextTimestamp(
    String identityKey,
    DateTime now,
    bool Function() isCurrent,
  ) async {
    final previous = await _storage.latestAdditionalIdentitySendTimestamp(identityKey);
    if (!isCurrent()) throw StateError('Radio session or identity changed');
    var timestamp = now.millisecondsSinceEpoch ~/ 1000;
    for (final used in [previous, _lastSendTimestamp[identityKey]]) {
      if (used != null && used >= timestamp) timestamp = used + 1;
    }
    _lastSendTimestamp[identityKey] = timestamp;
    return timestamp;
  }

  Future<bool> loginToRoom({
    required String identityKey,
    required Contact room,
    required String password,
    required PathSelection route,
    required int pathHashWidth,
    required String region,
    required bool Function() isCurrent,
    required Future<void> Function(Uint8List, bool Function()) write,
  }) async {
    final entry = entryFor(identityKey);
    final key = (identityKey, room.publicKeyHex);
    if (entry == null || _disposed || !isCurrent() || _roomLogins.containsKey(key)) {
      throw StateError('Cannot start this room login');
    }
    final result = Completer<bool>();
    var sent = false;
    final pending = (
      room: room,
      isCurrent: () => sent && isCurrent(),
      result: result,
    );
    _roomLogins[key] = pending;
    _roomPostAccess.remove(key);
    bool valid() => !_disposed &&
        isCurrent() &&
        identical(_roomLogins[key], pending);

    try {
      final syncSince = await _storage.latestAdditionalIdentityReceivedTimestamp(
        identityKey,
        room.publicKeyHex,
      );
      final timestamp = await _nextTimestamp(identityKey, DateTime.now(), valid);
      final frame = AdditionalIdentityTextPacket.roomLogin(
        identity: entry.identity,
        room: room.publicKey,
        timestamp: timestamp,
        syncSince: syncSince ?? 0,
        password: password,
        route: route,
        pathHashWidth: pathHashWidth,
        region: region,
      );
      await write(frame, () {
        sent = valid();
        return sent;
      });
      final canPost = await result.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => false,
      );
      if (!valid() || !canPost) return false;
      _roomPostAccess.add(key);
      return true;
    } finally {
      if (identical(_roomLogins[key], pending)) _roomLogins.remove(key);
    }
  }

  void acceptRoomLoginResponse(
    Uint8List payload,
    Uint8List? Function(Uint8List, Uint8List) decrypt, {
    required bool inPath,
  }) {
    if (_roomLogins.isEmpty ||
        payload.length < 20 ||
        (payload.length - 4) % 16 != 0) {
      return;
    }
    final recipients = _recipients[payload.first];
    if (recipients == null) return;
    final encrypted = Uint8List.sublistView(payload, 2);
    ((String, String), _PendingRoomLogin, int, bool)? match;
    for (final item in _roomLogins.entries) {
      final pending = item.value;
      if (pending.result.isCompleted ||
          !pending.isCurrent() ||
          pending.room.publicKey.first != payload[1]) {
        continue;
      }
      for (final recipient in recipients) {
        if (recipient.entry.identity.publicKeyHex != item.key.$1) continue;
        final secret = recipient.secretFor(pending.room);
        if (secret == null) continue;
        final plaintext = decrypt(secret, encrypted);
        if (plaintext == null) continue;
        final response = AdditionalIdentityTextPacket.roomLoginResponse(
          plaintext,
          inPath: inPath,
        );
        if (response == null ||
            response.timestamp <= (_lastRoomResponse[item.key] ?? 0)) {
          continue;
        }
        if (match != null) return;
        match = (item.key, pending, response.timestamp, response.canPost);
      }
    }
    if (match == null) return;
    _lastRoomResponse[match.$1] = match.$3;
    match.$2.result.complete(match.$4);
  }

  void acceptAck(int hash) {
    final pending = _pending[hash];
    if (pending != null && pending.elapsed.isRunning && pending.isCurrent()) {
      _persistInBackground(_finishSend(hash, MessageStatus.delivered));
    }
  }

  void acceptPathAck(
    Uint8List payload,
    Uint8List? Function(Uint8List, Uint8List) decrypt,
  ) {
    if (_pending.isEmpty ||
        payload.length < 20 ||
        (payload.length - 4) % 16 != 0) {
      return;
    }
    final recipients = _recipients[payload.first];
    if (recipients == null) return;
    int? match;
    final encrypted = Uint8List.sublistView(payload, 2);
    final tried = <(String, String)>{};
    for (final pending in _pending.values) {
      if (!pending.flood || !pending.isCurrent() ||
          pending.peer.publicKey.first != payload[1] ||
          !tried.add((pending.identityKey, pending.peer.publicKeyHex))) {
        continue;
      }
      for (final recipient in recipients) {
        final key = recipient.entry.identity.publicKeyHex;
        if (key != pending.identityKey) continue;
        final secret = recipient.secretFor(pending.peer);
        if (secret == null) continue;
        final plaintext = decrypt(secret, encrypted);
        if (plaintext == null) continue;
        final hash = AdditionalIdentityTextPacket.pathAckHash(plaintext);
        final found = _pending[hash];
        if (hash == null || found == null ||
            !found.flood || !found.isCurrent() ||
            found.identityKey != key ||
            found.peer.publicKeyHex != pending.peer.publicKeyHex) {
          continue;
        }
        if (match != null && match != hash) return;
        match = hash;
      }
    }
    if (match != null) acceptAck(match);
  }

  Future<void> _finishSend(int hash, MessageStatus status) async {
    final pending = _pending.remove(hash);
    if (pending == null) return;
    pending.timeout.cancel();
    pending.elapsed.stop();
    await _updateSend(pending, status);
  }

  Future<void> _updateSend(
    _PendingIdentitySend pending,
    MessageStatus status,
  ) async {
    if (await _storage.updateAdditionalIdentitySendStatus(
      pending.identityKey,
      pending.peer.publicKeyHex,
      pending.timestamp,
      status,
      dispatchedAtMs: pending.dispatchedAtMs,
      tripTimeMs: status == MessageStatus.delivered
          ? pending.elapsed.elapsedMilliseconds
          : null,
      airtimeMs: status == MessageStatus.failed ? null : pending.airtimeMs,
    )) {
      _historyChanged();
    }
  }

  void _historyChanged() {
    if (_disposed) return;
    _messageRevision++;
    notifyListeners();
  }

  void _persistInBackground(Future<void> operation) {
    unawaited(operation.catchError((Object _, StackTrace _) {}));
  }

  void endRadioSession() {
    _roomPostAccess.clear();
    for (final pending in _roomLogins.values) {
      if (!pending.result.isCompleted) pending.result.complete(false);
    }
    _roomLogins.clear();
    for (final hash in _pending.keys.toList()) {
      _persistInBackground(_finishSend(hash, MessageStatus.failed));
    }
  }

  Future<void> restoreRemembered() async {
    final revision = _revision;
    final vault = await AdditionalIdentityVault.openRemembered(storage: _storage);
    if (!_disposed && vault != null && revision == _revision) unlock(vault.entries);
  }

  void unlock(List<AdditionalIdentityEntry> entries) {
    if (_disposed) return;
    _replaceEntries(entries);
    notifyListeners();
  }

  void _replaceEntries(List<AdditionalIdentityEntry> entries) {
    final nextKeys = {for (final entry in entries) entry.identity.publicKeyHex};
    _revision++;
    if (!setEquals(_ownKeys, nextKeys)) endRadioSession();
    _entries = List.unmodifiable(entries);
    for (final group in _recipients.values) {
      for (final recipient in group) {
        recipient.clear();
      }
    }
    _recipients.clear();
    _ownKeys.clear();
    _recentAcks.clear();
    for (final entry in entries) {
      final key = entry.identity.publicKey;
      _ownKeys.add(entry.identity.publicKeyHex);
      (_recipients[key.first] ??= []).add(_Recipient(entry));
    }
  }

  /// Returns an ACK candidate only after persisting a uniquely decoded packet.
  /// History coalesces logical retries while their distinct packets may each
  /// earn an ACK. Copies of the same packet heard close together earn one.
  Future<AdditionalIdentityReceipt?> receive({
    required Uint8List payload,
    required String primaryKey,
    required Iterable<Contact> Function() contacts,
    required Uint8List? Function(Uint8List secret, Uint8List encrypted) decrypt,
    required bool Function() isCurrent,
  }) async {
    if (payload.length < 20 || (payload.length - 4) % 16 != 0) return null;
    final recipients = _recipients[payload[0]];
    if (recipients == null) return null;
    final candidates = <String, Contact>{
      for (final contact in contacts())
        if ((contact.type == advTypeChat || contact.type == advTypeRoom) &&
            contact.publicKey.length == pubKeySize &&
            contact.publicKey.first == payload[1] &&
            contact.publicKeyHex != primaryKey &&
            !_ownKeys.contains(contact.publicKeyHex))
          contact.publicKeyHex: contact,
    };
    if (candidates.isEmpty) return null;

    final receivedAt = DateTime.now();
    final encrypted = Uint8List.sublistView(payload, 2);
    _Match? match;
    for (final recipient in recipients) {
      final recipientKey = recipient.entry.identity.publicKeyHex;
      if (recipientKey == primaryKey) continue;
      for (final contact in candidates.values) {
        final secret = recipient.secretFor(contact);
        if (secret == null) continue;
        final bytes = decrypt(secret, encrypted);
        if (bytes == null) continue;
        final isRoom = contact.type == advTypeRoom;
        final plaintext = isRoom
            ? _parseRoomPost(bytes)
            : DirectEchoRecovery.parsePlaintext(bytes);
        if (plaintext == null) continue;
        final String wireText;
        try {
          wireText = utf8.decode(
            isRoom ? plaintext.textBytes.sublist(4) : plaintext.textBytes,
          );
        } on FormatException {
          continue;
        }
        if (match != null) return null;
        match = (
          recipientKey: recipientKey,
          contact: contact,
          plaintext: plaintext,
          wireText: wireText,
          roomAuthor: isRoom ? bytes.sublist(5, 9) : null,
          roomRecipientKey: isRoom ? recipient.entry.identity.publicKey : null,
        );
      }
    }
    if (match == null || !isCurrent()) return null;

    final sender = match.contact.publicKeyHex;
    final recipientKey = match.recipientKey;
    final packetKey = (
      recipientKey,
      sender,
      crypto.sha256.convert(payload).toString(),
    );
    _recentAcks.removeWhere(
      (_, seen) => receivedAt.difference(seen) >= const Duration(seconds: 15),
    );
    if (_recentAcks.containsKey(packetKey)) return null;

    final revision = _revision;
    final timestamp = match.plaintext.timestamp;
    final text = MessageTextCodec.tryDecodeKnownCompression(
      match.wireText,
      inheritedTimestamp: timestamp,
    ) ?? match.wireText;
    final stored = await _storage.insertAdditionalIdentityMessage((
      recipientKey: match.recipientKey,
      senderKey: sender,
      senderName: match.contact.name,
      peerType: match.contact.type,
      roomAuthorHex: match.roomAuthor == null ? null : pubKeyToHex(match.roomAuthor!),
      timestampSeconds: timestamp,
      receivedAtMs: receivedAt.millisecondsSinceEpoch,
      wireText: match.wireText,
      text: text,
      isUnread: !(_visibleChats[sender]?.any(
        (isVisible) => isVisible(recipientKey),
      ) ?? false),
      isOutgoing: false,
      status: MessageStatus.delivered,
      rowId: 0,
      sentByFlood: null,
      region: null,
      path: null,
      dispatchedAtMs: null,
      tripTimeMs: null,
      airtimeMs: null,
      usedCyr2Lat: false,
    ));
    if (stored) _historyChanged();
    if (revision != _revision ||
        !isCurrent() ||
        _recentAcks.containsKey(packetKey)) {
      return null;
    }
    if (_recentAcks.length >= 256) _recentAcks.remove(_recentAcks.keys.first);
    _recentAcks[packetKey] = DateTime.now();
    return (
      contact: match.contact,
      plaintext: match.plaintext,
      isCurrent: () => revision == _revision && isCurrent(),
      roomRecipientKey: match.roomRecipientKey,
    );
  }

  static DirectEchoPlaintext? _parseRoomPost(Uint8List bytes) {
    if (bytes.length <= 9 || bytes[4] >> 2 != txtTypeSigned) return null;
    final timestamp = ByteData.sublistView(bytes).getUint32(0, Endian.little);
    if (timestamp == 0 || bytes[9] == 0) return null;
    var end = 9;
    while (end < bytes.length && bytes[end] != 0) {
      end++;
    }
    return DirectEchoPlaintext(
      bytes: bytes,
      timestamp: timestamp,
      flags: bytes[4],
      textLength: end - 5,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    endRadioSession();
    _replaceEntries(const []);
    _visibleChats.clear();
    super.dispose();
  }
}

class _Recipient {
  _Recipient(this.entry);

  final AdditionalIdentityEntry entry;
  final _secrets = <String, Uint8List>{};

  Uint8List? secretFor(Contact contact) {
    final key = contact.publicKeyHex;
    final saved = _secrets.remove(key);
    if (saved != null) {
      _secrets[key] = saved;
      return saved;
    }
    try {
      final secret = entry.identity.sharedSecret(contact.publicKey);
      if (_secrets.length >= 128) {
        final oldest = _secrets.remove(_secrets.keys.first)!;
        oldest.fillRange(0, oldest.length, 0);
      }
      _secrets[key] = secret;
      return secret;
    } on ArgumentError {
      return null;
    }
  }

  void clear() {
    for (final secret in _secrets.values) {
      secret.fillRange(0, secret.length, 0);
    }
    _secrets.clear();
  }
}

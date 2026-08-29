// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_history_database.dart';

// ignore_for_file: type=lint
class $HistoryMessagesTable extends HistoryMessages
    with TableInfo<$HistoryMessagesTable, HistoryMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<int> kind = GeneratedColumn<int>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storageKeyMeta = const VerificationMeta(
    'storageKey',
  );
  @override
  late final GeneratedColumn<String> storageKey = GeneratedColumn<String>(
    'storage_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _packetHashMeta = const VerificationMeta(
    'packetHash',
  );
  @override
  late final GeneratedColumn<String> packetHash = GeneratedColumn<String>(
    'packet_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timelineAtMsMeta = const VerificationMeta(
    'timelineAtMs',
  );
  @override
  late final GeneratedColumn<int> timelineAtMs = GeneratedColumn<int>(
    'timeline_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMsMeta = const VerificationMeta(
    'timestampMs',
  );
  @override
  late final GeneratedColumn<int> timestampMs = GeneratedColumn<int>(
    'timestamp_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedAtMsMeta = const VerificationMeta(
    'receivedAtMs',
  );
  @override
  late final GeneratedColumn<int> receivedAtMs = GeneratedColumn<int>(
    'received_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _senderKeyMeta = const VerificationMeta(
    'senderKey',
  );
  @override
  late final GeneratedColumn<String> senderKey = GeneratedColumn<String>(
    'sender_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _senderNameMeta = const VerificationMeta(
    'senderName',
  );
  @override
  late final GeneratedColumn<String> senderName = GeneratedColumn<String>(
    'sender_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isOutgoingMeta = const VerificationMeta(
    'isOutgoing',
  );
  @override
  late final GeneratedColumn<bool> isOutgoing = GeneratedColumn<bool>(
    'is_outgoing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_outgoing" IN (0, 1))',
    ),
  );
  static const VerificationMeta _isCliMeta = const VerificationMeta('isCli');
  @override
  late final GeneratedColumn<bool> isCli = GeneratedColumn<bool>(
    'is_cli',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_cli" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawTextMeta = const VerificationMeta(
    'rawText',
  );
  @override
  late final GeneratedColumn<String> rawText = GeneratedColumn<String>(
    'raw_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawPayloadMeta = const VerificationMeta(
    'rawPayload',
  );
  @override
  late final GeneratedColumn<Uint8List> rawPayload = GeneratedColumn<Uint8List>(
    'raw_payload',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _searchTextMeta = const VerificationMeta(
    'searchText',
  );
  @override
  late final GeneratedColumn<String> searchText = GeneratedColumn<String>(
    'search_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _containsMarkerMeta = const VerificationMeta(
    'containsMarker',
  );
  @override
  late final GeneratedColumn<bool> containsMarker = GeneratedColumn<bool>(
    'contains_marker',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("contains_marker" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _messageJsonMeta = const VerificationMeta(
    'messageJson',
  );
  @override
  late final GeneratedColumn<String> messageJson = GeneratedColumn<String>(
    'message_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    storageKey,
    messageId,
    packetHash,
    timelineAtMs,
    timestampMs,
    receivedAtMs,
    senderKey,
    senderName,
    isOutgoing,
    isCli,
    status,
    rawText,
    rawPayload,
    searchText,
    containsMarker,
    messageJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('storage_key')) {
      context.handle(
        _storageKeyMeta,
        storageKey.isAcceptableOrUnknown(data['storage_key']!, _storageKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_storageKeyMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('packet_hash')) {
      context.handle(
        _packetHashMeta,
        packetHash.isAcceptableOrUnknown(data['packet_hash']!, _packetHashMeta),
      );
    }
    if (data.containsKey('timeline_at_ms')) {
      context.handle(
        _timelineAtMsMeta,
        timelineAtMs.isAcceptableOrUnknown(
          data['timeline_at_ms']!,
          _timelineAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timelineAtMsMeta);
    }
    if (data.containsKey('timestamp_ms')) {
      context.handle(
        _timestampMsMeta,
        timestampMs.isAcceptableOrUnknown(
          data['timestamp_ms']!,
          _timestampMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timestampMsMeta);
    }
    if (data.containsKey('received_at_ms')) {
      context.handle(
        _receivedAtMsMeta,
        receivedAtMs.isAcceptableOrUnknown(
          data['received_at_ms']!,
          _receivedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('sender_key')) {
      context.handle(
        _senderKeyMeta,
        senderKey.isAcceptableOrUnknown(data['sender_key']!, _senderKeyMeta),
      );
    }
    if (data.containsKey('sender_name')) {
      context.handle(
        _senderNameMeta,
        senderName.isAcceptableOrUnknown(data['sender_name']!, _senderNameMeta),
      );
    }
    if (data.containsKey('is_outgoing')) {
      context.handle(
        _isOutgoingMeta,
        isOutgoing.isAcceptableOrUnknown(data['is_outgoing']!, _isOutgoingMeta),
      );
    } else if (isInserting) {
      context.missing(_isOutgoingMeta);
    }
    if (data.containsKey('is_cli')) {
      context.handle(
        _isCliMeta,
        isCli.isAcceptableOrUnknown(data['is_cli']!, _isCliMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('raw_text')) {
      context.handle(
        _rawTextMeta,
        rawText.isAcceptableOrUnknown(data['raw_text']!, _rawTextMeta),
      );
    } else if (isInserting) {
      context.missing(_rawTextMeta);
    }
    if (data.containsKey('raw_payload')) {
      context.handle(
        _rawPayloadMeta,
        rawPayload.isAcceptableOrUnknown(data['raw_payload']!, _rawPayloadMeta),
      );
    }
    if (data.containsKey('search_text')) {
      context.handle(
        _searchTextMeta,
        searchText.isAcceptableOrUnknown(data['search_text']!, _searchTextMeta),
      );
    } else if (isInserting) {
      context.missing(_searchTextMeta);
    }
    if (data.containsKey('contains_marker')) {
      context.handle(
        _containsMarkerMeta,
        containsMarker.isAcceptableOrUnknown(
          data['contains_marker']!,
          _containsMarkerMeta,
        ),
      );
    }
    if (data.containsKey('message_json')) {
      context.handle(
        _messageJsonMeta,
        messageJson.isAcceptableOrUnknown(
          data['message_json']!,
          _messageJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_messageJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HistoryMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kind'],
      )!,
      storageKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_key'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      packetHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}packet_hash'],
      ),
      timelineAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timeline_at_ms'],
      )!,
      timestampMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp_ms'],
      )!,
      receivedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}received_at_ms'],
      ),
      senderKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_key'],
      ),
      senderName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_name'],
      ),
      isOutgoing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_outgoing'],
      )!,
      isCli: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_cli'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      rawText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_text'],
      )!,
      rawPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}raw_payload'],
      ),
      searchText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}search_text'],
      )!,
      containsMarker: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}contains_marker'],
      )!,
      messageJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_json'],
      )!,
    );
  }

  @override
  $HistoryMessagesTable createAlias(String alias) {
    return $HistoryMessagesTable(attachedDatabase, alias);
  }
}

class HistoryMessage extends DataClass implements Insertable<HistoryMessage> {
  final int id;
  final int kind;
  final String storageKey;
  final String messageId;
  final String? packetHash;
  final int timelineAtMs;
  final int timestampMs;
  final int? receivedAtMs;
  final String? senderKey;
  final String? senderName;
  final bool isOutgoing;
  final bool isCli;
  final int status;
  final String rawText;
  final Uint8List? rawPayload;
  final String searchText;
  final bool containsMarker;
  final String messageJson;
  const HistoryMessage({
    required this.id,
    required this.kind,
    required this.storageKey,
    required this.messageId,
    this.packetHash,
    required this.timelineAtMs,
    required this.timestampMs,
    this.receivedAtMs,
    this.senderKey,
    this.senderName,
    required this.isOutgoing,
    required this.isCli,
    required this.status,
    required this.rawText,
    this.rawPayload,
    required this.searchText,
    required this.containsMarker,
    required this.messageJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<int>(kind);
    map['storage_key'] = Variable<String>(storageKey);
    map['message_id'] = Variable<String>(messageId);
    if (!nullToAbsent || packetHash != null) {
      map['packet_hash'] = Variable<String>(packetHash);
    }
    map['timeline_at_ms'] = Variable<int>(timelineAtMs);
    map['timestamp_ms'] = Variable<int>(timestampMs);
    if (!nullToAbsent || receivedAtMs != null) {
      map['received_at_ms'] = Variable<int>(receivedAtMs);
    }
    if (!nullToAbsent || senderKey != null) {
      map['sender_key'] = Variable<String>(senderKey);
    }
    if (!nullToAbsent || senderName != null) {
      map['sender_name'] = Variable<String>(senderName);
    }
    map['is_outgoing'] = Variable<bool>(isOutgoing);
    map['is_cli'] = Variable<bool>(isCli);
    map['status'] = Variable<int>(status);
    map['raw_text'] = Variable<String>(rawText);
    if (!nullToAbsent || rawPayload != null) {
      map['raw_payload'] = Variable<Uint8List>(rawPayload);
    }
    map['search_text'] = Variable<String>(searchText);
    map['contains_marker'] = Variable<bool>(containsMarker);
    map['message_json'] = Variable<String>(messageJson);
    return map;
  }

  HistoryMessagesCompanion toCompanion(bool nullToAbsent) {
    return HistoryMessagesCompanion(
      id: Value(id),
      kind: Value(kind),
      storageKey: Value(storageKey),
      messageId: Value(messageId),
      packetHash: packetHash == null && nullToAbsent
          ? const Value.absent()
          : Value(packetHash),
      timelineAtMs: Value(timelineAtMs),
      timestampMs: Value(timestampMs),
      receivedAtMs: receivedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(receivedAtMs),
      senderKey: senderKey == null && nullToAbsent
          ? const Value.absent()
          : Value(senderKey),
      senderName: senderName == null && nullToAbsent
          ? const Value.absent()
          : Value(senderName),
      isOutgoing: Value(isOutgoing),
      isCli: Value(isCli),
      status: Value(status),
      rawText: Value(rawText),
      rawPayload: rawPayload == null && nullToAbsent
          ? const Value.absent()
          : Value(rawPayload),
      searchText: Value(searchText),
      containsMarker: Value(containsMarker),
      messageJson: Value(messageJson),
    );
  }

  factory HistoryMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryMessage(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<int>(json['kind']),
      storageKey: serializer.fromJson<String>(json['storageKey']),
      messageId: serializer.fromJson<String>(json['messageId']),
      packetHash: serializer.fromJson<String?>(json['packetHash']),
      timelineAtMs: serializer.fromJson<int>(json['timelineAtMs']),
      timestampMs: serializer.fromJson<int>(json['timestampMs']),
      receivedAtMs: serializer.fromJson<int?>(json['receivedAtMs']),
      senderKey: serializer.fromJson<String?>(json['senderKey']),
      senderName: serializer.fromJson<String?>(json['senderName']),
      isOutgoing: serializer.fromJson<bool>(json['isOutgoing']),
      isCli: serializer.fromJson<bool>(json['isCli']),
      status: serializer.fromJson<int>(json['status']),
      rawText: serializer.fromJson<String>(json['rawText']),
      rawPayload: serializer.fromJson<Uint8List?>(json['rawPayload']),
      searchText: serializer.fromJson<String>(json['searchText']),
      containsMarker: serializer.fromJson<bool>(json['containsMarker']),
      messageJson: serializer.fromJson<String>(json['messageJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<int>(kind),
      'storageKey': serializer.toJson<String>(storageKey),
      'messageId': serializer.toJson<String>(messageId),
      'packetHash': serializer.toJson<String?>(packetHash),
      'timelineAtMs': serializer.toJson<int>(timelineAtMs),
      'timestampMs': serializer.toJson<int>(timestampMs),
      'receivedAtMs': serializer.toJson<int?>(receivedAtMs),
      'senderKey': serializer.toJson<String?>(senderKey),
      'senderName': serializer.toJson<String?>(senderName),
      'isOutgoing': serializer.toJson<bool>(isOutgoing),
      'isCli': serializer.toJson<bool>(isCli),
      'status': serializer.toJson<int>(status),
      'rawText': serializer.toJson<String>(rawText),
      'rawPayload': serializer.toJson<Uint8List?>(rawPayload),
      'searchText': serializer.toJson<String>(searchText),
      'containsMarker': serializer.toJson<bool>(containsMarker),
      'messageJson': serializer.toJson<String>(messageJson),
    };
  }

  HistoryMessage copyWith({
    int? id,
    int? kind,
    String? storageKey,
    String? messageId,
    Value<String?> packetHash = const Value.absent(),
    int? timelineAtMs,
    int? timestampMs,
    Value<int?> receivedAtMs = const Value.absent(),
    Value<String?> senderKey = const Value.absent(),
    Value<String?> senderName = const Value.absent(),
    bool? isOutgoing,
    bool? isCli,
    int? status,
    String? rawText,
    Value<Uint8List?> rawPayload = const Value.absent(),
    String? searchText,
    bool? containsMarker,
    String? messageJson,
  }) => HistoryMessage(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    storageKey: storageKey ?? this.storageKey,
    messageId: messageId ?? this.messageId,
    packetHash: packetHash.present ? packetHash.value : this.packetHash,
    timelineAtMs: timelineAtMs ?? this.timelineAtMs,
    timestampMs: timestampMs ?? this.timestampMs,
    receivedAtMs: receivedAtMs.present ? receivedAtMs.value : this.receivedAtMs,
    senderKey: senderKey.present ? senderKey.value : this.senderKey,
    senderName: senderName.present ? senderName.value : this.senderName,
    isOutgoing: isOutgoing ?? this.isOutgoing,
    isCli: isCli ?? this.isCli,
    status: status ?? this.status,
    rawText: rawText ?? this.rawText,
    rawPayload: rawPayload.present ? rawPayload.value : this.rawPayload,
    searchText: searchText ?? this.searchText,
    containsMarker: containsMarker ?? this.containsMarker,
    messageJson: messageJson ?? this.messageJson,
  );
  HistoryMessage copyWithCompanion(HistoryMessagesCompanion data) {
    return HistoryMessage(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      storageKey: data.storageKey.present
          ? data.storageKey.value
          : this.storageKey,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      packetHash: data.packetHash.present
          ? data.packetHash.value
          : this.packetHash,
      timelineAtMs: data.timelineAtMs.present
          ? data.timelineAtMs.value
          : this.timelineAtMs,
      timestampMs: data.timestampMs.present
          ? data.timestampMs.value
          : this.timestampMs,
      receivedAtMs: data.receivedAtMs.present
          ? data.receivedAtMs.value
          : this.receivedAtMs,
      senderKey: data.senderKey.present ? data.senderKey.value : this.senderKey,
      senderName: data.senderName.present
          ? data.senderName.value
          : this.senderName,
      isOutgoing: data.isOutgoing.present
          ? data.isOutgoing.value
          : this.isOutgoing,
      isCli: data.isCli.present ? data.isCli.value : this.isCli,
      status: data.status.present ? data.status.value : this.status,
      rawText: data.rawText.present ? data.rawText.value : this.rawText,
      rawPayload: data.rawPayload.present
          ? data.rawPayload.value
          : this.rawPayload,
      searchText: data.searchText.present
          ? data.searchText.value
          : this.searchText,
      containsMarker: data.containsMarker.present
          ? data.containsMarker.value
          : this.containsMarker,
      messageJson: data.messageJson.present
          ? data.messageJson.value
          : this.messageJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryMessage(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('storageKey: $storageKey, ')
          ..write('messageId: $messageId, ')
          ..write('packetHash: $packetHash, ')
          ..write('timelineAtMs: $timelineAtMs, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('receivedAtMs: $receivedAtMs, ')
          ..write('senderKey: $senderKey, ')
          ..write('senderName: $senderName, ')
          ..write('isOutgoing: $isOutgoing, ')
          ..write('isCli: $isCli, ')
          ..write('status: $status, ')
          ..write('rawText: $rawText, ')
          ..write('rawPayload: $rawPayload, ')
          ..write('searchText: $searchText, ')
          ..write('containsMarker: $containsMarker, ')
          ..write('messageJson: $messageJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    storageKey,
    messageId,
    packetHash,
    timelineAtMs,
    timestampMs,
    receivedAtMs,
    senderKey,
    senderName,
    isOutgoing,
    isCli,
    status,
    rawText,
    $driftBlobEquality.hash(rawPayload),
    searchText,
    containsMarker,
    messageJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryMessage &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.storageKey == this.storageKey &&
          other.messageId == this.messageId &&
          other.packetHash == this.packetHash &&
          other.timelineAtMs == this.timelineAtMs &&
          other.timestampMs == this.timestampMs &&
          other.receivedAtMs == this.receivedAtMs &&
          other.senderKey == this.senderKey &&
          other.senderName == this.senderName &&
          other.isOutgoing == this.isOutgoing &&
          other.isCli == this.isCli &&
          other.status == this.status &&
          other.rawText == this.rawText &&
          $driftBlobEquality.equals(other.rawPayload, this.rawPayload) &&
          other.searchText == this.searchText &&
          other.containsMarker == this.containsMarker &&
          other.messageJson == this.messageJson);
}

class HistoryMessagesCompanion extends UpdateCompanion<HistoryMessage> {
  final Value<int> id;
  final Value<int> kind;
  final Value<String> storageKey;
  final Value<String> messageId;
  final Value<String?> packetHash;
  final Value<int> timelineAtMs;
  final Value<int> timestampMs;
  final Value<int?> receivedAtMs;
  final Value<String?> senderKey;
  final Value<String?> senderName;
  final Value<bool> isOutgoing;
  final Value<bool> isCli;
  final Value<int> status;
  final Value<String> rawText;
  final Value<Uint8List?> rawPayload;
  final Value<String> searchText;
  final Value<bool> containsMarker;
  final Value<String> messageJson;
  const HistoryMessagesCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.storageKey = const Value.absent(),
    this.messageId = const Value.absent(),
    this.packetHash = const Value.absent(),
    this.timelineAtMs = const Value.absent(),
    this.timestampMs = const Value.absent(),
    this.receivedAtMs = const Value.absent(),
    this.senderKey = const Value.absent(),
    this.senderName = const Value.absent(),
    this.isOutgoing = const Value.absent(),
    this.isCli = const Value.absent(),
    this.status = const Value.absent(),
    this.rawText = const Value.absent(),
    this.rawPayload = const Value.absent(),
    this.searchText = const Value.absent(),
    this.containsMarker = const Value.absent(),
    this.messageJson = const Value.absent(),
  });
  HistoryMessagesCompanion.insert({
    this.id = const Value.absent(),
    required int kind,
    required String storageKey,
    required String messageId,
    this.packetHash = const Value.absent(),
    required int timelineAtMs,
    required int timestampMs,
    this.receivedAtMs = const Value.absent(),
    this.senderKey = const Value.absent(),
    this.senderName = const Value.absent(),
    required bool isOutgoing,
    this.isCli = const Value.absent(),
    required int status,
    required String rawText,
    this.rawPayload = const Value.absent(),
    required String searchText,
    this.containsMarker = const Value.absent(),
    required String messageJson,
  }) : kind = Value(kind),
       storageKey = Value(storageKey),
       messageId = Value(messageId),
       timelineAtMs = Value(timelineAtMs),
       timestampMs = Value(timestampMs),
       isOutgoing = Value(isOutgoing),
       status = Value(status),
       rawText = Value(rawText),
       searchText = Value(searchText),
       messageJson = Value(messageJson);
  static Insertable<HistoryMessage> custom({
    Expression<int>? id,
    Expression<int>? kind,
    Expression<String>? storageKey,
    Expression<String>? messageId,
    Expression<String>? packetHash,
    Expression<int>? timelineAtMs,
    Expression<int>? timestampMs,
    Expression<int>? receivedAtMs,
    Expression<String>? senderKey,
    Expression<String>? senderName,
    Expression<bool>? isOutgoing,
    Expression<bool>? isCli,
    Expression<int>? status,
    Expression<String>? rawText,
    Expression<Uint8List>? rawPayload,
    Expression<String>? searchText,
    Expression<bool>? containsMarker,
    Expression<String>? messageJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (storageKey != null) 'storage_key': storageKey,
      if (messageId != null) 'message_id': messageId,
      if (packetHash != null) 'packet_hash': packetHash,
      if (timelineAtMs != null) 'timeline_at_ms': timelineAtMs,
      if (timestampMs != null) 'timestamp_ms': timestampMs,
      if (receivedAtMs != null) 'received_at_ms': receivedAtMs,
      if (senderKey != null) 'sender_key': senderKey,
      if (senderName != null) 'sender_name': senderName,
      if (isOutgoing != null) 'is_outgoing': isOutgoing,
      if (isCli != null) 'is_cli': isCli,
      if (status != null) 'status': status,
      if (rawText != null) 'raw_text': rawText,
      if (rawPayload != null) 'raw_payload': rawPayload,
      if (searchText != null) 'search_text': searchText,
      if (containsMarker != null) 'contains_marker': containsMarker,
      if (messageJson != null) 'message_json': messageJson,
    });
  }

  HistoryMessagesCompanion copyWith({
    Value<int>? id,
    Value<int>? kind,
    Value<String>? storageKey,
    Value<String>? messageId,
    Value<String?>? packetHash,
    Value<int>? timelineAtMs,
    Value<int>? timestampMs,
    Value<int?>? receivedAtMs,
    Value<String?>? senderKey,
    Value<String?>? senderName,
    Value<bool>? isOutgoing,
    Value<bool>? isCli,
    Value<int>? status,
    Value<String>? rawText,
    Value<Uint8List?>? rawPayload,
    Value<String>? searchText,
    Value<bool>? containsMarker,
    Value<String>? messageJson,
  }) {
    return HistoryMessagesCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      storageKey: storageKey ?? this.storageKey,
      messageId: messageId ?? this.messageId,
      packetHash: packetHash ?? this.packetHash,
      timelineAtMs: timelineAtMs ?? this.timelineAtMs,
      timestampMs: timestampMs ?? this.timestampMs,
      receivedAtMs: receivedAtMs ?? this.receivedAtMs,
      senderKey: senderKey ?? this.senderKey,
      senderName: senderName ?? this.senderName,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      isCli: isCli ?? this.isCli,
      status: status ?? this.status,
      rawText: rawText ?? this.rawText,
      rawPayload: rawPayload ?? this.rawPayload,
      searchText: searchText ?? this.searchText,
      containsMarker: containsMarker ?? this.containsMarker,
      messageJson: messageJson ?? this.messageJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(kind.value);
    }
    if (storageKey.present) {
      map['storage_key'] = Variable<String>(storageKey.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (packetHash.present) {
      map['packet_hash'] = Variable<String>(packetHash.value);
    }
    if (timelineAtMs.present) {
      map['timeline_at_ms'] = Variable<int>(timelineAtMs.value);
    }
    if (timestampMs.present) {
      map['timestamp_ms'] = Variable<int>(timestampMs.value);
    }
    if (receivedAtMs.present) {
      map['received_at_ms'] = Variable<int>(receivedAtMs.value);
    }
    if (senderKey.present) {
      map['sender_key'] = Variable<String>(senderKey.value);
    }
    if (senderName.present) {
      map['sender_name'] = Variable<String>(senderName.value);
    }
    if (isOutgoing.present) {
      map['is_outgoing'] = Variable<bool>(isOutgoing.value);
    }
    if (isCli.present) {
      map['is_cli'] = Variable<bool>(isCli.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (rawText.present) {
      map['raw_text'] = Variable<String>(rawText.value);
    }
    if (rawPayload.present) {
      map['raw_payload'] = Variable<Uint8List>(rawPayload.value);
    }
    if (searchText.present) {
      map['search_text'] = Variable<String>(searchText.value);
    }
    if (containsMarker.present) {
      map['contains_marker'] = Variable<bool>(containsMarker.value);
    }
    if (messageJson.present) {
      map['message_json'] = Variable<String>(messageJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryMessagesCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('storageKey: $storageKey, ')
          ..write('messageId: $messageId, ')
          ..write('packetHash: $packetHash, ')
          ..write('timelineAtMs: $timelineAtMs, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('receivedAtMs: $receivedAtMs, ')
          ..write('senderKey: $senderKey, ')
          ..write('senderName: $senderName, ')
          ..write('isOutgoing: $isOutgoing, ')
          ..write('isCli: $isCli, ')
          ..write('status: $status, ')
          ..write('rawText: $rawText, ')
          ..write('rawPayload: $rawPayload, ')
          ..write('searchText: $searchText, ')
          ..write('containsMarker: $containsMarker, ')
          ..write('messageJson: $messageJson')
          ..write(')'))
        .toString();
  }
}

class $HistoryMetadataTable extends HistoryMetadata
    with TableInfo<$HistoryMetadataTable, HistoryMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  HistoryMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryMetadataData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $HistoryMetadataTable createAlias(String alias) {
    return $HistoryMetadataTable(attachedDatabase, alias);
  }
}

class HistoryMetadataData extends DataClass
    implements Insertable<HistoryMetadataData> {
  final String key;
  final String value;
  const HistoryMetadataData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  HistoryMetadataCompanion toCompanion(bool nullToAbsent) {
    return HistoryMetadataCompanion(key: Value(key), value: Value(value));
  }

  factory HistoryMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryMetadataData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  HistoryMetadataData copyWith({String? key, String? value}) =>
      HistoryMetadataData(key: key ?? this.key, value: value ?? this.value);
  HistoryMetadataData copyWithCompanion(HistoryMetadataCompanion data) {
    return HistoryMetadataData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryMetadataData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryMetadataData &&
          other.key == this.key &&
          other.value == this.value);
}

class HistoryMetadataCompanion extends UpdateCompanion<HistoryMetadataData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const HistoryMetadataCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HistoryMetadataCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<HistoryMetadataData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HistoryMetadataCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return HistoryMetadataCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryMetadataCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$MessageHistoryDatabase extends GeneratedDatabase {
  _$MessageHistoryDatabase(QueryExecutor e) : super(e);
  $MessageHistoryDatabaseManager get managers =>
      $MessageHistoryDatabaseManager(this);
  late final $HistoryMessagesTable historyMessages = $HistoryMessagesTable(
    this,
  );
  late final $HistoryMetadataTable historyMetadata = $HistoryMetadataTable(
    this,
  );
  late final Index historyMessageTimeline = Index(
    'history_message_timeline',
    'CREATE INDEX history_message_timeline ON history_messages (kind, storage_key, timeline_at_ms, message_id)',
  );
  late final Index historyMessageIdentity = Index(
    'history_message_identity',
    'CREATE UNIQUE INDEX history_message_identity ON history_messages (kind, storage_key, message_id)',
  );
  late final Index historyMessageSummary = Index(
    'history_message_summary',
    'CREATE INDEX history_message_summary ON history_messages (kind, storage_key, is_cli, timeline_at_ms, message_id)',
  );
  late final Index historyMessageMarker = Index(
    'history_message_marker',
    'CREATE INDEX history_message_marker ON history_messages (kind, storage_key, contains_marker)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    historyMessages,
    historyMetadata,
    historyMessageTimeline,
    historyMessageIdentity,
    historyMessageSummary,
    historyMessageMarker,
  ];
}

typedef $$HistoryMessagesTableCreateCompanionBuilder =
    HistoryMessagesCompanion Function({
      Value<int> id,
      required int kind,
      required String storageKey,
      required String messageId,
      Value<String?> packetHash,
      required int timelineAtMs,
      required int timestampMs,
      Value<int?> receivedAtMs,
      Value<String?> senderKey,
      Value<String?> senderName,
      required bool isOutgoing,
      Value<bool> isCli,
      required int status,
      required String rawText,
      Value<Uint8List?> rawPayload,
      required String searchText,
      Value<bool> containsMarker,
      required String messageJson,
    });
typedef $$HistoryMessagesTableUpdateCompanionBuilder =
    HistoryMessagesCompanion Function({
      Value<int> id,
      Value<int> kind,
      Value<String> storageKey,
      Value<String> messageId,
      Value<String?> packetHash,
      Value<int> timelineAtMs,
      Value<int> timestampMs,
      Value<int?> receivedAtMs,
      Value<String?> senderKey,
      Value<String?> senderName,
      Value<bool> isOutgoing,
      Value<bool> isCli,
      Value<int> status,
      Value<String> rawText,
      Value<Uint8List?> rawPayload,
      Value<String> searchText,
      Value<bool> containsMarker,
      Value<String> messageJson,
    });

class $$HistoryMessagesTableFilterComposer
    extends Composer<_$MessageHistoryDatabase, $HistoryMessagesTable> {
  $$HistoryMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packetHash => $composableBuilder(
    column: $table.packetHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timelineAtMs => $composableBuilder(
    column: $table.timelineAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get receivedAtMs => $composableBuilder(
    column: $table.receivedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderKey => $composableBuilder(
    column: $table.senderKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCli => $composableBuilder(
    column: $table.isCli,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get rawPayload => $composableBuilder(
    column: $table.rawPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get containsMarker => $composableBuilder(
    column: $table.containsMarker,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageJson => $composableBuilder(
    column: $table.messageJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HistoryMessagesTableOrderingComposer
    extends Composer<_$MessageHistoryDatabase, $HistoryMessagesTable> {
  $$HistoryMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packetHash => $composableBuilder(
    column: $table.packetHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timelineAtMs => $composableBuilder(
    column: $table.timelineAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receivedAtMs => $composableBuilder(
    column: $table.receivedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderKey => $composableBuilder(
    column: $table.senderKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCli => $composableBuilder(
    column: $table.isCli,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get rawPayload => $composableBuilder(
    column: $table.rawPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get containsMarker => $composableBuilder(
    column: $table.containsMarker,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageJson => $composableBuilder(
    column: $table.messageJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HistoryMessagesTableAnnotationComposer
    extends Composer<_$MessageHistoryDatabase, $HistoryMessagesTable> {
  $$HistoryMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get packetHash => $composableBuilder(
    column: $table.packetHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timelineAtMs => $composableBuilder(
    column: $table.timelineAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get receivedAtMs => $composableBuilder(
    column: $table.receivedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get senderKey =>
      $composableBuilder(column: $table.senderKey, builder: (column) => column);

  GeneratedColumn<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCli =>
      $composableBuilder(column: $table.isCli, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get rawText =>
      $composableBuilder(column: $table.rawText, builder: (column) => column);

  GeneratedColumn<Uint8List> get rawPayload => $composableBuilder(
    column: $table.rawPayload,
    builder: (column) => column,
  );

  GeneratedColumn<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get containsMarker => $composableBuilder(
    column: $table.containsMarker,
    builder: (column) => column,
  );

  GeneratedColumn<String> get messageJson => $composableBuilder(
    column: $table.messageJson,
    builder: (column) => column,
  );
}

class $$HistoryMessagesTableTableManager
    extends
        RootTableManager<
          _$MessageHistoryDatabase,
          $HistoryMessagesTable,
          HistoryMessage,
          $$HistoryMessagesTableFilterComposer,
          $$HistoryMessagesTableOrderingComposer,
          $$HistoryMessagesTableAnnotationComposer,
          $$HistoryMessagesTableCreateCompanionBuilder,
          $$HistoryMessagesTableUpdateCompanionBuilder,
          (
            HistoryMessage,
            BaseReferences<
              _$MessageHistoryDatabase,
              $HistoryMessagesTable,
              HistoryMessage
            >,
          ),
          HistoryMessage,
          PrefetchHooks Function()
        > {
  $$HistoryMessagesTableTableManager(
    _$MessageHistoryDatabase db,
    $HistoryMessagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoryMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoryMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoryMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> kind = const Value.absent(),
                Value<String> storageKey = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String?> packetHash = const Value.absent(),
                Value<int> timelineAtMs = const Value.absent(),
                Value<int> timestampMs = const Value.absent(),
                Value<int?> receivedAtMs = const Value.absent(),
                Value<String?> senderKey = const Value.absent(),
                Value<String?> senderName = const Value.absent(),
                Value<bool> isOutgoing = const Value.absent(),
                Value<bool> isCli = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<String> rawText = const Value.absent(),
                Value<Uint8List?> rawPayload = const Value.absent(),
                Value<String> searchText = const Value.absent(),
                Value<bool> containsMarker = const Value.absent(),
                Value<String> messageJson = const Value.absent(),
              }) => HistoryMessagesCompanion(
                id: id,
                kind: kind,
                storageKey: storageKey,
                messageId: messageId,
                packetHash: packetHash,
                timelineAtMs: timelineAtMs,
                timestampMs: timestampMs,
                receivedAtMs: receivedAtMs,
                senderKey: senderKey,
                senderName: senderName,
                isOutgoing: isOutgoing,
                isCli: isCli,
                status: status,
                rawText: rawText,
                rawPayload: rawPayload,
                searchText: searchText,
                containsMarker: containsMarker,
                messageJson: messageJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int kind,
                required String storageKey,
                required String messageId,
                Value<String?> packetHash = const Value.absent(),
                required int timelineAtMs,
                required int timestampMs,
                Value<int?> receivedAtMs = const Value.absent(),
                Value<String?> senderKey = const Value.absent(),
                Value<String?> senderName = const Value.absent(),
                required bool isOutgoing,
                Value<bool> isCli = const Value.absent(),
                required int status,
                required String rawText,
                Value<Uint8List?> rawPayload = const Value.absent(),
                required String searchText,
                Value<bool> containsMarker = const Value.absent(),
                required String messageJson,
              }) => HistoryMessagesCompanion.insert(
                id: id,
                kind: kind,
                storageKey: storageKey,
                messageId: messageId,
                packetHash: packetHash,
                timelineAtMs: timelineAtMs,
                timestampMs: timestampMs,
                receivedAtMs: receivedAtMs,
                senderKey: senderKey,
                senderName: senderName,
                isOutgoing: isOutgoing,
                isCli: isCli,
                status: status,
                rawText: rawText,
                rawPayload: rawPayload,
                searchText: searchText,
                containsMarker: containsMarker,
                messageJson: messageJson,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HistoryMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$MessageHistoryDatabase,
      $HistoryMessagesTable,
      HistoryMessage,
      $$HistoryMessagesTableFilterComposer,
      $$HistoryMessagesTableOrderingComposer,
      $$HistoryMessagesTableAnnotationComposer,
      $$HistoryMessagesTableCreateCompanionBuilder,
      $$HistoryMessagesTableUpdateCompanionBuilder,
      (
        HistoryMessage,
        BaseReferences<
          _$MessageHistoryDatabase,
          $HistoryMessagesTable,
          HistoryMessage
        >,
      ),
      HistoryMessage,
      PrefetchHooks Function()
    >;
typedef $$HistoryMetadataTableCreateCompanionBuilder =
    HistoryMetadataCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$HistoryMetadataTableUpdateCompanionBuilder =
    HistoryMetadataCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$HistoryMetadataTableFilterComposer
    extends Composer<_$MessageHistoryDatabase, $HistoryMetadataTable> {
  $$HistoryMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HistoryMetadataTableOrderingComposer
    extends Composer<_$MessageHistoryDatabase, $HistoryMetadataTable> {
  $$HistoryMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HistoryMetadataTableAnnotationComposer
    extends Composer<_$MessageHistoryDatabase, $HistoryMetadataTable> {
  $$HistoryMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$HistoryMetadataTableTableManager
    extends
        RootTableManager<
          _$MessageHistoryDatabase,
          $HistoryMetadataTable,
          HistoryMetadataData,
          $$HistoryMetadataTableFilterComposer,
          $$HistoryMetadataTableOrderingComposer,
          $$HistoryMetadataTableAnnotationComposer,
          $$HistoryMetadataTableCreateCompanionBuilder,
          $$HistoryMetadataTableUpdateCompanionBuilder,
          (
            HistoryMetadataData,
            BaseReferences<
              _$MessageHistoryDatabase,
              $HistoryMetadataTable,
              HistoryMetadataData
            >,
          ),
          HistoryMetadataData,
          PrefetchHooks Function()
        > {
  $$HistoryMetadataTableTableManager(
    _$MessageHistoryDatabase db,
    $HistoryMetadataTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoryMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoryMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoryMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoryMetadataCompanion(
                key: key,
                value: value,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => HistoryMetadataCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HistoryMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$MessageHistoryDatabase,
      $HistoryMetadataTable,
      HistoryMetadataData,
      $$HistoryMetadataTableFilterComposer,
      $$HistoryMetadataTableOrderingComposer,
      $$HistoryMetadataTableAnnotationComposer,
      $$HistoryMetadataTableCreateCompanionBuilder,
      $$HistoryMetadataTableUpdateCompanionBuilder,
      (
        HistoryMetadataData,
        BaseReferences<
          _$MessageHistoryDatabase,
          $HistoryMetadataTable,
          HistoryMetadataData
        >,
      ),
      HistoryMetadataData,
      PrefetchHooks Function()
    >;

class $MessageHistoryDatabaseManager {
  final _$MessageHistoryDatabase _db;
  $MessageHistoryDatabaseManager(this._db);
  $$HistoryMessagesTableTableManager get historyMessages =>
      $$HistoryMessagesTableTableManager(_db, _db.historyMessages);
  $$HistoryMetadataTableTableManager get historyMetadata =>
      $$HistoryMetadataTableTableManager(_db, _db.historyMetadata);
}

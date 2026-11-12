import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../helpers/companion_cli_protocol.dart';
import '../models/companion_cli_entry.dart';
import '../storage/companion_cli_store.dart';

/// Единственная локальная CLI-операция. Таймеры/ответы относятся к захваченному
/// node key, а поздние ответы никогда не дописывают новую операцию.
class CompanionCliSession extends ChangeNotifier {
  CompanionCliSession({required this.send, required this.nodeKey, required this.nodeName,
    required this.available, CompanionCliHistory? history,
    this.runWork, this.onTimeout, this.timeout = companionCliTimeout})
    : _history = history ?? CompanionCliStore();

  final Future<void> Function(Uint8List) send;
  final String Function() nodeKey;
  final String Function() nodeName;
  final bool Function() available;
  final Future<void> Function(Future<void> Function())? runWork;
  final void Function(String prefix)? onTimeout;
  final Duration timeout;
  final CompanionCliHistory _history;
  final _tags = CompanionCliTags();
  final _entries = <CompanionCliEntry>[];
  Future<void>? _loading;
  Completer<Uint8List>? _reply;
  String? _prefix;
  String? _activeNode;
  Completer<void>? _operationDone;
  bool Function()? _canSend;
  bool _disposed = false;
  bool get busy => _operationDone != null;
  bool isActive(String prefix) => !_disposed && _prefix == prefix &&
      _activeNode == nodeKey() && available() && _canSend?.call() != false;
  List<CompanionCliEntry> entries({required bool shared}) => List.unmodifiable(
    _entries.where((entry) => shared || entry.nodeKey == nodeKey()));

  void _changed() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> ensureLoaded() => _loading ??= _load().catchError((Object error) {
    _loading = null;
    throw error;
  });

  Future<void> _load() async {
    final stored = await _history.load();
    final loaded = <CompanionCliEntry>[];
    for (var entry in stored) {
      // После перезапуска не возобновляем выполнение старой команды.
      if (entry.status == CompanionCliStatus.pending) {
        entry = entry.finish(CompanionCliStatus.disconnected);
        await _history.save(entry);
      }
      loaded.add(entry);
    }
    _entries.addAll(loaded);
    _changed();
  }

  void observeReply(Uint8List frame) {
    final reply = _reply;
    final prefix = _prefix;
    if (reply == null || reply.isCompleted || prefix == null) {
      return;
    }
    if (!isActive(prefix)) {
      return;
    }
    if (frame.isNotEmpty && frame.first == 1) {
      reply.completeError(const CompanionCliException('protocol'));
    } else if (companionCliReplyMatches(frame, prefix)) {
      reply.complete(frame);
    }
  }

  void connectionChanged() {
    final reply = _reply;
    if (reply != null && !reply.isCompleted &&
        (_prefix == null || !isActive(_prefix!))) {
      reply.completeError(const CompanionCliException('disconnected'));
    }
    _changed();
  }

  Future<void> sendCommand(String command) {
    return _runExclusive(() {
      final prefix = _tags.allocate();
      final frame = buildCompanionCliFrame(command, prefix);
      return _execute(command, prefix, frame);
    });
  }

  /// Automated commands share the manual console's tags and wire queue.
  /// Keep the slot across a read followed by a conditional write.
  Future<void> runTransient(
    Future<void> Function(Future<String> Function(String) sendCommand) action, {
    required bool Function() canSend,
  }) async {
    final capturedNode = nodeKey();
    bool sameSession() => nodeKey() == capturedNode && canSend();

    while (sameSession() && _operationDone != null) {
      await _operationDone!.future;
    }
    if (!sameSession()) throw const CompanionCliException('disconnected');
    await _runExclusive(() => action((command) {
      final prefix = _tags.allocate();
      return _exchange(
        buildCompanionCliFrame(command, prefix),
        prefix,
        capturedNode,
        canSend: sameSession,
      );
    }));
  }

  Future<void> _runExclusive(Future<void> Function() operation) async {
    if (_disposed || !available() || nodeKey().isEmpty) {
      throw const CompanionCliException('unavailable');
    }
    if (busy) throw const CompanionCliException('busy');
    final done = Completer<void>();
    _operationDone = done;
    _changed();
    try {
      final work = runWork;
      if (work == null) {
        await operation();
      } else {
        await work(operation);
      }
    } finally {
      _operationDone = null;
      done.complete();
      _changed();
    }
  }

  Future<void> _execute(String command, String prefix, Uint8List frame) async {
    final capturedNode = nodeKey();
    final capturedName = nodeName();
    await ensureLoaded();
    if (_disposed || !available() || nodeKey() != capturedNode) {
      throw const CompanionCliException('disconnected');
    }
    final revision = _history.revision(capturedNode);
    var entry = CompanionCliEntry(id: const Uuid().v4(), nodeKey: capturedNode,
      nodeName: capturedName, command: command, createdAt: DateTime.now());
    // Сначала SQL-запись; очистка до завершения записи отменяет ещё не посланное.
    if (!await _history.save(entry, revision: revision) ||
        _history.revision(capturedNode) != revision) {
      return;
    }
    _entries.add(entry);
    if (_disposed || !available() || nodeKey() != capturedNode) {
      entry = entry.finish(CompanionCliStatus.disconnected);
      _replace(entry, revision);
      _changed();
      await _history.save(entry, revision: revision);
      return;
    }
    try {
      final response = await _exchange(frame, prefix, capturedNode);
      entry = entry.finish(CompanionCliStatus.replied, response: response);
    } on TimeoutException {
      entry = entry.finish(CompanionCliStatus.failed, failure: 'timeout');
    } on CompanionCliException catch (error) {
      entry = entry.finish(error.code == 'disconnected'
        ? CompanionCliStatus.disconnected : CompanionCliStatus.failed, failure: error.code);
    } catch (_) {
      entry = entry.finish(CompanionCliStatus.failed, failure: 'sendFailed');
    }
    _replace(entry, revision);
    await _history.save(entry, revision: revision);
  }

  Future<String> _exchange(
    Uint8List frame,
    String prefix,
    String capturedNode, {
    bool Function()? canSend,
  }) async {
    if (_disposed || !available() || nodeKey() != capturedNode ||
        canSend?.call() == false) {
      throw const CompanionCliException('disconnected');
    }
    _activeNode = capturedNode;
    _prefix = prefix;
    _canSend = canSend;
    final reply = Completer<Uint8List>();
    _reply = reply;
    // A reply or disconnect can arrive before the transport write completes.
    unawaited(reply.future.catchError((Object _) => Uint8List(0)));
    _changed();
    try {
      await send(frame).timeout(timeout);
      return companionCliReplyText(await reply.future.timeout(timeout));
    } on TimeoutException {
      onTimeout?.call(prefix);
      rethrow;
    } finally {
      _reply = null;
      _prefix = null;
      _activeNode = null;
      _canSend = null;
    }
  }

  void _replace(CompanionCliEntry entry, int revision) {
    if (_history.revision(entry.nodeKey) != revision) {
      return;
    }
    final index = _entries.indexWhere((value) => value.nodeKey == entry.nodeKey && value.id == entry.id);
    if (index >= 0) {
      _entries[index] = entry;
      _changed();
    }
  }

  Future<void> clearHistory(String targetNode) async {
    await ensureLoaded();
    await _history.clear(targetNode);
    _entries.removeWhere((entry) => entry.nodeKey == targetNode);
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    final reply = _reply;
    if (reply != null && !reply.isCompleted) {
      reply.completeError(const CompanionCliException('disconnected'));
    }
    super.dispose();
  }
}

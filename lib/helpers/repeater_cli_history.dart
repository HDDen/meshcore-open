import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/repeater_cli_entry.dart';
import '../storage/repeater_cli_store.dart';

/// Только transcript конкретного экрана/адреса, не журнал всех фоновых команд.
class RepeaterCliHistory extends ChangeNotifier {
  RepeaterCliHistory({required this.nodeKey, required this.nodeName,
    required this.repeaterKey, required this.repeaterName, RepeaterCliStore? store})
    : _store = store ?? RepeaterCliStore();

  final String nodeKey;
  final String nodeName;
  final String repeaterKey;
  final String repeaterName;
  final RepeaterCliStore _store;
  final _entries = <RepeaterCliEntry>[];
  List<Map<String, String>> _transcript = const [];
  Future<void>? _loading;
  bool loaded = false;
  bool _disposed = false;
  int get revision => _store.revision(nodeKey, repeaterKey);
  List<Map<String, String>> get transcript => _transcript;

  void _changed() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _refresh() {
    _transcript = List.unmodifiable(_entries.map((entry) => entry.transcript));
    _changed();
  }

  Future<void> ensureLoaded() => _loading ??= _load().catchError((Object error) {
    _loading = null;
    throw error;
  });

  Future<void> _load() async {
    final before = revision;
    final entries = await _store.load(nodeKey, repeaterKey);
    if (before == revision) {
      _entries..clear()..addAll(entries);
    }
    loaded = true;
    _refresh();
  }

  Future<bool> append(String type, String text, {required int revision}) async {
    await ensureLoaded();
    final entry = RepeaterCliEntry(id: const Uuid().v4(), nodeKey: nodeKey,
      nodeName: nodeName, repeaterKey: repeaterKey, repeaterName: repeaterName,
      createdAt: DateTime.now(), type: type, text: text);
    final saved = await _store.save(entry, revision: revision);
    if (saved && this.revision == revision) {
      _entries.add(entry);
      _refresh();
    }
    return saved;
  }

  Future<void> clear() async {
    await ensureLoaded();
    await _store.clear(nodeKey, repeaterKey);
    _entries.clear();
    _refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

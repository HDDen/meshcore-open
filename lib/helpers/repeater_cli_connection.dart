import 'dart:async';
import 'dart:typed_data';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../services/repeater_command_service.dart';
import 'repeater_cli_history.dart';

/// Один parser/service/transcript на адрес консоли. Пока ждём ответ, закрытие
/// экрана не теряет его; повторно открытый экран использует те же pending tags.
class RepeaterCliConnection {
  static final _owners = Expando<Map<String, RepeaterCliConnection>>();

  factory RepeaterCliConnection.attach(MeshCoreConnector connector, Contact repeater) {
    final owners = _owners[connector] ??= <String, RepeaterCliConnection>{};
    final key = '${connector.selfPublicKeyHex}:${repeater.publicKeyHex}';
    final connection = owners.putIfAbsent(key, () => RepeaterCliConnection._(connector, repeater, key));
    connection._views++;
    return connection;
  }

  RepeaterCliConnection._(this._connector, this._repeater, this._key)
    : _service = RepeaterCommandService(_connector),
      _target = Uint8List.fromList(_repeater.publicKey),
      history = RepeaterCliHistory(nodeKey: _connector.selfPublicKeyHex,
        nodeName: _connector.selfName ?? _connector.selfPublicKeyHex,
        repeaterKey: _repeater.publicKeyHex, repeaterName: _repeater.name) {
    _frames = _connector.receivedFrames.listen(_onFrame);
  }

  final MeshCoreConnector _connector;
  final Contact _repeater;
  final String _key;
  final Uint8List _target;
  final RepeaterCommandService _service;
  final RepeaterCliHistory history;
  StreamSubscription<Uint8List>? _frames;
  int _views = 0;
  int _pending = 0;
  bool _closed = false;

  void _onFrame(Uint8List frame) {
    if (frame.isEmpty || _connector.selfPublicKeyHex != history.nodeKey) { return; }
    if (frame.first != respCodeContactMsgRecv && frame.first != respCodeContactMsgRecvV3) { return; }
    final parsed = parseContactMessageText(frame);
    if (parsed == null || parsed.senderPrefix.length < 6 || _target.length < 6) { return; }
    for (var i = 0; i < 6; i++) {
      if (parsed.senderPrefix[i] != _target[i]) { return; }
    }
    _service.handleResponse(_repeater, parsed.text);
  }

  Future<T> _keep<T>(Future<T> Function() operation) async {
    if (_closed) { throw StateError('CLI connection is closed'); }
    _pending++;
    try {
      return await operation();
    } finally {
      _pending--;
      _closeIfUnused();
    }
  }

  Future<String> sendCommand(Contact repeater, String command, {int retries = 1, bool raw = false}) =>
      _keep(() => _service.sendCommand(repeater, command, retries: retries, raw: raw));
  Future<void> sendUnansweredLine(Contact repeater, String line) =>
      _keep(() => _service.sendUnansweredLine(repeater, line));
  String previewFramedCommand(String command) => _service.previewFramedCommand(command);

  void release() {
    if (_views > 0) { _views--; }
    _closeIfUnused();
  }

  void _closeIfUnused() {
    if (_closed || _views > 0 || _pending > 0) { return; }
    _closed = true;
    _frames?.cancel();
    _frames = null;
    _service.dispose();
    history.dispose();
    final owners = _owners[_connector];
    if (identical(owners?[_key], this)) { owners?.remove(_key); }
  }
}

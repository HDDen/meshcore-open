/// One navigation per live TCP session. Settings/native preparation may await;
/// a later reconnect must invalidate an earlier completion, even at the same IP.
class TcpConnectionNavigation {
  int _revision = 0;
  bool _disposed = false;
  bool _running = false;
  bool _navigated = false;
  Object? _pendingIdentity;

  bool get hasNavigated => _navigated;

  void reset() {
    _revision++;
    _running = false;
    _pendingIdentity = null;
    _navigated = false;
  }

  void dispose() {
    _disposed = true;
    _revision++;
  }

  Future<void> open({
    required Object? identity,
    required bool Function() stillCurrent,
    required Future<void> Function() prepare,
    required void Function() navigate,
  }) async {
    if (_disposed || _navigated || !stillCurrent() ||
        (_running && identical(_pendingIdentity, identity))) {
      return;
    }
    final revision = ++_revision;
    _running = true;
    _pendingIdentity = identity;
    try {
      await prepare();
      if (_disposed || revision != _revision || !stillCurrent()) {
        return;
      }
      // Set only at the actual handoff. A covered route or a stale completion
      // must not disable the next chance to navigate.
      _navigated = true;
      navigate();
    } finally {
      if (revision == _revision) {
        _running = false;
        _pendingIdentity = null;
      }
    }
  }
}

/// The transport renders endpoints as host:port, including tailscale:// hosts
/// and IPv6. Split at the last colon instead of using editable form fields.
({String host, int port})? connectedTcpEndpoint(String? endpoint) {
  if (endpoint == null) {
    return null;
  }
  final separator = endpoint.lastIndexOf(':');
  if (separator <= 0) {
    return null;
  }
  final port = int.tryParse(endpoint.substring(separator + 1));
  if (port == null || port < 1 || port > 65535) {
    return null;
  }
  return (host: endpoint.substring(0, separator), port: port);
}

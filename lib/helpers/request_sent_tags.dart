/// Pairs the answer to a request sent to a remote node, a neighbours or a
/// telemetry request, with the `RESP_CODE_SENT` the node gave for it.
///
/// The node answers every command it is handed, in turn, so while a request
/// waits, the SENT of a message the app sends meanwhile arrives as well,
/// before the request's own or after it. The screens used to take the tag
/// from whichever SENT came last and dropped the answer whenever another
/// send fell in between. Every tag seen while the request waits is kept
/// instead: the answer carries its request's tag, and the companion passes
/// on the answer to its latest binary request only (`pending_req`), so a
/// tag that belongs to another command matches nothing.
///
/// The estimates those SENTs carry set the timeout the same way. The first
/// replaces the fallback the screen armed after writing the request; a
/// later one, which may be another command's, can push the deadline back
/// but never bring it forward.
class RequestSentTags {
  Set<int>? _tags;
  DateTime? _deadline;

  /// Whether a request is out and its answer still matches.
  bool get isWaiting => _tags != null;

  /// Whether a SENT estimate has set the deadline of the current request.
  bool get hasDeadline => _deadline != null;

  /// Opens a request, just before its frame is written, so that a SENT
  /// arriving while the write is still under way is kept too.
  void start() {
    _tags = <int>{};
    _deadline = null;
  }

  /// Closes the wait: the answer arrived, or a new request is being
  /// prepared and nothing that arrives before it goes out is its own.
  void clear() {
    _tags = null;
    _deadline = null;
  }

  /// Keeps the tag of a SENT that arrived while the request waits and
  /// returns the timeout to arm from [now], or null when an earlier SENT
  /// already set a deadline no sooner than this one.
  Duration? recordSent(int tag, Duration estimate, {DateTime? now}) {
    final tags = _tags;
    if (tags == null) return null;
    tags.add(tag);
    final deadline = (now ?? DateTime.now()).add(estimate);
    final current = _deadline;
    if (current != null && !deadline.isAfter(current)) return null;
    _deadline = deadline;
    return estimate;
  }

  /// Whether [tag], read from an answer, belongs to the current request.
  bool matches(int tag) => _tags?.contains(tag) ?? false;
}

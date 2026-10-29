/// App-side contact options read together from the initialized storage cache.
/// No platform call is needed before opening a settings sheet or composing text.
class ContactSettingsSnapshot {
  const ContactSettingsSnapshot({
    this.mcmpEnabled = false,
    this.mcmpVersion = 3,
    this.mcmpUseSign = false,
    this.mcotxtEnabled = false,
    this.mcotxtPlainWhenSmaller = true,
    this.smazEnabled = false,
    this.cyr2LatEnabled = false,
    this.cyr2LatProfileId,
    this.sendingDelayEnabled = false,
    this.quickAnswerIds = const [],
    this.urlImagesEnabled = false,
  });

  final bool mcmpEnabled;
  final int mcmpVersion;
  final bool mcmpUseSign;
  final bool mcotxtEnabled;
  final bool mcotxtPlainWhenSmaller;
  final bool smazEnabled;
  final bool cyr2LatEnabled;
  final String? cyr2LatProfileId;
  final bool sendingDelayEnabled;
  final List<String> quickAnswerIds;
  final bool urlImagesEnabled;
}

/// Codec switches write several preferences. Keep complete selections in order,
/// so an earlier enable cannot finish after a later disable and resurrect itself.
class ContactCompressionWrites {
  Future<void> _tail = Future<void>.value();

  Future<void> run(Future<void> Function() write) {
    final result = _tail.then((_) => write());
    // A failed write is reported to its caller without blocking later writes.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

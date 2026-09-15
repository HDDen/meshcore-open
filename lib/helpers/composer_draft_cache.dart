class ComposerDraftCache {
  ComposerDraftCache._();

  static final Map<String, String> _drafts = <String, String>{};

  static String contactKey(String publicKeyHex) => 'contact:$publicKeyHex';

  static String channelKey(int channelIndex) => 'channel:$channelIndex';

  static String? read(String key) {
    final draft = _drafts[key];
    return draft == null || draft.isEmpty ? null : draft;
  }

  static void write(String key, String text) {
    if (text.isEmpty) {
      _drafts.remove(key);
      return;
    }
    _drafts[key] = text;
  }

  static void clear(String key) {
    _drafts.remove(key);
  }
}

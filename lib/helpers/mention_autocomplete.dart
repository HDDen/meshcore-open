import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/contact.dart';

/// A run of message text: either plain text, or an `@[name]` mention that
/// should be drawn as a chip instead of raw characters.
class MentionSegment {
  /// Plain text, or the bare name for a mention.
  final String text;

  final bool isMention;

  const MentionSegment(this.text, {this.isMention = false});
}

/// Reads finished `@[name]` mentions out of message text. The composer
/// writes this form (see [MentionAutocomplete]) and replies have used it all
/// along, so incoming text can carry one anywhere in the sentence.
class MentionText {
  MentionText._();

  static final RegExp pattern = RegExp(r'@\[([^\]]+)\]');

  static bool has(String text) => pattern.hasMatch(text);

  /// Splits [text] into alternating plain and mention runs, in order.
  static List<MentionSegment> split(String text) {
    final segments = <MentionSegment>[];
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        segments.add(MentionSegment(text.substring(cursor, match.start)));
      }
      segments.add(MentionSegment(match.group(1)!, isMention: true));
      cursor = match.end;
    }
    if (cursor < text.length) {
      segments.add(MentionSegment(text.substring(cursor)));
    }
    return segments;
  }
}

/// The "@name" being typed at the caret.
class MentionQuery {
  /// Index of the `@` that opened it.
  final int start;

  /// Caret position, where the typed name ends.
  final int end;

  /// What has been typed after the `@`.
  final String filter;

  const MentionQuery({
    required this.start,
    required this.end,
    required this.filter,
  });
}

/// Holds the suggestion search back while an `@name` is still being typed.
///
/// The search runs from a bare `TextEditingController` listener, which fires
/// on every value change — selection included, so an Android selection drag
/// notifies continuously — and it walks the node's contacts together with a
/// discovery cache of up to 500 entries. Waiting for the typing to pause keeps
/// the picker from reshuffling under a half-written name and keeps that walk
/// off the common keystroke.
///
/// Only the search waits, and only while a name is being typed. Opening the
/// picker on the bare `@` is immediate — there is no earlier keystroke to wait
/// between, and the trigger character has always brought the list up at once.
/// Closing it stays immediate too, as does tracking the caret range: a panel
/// lingering after the mention has ended, or a replacement range pointing at
/// text the user has already moved past, would be wrong rather than merely
/// late.
class MentionSearchDebounce {
  MentionSearchDebounce({this.delay = const Duration(milliseconds: 750)});

  final Duration delay;
  Timer? _timer;

  /// Schedules [search] for [query], dropping whatever was pending.
  ///
  /// An empty filter is the `@` on its own: the user has just opened a
  /// mention and nothing is being filtered yet, so the full list appears
  /// straight away. Every character after it restarts the wait instead, which
  /// is where the delay belongs — between the keystrokes of a name.
  void schedule(MentionQuery query, VoidCallback search) {
    cancel();
    if (query.filter.isEmpty) {
      search();
      return;
    }
    _timer = Timer(delay, search);
  }

  /// Drops a pending search. Called when the mention ends and from `dispose`,
  /// so a timer cannot fire into a screen that is gone.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Turns a half-typed `@name` in a composer into a proper `@[name]` mention.
///
/// The mention format is the same one replies use, so the receiving app
/// resolves it to a known contact instead of leaving a bare word.
class MentionAutocomplete {
  MentionAutocomplete._();

  /// Reads the mention being typed at the caret, or null when there is none:
  /// the caret sits inside a selection, no `@` precedes it, the `@` does not
  /// open a word, or whitespace has already ended the name.
  static MentionQuery? queryAt(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;

    final caret = selection.baseOffset;
    final text = value.text;
    if (caret <= 0 || caret > text.length) return null;

    var index = caret - 1;
    while (index >= 0) {
      final char = text[index];
      if (char == '@') break;
      // A name never spans whitespace, and the brackets mean the mention is
      // already complete.
      if (char.trim().isEmpty || char == '[' || char == ']') return null;
      index--;
    }
    if (index < 0) return null;
    // The `@` must open a word: start of the text, or preceded by whitespace.
    if (index > 0 && text[index - 1].trim().isNotEmpty) return null;

    return MentionQuery(
      start: index,
      end: caret,
      filter: text.substring(index + 1, caret),
    );
  }

  /// Contacts matching [filter], alphabetically and with no name twice. An
  /// empty filter lists them all, which is what the user sees the moment they
  /// type `@`.
  ///
  /// Callers pass the node's own contacts together with the nodes the app has
  /// merely heard advertise, so somebody can be addressed before they have
  /// been added to the radio. Those two sets overlap, and a mention carries
  /// nothing but a name, so a repeated name would put visually identical rows
  /// in the picker with nothing to choose between them. The first occurrence
  /// wins: it keeps a real contact ahead of a discovery entry when the caller
  /// passes them in that order, and it is what makes the surviving row the
  /// same one on every rebuild — the callers compare suggestion lists by
  /// public key, and an unstable pick would rebuild the picker under the
  /// user's finger.
  ///
  /// Names are compared trimmed and case-insensitively, which also leaves the
  /// sort below without ties to break.
  ///
  /// [excludeKeyHex] drops a single key, used for this node itself: the picker
  /// offers people to address, and the user is not one of them.
  static List<Contact> suggestionsFor(
    Iterable<Contact> contacts,
    String filter, {
    String? excludeKeyHex,
  }) {
    final needle = filter.toLowerCase();
    final seen = <String>{};
    final matches = <Contact>[];
    for (final contact in contacts) {
      final name = contact.name.trim();
      if (name.isEmpty) continue;
      final lowered = name.toLowerCase();
      if (needle.isNotEmpty && !lowered.contains(needle)) continue;
      if (excludeKeyHex != null && contact.publicKeyHex == excludeKeyHex) {
        continue;
      }
      if (!seen.add(lowered)) continue;
      matches.add(contact);
    }
    matches.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return matches;
  }

  /// Replaces the typed fragment with a finished mention and leaves the caret
  /// right after the closing bracket — no trailing space, so the user decides
  /// what follows.
  static TextEditingValue apply(
    TextEditingValue value,
    MentionQuery query,
    String name,
  ) {
    final mention = '@[$name]';
    return TextEditingValue(
      text: value.text.replaceRange(query.start, query.end, mention),
      selection: TextSelection.collapsed(offset: query.start + mention.length),
    );
  }
}

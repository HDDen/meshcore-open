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

  /// Contacts matching [filter], alphabetically. An empty filter lists them
  /// all, which is what the user sees the moment they type `@`.
  static List<Contact> suggestionsFor(
    Iterable<Contact> contacts,
    String filter,
  ) {
    final needle = filter.toLowerCase();
    final matches = [
      for (final contact in contacts)
        if (contact.name.trim().isNotEmpty &&
            (needle.isEmpty || contact.name.toLowerCase().contains(needle)))
          contact,
    ];
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

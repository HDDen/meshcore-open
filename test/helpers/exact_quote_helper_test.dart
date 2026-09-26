import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/exact_quote_helper.dart';

// A direct conversation: its messages carry no author, the chat names them.
typedef _Entry = ({String author, String text, String id});

String _authorOf(_Entry entry) => entry.author;
String _idOf(_Entry entry) => entry.id;
String _textOf(_Entry entry) => entry.text;

const _history = <_Entry>[
  (author: 'Vasya', text: 'Where do we meet tomorrow?', id: 'v1'),
  (author: 'Me', text: 'At the entrance at seven', id: 'm1'),
  (author: 'Vasya', text: 'Fine', id: 'v2'),
];

String _format(String senderName, String quotedId) {
  final quoted = _history.firstWhere((entry) => entry.id == quotedId);
  return ExactQuoteHelper.formatReplyWith(
    senderName: senderName,
    text: 'ok',
    quotedText: quoted.text,
    quotedMessageId: quoted.id,
    history: _history,
    authorOf: _authorOf,
    idOf: _idOf,
    enabled: true,
    maxFragmentBytes: 30,
  );
}

ResolvedQuote<_Entry>? _resolve(String body, String mentionedNode) =>
    ExactQuoteHelper.resolveReplyWith(
      body: body,
      mentionedNode: mentionedNode,
      history: _history,
      authorOf: _authorOf,
      textOf: _textOf,
    );

void main() {
  group('ExactQuoteHelper over any message type', () {
    test('a quote of an older message carries a fragment', () {
      expect(
        _format('Vasya', 'v1'),
        '@[Vasya] >Where do we meet tomorrow?\nok',
      );
    });

    test("the author's newest message needs no fragment", () {
      expect(_format('Vasya', 'v2'), '@[Vasya] ok');
    });

    test('our own message is quoted under our name', () {
      expect(_format('Me', 'm1'), '@[Me] ok');
    });

    test('the receiver finds the quoted message by author and fragment', () {
      final resolved = _resolve('>Where do we meet tomorrow?\nok', 'Vasya');

      expect(resolved?.text, 'ok');
      expect(resolved?.fragment, 'Where do we meet tomorrow?');
      expect(resolved?.quoted?.id, 'v1');
    });

    test('a fragment under another author matches nothing', () {
      final resolved = _resolve('>Where do we meet\nok', 'Me');

      expect(resolved?.fragment, 'Where do we meet');
      expect(resolved?.quoted, isNull);
    });

    test('a body without a quote line resolves to nothing', () {
      expect(_resolve('ok', 'Vasya'), isNull);
      expect(ExactQuoteHelper.splitQuoteLine('>\nok'), isNull);
      expect(
        ExactQuoteHelper.splitQuoteLine('>frag\nok'),
        (fragment: 'frag', text: 'ok'),
      );
    });
  });
}

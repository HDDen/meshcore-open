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

  group('a quote trimmed in the composer', () {
    // The composer's prefix for a reply to Vasya's first message, cut short
    // by a small budget so that it ends in an ellipsis.
    final quoted = _history[0];
    final prefix = ExactQuoteHelper.formatReplyWith(
      senderName: 'Vasya',
      text: '',
      quotedText: quoted.text,
      quotedMessageId: quoted.id,
      history: _history,
      authorOf: _authorOf,
      idOf: _idOf,
      enabled: true,
      maxFragmentBytes: 12,
    );

    ComposerReply? composerReply(String text) =>
        ExactQuoteHelper.composerReply(
          text: text,
          prefix: prefix,
          senderName: 'Vasya',
          quotedText: quoted.text,
        );

    String send(String? quoteFragment) => ExactQuoteHelper.formatReplyWith(
      senderName: 'Vasya',
      text: 'ok',
      quotedText: quoted.text,
      quotedMessageId: quoted.id,
      history: _history,
      authorOf: _authorOf,
      idOf: _idOf,
      enabled: true,
      maxFragmentBytes: 12,
      quoteFragment: quoteFragment,
    );

    test('an untouched quote goes out as the budget cut it', () {
      expect(prefix, '@[Vasya] >Where do we...\n');
      final reply = composerReply('${prefix}ok');
      expect(reply?.prefix, prefix);
      expect(reply?.wirePrefix, prefix);
      expect(reply?.fragment, 'Where do we...');
      expect(send(reply!.fragment), '@[Vasya] >Where do we...\nok');
    });

    test('a fragment shortened from its end stays a reply', () {
      final reply = composerReply('@[Vasya] >Where do w\nok');
      expect(reply?.prefix, '@[Vasya] >Where do w\n');
      expect(reply?.wirePrefix, '@[Vasya] >Where do w...\n');
      expect(reply?.fragment, 'Where do w');
      expect(send(reply!.fragment), '@[Vasya] >Where do w...\nok');
    });

    test('a partly deleted ellipsis goes out whole', () {
      final reply = composerReply('@[Vasya] >Where do we.\nok');
      expect(reply?.fragment, 'Where do we.');
      expect(reply?.wirePrefix, '@[Vasya] >Where do we...\n');
      expect(send(reply!.fragment), '@[Vasya] >Where do we...\nok');
    });

    test('the receiver finds the message a trimmed quote was cut from', () {
      expect(_resolve('>Where do w...\nok', 'Vasya')?.quoted?.id, 'v1');
    });

    test('a rewritten quote or a touched mention drops the reply', () {
      expect(composerReply('@[Vasya] >Where we...\nok'), isNull);
      expect(composerReply('@[Vasya] >...\nok'), isNull);
      expect(composerReply('@[Vasya] >\nok'), isNull);
      expect(composerReply('@[Vasya] ok'), isNull);
      expect(composerReply('@[Vasy] >Where do we...\nok'), isNull);
    });

    test('a fragment that quotes something else leaves the budget cut', () {
      expect(send('Where we'), '@[Vasya] >Where do we...\nok');
    });

    test('no fragment is spent where none is due', () {
      expect(
        ExactQuoteHelper.formatReplyWith(
          senderName: 'Vasya',
          text: 'ok',
          quotedText: 'Fine',
          quotedMessageId: 'v2',
          history: _history,
          authorOf: _authorOf,
          idOf: _idOf,
          enabled: true,
          maxFragmentBytes: 30,
          quoteFragment: 'Fin',
        ),
        '@[Vasya] ok',
      );
    });
  });
}

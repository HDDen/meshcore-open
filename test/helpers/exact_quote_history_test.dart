import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/exact_quote_helper.dart';

// With the quote switched off, a reply is the mention and the text whatever
// the history holds: the history is not read at all. What a caller relies on
// when it stops merging history for a reply that spends no fragment.

typedef _Entry = ({String author, String text, String id});

String _authorOf(_Entry entry) => entry.author;
String _idOf(_Entry entry) => entry.id;

const _history = <_Entry>[
  (author: 'Vasya', text: 'Where do we meet tomorrow?', id: 'v1'),
  (author: 'Me', text: 'At the entrance at seven', id: 'm1'),
  (author: 'Vasya', text: 'Fine', id: 'v2'),
];

String _format(
  List<_Entry> history, {
  required bool enabled,
  bool fragmentForLatest = false,
  String quotedId = 'v1',
}) => ExactQuoteHelper.formatReplyWith(
  senderName: 'Vasya',
  text: 'ok',
  quotedText: _history.firstWhere((entry) => entry.id == quotedId).text,
  quotedMessageId: quotedId,
  history: history,
  authorOf: _authorOf,
  idOf: _idOf,
  enabled: enabled,
  fragmentForLatest: fragmentForLatest,
  maxFragmentBytes: 30,
);

void main() {
  test('with the quote off the history is not consulted', () {
    expect(_format(_history, enabled: false), '@[Vasya] ok');
    expect(_format(const [], enabled: false), '@[Vasya] ok');
  });

  test('with the quote on the history is what decides the fragment', () {
    expect(
      _format(_history, enabled: true),
      '@[Vasya] >Where do we meet tomorrow?\nok',
    );
    expect(_format(_history, enabled: true, quotedId: 'v2'), '@[Vasya] ok');
  });

  test('with the fragment spent on the latest message too, the history is '
      'not consulted either', () {
    expect(
      _format(const [], enabled: true, fragmentForLatest: true),
      '@[Vasya] >Where do we meet tomorrow?\nok',
    );
    expect(
      _format(
        const [],
        enabled: true,
        fragmentForLatest: true,
        quotedId: 'v2',
      ),
      '@[Vasya] >Fine\nok',
    );
  });
}

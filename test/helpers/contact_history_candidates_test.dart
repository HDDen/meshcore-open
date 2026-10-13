import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/contact_history_candidates.dart';
import 'package:meshcore_open/models/contact.dart';

// Which histories a chat offers to attach: those of chat contacts named like
// this one under another key, with a history, newest first; keys already
// linked, other kinds of node and namesakes without a history are left out.

Contact _contact(
  int seed,
  String name, {
  int type = advTypeChat,
  bool hasMessages = true,
  int day = 1,
}) => Contact(
  publicKey: Uint8List.fromList(List<int>.generate(32, (i) => (seed + i) & 0xFF)),
  name: name,
  type: type,
  pathLength: 0,
  path: Uint8List(0),
  lastSeen: DateTime(2026, 10, day),
  hasMessages: hasMessages,
);

void main() {
  final me = _contact(1, 'Alex');

  test('a namesake under another key with a history is offered, newest first', () {
    final older = _contact(2, 'alex ', day: 3);
    final newer = _contact(3, 'Alex', day: 9);
    final found = ContactHistoryCandidates.sameNameWithHistory(me, [
      me,
      older,
      newer,
    ]);
    expect(found.map((c) => c.publicKeyHex), [
      newer.publicKeyHex,
      older.publicKeyHex,
    ]);
    expect(found.first.name, 'Alex');
    expect(found.first.nodeScope, isNull);
  });

  test('without a history, under another kind, or already linked: no', () {
    final noHistory = _contact(2, 'Alex', hasMessages: false);
    final repeater = _contact(3, 'Alex', type: advTypeRepeater);
    final linked = _contact(4, 'Alex');
    final other = _contact(5, 'Bob');
    final found = ContactHistoryCandidates.sameNameWithHistory(
      me,
      [me, noHistory, repeater, linked, other],
      excludedKeys: {linked.publicKeyHex},
    );
    expect(found, isEmpty);
  });

  test('a repeater or a nameless contact is never offered anything', () {
    expect(
      ContactHistoryCandidates.sameNameWithHistory(
        _contact(1, 'Alex', type: advTypeRepeater),
        [_contact(2, 'Alex')],
      ),
      isEmpty,
    );
    expect(
      ContactHistoryCandidates.sameNameWithHistory(_contact(1, '  '), [
        _contact(2, '  '),
      ]),
      isEmpty,
    );
  });

  test('a candidate from another node carries that node', () {
    final found = ContactHistoryCandidates.sameNameWithHistory(
      me,
      [_contact(2, 'Alex')],
      nodeScope: 'afdad95d3a',
    );
    expect(found.single.nodeScope, 'afdad95d3a');
    expect(found.single.toString(), contains('on afdad95d3a'));
  });
}

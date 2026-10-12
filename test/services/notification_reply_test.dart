import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/notification_reply.dart';

void main() {
  group('NotificationReply.parse', () {
    test('parses a contact reply', () {
      final reply = NotificationReply.parse(
        actionId: notificationReplyActionId,
        payload: 'message:ab12cd',
        input: '  on my way  ',
      )!;
      expect(reply.action, NotificationReplyAction.reply);
      expect(reply.isChannel, isFalse);
      expect(reply.contactKeyHex, 'ab12cd');
      expect(reply.text, 'on my way');
    });

    test('parses a channel reply', () {
      final reply = NotificationReply.parse(
        actionId: notificationReplyActionId,
        payload: 'channel:3',
        input: 'ok',
      )!;
      expect(reply.isChannel, isTrue);
      expect(reply.channelIndex, 3);
    });

    test('parses mark as read without input', () {
      final reply = NotificationReply.parse(
        actionId: notificationMarkReadActionId,
        payload: 'channel:0',
      )!;
      expect(reply.action, NotificationReplyAction.markRead);
      expect(reply.channelIndex, 0);
    });

    test('parses mute for channels only', () {
      final reply = NotificationReply.parse(
        actionId: notificationMuteActionId,
        payload: 'channel:2',
      )!;
      expect(reply.action, NotificationReplyAction.mute);
      expect(reply.channelIndex, 2);
      expect(
        NotificationReply.parse(
          actionId: notificationMuteActionId,
          payload: 'message:ab12',
        ),
        isNull,
      );
    });

    test('ignores taps, unknown actions, empty replies and bad payloads', () {
      expect(
        NotificationReply.parse(actionId: null, payload: 'message:ab'),
        isNull,
      );
      expect(
        NotificationReply.parse(actionId: 'archive', payload: 'message:ab'),
        isNull,
      );
      expect(
        NotificationReply.parse(
          actionId: notificationReplyActionId,
          payload: 'message:ab',
          input: '   ',
        ),
        isNull,
      );
      for (final payload in [null, 'message:', 'message:null', 'channel:x']) {
        expect(
          NotificationReply.parse(
            actionId: notificationReplyActionId,
            payload: payload,
            input: 'hi',
          ),
          isNull,
          reason: '$payload',
        );
      }
    });
  });

  group('splitMessageToFit', () {
    bool fitsBytes(String s, int max) => utf8.encode(s).length <= max;

    test('returns short text unchanged', () {
      expect(splitMessageToFit('hello there', (s) => fitsBytes(s, 20)), [
        'hello there',
      ]);
    });

    test('splits at word boundaries within the byte budget', () {
      final parts = splitMessageToFit(
        'one two three four five six',
        (s) => fitsBytes(s, 10),
      )!;
      expect(parts, ['one two', 'three four', 'five six']);
      expect(parts.every((p) => fitsBytes(p, 10)), isTrue);
    });

    test('counts multi-byte characters by UTF-8 size', () {
      final parts = splitMessageToFit(
        'привет привет привет',
        (s) => fitsBytes(s, 13),
      )!;
      expect(parts, ['привет', 'привет', 'привет']);
    });

    test('hard-splits a word that is too long on its own', () {
      final parts = splitMessageToFit('abcdefghij', (s) => fitsBytes(s, 4))!;
      expect(parts, ['abcd', 'efgh', 'ij']);
    });

    test('returns null when a single character does not fit', () {
      expect(splitMessageToFit('aé', (s) => fitsBytes(s, 1)), isNull);
    });

    test('returns null when more than maxParts are needed', () {
      expect(
        splitMessageToFit('a b c d e f g h', (s) => fitsBytes(s, 1)),
        isNull,
      );
    });
  });
}

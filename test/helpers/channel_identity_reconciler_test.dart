import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_identity_reconciler.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/storage/channel_identity_store.dart';

// The rules that tell a renamed or rekeyed channel from a new one, for an
// edit the app makes itself and for a channel list another app changed: a
// link only when exactly one of key and name changed, slots playing no part.

Uint8List _psk(int fill) =>
    Uint8List.fromList(List<int>.generate(16, (i) => (fill + i) & 0xFF));

String _id(int fill) => Channel.storageIdForPsk(_psk(fill))!;

Channel _channel(int index, String name, int fill) =>
    Channel(index: index, name: name, psk: _psk(fill));

Channel _empty(int index) => Channel(index: index, name: '', psk: Uint8List(16));

void main() {
  group('an edit of one channel', () {
    test('a rename under the same key links the two names', () {
      final link = ChannelIdentityReconciler.linkFor(
        _channel(2, 'Горы', 1),
        _channel(2, 'Горы-2026', 1),
      );
      expect(
        link,
        ChannelIdentityLink(
          ChannelIdentity(_id(1), 'Горы'),
          ChannelIdentity(_id(1), 'Горы-2026'),
        ),
      );
    });

    test('a new key under the same name links the two keys', () {
      final link = ChannelIdentityReconciler.linkFor(
        _channel(2, 'Горы', 1),
        _channel(2, 'Горы', 2),
      );
      expect(
        link,
        ChannelIdentityLink(
          ChannelIdentity(_id(1), 'Горы'),
          ChannelIdentity(_id(2), 'Горы'),
        ),
      );
    });

    test('both changed, nothing changed, or an empty slot: no link', () {
      expect(
        ChannelIdentityReconciler.linkFor(
          _channel(2, 'Горы', 1),
          _channel(2, 'Поля', 2),
        ),
        isNull,
      );
      expect(
        ChannelIdentityReconciler.linkFor(
          _channel(2, 'Горы', 1),
          _channel(2, 'Горы', 1),
        ),
        isNull,
      );
      expect(
        ChannelIdentityReconciler.linkFor(null, _channel(2, 'Горы', 1)),
        isNull,
      );
      expect(
        ChannelIdentityReconciler.linkFor(_empty(2), _channel(2, 'Горы', 1)),
        isNull,
      );
      expect(
        ChannelIdentityReconciler.linkFor(_channel(2, 'Горы', 1), _empty(2)),
        isNull,
      );
    });
  });

  group('a channel list another app changed', () {
    test('a rename in place and a rename with a move link the same', () {
      final inPlace = ChannelIdentityReconciler.diff(
        [_channel(2, 'Горы', 1), _channel(3, 'Поля', 7)],
        [_channel(2, 'Горы-2026', 1), _channel(3, 'Поля', 7)],
      );
      final moved = ChannelIdentityReconciler.diff(
        [_channel(2, 'Горы', 1), _channel(3, 'Поля', 7)],
        [_channel(2, 'Поля', 7), _channel(5, 'Горы-2026', 1)],
      );
      final expected = [
        ChannelIdentityLink(
          ChannelIdentity(_id(1), 'Горы'),
          ChannelIdentity(_id(1), 'Горы-2026'),
        ),
      ];
      expect(inPlace, expected);
      expect(moved, expected);
    });

    test('a new key under the same name links once the old key is gone', () {
      expect(
        ChannelIdentityReconciler.diff(
          [_channel(2, 'Горы', 1)],
          [_channel(4, 'Горы', 2)],
        ),
        [
          ChannelIdentityLink(
            ChannelIdentity(_id(1), 'Горы'),
            ChannelIdentity(_id(2), 'Горы'),
          ),
        ],
      );
    });

    test('a second channel added under a name links nothing', () {
      expect(
        ChannelIdentityReconciler.diff(
          [_channel(2, 'Горы', 1)],
          [_channel(2, 'Горы', 1), _channel(3, 'Горы', 2)],
        ),
        isEmpty,
      );
    });

    test('the key kept under another old name links nothing', () {
      // Slot 2 lost its name but the key still sits in slot 3 under the
      // name it had there before: nothing of that channel moved.
      expect(
        ChannelIdentityReconciler.diff(
          [_channel(2, 'Горы', 1), _channel(3, 'Горы-дубль', 1)],
          [_channel(3, 'Горы-дубль', 1), _channel(2, 'Горы', 9)],
        ),
        isEmpty,
      );
    });

    test('a move, a removal and an unrelated addition link nothing', () {
      expect(
        ChannelIdentityReconciler.diff(
          [_channel(2, 'Горы', 1), _channel(3, 'Поля', 7)],
          [_channel(5, 'Горы', 1), _channel(3, 'Поля', 7)],
        ),
        isEmpty,
      );
      expect(
        ChannelIdentityReconciler.diff(
          [_channel(2, 'Горы', 1), _channel(3, 'Поля', 7)],
          [_channel(3, 'Поля', 7), _channel(2, 'Реки', 4)],
        ),
        isEmpty,
      );
      expect(ChannelIdentityReconciler.diff([], [_channel(2, 'Горы', 1)]), isEmpty);
      expect(ChannelIdentityReconciler.diff([_channel(2, 'Горы', 1)], []), isEmpty);
    });

    test('empty slots count for nothing', () {
      expect(
        ChannelIdentityReconciler.diff(
          [_channel(2, 'Горы', 1), _empty(3)],
          [_empty(2), _channel(3, 'Горы-2026', 1)],
        ),
        [
          ChannelIdentityLink(
            ChannelIdentity(_id(1), 'Горы'),
            ChannelIdentity(_id(1), 'Горы-2026'),
          ),
        ],
      );
    });
  });
}

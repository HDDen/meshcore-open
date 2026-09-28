import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/reply_target_index.dart';
import 'package:meshcore_open/models/channel_message.dart';

void main() {
  ChannelMessage message(String id, int minute, {String text = 'text'}) {
    final at = DateTime(2026, 9, 20, 12, minute);
    return ChannelMessage(
      messageId: id,
      senderName: 'a',
      text: text,
      timestamp: at,
      receivedAt: at,
      isOutgoing: false,
      channelIndex: 3,
    );
  }

  test('finds a message by id and misses cleanly', () {
    final index = ReplyTargetIndex();
    final source = [message('m1', 1), message('m2', 2)];

    expect(identical(index.find(source, 'm2'), source[1]), isTrue);
    expect(identical(index.find(source, 'm1'), source[0]), isTrue);
    expect(index.find(source, 'missing'), isNull);
    expect(index.find(const <ChannelMessage>[], 'm1'), isNull);
  });

  test('the first message carrying an id wins, as the scan it replaced did',
      () {
    final index = ReplyTargetIndex();
    final own = message('same', 1, text: 'own copy');
    final shared = message('same', 2, text: 'shared copy');

    expect(index.find([own, shared], 'same')?.text, 'own copy');
    expect(index.find([shared, own], 'same')?.text, 'shared copy');
  });

  test('the index follows the list object, not its contents', () {
    final index = ReplyTargetIndex();
    final source = [message('m1', 1)];
    expect(index.find(source, 'm1'), isNotNull);

    // Mutated in place: the transcript never does this, its cache hands out a
    // new object per rebuild, so the index is allowed to trust identity.
    source.add(message('m2', 2));
    expect(index.find(source, 'm2'), isNull);

    final rebuilt = List<ChannelMessage>.of(source);
    expect(identical(index.find(rebuilt, 'm2'), source[1]), isTrue);
    expect(index.find(rebuilt, 'm1'), isNotNull);
  });
}

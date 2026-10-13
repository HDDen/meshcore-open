import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_sender_name.dart';

void main() {
  group('resolveChannelSenderNameLock', () {
    test('nothing holds a public region on recent firmware back', () {
      expect(
        resolveChannelSenderNameLock(
          signsMcmp: false,
          firmwareSendsRawPackets: true,
          scope: 'ru-kda',
        ),
        ChannelSenderNameLock.none,
      );
      expect(
        resolveChannelSenderNameLock(
          signsMcmp: false,
          firmwareSendsRawPackets: true,
          scope: '',
        ),
        ChannelSenderNameLock.none,
      );
    });

    test('signing wins over everything else', () {
      expect(
        resolveChannelSenderNameLock(
          signsMcmp: true,
          firmwareSendsRawPackets: false,
          scope: r'$private',
        ),
        ChannelSenderNameLock.signedMcmp,
      );
    });

    test('old firmware, then a private region', () {
      expect(
        resolveChannelSenderNameLock(
          signsMcmp: false,
          firmwareSendsRawPackets: false,
          scope: r'$private',
        ),
        ChannelSenderNameLock.firmware,
      );
      expect(
        resolveChannelSenderNameLock(
          signsMcmp: false,
          firmwareSendsRawPackets: true,
          scope: r' $private',
        ),
        ChannelSenderNameLock.privateRegion,
      );
    });
  });

  group('channelSenderNameFromSetting', () {
    test('a missing, empty or blank value is no name', () {
      expect(channelSenderNameFromSetting(null), isNull);
      expect(channelSenderNameFromSetting(''), isNull);
      expect(channelSenderNameFromSetting('   '), isNull);
    });

    test('a name comes back trimmed', () {
      expect(channelSenderNameFromSetting(' Base '), 'Base');
    });
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/channel_resend_coverage.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _channel = Channel(index: 0, name: 'synthetic', psk: Uint8List(16));

class _Connector extends MeshCoreConnector {
  @override
  bool get isConnected => true;
}

class _Harness {
  _Harness(this.connector, this.settings, this.tester, this.delay, this.minHops);
  final _Connector connector;
  final AppSettingsService settings;
  final WidgetTester tester;
  final int delay;
  final int minHops;
  int resends = 0;
  bool finished = false;
  Future<void>? running;
  Future<void> Function()? onResend;

  ChannelMessage get message => connector.getChannelMessages(_channel).single;

  void start() {
    running = connector.runChannelHopCheckForTest(
      message.messageId, minHops: minHops, maxResends: 3,
      resend: () async {
        resends++;
        final callback = onResend;
        if (callback != null) {
          await callback();
        }
      },
    ).then((_) { finished = true; });
  }

  Future<void> exhaust() async {
    start();
    for (var attempt = 0; attempt < 4; attempt++) {
      await tester.pump(Duration(seconds: delay));
    }
    expect(finished, isTrue);
    await running!;
    expect(resends, 3);
    expect(message.resendCount, 3);
    expect(connector.channelResendProgress(message.messageId), isNull);
  }

  ChannelMessage echo(List<int> path) => connector.mergeChannelEchoForTest(
    _channel.index,
    ChannelMessage(
      messageId: message.messageId, senderName: message.senderName,
      text: message.text, timestamp: message.timestamp,
      receivedAt: tester.binding.clock.now(), isOutgoing: false,
      status: ChannelMessageStatus.sent, pathBytes: Uint8List.fromList(path),
      pathLength: path.length ~/ 2, pathHashWidth: 2,
    ),
  );
}

Future<void> _withHarness(
  WidgetTester tester,
  Future<void> Function(_Harness) body, {
  int warningSeconds = 7,
  int delay = 20,
  int minHops = 2,
  bool countRepeaters = true,
  bool heardEcho = true,
}) async {
  final settings = AppSettingsService();
  final connector = _Connector();
  final h = _Harness(connector, settings, tester, delay, minHops);
  try {
    await settings.updateSettings(AppSettings(
      noRetransmissionWarningSeconds: warningSeconds,
      channelMinHopsEnabled: true,
      channelMinHops: minHops,
      channelMinHopsRetries: 3,
      channelMinHopsDelaySeconds: delay,
      channelMinHopsCountRepeaters: countRepeaters,
      channelMinHopsRepeaterCount: 3,
    ));
    connector.attachAppSettingsServiceForTest(settings);
    connector.setChannelResendClockForTest(tester.binding.clock.now);
    final now = tester.binding.clock.now();
    connector.setChannelMessagesForTest(_channel.index, [ChannelMessage(
      messageId: 'synthetic-coverage', senderName: 'synthetic', text: 'test',
      timestamp: now, receivedAt: now, sentByRadioAt: now,
      isOutgoing: true, status: ChannelMessageStatus.sent,
      repeatCount: heardEcho ? 1 : 0,
      pathLength: heardEcho ? 1 : 0, pathHashWidth: 2,
      pathBytes: heardEcho ? Uint8List.fromList([0x81, 0x30]) : null,
    )]);
    await body(h);
  } finally {
    // Future.any может оставить исходный delayed deadline после раннего эхо.
    // Пустая история завершает loop, остаток окна исполняем до invariants.
    connector.setChannelMessagesForTest(_channel.index, []);
    await tester.pump(Duration(seconds: delay + 8));
    final pending = h.running;
    if (pending != null) {
      await pending;
    }
    connector.dispose();
    settings.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  testWidgets('one heard hop after four sends warns without changing sent status or packet time', (tester) async {
    await _withHarness(tester, (h) async {
      final original = h.message;
      await h.exhaust();
      expect(h.message.repeatCount, 1);
      expect(h.message.pathLength, 1);
      expect(h.message.resendCount + 1, 4);
      expect(h.message.noRetransmissionWarningSeconds, 7);
      expect(h.message.status, ChannelMessageStatus.sent);
      expect(h.message.timestamp, original.timestamp);
      expect(h.message.sentByRadioAt, original.sentByRadioAt);
      expect(h.message.receivedAt, original.receivedAt);
      expect(h.connector.channelHopShortfall(h.message.messageId), (hops: 1, required: 2));
    });
  });

  testWidgets('repeating one nearby hop never clears shortfall or restarts resends', (tester) async {
    await _withHarness(tester, (h) async {
      await h.exhaust();
      for (var i = 0; i < 5; i++) {
        h.echo([0x81, 0x30]);
        expect(h.message.noRetransmissionWarningSeconds, 7);
        expect(distinctFirstHopRepeaters(h.message), {'8130'});
        expect(h.connector.channelHopShortfall(h.message.messageId), (hops: 1, required: 2));
      }
      await tester.pump(const Duration(minutes: 1));
      expect(h.resends, 3);
      expect(h.message.resendCount, 3);
    });
  });

  testWidgets('the same repeater heard on every resend still ends with a shortfall', (tester) async {
    await _withHarness(tester, (h) async {
      h.onResend = () async { h.echo([0x81, 0x30]); };
      await h.exhaust();
      expect(h.message.repeatCount, 4);
      expect(h.message.resendCount, 3);
      expect(distinctFirstHopRepeaters(h.message), {'8130'});
      expect(h.message.noRetransmissionWarningSeconds, 7);
      expect(h.connector.channelHopShortfall(h.message.messageId), (hops: 1, required: 2));
    });
  });

  testWidgets('only the third distinct nearby repeater clears the completed shortfall', (tester) async {
    await _withHarness(tester, (h) async {
      await h.exhaust();
      h.echo([0x81, 0x40]);
      expect(h.message.noRetransmissionWarningSeconds, 7);
      expect(h.connector.channelHopShortfall(h.message.messageId), isNotNull);
      final revision = h.connector.channelResendRevision;
      h.echo([0x81, 0x50]);
      expect(distinctFirstHopRepeaters(h.message), {'8130', '8140', '8150'});
      expect(h.message.pathLength, 1);
      expect(h.message.noRetransmissionWarningSeconds, isNull);
      expect(h.connector.channelHopShortfall(h.message.messageId), isNull);
      expect(h.connector.channelResendRevision, greaterThan(revision));
      expect(h.message.status, ChannelMessageStatus.sent);
      expect(h.message.resendCount, 3);
    });
  });

  testWidgets('a late two-hop route satisfies the independent distance alternative', (tester) async {
    await _withHarness(tester, (h) async {
      await h.exhaust();
      h.echo([0x81, 0x30, 0x99, 0x99]);
      expect(distinctFirstHopRepeaters(h.message), {'8130'});
      expect(h.message.pathLength, 2);
      expect(h.message.noRetransmissionWarningSeconds, isNull);
      expect(h.connector.channelHopShortfall(h.message.messageId), isNull);
    });
  });

  testWidgets('late progress below a larger distance target updates the visible shortfall', (tester) async {
    await _withHarness(tester, (h) async {
      await h.exhaust();
      final revision = h.connector.channelResendRevision;
      h.echo([0x81, 0x30, 0x99, 0x99]);
      expect(h.message.noRetransmissionWarningSeconds, 7);
      expect(h.connector.channelHopShortfall(h.message.messageId), (hops: 2, required: 3));
      expect(h.connector.channelResendRevision, greaterThan(revision));
    }, minHops: 3);
  });

  testWidgets('insufficient late echo does not cancel the pending ordinary warning timer', (tester) async {
    await _withHarness(tester, (h) async {
      await h.exhaust();
      expect(h.message.noRetransmissionWarningSeconds, isNull);
      expect(h.connector.channelHopShortfall(h.message.messageId), isNotNull);
      h.echo([0x81, 0x30]);
      await tester.pump(const Duration(milliseconds: 1999));
      expect(h.message.noRetransmissionWarningSeconds, isNull);
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.message.noRetransmissionWarningSeconds, 7);
    }, delay: 5);
  });

  testWidgets('sufficient late echo cancels the pending warning timer', (tester) async {
    await _withHarness(tester, (h) async {
      await h.exhaust();
      h.echo([0x81, 0x30, 0x99, 0x99]);
      await tester.pump(const Duration(seconds: 10));
      expect(h.message.noRetransmissionWarningSeconds, isNull);
      expect(h.connector.channelHopShortfall(h.message.messageId), isNull);
    }, delay: 5);
  });

  testWidgets('the disabled mod warning leaves coverage status without a warning line', (tester) async {
    await _withHarness(tester, (h) async {
      await h.exhaust();
      expect(h.message.noRetransmissionWarningSeconds, isNull);
      expect(h.connector.channelHopShortfall(h.message.messageId), isNotNull);
      h.echo([0x81, 0x30]);
      expect(h.message.noRetransmissionWarningSeconds, isNull);
      expect(h.connector.channelHopShortfall(h.message.messageId), isNotNull);
    }, warningSeconds: 0);
  });

  testWidgets('a sufficient early echo ends the series without resending or warning', (tester) async {
    await _withHarness(tester, (h) async {
      h.start();
      await tester.pump(const Duration(seconds: 1));
      h.echo([0x81, 0x30, 0x99, 0x99]);
      await tester.pump(Duration.zero);
      expect(h.finished, isTrue);
      expect(h.resends, 0);
      expect(h.message.resendCount, 0);
      expect(h.message.noRetransmissionWarningSeconds, isNull);
      expect(h.connector.channelHopShortfall(h.message.messageId), isNull);
    });
  });

  testWidgets('without a recorded shortfall any echo still clears the ordinary warning', (tester) async {
    await _withHarness(tester, (h) async {
      h.connector.scheduleChannelNoRetransmissionWarningForTest(h.message.messageId,
          since: tester.binding.clock.now().subtract(const Duration(minutes: 1)));
      expect(h.message.noRetransmissionWarningSeconds, 7);
      h.echo([0x81, 0x30]);
      expect(h.message.noRetransmissionWarningSeconds, isNull);
      expect(h.connector.channelHopShortfall(h.message.messageId), isNull);
    }, heardEcho: false);
  });

  testWidgets('nearby repeats alone do not clear shortfall when the alternative is off', (tester) async {
    await _withHarness(tester, (h) async {
      await h.exhaust();
      h.echo([0x81, 0x40]);
      h.echo([0x81, 0x50]);
      expect(h.message.noRetransmissionWarningSeconds, 7);
      expect(h.connector.channelHopShortfall(h.message.messageId), isNotNull);
      h.echo([0x81, 0x30, 0x99, 0x99]);
      expect(h.message.noRetransmissionWarningSeconds, isNull);
      expect(h.connector.channelHopShortfall(h.message.messageId), isNull);
    }, countRepeaters: false);
  });
}

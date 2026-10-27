import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ios_execution_diagnostics.dart';

import 'ios_execution_diagnostics_fixture.dart';

void main() {
  final messenger = TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  const channel = MethodChannel('mco_test/ios_execution_diagnostics');

  tearDown(() { messenger.setMockMethodCallHandler(channel, null); });

  test('diagnostics keep actual and preferred hardware values distinct', () {
    final message = formatIosExecutionDiagnostics(iosExecutionDiagnosticsFixture());
    expect(message, contains('sampleRate=48000.000000'));
    expect(message, contains('preferredSampleRate=44100.000000'));
    expect(message, contains('ioBufferDuration=0.020000'));
    expect(message, contains('preferredIOBufferDuration=0.005000'));
    expect(message, contains('playerSampleRate=8000.000000'));
    expect(message, contains('outputPortTypes=Speaker'));
  });

  test('unknown fields and untrusted tokens cannot leak into diagnostic text', () {
    final raw = iosExecutionDiagnosticsFixture();
    raw['authUrl'] = 'synthetic-private-marker';
    final audio = raw['audio'] as Map<String, Object>;
    audio['deviceName'] = 'synthetic-private-marker';
    audio['event'] = 'synthetic-private-marker';
    audio['category'] = 'synthetic-private-marker';
    audio['outputPortTypes'] = ['Speaker', 'synthetic-private-marker'];
    final message = formatIosExecutionDiagnostics(raw);
    expect(message, isNotNull);
    expect(message, isNot(contains('synthetic-private-marker')));
    expect(message, contains('event=other'));
    expect(message, contains('outputPortTypes=Speaker|other'));
  });

  test('invalid snapshots are refused without stringifying native data', () {
    expect(formatIosExecutionDiagnostics(null), isNull);
    expect(formatIosExecutionDiagnostics({'schema': 9}), isNull);
    for (final invalid in [double.nan, double.infinity, -1.0, 'bad']) {
      final raw = iosExecutionDiagnosticsFixture();
      (raw['audio'] as Map<String, Object>)['sampleRate'] = invalid;
      expect(formatIosExecutionDiagnostics(raw), isNull);
    }
    final raw = iosExecutionDiagnosticsFixture();
    (raw['audio'] as Map<String, Object>)['playStarts'] = -1;
    expect(formatIosExecutionDiagnostics(raw), isNull);
  });

  test('explicit request reads once without configuring or starting the backend', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {...iosExecutionDiagnosticsFixture(), 'source': 'requested'};
    });
    final message = await readIosExecutionDiagnostics(isIos: true, channel: channel);
    expect(message, contains('source=requested'));
    expect(calls.map((call) => call.method), ['diagnostics']);
    expect(calls.single.arguments, isNull);
  });

  test('other platforms do not call the channel', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async { calls++; return null; });
    expect(await readIosExecutionDiagnostics(isIos: false, channel: channel), isNull);
    expect(calls, 0);
  });

  test('an older runner or native failure does not block log export or expose details', () async {
    messenger.setMockMethodCallHandler(channel, (_) async { throw MissingPluginException(); });
    expect(await readIosExecutionDiagnostics(isIos: true, channel: channel),
        contains('older runner'));
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'synthetic-private-marker', details: 'synthetic-private-marker');
    });
    final message = await readIosExecutionDiagnostics(isIos: true, channel: channel);
    expect(message, contains('native error'));
    expect(message, isNot(contains('synthetic-private-marker')));
    messenger.setMockMethodCallHandler(channel, (_) async => {'schema': 3});
    expect(await readIosExecutionDiagnostics(isIos: true, channel: channel),
        contains('invalid snapshot'));
  });

  testWidgets('a stuck snapshot times out and a late response adds no operation', (tester) async {
    final reply = Completer<Object?>();
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) {
      calls++;
      return reply.future;
    });
    final pending = readIosExecutionDiagnostics(isIos: true, channel: channel);
    await tester.pump(const Duration(seconds: 3));
    expect(await pending, contains('timeout'));
    reply.complete(iosExecutionDiagnosticsFixture());
    await tester.pump();
    expect(calls, 1);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

import 'package:flutter/foundation.dart' show ByteData, Endian, Uint8List;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/widgets.dart' show Builder, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/services/ble_debug_log_service.dart';

// Фиксируем исходное содержимое журнала до отложенного построения описаний.
// Только синтетические кадры; транспорт, preferences, ключи и файлы не читаются.
BleDebugLogService _log() {
  final log = BleDebugLogService();
  addTearDown(log.dispose);
  return log;
}

Uint8List _rawFrame(int sequence) => Uint8List.fromList([
  pushCodeLogRxData, 40, 176, sequence & 0xff, (sequence >> 8) & 0xff,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('baseline: direction labels notes and unknown codes remain readable', () {
    final log = _log();
    log.logFrame(Uint8List.fromList([cmdAppStart]), outgoing: true, note: 'sample');
    log.logFrame(Uint8List.fromList([respCodeErr]), outgoing: false);
    log.logFrame(Uint8List.fromList([pushCodeMsgWaiting]), outgoing: false);
    log.logFrame(Uint8List.fromList([254]), outgoing: false, note: 'unknown');
    log.logFrame(Uint8List.fromList([254]), outgoing: true);
    expect(log.entries.map((e) => e.description), [
      'TX CMD_APP_START • sample',
      'RX RESP_CODE_ERR',
      'RX PUSH_CODE_MSG_WAITING',
      'RX CODE_254 • unknown',
      'TX CODE_254',
    ]);
    expect(log.entries.map((e) => e.outgoing), [true, false, false, false, true]);
  });

  test('baseline: signing responses and commands with the same code stay distinct', () {
    final log = _log();
    expect(cmdReboot, respCodeSignStart);
    expect(cmdGetBattAndStorage, respCodeSignature);
    log.logFrame(Uint8List.fromList([cmdReboot]), outgoing: true);
    log.logFrame(Uint8List.fromList([respCodeSignStart, 0, 0, 16, 0, 0]),
        outgoing: false);
    log.logFrame(Uint8List.fromList([cmdGetBattAndStorage]), outgoing: true);
    log.logFrame(Uint8List.fromList([respCodeSignature, 1, 2, 3, 4]),
        outgoing: false);
    log.logFrame(Uint8List.fromList([cmdSignStart]), outgoing: true);
    log.logFrame(Uint8List.fromList([cmdSignData, 1, 2, 3]), outgoing: true);
    log.logFrame(Uint8List.fromList([cmdSignFinish]), outgoing: true);
    expect(log.entries.map((e) => e.description), [
      'TX CMD_REBOOT',
      'RX RESP_CODE_SIGN_START • maxLen=4096B',
      'TX CMD_GET_BATT_AND_STORAGE',
      'RX RESP_CODE_SIGNATURE • sig=4B',
      'TX CMD_SIGN_START',
      'TX CMD_SIGN_DATA • chunk=3B',
      'TX CMD_SIGN_FINISH',
    ]);
  });

  test('baseline: diagnostic details keep little endian offsets and short frame guards', () {
    final log = _log();
    final sent = ByteData(10)..setUint8(0, respCodeSent);
    sent.setUint32(6, 3210, Endian.little);
    final confirmed = ByteData(9)..setUint8(0, pushCodeSendConfirmed);
    confirmed.setUint32(5, 987, Endian.little);
    log.logFrame(sent.buffer.asUint8List(), outgoing: false);
    log.logFrame(confirmed.buffer.asUint8List(), outgoing: false);
    log.logFrame(Uint8List.fromList([respCodeBattAndStorage, 0x68, 0x10]),
        outgoing: false);
    log.logFrame(Uint8List.fromList([pushCodeLoginSuccess]), outgoing: false);
    log.logFrame(Uint8List.fromList([pushCodeLoginFail]), outgoing: false);
    for (final code in [
      respCodeSent, pushCodeSendConfirmed, respCodeBattAndStorage, respCodeSignStart,
    ]) {
      log.logFrame(Uint8List.fromList([code]), outgoing: false);
    }
    expect(log.entries.map((e) => e.description), [
      'RX RESP_CODE_SENT • timeout=3210ms',
      'RX PUSH_CODE_SEND_CONFIRMED • trip=987ms',
      'RX RESP_CODE_BATT_AND_STORAGE • 4200mV',
      'RX PUSH_CODE_LOGIN_SUCCESS • login ok',
      'RX PUSH_CODE_LOGIN_FAIL • login fail',
      'RX RESP_CODE_SENT',
      'RX PUSH_CODE_SEND_CONFIRMED',
      'RX RESP_CODE_BATT_AND_STORAGE',
      'RX RESP_CODE_SIGN_START',
    ]);
  });

  test('baseline: stored bytes and descriptions survive mutation of input buffers', () {
    final log = _log();
    final battery = Uint8List.fromList([respCodeBattAndStorage, 0x68, 0x10]);
    final raw = _rawFrame(513);
    log.logFrame(battery, outgoing: false, note: 'snapshot');
    log.logFrame(raw, outgoing: false);
    battery.fillRange(0, battery.length, 0);
    raw.fillRange(0, raw.length, 0);
    expect(log.entries.first.description, 'RX RESP_CODE_BATT_AND_STORAGE • 4200mV • snapshot');
    expect(log.entries.first.payload, [respCodeBattAndStorage, 0x68, 0x10]);
    expect(log.entries.last.description, 'RX PUSH_CODE_LOG_RX_DATA');
    expect(log.entries.last.payload, [pushCodeLogRxData, 40, 176, 1, 2]);
    expect(log.rawLogRxEntries.single.payload, [1, 2]);
  });

  test('baseline: incoming synthetic private key is withheld without altering the frame', () {
    final log = _log();
    // Фиктивные одинаковые байты, не ключ и не материал из рабочей среды.
    final frame = Uint8List.fromList([respCodePrivateKey, ...List<int>.filled(64, 0xa5)]);
    log.logFrame(frame, outgoing: false, note: 'must be replaced');
    log.logFrame(Uint8List.fromList([respCodePrivateKey]), outgoing: false);
    for (final entry in log.entries) {
      expect(entry.description, 'RX RESP_CODE_PRIVATE_KEY • payload withheld');
      expect(entry.payload, [respCodePrivateKey]);
      expect(entry.hexPreview, '0e');
    }
    expect(log.rawLogRxEntries, isEmpty);
    expect(frame.length, 65);
    expect(frame.first, respCodePrivateKey);
    expect(frame.skip(1), everyElement(0xa5));
  });

  test('baseline: raw log stores only incoming packet bytes after the three byte prefix', () {
    final log = _log();
    log.logFrame(_rawFrame(513), outgoing: false);
    log.logFrame(_rawFrame(1027), outgoing: true);
    for (final frame in [
      <int>[pushCodeLogRxData],
      <int>[pushCodeLogRxData, 40],
      <int>[pushCodeLogRxData, 40, 176],
    ]) {
      log.logFrame(Uint8List.fromList(frame), outgoing: false);
    }
    expect(log.entries, hasLength(5));
    expect(log.rawLogRxEntries, hasLength(1));
    expect(log.rawLogRxEntries.single.payload, [1, 2]);
    expect(log.entries.first.payload, [pushCodeLogRxData, 40, 176, 1, 2]);
  });

  test('baseline: previews stop at 64 bytes while payloads remain complete', () {
    final bytes = Uint8List.fromList(List<int>.generate(65, (i) => i));
    final entry = BleDebugLogEntry(
      timestamp: DateTime.utc(2000), outgoing: false, description: 'synthetic',
      payload: bytes,
    );
    final raw = BleRawLogRxEntry(timestamp: DateTime.utc(2000), payload: bytes);
    for (final preview in [entry.hexPreview, raw.hexPreview]) {
      expect(preview, startsWith('00 01 02 03 '));
      expect(preview, endsWith('3e 3f …'));
      expect(preview.split(' '), hasLength(65));
    }
    expect(entry.payload, hasLength(65));
    expect(raw.payload.last, 0x40);
    final exact = BleRawLogRxEntry(
      timestamp: DateTime.utc(2000), payload: Uint8List.fromList(bytes.take(64).toList()),
    );
    expect(exact.hexPreview, endsWith('3e 3f'));
    expect(exact.hexPreview, isNot(contains('…')));
    expect(exact.hexPreview.split(' '), hasLength(64));
  });

  test('baseline: frame and raw buffers retain independent latest 500 entries', () {
    final log = _log();
    expect(BleDebugLogService.maxEntries, 500);
    for (var i = 0; i < 503; i++) {
      log.logFrame(_rawFrame(i), outgoing: false);
    }
    expect(log.entries, hasLength(500));
    expect(log.rawLogRxEntries, hasLength(500));
    expect(log.entries.first.payload.sublist(3), [3, 0]);
    expect(log.rawLogRxEntries.first.payload, [3, 0]);
    expect(log.rawLogRxEntries.last.payload, [246, 1]);
    for (var i = 0; i < 4; i++) {
      log.logFrame(Uint8List.fromList([cmdAppStart]), outgoing: true);
    }
    expect(log.entries, hasLength(500));
    expect(log.entries.first.payload.sublist(3), [7, 0]);
    expect(log.entries.last.description, 'TX CMD_APP_START');
    expect(log.rawLogRxEntries, hasLength(500));
    expect(log.rawLogRxEntries.first.payload, [3, 0]);
    expect(log.rawLogRxEntries.last.payload, [246, 1]);
  });

  test('baseline: exposed lists are immutable snapshots and clear notifies while idle', () {
    final log = _log();
    final notifications = <(int, int)>[];
    log.addListener(() => notifications.add((log.entries.length, log.rawLogRxEntries.length)));
    log.logFrame(Uint8List(0), outgoing: false);
    expect(notifications, isEmpty);
    log.logFrame(_rawFrame(1), outgoing: false);
    final frames = log.entries;
    final raw = log.rawLogRxEntries;
    expect(() => frames.add(frames.single), throwsUnsupportedError);
    expect(() => raw.clear(), throwsUnsupportedError);
    log.logFrame(Uint8List.fromList([cmdAppStart]), outgoing: true);
    expect(frames, hasLength(1));
    expect(raw, hasLength(1));
    log.clear();
    log.clear();
    expect(log.entries, isEmpty);
    expect(log.rawLogRxEntries, isEmpty);
    expect(notifications, [(1, 1), (2, 1), (0, 0), (0, 0)]);
  });

  testWidgets('baseline: logging during build defers and coalesces notifications until post frame',
      (tester) async {
    final log = _log();
    final phases = <SchedulerPhase>[];
    log.addListener(() => phases.add(SchedulerBinding.instance.schedulerPhase));
    await tester.pumpWidget(Builder(builder: (_) {
      expect(SchedulerBinding.instance.schedulerPhase, SchedulerPhase.persistentCallbacks);
      log.logFrame(Uint8List.fromList([cmdAppStart]), outgoing: true);
      log.logFrame(_rawFrame(1), outgoing: false);
      expect(log.entries, hasLength(2));
      expect(phases, isEmpty);
      return const SizedBox.shrink();
    }));
    expect(phases, [SchedulerPhase.postFrameCallbacks]);
    log.logFrame(Uint8List.fromList([respCodeOk]), outgoing: false);
    expect(phases, [SchedulerPhase.postFrameCallbacks, SchedulerPhase.idle]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

// Фиксируем существующее окно 50 мс до появления энергопараметра.
// Настоящий коннектор, без init, транспорта, диска и платформенных сервисов.
// Fake time проверяет расписание Dart, а не энергопотребление устройства.
Future<void> _withConnector(
  WidgetTester tester,
  Future<void> Function(MeshCoreConnector) check,
) async {
  final connector = MeshCoreConnector();
  try {
    await check(connector);
  } finally {
    connector.dispose();
    await tester.pump();
  }
}

Uint8List _batteryFrame(int millivolts, {int usedKb = 12}) {
  final data = ByteData(11);
  data.setUint8(0, respCodeBattAndStorage);
  data.setUint16(1, millivolts, Endian.little);
  data.setUint32(3, usedKb, Endian.little);
  data.setUint32(7, 1024, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _statsFrame(int txAirSecs) {
  final data = ByteData(14);
  data.setUint8(0, respCodeStats);
  data.setUint8(1, statsTypeRadio);
  data.setInt16(2, -110, Endian.little);
  data.setInt8(4, -80);
  data.setInt8(5, 30);
  data.setUint32(6, txAirSecs, Endian.little);
  data.setUint32(10, 20, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  testWidgets('baseline: dirty and notify calls share one 50 ms window',
      (tester) async {
    await _withConnector(tester, (connector) async {
      final revisions = <int>[];
      connector.addListener(() => revisions.add(connector.uiRevision));
      final before = connector.uiRevision;

      connector.markNotifyDirty();
      connector.notifyListeners();
      connector.markNotifyDirty();
      expect(revisions, isEmpty);
      expect(connector.uiRevision, before);
      await tester.pump(const Duration(milliseconds: 49));
      expect(revisions, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(revisions, [before + 1]);
      expect(connector.uiRevision, before + 1);
    });
  });

  testWidgets('baseline: a late event does not postpone the first notification',
      (tester) async {
    await _withConnector(tester, (connector) async {
      var notifications = 0;
      connector.addListener(() => notifications++);
      connector.markNotifyDirty();
      await tester.pump(const Duration(milliseconds: 49));
      connector.markNotifyDirty();
      await tester.pump(const Duration(milliseconds: 1));
      expect(notifications, 1);
      await tester.pump(const Duration(milliseconds: 49));
      expect(notifications, 1);
    });
  });

  testWidgets('baseline: continuous events still notify once per window',
      (tester) async {
    await _withConnector(tester, (connector) async {
      var notifications = 0;
      connector.addListener(() => notifications++);
      for (var step = 1; step <= 25; step++) {
        connector.markNotifyDirty();
        await tester.pump(const Duration(milliseconds: 10));
        expect(notifications, step ~/ 5);
      }
      expect(notifications, 5);
      await tester.pump(const Duration(seconds: 1));
      expect(notifications, 5);
    });
  });

  testWidgets('baseline: a listener can schedule another bounded window',
      (tester) async {
    await _withConnector(tester, (connector) async {
      final revisions = <int>[];
      final before = connector.uiRevision;
      connector.addListener(() {
        revisions.add(connector.uiRevision);
        if (revisions.length == 1) {
          connector.markNotifyDirty();
          connector.notifyListeners();
        }
      });
      connector.markNotifyDirty();
      await tester.pump(const Duration(milliseconds: 50));
      expect(revisions, [before + 1]);
      await tester.pump(const Duration(milliseconds: 49));
      expect(revisions, [before + 1]);
      await tester.pump(const Duration(milliseconds: 1));
      expect(revisions, [before + 1, before + 2]);
      await tester.pump(const Duration(seconds: 1));
      expect(revisions, [before + 1, before + 2]);
    });
  });

  testWidgets('baseline: after idle the next event starts a fresh window',
      (tester) async {
    await _withConnector(tester, (connector) async {
      var notifications = 0;
      connector.addListener(() => notifications++);
      connector.markNotifyDirty();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(seconds: 1));
      expect(notifications, 1);
      connector.markNotifyDirty();
      await tester.pump(const Duration(milliseconds: 49));
      expect(notifications, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(notifications, 2);
    });
  });

  testWidgets('baseline: state and every raw frame arrive before UI notification',
      (tester) async {
    await _withConnector(tester, (connector) async {
      final received = <Uint8List>[];
      final subscription = connector.receivedFrames.listen(received.add);
      try {
        final seenBattery = <int?>[];
        connector.addListener(() => seenBattery.add(connector.batteryMillivolts));
        final first = _batteryFrame(4100);
        final second = _batteryFrame(4200, usedKb: 24);
        connector.handleFrameForTest(first);
        expect(connector.batteryMillivolts, 4100);
        connector.handleFrameForTest(second);
        expect(connector.batteryMillivolts, 4200);
        expect(connector.storageUsedKb, 24);
        expect(connector.storageTotalKb, 1024);
        expect(seenBattery, isEmpty);

        // Broadcast Stream доставляется микрозадачами, без ожидания окна UI.
        await tester.pump();
        expect(received, [first, second]);
        expect(seenBattery, isEmpty);
        await tester.pump(const Duration(milliseconds: 50));
        expect(seenBattery, [4200]);
        expect(received, hasLength(2));
      } finally {
        // Этот broadcast без onCancel снимает listener синхронно.
        // Общая Future<void> из cancel может ждать вне текущего FakeAsync.
        unawaited(subscription.cancel());
        await tester.pump();
      }
    });
  });

  testWidgets('baseline: radio stats notifier bypasses the pending UI window',
      (tester) async {
    await _withConnector(tester, (connector) async {
      var notifications = 0;
      final txValues = <int>[];
      connector.addListener(() => notifications++);
      connector.radioStatsNotifier.addListener(() {
        txValues.add(connector.radioStatsNotifier.value!.txAirSecs);
      });
      connector.markNotifyDirty();
      connector.handleFrameForTest(_statsFrame(10));
      connector.handleFrameForTest(_statsFrame(12));
      expect(txValues, [10, 12]);
      expect(connector.latestRadioStats!.txAirSecs, 12);
      expect(connector.radioStatsAirActivityPulse, isTrue);
      expect(notifications, 0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(notifications, 1);
      expect(txValues, [10, 12]);
      connector.handleFrameForTest(_statsFrame(12));
      expect(connector.radioStatsAirActivityPulse, isFalse);
      expect(txValues, [10, 12, 12]);
      await tester.pump(const Duration(milliseconds: 50));
      expect(notifications, 1);
    });
  });

  testWidgets('baseline: disposal cancels pending notification and ignores late marks',
      (tester) async {
    final connector = MeshCoreConnector();
    var disposed = false;
    var notifications = 0;
    final before = connector.uiRevision;
    try {
      connector.addListener(() => notifications++);
      connector.markNotifyDirty();
      await tester.pump(const Duration(milliseconds: 49));
      connector.dispose();
      disposed = true;
      connector.markNotifyDirty();
      connector.notifyListeners();
      await tester.pump(const Duration(seconds: 1));
      expect(notifications, 0);
      expect(connector.uiRevision, before);
    } finally {
      if (!disposed) {
        connector.dispose();
      }
      await tester.pump();
    }
  });
}

import 'dart:typed_data';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/image_reassembly_maintenance.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/image_chunk_transport.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/image_send_codec_binding.dart';
import 'package:shared_preferences/shared_preferences.dart';

ImageChunkSet _chunks(int id, {int length = 400}) => buildImageChunks(
  payload: Uint8List.fromList(
    List<int>.generate(length, (index) => (index * 37 + id) & 0xff),
  ),
  metadata: const ImageStreamMetadata(rate: ImageCodecRatePoint.standard),
  senderPrefix: 0x1234,
  imgId: id,
);

class _CountingReassembler extends MaintainedImageReassembler {
  _CountingReassembler({super.clock, super.onFailed, super.selfPrefix});

  int sweeps = 0;

  @override
  List<ImageReassemblyFailure> evictExpired({DateTime? now}) {
    sweeps++;
    return super.evictExpired(now: now);
  }
}

Future<void> _withReassembler(
  WidgetTester tester,
  Future<void> Function(_CountingReassembler) check, {
  void Function(_CountingReassembler, ImageReassemblyFailure)? onFailed,
  int? selfPrefix,
}) async {
  late _CountingReassembler reassembler;
  reassembler = _CountingReassembler(
    clock: tester.binding.clock.now,
    selfPrefix: selfPrefix,
    onFailed: (failure) => onFailed?.call(reassembler, failure),
  );
  try {
    await check(reassembler);
  } finally {
    reassembler.stopMaintenance();
    await tester.pump();
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    // path_provider должен завершиться до входа testWidgets в FakeAsync.
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  testWidgets('off preserves the five-second idle timer and live flag changes',
      (tester) async {
    await _withReassembler(tester, (r) async {
      r.startMaintenance(pauseWhileIdle: false);
      await tester.pump(const Duration(seconds: 15));
      expect(r.sweeps, 3);
      r.startMaintenance(pauseWhileIdle: false);
      await tester.pump(const Duration(seconds: 2));
      r.startMaintenance(pauseWhileIdle: true);
      await tester.pump(const Duration(seconds: 20));
      expect(r.sweeps, 3);
      r.startMaintenance(pauseWhileIdle: false);
      await tester.pump(const Duration(milliseconds: 4999));
      expect(r.sweeps, 3);
      await tester.pump(const Duration(milliseconds: 1));
      expect(r.sweeps, 4);
    });
  });

  testWidgets('opted-in idle cleanup ignores malformed and self chunks',
      (tester) async {
    await _withReassembler(tester, (r) async {
      r.startMaintenance(pauseWhileIdle: true);
      await tester.pump(const Duration(minutes: 2));
      expect(r.sweeps, 0);
      expect(r.addChunk(Uint8List(0)).status, ImageChunkStatus.malformed);
      expect(r.addChunk(_chunks(1).blobs.first).status, ImageChunkStatus.fromSelf);
      final afterChunks = r.sweeps;
      await tester.pump(const Duration(minutes: 2));
      expect(r.sweeps, afterChunks);
      expect(r.pendingCount, 0);
      expect(r.completedCount, 0);
    }, selfPrefix: 0x1234);
  });

  testWidgets('pending work starts cleanup, expires without traffic and restarts',
      (tester) async {
    final failures = <ImageReassemblyFailure>[];
    await _withReassembler(tester, (r) async {
      r.startMaintenance(pauseWhileIdle: true);
      await tester.pump(const Duration(seconds: 2));
      r.addChunk(_chunks(1).blobs.first);
      final afterChunk = r.sweeps;
      await tester.pump(const Duration(milliseconds: 4999));
      expect(r.sweeps, afterChunk);
      await tester.pump(const Duration(milliseconds: 1));
      expect(r.sweeps, afterChunk + 1);
      await tester.pump(const Duration(seconds: 55));
      expect(r.sweeps, afterChunk + 12);
      expect(failures.single.key.imgId, 1);
      expect(r.pendingCount, 0);
      final afterExpiry = r.sweeps;
      await tester.pump(const Duration(minutes: 2));
      expect(r.sweeps, afterExpiry);
      r.addChunk(_chunks(2).blobs.first);
      await tester.pump(const Duration(seconds: 60));
      expect(failures.map((failure) => failure.key.imgId), [1, 2]);
      expect(r.pendingCount, 0);
    }, onFailed: (_, failure) => failures.add(failure));
  });

  testWidgets('completed-only cache keeps cleanup until its own TTL',
      (tester) async {
    final failures = <ImageReassemblyFailure>[];
    await _withReassembler(tester, (r) async {
      r.startMaintenance(pauseWhileIdle: true);
      final chunks = _chunks(1, length: 300);
      r.addChunk(chunks.blobs[0]);
      await tester.pump(const Duration(seconds: 20));
      expect(r.addChunk(chunks.blobs[1]).status, ImageChunkStatus.completed);
      expect(r.pendingCount, 0);
      expect(r.completedCount, 1);
      await tester.pump(const Duration(seconds: 50));
      expect(r.completedCount, 1);
      expect(r.addChunk(chunks.blobs.last).status, ImageChunkStatus.duplicate);
      await tester.pump(const Duration(milliseconds: 9999));
      expect(r.completedCount, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(r.completedCount, 0);
      final afterExpiry = r.sweeps;
      await tester.pump(const Duration(minutes: 2));
      expect(r.sweeps, afterExpiry);
      expect(failures, isEmpty);
    }, onFailed: (_, failure) => failures.add(failure));
  });

  testWidgets('a sweep keeps servicing younger pending and completed work',
      (tester) async {
    final failures = <ImageReassemblyFailure>[];
    await _withReassembler(tester, (r) async {
      r.startMaintenance(pauseWhileIdle: true);
      r.addChunk(_chunks(1).blobs.first);
      await tester.pump(const Duration(seconds: 10));
      r.addChunk(_chunks(2, length: 20).blobs.first);
      await tester.pump(const Duration(seconds: 10));
      r.addChunk(_chunks(3).blobs.first);
      await tester.pump(const Duration(seconds: 40));
      expect(failures.single.key.imgId, 1);
      expect(r.pendingKeys.single.imgId, 3);
      expect(r.completedKeys.single.imgId, 2);
      await tester.pump(const Duration(seconds: 10));
      expect(r.completedCount, 0);
      expect(r.pendingCount, 1);
      await tester.pump(const Duration(seconds: 10));
      expect(failures.map((failure) => failure.key.imgId), [1, 3]);
      final afterExpiry = r.sweeps;
      await tester.pump(const Duration(seconds: 10));
      expect(r.sweeps, afterExpiry);
    }, onFailed: (_, failure) => failures.add(failure));
  });

  testWidgets('channel clear, full clear and stop balance timer ownership',
      (tester) async {
    await _withReassembler(tester, (r) async {
      r.startMaintenance(pauseWhileIdle: true);
      r.addChunk(_chunks(1, length: 20).blobs.first, channelIndex: 3);
      r.addChunk(_chunks(2).blobs.first, channelIndex: 7);
      r.clearChannel(3);
      var before = r.sweeps;
      await tester.pump(const Duration(seconds: 5));
      expect(r.sweeps, before + 1);
      r.clearChannel(7);
      before = r.sweeps;
      await tester.pump(const Duration(seconds: 10));
      expect(r.sweeps, before);
      r.addChunk(_chunks(3, length: 20).blobs.first);
      r.clear();
      before = r.sweeps;
      await tester.pump(const Duration(seconds: 10));
      expect(r.sweeps, before);
      r.addChunk(_chunks(4).blobs.first);
      r.stopMaintenance();
      r.addChunk(_chunks(5).blobs.first);
      before = r.sweeps;
      await tester.pump(const Duration(seconds: 10));
      expect(r.sweeps, before);
      expect(r.pendingCount, 2);
      r.startMaintenance(pauseWhileIdle: true);
      await tester.pump(const Duration(seconds: 5));
      expect(r.sweeps, before + 1);
    });
  });

  testWidgets('a fresh stream from an expiry callback retains the timer',
      (tester) async {
    final failures = <ImageReassemblyFailure>[];
    await _withReassembler(tester, (r) async {
      r.startMaintenance(pauseWhileIdle: true);
      r.addChunk(_chunks(1).blobs.first);
      await tester.pump(const Duration(seconds: 60));
      expect(failures.single.key.imgId, 1);
      expect(r.pendingKeys.single.imgId, 2);
      await tester.pump(const Duration(seconds: 60));
      expect(failures.map((failure) => failure.key.imgId), [1, 2]);
      expect(r.pendingCount, 0);
      final afterExpiry = r.sweeps;
      await tester.pump(const Duration(seconds: 10));
      expect(r.sweeps, afterExpiry);
    }, onFailed: (r, failure) {
      failures.add(failure);
      if (failure.key.imgId == 1) {
        r.addChunk(_chunks(2).blobs.first);
      }
    });
  });

  testWidgets('paused lifecycle does not disable incomplete image expiry',
      (tester) async {
    final failures = <ImageReassemblyFailure>[];
    final previous = tester.binding.lifecycleState ?? AppLifecycleState.resumed;
    try {
      await _withReassembler(tester, (r) async {
        r.startMaintenance(pauseWhileIdle: true);
        r.addChunk(_chunks(1).blobs.first);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(seconds: 60));
        expect(failures, hasLength(1));
        expect(r.pendingCount, 0);
      }, onFailed: (_, failure) => failures.add(failure));
    } finally {
      tester.binding.handleAppLifecycleStateChanged(previous);
      await tester.pump();
    }
  });

  testWidgets('settings binding applies profiles without resetting active cadence',
      (tester) async {
    final settings = AppSettingsService();
    try {
      await _withReassembler(tester, (r) async {
        await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
        final binding = ImageReassemblyMaintenance(reassembler: r, settings: settings);
        try {
          for (final profile in [
            PowerSavingProfile.balanced,
            PowerSavingProfile.economical,
            PowerSavingProfile.maximum,
          ]) {
            await settings.setPowerSavingProfile(profile);
            await tester.pump(const Duration(seconds: 10));
            expect(r.sweeps, 0);
          }
          await settings.setPowerSavingProfile(PowerSavingProfile.custom);
          await tester.pump(const Duration(seconds: 2));
          await settings.setShowHops(!settings.settings.showHops);
          await tester.pump(const Duration(seconds: 3));
          expect(r.sweeps, 1);
          await settings.setPauseIdleImageCleanup(true);
          await tester.pump(const Duration(seconds: 10));
          expect(r.sweeps, 1);
          r.addChunk(_chunks(1).blobs.first);
          final afterChunk = r.sweeps;
          await tester.pump(const Duration(seconds: 2));
          await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
          await tester.pump(const Duration(seconds: 3));
          expect(r.sweeps, afterChunk + 1);
          binding.dispose();
          binding.dispose();
          await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
          r.addChunk(_chunks(2).blobs.first);
          final afterDispose = r.sweeps;
          await tester.pump(const Duration(seconds: 10));
          expect(r.sweeps, afterDispose);
        } finally {
          binding.dispose();
        }
      });
    } finally {
      settings.dispose();
    }
  });
}

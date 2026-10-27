import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/cpu_sleep_binding.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/cpu_sleep_options.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/background_service.dart';
import 'package:meshcore_open/services/wardrive_service.dart';

class _Connector extends Fake implements MeshCoreConnector {
  final changes = ChangeNotifier();
  final work = BackgroundWorkTracker();
  bool connected = true;
  MeshCoreTransportType transport = MeshCoreTransportType.bluetooth;
  @override bool get isConnected => connected;
  @override bool get isRecoveringConnection => false;
  @override MeshCoreTransportType get activeTransport => transport;
  @override BackgroundWorkSnapshot get backgroundWorkSnapshot => work.snapshot;
  @override void addListener(VoidCallback listener) => changes.addListener(listener);
  @override void removeListener(VoidCallback listener) => changes.removeListener(listener);
  @override void addBackgroundWorkListener(VoidCallback listener) => work.addListener(listener);
  @override void removeBackgroundWorkListener(VoidCallback listener) => work.removeListener(listener);
  @override int runningBackgroundWorkCount(BackgroundWorkKind kind) => work.runningCountFor(kind);
  @override Future<void>? Function(BackgroundWorkKind)? get backgroundWorkPreparation => work.prepareOperation;
  @override set backgroundWorkPreparation(Future<void>? Function(BackgroundWorkKind)? value) {
    work.prepareOperation = value;
  }
}

class _MemorySettings extends Fake implements AppSettingsService {
  final changes = ChangeNotifier();
  CpuSleepOptions value = const CpuSleepOptions();
  PowerSavingProfile profile = PowerSavingProfile.custom;
  bool unavailable = false;
  @override AppSettings get settings => unavailable
      ? throw StateError('Synthetic settings unavailable') : AppSettings(
    powerSaving: PowerSavingSettings(
      profile: profile,
      custom: PowerSavingOptions(cpuSleep: value),
    ),
  );
  @override void addListener(VoidCallback listener) => changes.addListener(listener);
  @override void removeListener(VoidCallback listener) => changes.removeListener(listener);
}

class _Wardrive extends Fake implements WardriveService {
  final changes = ChangeNotifier();
  bool running = false;
  @override bool get isRunning => running;
  @override void addListener(VoidCallback listener) => changes.addListener(listener);
  @override void removeListener(VoidCallback listener) => changes.removeListener(listener);
}

class _Service extends Fake implements BackgroundService {
  final calls = <({bool requested, bool allowSleep, bool work, bool unconditional})>[];
  Future<void> settled = Future<void>.value();
  @override Future<void> get cpuPolicySettled => settled;
  @override Future<void> configureCpuSleep({required bool requested,
    required bool allowSleep, required bool protectedWork,
    bool unconditional = false}) async {
    calls.add((requested: requested, allowSleep: allowSleep,
      work: protectedWork, unconditional: unconditional));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('binding combines active scenarios, protects work and disposes listeners',
      (tester) async {
    // Settings view is injected through a simple getter; no platform or disk access.
    final connector = _Connector();
    final settings = _MemorySettings();
    final wardrive = _Wardrive();
    final service = _Service();
    final proxy = ValueNotifier(false);
    final binding = CpuSleepBinding(connector: connector, settings: settings,
      service: service, wardrive: wardrive, proxyChanges: proxy,
      proxyActive: () => proxy.value, isAndroid: true);
    try {
      expect(connector.work.prepareOperation, isNull);
      settings.value = const CpuSleepOptions(ble: true);
      settings.changes.notifyListeners();
      binding.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(service.calls.last.allowSleep, isTrue);
      proxy.value = true;
      expect(service.calls.last.allowSleep, isFalse);
      settings.value = const CpuSleepOptions(always: true);
      settings.changes.notifyListeners();
      binding.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(service.calls.last.allowSleep, isTrue);
      final guard = Completer<void>();
      service.settled = guard.future;
      var entered = false;
      final write = connector.work.run(BackgroundWorkKind.persistence, () { entered = true; });
      expect(service.calls.last.work, isTrue);
      expect(entered, isFalse);
      guard.complete();
      await tester.pump();
      await write;
      expect(entered, isTrue);
      expect(service.calls.last.work, isFalse);
    } finally {
      binding.dispose();
      expect(connector.work.prepareOperation, isNull);
      final count = service.calls.length;
      proxy.value = !proxy.value;
      connector.changes.notifyListeners();
      expect(service.calls.length, count);
      proxy.dispose();
      settings.changes.dispose(); connector.changes.dispose(); wardrive.changes.dispose();
    }
  });

  testWidgets('baseline: returning to custom protects work already in progress',
      (tester) async {
    final connector = _Connector();
    final settings = _MemorySettings()
      ..value = const CpuSleepOptions(always: true, ble: true);
    final wardrive = _Wardrive();
    final service = _Service();
    final proxy = ValueNotifier(false);
    final completion = Completer<void>();
    Future<void>? pending;
    final binding = CpuSleepBinding(connector: connector, settings: settings,
      service: service, wardrive: wardrive, proxyChanges: proxy,
      proxyActive: () => proxy.value, isAndroid: true);
    try {
      binding.didChangeAppLifecycleState(AppLifecycleState.resumed);
      pending = connector.work.run(BackgroundWorkKind.persistence,
        () => completion.future);
      await tester.pump();
      expect(service.calls.last.allowSleep, isTrue);
      expect(service.calls.last.work, isTrue);

      settings.profile = PowerSavingProfile.disabled;
      settings.changes.notifyListeners();
      expect(service.calls.last.requested, isFalse);
      expect(service.calls.last.allowSleep, isFalse);
      expect(connector.work.prepareOperation, isNull);
      expect(connector.work.snapshot.countFor(BackgroundWorkKind.persistence), 1);

      // Возврат должен увидеть старую операцию, не требуя нового begin().
      settings.profile = PowerSavingProfile.custom;
      settings.changes.notifyListeners();
      expect(service.calls.last.allowSleep, isTrue);
      expect(service.calls.last.work, isTrue);
      expect(connector.work.prepareOperation, isNotNull);
      expect(settings.value.always && settings.value.ble, isTrue);

      completion.complete();
      await tester.pump();
      await pending;
      expect(service.calls.last.work, isFalse);
      expect(connector.work.snapshot.activeCount, 0);
    } finally {
      if (!completion.isCompleted) completion.complete();
      await tester.pump();
      if (pending != null) await pending;
      binding.dispose();
      proxy.dispose();
      settings.changes.dispose();
      connector.changes.dispose();
      wardrive.changes.dispose();
    }
  });

  testWidgets('unconditional bypasses work preparation and returning protects the same work',
      (tester) async {
    final connector = _Connector();
    final settings = _MemorySettings()
      ..value = const CpuSleepOptions(unconditional: true, always: true, ble: true);
    final wardrive = _Wardrive();
    final service = _Service();
    final proxy = ValueNotifier(true);
    final completion = Completer<void>();
    final guard = Completer<void>();
    Future<void>? pending;
    final binding = CpuSleepBinding(connector: connector, settings: settings,
      service: service, wardrive: wardrive, proxyChanges: proxy,
      proxyActive: () => proxy.value, isAndroid: true);
    try {
      binding.didChangeAppLifecycleState(AppLifecycleState.resumed);
      service.settled = guard.future;
      var entered = false;
      pending = connector.work.run(BackgroundWorkKind.persistence, () {
        entered = true;
        return completion.future;
      });
      expect(entered, isTrue, reason: 'unconditional must not wait for a CPU work guard');
      expect(connector.work.prepareOperation, isNull);
      expect(service.calls.last.unconditional, isTrue);
      expect(service.calls.last.allowSleep, isTrue);
      expect(service.calls.last.work, isFalse);

      settings.value = settings.value.copyWith(unconditional: false);
      settings.changes.notifyListeners();
      expect(service.calls.last.unconditional, isFalse);
      expect(service.calls.last.work, isTrue);
      expect(connector.work.prepareOperation, isNotNull);
      expect(settings.value.always && settings.value.ble, isTrue);
      guard.complete();
      completion.complete();
      await tester.pump();
      await pending;
      expect(service.calls.last.work, isFalse);

      settings.value = settings.value.copyWith(unconditional: true);
      settings.changes.notifyListeners();
      settings.unavailable = true;
      settings.changes.notifyListeners();
      expect(service.calls.last.unconditional, isTrue);
      expect(service.calls.last.work, isFalse,
        reason: 'state fallback must preserve the last unconditional choice');
      binding.dispose();
      expect(service.calls.last.unconditional, isTrue,
        reason: 'UI disposal must not restore a CPU hold in unconditional mode');
    } finally {
      if (!guard.isCompleted) guard.complete();
      if (!completion.isCompleted) completion.complete();
      await tester.pump();
      if (pending != null) await pending;
      binding.dispose();
      proxy.dispose();
      settings.changes.dispose();
      connector.changes.dispose();
      wardrive.changes.dispose();
    }
  });

  testWidgets('presets apply BLE-only and protected always without overwriting custom',
      (tester) async {
    final connector = _Connector();
    final settings = _MemorySettings()
      ..profile = PowerSavingProfile.balanced
      ..value = const CpuSleepOptions(unconditional: true, tcp: true, wardrive: true);
    final savedCustom = settings.value.toJson();
    final wardrive = _Wardrive();
    final service = _Service();
    final proxy = ValueNotifier(false);
    final binding = CpuSleepBinding(connector: connector, settings: settings,
      service: service, wardrive: wardrive, proxyChanges: proxy,
      proxyActive: () => proxy.value, isAndroid: true);
    try {
      binding.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(service.calls.last.requested, isFalse);
      settings.profile = PowerSavingProfile.economical;
      settings.changes.notifyListeners();
      expect(service.calls.last.allowSleep, isTrue);
      expect(service.calls.last.unconditional, isFalse);
      binding.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(service.calls.last.allowSleep, isFalse);
      binding.didChangeAppLifecycleState(AppLifecycleState.paused);
      proxy.value = true;
      expect(service.calls.last.allowSleep, isFalse,
        reason: 'BLE permission alone does not permit sleep for a running proxy');

      settings.profile = PowerSavingProfile.maximum;
      settings.changes.notifyListeners();
      binding.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(service.calls.last.allowSleep, isTrue);
      expect(service.calls.last.unconditional, isFalse);
      expect(connector.work.prepareOperation, isNotNull);
      expect(settings.value.toJson(), savedCustom);

      settings.profile = PowerSavingProfile.custom;
      settings.changes.notifyListeners();
      expect(service.calls.last.unconditional, isTrue);
      expect(connector.work.prepareOperation, isNull);
      expect(settings.value.toJson(), savedCustom);
    } finally {
      binding.dispose();
      proxy.dispose();
      settings.changes.dispose();
      connector.changes.dispose();
      wardrive.changes.dispose();
    }
  });
}

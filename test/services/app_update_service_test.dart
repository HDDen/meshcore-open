import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/services/app_update_service.dart';
import 'package:meshcore_open/services/github_release_check.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends GitHubReleaseCheck {
  int calls = 0;
  bool available = false;
  UpdateCheckException? error;
  Completer<void>? gate;
  @override
  Future<bool> hasNewerRelease(String installedCommit) async {
    calls++;
    await gate?.future;
    if (error != null) throw error!;
    return available;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late _Api api;
  late AppUpdateService service;
  var now = DateTime.utc(2026, 10, 29, 12);
  final events = <AppUpdateResult>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    api = _Api();
    now = DateTime.utc(2026, 10, 29, 12);
    events.clear();
    service = AppUpdateService(preferences: prefs, api: api,
      installedCommit: 'a' * 40, clock: () => now);
    service.results.listen(events.add);
  });
  tearDown(() => service.dispose());

  test('automatic setting defaults on and false survives unrelated copy and JSON', () {
    expect(AppSettings().checkGitHubUpdates, isTrue);
    expect(AppSettings.fromJson({}).checkGitHubUpdates, isTrue);
    final custom = AppSettings().copyWith(checkGitHubUpdates: false)
        .copyWith(showHops: false);
    expect(AppSettings.fromJson(custom.toJson()).checkGitHubUpdates, isFalse);
  });

  test('manual attempt moves the daily automatic deadline, including across restart', () async {
    await service.check();
    expect(api.calls, 1);
    expect(events.single.manual, isFalse);
    now = now.add(const Duration(hours: 12));
    await service.check();
    expect(api.calls, 1);
    await service.check(manual: true);
    expect(api.calls, 2);
    expect(events.last.manual, isTrue);
    expect(service.timeUntilCheck, const Duration(days: 1));
    final next = AppUpdateService(preferences: prefs, api: _Api(),
      installedCommit: 'a' * 40, clock: () => now);
    addTearDown(next.dispose);
    expect(next.timeUntilCheck, const Duration(days: 1));
    now = now.add(const Duration(days: 1));
    await service.check();
    expect(api.calls, 3);
  });

  test('failed checks are throttled and cannot erase a cached update', () async {
    api.available = true;
    await service.check();
    expect(service.updateAvailable, isTrue);
    api.error = const UpdateCheckException(UpdateCheckError.network);
    await service.check(manual: true);
    expect(service.updateAvailable, isTrue);
    expect(events.last.error!.reason, UpdateCheckError.network);
    now = now.add(const Duration(hours: 23));
    await service.check();
    expect(api.calls, 2);
    final same = AppUpdateService(preferences: prefs, api: _Api(),
      installedCommit: 'a' * 40, clock: () => now);
    final other = AppUpdateService(preferences: prefs, api: _Api(),
      installedCommit: 'b' * 40, clock: () => now);
    final anotherBuild = AppUpdateService(preferences: prefs, api: _Api(),
      installedCommit: 'a' * 40, buildIdentity: 'different-module-or-options', clock: () => now);
    addTearDown(same.dispose);
    addTearDown(other.dispose);
    addTearDown(anotherBuild.dispose);
    expect(same.updateAvailable, isTrue);
    expect(other.updateAvailable, isFalse);
    expect(anotherBuild.updateAvailable, isFalse);
  });

  test('manual request joins the automatic request and keeps its later deadline on failure', () async {
    api.gate = Completer<void>();
    api.error = const UpdateCheckException(UpdateCheckError.network);
    final automatic = service.check();
    // Allow the real mocked preferences future to finish before API entry.
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(minutes: 5));
    final manual = service.check(manual: true);
    expect(identical(automatic, manual), isTrue);
    api.gate!.complete();
    await manual;
    expect(api.calls, 1);
    expect(events.single.manual, isTrue);
    final reopened = AppUpdateService(preferences: prefs, api: _Api(),
      installedCommit: 'a' * 40, clock: () => now);
    addTearDown(reopened.dispose);
    expect(reopened.timeUntilCheck, const Duration(days: 1));
  });
}

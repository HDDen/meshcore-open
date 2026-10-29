import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_build_info.dart';
import 'github_release_check.dart';

class AppUpdateResult {
  const AppUpdateResult({required this.manual, this.available = false, this.error});
  final bool manual;
  final bool available;
  final UpdateCheckException? error;
}

/// One foreground check per 24 hours, including failed attempts. Manual checks
/// bypass the interval, join an existing request, and move the next deadline.
class AppUpdateService extends ChangeNotifier {
  AppUpdateService({
    required SharedPreferences preferences,
    GitHubReleaseCheck? api,
    String installedCommit = appGitCommit,
    String? buildIdentity,
    DateTime Function()? clock,
  }) : _preferences = preferences,
       _api = api ?? GitHubReleaseCheck(),
       _commit = installedCommit,
       _buildIdentity = buildIdentity ??
           (installedCommit == appGitCommit ? appBuildIdentity : installedCommit),
       _clock = clock ?? DateTime.now {
    try {
      final stored = jsonDecode(_preferences.getString(_key) ?? '{}');
      if (stored is Map<String, dynamic>) {
        final last = stored['lastAttemptMs'];
        if (last is int && last >= 0) {
          _lastAttempt = DateTime.fromMillisecondsSinceEpoch(last);
        }
        _updateAvailable = stored['commit'] == _commit &&
            stored['build'] == _buildIdentity && stored['available'] == true;
      }
    } catch (_) {
      // A malformed old cache is disposable; it must not prevent a new check.
    }
  }

  static const _key = 'github_update_check';
  static const interval = Duration(days: 1);
  final SharedPreferences _preferences;
  final GitHubReleaseCheck _api;
  final String _commit;
  final String _buildIdentity;
  final DateTime Function() _clock;
  final _results = StreamController<AppUpdateResult>.broadcast(sync: true);
  Stream<AppUpdateResult> get results => _results.stream;
  DateTime? _lastAttempt;
  Future<void>? _inFlight;
  bool _manual = false;
  bool _disposed = false;
  bool _updateAvailable = false;
  bool get updateAvailable => _updateAvailable;
  bool get checking => _inFlight != null;
  DateTime get nextCheckAt => (_lastAttempt ?? DateTime.fromMillisecondsSinceEpoch(0)).add(interval);
  Duration get timeUntilCheck {
    final now = _clock();
    // A clock correction must not disable checks indefinitely.
    if (_lastAttempt == null || _lastAttempt!.isAfter(now)) return Duration.zero;
    final remaining = nextCheckAt.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> _save() async {
    final saved = await _preferences.setString(_key, jsonEncode({
      'lastAttemptMs': _lastAttempt?.millisecondsSinceEpoch,
      'commit': _commit,
      'build': _buildIdentity,
      'available': updateAvailable,
    }));
    if (!saved) throw const UpdateCheckException(UpdateCheckError.storage);
  }

  Future<void> check({bool manual = false}) {
    if (_disposed) return Future<void>.value();
    if (_inFlight != null) {
      _manual = _manual || manual;
      if (manual) _lastAttempt = _clock();
      return _inFlight!;
    }
    if (!manual && timeUntilCheck > Duration.zero) return Future<void>.value();
    _manual = manual;
    _lastAttempt = _clock();
    // Install the in-flight guard before starting any injected async work.
    final done = Completer<void>();
    _inFlight = done.future;
    notifyListeners();
    unawaited(_run().whenComplete(() {
      _inFlight = null;
      if (!_disposed) notifyListeners();
      done.complete();
    }));
    return done.future;
  }

  Future<void> _run() async {
    UpdateCheckException? failure;
    try {
      await _save(); // Persist the attempt before touching the network.
      final available = await _api.hasNewerRelease(_commit);
      if (_disposed) return;
      _updateAvailable = available;
    } on UpdateCheckException catch (error) {
      failure = error;
    } catch (_) {
      failure = const UpdateCheckException(UpdateCheckError.storage);
    }
    if (_disposed) return;
    // A manual request may have joined a failed automatic request later.
    // Persist its newer deadline as well, without starting a second HTTP chain.
    try {
      await _save();
    } catch (_) {
      failure ??= const UpdateCheckException(UpdateCheckError.storage);
    }
    if (_disposed) return;
    _results.add(AppUpdateResult(manual: _manual, available: updateAvailable, error: failure));
  }

  @override
  void dispose() {
    _disposed = true;
    _api.close();
    unawaited(_results.close());
    super.dispose();
  }
}

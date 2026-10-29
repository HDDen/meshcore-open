import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../services/app_settings_service.dart';
import '../services/app_update_service.dart';
import '../services/github_release_check.dart';
import 'mesh_ui.dart';
import 'settings_nav_tile_content.dart';

String _errorReason(BuildContext context, UpdateCheckException error) {
  final l10n = context.l10n;
  return switch (error.reason) {
    UpdateCheckError.missingCommit => l10n.updates_errorMissingCommit,
    UpdateCheckError.unknownCommit => l10n.updates_errorUnknownCommit,
    UpdateCheckError.diverged => l10n.updates_errorDiverged,
    UpdateCheckError.network => l10n.updates_errorNetwork,
    UpdateCheckError.timeout => l10n.updates_errorTimeout,
    UpdateCheckError.rateLimit => l10n.updates_errorRateLimit,
    UpdateCheckError.http => l10n.updates_errorHttp(error.statusCode ?? 0),
    UpdateCheckError.invalidResponse => l10n.updates_errorResponse,
    UpdateCheckError.storage => l10n.updates_errorStorage,
    UpdateCheckError.browser => l10n.updates_errorBrowser,
  };
}

void showUpdateResult(BuildContext context, ScaffoldMessengerState messenger,
    AppUpdateResult result) {
  if (result.error == null && !result.available && !result.manual) return;
  final l10n = context.l10n;
  final colors = Theme.of(context).colorScheme;
  final error = result.error;
  final message = error != null ? l10n.updates_failed :
      result.available ? l10n.updates_found : l10n.updates_notFound;
  final reason = error == null ? null : _errorReason(context, error);
  messenger.showSnackBar(SnackBar(
    // Inherit the application's normal snackbar background and text colors.
    backgroundColor: error != null ? colors.error : null,
    padding: EdgeInsets.zero,
    duration: Duration(seconds: error != null ? 8 : result.available ? 8 : 4),
    content: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        messenger.hideCurrentSnackBar();
        if (error != null) {
          try {
            await Clipboard.setData(ClipboardData(text: '$message\n$reason'));
          } catch (_) {
            // A clipboard failure must still dismiss the original notice.
          }
        } else if (result.available) {
          await openGitHubReleases(context);
        }
      },
      child: Semantics(
        button: true,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: error != null ? TextStyle(color: colors.onError) : null),
              if (reason != null) ...[
                const SizedBox(height: 4),
                Text(reason, style: TextStyle(color: colors.onError)),
              ],
            ],
          ),
        ),
      ),
    ),
  ));
}

Future<void> openGitHubReleases(BuildContext context) async {
  try {
    if (await launchUrl(githubReleasesPage, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // Report the failure locally; the known update remains available.
  }
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger != null) {
    showUpdateResult(context, messenger, const AppUpdateResult(
      manual: true, error: UpdateCheckException(UpdateCheckError.browser)));
  }
}

class AppUpdateSettingsTile extends StatelessWidget {
  const AppUpdateSettingsTile({super.key});
  @override
  Widget build(BuildContext context) {
    final service = context.watch<AppUpdateService>();
    return MeshCard(
      key: const ValueKey('github-update-check'),
      onTap: service.checking ? null : () {
        if (service.updateAvailable) {
          unawaited(openGitHubReleases(context));
        } else {
          unawaited(service.check(manual: true));
        }
      },
      child: SettingsNavTileContent(
        icon: service.updateAvailable ? Icons.system_update : Icons.update,
        title: service.updateAvailable ? context.l10n.updates_available :
            service.checking ? context.l10n.updates_checking : context.l10n.updates_check,
        trailing: service.checking ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ) : null,
      ),
    );
  }
}

/// Only foreground timers: no background service, wake lock or OS alarm.
/// Results that arrive while inactive wait until the app is visible again.
class AppUpdateBinding extends StatefulWidget {
  const AppUpdateBinding({super.key, required this.child, required this.messengerKey});
  final Widget child;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  @override
  State<AppUpdateBinding> createState() => _AppUpdateBindingState();
}

class _AppUpdateBindingState extends State<AppUpdateBinding> with WidgetsBindingObserver {
  AppUpdateService? _service;
  AppSettingsService? _settings;
  StreamSubscription<AppUpdateResult>? _subscription;
  Timer? _timer;
  AppUpdateResult? _pending;
  bool _queued = false;
  bool get _foreground => WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<AppUpdateService>();
    final settings = context.read<AppSettingsService>();
    if (!identical(service, _service)) {
      _service?.removeListener(_schedule);
      unawaited(_subscription?.cancel());
      _service = service;
      service.addListener(_schedule);
      _subscription = service.results.listen((result) {
        if (result.error == null && !result.available && !result.manual) return;
        _pending = result;
        _queueFrame();
      });
    }
    if (!identical(settings, _settings)) {
      _settings?.removeListener(_schedule);
      _settings = settings;
      settings.addListener(_schedule);
    }
    _queueFrame();
  }

  void _queueFrame() {
    if (_queued || !mounted || !_foreground) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted || !_foreground) return;
      final messenger = widget.messengerKey.currentState;
      if (_pending != null && messenger != null) {
        final result = _pending!;
        _pending = null;
        showUpdateResult(context, messenger, result);
      }
      _schedule();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    final service = _service;
    if (!mounted || !_foreground || service == null || service.checking ||
        _settings?.settings.checkGitHubUpdates != true) {
      return;
    }
    _timer = Timer(service.timeUntilCheck, () {
      _timer = null;
      if (mounted && _foreground && _settings?.settings.checkGitHubUpdates == true) {
        unawaited(service.check());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    _timer = null;
    if (state == AppLifecycleState.resumed) _queueFrame();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service?.removeListener(_schedule);
    _settings?.removeListener(_schedule);
    unawaited(_subscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

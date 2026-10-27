import 'dart:async';

import 'package:flutter/services.dart';

import '../utils/platform_info.dart';
import 'ios_presentation_guard.dart';

const _sources = <String>{'audio', 'requested'};
const _events = <String>{
  'initial', 'started', 'stopped', 'categoryFailed', 'activationFailed',
  'playFailed', 'interruptionBegan', 'interruptionEnded', 'mediaServicesReset',
  'routeChanged',
};
const _categories = <String>{
  'AVAudioSessionCategoryAmbient', 'AVAudioSessionCategorySoloAmbient',
  'AVAudioSessionCategoryPlayback', 'AVAudioSessionCategoryRecord',
  'AVAudioSessionCategoryPlayAndRecord', 'AVAudioSessionCategoryMultiRoute',
};
const _modes = <String>{
  'AVAudioSessionModeDefault', 'AVAudioSessionModeVoiceChat',
  'AVAudioSessionModeGameChat', 'AVAudioSessionModeVideoRecording',
  'AVAudioSessionModeMoviePlayback', 'AVAudioSessionModeMeasurement',
  'AVAudioSessionModeVideoChat', 'AVAudioSessionModeSpokenAudio',
  'AVAudioSessionModeVoicePrompt',
};
const _ports = <String>{
  'Speaker', 'Receiver', 'Headphones', 'LineOut', 'AirPlay', 'HDMIOutput',
  'BluetoothA2DPOutput', 'BluetoothLE', 'BluetoothHFP', 'USBAudio',
  'DisplayPort', 'CarAudio', 'AVB', 'Virtual', 'PCI', 'FireWire',
};

String _token(Object? value, Set<String> allowed) =>
    value is String && allowed.contains(value) ? value : 'other';

/// Only known primitive fields can reach a log; never stringify a native map.
String? formatIosExecutionDiagnostics(Object? raw) {
  if (raw is! Map || raw['schema'] != 1 || raw['revision'] is! int ||
      (raw['revision'] as int) < 0 || !_sources.contains(raw['source'])) {
    return null;
  }
  const flags = <String>['eligible', 'manualAllowed', 'background', 'armed', 'legacyInjection'];
  if (!flags.every((key) => raw[key] is bool)) {
    return null;
  }
  final audio = raw['audio'];
  if (audio is! Map || audio['schema'] != 1 || audio['running'] is! bool) {
    return null;
  }
  if (audio['backendArmed'] is! bool || audio['physicalBackground'] is! bool) {
    return null;
  }
  const counts = <String>[
    'startAttempts', 'playStarts', 'cleanupStops', 'interruptions',
    'mediaResets', 'routeChanges', 'failures', 'categoryOptions', 'playerChannels',
  ];
  if (!counts.every((key) => audio[key] is int && (audio[key] as int) >= 0)) {
    return null;
  }
  const values = <String>[
    'sampleRate', 'preferredSampleRate', 'ioBufferDuration',
    'preferredIOBufferDuration', 'playerSampleRate', 'playerDuration', 'playerVolume',
  ];
  if (!values.every((key) => audio[key] is num &&
      (audio[key] as num).isFinite && (audio[key] as num) >= 0)) {
    return null;
  }
  final routes = audio['outputPortTypes'];
  if (routes is! List || routes.length > 16) {
    return null;
  }
  final portTypes = routes.map((value) => _token(value, _ports)).toSet().toList()..sort();
  final fields = <String>[
    'audioSchema=1', 'revision=${raw['revision']}', 'source=${raw['source']}',
    for (final key in flags) '$key=${raw[key]}',
    'running=${audio['running']}', 'event=${_token(audio['event'], _events)}',
    'backendArmed=${audio['backendArmed']}', 'physicalBackground=${audio['physicalBackground']}',
    'category=${_token(audio['category'], _categories)}',
    'mode=${_token(audio['mode'], _modes)}', 'outputPortTypes=${portTypes.join('|')}',
    for (final key in counts) '$key=${audio[key]}',
    for (final key in values) '$key=${(audio[key] as num).toStringAsFixed(6)}',
    if (raw['nativeAtUtcMs'] is int) 'nativeAtUtcMs=${raw['nativeAtUtcMs']}',
    if (raw['nativeUptimeMs'] is int) 'nativeUptimeMs=${raw['nativeUptimeMs']}',
  ];
  return fields.join(', ');
}

/// Explicit request when copying the log. No polling, player or hold changes.
Future<String?> readIosExecutionDiagnostics({
  bool? isIos,
  MethodChannel channel = const MethodChannel('mco_advanced/ios_execution'),
}) async {
  if (!(isIos ?? PlatformInfo.isIOS)) {
    return null;
  }
  try {
    final raw = await channel.invokeMethod<Object?>('diagnostics')
        .timeout(const Duration(seconds: 3));
    final audio = formatIosExecutionDiagnostics(raw);
    final frames = currentIosFrameDiagnosticsSummary();
    return '${audio ?? 'Audio diagnostics unavailable (invalid snapshot)'}'
        '${frames == null ? '' : ', $frames'}';
  } on MissingPluginException {
    return 'Audio diagnostics unavailable (older runner)';
  } on PlatformException {
    return 'Audio diagnostics unavailable (native error)';
  } on TimeoutException {
    return 'Audio diagnostics unavailable (timeout)';
  }
}

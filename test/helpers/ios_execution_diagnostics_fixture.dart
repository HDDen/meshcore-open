// Synthetic audio metadata only: no real route, device, account or credentials.
Map<String, Object> iosExecutionDiagnosticsFixture({int revision = 1}) => {
  'schema': 1, 'revision': revision, 'source': 'audio',
  'eligible': true, 'manualAllowed': true, 'background': true,
  'armed': true, 'legacyInjection': false,
  'nativeAtUtcMs': 10000, 'nativeUptimeMs': 9000,
  'audio': <String, Object>{
    'schema': 1, 'event': 'started', 'running': true,
    'backendArmed': true, 'physicalBackground': true,
    'startAttempts': 1, 'playStarts': 1, 'cleanupStops': 0, 'interruptions': 0,
    'mediaResets': 0, 'routeChanges': 0, 'failures': 0,
    'category': 'AVAudioSessionCategoryPlayback', 'mode': 'AVAudioSessionModeDefault',
    'categoryOptions': 1, 'outputPortTypes': ['Speaker'],
    'sampleRate': 48000.0, 'preferredSampleRate': 44100.0,
    'ioBufferDuration': 0.02, 'preferredIOBufferDuration': 0.005,
    'playerSampleRate': 8000.0, 'playerChannels': 1,
    'playerDuration': 1.0, 'playerVolume': 0.0,
  },
};

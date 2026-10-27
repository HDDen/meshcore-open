/// Экспериментальные параметры удержания iOS. Исходные значения ничего не меняют.
class IosImmortalizerPowerOptions {
  const IosImmortalizerPowerOptions({
    this.pauseUiFrames = false,
    this.leanHooks = false,
    this.withoutAudio = false,
    this.useOutputSampleRate = false,
    this.audioBufferMilliseconds = 0,
    this.loopSeconds = 1,
  }) : assert(audioBufferMilliseconds >= 0 && audioBufferMilliseconds <= 200),
       assert(audioBufferMilliseconds % 10 == 0),
       assert(loopSeconds >= 1 && loopSeconds <= 10);

  final bool pauseUiFrames;
  final bool leanHooks;
  final bool withoutAudio;
  final bool useOutputSampleRate;
  /// Ноль — не задавать предпочтение audio session, а не запрашивать 0 секунд.
  final int audioBufferMilliseconds;
  final int loopSeconds;
  bool get isOriginal => this == const IosImmortalizerPowerOptions();

  static int _buffer(Object? value) => value is int
      ? value.clamp(0, 200).toInt() ~/ 10 * 10 : 0;
  static int _loop(Object? value) => value is int ? value.clamp(1, 10).toInt() : 1;

  IosImmortalizerPowerOptions copyWith({bool? pauseUiFrames, bool? leanHooks,
    bool? withoutAudio, bool? useOutputSampleRate, int? audioBufferMilliseconds,
    int? loopSeconds}) => IosImmortalizerPowerOptions(
      pauseUiFrames: pauseUiFrames ?? this.pauseUiFrames,
      leanHooks: leanHooks ?? this.leanHooks,
      withoutAudio: withoutAudio ?? this.withoutAudio,
      useOutputSampleRate: useOutputSampleRate ?? this.useOutputSampleRate,
      audioBufferMilliseconds: _buffer(audioBufferMilliseconds ?? this.audioBufferMilliseconds),
      loopSeconds: _loop(loopSeconds ?? this.loopSeconds),
    );

  factory IosImmortalizerPowerOptions.fromJson(Object? value) => IosImmortalizerPowerOptions(
    pauseUiFrames: value is Map && value['pause_ui_frames'] == true,
    leanHooks: value is Map && value['lean_hooks'] == true,
    withoutAudio: value is Map && value['without_audio'] == true,
    useOutputSampleRate: value is Map && value['use_output_sample_rate'] == true,
    audioBufferMilliseconds: _buffer(value is Map ? value['audio_buffer_milliseconds'] : null),
    loopSeconds: _loop(value is Map ? value['loop_seconds'] : null),
  );

  Map<String, Object> toJson() => {
    'pause_ui_frames': pauseUiFrames, 'lean_hooks': leanHooks,
    'without_audio': withoutAudio, 'use_output_sample_rate': useOutputSampleRate,
    'audio_buffer_milliseconds': audioBufferMilliseconds, 'loop_seconds': loopSeconds,
  };

  Map<String, Object> toNativeArguments() => {
    'schema': 1, 'pauseUiFrames': pauseUiFrames, 'leanHooks': leanHooks,
    'withoutAudio': withoutAudio, 'useOutputSampleRate': useOutputSampleRate,
    'audioBufferMilliseconds': audioBufferMilliseconds, 'loopSeconds': loopSeconds,
  };

  @override
  bool operator ==(Object other) => other is IosImmortalizerPowerOptions &&
      pauseUiFrames == other.pauseUiFrames && leanHooks == other.leanHooks &&
      withoutAudio == other.withoutAudio && useOutputSampleRate == other.useOutputSampleRate &&
      audioBufferMilliseconds == other.audioBufferMilliseconds && loopSeconds == other.loopSeconds;
  @override
  int get hashCode => Object.hash(pauseUiFrames, leanHooks, withoutAudio,
      useOutputSampleRate, audioBufferMilliseconds, loopSeconds);
}

class BuildFeatures {
  const BuildFeatures._();

  static const bool llmTranslationEnabled = bool.fromEnvironment(
    'MESHCORE_ENABLE_TRANSLATION',
    defaultValue: true,
  );
}

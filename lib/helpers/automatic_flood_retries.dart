/// The first automatic Flood is part of the ordinary attempt budget.
/// Extra attempts keep the same message timestamp and advance its wire number.
class AutomaticFloodRetries {
  const AutomaticFloodRetries({
    required this.firstAttempt,
    required this.lastAttempt,
  });

  final int firstAttempt;
  final int lastAttempt;

  bool shouldBoost(int attempt, int boostedRetries) =>
      attempt > firstAttempt &&
      attempt <= lastAttempt &&
      attempt > lastAttempt - boostedRetries;
}

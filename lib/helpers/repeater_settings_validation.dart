/// Firmware radio values that must be supplied together in `set radio`.
enum RepeaterRadioParameter { frequency, bandwidth, spreadingFactor, codingRate }

/// CommonRadioPrefs accepts finite TX delay factors in the inclusive 0..2
/// range for both `txdelay` and `direct.txdelay`. Keep this validation outside
/// the screen so it cannot diverge between those two controls.
double? parseRepeaterTxDelay(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || !value.isFinite || value < 0 || value > 2) {
    return null;
  }
  return value;
}

/// Report absent values without inventing radio defaults. The caller retains
/// its dirty draft and labels these fields with the existing localization.
List<RepeaterRadioParameter> missingRepeaterRadioParameters({
  required String frequency,
  int? bandwidth,
  int? spreadingFactor,
  int? codingRate,
}) => [
  if (frequency.trim().isEmpty) RepeaterRadioParameter.frequency,
  if (bandwidth == null) RepeaterRadioParameter.bandwidth,
  if (spreadingFactor == null) RepeaterRadioParameter.spreadingFactor,
  if (codingRate == null) RepeaterRadioParameter.codingRate,
];

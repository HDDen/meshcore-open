typedef BatteryVoltageRange = ({int minMv, int maxMv});

const String batteryChemistryCustom = 'custom';

BatteryVoltageRange batteryVoltageRange(String chemistry) {
  switch (chemistry) {
    case 'lifepo4':
      return (minMv: 2600, maxMv: 3650);
    case 'lipo':
      return (minMv: 3000, maxMv: 4200);
    case 'nmc':
    default:
      return (minMv: 3000, maxMv: 4200);
  }
}

int estimateBatteryPercentFromMillivolts(
  int millivolts,
  String chemistry, {
  BatteryVoltageRange? customRange,
}) {
  final range = customRange ?? batteryVoltageRange(chemistry);
  if (millivolts <= range.minMv) return 0;
  if (millivolts >= range.maxMv) return 100;
  return (((millivolts - range.minMv) * 100) / (range.maxMv - range.minMv))
      .round();
}

int estimateBatteryPercentFromVolts(
  double volts,
  String chemistry, {
  BatteryVoltageRange? customRange,
}) {
  final millivolts = (volts * 1000).round();
  return estimateBatteryPercentFromMillivolts(
    millivolts,
    chemistry,
    customRange: customRange,
  );
}

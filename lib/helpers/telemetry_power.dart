/// Estimate from the voltage and current reported together on one channel.
/// Keep the sign and leave the sensor's transmitted power untouched.
double? calculatedTelemetryPowerWatts(Map<String, dynamic> values) {
  final voltage = values['voltage'];
  final current = values['current'];
  if (voltage is! num || current is! num) {
    return null;
  }
  if (!voltage.isFinite || !current.isFinite) {
    return null;
  }
  final watts = voltage.toDouble() * current.toDouble();
  return watts.isFinite ? watts : null;
}

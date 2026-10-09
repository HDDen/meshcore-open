import '../l10n/app_localizations.dart';

/// What the phone has to allow for wardriving to go on in the background on
/// Android, in the order the option asks for them: the notification the
/// foreground service shows, location services, location allowed all the
/// time, background activity not restricted, and the battery optimization
/// exemption that keeps the service alive. On Android 13 and newer the last
/// two are one three-way battery setting, unrestricted, optimized or
/// restricted; on 9 to 12 they are two switches, so both are checked.
enum WardriveBackgroundRequirement {
  notifications,
  locationServices,
  locationAlways,
  backgroundActivity,
  batteryOptimization,
}

/// The requirement to ask for next: the first of [missing] after [lastAsked]
/// in the enum's order, round the end, so a tap after a screen the user
/// backed out of moves on to the next permission and comes back round to the
/// first. Null with nothing missing. [missing] is in the enum's order.
WardriveBackgroundRequirement? nextWardriveBackgroundRequirement(
  List<WardriveBackgroundRequirement> missing,
  WardriveBackgroundRequirement? lastAsked,
) {
  if (missing.isEmpty) return null;
  if (lastAsked != null) {
    for (final requirement in missing) {
      if (requirement.index > lastAsked.index) return requirement;
    }
  }
  return missing.first;
}

/// The requirement as the messages name it.
String wardriveBackgroundRequirementText(
  AppLocalizations l10n,
  WardriveBackgroundRequirement requirement,
) => switch (requirement) {
  WardriveBackgroundRequirement.notifications =>
    l10n.map_wardriveRequirementNotifications,
  WardriveBackgroundRequirement.locationServices =>
    l10n.map_wardriveRequirementLocationServices,
  WardriveBackgroundRequirement.locationAlways =>
    l10n.map_wardriveRequirementLocationAlways,
  WardriveBackgroundRequirement.backgroundActivity =>
    l10n.map_wardriveRequirementBackgroundActivity,
  WardriveBackgroundRequirement.batteryOptimization =>
    l10n.map_wardriveRequirementBattery,
};

import 'package:flutter/material.dart';

export 'contact_action_contract.dart';

import 'contact_action_contract.dart';

class McoBatteryChemistryProfile {
  const McoBatteryChemistryProfile({
    required this.id,
    required this.label,
    required this.minVolts,
    required this.maxVolts,
  });

  final String id;
  final String label;
  final double minVolts;
  final double maxVolts;
}

class SettingsSectionsService extends ChangeNotifier {
  Future<void> initialize() async {}

  bool get useMService => false;

  bool get applyMService => false;

  bool get allowsRestrictedMapBulkDownload => false;

  bool tryEnServ(String input) => false;

  void onAboutDialogDismissed(BuildContext context) {}

  void setDeviceRawVars(Map<String, String>? vars, {String? raw}) {}

  void setDeviceVarsRequester(Future<void> Function()? requester) {}

  void setUiContextProvider(BuildContext? Function()? provider) {}

  void setActiveDeviceKey(String? publicKeyHex) {}

  void setBatteryProfileApplier(
    Future<void> Function(
      String deviceKey,
      String chemistry,
      double minVolts,
      double maxVolts,
    )?
    applier,
  ) {}

  List<McoBatteryChemistryProfile> batteryChemistryProfilesForDevice(
    String? deviceKey, {
    BuildContext? context,
  }) => const [];

  bool get southFrameFragmentsEnabled => false;

  List<LocalizationsDelegate<dynamic>> get localizationsDelegates =>
      const <LocalizationsDelegate<dynamic>>[];

  List<Widget> modSettingsSections(BuildContext context) => const [];

  List<Widget> contactActionTiles(
    BuildContext sheetContext, {
    required BuildContext navigatorContext,
    required String contactName,
    required int contactType,
    required String contactKeyHex,
    required int? spreadingFactor,
    required McoContactActionLoader loadRecords,
    required McoContactActionNodeLoader loadNodes,
    required McoContactActionTraceOpener openTrace,
    required McoContactActionEstimateOpener openEstimate,
  }) => const [];

  List<PopupMenuEntry<dynamic>> contactHeaderActionItems(
    BuildContext menuContext, {
    required BuildContext navigatorContext,
    required int? spreadingFactor,
    required McoContactActionLoader loadRecords,
    required McoContactActionNodeLoader loadNodes,
    required McoContactActionTraceOpener openTrace,
    required McoContactActionEstimateOpener openEstimate,
  }) => const [];
}

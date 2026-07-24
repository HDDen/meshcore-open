import 'package:flutter/material.dart';

class SettingsSectionsService extends ChangeNotifier {
  Future<void> initialize() async {}

  bool get useMService => false;

  bool get applyMService => false;

  bool tryEnServ(String input) => false;

  void onAboutDialogDismissed(BuildContext context) {}

  void setDeviceRawVars(Map<String, String>? vars, {String? raw}) {}

  void setDeviceVarsRequester(Future<void> Function()? requester) {}

  void setActiveDeviceKey(String? publicKeyHex) {}

  bool get southFrameFragmentsEnabled => false;

  List<LocalizationsDelegate<dynamic>> get localizationsDelegates =>
      const <LocalizationsDelegate<dynamic>>[];

  List<Widget> modSettingsSections(BuildContext context) => const [];
}

import 'package:flutter/material.dart';

class SettingsSectionsService extends ChangeNotifier {
  Future<void> initialize() async {}

  bool get useMService => false;

  bool get applyMService => false;

  bool tryEnServ(String input) => false;

  void setDeviceOverride(bool value) {}

  void onAboutDialogDismissed(BuildContext context) {}

  bool get southFrameFragmentsEnabled => false;

  List<LocalizationsDelegate<dynamic>> get localizationsDelegates =>
      const <LocalizationsDelegate<dynamic>>[];

  List<Widget> modSettingsSections(BuildContext context) => const [];
}

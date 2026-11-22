import 'package:mco_service/mco_service.dart';

import 'legacy_offline_access.dart';

class LegacyOfflineBinding {
  LegacyOfflineBinding(this._sections) {
    _sections.addListener(_sync);
    _sync();
  }
  final SettingsSectionsService _sections;
  void _sync() => LegacyOfflineAccess.instance.setEnabled(_sections.legacyOfflineEnabled);
  void dispose() => _sections.removeListener(_sync);
}

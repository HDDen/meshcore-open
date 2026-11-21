import 'package:mco_service/mco_service.dart';

import 'legacy_sender_blocker.dart';

/// Reflects the independent private phrase grant, including a live reset.
class LegacySenderBlockerBinding {
  LegacySenderBlockerBinding(this._sections) {
    _sections.addListener(_sync);
    _sync();
  }

  final SettingsSectionsService _sections;

  void _sync() => LegacySenderBlocker.instance.setEnabled(
    _sections.legacySenderBlockerEnabled,
  );

  void dispose() => _sections.removeListener(_sync);
}

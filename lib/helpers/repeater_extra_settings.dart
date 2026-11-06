final _sfToken = RegExp(r'^\d+$');

/// Additional upstream CLI settings; legacy fork settings keep their own UI.
enum RepeaterExtraSetting {
  floodMaxAdvert,
  floodMaxUnscoped,
  rxDelay,
  cad,
  adcMultiplier,
  extraSf,
}

enum RepeaterExtraSection { advertisement, networkHealth, advanced }

extension RepeaterExtraSettingDetails on RepeaterExtraSetting {
  String get cliKey => switch (this) {
    RepeaterExtraSetting.floodMaxAdvert => 'flood.max.advert',
    RepeaterExtraSetting.floodMaxUnscoped => 'flood.max.unscoped',
    RepeaterExtraSetting.rxDelay => 'rxdelay',
    RepeaterExtraSetting.cad => 'cad',
    RepeaterExtraSetting.adcMultiplier => 'adc.multiplier',
    RepeaterExtraSetting.extraSf => 'extra.sf',
  };

  RepeaterExtraSection get section => switch (this) {
    RepeaterExtraSetting.floodMaxAdvert ||
    RepeaterExtraSetting.floodMaxUnscoped => RepeaterExtraSection.advertisement,
    RepeaterExtraSetting.rxDelay => RepeaterExtraSection.networkHealth,
    _ => RepeaterExtraSection.advanced,
  };

  bool get isToggle => this == RepeaterExtraSetting.cad;
  bool get isDecimal => this == RepeaterExtraSetting.rxDelay ||
      this == RepeaterExtraSetting.adcMultiplier;
}

RepeaterExtraSetting? repeaterExtraSettingForKey(String key) => switch (key) {
  'flood.max.advert' => RepeaterExtraSetting.floodMaxAdvert,
  'flood.max.unscoped' => RepeaterExtraSetting.floodMaxUnscoped,
  'rxdelay' => RepeaterExtraSetting.rxDelay,
  'cad' => RepeaterExtraSetting.cad,
  'adc.multiplier' => RepeaterExtraSetting.adcMultiplier,
  'extra.sf' => RepeaterExtraSetting.extraSf,
  _ => null,
};

/// Null rejects an invalid value; an empty result is a valid extra.sf clear.
/// The unscoped 255 sentinel is readable but cannot be written by CommonCLI.
String? normalizeRepeaterExtraValue(
  RepeaterExtraSetting setting,
  String text, {
  bool fromRadio = false,
}) {
  final value = text.trim();
  switch (setting) {
    case RepeaterExtraSetting.floodMaxAdvert:
    case RepeaterExtraSetting.floodMaxUnscoped:
      final hops = int.tryParse(value);
      if (fromRadio && setting == RepeaterExtraSetting.floodMaxUnscoped &&
          hops == 255) {
        return '255';
      }
      return hops != null && hops >= 0 && hops <= 64 ? '$hops' : null;
    case RepeaterExtraSetting.rxDelay:
    case RepeaterExtraSetting.adcMultiplier:
      final number = double.tryParse(value.replaceAll(',', '.'));
      final max = setting == RepeaterExtraSetting.rxDelay ? 20 : 10;
      return number != null && number.isFinite && number >= 0 && number <= max
          ? '$number' : null;
    case RepeaterExtraSetting.cad:
      return switch (value.toLowerCase()) {
        'on' || 'true' || '1' => 'on',
        'off' || 'false' || '0' => 'off',
        _ => null,
      };
    case RepeaterExtraSetting.extraSf:
      if (value.isEmpty) return '';
      final parts = value.split(',');
      if (parts.length > 3) return null;
      final factors = <int>[];
      for (final part in parts) {
        final token = part.trim();
        if (!_sfToken.hasMatch(token)) return null;
        final sf = int.tryParse(token);
        if (sf == null || sf < 5 || sf > 12) return null;
        factors.add(sf);
      }
      return factors.join(',');
  }
}

/// Parse only recognized values, never treating an unsupported/error reply as
/// an off switch or zero. extra.sf uniquely uses an unprefixed firmware reply.
String? parseRepeaterExtraReply(RepeaterExtraSetting setting, String reply) {
  if (setting == RepeaterExtraSetting.extraSf) {
    final text = reply.trim();
    if (text == 'No extra SF configured') return '';
    if (text.isEmpty) return null;
    return normalizeRepeaterExtraValue(
      setting, text.startsWith('>') ? text.substring(1) : text,
      fromRadio: true,
    );
  }
  for (final line in reply.split('\n')) {
    final text = line.trim();
    if (text.startsWith('>')) {
      return normalizeRepeaterExtraValue(setting, text.substring(1),
          fromRadio: true);
    }
  }
  return null;
}

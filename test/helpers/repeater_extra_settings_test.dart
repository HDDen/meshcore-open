import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/repeater_extra_settings.dart';

void main() {
  test('new keys are distinct and do not intercept legacy settings', () {
    expect(RepeaterExtraSetting.values.map((s) => s.cliKey).toSet(), hasLength(6));
    for (final setting in RepeaterExtraSetting.values) {
      expect(repeaterExtraSettingForKey(setting.cliKey), setting);
    }
    for (final key in ['flood.max', 'radio', 'radio.rxgain', 'owner.info']) {
      expect(repeaterExtraSettingForKey(key), isNull);
    }
  });

  test('numeric limits preserve zero and accept finite decimal factors', () {
    for (final setting in [RepeaterExtraSetting.floodMaxAdvert,
      RepeaterExtraSetting.floodMaxUnscoped]) {
      expect(normalizeRepeaterExtraValue(setting, '0'), '0');
      expect(normalizeRepeaterExtraValue(setting, '64'), '64');
      for (final bad in ['', '-1', '65', '1.5', 'NaN']) {
        expect(normalizeRepeaterExtraValue(setting, bad), isNull, reason: bad);
      }
    }
    for (final setting in [RepeaterExtraSetting.rxDelay,
      RepeaterExtraSetting.adcMultiplier]) {
      final max = setting == RepeaterExtraSetting.rxDelay ? 20 : 10;
      expect(normalizeRepeaterExtraValue(setting, '0'), '0.0');
      expect(normalizeRepeaterExtraValue(setting, '$max'), '$max.0');
      expect(normalizeRepeaterExtraValue(setting, ' 1,25 '), '1.25');
      for (final bad in ['', '-0.01', '${max + 0.01}', 'NaN',
        'Infinity', '-Infinity', '1e309']) {
        expect(normalizeRepeaterExtraValue(setting, bad), isNull, reason: bad);
      }
    }
  });

  test('unscoped 255 can be read but is never a writable hop count', () {
    expect(parseRepeaterExtraReply(
      RepeaterExtraSetting.floodMaxUnscoped, '> 255',
    ), '255');
    expect(normalizeRepeaterExtraValue(
      RepeaterExtraSetting.floodMaxUnscoped, '255',
    ), isNull);
    expect(parseRepeaterExtraReply(
      RepeaterExtraSetting.floodMaxAdvert, '> 255',
    ), isNull);
  });

  test('extra SF keeps order, accepts empty clear and rejects malformed lists',
      () {
    const setting = RepeaterExtraSetting.extraSf;
    expect(normalizeRepeaterExtraValue(setting, ' 5, 12,9 '), '5,12,9');
    expect(normalizeRepeaterExtraValue(setting, '9,9'), '9,9');
    expect(normalizeRepeaterExtraValue(setting, ''), '');
    expect(normalizeRepeaterExtraValue(setting, '  '), '');
    for (final bad in ['4', '13', '5,6,7,8', '9,,10', ',9', '9,',
      '1e1', '9.5', '1 0', '-5', '5x']) {
      expect(normalizeRepeaterExtraValue(setting, bad), isNull, reason: bad);
    }
  });

  test('GET parses prefixed scalars and raw or cleared LR2021 SF values', () {
    expect(parseRepeaterExtraReply(RepeaterExtraSetting.rxDelay,
        'diagnostic\n> 2.5'), '2.5');
    expect(parseRepeaterExtraReply(RepeaterExtraSetting.adcMultiplier,
        '> 0'), '0.0');
    expect(parseRepeaterExtraReply(RepeaterExtraSetting.cad, '> on'), 'on');
    expect(parseRepeaterExtraReply(RepeaterExtraSetting.cad, '> off'), 'off');
    expect(parseRepeaterExtraReply(RepeaterExtraSetting.extraSf, '9,10'), '9,10');
    expect(parseRepeaterExtraReply(RepeaterExtraSetting.extraSf, '> 5,12'), '5,12');
    expect(parseRepeaterExtraReply(RepeaterExtraSetting.extraSf,
        'No extra SF configured'), '');
    expect(parseRepeaterExtraReply(RepeaterExtraSetting.extraSf, '> '), '');
    expect(parseRepeaterExtraReply(RepeaterExtraSetting.extraSf, ''), isNull);
    expect(parseRepeaterExtraReply(RepeaterExtraSetting.extraSf,
        'No extra SF configured: unsupported'), isNull);
  });

  test('unknown/error GET never becomes a loaded zero or an off switch', () {
    for (final setting in RepeaterExtraSetting.values) {
      for (final reply in ['Error: unsupported', 'unknown config',
        '??: ${setting.cliKey}', '> unknown', '> NaN']) {
        expect(parseRepeaterExtraReply(setting, reply), isNull,
            reason: '${setting.cliKey}: $reply');
      }
    }
  });
}

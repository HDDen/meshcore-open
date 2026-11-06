import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/repeater_settings_validation.dart';

void main() {
  test('TX delay accepts the firmware range, decimal comma and whitespace', () {
    for (final value in ['0', '0.25', ' 1,5 ', '2', '2.0']) {
      expect(parseRepeaterTxDelay(value),
          double.parse(value.trim().replaceAll(',', '.')));
    }
  });

  test('TX delay rejects absent, malformed, non-finite and out-of-range input',
      () {
    for (final value in [
      '', ' ', 'invalid', '1,2,3', '-0.0001', '2.0001',
      'NaN', 'Infinity', '-Infinity', '1e309',
    ]) {
      expect(parseRepeaterTxDelay(value), isNull, reason: value);
    }
  });

  test('an incomplete radio bundle lists every missing value in display order',
      () {
    expect(missingRepeaterRadioParameters(frequency: ' '),
        RepeaterRadioParameter.values);
    expect(missingRepeaterRadioParameters(
      frequency: '869.495', bandwidth: 125000, spreadingFactor: 7,
    ), [RepeaterRadioParameter.codingRate]);
    expect(missingRepeaterRadioParameters(
      frequency: '869.495', spreadingFactor: 7, codingRate: 5,
    ), [RepeaterRadioParameter.bandwidth]);
    expect(missingRepeaterRadioParameters(
      frequency: '869.495', bandwidth: 125000, codingRate: 5,
    ), [RepeaterRadioParameter.spreadingFactor]);
    expect(missingRepeaterRadioParameters(
      frequency: '', bandwidth: 125000, spreadingFactor: 7, codingRate: 5,
    ), [RepeaterRadioParameter.frequency]);
  });

  test('a complete radio bundle has no missing values', () {
    expect(missingRepeaterRadioParameters(
      frequency: '869,495', bandwidth: 125000,
      spreadingFactor: 7, codingRate: 5,
    ), isEmpty);
  });
}

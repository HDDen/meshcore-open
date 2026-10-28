import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/companion_cli_support.dart';

void main() {
  test('CLI requires firmware 1.18 or newer independently of protocol code', () {
    for (final version in <String?>[
      null, '', 'unknown', '14', '1', '1.x', '1.18oops', '1.18.-1',
      '1.18.0.1', '0.99.0', '1.9.0', '1.17', '1.17.99', 'v1.17.1-south',
    ]) {
      expect(supportsCompanionCliFirmware(protocolCode: 14, version: version),
        isFalse, reason: '$version');
      expect(supportsCompanionCliFirmware(protocolCode: 99, version: version),
        isFalse, reason: '$version with newer protocol');
    }
    for (final version in [
      '1.18', '1.18.0', '1.18.1', '1.19.0', '1.100.0', '2.0.0',
      'v1.18.0-dev', '1.18.0-south', '1.18.0+luchik', '  V1.18.0  ',
    ]) {
      for (final protocol in [14, 15, 99]) {
        expect(supportsCompanionCliFirmware(protocolCode: protocol, version: version),
          isTrue, reason: '$version, protocol $protocol');
      }
    }
  });

  test('a new firmware label cannot bypass the existing protocol requirement', () {
    for (final protocol in <int?>[null, 0, 12, 13]) {
      expect(supportsCompanionCliFirmware(protocolCode: protocol, version: '1.18.0'), isFalse);
      expect(supportsCompanionCliFirmware(protocolCode: protocol, version: '2.0.0'), isFalse);
    }
  });
}

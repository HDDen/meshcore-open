import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/companion_cli_support.dart';

void main() {
  test('CLI requires firmware 1.18 or newer independently of protocol code', () {
    for (final version in <String?>[
      null, '', 'unknown', '14', '1', '1.x', '1.oops', '1.17.-1',
      '1.17.0.1', '0.99.0', '1.9.0', '1.17', '1.17.99', 'v1.17.1-south',
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

  test('numeric fragments support fork prefixes and suffixes at any supported version', () {
    for (final version in [
      'v1.18.dev', 'MeshCore v1.18.dev', 'south-1.18.dev',
      '1.18oops', '1.18.-1', '1.18.0.1',
      '1.19', '1.25', '2.90', '35.16',
      'v1.19.dev', 'Fork 1.25.beta', 'MeshCore v2.90.dev', 'fork-35.16-rc1',
      'nRF52 build20261029 v1.18.dev', 'fork v1.100.dev',
      'Fork v1.18.999-dev', '  prefix-v1.19.0_suffix  ',
    ]) {
      expect(supportsCompanionCliFirmware(protocolCode: 14, version: version),
        isTrue, reason: version);
    }
  });

  test('unrelated integers and later build versions cannot override an old firmware', () {
    for (final version in [
      'nRF52 build18', 'version 1 beta18', 'v1..18.dev',
      'nRF52 v1.9.dev', 'fork v1.17.dev', 'fork v0.99.dev',
      'fork v0.1.18', 'fork v1.0.18',
      'v1.17 build2026.10', 'v1.17 based-on-1.18',
    ]) {
      expect(supportsCompanionCliFirmware(protocolCode: 14, version: version),
        isFalse, reason: version);
    }
  });

  test('a new firmware label cannot bypass the existing protocol requirement', () {
    for (final protocol in <int?>[null, 0, 12, 13]) {
      expect(supportsCompanionCliFirmware(protocolCode: protocol, version: '1.18.0'), isFalse);
      expect(supportsCompanionCliFirmware(protocolCode: protocol, version: '2.0.0'), isFalse);
      expect(supportsCompanionCliFirmware(protocolCode: protocol, version: 'v1.18.dev'), isFalse);
      expect(supportsCompanionCliFirmware(protocolCode: protocol, version: 'MeshCore v1.18.dev'), isFalse);
      for (final version in ['fork v1.19.dev', 'fork v1.25.dev', 'fork v2.90.dev', 'fork v35.16.dev']) {
        expect(supportsCompanionCliFirmware(protocolCode: protocol, version: version), isFalse);
      }
    }
  });
}

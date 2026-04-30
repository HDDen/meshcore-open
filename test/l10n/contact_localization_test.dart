import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/l10n/contact_localization.dart';
import 'package:meshcore_open/models/contact.dart';

Contact _contact({
  int type = advTypeChat,
  int pathLength = 0,
  int? pathOverride,
}) {
  return Contact(
    publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
    name: 'Node',
    type: type,
    pathLength: pathLength,
    path: Uint8List(0),
    pathOverride: pathOverride,
    lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('Contact.typeLabel', () {
    test('chat', () {
      expect(_contact(type: advTypeChat).typeLabel(l10n), 'Chat');
    });

    test('repeater', () {
      expect(_contact(type: advTypeRepeater).typeLabel(l10n), 'Repeater');
    });

    test('room', () {
      expect(_contact(type: advTypeRoom).typeLabel(l10n), 'Room');
    });

    test('sensor', () {
      expect(_contact(type: advTypeSensor).typeLabel(l10n), 'Sensor');
    });

    test('unknown type falls back', () {
      expect(_contact(type: 99).typeLabel(l10n), 'Unknown');
    });
  });

  group('Contact.pathLabel (override)', () {
    test('override < 0 -> flood (forced)', () {
      expect(_contact(pathOverride: -1).pathLabel(l10n), 'Flood (forced)');
    });

    test('override == 0 -> direct (forced)', () {
      expect(_contact(pathOverride: 0).pathLabel(l10n), 'Direct (forced)');
    });

    test('override > 0 -> hops (forced)', () {
      expect(_contact(pathOverride: 3).pathLabel(l10n), '3 hops (forced)');
    });

    test('override takes precedence over pathLength', () {
      expect(
        _contact(pathLength: 5, pathOverride: -1).pathLabel(l10n),
        'Flood (forced)',
      );
    });
  });

  group('Contact.pathLabel (auto)', () {
    test('pathLength < 0 -> flood', () {
      expect(_contact(pathLength: -1).pathLabel(l10n), 'Flood');
    });

    test('pathLength == 0 -> direct', () {
      expect(_contact(pathLength: 0).pathLabel(l10n), 'Direct');
    });

    test('pathLength == 1 -> singular hop', () {
      expect(_contact(pathLength: 1).pathLabel(l10n), '1 hop');
    });

    test('pathLength > 1 -> plural hops', () {
      expect(_contact(pathLength: 4).pathLabel(l10n), '4 hops');
    });
  });
}

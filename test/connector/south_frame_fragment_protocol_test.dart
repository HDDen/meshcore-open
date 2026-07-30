import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

void main() {
  test('APP_START advertises FR01 only when the setting is enabled', () {
    final enabledName = buildMeshCoreOpenAppName(
      enableSouthFrameFragments: true,
    );
    final disabledName = buildMeshCoreOpenAppName(
      enableSouthFrameFragments: false,
    );

    expect(enabledName, 'MeshCoreOpen;cap=frmfrg1');
    expect(disabledName, 'MeshCoreOpen');

    final enabledFrame = buildAppStartFrame(appName: enabledName);
    final disabledFrame = buildAppStartFrame(appName: disabledName);
    expect(
      utf8.decode(enabledFrame.sublist(8, enabledFrame.length - 1)),
      enabledName,
    );
    expect(
      utf8.decode(disabledFrame.sublist(8, disabledFrame.length - 1)),
      disabledName,
    );
  });

  test('queued FR01 ACK uses the extended SYNC_NEXT layout', () {
    expect(
      buildSyncNextMessageFrame(ackFragmentId: 0x1234, ackFragmentIndex: 1),
      orderedEquals(<int>[cmdSyncNextMessage, 0x01, 0x34, 0x12, 0x01]),
    );
    expect(
      buildSyncNextMessageFrame(),
      orderedEquals(<int>[cmdSyncNextMessage]),
    );
  });
}

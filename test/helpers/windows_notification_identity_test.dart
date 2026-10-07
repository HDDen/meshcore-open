import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/windows_notification_identity.dart';
import 'package:path/path.dart' as p;

// The Windows notification identity of a data folder: the same at every
// launch, different for every folder, readable in the display name. The
// expected values are the RFC 4122 v5 UUIDs of the lowercased paths in the
// legacy GUID's namespace, computed outside the app; a change here changes
// the registry entries of every installed copy.

final _windows = p.Context(style: p.Style.windows);

WindowsNotificationIdentity _identity(String? path) =>
    WindowsNotificationIdentity.forDataFolder(
      path,
      appName: 'MeshCore Open',
      context: _windows,
    );

final _guidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  test('a profile folder gets its own id, GUID and name', () {
    final identity = _identity(r'D:\Mesh\node-868');

    expect(identity.guid, 'c6c014e3-cbdb-5aaa-9948-c0ac51660f31');
    expect(identity.appUserModelId, 'org.meshcore.open.app.c6c014e3cbdb5aaa');
    expect(identity.displayName, 'MeshCore Open (node-868)');
  });

  test('the default folder is named after the app folder', () {
    final identity = _identity(r'D:\Mesh\mco\userdata');

    expect(identity.guid, '063b54fe-811a-5860-aac7-8b9f0700ccb4');
    expect(identity.appUserModelId, 'org.meshcore.open.app.063b54fe811a5860');
    expect(identity.displayName, 'MeshCore Open (mco)');
  });

  test('case and a trailing separator do not make another folder', () {
    final reference = _identity(r'D:\Mesh\node-868');
    final other = _identity(r'd:\MESH\Node-868\');

    expect(other.guid, reference.guid);
    expect(other.appUserModelId, reference.appUserModelId);
  });

  test('different folders get different identities', () {
    final a = _identity(r'D:\Mesh\node-868');
    final b = _identity(r'D:\Mesh\node-433');

    expect(a.guid, isNot(b.guid));
    expect(a.appUserModelId, isNot(b.appUserModelId));
    expect(a.guid, matches(_guidPattern));
    expect(b.guid, matches(_guidPattern));
    expect(a.guid, isNot(WindowsNotificationIdentity.legacyGuid));
  });

  test('a folder at a drive root adds no name', () {
    final identity = _identity(r'D:\userdata');

    expect(identity.displayName, 'MeshCore Open');
    expect(identity.guid, matches(_guidPattern));
  });

  test('without a data folder the legacy identity stays', () {
    final identity = _identity(null);

    expect(identity.appUserModelId, 'org.meshcore.open.app');
    expect(identity.guid, 'e7ea8f85-72f5-4f36-91f6-038f740ccf86');
    expect(identity.displayName, 'MeshCore Open');
  });
}

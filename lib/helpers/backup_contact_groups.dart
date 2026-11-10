import '../models/contact_group.dart';
import '../services/ui_view_state_service.dart' show contactsAllGroupsValue;

List<ContactGroup> readBackupContactGroups(List<Object?> rows) {
  final publicKey = RegExp(r'^[0-9a-fA-F]{64}$');
  const invalid = FormatException('Invalid backup contact group');
  return List<ContactGroup>.unmodifiable(rows.map((row) {
    if (row is! Map<String, Object?> || row['name'] is! String) throw invalid;
    final name = (row['name'] as String).trim();
    if (name.isEmpty ||
        name.contains('\u0000') ||
        name.toLowerCase() == contactsAllGroupsValue) {
      throw invalid;
    }
    final entries = row['members'] ?? const <Object?>[];
    if (entries is! List<Object?>) throw invalid;
    final members = <String>{};
    for (final key in entries) {
      if (key is! String || !publicKey.hasMatch(key)) throw invalid;
      members.add(key.toLowerCase());
    }
    return ContactGroup(name: name, memberKeys: List<String>.unmodifiable(members));
  }));
}

class BackupContactGroupsPreview {
  BackupContactGroupsPreview({
    required this.session,
    required this.expectedValue,
    required List<ContactGroup> current,
    required List<ContactGroup> incoming,
  }) {
    final names = {for (final group in current) group.name.trim().toLowerCase()};
    added = List<ContactGroup>.unmodifiable([
      for (final group in incoming)
        if (names.add(group.name.trim().toLowerCase())) group,
    ]);
    groups = List<ContactGroup>.unmodifiable([...current, ...added]);
    skipped = incoming.length - added.length;
  }

  final Object session;
  final String? expectedValue;
  late final List<ContactGroup> added;
  late final List<ContactGroup> groups;
  late final int skipped;
}

import '../models/community.dart';

List<Community> readBackupCommunities(List<Object?> rows) {
  const invalid = FormatException('Invalid backup community');
  return List<Community>.unmodifiable(rows.map((row) {
    if (row is! Map<String, Object?>) throw invalid;
    final hashtags = row['hashtag_channels'];
    if (hashtags != null &&
        (hashtags is! List<Object?> || hashtags.any((tag) => tag is! String))) {
      throw invalid;
    }
    try {
      final community = Community.fromJson(row);
      if (community.secret.length == 32 && community.id.trim().isNotEmpty) {
        return community;
      }
    } catch (_) {
      throw invalid;
    }
    throw invalid;
  }));
}

class BackupCommunitiesPreview {
  BackupCommunitiesPreview({
    required this.session,
    required this.expectedValue,
    required List<Community> current,
    required List<Community> incoming,
  }) {
    final ids = {for (final community in current) community.id};
    final sharedIds = {for (final community in current) community.communityId};
    final additions = <Community>[];
    for (final community in incoming) {
      final sharedId = community.communityId;
      if (!sharedIds.add(sharedId)) continue;

      var id = community.id;
      if (!ids.add(id)) {
        id = sharedId;
        for (var suffix = 1; !ids.add(id); suffix++) {
          id = '$sharedId-$suffix';
        }
      }
      additions.add(Community(
        id: id,
        name: community.name,
        secret: community.secret.asUnmodifiableView(),
        createdAt: community.createdAt,
        hashtagChannels: List.unmodifiable(community.hashtagChannels),
      ));
    }
    added = List.unmodifiable(additions);
    communities = List.unmodifiable([...current, ...added]);
    skipped = incoming.length - added.length;
  }

  final Object session;
  final String? expectedValue;
  late final List<Community> added;
  late final List<Community> communities;
  late final int skipped;
}

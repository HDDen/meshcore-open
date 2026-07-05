class MCOImagePackMetadata {
  final String name;
  final String id;
  final String version;
  final String? author;
  final String? authorUrl;
  final String? packUrl;
  final int? maxImageSize;
  final String folderName;

  const MCOImagePackMetadata({
    required this.name,
    required this.id,
    required this.version,
    required this.folderName,
    this.author,
    this.authorUrl,
    this.packUrl,
    this.maxImageSize,
  });

  String get groupId => 'pack:$folderName';

  String get groupTitle {
    final authorText = author?.trim();
    final details = authorText != null && authorText.isNotEmpty
        ? '$authorText, $version'
        : version;
    return '$name ($details)';
  }

  factory MCOImagePackMetadata.fromJson(
    Map<String, dynamic> json, {
    required String folderName,
  }) {
    final name = (json['name'] as String?)?.trim();
    final id = (json['id'] as String?)?.trim();
    final version = (json['ver'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      throw const FormatException('MCOimg pack name is missing');
    }
    if (id == null || id.isEmpty) {
      throw const FormatException('MCOimg pack id is missing');
    }
    if (version == null || version.isEmpty) {
      throw const FormatException('MCOimg pack version is missing');
    }

    final maxImageSize = json['maxImageSize'];
    return MCOImagePackMetadata(
      name: name,
      id: id,
      version: version,
      author: (json['author'] as String?)?.trim(),
      authorUrl: (json['authorUrl'] as String?)?.trim(),
      packUrl: (json['packUrl'] as String?)?.trim(),
      maxImageSize: maxImageSize is int && maxImageSize > 0
          ? maxImageSize
          : null,
      folderName: folderName,
    );
  }
}

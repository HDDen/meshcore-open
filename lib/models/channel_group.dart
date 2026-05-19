class ChannelGroup {
  final String name;
  final List<int> channelIndexes;
  final int sortOrder;

  const ChannelGroup({
    required this.name,
    required this.channelIndexes,
    this.sortOrder = 0,
  });

  ChannelGroup copyWith({
    String? name,
    List<int>? channelIndexes,
    int? sortOrder,
  }) {
    return ChannelGroup(
      name: name ?? this.name,
      channelIndexes: channelIndexes ?? List<int>.from(this.channelIndexes),
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'channels': channelIndexes, 'sort_order': sortOrder};
  }

  factory ChannelGroup.fromJson(Map<String, dynamic> json) {
    final channels =
        (json['channels'] as List?)
            ?.map((value) => int.tryParse(value.toString()))
            .whereType<int>()
            .toList() ??
        <int>[];
    return ChannelGroup(
      name: json['name'] as String? ?? '',
      channelIndexes: channels,
      sortOrder: int.tryParse(json['sort_order']?.toString() ?? '') ?? -1,
    );
  }
}

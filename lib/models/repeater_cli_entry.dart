/// Строка терминала хранится отдельно от mesh-сообщений и от других репитеров.
class RepeaterCliEntry {
  const RepeaterCliEntry({required this.id, required this.nodeKey,
    required this.repeaterKey, required this.nodeName, required this.repeaterName,
    required this.createdAt, required this.type, required this.text});

  final String id;
  final String nodeKey;
  final String repeaterKey;
  final String nodeName;
  final String repeaterName;
  final DateTime createdAt;
  final String type;
  final String text;

  Map<String, String> get transcript => {
    'type': type, 'text': text, 'timestamp': createdAt.toString(),
  };
}

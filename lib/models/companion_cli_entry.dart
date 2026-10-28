enum CompanionCliStatus { pending, replied, failed, disconnected }

class CompanionCliEntry {
  const CompanionCliEntry({required this.id, required this.nodeKey,
    required this.nodeName, required this.command, required this.createdAt,
    this.response, this.failure, this.status = CompanionCliStatus.pending});

  final String id;
  final String nodeKey;
  final String nodeName;
  final String command;
  final DateTime createdAt;
  final String? response;
  final String? failure;
  final CompanionCliStatus status;

  CompanionCliEntry finish(CompanionCliStatus status, {String? response, String? failure}) =>
      CompanionCliEntry(id: id, nodeKey: nodeKey, nodeName: nodeName, command: command,
        createdAt: createdAt, status: status, response: response, failure: failure);

}

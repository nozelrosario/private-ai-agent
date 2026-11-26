class RoutineLedgerEntry {
  final String id;
  final String routineId;
  final DateTime timestamp;
  final String targetAppPackage;
  final String senderIdentifier;
  final String messageSnippet;
  final String messageSnippetHash;
  final String agentReply;
  final String status; // 'sent', 'pending_approval', 'rejected', 'skipped'

  RoutineLedgerEntry({
    required this.id,
    required this.routineId,
    required this.timestamp,
    required this.targetAppPackage,
    required this.senderIdentifier,
    required this.messageSnippet,
    String? messageSnippetHash,
    required this.agentReply,
    this.status = 'sent',
  }) : messageSnippetHash = messageSnippetHash ??
            computeHash(senderIdentifier, messageSnippet);

  /// Self-contained deterministic 64-bit FNV-1a hash
  static String computeHash(String sender, String snippet) {
    final cleanSender = sender.trim().toLowerCase();
    final cleanSnippet = snippet.trim().toLowerCase();
    final input = '$cleanSender::$cleanSnippet';
    int hash = 0xcbf29ce4; // 32-bit FNV offset basis
    const prime = 16777619; // 32-bit FNV prime
    for (int i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * prime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'routine_id': routineId,
        'timestamp': timestamp.toIso8601String(),
        'target_app_package': targetAppPackage,
        'sender_identifier': senderIdentifier,
        'message_snippet': messageSnippet,
        'message_snippet_hash': messageSnippetHash,
        'agent_reply': agentReply,
        'status': status,
      };

  factory RoutineLedgerEntry.fromJson(Map<String, dynamic> json) =>
      RoutineLedgerEntry(
        id: json['id'] as String,
        routineId: json['routine_id'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        targetAppPackage: json['target_app_package'] as String? ?? '',
        senderIdentifier: json['sender_identifier'] as String? ?? '',
        messageSnippet: json['message_snippet'] as String? ?? '',
        messageSnippetHash: json['message_snippet_hash'] as String?,
        agentReply: json['agent_reply'] as String? ?? '',
        status: json['status'] as String? ?? 'sent',
      );
}

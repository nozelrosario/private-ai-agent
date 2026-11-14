import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/routine_ledger_entry.dart';

class RoutineLedgerService {
  static final RoutineLedgerService _instance =
      RoutineLedgerService._internal();
  factory RoutineLedgerService() => _instance;
  RoutineLedgerService._internal();

  final List<RoutineLedgerEntry> _entries = [];
  bool _isLoaded = false;
  final ValueNotifier<int> ledgerUpdateNotifier = ValueNotifier(0);

  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/routine_ledger.json');
  }

  Future<void> init() async {
    if (_isLoaded) return;
    try {
      final file = await _localFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content) as List;
          _entries.clear();
          _entries.addAll(
            decoded.map((item) =>
                RoutineLedgerEntry.fromJson(item as Map<String, dynamic>)),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading routine ledger: $e');
    }
    _isLoaded = true;
  }

  /// Checks if a message from this sender with this content has already been processed/replied
  /// within the deduplication window (defaults to 24 hours).
  bool hasRepliedTo({
    required String routineId,
    required String senderIdentifier,
    required String messageSnippet,
    Duration deduplicationWindow = const Duration(hours: 24),
  }) {
    final hash = RoutineLedgerEntry.computeHash(senderIdentifier, messageSnippet);
    final cutoff = DateTime.now().subtract(deduplicationWindow);

    return _entries.any((entry) =>
        entry.routineId == routineId &&
        entry.messageSnippetHash == hash &&
        entry.timestamp.isAfter(cutoff) &&
        entry.status != 'rejected');
  }

  /// Record a newly executed or pending reply
  Future<void> recordEntry({
    required String routineId,
    required String targetAppPackage,
    required String senderIdentifier,
    required String messageSnippet,
    required String agentReply,
    String status = 'sent',
  }) async {
    await init();
    final entry = RoutineLedgerEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      routineId: routineId,
      timestamp: DateTime.now(),
      targetAppPackage: targetAppPackage,
      senderIdentifier: senderIdentifier,
      messageSnippet: messageSnippet,
      agentReply: agentReply,
      status: status,
    );

    _entries.insert(0, entry);

    // Keep ledger bounded to last 500 entries to prevent disk/memory bloat
    if (_entries.length > 500) {
      _entries.removeRange(500, _entries.length);
    }

    await _saveAll();
    ledgerUpdateNotifier.value++;
  }

  /// Update the status of an existing entry (e.g. from pending_approval to sent or rejected)
  Future<void> updateEntryStatus(String entryId, String newStatus) async {
    await init();
    final idx = _entries.indexWhere((e) => e.id == entryId);
    if (idx != -1) {
      final old = _entries[idx];
      _entries[idx] = RoutineLedgerEntry(
        id: old.id,
        routineId: old.routineId,
        timestamp: old.timestamp,
        targetAppPackage: old.targetAppPackage,
        senderIdentifier: old.senderIdentifier,
        messageSnippet: old.messageSnippet,
        messageSnippetHash: old.messageSnippetHash,
        agentReply: old.agentReply,
        status: newStatus,
      );
      await _saveAll();
      ledgerUpdateNotifier.value++;
    }
  }

  List<RoutineLedgerEntry> getRecentEntries({
    String? routineId,
    int limit = 50,
  }) {
    var filtered = _entries.asMap().values;
    if (routineId != null) {
      filtered = filtered.where((e) => e.routineId == routineId);
    }
    return filtered.take(limit).toList();
  }

  Future<void> clearLedger({String? routineId}) async {
    await init();
    if (routineId != null) {
      _entries.removeWhere((e) => e.routineId == routineId);
    } else {
      _entries.clear();
    }
    await _saveAll();
    ledgerUpdateNotifier.value++;
  }

  Future<void> _saveAll() async {
    try {
      final file = await _localFile;
      final jsonStr = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (e) {
      debugPrint('Error saving routine ledger: $e');
    }
  }
}

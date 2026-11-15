import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/task_history_logger.dart';

class TaskHistoryScreen extends StatefulWidget {
  const TaskHistoryScreen({super.key});

  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

class _TaskHistoryScreenState extends State<TaskHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _analytics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final history = await TaskHistoryLogger.readHistory();
    final analytics = await TaskHistoryLogger.getAnalytics();
    setState(() {
      _history = history;
      _analytics = analytics;
      _isLoading = false;
    });
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Task History'),
        content: const Text('Are you sure you want to delete all task history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TaskHistoryLogger.clearHistory();
      _loadHistory();
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Success':
        return Colors.green;
      case 'Failed':
        return Colors.red;
      case 'Cancelled':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Success':
        return Icons.check_circle;
      case 'Failed':
        return Icons.cancel;
      case 'Cancelled':
        return Icons.stop_circle;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Task History (${_history.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _history.isEmpty ? null : _clearHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(child: Text('No task history found.'))
              : Column(
                  children: [
                    if (_analytics != null && _analytics!['totalTasks'] > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatColumn('Total', _analytics!['totalTasks'].toString(), isDark: Theme.of(context).brightness == Brightness.dark),
                                _buildStatColumn('Success', _analytics!['successCount'].toString(), color: Colors.green, isDark: Theme.of(context).brightness == Brightness.dark),
                                _buildStatColumn('Failed', _analytics!['failedCount'].toString(), color: Colors.red, isDark: Theme.of(context).brightness == Brightness.dark),
                                _buildStatColumn('Rate', '${(_analytics!['successRate'] * 100).toStringAsFixed(1)}%', isDark: Theme.of(context).brightness == Brightness.dark),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _history.length,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final task = _history[index];
                          final date = DateTime.tryParse(task['timestamp'] ?? '');
                          final dateStr = date != null
                              ? DateFormat('MMM d, y h:mm a').format(date)
                              : 'Unknown Date';
                          final status = task['status'] as String? ?? 'Unknown';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: ExpansionTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(status).withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _getStatusIcon(status),
                                  color: _getStatusColor(status),
                                  size: 24,
                                ),
                              ),
                              title: Text(
                                task['goal'] ?? 'Unknown Goal',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(
                                  children: [
                                    Text(dateStr, style: const TextStyle(fontSize: 12)),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${task['total_tokens'] ?? 0} tokens',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: _getStatusColor(status).withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: _getStatusColor(status).withOpacity(0.3)),
                                            ),
                                            child: Text(
                                              status.toUpperCase(),
                                              style: TextStyle(
                                                color: _getStatusColor(status),
                                                fontWeight: FontWeight.w800,
                                                fontSize: 10,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            'Steps taken: ${task['steps_taken'] ?? 0}',
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      Row(
                                        children: [
                                          Text(
                                            'Execution Trace (${((task['trace'] as List<dynamic>?) ?? []).length}):',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          const Spacer(),
                                          TextButton.icon(
                                            style: TextButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            icon: const Icon(Icons.copy_rounded, size: 13),
                                            label: const Text('Copy Trace', style: TextStyle(fontSize: 11)),
                                            onPressed: () {
                                              final traceJson = const JsonEncoder.withIndent('  ').convert(task['trace'] ?? []);
                                              Clipboard.setData(ClipboardData(text: traceJson));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Execution trace copied to clipboard!')),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      ...((task['trace'] as List<dynamic>?) ?? []).map((t) => _buildTraceItem(context, t)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildTraceItem(BuildContext context, dynamic item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (item is Map<String, dynamic> && item.containsKey('step')) {
      final stepNum = item['step'];
      final action = item['action'] as String? ?? 'action';
      final reasoning = (item['reasoning'] ?? item['intent'] ?? '') as String;
      final params = (item['params'] as Map<String, dynamic>?) ?? {};
      final result = (item['result'] ?? '') as String;
      final status = (item['status'] ?? 'success') as String;
      final isSuccess = status == 'success' || status == 'approved';

      final Color statusColor = isSuccess ? Colors.green : Colors.red;
      final IconData actionIcon = _getActionIcon(action);

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSuccess
                ? Colors.green.withOpacity(0.2)
                : Colors.red.withOpacity(0.25),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'STEP $stepNum',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(actionIcon, size: 12, color: isDark ? Colors.white70 : Colors.black87),
                        const SizedBox(width: 4),
                        Text(
                          action.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSuccess ? Icons.check_circle_outline : Icons.cancel_outlined,
                          size: 11,
                          color: statusColor,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (reasoning.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💡 ', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Text(
                          reasoning,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (params.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'Params: ${_formatParams(params)}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ),
              ],
              if (result.isNotEmpty) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'Outcome: $result',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final text = item is Map<String, dynamic> ? (item['info'] ?? jsonEncode(item)) : item.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'click_text':
      case 'click_at':
        return Icons.touch_app;
      case 'type_text':
        return Icons.keyboard;
      case 'press_enter':
        return Icons.keyboard_return;
      case 'scroll':
      case 'swipe':
        return Icons.swipe;
      case 'open_app':
        return Icons.open_in_new;
      case 'press_back':
        return Icons.arrow_back;
      case 'press_home':
        return Icons.home;
      case 'evaluator_check':
        return Icons.fact_check_outlined;
      case 'supervised_checkpoint':
        return Icons.security;
      case 'done':
        return Icons.check_circle_outline;
      default:
        return Icons.play_arrow;
    }
  }

  String _formatParams(Map<String, dynamic> params) {
    if (params.containsKey('text')) return 'text: "${params['text']}"';
    if (params.containsKey('app_name')) return 'app: "${params['app_name']}"';
    if (params.containsKey('direction')) return 'direction: ${params['direction']}';
    return params.toString();
  }

  Widget _buildStatColumn(String label, String value, {Color? color, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color ?? (isDark ? Colors.white : const Color(0xFF1E293B)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

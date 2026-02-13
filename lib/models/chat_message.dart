class ChatMessage {
  final String id;
  final String role;
  final String content;
  final List<ToolCallInfo>? toolCalls;
  final DateTime timestamp;
  final bool isStreaming;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.toolCalls,
    DateTime? timestamp,
    this.isStreaming = false,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? content,
    List<ToolCallInfo>? toolCalls,
    bool? isStreaming,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      toolCalls: toolCalls ?? this.toolCalls,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  Map<String, dynamic> toApiFormat() {
    return {
      'role': role,
      'content': content.isEmpty ? null : content,
    };
  }
}

class ToolCallInfo {
  final String id;
  final String name;
  final String arguments;
  final Map<String, dynamic>? result;
  final ToolCallStatus status;

  ToolCallInfo({
    required this.id,
    required this.name,
    this.arguments = '',
    this.result,
    this.status = ToolCallStatus.pending,
  });

  ToolCallInfo copyWith({
    String? name,
    String? arguments,
    Map<String, dynamic>? result,
    ToolCallStatus? status,
  }) {
    return ToolCallInfo(
      id: id,
      name: name ?? this.name,
      arguments: arguments ?? this.arguments,
      result: result ?? this.result,
      status: status ?? this.status,
    );
  }

  String get displayName {
    switch (name) {
      case 'get_tasks':
        return 'Fetching tasks';
      case 'add_task':
        return 'Adding task';
      case 'update_task':
        return 'Updating task';
      case 'delete_task':
        return 'Deleting task';
      case 'toggle_task':
        return 'Updating status';
      case 'clear_all_tasks':
        return 'Clearing all tasks';
      default:
        return name;
    }
  }

  String get resultSummary {
    if (result == null) return '';
    final success = result!['success'] == true;
    if (!success) {
      return result!['error'] ?? 'Failed';
    }
    switch (name) {
      case 'get_tasks':
        final count = result!['count'] ?? 0;
        return 'Found $count task${count == 1 ? '' : 's'}';
      case 'add_task':
        final task = result!['task'];
        return 'Added "${task?['title'] ?? 'task'}"';
      case 'update_task':
        final task = result!['task'];
        return 'Updated "${task?['title'] ?? 'task'}"';
      case 'delete_task':
        final task = result!['deleted_task'];
        return 'Deleted "${task?['title'] ?? 'task'}"';
      case 'toggle_task':
        final task = result!['task'];
        final completed = task?['completed'] == true;
        return '${completed ? 'Completed' : 'Uncompleted'} "${task?['title'] ?? 'task'}"';
      case 'clear_all_tasks':
        return 'Cleared ${result!['deleted_count'] ?? 0} tasks';
      default:
        return 'Done';
    }
  }
}

enum ToolCallStatus {
  pending,
  executing,
  completed,
  error,
}

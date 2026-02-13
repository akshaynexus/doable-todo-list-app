import 'dart:convert';
import '../data/task_dao.dart';
import '../models/task_entity.dart';
import '../repositories/task_repository.dart';

class ToolCallingService {
  static final TaskRepository _taskRepository = TaskRepository();

  static List<Map<String, dynamic>> getToolDefinitions() {
    return [
      {
        'type': 'function',
        'function': {
          'name': 'get_tasks',
          'description': 'Get all todo tasks from the list. Returns all tasks with their details including id, title, description, time, date, completion status, and repeat rules.',
          'parameters': {
            'type': 'object',
            'properties': {},
            'required': [],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'add_task',
          'description': 'Add a new task to the todo list. Requires a title. Optionally include description, time, date, notification preference, and repeat rule.',
          'parameters': {
            'type': 'object',
            'properties': {
              'title': {
                'type': 'string',
                'description': 'The title/name of the task (required)',
              },
              'description': {
                'type': 'string',
                'description': 'Optional description or notes for the task',
              },
              'time': {
                'type': 'string',
                'description': 'Time for the task in format like "11:30 AM" or "3:30 PM"',
              },
              'date': {
                'type': 'string',
                'description': 'Date for the task in format like "26/11/24" or "01/12/24"',
              },
              'has_notification': {
                'type': 'boolean',
                'description': 'Whether to enable notification for this task',
              },
              'repeat_rule': {
                'type': 'string',
                'description': 'How often to repeat the task',
                'enum': ['Daily', 'Weekly', 'Monthly', 'Yearly', null],
              },
            },
            'required': ['title'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'update_task',
          'description': 'Update an existing task in the todo list. Provide the task id and the fields you want to update.',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'integer',
                'description': 'The ID of the task to update (required)',
              },
              'title': {
                'type': 'string',
                'description': 'New title for the task',
              },
              'description': {
                'type': 'string',
                'description': 'New description for the task',
              },
              'time': {
                'type': 'string',
                'description': 'New time for the task in format like "11:30 AM"',
              },
              'date': {
                'type': 'string',
                'description': 'New date for the task in format like "26/11/24"',
              },
              'has_notification': {
                'type': 'boolean',
                'description': 'Whether to enable notification for this task',
              },
              'repeat_rule': {
                'type': 'string',
                'description': 'How often to repeat the task',
                'enum': ['Daily', 'Weekly', 'Monthly', 'Yearly', null],
              },
            },
            'required': ['id'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'delete_task',
          'description': 'Delete a task from the todo list by its ID.',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'integer',
                'description': 'The ID of the task to delete (required)',
              },
            },
            'required': ['id'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'toggle_task',
          'description': 'Toggle the completion status of a task (mark as completed or incomplete).',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'integer',
                'description': 'The ID of the task to toggle (required)',
              },
              'completed': {
                'type': 'boolean',
                'description': 'Set to true to mark as completed, false to mark as incomplete (required)',
              },
            },
            'required': ['id', 'completed'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'clear_all_tasks',
          'description': 'Delete all tasks from the todo list. Use with caution as this cannot be undone.',
          'parameters': {
            'type': 'object',
            'properties': {},
            'required': [],
          },
        },
      },
    ];
  }

  static Future<Map<String, dynamic>> executeToolCall({
    required String name,
    Map<String, dynamic>? arguments,
  }) async {
    try {
      switch (name) {
        case 'get_tasks':
          return await _getTasks();
        case 'add_task':
          return await _addTask(arguments ?? {});
        case 'update_task':
          return await _updateTask(arguments ?? {});
        case 'delete_task':
          return await _deleteTask(arguments ?? {});
        case 'toggle_task':
          return await _toggleTask(arguments ?? {});
        case 'clear_all_tasks':
          return await _clearAllTasks();
        default:
          return {'success': false, 'error': 'Unknown tool: $name'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _getTasks() async {
    final tasks = await _taskRepository.fetchAll();
    return {
      'success': true,
      'tasks': tasks.map((t) => _taskToMap(t)).toList(),
      'count': tasks.length,
    };
  }

  static Future<Map<String, dynamic>> _addTask(Map<String, dynamic> args) async {
    if (args['title'] == null || (args['title'] as String).isEmpty) {
      return {'success': false, 'error': 'Title is required'};
    }

    final task = TaskEntity(
      title: args['title'] as String,
      description: args['description'] as String?,
      time: args['time'] as String?,
      date: args['date'] as String?,
      hasNotification: args['has_notification'] as bool? ?? false,
      repeatRule: args['repeat_rule'] as String?,
      completed: false,
      createdAt: DateTime.now().toIso8601String(),
    );

    final id = await _taskRepository.add(task);
    task.id = id;

    return {
      'success': true,
      'message': 'Task added successfully',
      'task': _taskToMap(task),
    };
  }

  static Future<Map<String, dynamic>> _updateTask(Map<String, dynamic> args) async {
    final id = args['id'] as int?;
    if (id == null) {
      return {'success': false, 'error': 'Task ID is required'};
    }

    final existingTask = await TaskDao.getById(id);
    if (existingTask == null) {
      return {'success': false, 'error': 'Task not found with ID: $id'};
    }

    if (args['title'] != null) existingTask.title = args['title'] as String;
    if (args['description'] != null) existingTask.description = args['description'] as String?;
    if (args['time'] != null) existingTask.time = args['time'] as String?;
    if (args['date'] != null) existingTask.date = args['date'] as String?;
    if (args['has_notification'] != null) existingTask.hasNotification = args['has_notification'] as bool;
    if (args['repeat_rule'] != null) existingTask.repeatRule = args['repeat_rule'] as String?;

    await _taskRepository.update(existingTask);

    return {
      'success': true,
      'message': 'Task updated successfully',
      'task': _taskToMap(existingTask),
    };
  }

  static Future<Map<String, dynamic>> _deleteTask(Map<String, dynamic> args) async {
    final id = args['id'] as int?;
    if (id == null) {
      return {'success': false, 'error': 'Task ID is required'};
    }

    final existingTask = await TaskDao.getById(id);
    if (existingTask == null) {
      return {'success': false, 'error': 'Task not found with ID: $id'};
    }

    await _taskRepository.delete(id);

    return {
      'success': true,
      'message': 'Task deleted successfully',
      'deleted_task': _taskToMap(existingTask),
    };
  }

  static Future<Map<String, dynamic>> _toggleTask(Map<String, dynamic> args) async {
    final id = args['id'] as int?;
    final completed = args['completed'] as bool?;

    if (id == null) {
      return {'success': false, 'error': 'Task ID is required'};
    }
    if (completed == null) {
      return {'success': false, 'error': 'Completed status is required'};
    }

    final existingTask = await TaskDao.getById(id);
    if (existingTask == null) {
      return {'success': false, 'error': 'Task not found with ID: $id'};
    }

    await _taskRepository.toggle(id, completed);
    existingTask.completed = completed;

    return {
      'success': true,
      'message': 'Task ${completed ? 'completed' : 'marked as incomplete'}',
      'task': _taskToMap(existingTask),
    };
  }

  static Future<Map<String, dynamic>> _clearAllTasks() async {
    final count = await _taskRepository.clearAll();
    return {
      'success': true,
      'message': 'All tasks cleared',
      'deleted_count': count,
    };
  }

  static Map<String, dynamic> _taskToMap(TaskEntity task) {
    return {
      'id': task.id,
      'title': task.title,
      'description': task.description,
      'time': task.time,
      'date': task.date,
      'has_notification': task.hasNotification,
      'repeat_rule': task.repeatRule,
      'completed': task.completed,
      'created_at': task.createdAt,
      'updated_at': task.updatedAt,
    };
  }

  static String getToolDefinitionsJson() {
    final tools = getToolDefinitions();
    final buffer = StringBuffer();
    for (final tool in tools) {
      final toolMap = Map<String, dynamic>.from(tool as Map);
      final func = Map<String, dynamic>.from(toolMap['function'] as Map);
      final name = func['name'] as String? ?? '';
      final description = func['description'] as String? ?? '';
      final params = Map<String, dynamic>.from(func['parameters'] as Map? ?? {});
      final required = (params['required'] as List?) ?? [];
      final properties = Map<String, dynamic>.from(params['properties'] as Map? ?? {});

      buffer.writeln('- $name: $description');
      if (properties.isNotEmpty) {
        buffer.writeln('  Parameters:');
        for (final entry in properties.entries) {
          final paramName = entry.key;
          final paramInfo = Map<String, dynamic>.from(entry.value as Map);
          final paramDesc = paramInfo['description'] ?? '';
          final paramType = paramInfo['type'] ?? 'any';
          final isRequired = required.contains(paramName);
          buffer.writeln('    - $paramName ($paramType${isRequired ? ', required' : ', optional'}): $paramDesc');
        }
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  static String formatToolResultForAI(Map<String, dynamic> result) {
    return jsonEncode(result);
  }
}

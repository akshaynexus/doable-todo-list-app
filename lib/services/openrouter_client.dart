import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'tool_calling_service.dart';

class OpenRouterClient {
  static const String _baseUrl = 'https://openrouter.ai/api/v1';
  static const String _modelsUrl = 'https://openrouter.ai/api/v1/models';
  static const String defaultModel = 'qwen/qwen3-coder-next';

  static String _buildSystemPrompt() {
    final toolDefs = ToolCallingService.getToolDefinitionsJson();
    return '''You are a helpful todo list assistant for a task management app. Help users manage their tasks through natural conversation.

You have access to the following tools:

$toolDefs

INSTRUCTIONS:
1. Use tools proactively - don't just describe what you'll do, actually call the tools
2. When adding tasks, extract title, time, and date from the user's message
3. Time format: "11:30 AM" or "5:00 PM"  
4. Date format: "26/11/24" (DD/MM/YY)
5. After tool calls, summarize what happened in a friendly, brief way
6. Keep responses short and actionable''';
  }

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('openrouter_api_key');
  }

  static Future<void> setApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('openrouter_api_key', apiKey);
  }

  static Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('openrouter_api_key');
  }

  static Future<String?> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('openrouter_model') ?? defaultModel;
  }

  static Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('openrouter_model', model);
  }

  static Future<List<OpenRouterModel>> fetchModels() async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return [];
    }

    try {
      final client = http.Client();
      final response = await client.get(
        Uri.parse(_modelsUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'HTTP-Referer': 'https://doable-todo.app',
          'X-Title': 'Doable Todo List',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return [];
      }

      final json = jsonDecode(response.body);
      final data = json['data'] as List?;
      if (data == null) return [];

      return data.map((m) => OpenRouterModel.fromJson(m)).toList()
        ..sort((a, b) {
          final aTop = a.top ? 0 : 1;
          final bTop = b.top ? 0 : 1;
          if (aTop != bTop) return aTop.compareTo(bTop);
          return a.name.compareTo(b.name);
        });
    } catch (e) {
      return [];
    }
  }

  static Stream<ChatStreamEvent> chat({
    required List<Map<String, dynamic>> conversationHistory,
    String? model,
    String? apiKey,
  }) async* {
    final key = apiKey ?? await getApiKey();
    if (key == null || key.isEmpty) {
      yield ChatStreamEvent(type: ChatStreamEventType.error, error: 'API key not set. Tap the key icon to set it.');
      return;
    }

    final today = DateTime.now();
    final dateStr = '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year.toString().substring(2)}';

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': '${_buildSystemPrompt()}\n\nToday\'s date: $dateStr'},
      ...conversationHistory,
    ];

    final selectedModel = model ?? (await getModel()) ?? defaultModel;
    yield* _makeRequest(messages, selectedModel, key);
  }

  static Stream<ChatStreamEvent> _makeRequest(
    List<Map<String, dynamic>> messages,
    String model,
    String apiKey,
  ) async* {
    final client = http.Client();

    try {
      final response = await client.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://doable-todo.app',
          'X-Title': 'Doable Todo List',
        },
        body: jsonEncode({
          'model': model,
          'messages': messages,
          'tools': ToolCallingService.getToolDefinitions(),
        }),
      );

      if (response.statusCode != 200) {
        String errorMsg = 'API error (${response.statusCode})';
        try {
          final errorJson = jsonDecode(response.body);
          if (errorJson['error'] != null) {
            errorMsg = errorJson['error']['message'] ?? errorMsg;
          }
        } catch (_) {}
        yield ChatStreamEvent(type: ChatStreamEventType.error, error: errorMsg);
        return;
      }

      final json = jsonDecode(response.body);
      print('Response JSON: $json');
      final choice = json['choices']?[0];
      if (choice == null) {
        yield ChatStreamEvent(type: ChatStreamEventType.error, error: 'No response from API');
        return;
      }

      final assistantMessage = choice['message'] as Map<String, dynamic>?;
      if (assistantMessage == null) {
        yield ChatStreamEvent(type: ChatStreamEventType.error, error: 'Invalid response format');
        return;
      }

      final content = assistantMessage['content'] as String?;
      if (content != null && content.isNotEmpty) {
        yield ChatStreamEvent(type: ChatStreamEventType.content, content: content);
      }

      final toolCalls = assistantMessage['tool_calls'] as List?;
      print('Tool calls: $toolCalls');
      if (toolCalls != null && toolCalls.isNotEmpty) {
        for (final tc in toolCalls) {
          final func = tc['function'] as Map<String, dynamic>?;
          if (func == null) continue;

          final toolName = func['name'] as String? ?? '';
          final argsStr = func['arguments'] as String? ?? '{}';

          if (toolName.isEmpty) continue;

          print('Tool name: $toolName, args: $argsStr');
          yield ChatStreamEvent(
            type: ChatStreamEventType.toolStart,
            toolName: toolName,
          );

          yield ChatStreamEvent(
            type: ChatStreamEventType.toolExecuting,
            toolName: toolName,
            toolArgs: argsStr,
          );

          Map<String, dynamic> args = {};
          try {
            args = jsonDecode(argsStr) as Map<String, dynamic>;
          } catch (_) {}

          print('Executing tool: $toolName with args: $args');
          final result = await ToolCallingService.executeToolCall(
            name: toolName,
            arguments: args,
          );
          print('Tool result: $result');

          yield ChatStreamEvent(
            type: ChatStreamEventType.toolResult,
            toolName: toolName,
            toolResult: result,
          );

          final toolCallId = tc['id'] ?? 'call_${DateTime.now().millisecondsSinceEpoch}';

          final newMessages = List<Map<String, dynamic>>.from(messages);
          newMessages.add({
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {
                'id': toolCallId,
                'type': 'function',
                'function': {
                  'name': toolName,
                  'arguments': argsStr,
                },
              },
            ],
          });
          newMessages.add({
            'role': 'tool',
            'tool_call_id': toolCallId,
            'content': jsonEncode(result),
          });

          yield* _makeRequest(newMessages, model, apiKey);
          return;
        }
      }

      yield ChatStreamEvent(type: ChatStreamEventType.done);
    } catch (e) {
      yield ChatStreamEvent(type: ChatStreamEventType.error, error: e.toString());
    } finally {
      client.close();
    }
  }
}

class OpenRouterModel {
  final String id;
  final String name;
  final String? description;
  final bool top;
  final int? contextLength;
  final String? pricing;

  OpenRouterModel({
    required this.id,
    required this.name,
    this.description,
    this.top = false,
    this.contextLength,
    this.pricing,
  });

  factory OpenRouterModel.fromJson(Map<String, dynamic> json) {
    return OpenRouterModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['id'] as String? ?? 'Unknown',
      description: json['description'] as String?,
      top: json['top'] as bool? ?? false,
      contextLength: json['context_length'] as int?,
      pricing: json['pricing'] != null 
          ? _formatPricing(json['pricing'] as Map<String, dynamic>)
          : null,
    );
  }

  static String? _formatPricing(Map<String, dynamic>? pricing) {
    if (pricing == null) return null;
    final prompt = pricing['prompt'] as num?;
    final completion = pricing['completion'] as num?;
    if (prompt == null && completion == null) return null;
    
    final parts = <String>[];
    if (prompt != null) {
      parts.add('\$${(prompt * 1000000).toStringAsFixed(2)}/M prompt');
    }
    if (completion != null) {
      parts.add('\$${(completion * 1000000).toStringAsFixed(2)}/M completion');
    }
    return parts.join(', ');
  }

  String get displayName {
    if (name.length > 30) {
      return '${name.substring(0, 27)}...';
    }
    return name;
  }
}

enum ChatStreamEventType {
  content,
  toolStart,
  toolExecuting,
  toolResult,
  done,
  error,
}

class ChatStreamEvent {
  final ChatStreamEventType type;
  final String? content;
  final String? toolName;
  final String? toolArgs;
  final Map<String, dynamic>? toolResult;
  final String? error;

  ChatStreamEvent({
    required this.type,
    this.content,
    this.toolName,
    this.toolArgs,
    this.toolResult,
    this.error,
  });

  @override
  String toString() => 'ChatStreamEvent(type: $type, content: $content, toolName: $toolName)';
}

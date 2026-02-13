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

IMPORTANT - TASK ADDING RULES:
1. When adding tasks, you MUST ask for clarification if the user doesn't provide BOTH time AND date
2. If the user says "remind me to buy milk" - respond with "What time should I remind you?" or "What date?" 
3. Only call add_task when you have ALL of: title, time (e.g., "11:30 AM"), AND date (e.g., "26/11/24")
4. Ask follow-up questions like: "What time?" or "What date?" to get missing info
5. Time format: "11:30 AM" or "5:00 PM"  
6. Date format: "26/11/24" (DD/MM/YY)
7. After successfully adding a task, summarize what happened
8. Keep responses short and actionable''';
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

  static Future<({List<OpenRouterModel> models, String? error})> fetchModels() async {
    final apiKey = await getApiKey();
    print('Fetch models - API key: ${apiKey?.substring(0, 10)}...');
    if (apiKey == null || apiKey.isEmpty) {
      print('No API key');
      return (models: <OpenRouterModel>[], error: 'API key not set');
    }

    try {
      final client = http.Client();
      print('Making request to $_modelsUrl');
      final response = await client.get(
        Uri.parse(_modelsUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'HTTP-Referer': 'https://doable-todo.app',
          'X-Title': 'Doable Todo List',
        },
      ).timeout(const Duration(seconds: 15));

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body.substring(0, 500)}');

      if (response.statusCode != 200) {
        print('Error: ${response.statusCode}');
        String errorMsg = 'Failed to fetch models (${response.statusCode})';
        try {
          final errorJson = jsonDecode(response.body);
          if (errorJson['error'] != null) {
            errorMsg = errorJson['error']['message'] ?? errorMsg;
          }
        } catch (_) {}
        return (models: <OpenRouterModel>[], error: errorMsg);
      }

      final json = jsonDecode(response.body);
      final data = json['data'] as List?;
      if (data == null) {
        print('No data field');
        return (models: <OpenRouterModel>[], error: 'Invalid response format');
      }

      print('Found ${data.length} models');
      final models = data.map((m) => OpenRouterModel.fromJson(m)).toList()
        ..sort((a, b) {
          final aTop = a.top ? 0 : 1;
          final bTop = b.top ? 0 : 1;
          if (aTop != bTop) return aTop.compareTo(bTop);
          return a.name.compareTo(b.name);
        });
      return (models: models, error: null);
    } catch (e) {
      print('Exception: $e');
      return (models: <OpenRouterModel>[], error: e.toString());
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
  final double? pricingNumeric;
  final String? architecture;
  final String? creator;
  final bool supportsToolCalls;

  OpenRouterModel({
    required this.id,
    required this.name,
    this.description,
    this.top = false,
    this.contextLength,
    this.pricing,
    this.pricingNumeric,
    this.architecture,
    this.creator,
    this.supportsToolCalls = false,
  });

  String get provider {
    final lowerId = id.toLowerCase();
    if (lowerId.contains('google') || lowerId.contains('gemini') || lowerId.contains('gemma')) {
      return 'Google';
    } else if (lowerId.contains('anthropic') || lowerId.contains('claude')) {
      return 'Anthropic';
    } else if (lowerId.contains('openai') || lowerId.contains('gpt')) {
      return 'OpenAI';
    } else if (lowerId.contains('qwen')) {
      return 'Qwen';
    } else if (lowerId.contains('deepseek')) {
      return 'DeepSeek';
    } else if (lowerId.contains('meta') || lowerId.contains('llama')) {
      return 'Meta';
    } else if (lowerId.contains('mistral')) {
      return 'Mistral';
    } else if (lowerId.contains('nvidia') || lowerId.contains('nemotron')) {
      return 'NVIDIA';
    } else if (lowerId.contains('xai') || lowerId.contains('grok')) {
      return 'xAI';
    } else if (lowerId.contains('perplexity')) {
      return 'Perplexity';
    } else if (lowerId.contains('amazon') || lowerId.contains('claude') == false && lowerId.contains('nova')) {
      return 'Amazon';
    }
    return 'Other';
  }

  bool get isFree {
    if (pricing == null) return false;
    return pricing!.toLowerCase().contains('free') || pricing == '\$0';
  }

  bool get isPaid {
    return !isFree;
  }

  factory OpenRouterModel.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final lowerId = id.toLowerCase();
    
    String? creator;
    if (lowerId.contains('google') || lowerId.contains('gemini') || lowerId.contains('gemma')) {
      creator = 'Google';
    } else if (lowerId.contains('anthropic') || lowerId.contains('claude')) {
      creator = 'Anthropic';
    } else if (lowerId.contains('openai') || lowerId.contains('gpt')) {
      creator = 'OpenAI';
    } else if (lowerId.contains('qwen')) {
      creator = 'Qwen';
    } else if (lowerId.contains('deepseek')) {
      creator = 'DeepSeek';
    } else if (lowerId.contains('meta') || lowerId.contains('llama')) {
      creator = 'Meta';
    } else if (lowerId.contains('mistral')) {
      creator = 'Mistral';
    } else if (lowerId.contains('nvidia') || lowerId.contains('nemotron')) {
      creator = 'NVIDIA';
    } else if (lowerId.contains('xai') || lowerId.contains('grok')) {
      creator = 'xAI';
    } else if (lowerId.contains('perplexity')) {
      creator = 'Perplexity';
    } else if (lowerId.contains('amazon') || lowerId.contains('nova')) {
      creator = 'Amazon';
    }

    final pricingData = json['pricing'];
    final pricingMap = pricingData is Map ? Map<String, dynamic>.from(pricingData as Map) : null;
    final pricingStr = pricingMap != null ? _formatPricing(pricingMap) : null;
    final pricingNum = pricingMap != null ? _parsePricingNumeric(pricingMap) : null;

    bool supportsToolCalls = false;
    final supportedParams = json['supported_parameters'];
    if (supportedParams is List) {
      supportsToolCalls = supportedParams.any((p) => p.toString().toLowerCase() == 'tools');
    }

    return OpenRouterModel(
      id: id,
      name: json['name']?.toString() ?? id,
      description: json['description']?.toString(),
      top: json['top'] == true,
      contextLength: json['context_length'] is int ? json['context_length'] as int : int.tryParse(json['context_length']?.toString() ?? ''),
      pricing: pricingStr,
      pricingNumeric: pricingNum,
      architecture: json['architecture']?.toString(),
      creator: creator,
      supportsToolCalls: supportsToolCalls,
    );
  }

  static String? _formatPricing(Map<String, dynamic>? pricing) {
    if (pricing == null || pricing.isEmpty) return null;
    
    final prompt = _parseNumeric(pricing['prompt']);
    final completion = _parseNumeric(pricing['completion']);
    final image = _parseNumeric(pricing['image']);
    
    if (prompt == null && completion == null && image == null) return null;
    
    final parts = <String>[];
    if (prompt != null && prompt > 0) {
      parts.add('\$${(prompt * 1000000).toStringAsFixed(2)}/M');
    }
    if (completion != null && completion > 0) {
      parts.add('\$${(completion * 1000000).toStringAsFixed(2)}/M');
    }
    if (parts.isEmpty) return 'Free';
    return parts.join(' + ');
  }

  static double? _parseNumeric(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static double? _parsePricingNumeric(Map<String, dynamic> pricing) {
    final prompt = _parseNumeric(pricing['prompt']);
    final completion = _parseNumeric(pricing['completion']);
    if (prompt == null && completion == null) return null;
    return (prompt ?? 0) + (completion ?? 0);
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

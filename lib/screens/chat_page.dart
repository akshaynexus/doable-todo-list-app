import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/openrouter_client.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final List<ChatMessage> _messages = [];
  final List<Map<String, dynamic>> _conversationHistory = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = false;
  bool _hasApiKey = false;
  int _toolCallIdCounter = 0;
  String? _currentAssistantId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkApiKey();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkApiKey();
    }
  }

  Future<void> _checkApiKey() async {
    final key = await OpenRouterClient.getApiKey();
    setState(() {
      _hasApiKey = key != null && key.isNotEmpty;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;

    _inputController.clear();
    _focusNode.unfocus();

    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: text,
    );

    setState(() {
      _messages.add(userMessage);
      _conversationHistory.add({'role': 'user', 'content': text});
      _isLoading = true;
    });
    _scrollToBottom();

    final assistantId = '${DateTime.now().millisecondsSinceEpoch}_assistant';
    _currentAssistantId = assistantId;

    final assistantMessage = ChatMessage(
      id: assistantId,
      role: 'assistant',
      content: '',
      isStreaming: true,
    );

    setState(() {
      _messages.add(assistantMessage);
    });
    _scrollToBottom();

    try {
      print('Starting chat request...');
      await for (final event in OpenRouterClient.chat(conversationHistory: _conversationHistory)) {
        print('Got event: ${event.type}');
        if (!mounted) return;

        if (_currentAssistantId == null) continue;

        setState(() {
          final idx = _messages.indexWhere((m) => m.id == _currentAssistantId);
          if (idx == -1) {
            print('Message not found for id: $_currentAssistantId');
            return;
          }

          switch (event.type) {
            case ChatStreamEventType.content:
              if (event.content != null) {
                final current = _messages[idx];
                _messages[idx] = current.copyWith(
                  content: current.content + event.content!,
                );
              }
              _scrollToBottom();
              break;

            case ChatStreamEventType.toolStart:
              final toolCall = ToolCallInfo(
                id: 'tc_${_toolCallIdCounter++}',
                name: event.toolName ?? 'unknown',
                status: ToolCallStatus.pending,
              );
              final current = _messages[idx];
              final existing = current.toolCalls ?? [];
              _messages[idx] = current.copyWith(
                toolCalls: [...existing, toolCall],
              );
              _scrollToBottom();
              break;

            case ChatStreamEventType.toolExecuting:
              final current = _messages[idx];
              if (current.toolCalls != null && current.toolCalls!.isNotEmpty) {
                final toolCalls = List<ToolCallInfo>.from(current.toolCalls!);
                final lastIdx = toolCalls.length - 1;
                if (lastIdx >= 0) {
                  toolCalls[lastIdx] = toolCalls[lastIdx].copyWith(
                    status: ToolCallStatus.executing,
                  );
                  _messages[idx] = current.copyWith(toolCalls: toolCalls);
                }
              }
              break;

            case ChatStreamEventType.toolResult:
              final current = _messages[idx];
              if (current.toolCalls != null && current.toolCalls!.isNotEmpty) {
                final toolCalls = List<ToolCallInfo>.from(current.toolCalls!);
                final lastIdx = toolCalls.length - 1;
                if (lastIdx >= 0) {
                  final result = event.toolResult;
                  final success = result?['success'] == true;
                  toolCalls[lastIdx] = toolCalls[lastIdx].copyWith(
                    status: success ? ToolCallStatus.completed : ToolCallStatus.error,
                    result: result,
                  );
                  _messages[idx] = current.copyWith(toolCalls: toolCalls);
                }
              }
              break;

            case ChatStreamEventType.done:
              final current = _messages[idx];
              final content = current.content;
              final hasToolCalls = current.toolCalls != null && current.toolCalls!.isNotEmpty;
              if (content.isNotEmpty) {
                _conversationHistory.add({'role': 'assistant', 'content': content});
              } else if (hasToolCalls) {
                _conversationHistory.add({'role': 'assistant', 'content': ''});
              }
              _messages[idx] = current.copyWith(isStreaming: false);
              _isLoading = false;
              _currentAssistantId = null;
              break;

            case ChatStreamEventType.error:
              _messages[idx] = _messages[idx].copyWith(
                content: event.error ?? 'An error occurred',
                isStreaming: false,
              );
              _isLoading = false;
              _currentAssistantId = null;
              break;
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_currentAssistantId != null) {
          final idx = _messages.indexWhere((m) => m.id == _currentAssistantId);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(
              content: 'Error: $e',
              isStreaming: false,
            );
          }
        }
        _isLoading = false;
        _currentAssistantId = null;
      });
    }
  }

  void _showApiKeyDialog() {
    Navigator.pushNamed(context, 'ai_settings');
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _conversationHistory.clear();
      _currentAssistantId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'AI Assistant',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _hasApiKey ? Icons.check_circle : Icons.warning_amber_rounded,
              color: _hasApiKey ? Colors.green : Colors.orange,
            ),
            onPressed: _showApiKeyDialog,
            tooltip: _hasApiKey ? 'AI Settings' : 'Set API Key',
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: isDark ? Colors.white54 : Colors.black54),
            onPressed: _clearChat,
            tooltip: 'Clear chat',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) => Dismissible(
                      key: Key(_messages[i].id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        color: isDark ? Colors.red.shade900 : Colors.red.shade400,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) {
                        setState(() {
                          _messages.removeAt(i);
                        });
                      },
                      child: _MessageBubble(message: _messages[i]),
                    ),
                  ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 36,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Hi! I\'m your task assistant',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask me to add, view, or manage your tasks.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.black54,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _SuggestionChip(
                  label: 'Show my tasks',
                  onTap: () => _sendSuggestion('Show my tasks'),
                ),
                _SuggestionChip(
                  label: 'Add a task',
                  onTap: () => _sendSuggestion('Add a task to call mom tomorrow at 6 PM'),
                ),
                _SuggestionChip(
                  label: 'What\'s pending?',
                  onTap: () => _sendSuggestion('What tasks do I have pending?'),
                ),
              ],
            ),
            if (!_hasApiKey) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _showApiKeyDialog,
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Configure AI'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _sendSuggestion(String text) {
    _inputController.text = text;
    _sendMessage();
  }

  Widget _buildInputArea() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        border: Border(top: BorderSide(color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE5E7EB))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF262626) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _inputController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.black38),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: _isLoading ? (isDark ? Colors.grey.shade700 : Colors.grey.shade300) : const Color(0xFF3B82F6),
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _isLoading ? null : _sendMessage,
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isDark ? Colors.white : Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Material(
      color: isDark ? const Color(0xFF262626) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: isDark ? const Color(0xFF404040) : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF3B82F6)),
            ),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (message.toolCalls != null && message.toolCalls!.isNotEmpty)
                  ...message.toolCalls!.map((tc) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ToolCallTile(toolCall: tc),
                  )),
                if (message.content.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF3B82F6) : (isDark ? const Color(0xFF1A1A1A) : Colors.white),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isUser ? null : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: SelectableText(
                      message.content,
                      style: TextStyle(
                        color: isUser ? Colors.white : (isDark ? Colors.white : Colors.black87),
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                if (message.isStreaming &&
                    message.content.isEmpty &&
                    (message.toolCalls == null || message.toolCalls!.isEmpty))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const _StreamingDots(),
                  ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 40),
          if (!isUser) const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _ToolCallTile extends StatelessWidget {
  const _ToolCallTile({required this.toolCall});

  final ToolCallInfo toolCall;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    Color bgColor;
    Color iconColor;
    IconData icon;
    String statusText;

    switch (toolCall.status) {
      case ToolCallStatus.pending:
        bgColor = isDark ? Colors.blue.shade900 : Colors.blue.shade50;
        iconColor = Colors.blue;
        icon = Icons.hourglass_empty;
        statusText = 'Preparing...';
      case ToolCallStatus.executing:
        bgColor = isDark ? Colors.amber.shade900 : Colors.amber.shade50;
        iconColor = isDark ? Colors.amber.shade300 : Colors.amber.shade700;
        icon = Icons.sync;
        statusText = 'Working...';
      case ToolCallStatus.completed:
        bgColor = isDark ? Colors.green.shade900 : Colors.green.shade50;
        iconColor = isDark ? Colors.green.shade300 : Colors.green;
        icon = Icons.check_circle;
        statusText = toolCall.resultSummary;
      case ToolCallStatus.error:
        bgColor = isDark ? Colors.red.shade900 : Colors.red.shade50;
        iconColor = isDark ? Colors.red.shade300 : Colors.red;
        icon = Icons.error_outline;
        statusText = toolCall.result?['error']?.toString() ?? 'Failed';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (toolCall.status == ToolCallStatus.executing)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: iconColor,
              ),
            )
          else
            Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${toolCall.displayName}: $statusText',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: iconColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StreamingDots extends StatefulWidget {
  const _StreamingDots();

  @override
  State<_StreamingDots> createState() => _StreamingDotsState();
}

class _StreamingDotsState extends State<_StreamingDots> {
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();
    _animate();
  }

  void _animate() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _dotCount = (_dotCount + 1) % 4;
        });
        _animate();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: i < _dotCount ? (isDark ? Colors.white54 : Colors.black54) : (isDark ? Colors.white24 : Colors.black26),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}

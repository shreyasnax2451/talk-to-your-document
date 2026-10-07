import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/scope_selector_dialog.dart';

class ChatScreen extends StatefulWidget {
  final VoidCallback onOpenLibrary;

  const ChatScreen({
    super.key,
    required this.onOpenLibrary,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final canSend = _textController.text.trim().isNotEmpty;
    if (canSend != _canSend) {
      setState(() {
        _canSend = canSend;
      });
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend([String? presetText]) async {
    final text = presetText ?? _textController.text.trim();
    if (text.isEmpty) return;

    if (presetText == null) {
      _textController.clear();
    }

    final appState = context.read<AppState>();
    await appState.sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final activeChat = appState.activeChat;
    final messages = activeChat.messages;
    final scopeName = appState.scopeDisplayName;

    // Scroll to bottom when messages change
    if (messages.isNotEmpty) {
      _scrollToBottom();
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppSidebar(
        onOpenLibrary: widget.onOpenLibrary,
        onNewChat: () {
          appState.createNewChat();
        },
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppTheme.textPrimary, size: 24),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        titleSpacing: 0,
        title: Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => ScopeSelectorDialog.show(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      scopeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppTheme.textPrimary, size: 22),
            onPressed: () {
              appState.createNewChat();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Chat Content (Empty State or Messages List)
            Expanded(
              child: messages.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 12.0,
                      ),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isLastAssistant = !msg.isUser &&
                            index == messages.length - 1;
                        return ChatBubble(
                          message: msg,
                          isLastAssistantMessage: isLastAssistant,
                        );
                      },
                    ),
            ),

            // Thumb-friendly Bottom Input Composer
            _buildInputBar(context, appState),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 48),

          // Rounded subtle logo badge
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Center(
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                color: AppTheme.textSecondary,
                size: 26,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Title
          const Text(
            'Ask about your documents',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.4,
            ),
          ),

          const SizedBox(height: 8),

          // Subtitle
          const Text(
            'Answers come from the PDFs\nin your library.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 36),

          // Suggested Prompts
          _buildSuggestedPromptButton('Summarize this document'),
          const SizedBox(height: 12),
          _buildSuggestedPromptButton('What are the key dates?'),
          const SizedBox(height: 12),
          _buildSuggestedPromptButton('List the main action items'),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSuggestedPromptButton(String prompt) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _handleSend(prompt),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(
          prompt,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(BuildContext context, AppState appState) {
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 12, top: 8),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(
          top: BorderSide(color: AppTheme.borderSubtle),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            // Attach button (+) uploads a PDF without leaving chat
            IconButton(
              icon: const Icon(Icons.add, color: AppTheme.textSecondary, size: 22),
              tooltip: 'Attach PDF',
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await appState.pickAndUploadDocument();
                messenger.showSnackBar(
                  const SnackBar(
                    backgroundColor: AppTheme.surface,
                    content: Text(
                      'Document uploaded to Library as Processing',
                      style: TextStyle(color: AppTheme.processingText),
                    ),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),

            // Message box
            Expanded(
              child: TextField(
                controller: _textController,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Ask about your documents',
                  hintStyle: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                ),
                onSubmitted: (_) => _handleSend(),
              ),
            ),

            // Send button (round button with upward arrow)
            Container(
              margin: const EdgeInsets.only(right: 4),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _canSend || appState.isGenerating
                    ? AppTheme.accent
                    : const Color(0xFF383835),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.arrow_upward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: _canSend && !appState.isGenerating
                    ? () => _handleSend()
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

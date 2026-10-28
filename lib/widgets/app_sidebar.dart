import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_session.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

class AppSidebar extends StatelessWidget {
  final VoidCallback onOpenLibrary;
  final VoidCallback onNewChat;

  /// Called after a chat in Recents is selected, so the host can show it.
  final VoidCallback onChatSelected;

  const AppSidebar({
    super.key,
    required this.onOpenLibrary,
    required this.onNewChat,
    required this.onChatSelected,
  });

  void _showChatOptions(BuildContext context, ChatSession session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.drive_file_rename_outline_rounded,
                  color: AppTheme.textPrimary,
                ),
                title: const Text(
                  'Rename chat',
                  style: TextStyle(color: AppTheme.textPrimary),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showRenameChatDialog(context, session);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.failedText,
                ),
                title: const Text(
                  'Delete chat',
                  style: TextStyle(color: AppTheme.failedText),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.read<AppState>().deleteChat(session.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameChatDialog(BuildContext context, ChatSession session) {
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          'Rename chat',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 18),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter chat title',
            hintStyle: const TextStyle(color: AppTheme.textMuted),
            filled: true,
            fillColor: AppTheme.background,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.accent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context.read<AppState>().renameChat(session.id, controller.text.trim());
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showProfileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.accent,
                    child: Text(
                      'P',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Primary User',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'user@docchat.local',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppTheme.borderSubtle),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: AppTheme.textPrimary),
                title: const Text(
                  'Sign out',
                  style: TextStyle(color: AppTheme.textPrimary),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppTheme.surface,
                      content: Text('Signed out successfully'),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_remove_outlined, color: AppTheme.failedText),
                title: const Text(
                  'Delete account',
                  style: TextStyle(color: AppTheme.failedText),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppTheme.surface,
                      content: Text(
                        'Account deletion requested',
                        style: TextStyle(color: AppTheme.failedText),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final activeId = appState.activeChatId;
    final sessions = appState.chatSessions;

    return Drawer(
      backgroundColor: const Color(0xFF1C1C1A),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top App Title & Library button
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(
                      Icons.description_rounded,
                      color: AppTheme.accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'DocChat',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Library Item
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.of(context).pop(); // close drawer
                  onOpenLibrary();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: AppTheme.surface.withValues(alpha: 0.5),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        color: AppTheme.textPrimary,
                        size: 20,
                      ),
                      SizedBox(width: 14),
                      Text(
                        'Library',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Divider(color: AppTheme.borderSubtle, height: 1),
            const SizedBox(height: 12),

            // Recents Section Title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 6.0),
              child: Text(
                'Recents',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),

            // Recents List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  final isActive = session.id == activeId;

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 2.5),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        appState.selectChat(session.id);
                        Navigator.of(context).pop(); // close drawer
                        onChatSelected();
                      },
                      onLongPress: () => _showChatOptions(context, session),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppTheme.surfaceHover
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: isActive
                              ? Border.all(color: AppTheme.border)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isActive
                                    ? AppTheme.accent
                                    : AppTheme.textMuted.withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                session.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isActive
                                      ? AppTheme.textPrimary
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const Divider(color: AppTheme.borderSubtle, height: 1),

            // Bottom Thumb-Zone: Profile Avatar & + New Chat
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Profile avatar (tap opens small menu with Sign out & Delete account)
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _showProfileMenu(context),
                    child: const CircleAvatar(
                      radius: 19,
                      backgroundColor: AppTheme.accent,
                      child: Text(
                        'P',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),

                  // + New Chat button within easy thumb reach
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.surface,
                      foregroundColor: AppTheme.textPrimary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: AppTheme.border),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop(); // close drawer
                      onNewChat();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(
                      'New chat',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

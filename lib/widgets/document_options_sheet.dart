import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/document.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../screens/pdf_viewer_screen.dart';

class DocumentOptionsSheet extends StatelessWidget {
  final Document document;
  final VoidCallback onNavigateToChat;

  const DocumentOptionsSheet({
    super.key,
    required this.document,
    required this.onNavigateToChat,
  });

  static Future<void> show(
    BuildContext context,
    Document document, {
    required VoidCallback onNavigateToChat,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DocumentOptionsSheet(
        document: document,
        onNavigateToChat: onNavigateToChat,
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: document.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          'Rename document',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 18),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter new document name',
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
                context.read<AppState>().renameDocument(document.id, controller.text.trim());
              }
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(); // Close sheet
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          'Delete document?',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 18),
        ),
        content: Text(
          'Are you sure you want to remove "${document.name}" from your library? This cannot be undone.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.failedText,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              context.read<AppState>().deleteDocument(document.id);
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(); // Close sheet
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d');
    final formattedDate = dateFormat.format(document.uploadDate);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Document info header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Center(
                    child: Text(
                      'PDF',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${document.pageCount} pages · $formattedDate',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: AppTheme.borderSubtle),
            const SizedBox(height: 8),

            // Action 1: Chat about this document
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: AppTheme.textPrimary,
                size: 22,
              ),
              title: const Text(
                'Chat about this document',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                final appState = context.read<AppState>();
                appState.createNewChat(scopeDocumentId: document.id);
                Navigator.of(context).pop();
                onNavigateToChat();
              },
            ),

            // Action 2: View PDF
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: const Icon(
                Icons.visibility_outlined,
                color: AppTheme.textPrimary,
                size: 22,
              ),
              title: const Text(
                'View PDF',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PdfViewerScreen(
                      document: document,
                      initialPage: 1,
                    ),
                  ),
                );
              },
            ),

            // Action 3: Rename
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: const Icon(
                Icons.drive_file_rename_outline_rounded,
                color: AppTheme.textPrimary,
                size: 22,
              ),
              title: const Text(
                'Rename',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () => _showRenameDialog(context),
            ),

            // Action 4: Delete
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: const Icon(
                Icons.close_rounded,
                color: AppTheme.failedText,
                size: 22,
              ),
              title: const Text(
                'Delete',
                style: TextStyle(
                  color: AppTheme.failedText,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () => _showDeleteDialog(context),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/chat_message.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../screens/pdf_viewer_screen.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isLastAssistantMessage;

  const ChatBubble({
    super.key,
    required this.message,
    this.isLastAssistantMessage = false,
  });

  void _copyText(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppTheme.surface,
        content: Text(
          'Copied to clipboard',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _openSourcePdf(BuildContext context, SourceRef source) {
    final doc = context.read<AppState>().getDocumentById(source.docId);
    if (doc != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            document: doc,
            initialPage: source.page.clamp(1, doc.pageCount < 1 ? 1 : doc.pageCount),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.surface,
          content: Text(
            'Document "${source.docName}" was deleted',
            style: const TextStyle(color: AppTheme.failedText),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return Padding(
        padding: const EdgeInsets.only(top: 12.0, bottom: 8.0, left: 48.0, right: 4.0),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.userBubble,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(
              message.text,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ),
        ),
      );
    }

    // Assistant answer on the left
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 16.0, right: 32.0, left: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Answer text
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: message.text.isEmpty && message.isStreaming
                ? Text(
                    message.statusText ?? '...',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      height: 1.55,
                    ),
                  )
                : Text(
                    message.text,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      height: 1.55,
                    ),
                  ),
          ),

          // Sources row under each answer
          if (message.sources.isNotEmpty && !message.isStreaming) ...[
            const SizedBox(height: 14),
            const Text(
              'Sources',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: message.sources.map((source) {
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _openSourcePdf(context, source),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.picture_as_pdf_rounded,
                          size: 14,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${source.docName} · p. ${source.page}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          // Action row: Copy & Regenerate
          if (!message.isStreaming && message.text.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _copyText(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: AppTheme.textMuted,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                if (isLastAssistantMessage)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      context.read<AppState>().regenerateLastAnswer();
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 15,
                            color: AppTheme.textMuted,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Regenerate',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

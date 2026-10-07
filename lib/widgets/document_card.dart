import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/document.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'document_options_sheet.dart';

class DocumentCard extends StatelessWidget {
  final Document document;
  final VoidCallback onNavigateToChat;

  const DocumentCard({
    super.key,
    required this.document,
    required this.onNavigateToChat,
  });

  void _showFailedOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: Text(
          document.name,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        ),
        content: Text(
          document.errorMessage ?? "This file could not be read or processed.",
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<AppState>().deleteDocument(document.id);
            },
            child: const Text('Delete', style: TextStyle(color: AppTheme.failedText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<AppState>().retryProcessing(document.id);
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d');
    final formattedDate = dateFormat.format(document.uploadDate);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (document.status == DocumentStatus.ready) {
          DocumentOptionsSheet.show(
            context,
            document,
            onNavigateToChat: onNavigateToChat,
          );
        } else if (document.status == DocumentStatus.failed) {
          _showFailedOptions(context);
        } else if (document.status == DocumentStatus.processing) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.surface,
              content: Text(
                'Indexing ${document.name}... (${(document.progress * 100).toInt()}%)',
                style: const TextStyle(color: AppTheme.processingText),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Row(
          children: [
            // PDF badge
            Container(
              width: 42,
              height: 42,
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
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Title & metadata / progress
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (document.status == DocumentStatus.processing) ...[
                    Row(
                      children: [
                        Text(
                          'Indexing ${(document.progress * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.processingText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: document.progress,
                              minHeight: 4,
                              backgroundColor: AppTheme.border,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppTheme.processingText,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (document.status == DocumentStatus.failed) ...[
                    Text(
                      document.errorMessage ?? "Couldn't read this file",
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.failedText,
                      ),
                    ),
                  ] else ...[
                    Text(
                      '${document.pageCount} pages · $formattedDate',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Status Chip
            _buildStatusChip(document),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(Document doc) {
    switch (doc.status) {
      case DocumentStatus.ready:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.readyBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.readyBorder),
          ),
          child: const Text(
            'Ready',
            style: TextStyle(
              color: AppTheme.readyText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case DocumentStatus.processing:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.processingBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.processingBorder),
          ),
          child: const Text(
            'Processing',
            style: TextStyle(
              color: AppTheme.processingText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case DocumentStatus.failed:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.failedBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.failedBorder),
          ),
          child: const Text(
            'Failed',
            style: TextStyle(
              color: AppTheme.failedText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
    }
  }
}

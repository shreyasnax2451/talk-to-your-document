import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/document.dart';

class ScopeSelectorDialog extends StatelessWidget {
  const ScopeSelectorDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ScopeSelectorDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final currentScopeId = appState.scopeDocumentId;
    final readyDocuments = appState.documents
        .where((d) => d.status == DocumentStatus.ready)
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 4),
              child: Text(
                'Select chat scope',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: currentScopeId == null
                      ? AppTheme.accent.withValues(alpha: 0.15)
                      : AppTheme.surfaceHover,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.folder_copy_outlined,
                  size: 20,
                  color: currentScopeId == null
                      ? AppTheme.accent
                      : AppTheme.textSecondary,
                ),
              ),
              title: const Text(
                'All documents',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
              subtitle: Text(
                'Search across all ${readyDocuments.length} ready documents in library',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              trailing: currentScopeId == null
                  ? const Icon(Icons.check_rounded, color: AppTheme.accent)
                  : null,
              onTap: () {
                appState.setScope(null);
                Navigator.of(context).pop();
              },
            ),
            const Divider(color: AppTheme.borderSubtle, height: 16),
            ...readyDocuments.map((doc) {
              final isSelected = currentScopeId == doc.id;
              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.accent.withValues(alpha: 0.15)
                        : AppTheme.surfaceHover,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 20,
                    color: isSelected ? AppTheme.accent : Colors.redAccent.shade200,
                  ),
                ),
                title: Text(
                  doc.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  '${doc.pageCount} pages',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_rounded, color: AppTheme.accent)
                    : null,
                onTap: () {
                  appState.setScope(doc.id);
                  Navigator.of(context).pop();
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

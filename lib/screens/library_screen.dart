import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/document_card.dart';
import '../widgets/app_sidebar.dart';

class LibraryScreen extends StatefulWidget {
  final VoidCallback onNavigateToChat;
  final VoidCallback onNewChat;

  const LibraryScreen({
    super.key,
    required this.onNavigateToChat,
    required this.onNewChat,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final filteredDocuments = appState.searchDocuments(_searchQuery);

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppSidebar(
        onOpenLibrary: () {},
        onNewChat: () {
          widget.onNewChat();
          widget.onNavigateToChat();
        },
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppTheme.textPrimary, size: 24),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text(
          'Library',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search documents bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search documents',
                  hintStyle: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppTheme.textMuted,
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          color: AppTheme.textMuted,
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),

          // Document list
          Expanded(
            child: filteredDocuments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: AppTheme.textMuted.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No documents found',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      top: 4.0,
                      bottom: 88.0,
                    ),
                    itemCount: filteredDocuments.length,
                    itemBuilder: (context, index) {
                      final doc = filteredDocuments[index];
                      return DocumentCard(
                        document: doc,
                        onNavigateToChat: widget.onNavigateToChat,
                      );
                    },
                  ),
          ),
        ],
      ),

      // Thumb-friendly + Floating Action Button at bottom right
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF262624),
        foregroundColor: AppTheme.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: AppTheme.border),
        ),
        elevation: 3,
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          await appState.pickAndUploadDocument();
          messenger.showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.surface,
              content: Text(
                'Document added to Library and processing started',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              duration: Duration(seconds: 2),
            ),
          );
        },
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }
}

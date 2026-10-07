import 'package:flutter/material.dart';
import '../models/document.dart';
import '../theme/app_theme.dart';

class PdfViewerScreen extends StatefulWidget {
  final Document document;
  final int initialPage;

  const PdfViewerScreen({
    super.key,
    required this.document,
    this.initialPage = 1,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late PageController _pageController;
  late int _currentPage;
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage - 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _goToPreviousPage() {
    if (_currentPage > 1) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToNextPage() {
    if (_currentPage < widget.document.pageCount) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = widget.document.pageCount;

    return Scaffold(
      backgroundColor: const Color(0xFF141413),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B19),
        elevation: 1,
        shadowColor: Colors.black26,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.document.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              'Page $_currentPage of $totalPages',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Document canvas with pinch-to-zoom and page swipe
          Expanded(
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.8,
              maxScale: 3.5,
              child: PageView.builder(
                controller: _pageController,
                itemCount: totalPages,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index + 1;
                  });
                },
                itemBuilder: (context, index) {
                  return _buildPageCard(index + 1);
                },
              ),
            ),
          ),

          // Bottom reader controls: < X / Y >
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1B1B19),
              border: Border(
                top: BorderSide(color: AppTheme.borderSubtle),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 28),
                    color: _currentPage > 1
                        ? AppTheme.textPrimary
                        : AppTheme.textMuted,
                    onPressed: _currentPage > 1 ? _goToPreviousPage : null,
                  ),
                  const SizedBox(width: 24),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      '$_currentPage / $totalPages',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 28),
                    color: _currentPage < totalPages
                        ? AppTheme.textPrimary
                        : AppTheme.textMuted,
                    onPressed: _currentPage < totalPages ? _goToNextPage : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageCard(int pageNum) {
    String pageContent = '';
    if (widget.document.pages.isNotEmpty) {
      final pageIndex = (pageNum - 1) % widget.document.pages.length;
      pageContent = widget.document.pages[pageIndex];
    } else {
      pageContent = '''${widget.document.name.toUpperCase()}
Page $pageNum of ${widget.document.pageCount}

Section 1: General Provisions
The terms and statements documented herein outline the verified specifications, structured data records, and contractual stipulations applicable to this active portfolio item.

Section 2: Performance & Metrics
All quantitative observations comply with regulatory requirements, standard accounting directives, and periodic auditing parameters established for this fiscal year.

Section 3: Record Integrity
This document was indexed and verified in the DocChat library on ${widget.document.uploadDate.year}-${widget.document.uploadDate.month.toString().padLeft(2, '0')}-${widget.document.uploadDate.day.toString().padLeft(2, '0')}.''';
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 580),
        decoration: BoxDecoration(
          color: const Color(0xFFFCFCF9), // Authentic cream document paper
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Document header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.document.name,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Page $pageNum',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
              const Divider(color: Color(0xFFE5E7EB), thickness: 1, height: 24),
              const SizedBox(height: 12),
              SelectableText(
                pageContent,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Color(0xFF1F2937),
                  fontFamily: 'Courier',
                ),
              ),
              const SizedBox(height: 32),
              // Document footer
              Center(
                child: Container(
                  width: 60,
                  height: 2,
                  color: const Color(0xFFE5E7EB),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'CONFIDENTIAL & PROPRIETARY',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

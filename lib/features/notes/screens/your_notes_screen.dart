import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/models/library_item_model.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/services/api_service.dart';
import 'package:pgme/core/services/dashboard_service.dart';
import 'package:pgme/core/services/download_service.dart';
import 'package:pgme/core/services/ebook_access_service.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/widgets/app_dialog.dart';
import 'package:pgme/features/home/providers/dashboard_provider.dart';

class YourNotesScreen extends StatefulWidget {
  const YourNotesScreen({super.key});

  @override
  State<YourNotesScreen> createState() => _YourNotesScreenState();
}

class _YourNotesScreenState extends State<YourNotesScreen> {
  final DashboardService _dashboardService = DashboardService();
  final EbookAccessService _ebookAccessService = EbookAccessService();
  final DownloadService _downloadService = DownloadService();
  List<LibraryItemModel> _libraryItems = [];
  List<LibraryItemModel> _purchasedEbookItems = [];
  bool _isLoading = true;
  String? _error;
  bool _showBookmarkedOnly = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Download tracking
  final Set<String> _downloadedDocIds = {};
  final Map<String, double> _downloadingDocs = {}; // itemId → progress 0.0-1.0

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    _loadPurchasedEbooks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleBookmark(LibraryItemModel item) async {
    final newBookmarkState = !item.isBookmarked;
    final index = _libraryItems.indexWhere((i) => i.libraryId == item.libraryId);
    if (index == -1) return;

    // Optimistic update
    setState(() {
      _libraryItems[index] = item.copyWith(isBookmarked: newBookmarkState);
    });

    try {
      await _dashboardService.toggleBookmark(item.libraryId, newBookmarkState);

      // If on "Bookmarked" tab and we just unbookmarked, remove from list
      if (_showBookmarkedOnly && !newBookmarkState && mounted) {
        setState(() {
          _libraryItems.removeAt(index);
        });
      }
    } catch (e) {
      // Revert on failure
      if (mounted) {
        setState(() {
          _libraryItems[index] = item;
        });
        showAppDialog(context, message: 'Failed to update bookmark', type: AppDialogType.info);
      }
    }
  }

  Future<void> _loadLibrary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Filter by user's primary subject so only relevant notes are shown
      final primarySubjectId = context.read<DashboardProvider>().primarySubject?.subjectId;

      final items = await _dashboardService.getUserLibrary(
        isBookmarked: _showBookmarkedOnly ? true : null,
        subjectId: primarySubjectId,
      );

      if (mounted) {
        setState(() {
          _libraryItems = items;
          _isLoading = false;
        });
        _checkDownloadedDocs();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadPurchasedEbooks() async {
    try {
      final ebooks = await _ebookAccessService.getUserAccessibleEbooks();
      if (mounted) {
        setState(() {
          _purchasedEbookItems = ebooks.map((ebook) => LibraryItemModel(
            libraryId: 'ebook_${ebook.purchaseId}',
            documentId: ebook.bookId,
            title: ebook.title,
            description: ebook.author,
            fileFormat: ebook.ebookFileFormat ?? 'pdf',
            pageCount: ebook.pages,
            fileSizeMb: ebook.ebookFileSizeMb,
            addedAt: ebook.purchasedAt,
            isBookmarked: false,
          )).toList();
        });
        _checkDownloadedDocs();
      }
    } catch (e) {
      debugPrint('Error loading purchased ebooks: $e');
    }
  }

  /// Check which documents are already downloaded
  Future<void> _checkDownloadedDocs() async {
    for (final item in _libraryItems) {
      final fileName = 'doc_${item.documentId}.pdf';
      final downloaded = await _downloadService.isDownloaded(fileName);
      if (downloaded) _downloadedDocIds.add(item.documentId);
    }
    for (final item in _purchasedEbookItems) {
      final fileName = 'ebook_${item.documentId}.pdf';
      final downloaded = await _downloadService.isDownloaded(fileName);
      if (downloaded) _downloadedDocIds.add(item.documentId);
    }
    if (mounted) setState(() {});
  }

  /// Download a document (library item or ebook)
  Future<void> _downloadDocument(LibraryItemModel item) async {
    final docId = item.documentId;
    if (_downloadingDocs.containsKey(docId) || _downloadedDocIds.contains(docId)) return;

    setState(() {
      _downloadingDocs[docId] = 0.0;
    });

    try {
      String url;
      String fileName;

      if (_isEbookItem(item)) {
        final data = await _ebookAccessService.getEbookViewUrl(docId);
        url = data['url'] as String;
        fileName = 'ebook_$docId.pdf';
      } else {
        final response = await ApiService().dio.get(
          ApiConstants.documentViewUrl(docId),
        );
        url = response.data['data']['url'] as String;
        fileName = 'doc_$docId.pdf';
      }

      await _downloadService.downloadFile(
        url: url,
        fileName: fileName,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadingDocs[docId] = progress;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloadingDocs.remove(docId);
          _downloadedDocIds.add(docId);
        });
        showAppDialog(context, message: 'Document downloaded successfully', type: AppDialogType.info);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadingDocs.remove(docId);
        });
        showAppDialog(context, message: 'Download failed: ${e.toString().replaceAll('Exception: ', '')}', type: AppDialogType.info);
      }
    }
  }

  bool _isEbookItem(LibraryItemModel item) {
    return item.libraryId.startsWith('ebook_');
  }

  Future<void> _openEbook(LibraryItemModel item) async {
    try {
      final data = await _ebookAccessService.getEbookViewUrl(item.documentId);
      if (mounted) {
        final url = data['url'] as String?;
        final title = data['title'] as String? ?? item.title;
        final fileFormat = (data['file_format'] as String?) ?? 'pdf';
        if (url != null) {
          if (fileFormat == 'epub') {
            context.pushNamed(
              'epub-viewer',
              queryParameters: {
                'documentId': item.documentId,
                'epubUrl': url,
                'title': title,
              },
            );
          } else {
            context.pushNamed(
              'pdf-viewer',
              queryParameters: {
                'documentId': item.documentId,
                'pdfUrl': url,
                'title': title,
              },
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        showAppDialog(context, message: 'Failed to open eBook: ${e.toString().replaceAll("Exception: ", "")}');
      }
    }
  }

  List<LibraryItemModel> get _filteredItems {
    // Merge purchased ebooks at top (only in All Notes tab, not bookmarked)
    final List<LibraryItemModel> merged = [];
    if (!_showBookmarkedOnly) {
      merged.addAll(_purchasedEbookItems);
    }
    merged.addAll(_libraryItems);

    if (_searchQuery.isEmpty) return merged;
    return merged.where((item) {
      final titleMatch = item.title.toLowerCase().contains(_searchQuery.toLowerCase());
      final descMatch = item.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false;
      return titleMatch || descMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final cardBgColor = isDark ? AppColors.darkCardBackground : const Color(0xFFE4F4FF);
    final searchBarColor = isDark ? AppColors.darkSurface : Colors.white;
    final searchBarBorderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final dividerColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final badgeColor = isDark ? const Color(0xFF1A1A4D) : const Color(0xFF000080);
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;
    final scale = ResponsiveHelper.tabletScale(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: EdgeInsets.only(top: topPadding + (isTablet ? 21 : 16), left: hPadding, right: hPadding),
            child: Row(
              children: [
                // Title
                Text(
                  'Your Notes',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 25 * scale : 20,
                    height: 1.0,
                    letterSpacing: -0.5,
                    color: textColor,
                  ),
                ),
                const Spacer(),
                // Refresh button
                GestureDetector(
                  onTap: () {
                    _loadLibrary();
                    _loadPurchasedEbooks();
                  },
                  child: SizedBox(
                    width: isTablet ? 30 * scale : 24,
                    height: isTablet ? 30 * scale : 24,
                    child: Icon(
                      Icons.refresh,
                      size: isTablet ? 30 * scale : 24,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: isTablet ? 21 : 16),

          // Search Bar
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hPadding),
            child: Container(
              width: double.infinity,
              height: isTablet ? 56 * scale : 48,
              decoration: BoxDecoration(
                color: searchBarColor,
                borderRadius: BorderRadius.circular(isTablet ? 23 * scale : 18),
                border: Border.all(
                  color: searchBarBorderColor,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(width: isTablet ? 20 : 16),
                  Icon(
                    Icons.search,
                    size: isTablet ? 30 * scale : 24,
                    color: secondaryTextColor,
                  ),
                  SizedBox(width: isTablet ? 16 : 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search through your medical notes...',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 15 * scale : 12,
                          fontWeight: FontWeight.w500,
                          height: 20 / 12,
                          letterSpacing: -0.5,
                          color: textColor.withValues(alpha: 0.4),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isTablet ? 15 * scale : 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.5,
                        color: textColor,
                      ),
                    ),
                  ),
                  SizedBox(width: isTablet ? 20 : 16),
                ],
              ),
            ),
          ),

          SizedBox(height: isTablet ? 21 : 16),

          // Filter Buttons
          Padding(
            padding: EdgeInsets.only(left: isTablet ? hPadding : 17),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showBookmarkedOnly = false;
                    });
                    _loadLibrary();
                  },
                  child: Container(
                    height: isTablet ? 42 * scale : 36,
                    decoration: BoxDecoration(
                      color: !_showBookmarkedOnly ? badgeColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(isTablet ? 8 : 6),
                      border: !_showBookmarkedOnly ? null : Border.all(color: badgeColor),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 15 : 11, vertical: isTablet ? 10 : 8),
                    child: Text(
                      'All Notes',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: isTablet ? 15 * scale : 12,
                        height: 20 / 12,
                        letterSpacing: -0.5,
                        color: !_showBookmarkedOnly ? Colors.white : badgeColor,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: isTablet ? 13 : 10),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showBookmarkedOnly = true;
                    });
                    _loadLibrary();
                  },
                  child: Container(
                    height: isTablet ? 42 * scale : 36,
                    decoration: BoxDecoration(
                      color: _showBookmarkedOnly ? badgeColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(isTablet ? 8 : 6),
                      border: _showBookmarkedOnly ? null : Border.all(color: badgeColor),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 15 : 11, vertical: isTablet ? 10 : 8),
                    child: Text(
                      'Bookmarked',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: isTablet ? 15 * scale : 12,
                        height: 20 / 12,
                        letterSpacing: -0.5,
                        color: _showBookmarkedOnly ? Colors.white : badgeColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: isTablet ? 23 : 18),

          // eBook & Physical Cards
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isTablet ? hPadding : 15),
            child: GestureDetector(
              onTap: () => context.push('/ebook-store'),
              child: Container(
                width: double.infinity,
                height: ResponsiveHelper.orderBookCardHeight(context),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(isTablet ? 24 : 14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [const Color(0xFF1A3A2E), const Color(0xFF0D2A1C)]
                        : [const Color(0xFF00875A), const Color(0xFF00C853)],
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 24 : 16,
                    vertical: isTablet ? 20 : 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: isTablet ? 52 : 40,
                        height: isTablet ? 52 : 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
                        ),
                        child: Icon(
                          Icons.menu_book_rounded,
                          size: isTablet ? 28 : 22,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: isTablet ? 16 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              Platform.isIOS ? 'E-Books' : 'Buy E-Books',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: isTablet ? 22 * scale : 16,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: isTablet ? 4 : 2),
                            Text(
                              Platform.isIOS ? 'Browse study materials' : 'Browse and purchase study materials',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w400,
                                fontSize: isTablet ? 15 * scale : 12,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: isTablet ? 22 : 16,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SizedBox(height: isTablet ? 21 : 16),

          // Content
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: iconColor),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: isTablet ? 64 : 48, color: secondaryTextColor),
                            SizedBox(height: isTablet ? 21 : 16),
                            Text(
                              'Failed to load notes',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 20 : 16,
                                color: textColor,
                              ),
                            ),
                            SizedBox(height: isTablet ? 10 : 8),
                            Text(
                              _error!.replaceAll('Exception: ', ''),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 15 * scale : 12,
                                color: secondaryTextColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: isTablet ? 21 : 16),
                            ElevatedButton(
                              onPressed: _loadLibrary,
                              style: ElevatedButton.styleFrom(backgroundColor: iconColor),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _filteredItems.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.menu_book_outlined,
                                  size: isTablet ? 80 : 64,
                                  color: secondaryTextColor,
                                ),
                                SizedBox(height: isTablet ? 21 : 16),
                                Text(
                                  _showBookmarkedOnly
                                      ? 'No bookmarked notes yet'
                                      : 'No notes in your library',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: isTablet ? 20 : 16,
                                    fontWeight: FontWeight.w500,
                                    color: textColor,
                                  ),
                                ),
                                SizedBox(height: isTablet ? 10 : 8),
                                Text(
                                  'Add notes to your library from series',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: isTablet ? 17 : 14,
                                    color: secondaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadLibrary,
                            child: isTablet
                              ? GridView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                                  padding: EdgeInsets.only(
                                    left: hPadding,
                                    right: hPadding,
                                    bottom: 130,
                                  ),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                    childAspectRatio: 16 / 9,
                                  ),
                                  itemCount: _filteredItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _filteredItems[index];
                                    return _buildBookCard(
                                      item: item,
                                      isDark: isDark,
                                      isTablet: isTablet,
                                      textColor: textColor,
                                      secondaryTextColor: secondaryTextColor,
                                      cardBgColor: cardBgColor,
                                      dividerColor: dividerColor,
                                      badgeColor: badgeColor,
                                      iconColor: iconColor,
                                      hPadding: 0,
                                    );
                                  },
                                )
                              : ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                                  padding: const EdgeInsets.only(bottom: 100),
                                  itemCount: _filteredItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _filteredItems[index];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _buildBookCard(
                                        item: item,
                                        isDark: isDark,
                                        isTablet: isTablet,
                                        textColor: textColor,
                                        secondaryTextColor: secondaryTextColor,
                                        cardBgColor: cardBgColor,
                                        dividerColor: dividerColor,
                                        badgeColor: badgeColor,
                                        iconColor: iconColor,
                                        hPadding: hPadding,
                                      ),
                                    );
                                  },
                                ),
                          ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildBookCard({
    required LibraryItemModel item,
    required bool isDark,
    required bool isTablet,
    required Color textColor,
    required Color secondaryTextColor,
    required Color cardBgColor,
    required Color dividerColor,
    required Color badgeColor,
    required Color iconColor,
    required double hPadding,
  }) {
    final scale = ResponsiveHelper.tabletScale(context);
    final inGrid = isTablet && hPadding == 0;
    final cardPad = isTablet ? 18.0 * scale : 16.0;
    final titleSize = isTablet ? 20.0 * scale : 16.0;
    final descSize = isTablet ? 16.0 * scale : 12.0;
    final metaSize = isTablet ? 15.0 * scale : 12.0;
    final metaIconSize = isTablet ? 20.0 * scale : 16.0;
    final badgeHeight = isTablet ? 26.0 * scale : 20.0;
    final badgeFontSize = isTablet ? 13.0 * scale : 10.0;
    final bookmarkSize = isTablet ? 34.0 * scale : 28.0;
    final cardRadius = isTablet ? 22.0 * scale : 20.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: inGrid ? 0 : (isTablet ? hPadding : 15)),
      child: GestureDetector(
        onTap: () {
          if (_isEbookItem(item)) {
            _openEbook(item);
          } else {
            context.pushNamed(
              'pdf-viewer',
              queryParameters: {
                'documentId': item.documentId,
                'title': item.title,
              },
            );
          }
        },
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(cardPad),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(cardRadius),
            border: Border.all(
              color: iconColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: inGrid ? MainAxisSize.max : MainAxisSize.min,
            children: [
              // Title Row with Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: titleSize,
                        height: 1.2,
                        color: textColor,
                      ),
                      maxLines: inGrid ? 2 : null,
                      overflow: inGrid ? TextOverflow.ellipsis : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Badge
                  Container(
                    height: badgeHeight,
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 10 : 10),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(isTablet ? 6 : 5),
                    ),
                    child: Center(
                      child: Text(
                        item.fileExtension,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: badgeFontSize,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  if (!_isEbookItem(item)) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _toggleBookmark(item),
                      child: Icon(
                        item.isBookmarked
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                        size: bookmarkSize,
                        color: iconColor,
                      ),
                    ),
                  ],
                  // Download button
                  const SizedBox(width: 4),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (!_downloadingDocs.containsKey(item.documentId) &&
                          !_downloadedDocIds.contains(item.documentId)) {
                        _downloadDocument(item);
                      }
                    },
                    child: Container(
                      width: isTablet ? 44.0 : 38.0,
                      height: isTablet ? 44.0 : 38.0,
                      alignment: Alignment.center,
                      child: _downloadingDocs.containsKey(item.documentId)
                          ? SizedBox(
                              width: isTablet ? 26.0 : 22.0,
                              height: isTablet ? 26.0 : 22.0,
                              child: CircularProgressIndicator(
                                value: _downloadingDocs[item.documentId],
                                strokeWidth: 2,
                                color: iconColor,
                              ),
                            )
                          : Icon(
                              _downloadedDocIds.contains(item.documentId)
                                  ? Icons.download_done
                                  : Icons.download_outlined,
                              size: bookmarkSize,
                              color: _downloadedDocIds.contains(item.documentId)
                                  ? AppColors.success
                                  : secondaryTextColor,
                            ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: isTablet ? 8 : 8),

              // Description
              if (item.description != null && item.description!.isNotEmpty)
                Flexible(
                  flex: inGrid ? 1 : 0,
                  fit: inGrid ? FlexFit.tight : FlexFit.loose,
                  child: Text(
                    item.description!,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: descSize,
                      height: 1.4,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                    maxLines: inGrid ? 2 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (item.description == null || item.description!.isEmpty)
                if (inGrid) const Spacer(),

              SizedBox(height: isTablet ? 10 : 12),

              // Divider
              Container(
                width: double.infinity,
                height: 1,
                color: dividerColor,
              ),

              SizedBox(height: isTablet ? 10 : 12),

              // Date Row
              Wrap(
                spacing: inGrid ? 12 : (isTablet ? 24 : 24),
                runSpacing: 6,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: metaIconSize,
                        color: secondaryTextColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.formattedAddedDate,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: metaSize,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                  if (item.fileSizeMb != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.storage_outlined,
                          size: metaIconSize,
                          color: secondaryTextColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.formattedFileSize,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w400,
                            fontSize: metaSize,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

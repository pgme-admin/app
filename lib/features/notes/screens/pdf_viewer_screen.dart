import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/services/api_service.dart';
import 'package:pgme/core/services/bookmark_service.dart';
import 'package:pgme/core/services/highlight_service.dart';
import 'package:pgme/core/services/download_service.dart';
import 'package:pgme/core/services/progress_service.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/widgets/app_dialog.dart';
import 'package:pgme/features/notes/widgets/bookmarks_drawer.dart';

class PdfViewerScreen extends StatefulWidget {
  /// Document ID — used to fetch the URL from the backend (with access control).
  final String? documentId;

  /// Direct PDF URL — used for preview URLs that don't need auth.
  /// If provided, skips the backend API call.
  final String? pdfUrl;

  /// Local file path — used when the PDF is already downloaded to disk.
  /// If provided, skips both the backend API call and the download step.
  final String? filePath;

  final String title;

  const PdfViewerScreen({
    super.key,
    this.documentId,
    this.pdfUrl,
    this.filePath,
    this.title = 'PDF Viewer',
  }) : assert(documentId != null || pdfUrl != null || filePath != null);

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final HighlightService _highlightService = HighlightService();
  final BookmarkService _bookmarkService = BookmarkService();
  final ProgressService _progressService = ProgressService();

  String? _localPath;
  bool _isLoading = true;
  bool _isPdfReady = false; // true once SfPdfViewer finishes parsing
  String? _error;
  double _downloadProgress = 0;
  bool _isSearchOpen = false;
  PdfTextSearchResult? _searchResult;

  // Track highlight_id -> annotation mapping for deletion
  final Map<String, Annotation> _highlightAnnotations = {};

  // Track underline_id -> annotation mapping
  final Map<String, Annotation> _underlineAnnotations = {};

  // Track annotation notes: annotationId -> note
  final Map<String, String?> _annotationNotes = {};

  // Track annotation text: annotationId -> highlighted text
  final Map<String, String> _annotationTexts = {};

  // Context menu overlay (for highlight color picker + delete)
  OverlayEntry? _contextMenuOverlay;

  // Feature 1: Bookmarks — pageNumber -> bookmarkId
  final Map<int, String> _bookmarkedPages = {};
  // Bookmark notes: bookmarkId -> note
  final Map<String, String?> _bookmarkNotes = {};

  // Feature 2: Progress tracking
  final ValueNotifier<int> _currentPage = ValueNotifier(1);
  Timer? _progressDebounceTimer;

  // Feature 3: PDF content dark mode
  bool _isPdfDarkMode = false;

  // Quick action buttons visibility (toggle on single tap)
  bool _showQuickActions = true;
  bool _isAnnotationSelected = false;

  static const Map<String, Color> highlightColors = {
    'yellow': Color(0x80FFEB3B),
    'green': Color(0x8066BB6A),
    'blue': Color(0x8042A5F5),
    'pink': Color(0x80EC407A),
  };

  static const Color underlineColor = Color(0xFF1565C0);

  // Color inversion matrix for PDF dark mode
  static const ColorFilter _invertColorFilter = ColorFilter.matrix(<double>[
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ]);

  @override
  void initState() {
    super.initState();
    // Initialize PDF dark mode from system theme
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final isDark =
            Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
        setState(() {
          _isPdfDarkMode = isDark;
        });
      }
    });
    _loadPdf();
  }

  @override
  void dispose() {
    _contextMenuOverlay?.remove();
    // Save final progress before disposing
    _progressDebounceTimer?.cancel();
    if (widget.documentId != null && _currentPage.value > 0) {
      _saveProgress(_currentPage.value);
    }
    _currentPage.dispose();
    _pdfController.dispose();
    _searchResult?.dispose();
    super.dispose();
  }

  Future<void> _loadPdf() async {
    try {
      // If a local file path is provided, use it directly (e.g. invoice PDF)
      if (widget.filePath != null) {
        if (mounted) {
          setState(() {
            _localPath = widget.filePath;
            _isLoading = false;
          });
        }
        return;
      }

      // Check for permanently downloaded file first (parallel lookup)
      if (widget.documentId != null) {
        final docFileName = 'doc_${widget.documentId}.pdf';
        final ebookFileName = 'ebook_${widget.documentId}.pdf';
        final downloadService = DownloadService();
        final results = await Future.wait([
          downloadService.getDownloadedPath(docFileName),
          downloadService.getDownloadedPath(ebookFileName),
        ]);
        final downloadedPath = results[0] ?? results[1];
        if (downloadedPath != null) {
          final file = File(downloadedPath);
          if (await file.exists() && mounted) {
            setState(() {
              _localPath = downloadedPath;
              _isLoading = false;
            });
            return;
          }
        }
      }

      String pdfUrl;

      if (widget.pdfUrl != null) {
        pdfUrl = widget.pdfUrl!;
      } else {
        final apiService = ApiService();
        final response = await apiService.dio.get(
          ApiConstants.documentViewUrl(widget.documentId!),
        );
        pdfUrl = response.data['data']['url'] as String;
      }

      if (!mounted) return;

      // Download PDF to temp directory
      final dir = await getTemporaryDirectory();
      final fileName = 'pgme_${widget.documentId ?? pdfUrl.hashCode}.pdf';
      final filePath = '${dir.path}/$fileName';

      // Check if already cached
      final file = File(filePath);
      if (await file.exists()) {
        if (mounted) {
          setState(() {
            _localPath = filePath;
            _isLoading = false;
          });
        }
        return;
      }

      // Download with progress
      await Dio().download(
        pdfUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() {
              _downloadProgress = received / total;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _localPath = filePath;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('PDF load error: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to load PDF';
          _isLoading = false;
        });
      }
    }
  }

  // ── Feature 2: Continue Where Left Off ─────────────────────────────

  Future<void> _restoreProgress() async {
    if (widget.documentId == null) return;
    try {
      final progress =
          await _progressService.getDocumentProgress(widget.documentId!);
      final savedPage = progress['page_number'] as int? ?? 1;
      if (savedPage > 1 && mounted) {
        _pdfController.jumpToPage(savedPage);
      }
    } catch (e) {
      debugPrint('Failed to restore progress: $e');
    }
  }

  void _debouncedSaveProgress(int pageNumber) {
    _progressDebounceTimer?.cancel();
    _progressDebounceTimer = Timer(const Duration(seconds: 2), () {
      _saveProgress(pageNumber);
    });
  }

  Future<void> _saveProgress(int pageNumber) async {
    if (widget.documentId == null) return;
    try {
      await _progressService.updateDocumentProgress(
        documentId: widget.documentId!,
        pageNumber: pageNumber,
      );
    } catch (e) {
      debugPrint('Failed to save progress: $e');
    }
  }

  // ── Feature 1: Bookmarks ──────────────────────────────────────────

  Future<void> _loadBookmarks() async {
    if (widget.documentId == null) return;
    try {
      final bookmarks =
          await _bookmarkService.getBookmarks(widget.documentId!);
      if (mounted) {
        setState(() {
          _bookmarkedPages.clear();
          _bookmarkNotes.clear();
          for (final b in bookmarks) {
            final pageNumber = b['page_number'] as int;
            final bookmarkId = b['bookmark_id'] as String;
            _bookmarkedPages[pageNumber] = bookmarkId;
            _bookmarkNotes[bookmarkId] = b['note'] as String?;
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to load bookmarks: $e');
    }
  }

  Future<void> _toggleBookmark() async {
    if (widget.documentId == null) return;
    final page = _currentPage.value;

    if (_bookmarkedPages.containsKey(page)) {
      // Remove bookmark — optimistic UI
      final bookmarkId = _bookmarkedPages[page]!;
      setState(() {
        _bookmarkedPages.remove(page);
        _bookmarkNotes.remove(bookmarkId);
      });
      try {
        await _bookmarkService.deleteBookmark(bookmarkId);
      } catch (e) {
        // Restore on failure
        if (mounted) {
          setState(() => _bookmarkedPages[page] = bookmarkId);
          showAppDialog(context, message: 'Failed to remove bookmark', type: AppDialogType.info);
        }
      }
    } else {
      // Add bookmark
      try {
        final result = await _bookmarkService.addBookmark(
          documentId: widget.documentId!,
          pageNumber: page,
        );
        if (mounted) {
          setState(() {
            final bookmarkId = result['bookmark_id'] as String;
            _bookmarkedPages[page] = bookmarkId;
            _bookmarkNotes[bookmarkId] = result['note'] as String?;
          });
        }
      } catch (e) {
        if (mounted) {
          showAppDialog(context, message: 'Failed to add bookmark', type: AppDialogType.info);
        }
      }
    }
  }

  // ── Highlights & Underlines ───────────────────────────────────────

  /// Load saved highlights/underlines from backend and apply as annotations
  Future<void> _loadHighlights() async {
    if (widget.documentId == null) return;

    // Small delay to ensure PDF viewer is fully ready for annotations
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    try {
      final highlights =
          await _highlightService.getHighlights(widget.documentId!);

      for (final h in highlights) {
        try {
          final colorName = h['color'] ?? 'yellow';
          final color =
              highlightColors[colorName] ?? highlightColors['yellow']!;
          final highlightId = h['highlight_id'] as String;
          final boundsData = h['bounds_data'] as List?;
          final annotationType =
              (h['annotation_type'] as String?) ?? 'highlight';
          final note = h['note'] as String?;

          if (boundsData == null || boundsData.isEmpty) continue;

          // Reconstruct PdfTextLine objects from saved bounds
          final textLines = boundsData.map<PdfTextLine>((b) {
            return PdfTextLine(
              Rect.fromLTWH(
                (b['left'] as num).toDouble(),
                (b['top'] as num).toDouble(),
                (b['width'] as num).toDouble(),
                (b['height'] as num).toDouble(),
              ),
              b['text'] as String? ?? '',
              (b['page_number'] as num).toInt(),
            );
          }).toList();

          if (textLines.isEmpty) continue;

          if (annotationType == 'underline') {
            final annotation = UnderlineAnnotation(
              textBoundsCollection: textLines,
            );
            annotation.color = underlineColor;
            _pdfController.addAnnotation(annotation);
            _underlineAnnotations[highlightId] = annotation;
          } else {
            final annotation = HighlightAnnotation(
              textBoundsCollection: textLines,
            );
            annotation.color = color;
            _pdfController.addAnnotation(annotation);
            _highlightAnnotations[highlightId] = annotation;
          }

          // Track note and text
          _annotationNotes[highlightId] = note;
          _annotationTexts[highlightId] =
              (h['highlighted_text'] as String?) ?? '';
        } catch (e) {
          debugPrint('Failed to restore highlight: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to load highlights: $e');
    }
  }

  /// Show context menu when text is selected (highlight colors + underline)
  void _showContextMenu(Offset position) {
    _removeContextMenu();

    final overlay = Overlay.of(context);
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final screenSize = MediaQuery.of(context).size;

    // Adjust position to stay within screen bounds
    double left = position.dx - 100;
    double top = position.dy - 60;
    if (left < 8) left = 8;
    if (left + 200 > screenSize.width) left = screenSize.width - 208;
    if (top < 8) top = 60;

    _contextMenuOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
          color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          child: Padding(
            padding: EdgeInsets.all(isTablet ? 10 : 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Highlight color circles
                ...highlightColors.entries.map((entry) {
                  return GestureDetector(
                    onTap: () {
                      _highlightSelectedText(entry.key);
                      _removeContextMenu();
                    },
                    child: Container(
                      width: isTablet ? 36 : 30,
                      height: isTablet ? 36 : 30,
                      margin:
                          EdgeInsets.symmetric(horizontal: isTablet ? 5 : 4),
                      decoration: BoxDecoration(
                        color: entry.value.withValues(alpha: 1.0),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? Colors.white24 : Colors.black12,
                          width: 1.5,
                        ),
                      ),
                    ),
                  );
                }),
                // Divider
                Container(
                  width: 1,
                  height: isTablet ? 28 : 22,
                  margin: EdgeInsets.symmetric(horizontal: isTablet ? 6 : 4),
                  color: isDark ? Colors.white24 : Colors.black12,
                ),
                // Underline button
                GestureDetector(
                  onTap: () {
                    _underlineSelectedText();
                    _removeContextMenu();
                  },
                  child: Container(
                    width: isTablet ? 36 : 30,
                    height: isTablet ? 36 : 30,
                    margin:
                        EdgeInsets.symmetric(horizontal: isTablet ? 5 : 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white12
                          : Colors.black.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? Colors.white24 : Colors.black12,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.format_underlined,
                      size: isTablet ? 20 : 16,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
                // Add Note button (highlight + open note dialog in one step)
                GestureDetector(
                  onTap: () {
                    _removeContextMenu();
                    _quickHighlightAndNote();
                  },
                  child: Container(
                    width: isTablet ? 36 : 30,
                    height: isTablet ? 36 : 30,
                    margin:
                        EdgeInsets.symmetric(horizontal: isTablet ? 5 : 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white12
                          : Colors.black.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? Colors.white24 : Colors.black12,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.note_add_outlined,
                      size: isTablet ? 20 : 16,
                      color: const Color(0xFF43A047),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(_contextMenuOverlay!);
  }

  void _removeContextMenu() {
    _contextMenuOverlay?.remove();
    _contextMenuOverlay = null;
  }

  /// Highlight the currently selected text; returns the created annotation.
  Future<Annotation?> _highlightSelectedText(String color) async {
    final textLines = _pdfViewerKey.currentState?.getSelectedTextLines();
    if (textLines == null || textLines.isEmpty) return null;

    final highlightColor =
        highlightColors[color] ?? highlightColors['yellow']!;

    // Create annotation
    final annotation = HighlightAnnotation(
      textBoundsCollection: textLines,
    );
    annotation.color = highlightColor;

    _pdfController.addAnnotation(annotation);

    // Save to backend
    if (widget.documentId != null) {
      try {
        final firstLine = textLines.first;
        final lastLine = textLines.last;

        // Collect highlighted text
        final highlightedText = textLines.map((line) => line.text).join(' ');

        // Serialize bounds data for restoration
        final boundsData = textLines
            .map((line) => {
                  'left': line.bounds.left,
                  'top': line.bounds.top,
                  'width': line.bounds.width,
                  'height': line.bounds.height,
                  'text': line.text,
                  'page_number': line.pageNumber,
                })
            .toList();

        final result = await _highlightService.addHighlight(
          documentId: widget.documentId!,
          pageNumber: firstLine.pageNumber,
          startOffset: firstLine.bounds.left.toInt(),
          endOffset: lastLine.bounds.right.toInt(),
          highlightedText: highlightedText.length > 2000
              ? highlightedText.substring(0, 2000)
              : highlightedText,
          color: color,
          boundsData: boundsData,
        );

        // Track the annotation with its backend ID
        final highlightId = result['highlight_id'] as String;
        _highlightAnnotations[highlightId] = annotation;
        _annotationNotes[highlightId] = null;
        _annotationTexts[highlightId] = highlightedText;
      } catch (e) {
        debugPrint('Failed to save highlight: $e');
        if (mounted) {
          showAppDialog(context, message: 'Failed to save highlight', type: AppDialogType.info);
        }
      }
    }

    // Clear selection
    _pdfController.clearSelection();
    return annotation;
  }

  /// Highlight selected text in yellow then immediately open the note dialog.
  Future<void> _quickHighlightAndNote() async {
    final textLines = _pdfViewerKey.currentState?.getSelectedTextLines();
    if (textLines == null || textLines.isEmpty) return;
    final annotation = await _highlightSelectedText('yellow');
    if (annotation != null && mounted) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) _showNoteDialog(annotation);
    }
  }

  // ── Feature 4: Underline Text ─────────────────────────────────────

  Future<void> _underlineSelectedText() async {
    final textLines = _pdfViewerKey.currentState?.getSelectedTextLines();
    if (textLines == null || textLines.isEmpty) return;

    final annotation = UnderlineAnnotation(
      textBoundsCollection: textLines,
    );
    annotation.color = underlineColor;

    _pdfController.addAnnotation(annotation);

    // Save to backend
    if (widget.documentId != null) {
      try {
        final firstLine = textLines.first;
        final lastLine = textLines.last;

        final highlightedText = textLines.map((line) => line.text).join(' ');

        final boundsData = textLines
            .map((line) => {
                  'left': line.bounds.left,
                  'top': line.bounds.top,
                  'width': line.bounds.width,
                  'height': line.bounds.height,
                  'text': line.text,
                  'page_number': line.pageNumber,
                })
            .toList();

        final result = await _highlightService.addHighlight(
          documentId: widget.documentId!,
          pageNumber: firstLine.pageNumber,
          startOffset: firstLine.bounds.left.toInt(),
          endOffset: lastLine.bounds.right.toInt(),
          highlightedText: highlightedText.length > 2000
              ? highlightedText.substring(0, 2000)
              : highlightedText,
          color: 'blue',
          annotationType: 'underline',
          boundsData: boundsData,
        );

        final highlightId = result['highlight_id'] as String;
        _underlineAnnotations[highlightId] = annotation;
        _annotationNotes[highlightId] = null;
        _annotationTexts[highlightId] = highlightedText;
      } catch (e) {
        debugPrint('Failed to save underline: $e');
        if (mounted) {
          showAppDialog(context, message: 'Failed to save underline', type: AppDialogType.info);
        }
      }
    }

    _pdfController.clearSelection();
  }

  // ── Feature 5: Notes on Annotations ───────────────────────────────

  String? _getAnnotationId(Annotation annotation) {
    String? id;
    _highlightAnnotations.forEach((key, ann) {
      if (ann == annotation) id = key;
    });
    if (id == null) {
      _underlineAnnotations.forEach((key, ann) {
        if (ann == annotation) id = key;
      });
    }
    return id;
  }

  /// Show polished bottom sheet menu when a highlight/underline is tapped
  void _showAnnotationMenu(Annotation annotation) {
    _removeContextMenu();

    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    final annotationId = _getAnnotationId(annotation);
    final isUnderline = annotation is UnderlineAnnotation;
    final hasNote =
        annotationId != null && _annotationNotes[annotationId] != null;
    final noteText = hasNote ? _annotationNotes[annotationId] : null;
    final annotationText =
        annotationId != null ? _annotationTexts[annotationId] : null;

    // Determine indicator color
    Color indicatorColor;
    if (isUnderline) {
      indicatorColor = underlineColor;
    } else if (annotation is HighlightAnnotation) {
      indicatorColor = annotation.color.withValues(alpha: 1.0);
    } else {
      indicatorColor = highlightColors['yellow']!.withValues(alpha: 1.0);
    }

    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;
    final subtitleColor =
        isDark ? AppColors.darkTextSecondary : Colors.grey[600]!;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Annotation header with type indicator + text preview
              Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: isTablet ? 44 : 40,
                      height: isTablet ? 44 : 40,
                      decoration: BoxDecoration(
                        color: indicatorColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Icon(
                          isUnderline
                              ? Icons.format_underlined
                              : Icons.border_color,
                          size: isTablet ? 22 : 20,
                          color: indicatorColor,
                        ),
                      ),
                    ),
                    SizedBox(width: isTablet ? 14 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isUnderline ? 'Underline' : 'Highlight',
                            style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontWeight: FontWeight.w600,
                              fontSize: isTablet ? 17 : 15,
                              color: textColor,
                            ),
                          ),
                          if (annotationText != null &&
                              annotationText.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '"${annotationText.length > 80 ? '${annotationText.substring(0, 80)}...' : annotationText}"',
                              style: TextStyle(
                                fontSize: isTablet ? 13 : 12,
                                color: subtitleColor,
                                fontStyle: FontStyle.italic,
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isTablet ? 18 : 16),
              // Note preview card (if note exists)
              if (hasNote && noteText != null) ...[
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isTablet ? 14 : 12),
                    decoration: BoxDecoration(
                      color:
                          AppColors.primaryBlue.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primaryBlue
                            .withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.sticky_note_2_outlined,
                          size: isTablet ? 18 : 16,
                          color: AppColors.primaryBlue,
                        ),
                        SizedBox(width: isTablet ? 10 : 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'YOUR NOTE',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: isTablet ? 11 : 10,
                                  color: AppColors.primaryBlue,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                noteText,
                                style: TextStyle(
                                  fontSize: isTablet ? 14 : 13,
                                  color: textColor,
                                  height: 1.4,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: isTablet ? 12 : 10),
              ],
              Divider(
                height: 1,
                color: isDark
                    ? AppColors.darkDivider
                    : const Color(0xFFF0F0F0),
              ),
              // Add/Edit Note action
              InkWell(
                onTap: () {
                  Navigator.pop(sheetContext);
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted) _showNoteDialog(annotation);
                  });
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 24 : 20,
                    vertical: isTablet ? 16 : 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: isTablet ? 36 : 32,
                        height: isTablet ? 36 : 32,
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          hasNote
                              ? Icons.edit_note
                              : Icons.note_add_outlined,
                          size: isTablet ? 20 : 18,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      SizedBox(width: isTablet ? 14 : 12),
                      Text(
                        hasNote ? 'Edit Note' : 'Add Note',
                        style: TextStyle(
                          fontSize: isTablet ? 16 : 15,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right,
                        size: isTablet ? 22 : 20,
                        color: subtitleColor,
                      ),
                    ],
                  ),
                ),
              ),
              Divider(
                height: 1,
                indent: isTablet ? 70 : 64,
                endIndent: isTablet ? 24 : 20,
                color: isDark
                    ? AppColors.darkDivider
                    : const Color(0xFFF0F0F0),
              ),
              // Remove action
              InkWell(
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removeHighlight(annotation);
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 24 : 20,
                    vertical: isTablet ? 16 : 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: isTablet ? 36 : 32,
                        height: isTablet ? 36 : 32,
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.delete_outline,
                          size: isTablet ? 20 : 18,
                          color: AppColors.error,
                        ),
                      ),
                      SizedBox(width: isTablet ? 14 : 12),
                      Text(
                        isUnderline
                            ? 'Remove Underline'
                            : 'Remove Highlight',
                        style: TextStyle(
                          fontSize: isTablet ? 16 : 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: isTablet ? 8 : 4),
            ],
          ),
        );
      },
    );
  }

  void _showNoteDialog(Annotation annotation) {
    final annotationId = _getAnnotationId(annotation);
    if (annotationId == null) return;

    final existingNote = _annotationNotes[annotationId];
    final controller = TextEditingController(text: existingNote ?? '');
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final isUnderline = annotation is UnderlineAnnotation;
    final annotationText = _annotationTexts[annotationId];

    // Determine accent color for the text preview
    Color accentColor;
    if (isUnderline) {
      accentColor = underlineColor;
    } else if (annotation is HighlightAnnotation) {
      accentColor = annotation.color.withValues(alpha: 1.0);
    } else {
      accentColor = highlightColors['yellow']!.withValues(alpha: 1.0);
    }

    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 20),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Title with icon
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: Row(
                    children: [
                      Icon(
                        existingNote != null
                            ? Icons.edit_note
                            : Icons.note_add_outlined,
                        size: isTablet ? 24 : 22,
                        color: AppColors.primaryBlue,
                      ),
                      SizedBox(width: isTablet ? 10 : 8),
                      Text(
                        existingNote != null ? 'Edit Note' : 'Add Note',
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontWeight: FontWeight.w700,
                          fontSize: isTablet ? 20 : 18,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
                // Highlighted text preview with accent border
                if (annotationText != null &&
                    annotationText.isNotEmpty) ...[
                  SizedBox(height: isTablet ? 14 : 12),
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 24 : 20),
                    child: Container(
                      padding: EdgeInsets.all(isTablet ? 14 : 12),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border(
                          left: BorderSide(
                            color: accentColor,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        annotationText,
                        style: TextStyle(
                          fontSize: isTablet ? 14 : 13,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : Colors.grey[700],
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                SizedBox(height: isTablet ? 16 : 14),
                // Styled text field
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: TextField(
                    controller: controller,
                    maxLines: 4,
                    maxLength: 500,
                    autofocus: true,
                    style: TextStyle(
                      color: textColor,
                      fontSize: isTablet ? 15 : 14,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Write your thoughts...',
                      hintStyle: TextStyle(
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : Colors.grey[400],
                        fontSize: isTablet ? 15 : 14,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? AppColors.darkSurface
                          : const Color(0xFFF8F9FE),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.primaryBlue,
                          width: 1.5,
                        ),
                      ),
                      counterStyle: TextStyle(
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : Colors.grey,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: isTablet ? 18 : 14),
                // Action buttons
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: Row(
                    children: [
                      if (existingNote != null)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _saveAnnotationNote(annotationId, null);
                          },
                          icon:
                              const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Remove'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                          ),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(width: isTablet ? 12 : 8),
                      // Gradient save button
                      Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.blueGradient,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryBlue
                                  .withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              final note = controller.text.trim();
                              _saveAnnotationNote(annotationId,
                                  note.isEmpty ? null : note);
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: isTablet ? 28 : 24,
                                vertical: isTablet ? 12 : 10,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check,
                                    size: isTablet ? 18 : 16,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: isTablet ? 6 : 4),
                                  Text(
                                    'Save',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: isTablet ? 15 : 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isTablet ? 16 : 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveAnnotationNote(
      String annotationId, String? note) async {
    try {
      await _highlightService.updateHighlightNote(annotationId, note);
      if (mounted) {
        setState(() {
          _annotationNotes[annotationId] = note;
        });
      }
    } catch (e) {
      debugPrint('Failed to save note: $e');
      if (mounted) {
        showAppDialog(context, message: 'Failed to save note', type: AppDialogType.info);
      }
    }
  }

  /// Show a bottom sheet with all highlights/notes for this document
  void _showAllNotesPanel() {
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;
    final subtitleColor =
        isDark ? AppColors.darkTextSecondary : Colors.grey[600]!;

    // Combine highlights and underlines into a single list
    final allAnnotationIds = <String>[
      ..._highlightAnnotations.keys,
      ..._underlineAnnotations.keys,
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Title
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sticky_note_2_outlined,
                        size: isTablet ? 24 : 22,
                        color: AppColors.primaryBlue,
                      ),
                      SizedBox(width: isTablet ? 10 : 8),
                      Text(
                        'Your Notes & Highlights',
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontWeight: FontWeight.w700,
                          fontSize: isTablet ? 20 : 18,
                          color: textColor,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${allAnnotationIds.length}',
                        style: TextStyle(
                          fontSize: isTablet ? 15 : 13,
                          color: subtitleColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isTablet ? 12 : 10),
                Divider(
                  height: 1,
                  color:
                      isDark ? AppColors.darkDivider : const Color(0xFFF0F0F0),
                ),
                // List of annotations
                Expanded(
                  child: allAnnotationIds.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.note_alt_outlined,
                                size: isTablet ? 48 : 40,
                                color: subtitleColor,
                              ),
                              SizedBox(height: isTablet ? 12 : 8),
                              Text(
                                'No highlights or notes yet',
                                style: TextStyle(
                                  fontSize: isTablet ? 16 : 14,
                                  color: subtitleColor,
                                ),
                              ),
                              SizedBox(height: isTablet ? 6 : 4),
                              Text(
                                'Long press on text to highlight it',
                                style: TextStyle(
                                  fontSize: isTablet ? 13 : 12,
                                  color: subtitleColor,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: EdgeInsets.symmetric(
                            vertical: isTablet ? 10 : 8,
                          ),
                          itemCount: allAnnotationIds.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: isTablet ? 70 : 60,
                            endIndent: isTablet ? 24 : 20,
                            color: isDark
                                ? AppColors.darkDivider
                                : const Color(0xFFF0F0F0),
                          ),
                          itemBuilder: (context, index) {
                            final id = allAnnotationIds[index];
                            final isHighlight =
                                _highlightAnnotations.containsKey(id);
                            final annotation = isHighlight
                                ? _highlightAnnotations[id]!
                                : _underlineAnnotations[id]!;
                            final highlightedText =
                                _annotationTexts[id] ?? '';
                            final note = _annotationNotes[id];
                            final hasNote =
                                note != null && note.isNotEmpty;

                            Color accentColor;
                            if (!isHighlight) {
                              accentColor = underlineColor;
                            } else if (annotation is HighlightAnnotation) {
                              accentColor =
                                  annotation.color.withValues(alpha: 1.0);
                            } else {
                              accentColor = highlightColors['yellow']!
                                  .withValues(alpha: 1.0);
                            }

                            return InkWell(
                              onTap: () {
                                Navigator.pop(sheetContext);
                                Future.delayed(
                                    const Duration(milliseconds: 300), () {
                                  if (mounted) _showNoteDialog(annotation);
                                });
                              },
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 24 : 20,
                                  vertical: isTablet ? 14 : 12,
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // Color indicator
                                    Container(
                                      width: isTablet ? 36 : 30,
                                      height: isTablet ? 36 : 30,
                                      margin: EdgeInsets.only(
                                          right: isTablet ? 14 : 10),
                                      decoration: BoxDecoration(
                                        color: accentColor
                                            .withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isHighlight
                                            ? Icons.border_color
                                            : Icons.format_underlined,
                                        size: isTablet ? 18 : 16,
                                        color: accentColor,
                                      ),
                                    ),
                                    // Text content
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            highlightedText,
                                            style: TextStyle(
                                              fontSize:
                                                  isTablet ? 14 : 13,
                                              color: textColor,
                                              fontStyle:
                                                  FontStyle.italic,
                                              height: 1.3,
                                            ),
                                            maxLines: 2,
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                          if (hasNote) ...[
                                            SizedBox(
                                                height:
                                                    isTablet ? 6 : 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons
                                                      .sticky_note_2_outlined,
                                                  size:
                                                      isTablet ? 14 : 12,
                                                  color:
                                                      AppColors.primaryBlue,
                                                ),
                                                SizedBox(
                                                    width:
                                                        isTablet ? 6 : 4),
                                                Expanded(
                                                  child: Text(
                                                    note,
                                                    style: TextStyle(
                                                      fontSize: isTablet
                                                          ? 13
                                                          : 12,
                                                      color:
                                                          AppColors.primaryBlue,
                                                      height: 1.3,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow
                                                        .ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ] else ...[
                                            SizedBox(
                                                height:
                                                    isTablet ? 4 : 2),
                                            Text(
                                              'Tap to add note',
                                              style: TextStyle(
                                                fontSize:
                                                    isTablet ? 12 : 11,
                                                color: subtitleColor,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    // Chevron
                                    Icon(
                                      Icons.chevron_right,
                                      size: isTablet ? 20 : 18,
                                      color: subtitleColor,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Remove a highlight/underline annotation and delete from backend
  Future<void> _removeHighlight(Annotation annotation) async {
    _pdfController.removeAnnotation(annotation);
  }

  /// Handle annotation removal — delete from backend
  Future<void> _handleAnnotationRemoved(Annotation annotation) async {
    String? annotationId;
    _highlightAnnotations.forEach((id, ann) {
      if (ann == annotation) annotationId = id;
    });
    if (annotationId == null) {
      _underlineAnnotations.forEach((id, ann) {
        if (ann == annotation) annotationId = id;
      });
    }

    if (annotationId != null) {
      try {
        await _highlightService.deleteHighlight(annotationId!);
        _highlightAnnotations.remove(annotationId);
        _underlineAnnotations.remove(annotationId);
        _annotationNotes.remove(annotationId);
        _annotationTexts.remove(annotationId);
      } catch (e) {
        debugPrint('Failed to delete annotation from backend: $e');
      }
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearchOpen = !_isSearchOpen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;
    final toolbarColor = isDark ? AppColors.darkCardBackground : Colors.white;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: backgroundColor,
      endDrawer: widget.documentId != null
          ? BookmarksDrawer(
              bookmarkedPages: _bookmarkedPages,
              bookmarkNotes: _bookmarkNotes,
              isDark: isDark,
              isTablet: isTablet,
              onJumpToPage: (page) {
                _scaffoldKey.currentState?.closeEndDrawer();
                _pdfController.jumpToPage(page);
              },
              onDeleteBookmark: (bookmarkId, pageNumber) async {
                try {
                  await _bookmarkService.deleteBookmark(bookmarkId);
                  if (mounted) {
                    setState(() {
                      _bookmarkedPages.remove(pageNumber);
                      _bookmarkNotes.remove(bookmarkId);
                    });
                  }
                } catch (e) {
                  if (mounted) {
                    showAppDialog(context, message: 'Failed to delete bookmark', type: AppDialogType.info);
                  }
                }
              },
              onUpdateNote: (bookmarkId, note) async {
                try {
                  await _bookmarkService.updateBookmarkNote(
                      bookmarkId, note);
                  if (mounted) {
                    setState(() {
                      _bookmarkNotes[bookmarkId] = note;
                    });
                  }
                } catch (e) {
                  if (mounted) {
                    showAppDialog(context, message: 'Failed to update bookmark note', type: AppDialogType.info);
                  }
                }
              },
            )
          : null,
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: toolbarColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
                .copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark
                .copyWith(statusBarColor: Colors.transparent),
      ),
      body: _error != null
          ? _buildErrorView(isTablet, textColor)
          : _isLoading
              ? _buildLoadingView(isTablet)
              : Stack(
                  children: [
                    Column(
                      children: [
                        // Toolbar
                        _buildToolbar(
                            isDark, textColor, toolbarColor, isTablet),

                        // PDF Viewer
                        Expanded(
                          child: _buildPdfViewer(),
                        ),
                      ],
                    ),
                    // Quick action buttons (left side, toggle on single tap)
                    if (_isPdfReady)
                      Positioned(
                        left: 8,
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          ignoring: !_showQuickActions,
                          child: AnimatedOpacity(
                            opacity: _showQuickActions ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 300),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.black.withValues(alpha: 0.55)
                                      : Colors.white.withValues(alpha: 0.88),
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.18),
                                      blurRadius: 8,
                                      offset: const Offset(1, 2),
                                    ),
                                  ],
                                ),
                                padding: EdgeInsets.symmetric(
                                  vertical: isTablet ? 10 : 8,
                                  horizontal: isTablet ? 6 : 4,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildQuickActionButton(
                                      icon: Icons.border_color,
                                      color: const Color(0xFFFFEB3B),
                                      tooltip: 'Highlight',
                                      onTap: () => _highlightSelectedText('yellow'),
                                      isDark: isDark,
                                      isTablet: isTablet,
                                    ),
                                    SizedBox(height: isTablet ? 8 : 6),
                                    _buildQuickActionButton(
                                      icon: Icons.format_underlined,
                                      color: const Color(0xFF1565C0),
                                      tooltip: 'Underline',
                                      onTap: _underlineSelectedText,
                                      isDark: isDark,
                                      isTablet: isTablet,
                                    ),
                                    SizedBox(height: isTablet ? 8 : 6),
                                    _buildQuickActionButton(
                                      icon: Icons.sticky_note_2_outlined,
                                      color: const Color(0xFF43A047),
                                      tooltip: 'Notes',
                                      onTap: _showAllNotesPanel,
                                      isDark: isDark,
                                      isTablet: isTablet,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Loading overlay while PDF is parsing — fades out quickly
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: _isPdfReady,
                        child: AnimatedOpacity(
                          opacity: _isPdfReady ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            color: isDark
                                ? AppColors.darkBackground
                                : Colors.white,
                            child: Center(
                              child: const CircularProgressIndicator(
                                color: AppColors.primaryBlue,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildPdfViewer() {
    Widget viewer = SfPdfViewer.file(
      File(_localPath!),
      key: _pdfViewerKey,
      controller: _pdfController,
      canShowTextSelectionMenu: false,
      onTap: (PdfGestureDetails details) {
        _removeContextMenu();
        // Only toggle if no annotation is currently selected
        if (!_isAnnotationSelected) {
          setState(() {
            _showQuickActions = !_showQuickActions;
          });
        }
      },
      onDocumentLoaded: (PdfDocumentLoadedDetails details) {
        if (!_isPdfReady) {
          setState(() {
            _isPdfReady = true;
          });
        }
        _loadHighlights();
        _loadBookmarks();
        _restoreProgress();
      },
      onPageChanged: (PdfPageChangedDetails details) {
        _currentPage.value = details.newPageNumber;
        _debouncedSaveProgress(details.newPageNumber);
      },
      onTextSelectionChanged: (PdfTextSelectionChangedDetails details) {
        if (details.selectedText != null &&
            details.selectedText!.isNotEmpty) {
          if (details.globalSelectedRegion != null) {
            _showContextMenu(Offset(
              details.globalSelectedRegion!.center.dx,
              details.globalSelectedRegion!.top,
            ));
          }
        } else {
          _removeContextMenu();
        }
      },
      onAnnotationSelected: (Annotation annotation) {
        _isAnnotationSelected = true;
        _showAnnotationMenu(annotation);
      },
      onAnnotationDeselected: (Annotation annotation) {
        _isAnnotationSelected = false;
        _removeContextMenu();
      },
      onAnnotationRemoved: (Annotation annotation) {
        _handleAnnotationRemoved(annotation);
      },
    );

    // Feature 3: PDF dark mode via color inversion
    if (_isPdfDarkMode) {
      viewer = ColorFiltered(
        colorFilter: _invertColorFilter,
        child: viewer,
      );
    }

    return viewer;
  }

  Widget _buildToolbar(
      bool isDark, Color textColor, Color toolbarColor, bool isTablet) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 16 : 12,
          vertical: isTablet ? 12 : 8,
        ),
        decoration: BoxDecoration(
          color: toolbarColor,
          border: Border(
            bottom: BorderSide(
              color: isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0),
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Back button
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    width: isTablet ? 44 : 36,
                    height: isTablet ? 44 : 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? AppColors.darkSurface
                          : const Color(0xFFF5F5F5),
                    ),
                    child: Icon(
                      Icons.arrow_back,
                      size: isTablet ? 22 : 18,
                      color: textColor,
                    ),
                  ),
                ),
                SizedBox(width: isTablet ? 12 : 8),
                // Title
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 18 : 15,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Bookmark toggle button (only for auth documents)
                if (widget.documentId != null) ...[
                  ValueListenableBuilder<int>(
                    valueListenable: _currentPage,
                    builder: (context, currentPage, _) {
                      final isBookmarked = _bookmarkedPages.containsKey(currentPage);
                      return GestureDetector(
                        onTap: _toggleBookmark,
                        child: Container(
                          width: isTablet ? 44 : 36,
                          height: isTablet ? 44 : 36,
                          margin: EdgeInsets.only(right: isTablet ? 4 : 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isBookmarked
                                ? AppColors.primaryBlue.withValues(alpha: 0.1)
                                : (isDark
                                    ? AppColors.darkSurface
                                    : const Color(0xFFF5F5F5)),
                          ),
                          child: Icon(
                            isBookmarked
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            size: isTablet ? 22 : 18,
                            color: isBookmarked
                                ? AppColors.primaryBlue
                                : textColor,
                          ),
                        ),
                      );
                    },
                  ),
                  // Bookmarks list button (show when bookmarks exist)
                  if (_bookmarkedPages.isNotEmpty)
                    GestureDetector(
                      onTap: () =>
                          _scaffoldKey.currentState?.openEndDrawer(),
                      child: Container(
                        width: isTablet ? 44 : 36,
                        height: isTablet ? 44 : 36,
                        margin: EdgeInsets.only(right: isTablet ? 4 : 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? AppColors.darkSurface
                              : const Color(0xFFF5F5F5),
                        ),
                        child: Icon(
                          Icons.collections_bookmark_outlined,
                          size: isTablet ? 22 : 18,
                          color: textColor,
                        ),
                      ),
                    ),
                ],
                // PDF dark mode toggle
                GestureDetector(
                  onTap: () =>
                      setState(() => _isPdfDarkMode = !_isPdfDarkMode),
                  child: Container(
                    width: isTablet ? 44 : 36,
                    height: isTablet ? 44 : 36,
                    margin: EdgeInsets.only(right: isTablet ? 4 : 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isPdfDarkMode
                          ? AppColors.primaryBlue.withValues(alpha: 0.1)
                          : (isDark
                              ? AppColors.darkSurface
                              : const Color(0xFFF5F5F5)),
                    ),
                    child: Icon(
                      _isPdfDarkMode ? Icons.light_mode : Icons.dark_mode,
                      size: isTablet ? 22 : 18,
                      color:
                          _isPdfDarkMode ? AppColors.primaryBlue : textColor,
                    ),
                  ),
                ),
                // Search button
                GestureDetector(
                  onTap: _toggleSearch,
                  child: Container(
                    width: isTablet ? 44 : 36,
                    height: isTablet ? 44 : 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isSearchOpen
                          ? AppColors.primaryBlue.withValues(alpha: 0.1)
                          : (isDark
                              ? AppColors.darkSurface
                              : const Color(0xFFF5F5F5)),
                    ),
                    child: Icon(
                      _isSearchOpen ? Icons.close : Icons.search,
                      size: isTablet ? 22 : 18,
                      color:
                          _isSearchOpen ? AppColors.primaryBlue : textColor,
                    ),
                  ),
                ),
              ],
            ),
            // Search bar
            if (_isSearchOpen) ...[
              SizedBox(height: isTablet ? 10 : 8),
              _buildSearchBar(isDark, textColor, isTablet),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark, Color textColor, bool isTablet) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            autofocus: true,
            style: TextStyle(fontSize: isTablet ? 16 : 14, color: textColor),
            decoration: InputDecoration(
              hintText: 'Search in notes...',
              hintStyle: TextStyle(
                color: isDark ? AppColors.darkTextSecondary : Colors.grey,
                fontSize: isTablet ? 16 : 14,
              ),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: isTablet ? 16 : 12,
                vertical: isTablet ? 12 : 10,
              ),
              filled: true,
              fillColor:
                  isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (value) {
              if (value.isNotEmpty) {
                _searchResult?.dispose();
                _searchResult = _pdfController.searchText(value);
              }
            },
          ),
        ),
        if (_searchResult != null) ...[
          SizedBox(width: isTablet ? 8 : 4),
          GestureDetector(
            onTap: () => _searchResult?.previousInstance(),
            child: Icon(Icons.keyboard_arrow_up,
                size: isTablet ? 28 : 24, color: textColor),
          ),
          GestureDetector(
            onTap: () => _searchResult?.nextInstance(),
            child: Icon(Icons.keyboard_arrow_down,
                size: isTablet ? 28 : 24, color: textColor),
          ),
        ],
      ],
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
    required bool isDark,
    required bool isTablet,
  }) {
    final size = isTablet ? 44.0 : 36.0;
    final iconSize = isTablet ? 22.0 : 18.0;
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.22 : 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: iconSize, color: color),
        ),
      ),
    );
  }

  Widget _buildErrorView(bool isTablet, Color textColor) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: isTablet ? 64 : 48, color: Colors.grey),
          SizedBox(height: isTablet ? 21 : 16),
          Text(_error!,
              style:
                  TextStyle(fontSize: isTablet ? 20 : 16, color: textColor)),
          SizedBox(height: isTablet ? 21 : 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _error = null;
                _isLoading = true;
                _downloadProgress = 0;
              });
              _loadPdf();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingView(bool isTablet) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
              value: _downloadProgress > 0 ? _downloadProgress : null),
          if (_downloadProgress > 0) ...[
            SizedBox(height: isTablet ? 21 : 16),
            Text(
              '${(_downloadProgress * 100).toInt()}%',
              style: TextStyle(
                  fontSize: isTablet ? 17 : 14, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}

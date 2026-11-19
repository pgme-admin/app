import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:pgme/core_ios/constants/api_constants.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/services/api_service.dart';
import 'package:pgme/core_ios/services/bookmark_service.dart';
import 'package:pgme/core_ios/services/highlight_service.dart';
import 'package:pgme/core_ios/services/download_service.dart';
import 'package:pgme/core_ios/services/progress_service.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:pgme/core_ios/widgets/app_dialog.dart';
import 'package:pgme/core/providers/mini_player_provider.dart';
import 'package:pgme/features_ios/notes/widgets/bookmarks_drawer.dart';

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

  /// Set to 'ebook' when launched from EbookAccessService — skips progress
  /// save/restore (backend has no progress endpoint for ebook IDs).
  final String? source;

  const PdfViewerScreen({
    super.key,
    this.documentId,
    this.pdfUrl,
    this.filePath,
    this.title = 'PDF Viewer',
    this.source,
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

  // Store text bounds per annotation for reliable toggle matching
  // (Syncfusion does not re-expose textBoundsCollection after construction)
  final Map<String, List<PdfTextLine>> _annotationTextBounds = {};

  // Context menu overlay (for highlight color picker + delete)
  OverlayEntry? _contextMenuOverlay;

  // Feature 1: Bookmarks — pageNumber -> bookmarkId
  final Map<int, String> _bookmarkedPages = {};
  // Bookmark notes: bookmarkId -> note
  final Map<String, String?> _bookmarkNotes = {};

  // Feature 2: Progress tracking
  final ValueNotifier<int> _currentPage = ValueNotifier(1);
  Timer? _progressDebounceTimer;
  Timer? _contextMenuDebounce;

  // Feature 3: PDF content dark mode
  bool _isPdfDarkMode = false;

  // Keep screen on while reading
  bool _keepScreenOn = false;

  // Orientation lock
  bool _orientationLocked = false;

  // Standalone notes (annotation_type: 'note') — noteId -> {page, note}
  final Map<String, Map<String, dynamic>> _standaloneNotes = {};

  // Undo stack — stores annotation IDs + types for multi-level undo
  final List<({String id, String type})> _undoStack = [];

  // Guards against duplicate loads from multiple onDocumentLoaded calls
  bool _highlightsLoaded = false;
  bool _bookmarksLoaded = false;

  // Cached PDF viewer widget — prevents rebuilds when parent calls setState
  Widget? _cachedPdfViewer;

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
    // Allow rotation in PDF viewer
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Free RAM for the PDF: kill any active video player BEFORE Syncfusion
    // starts allocating. A 60MB textbook + a live ExoPlayer + image cache
    // pushes mid-tier Android tablets past their per-app heap cap → ANR.
    try {
      final miniProvider =
          Provider.of<MiniPlayerProvider>(context, listen: false);
      if (miniProvider.isActive) miniProvider.close();
    } catch (_) {}
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

  // Cached in didChangeDependencies so dispose() never touches MediaQuery.
  bool _restorePortraitOnDispose = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restorePortraitOnDispose = MediaQuery.sizeOf(context).shortestSide < 600;
  }

  @override
  void dispose() {
    _contextMenuOverlay?.remove();
    _contextMenuOverlay = null;
    _contextMenuDebounce?.cancel();
    // Save final progress before disposing — capture values before dispose
    _progressDebounceTimer?.cancel();
    final documentId = widget.documentId;
    final lastPage = _currentPage.value;
    if (documentId != null && lastPage > 0) {
      // Fire-and-forget: use a captured reference so no widget state is accessed
      _progressService.updateDocumentProgress(
        documentId: documentId,
        pageNumber: lastPage,
      );
    }
    if (_keepScreenOn) WakelockPlus.disable();
    // Restore portrait-only for non-tablet devices. Uses the value cached in
    // didChangeDependencies: MediaQuery.of(context) is not allowed in dispose()
    // (the element is already deactivated) and used to throw here, skipping
    // the orientation reset.
    if (_restorePortraitOnDispose) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    _currentPage.dispose();
    _pdfController.dispose();
    _searchResult?.dispose();
    super.dispose();
  }

  Future<void> _loadPdf() async {
    debugPrint(
        '[PDF-DBG] sync._loadPdf ENTRY documentId=${widget.documentId} '
        'pdfUrl=${widget.pdfUrl != null ? '(${widget.pdfUrl!.length} chars)' : 'null'} '
        'filePath=${widget.filePath} source=${widget.source}');
    try {
      // If a local file path is provided, use it directly (e.g. invoice PDF)
      if (widget.filePath != null) {
        debugPrint(
            '[PDF-DBG] sync._loadPdf branch=DIRECT_FILE_PATH path=${widget.filePath}');
        await _logFileForensics(widget.filePath!, 'sync.DIRECT_FILE_PATH');
        if (mounted) {
          setState(() {
            _localPath = widget.filePath;
            _isLoading = false;
          });
        }
        return;
      }

      // Check for permanently downloaded file first
      if (widget.documentId != null) {
        final docFileName = 'doc_${widget.documentId}.pdf';
        final ebookFileName = 'ebook_${widget.documentId}.pdf';
        final downloadedPath =
            await DownloadService().getDownloadedPath(docFileName) ??
                await DownloadService().getDownloadedPath(ebookFileName);
        if (downloadedPath != null) {
          // Verify file is valid (non-empty)
          final file = File(downloadedPath);
          final fileSize = await file.length();
          debugPrint(
              '[PDF-DBG] sync._loadPdf branch=DOWNLOADED_FILE '
              'path=$downloadedPath size=$fileSize');
          if (fileSize > 0 && mounted) {
            await _logFileForensics(downloadedPath, 'sync.DOWNLOADED_FILE');
            setState(() {
              _localPath = downloadedPath;
              _isLoading = false;
            });
            return;
          }
          debugPrint(
              '[PDF-DBG] sync._loadPdf downloaded file present but empty');
        } else {
          debugPrint(
              '[PDF-DBG] sync._loadPdf no downloaded copy for documentId='
              '${widget.documentId}');
        }
      }

      String pdfUrl;

      if (widget.pdfUrl != null) {
        pdfUrl = widget.pdfUrl!;
        debugPrint('[PDF-DBG] sync._loadPdf url=FROM_WIDGET');
      } else {
        debugPrint('[PDF-DBG] sync._loadPdf url=RESOLVING via documentViewUrl');
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
        final cachedSize = await file.length();
        debugPrint(
            '[PDF-DBG] sync._loadPdf branch=TEMP_CACHE_HIT '
            'path=$filePath size=$cachedSize');
        await _logFileForensics(filePath, 'sync.TEMP_CACHE_HIT');
        if (mounted) {
          setState(() {
            _localPath = filePath;
            _isLoading = false;
          });
        }
        return;
      }

      debugPrint(
          '[PDF-DBG] sync._loadPdf branch=TEMP_DOWNLOAD target=$filePath '
          'urlLen=${pdfUrl.length}');
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
      await _logFileForensics(filePath, 'sync.TEMP_DOWNLOAD complete');

      if (mounted) {
        setState(() {
          _localPath = filePath;
          _isLoading = false;
        });
      }
    } catch (e, st) {
      debugPrint('[PDF-DBG] sync._loadPdf EXCEPTION err=$e');
      debugPrint('[PDF-DBG] stack: $st');
      if (mounted) {
        setState(() {
          _error = 'Failed to load PDF';
          _isLoading = false;
        });
      }
    }
  }

  /// Read first bytes of [path] and log size + magic header. Used by the
  /// loader to surface why SfPdfViewer might fail to open a file that was
  /// just handed to it — the viewer only exposes an opaque
  /// onDocumentLoadFailed callback without raw bytes context.
  Future<void> _logFileForensics(String path, String stage) async {
    try {
      final f = File(path);
      final exists = await f.exists();
      final size = exists ? await f.length() : -1;
      String magic = '<no-file>';
      String headSnippet = '';
      if (exists && size > 0) {
        final raf = await f.open();
        try {
          final bytes = await raf.read(8);
          final buf = StringBuffer();
          for (final b in bytes) {
            if (b >= 0x20 && b < 0x7F) {
              buf.writeCharCode(b);
            } else {
              buf.write('\\x${b.toRadixString(16).padLeft(2, '0')}');
            }
          }
          magic = buf.toString();
          if (!magic.startsWith('%PDF')) {
            await raf.setPosition(0);
            final head = await raf.read(200);
            final hb = StringBuffer();
            for (final b in head) {
              if (b == 0x0A) {
                hb.write('\\n');
              } else if (b == 0x0D) {
                hb.write('\\r');
              } else if (b >= 0x20 && b < 0x7F) {
                hb.writeCharCode(b);
              } else {
                hb.write('.');
              }
            }
            headSnippet = ' headSnippet=$hb';
          }
        } finally {
          await raf.close();
        }
      }
      debugPrint(
          '[PDF-DBG] $stage path=$path exists=$exists size=$size '
          'magic="$magic" isPdf=${magic.startsWith('%PDF')}$headSnippet');
    } catch (e) {
      debugPrint('[PDF-DBG] $stage forensics error: $e');
    }
  }

  // ── Feature 2: Continue Where Left Off ─────────────────────────────

  Future<void> _restoreProgress() async {
    if (widget.documentId == null) return;
    if (widget.source == 'ebook') return;
    try {
      final progress =
          await _progressService.getDocumentProgress(widget.documentId!);
      final savedPage = progress['page_number'] as int? ?? 1;
      if (savedPage > 1 && mounted) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          _pdfController.jumpToPage(savedPage);
        }
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
    if (widget.source == 'ebook') return;
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
    if (widget.documentId == null || _bookmarksLoaded) return;
    _bookmarksLoaded = true;
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
      final savedNote = _bookmarkNotes[bookmarkId];
      setState(() {
        _bookmarkedPages.remove(page);
        _bookmarkNotes.remove(bookmarkId);
      });
      try {
        await _bookmarkService.deleteBookmark(bookmarkId);
      } catch (e) {
        // Restore on failure — including the note
        if (mounted) {
          setState(() {
            _bookmarkedPages[page] = bookmarkId;
            _bookmarkNotes[bookmarkId] = savedNote;
          });
          showAppDialog(context, message: 'Failed to remove bookmark', type: AppDialogType.info);
        }
      }
    } else {
      // Add bookmark
      try {
        debugPrint('[BOOKMARK] Adding bookmark: documentId=${widget.documentId}, page=$page');
        final result = await _bookmarkService.addBookmark(
          documentId: widget.documentId!,
          pageNumber: page,
        );
        debugPrint('[BOOKMARK] Success: ${result.toString()}');
        if (mounted) {
          setState(() {
            final bookmarkId = result['bookmark_id'] as String;
            _bookmarkedPages[page] = bookmarkId;
            _bookmarkNotes[bookmarkId] = result['note'] as String?;
          });
        }
      } catch (e) {
        debugPrint('[BOOKMARK] Failed: $e');
        if (mounted) {
          showAppDialog(context, message: 'Failed to add bookmark', type: AppDialogType.info);
        }
      }
    }
  }

  // ── Highlights & Underlines ───────────────────────────────────────

  /// Load saved highlights/underlines from backend and apply as annotations
  Future<void> _loadHighlights() async {
    if (widget.documentId == null || _highlightsLoaded) return;
    _highlightsLoaded = true;

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

          // Standalone notes have no bounds — just track in _standaloneNotes
          if (annotationType == 'note') {
            _standaloneNotes[highlightId] = {
              'page_number': h['page_number'] as int? ?? 1,
              'note': note ?? '',
            };
            continue;
          }

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

          // Track note, text, and bounds for toggle matching
          _annotationNotes[highlightId] = note;
          _annotationTexts[highlightId] =
              (h['highlighted_text'] as String?) ?? '';
          _annotationTextBounds[highlightId] = textLines;
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

    final safePadding = MediaQuery.of(context).padding;
    // Menu is 4 color circles + divider + underline + note button + padding
    final menuWidth = isTablet ? 310.0 : 260.0;
    final menuHeight = isTablet ? 56.0 : 46.0;

    // Center menu on selection, clamped to screen bounds
    double left = position.dx - menuWidth / 2;
    double top = position.dy - menuHeight - 12;

    // Horizontal: keep within safe area + margin
    final minLeft = safePadding.left + 8;
    final maxLeft = screenSize.width - safePadding.right - menuWidth - 8;
    left = left.clamp(minLeft, maxLeft);

    // Vertical: if clipped at top, flip below the selection
    if (top < safePadding.top + 8) {
      top = position.dy + 12;
    }
    // If clipped at bottom, push up
    if (top + menuHeight > screenSize.height - safePadding.bottom - 8) {
      top = screenSize.height - safePadding.bottom - menuHeight - 8;
    }

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
    _contextMenuDebounce?.cancel();
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
        _annotationTextBounds[highlightId] = textLines;
        _undoStack.add((id: highlightId, type: 'highlight'));
        setState(() {});
      } catch (e) {
        debugPrint('Failed to save highlight: $e');
        // Remove the annotation since it wasn't persisted — prevents ghost annotations
        _pdfController.removeAnnotation(annotation);
        if (mounted) {
          showAppDialog(context, message: 'Failed to save highlight', type: AppDialogType.info);
        }
        _pdfController.clearSelection();
        return null;
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

    // Toggle: if selected text exactly matches an existing underline, remove it.
    final selectedText = textLines.map((l) => l.text).join(' ').trim();
    for (final entry in _underlineAnnotations.entries) {
      final storedText = _annotationTexts[entry.key]?.trim();
      if (storedText != null && storedText == selectedText) {
        _pdfController.clearSelection();
        _removeHighlight(entry.value);
        return;
      }
    }

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
        _annotationTextBounds[highlightId] = textLines;
        _undoStack.add((id: highlightId, type: 'underline'));
        setState(() {});
      } catch (e) {
        debugPrint('Failed to save underline: $e');
        // Remove the annotation since it wasn't persisted — prevents ghost annotations
        _pdfController.removeAnnotation(annotation);
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

  // ── Overflow menu ──────────────────────────────────────────────────

  /// Three-dot popup menu in the toolbar holding less-frequently used
  /// toggles (keep-screen-on, lock-rotation, PDF dark mode). Each entry's
  /// onTap toggles the underlying state and rebuilds the toolbar — the
  /// popup itself closes automatically after a selection.
  Widget _buildOverflowMenu(bool isDark, Color textColor, bool isTablet) {
    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Container(
        width: isTablet ? 44 : 36,
        height: isTablet ? 44 : 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5),
        ),
        child: Icon(
          Icons.more_vert,
          size: isTablet ? 22 : 18,
          color: textColor,
        ),
      ),
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: (value) {
        switch (value) {
          case 'keep_screen_on':
            setState(() => _keepScreenOn = !_keepScreenOn);
            if (_keepScreenOn) {
              WakelockPlus.enable();
            } else {
              WakelockPlus.disable();
            }
            break;
          case 'lock_rotation':
            setState(() => _orientationLocked = !_orientationLocked);
            if (_orientationLocked) {
              final orientation = MediaQuery.of(context).orientation;
              if (orientation == Orientation.landscape) {
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]);
              } else {
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.portraitUp,
                  DeviceOrientation.portraitDown,
                ]);
              }
            } else {
              SystemChrome.setPreferredOrientations([
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]);
            }
            break;
          case 'dark_mode':
            setState(() => _isPdfDarkMode = !_isPdfDarkMode);
            break;
        }
      },
      itemBuilder: (context) => [
        _buildOverflowItem(
          value: 'keep_screen_on',
          icon: _keepScreenOn ? Icons.lightbulb : Icons.lightbulb_outline,
          label: _keepScreenOn ? 'Screen always on' : 'Keep screen on',
          active: _keepScreenOn,
          textColor: textColor,
        ),
        _buildOverflowItem(
          value: 'lock_rotation',
          icon: _orientationLocked
              ? Icons.screen_lock_rotation
              : Icons.screen_rotation,
          label: _orientationLocked ? 'Unlock rotation' : 'Lock rotation',
          active: _orientationLocked,
          textColor: textColor,
        ),
        _buildOverflowItem(
          value: 'dark_mode',
          icon: _isPdfDarkMode ? Icons.light_mode : Icons.dark_mode,
          label: _isPdfDarkMode ? 'Light mode' : 'Dark mode',
          active: _isPdfDarkMode,
          textColor: textColor,
        ),
      ],
    );
  }

  PopupMenuItem<String> _buildOverflowItem({
    required String value,
    required IconData icon,
    required String label,
    required bool active,
    required Color textColor,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: active ? AppColors.primaryBlue : textColor,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: active ? AppColors.primaryBlue : textColor,
            ),
          ),
        ],
      ),
    );
  }

  // ── Go to page ─────────────────────────────────────────────────────

  /// Replaces Syncfusion's built-in pagination dialog (disabled above).
  /// Triggered by the page-indicator badge in the toolbar.
  void _showGoToPageDialog() {
    final totalPages = _pdfController.pageCount;
    if (totalPages <= 0) return;
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;
    final controller =
        TextEditingController(text: _currentPage.value.toString());

    showDialog<void>(
      context: context,
      builder: (ctx) {
        void submit() {
          final n = int.tryParse(controller.text.trim());
          if (n == null || n < 1 || n > totalPages) {
            ScaffoldMessenger.of(ctx)
              ..clearSnackBars()
              ..showSnackBar(SnackBar(
                content: Text('Enter a page number between 1 and $totalPages'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ));
            return;
          }
          Navigator.pop(ctx);
          _pdfController.jumpToPage(n);
        }

        return AlertDialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('Go to page',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontWeight: FontWeight.w700,
                fontSize: isTablet ? 19 : 17,
                color: textColor,
              )),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            onSubmitted: (_) => submit(),
            style: TextStyle(color: textColor, fontSize: isTablet ? 16 : 15),
            decoration: InputDecoration(
              hintText: 'Page number (1–$totalPages)',
              hintStyle: TextStyle(
                color: isDark ? Colors.white38 : Colors.grey[400],
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
                    color: AppColors.primaryBlue, width: 1.5),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  )),
            ),
            ElevatedButton(
              onPressed: submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('Go'),
            ),
          ],
        );
      },
    );
  }

  /// Show a bottom sheet with all highlights/notes for this document
  // ── Standalone notes ───────────────────────────────────────────────

  void _showAddStandaloneNoteDialog(StateSetter setSheetState) {
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;
    final pageController = TextEditingController();
    final noteController = TextEditingController();
    final totalPages = _pdfController.pageCount;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 20),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: Text('Add Note',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontWeight: FontWeight.w700,
                        fontSize: isTablet ? 20 : 18,
                        color: textColor,
                      )),
                ),
                SizedBox(height: isTablet ? 16 : 12),
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: TextField(
                    controller: pageController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textColor, fontSize: isTablet ? 15 : 14),
                    decoration: InputDecoration(
                      hintText: 'Page number (1-$totalPages)',
                      hintStyle: TextStyle(
                        color: isDark ? AppColors.darkTextTertiary : Colors.grey[400],
                        fontSize: isTablet ? 15 : 14,
                      ),
                      filled: true,
                      fillColor: isDark ? AppColors.darkSurface : const Color(0xFFF8F9FE),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: isTablet ? 12 : 8),
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: TextField(
                    controller: noteController,
                    maxLines: 4,
                    maxLength: 500,
                    autofocus: true,
                    style: TextStyle(color: textColor, fontSize: isTablet ? 15 : 14, height: 1.5),
                    decoration: InputDecoration(
                      hintText: 'Write your note...',
                      hintStyle: TextStyle(
                        color: isDark ? AppColors.darkTextTertiary : Colors.grey[400],
                        fontSize: isTablet ? 15 : 14,
                      ),
                      filled: true,
                      fillColor: isDark ? AppColors.darkSurface : const Color(0xFFF8F9FE),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
                      ),
                      counterStyle: TextStyle(
                        color: isDark ? AppColors.darkTextTertiary : Colors.grey,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: isTablet ? 16 : 12),
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancel',
                            style: TextStyle(
                              color: isDark ? AppColors.darkTextSecondary : Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            )),
                      ),
                      SizedBox(width: isTablet ? 12 : 8),
                      Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.blueGradient,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () {
                              final pageNum = int.tryParse(pageController.text.trim());
                              final note = noteController.text.trim();
                              if (pageNum == null || pageNum < 1 || pageNum > totalPages) {
                                showAppDialog(context,
                                    message: 'Enter a valid page number (1-$totalPages)',
                                    type: AppDialogType.info);
                                return;
                              }
                              if (note.isEmpty) {
                                showAppDialog(context,
                                    message: 'Note cannot be empty',
                                    type: AppDialogType.info);
                                return;
                              }
                              Navigator.pop(ctx);
                              _saveStandaloneNote(pageNum, note, setSheetState);
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 28 : 24,
                                  vertical: isTablet ? 12 : 10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check, size: isTablet ? 18 : 16, color: Colors.white),
                                  SizedBox(width: isTablet ? 6 : 4),
                                  Text('Save',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: isTablet ? 15 : 14,
                                      )),
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

  Future<void> _saveStandaloneNote(int pageNumber, String note, StateSetter setSheetState) async {
    if (widget.documentId == null) return;
    try {
      final result = await _highlightService.addHighlight(
        documentId: widget.documentId!,
        pageNumber: pageNumber,
        startOffset: 0,
        endOffset: 0,
        highlightedText: '',
        color: 'yellow',
        annotationType: 'note',
        note: note,
      );
      final noteId = result['highlight_id'] as String;
      _standaloneNotes[noteId] = {
        'page_number': pageNumber,
        'note': note,
      };
      _undoStack.add((id: noteId, type: 'note'));
      setSheetState(() {});
      setState(() {});
    } catch (e) {
      debugPrint('Failed to save standalone note: $e');
      if (mounted) {
        showAppDialog(context, message: 'Failed to save note', type: AppDialogType.info);
      }
    }
  }

  // ── Edit standalone note ──────────────────────────────────────────

  void _showEditStandaloneNoteDialog(String noteId, StateSetter setSheetState) {
    final noteData = _standaloneNotes[noteId];
    if (noteData == null) return;
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;
    final noteController = TextEditingController(text: noteData['note'] as String);

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 20),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Edit Note  ·  Page ${noteData['page_number']}',
                            style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontWeight: FontWeight.w700,
                              fontSize: isTablet ? 20 : 18,
                              color: textColor,
                            )),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _deleteStandaloneNote(noteId, setSheetState);
                        },
                        child: Icon(Icons.delete_outline,
                            size: isTablet ? 22 : 20,
                            color: AppColors.error),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isTablet ? 16 : 12),
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: TextField(
                    controller: noteController,
                    maxLines: 4,
                    maxLength: 500,
                    autofocus: true,
                    style: TextStyle(color: textColor, fontSize: isTablet ? 15 : 14, height: 1.5),
                    decoration: InputDecoration(
                      hintText: 'Write your note...',
                      hintStyle: TextStyle(
                        color: isDark ? AppColors.darkTextTertiary : Colors.grey[400],
                        fontSize: isTablet ? 15 : 14,
                      ),
                      filled: true,
                      fillColor: isDark ? AppColors.darkSurface : const Color(0xFFF8F9FE),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
                      ),
                      counterStyle: TextStyle(
                        color: isDark ? AppColors.darkTextTertiary : Colors.grey,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: isTablet ? 16 : 12),
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancel',
                            style: TextStyle(
                              color: isDark ? AppColors.darkTextSecondary : Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            )),
                      ),
                      SizedBox(width: isTablet ? 12 : 8),
                      Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.blueGradient,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () async {
                              final note = noteController.text.trim();
                              if (note.isEmpty) {
                                showAppDialog(context,
                                    message: 'Note cannot be empty',
                                    type: AppDialogType.info);
                                return;
                              }
                              Navigator.pop(ctx);
                              try {
                                await _highlightService.updateHighlightNote(noteId, note);
                                _standaloneNotes[noteId]!['note'] = note;
                                setSheetState(() {});
                              } catch (e) {
                                debugPrint('Failed to update note: $e');
                                if (mounted) {
                                  showAppDialog(context,
                                      message: 'Failed to update note',
                                      type: AppDialogType.info);
                                }
                              }
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 28 : 24,
                                  vertical: isTablet ? 12 : 10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check, size: isTablet ? 18 : 16, color: Colors.white),
                                  SizedBox(width: isTablet ? 6 : 4),
                                  Text('Save',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: isTablet ? 15 : 14,
                                      )),
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

  Future<void> _deleteStandaloneNote(String noteId, StateSetter setSheetState) async {
    final backup = _standaloneNotes[noteId];
    _standaloneNotes.remove(noteId);
    setSheetState(() {});
    setState(() {});
    try {
      await _highlightService.deleteHighlight(noteId);
    } catch (e) {
      debugPrint('Failed to delete note: $e');
      // Restore on failure
      if (backup != null) {
        _standaloneNotes[noteId] = backup;
        setSheetState(() {});
        setState(() {});
      }
      if (mounted) {
        showAppDialog(context, message: 'Failed to delete note', type: AppDialogType.info);
      }
    }
  }

  // ── Undo last annotation ──────────────────────────────────────────

  Future<void> _undoLastAnnotation() async {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    final id = entry.id;
    final type = entry.type;

    try {
      if (type == 'highlight' && _highlightAnnotations.containsKey(id)) {
        try {
          _pdfController.removeAnnotation(_highlightAnnotations[id]!);
        } catch (_) {}
      } else if (type == 'underline' && _underlineAnnotations.containsKey(id)) {
        try {
          _pdfController.removeAnnotation(_underlineAnnotations[id]!);
        } catch (_) {}
      } else if (type == 'note') {
        _standaloneNotes.remove(id);
      }

      try {
        await _highlightService.deleteHighlight(id);
      } catch (_) {}

      _highlightAnnotations.remove(id);
      _underlineAnnotations.remove(id);
      _annotationNotes.remove(id);
      _annotationTexts.remove(id);
      _annotationTextBounds.remove(id);
      _standaloneNotes.remove(id);

      setState(() {});
    } catch (e) {
      debugPrint('Failed to undo: $e');
      if (mounted) {
        showAppDialog(context, message: 'Failed to undo: $e', type: AppDialogType.info);
      }
    }
  }

  void _showAllNotesPanel() {
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
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
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.3,
              maxChildSize: 0.85,
              expand: false,
              builder: (context, scrollController) {
                final currentIds = <String>[
                  ..._highlightAnnotations.keys,
                  ..._underlineAnnotations.keys,
                  ..._standaloneNotes.keys,
                ]..sort((a, b) => b.compareTo(a));
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
                    // Title + action buttons
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
                          // Add Note button
                          GestureDetector(
                            onTap: () => _showAddStandaloneNoteDialog(setSheetState),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 10 : 8,
                                  vertical: isTablet ? 6 : 4),
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add, size: isTablet ? 16 : 14,
                                      color: AppColors.primaryBlue),
                                  SizedBox(width: isTablet ? 4 : 3),
                                  Text('Add Note',
                                      style: TextStyle(
                                        fontSize: isTablet ? 12 : 11,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.primaryBlue,
                                      )),
                                ],
                              ),
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
                      child: currentIds.isEmpty
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
                              itemCount: currentIds.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                indent: isTablet ? 70 : 60,
                                endIndent: isTablet ? 24 : 20,
                                color: isDark
                                    ? AppColors.darkDivider
                                    : const Color(0xFFF0F0F0),
                              ),
                              itemBuilder: (context, index) {
                                final id = currentIds[index];
                                final isStandaloneNote =
                                    _standaloneNotes.containsKey(id);
                                final isHighlight =
                                    _highlightAnnotations.containsKey(id);

                                // Standalone note rendering
                                if (isStandaloneNote) {
                                  final noteData = _standaloneNotes[id]!;
                                  final noteText = noteData['note'] as String;
                                  final pageNum = noteData['page_number'] as int;
                                  return InkWell(
                                    onTap: () {
                                      _showEditStandaloneNoteDialog(id, setSheetState);
                                    },
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isTablet ? 24 : 20,
                                        vertical: isTablet ? 14 : 12,
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: isTablet ? 36 : 30,
                                            height: isTablet ? 36 : 30,
                                            margin: EdgeInsets.only(right: isTablet ? 14 : 10),
                                            decoration: BoxDecoration(
                                              color: AppColors.primaryBlue.withValues(alpha: 0.15),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(Icons.note_outlined,
                                                size: isTablet ? 18 : 16,
                                                color: AppColors.primaryBlue),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('Page $pageNum',
                                                    style: TextStyle(
                                                      fontSize: isTablet ? 12 : 11,
                                                      color: subtitleColor,
                                                      fontWeight: FontWeight.w500,
                                                    )),
                                                SizedBox(height: isTablet ? 4 : 2),
                                                Text(noteText,
                                                    style: TextStyle(
                                                      fontSize: isTablet ? 14 : 13,
                                                      color: textColor,
                                                      height: 1.3,
                                                    ),
                                                    maxLines: 3,
                                                    overflow: TextOverflow.ellipsis),
                                              ],
                                            ),
                                          ),
                                          // Go to page button
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.pop(sheetContext);
                                              _pdfController.jumpToPage(pageNum);
                                            },
                                            child: Padding(
                                              padding: EdgeInsets.only(left: isTablet ? 8 : 6),
                                              child: Icon(Icons.my_location,
                                                  size: isTablet ? 22 : 20,
                                                  color: AppColors.primaryBlue.withValues(alpha: 0.7)),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () => _deleteStandaloneNote(id, setSheetState),
                                            child: Padding(
                                              padding: EdgeInsets.only(left: isTablet ? 8 : 6),
                                              child: Icon(Icons.delete_outline,
                                                  size: isTablet ? 22 : 20,
                                                  color: AppColors.error.withValues(alpha: 0.7)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }

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
                                        // Go to page button
                                        GestureDetector(
                                          onTap: () {
                                            final bounds = _annotationTextBounds[id];
                                            if (bounds != null && bounds.isNotEmpty) {
                                              Navigator.pop(sheetContext);
                                              _pdfController.jumpToPage(bounds.first.pageNumber);
                                            }
                                          },
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              left: isTablet ? 8 : 6,
                                            ),
                                            child: Icon(
                                              Icons.my_location,
                                              size: isTablet ? 22 : 20,
                                              color: AppColors.primaryBlue.withValues(alpha: 0.7),
                                            ),
                                          ),
                                        ),
                                        // Delete button
                                        GestureDetector(
                                          onTap: () async {
                                            final confirm = await showDialog<bool>(
                                              context: sheetContext,
                                              builder: (dialogContext) => AlertDialog(
                                                backgroundColor: bgColor,
                                                title: Text(
                                                  isHighlight ? 'Remove Highlight' : 'Remove Underline',
                                                  style: TextStyle(color: textColor),
                                                ),
                                                content: Text(
                                                  'Are you sure you want to remove this ${isHighlight ? 'highlight' : 'underline'}?',
                                                  style: TextStyle(color: subtitleColor),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(dialogContext, false),
                                                    child: Text(
                                                      'Cancel',
                                                      style: TextStyle(color: subtitleColor),
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(dialogContext, true),
                                                    child: Text(
                                                      'Remove',
                                                      style: TextStyle(color: AppColors.error),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              _removeHighlight(annotation);
                                              setSheetState(() {});
                                              setState(() {});
                                            }
                                          },
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              left: isTablet ? 8 : 6,
                                            ),
                                            child: Icon(
                                              Icons.delete_outline,
                                              size: isTablet ? 22 : 20,
                                              color: AppColors.error.withValues(alpha: 0.7),
                                            ),
                                          ),
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
        _annotationTextBounds.remove(annotationId);
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
      drawerEnableOpenDragGesture: false,
      endDrawerEnableOpenDragGesture: false,
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

                        // Fixed bottom action bar
                        if (_isPdfReady)
                          _buildBottomActionBar(isDark, isTablet),
                      ],
                    ),
                    // Loading overlay while PDF is parsing
                    if (!_isPdfReady)
                      Positioned.fill(
                        child: Container(
                          color: isDark
                              ? AppColors.darkBackground
                              : Colors.white,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildPdfViewer() {
    // Cache the SfPdfViewer widget so setState calls never recreate it.
    // This is the key fix: Flutter sees the same widget instance and skips
    // the update, preserving scroll position and internal state.
    _cachedPdfViewer ??= SfPdfViewer.file(
      File(_localPath!),
      key: _pdfViewerKey,
      controller: _pdfController,
      canShowTextSelectionMenu: false,
      // Syncfusion's built-in Go-to-Page dialog interacts badly with
      // GoRouter — its OK button pops the PDF route instead of the
      // dialog, leaving the modal dangling on the previous screen. We
      // ship our own page-indicator + dialog in the toolbar below.
      // ScrollHead (the side scroll thumb showing current page) is left
      // on for visual feedback — its tap-to-jump trigger goes nowhere
      // because canShowPaginationDialog is off.
      canShowPaginationDialog: false,
      canShowScrollHead: true,
      interactionMode: PdfInteractionMode.pan,
      pageSpacing: 2,
      onTap: (PdfGestureDetails details) {
        _removeContextMenu();
      },
      onDocumentLoaded: (PdfDocumentLoadedDetails details) {
        debugPrint(
            '[PDF-DBG] sync.SfPdfViewer onDocumentLoaded pages=${details.document.pages.count} '
            'path=$_localPath');
        if (!_isPdfReady) {
          setState(() {
            _isPdfReady = true;
          });
        }
        _loadHighlights();
        _loadBookmarks();
        _restoreProgress();
      },
      onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
        // SfPdfViewer has its own failure path that bypasses _loadPdf's
        // catch (the file was handed off successfully, but pdfium rejected
        // it). Surface it explicitly so we can see WHICH file failed and
        // why — Syncfusion's error/description tells us if the file is
        // corrupted, password-protected, or unsupported version. This is
        // the active iOS PDF viewer (the pdfrx file is wired on Android).
        debugPrint(
            '[PDF-DBG] sync.SfPdfViewer onDocumentLoadFailed path=$_localPath '
            'error="${details.error}" description="${details.description}"');
        _logFileForensics(_localPath ?? '<null>', 'sync.LOAD_FAILED_CALLBACK');
        if (mounted) {
          setState(() {
            _error = 'Failed to load PDF';
          });
        }
      },
      onPageChanged: (PdfPageChangedDetails details) {
        _currentPage.value = details.newPageNumber;
        _debouncedSaveProgress(details.newPageNumber);
      },
      onTextSelectionChanged: (PdfTextSelectionChangedDetails details) {
        if (details.selectedText != null &&
            details.selectedText!.isNotEmpty) {
          // Debounce: don't rebuild the overlay on every pixel of handle drag.
          // Wait until the user pauses, then show the context menu.
          _contextMenuDebounce?.cancel();
          _removeContextMenu();
          final region = details.globalSelectedRegion;
          if (region != null) {
            _contextMenuDebounce =
                Timer(const Duration(milliseconds: 300), () {
              if (mounted) {
                _showContextMenu(Offset(region.center.dx, region.top));
              }
            });
          }
        } else {
          _removeContextMenu();
        }
      },
      onAnnotationSelected: (Annotation annotation) {
        _showAnnotationMenu(annotation);
      },
      onAnnotationDeselected: (Annotation annotation) {
        _removeContextMenu();
      },
      onAnnotationRemoved: (Annotation annotation) {
        _handleAnnotationRemoved(annotation);
      },
    );

    // RepaintBoundary isolates the viewer's render tree — toolbar / bottom bar
    // repaints won't cascade into the PDF rendering pipeline during scrolling.
    final viewer = RepaintBoundary(child: _cachedPdfViewer!);

    if (_isPdfDarkMode) {
      return ColorFiltered(
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
                Tooltip(
                  message: 'Go back',
                  child: GestureDetector(
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
                // Page indicator badge — tap to open Go-to-Page dialog.
                // Replaces Syncfusion's built-in scrollHead (disabled
                // above) and dialog (also disabled, since it pops the
                // PDF route under GoRouter).
                if (_isPdfReady)
                  ValueListenableBuilder<int>(
                    valueListenable: _currentPage,
                    builder: (context, page, _) {
                      final total = _pdfController.pageCount;
                      if (total <= 0) return const SizedBox.shrink();
                      return GestureDetector(
                        onTap: _showGoToPageDialog,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: isTablet ? 12 : 10,
                              vertical: isTablet ? 8 : 6),
                          margin: EdgeInsets.only(right: isTablet ? 6 : 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                                isTablet ? 12 : 10),
                          ),
                          child: Text(
                            '$page / $total',
                            style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontWeight: FontWeight.w600,
                              fontSize: isTablet ? 14 : 12,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                // Bookmark toggle button (only for auth documents)
                if (widget.documentId != null) ...[
                  ValueListenableBuilder<int>(
                    valueListenable: _currentPage,
                    builder: (context, currentPage, _) {
                      final isBookmarked = _bookmarkedPages.containsKey(currentPage);
                      return Tooltip(
                        message: isBookmarked ? 'Remove bookmark' : 'Bookmark page',
                        child: GestureDetector(
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
                        ),
                      );
                    },
                  ),
                  // Bookmarks list button (show when bookmarks exist)
                  if (_bookmarkedPages.isNotEmpty)
                    Tooltip(
                      message: 'Bookmarks',
                      child: GestureDetector(
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
                    ),
                ],
                // Search button
                Tooltip(
                  message: _isSearchOpen ? 'Close search' : 'Search',
                  child: GestureDetector(
                    onTap: _toggleSearch,
                    child: Container(
                      width: isTablet ? 44 : 36,
                      height: isTablet ? 44 : 36,
                      margin: EdgeInsets.only(right: isTablet ? 4 : 2),
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
                ),
                // Overflow menu — keeps the toolbar uncluttered. Holds
                // the toggles that aren't used every interaction:
                // keep-screen-on, lock-rotation, dark-mode.
                _buildOverflowMenu(isDark, textColor, isTablet),
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
                setState(() {
                  _searchResult = _pdfController.searchText(value);
                });
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

  void _requireSelectionOr(VoidCallback action) {
    final textLines = _pdfViewerKey.currentState?.getSelectedTextLines();
    if (textLines == null || textLines.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: const Text('Select text first by long-pressing on it'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          ),
        );
      return;
    }
    action();
  }

  Widget _buildBottomActionBar(bool isDark, bool isTablet) {
    final barColor = isDark ? AppColors.darkCardBackground : Colors.white;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 24 : 16,
        vertical: isTablet ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: barColor,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildBottomAction(
              icon: Icons.border_color,
              label: 'Highlight',
              color: const Color(0xFFFF6D00),
              onTap: () =>
                  _requireSelectionOr(() => _highlightSelectedText('yellow')),
              isDark: isDark,
              isTablet: isTablet,
            ),
            _buildBottomAction(
              icon: Icons.format_underlined,
              label: 'Underline',
              color: const Color(0xFF1565C0),
              onTap: () => _requireSelectionOr(_underlineSelectedText),
              isDark: isDark,
              isTablet: isTablet,
            ),
            _buildBottomAction(
              icon: Icons.sticky_note_2_outlined,
              label: 'Notes',
              color: const Color(0xFF43A047),
              onTap: _showAllNotesPanel,
              isDark: isDark,
              isTablet: isTablet,
            ),
            if (_undoStack.isNotEmpty)
              _buildBottomAction(
                icon: Icons.undo,
                label: 'Undo',
                color: AppColors.error,
                onTap: _undoLastAnnotation,
                isDark: isDark,
                isTablet: isTablet,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
    required bool isTablet,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 12 : 8,
          vertical: isTablet ? 4 : 2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: isTablet ? 40 : 32,
              height: isTablet ? 40 : 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: isTablet ? 20 : 16, color: color),
            ),
            SizedBox(height: isTablet ? 4 : 2),
            Text(
              label,
              style: TextStyle(
                fontSize: isTablet ? 11 : 9,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.darkTextSecondary : Colors.grey[700],
              ),
            ),
          ],
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
                _isPdfReady = false;
                _downloadProgress = 0;
                _cachedPdfViewer = null;
                _highlightsLoaded = false;
                _bookmarksLoaded = false;
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

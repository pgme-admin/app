import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:pgme/core/services/pdf_cache_service.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/models/annotation_bounds.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/providers/mini_player_provider.dart';
import 'package:pgme/core/services/api_service.dart';
import 'package:pgme/core/services/bookmark_service.dart';
import 'package:pgme/core/services/highlight_service.dart';
import 'package:pgme/core/services/download_service.dart';
import 'package:pgme/core/services/ebook_access_service.dart';
import 'package:pgme/core/services/progress_service.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/utils/highlight_placement.dart';
import 'package:pgme/core/widgets/app_dialog.dart';
import 'package:pgme/features/notes/widgets/bookmarks_drawer.dart';

// ─────────────────────────────────────────────────────────────────────
// Local data class to replace Syncfusion's Annotation objects.
// Holds everything needed to paint a highlight/underline on the canvas.
// ─────────────────────────────────────────────────────────────────────
class _AnnotationData {
  final List<AnnotationTextBounds> bounds;
  final Color color;
  const _AnnotationData({required this.bounds, required this.color});
}

/// Mutable accumulator used by `_selectionToBounds` to collapse pdfrx's
/// per-word fragments into one rect per visual line.
class _LineAccumulator {
  double top;
  double bottom;
  double left;
  double right;
  String text;

  _LineAccumulator({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
    required this.text,
  });

  void merge(double l, double r, double t, double b, String fragText) {
    if (l < left) left = l;
    if (r > right) right = r;
    if (t > top) top = t;
    if (b < bottom) bottom = b;
    text += fragText;
  }
}

class PdfViewerScreen extends StatefulWidget {
  final String? documentId;
  final String? pdfUrl;
  final String? filePath;
  final String title;

  /// Tells the URL-resolution path which API endpoint to hit when only
  /// [documentId] is provided. Pass `'ebook'` for items that came from
  /// EbookAccessService; anything else (or null) falls back to the
  /// regular documentViewUrl. Set by /test-pdfrx route, ignored when
  /// [pdfUrl] or [filePath] is given (those skip URL resolution).
  final String? source;

  /// True when this viewer is hosted inside another screen (the video
  /// player's split view) instead of being pushed as its own route. The only
  /// behavioural difference: the toolbar's leading button closes the pane via
  /// [onClose] instead of popping a route. Every other feature (highlight,
  /// underline, notes, undo, bookmarks, search, outline) is unchanged.
  final bool embedded;

  /// Called by the toolbar's leading button when [embedded] is true.
  final VoidCallback? onClose;

  const PdfViewerScreen({
    super.key,
    this.documentId,
    this.pdfUrl,
    this.filePath,
    this.title = 'PDF Viewer',
    this.source,
    this.embedded = false,
    this.onClose,
  }) : assert(documentId != null || pdfUrl != null || filePath != null);

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final HighlightService _highlightService = HighlightService();
  final BookmarkService _bookmarkService = BookmarkService();
  final ProgressService _progressService = ProgressService();

  bool _isLoading = true;
  bool _isPdfReady = false;
  String? _error;
  double _downloadProgress = 0;
  bool _isSearchOpen = false;

  // Search
  PdfTextSearcher? _textSearcher;
  final TextEditingController _searchController = TextEditingController();

  // Annotations — keyed by backend highlight_id
  final Map<String, _AnnotationData> _highlights = {};
  final Map<String, _AnnotationData> _underlines = {};
  final Map<String, String?> _annotationNotes = {};
  final Map<String, String> _annotationTexts = {};
  final Map<String, List<AnnotationTextBounds>> _annotationBounds = {};
  // Standalone notes (annotation_type=='note', no bounds, just a page+note).
  // Backend stores them in the same `highlights` collection with empty
  // bounds_data; we keep them in a separate map because they don't render
  // on the page — they only appear in the Notes panel.
  // noteId -> { 'page_number': int, 'note': String }
  final Map<String, Map<String, dynamic>> _standaloneNotes = {};

  // Undo stack — most recent action at the tail. Each entry records the
  // backend id and which kind of annotation it is so _undoLastAnnotation
  // can reach into the right map. Pushed only AFTER the backend save
  // succeeds (so undo always has a real id to delete). Manual deletes via
  // the Notes panel also strip matching entries from the stack so the
  // user can never undo something that's already gone.
  final List<({String id, String type})> _undoStack = [];

  // Context menu overlay
  OverlayEntry? _contextMenuOverlay;
  Timer? _contextMenuDebounce;

  // Current text selection (captured from pdfrx callback)
  List<PdfTextRanges>? _currentSelections;
  String? _currentSelectedText;

  // Captured at context menu show time — survives selection clearing when
  // the user taps an overlay button outside the SelectionArea.
  List<AnnotationTextBounds>? _capturedBounds;
  String? _capturedText;

  // Bookmarks
  final Map<int, String> _bookmarkedPages = {};
  final Map<String, String?> _bookmarkNotes = {};

  // Progress
  final ValueNotifier<int> _currentPage = ValueNotifier(1);
  Timer? _progressDebounceTimer;

  // Dark mode
  bool _isPdfDarkMode = false;

  // Guards
  bool _highlightsLoaded = false;
  bool _bookmarksLoaded = false;
  // Locates the viewer area on screen so the annotation menu can be kept
  // inside it (see _showContextMenuFromSelection).
  final GlobalKey _viewerAreaKey = GlobalKey();

  // The SelectionArea around the PDF text, so an applied highlight/underline
  // can clear the on-screen selection.
  final GlobalKey<SelectionAreaState> _selectionAreaKey =
      GlobalKey<SelectionAreaState>();

  void _clearTextSelection() {
    try {
      _selectionAreaKey.currentState?.selectableRegion.clearSelection();
    } catch (e) {
      debugPrint('[PDFRX] clearSelection failed: $e');
    }
  }

  // "Keep screen on" / "Lock rotation" menu toggles (full-screen reader
  // only — in the video split pane the host screen owns both).
  bool _keepScreenOn = false;
  bool _orientationLocked = false;

  // Tap-to-hide reader chrome (toolbar + bottom action bar).
  bool _chromeVisible = true;
  bool get _showChrome => _chromeVisible || _isSearchOpen || widget.embedded;
  // Raw pointer tracking for tap detection. A Listener does not take part in
  // the gesture arena, so it cannot interfere with scrolling, pinch-zoom or
  // text selection.
  int? _tapPointer;
  Offset _tapDownPosition = Offset.zero;
  DateTime _tapDownAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _onViewerPointerDown(PointerDownEvent e) {
    // Only a single-finger touch can be a tap; a second finger (pinch) cancels.
    _tapPointer = _tapPointer == null ? e.pointer : null;
    _tapDownPosition = e.position;
    _tapDownAt = DateTime.now();
  }

  void _onViewerPointerUp(PointerUpEvent e) {
    if (_tapPointer != e.pointer) return;
    _tapPointer = null;
    final moved = (e.position - _tapDownPosition).distance;
    final heldMs = DateTime.now().difference(_tapDownAt).inMilliseconds;
    // A quick, stationary touch is a tap. A long press starts a text
    // selection, and taps while a selection or the annotation menu is open
    // belong to those, so they never toggle the chrome.
    if (moved > 10 || heldMs > 300) return;
    if (_currentSelections != null && _currentSelections!.isNotEmpty) return;
    if (_contextMenuOverlay != null) return;
    if (widget.embedded) return;
    setState(() => _chromeVisible = !_chromeVisible);
  }

  // True once the saved reading position has been fetched/applied (or there is
  // nothing to restore). dispose() only saves progress after this, otherwise
  // closing the viewer quickly would overwrite the saved page with page 1.
  bool _progressRestored = false;

  // Pre-loaded PDF document. We open the file and run loadPagesProgressively
  // to completion BEFORE mounting the PdfViewer — that way the user sees a
  // full-screen progress UI instead of a half-loaded document they can't
  // scroll. Once non-null, the viewer mounts with PdfDocumentRefDirect.
  PdfDocument? _document;
  int _totalPages = 0;
  int _loadedPages = 0;

  // PDF outline / table of contents. Loaded after the document is ready;
  // null while loading, empty list if the PDF has no embedded outline.
  // Drives the left-side TOC drawer + the toolbar TOC button visibility.
  List<PdfOutlineNode>? _outline;

  // Cached viewer widget — must not be recreated on setState
  Widget? _cachedPdfViewer;

  /// Call instead of plain setState when annotation data changes.
  /// Uses controller.invalidate() to repaint annotations without
  /// recreating the PdfViewer widget (which would reset the document).
  void _setAnnotationState(VoidCallback fn) {
    // Wrap in setState so chrome that depends on annotation state — the
    // Notes count badge, the conditional Undo button at the bottom — also
    // refreshes. The PdfViewer widget itself is NOT recreated because
    // _buildPdfViewer uses `_cachedPdfViewer ??= PdfViewer(...)` so Flutter
    // reuses the same widget instance across rebuilds (no document reset,
    // no scroll-position reset, no internal pdfrx state churn).
    if (mounted) {
      setState(fn);
    } else {
      fn();
    }
    if (_pdfController.isReady) {
      _pdfController.invalidate();
    }
  }

  static const Map<String, Color> highlightColors = {
    'yellow': Color(0x80FFEB3B),
    'green': Color(0x8066BB6A),
    'blue': Color(0x8042A5F5),
    'pink': Color(0x80EC407A),
  };

  static const Color underlineColor = Color(0xFF1565C0);

  static const ColorFilter _invertColorFilter = ColorFilter.matrix(<double>[
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ]);

  // Identity matrix used as a no-op alternative to [_invertColorFilter] so
  // the ColorFiltered widget can stay permanently in the tree. Toggling
  // between two ColorFilter values keeps the widget structure stable, which
  // means the cached PdfViewer's State is never deactivated — preserving
  // the controller wiring, search results, and onPageChanged listeners.
  // (Previously we conditionally wrapped/unwrapped ColorFiltered, which
  // changed the parent type at this slot and tore down the viewer's
  // internal state on every toggle.)
  static const ColorFilter _identityColorFilter = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  // ── Lifecycle ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (!widget.embedded) {
      // Full-screen reader: allow reading in any orientation (phones are
      // otherwise portrait-only); dispose() restores the device default.
      SystemChrome.setPreferredOrientations(_allOrientations);
      // Free memory for the PDF: stop a minimized video player first, as the
      // previous (Syncfusion) reader did.
      try {
        final miniProvider =
            Provider.of<MiniPlayerProvider>(context, listen: false);
        if (miniProvider.isActive) miniProvider.close();
      } catch (_) {}
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final isDark =
            Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
        setState(() => _isPdfDarkMode = isDark);
      }
    });
    _loadPdf();
  }

  @override
  void dispose() {
    if (!widget.embedded) {
      // Back to the app's device policy (phones: portrait only; tablets: any).
      SystemChrome.setPreferredOrientations(
          ResponsiveHelper.supportedOrientationsForDevice());
      // The app keeps the screen awake everywhere (see main.dart). Restore
      // that if the reader's toggle switched it off.
      if (!_keepScreenOn) WakelockPlus.enable();
    }
    _contextMenuOverlay?.remove();
    _contextMenuOverlay = null;
    _contextMenuDebounce?.cancel();
    _progressDebounceTimer?.cancel();
    final documentId = widget.documentId;
    final lastPage = _currentPage.value;
    // Ebook ids are not valid for the document-progress route (it 404s), and
    // saving before the saved page was restored would reset it to page 1.
    if (documentId != null &&
        lastPage > 0 &&
        widget.source != 'ebook' &&
        _progressRestored) {
      _progressService
          .updateDocumentProgress(documentId: documentId, pageNumber: lastPage)
          .catchError((Object e) {
        debugPrint('Failed to save progress on close: $e');
        return <String, dynamic>{};
      });
    }
    _currentPage.dispose();
    _textSearcher?.dispose();
    _searchController.dispose();
    // Dispose the pre-loaded document. We pass it to PdfViewer with
    // autoDispose: false so the viewer doesn't dispose it under us when
    // the widget rebuilds.
    _document?.dispose();
    _document = null;
    super.dispose();
  }

  // ── PDF loading (identical to Syncfusion version) ─────────────────

  Future<void> _loadPdf() async {
    try {
      if (widget.filePath != null) {
        if (mounted) {
          setState(() => _isLoading = false);
          _loadDocumentFully(widget.filePath!);
        }
        return;
      }

      if (widget.documentId != null) {
        final docFileName = 'doc_${widget.documentId}.pdf';
        final ebookFileName = 'ebook_${widget.documentId}.pdf';
        final downloadedPath =
            await DownloadService().getDownloadedPath(docFileName) ??
                await DownloadService().getDownloadedPath(ebookFileName);
        if (downloadedPath != null) {
          final file = File(downloadedPath);
          final fileSize = await file.length();
          if (fileSize > 0 && mounted) {
            setState(() => _isLoading = false);
            _loadDocumentFully(downloadedPath);
            return;
          }
        }
      }

      String pdfUrl;
      if (widget.pdfUrl != null) {
        pdfUrl = widget.pdfUrl!;
      } else if (widget.source == 'ebook') {
        // Ebooks live behind a different access-controlled endpoint.
        // EbookAccessService handles the entitlement check + signed URL.
        final data =
            await EbookAccessService().getEbookViewUrl(widget.documentId!);
        pdfUrl = data['url'] as String;
      } else {
        final apiService = ApiService();
        final response = await apiService.dio.get(
          ApiConstants.documentViewUrl(widget.documentId!),
        );
        pdfUrl = response.data['data']['url'] as String;
      }

      if (!mounted) return;

      // Persistent on-device cache (TTL + LRU). Same key whether the URL
      // was a fresh signed S3 link or the static one — documentId is
      // preferred so URL rotation doesn't invalidate the cached copy.
      final cacheKey = widget.documentId ?? 'url_${pdfUrl.hashCode}';
      final cached = await PdfCacheService.getCachedFile(cacheKey);
      if (cached != null) {
        if (mounted) {
          setState(() => _isLoading = false);
          // Pass the key so a parse failure (corrupt cached file) can
          // invalidate the entry and the next Retry re-downloads.
          _loadDocumentFully(cached.path, cacheKey: cacheKey);
        }
        return;
      }

      final downloaded = await PdfCacheService.cacheFromUrl(
        cacheKey,
        pdfUrl,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      if (mounted) {
        setState(() => _isLoading = false);
        _loadDocumentFully(downloaded.path, cacheKey: cacheKey);
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

  /// Opens the PDF and fully loads ALL page metadata via
  /// [PdfDocument.loadPagesProgressively] BEFORE handing it to the
  /// [PdfViewer]. While this runs, the build shows a full-screen
  /// progress UI instead of the viewer — preventing the half-loaded
  /// state where the user would otherwise see page 1 but couldn't
  /// scroll past whatever batch had been loaded so far.
  Future<void> _loadDocumentFully(String filePath, {String? cacheKey}) async {
    if (!mounted) return;
    try {
      final doc = await PdfDocument.openFile(
        filePath,
        useProgressiveLoading: true, // only page 1 loads here — fast
      );
      if (!mounted) {
        await doc.dispose();
        return;
      }

      // Drive loadPagesProgressively to completion. The callback updates
      // the progress UI; returning true keeps the loader going.
      await doc.loadPagesProgressively<void>(
        onPageLoadProgress: (pageNumber, totalPageCount, _) {
          if (!mounted) return false;
          if (totalPageCount != _totalPages || pageNumber != _loadedPages) {
            setState(() {
              _totalPages = totalPageCount;
              _loadedPages = pageNumber;
            });
          }
          return true;
        },
      );

      if (!mounted) {
        await doc.dispose();
        return;
      }

      debugPrint(
          '[PDFRX] Fully loaded $_loadedPages / $_totalPages pages from $filePath');
      // Set _isPdfReady together with _document so the loading overlay
      // disappears the same frame the viewer mounts. Don't wait for
      // pdfrx's onDocumentChanged callback — with PdfDocumentRefDirect
      // the document is already loaded so the listener doesn't always
      // fire, leaving the overlay stuck on top of the rendered PDF.
      setState(() {
        _document = doc;
        _isPdfReady = true;
      });
      // Init the post-load services after the next frame so the
      // PdfViewer has had a chance to mount and attach _pdfController.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _textSearcher ??= PdfTextSearcher(_pdfController);
        _loadHighlights();
        _loadBookmarks();
        _loadOutline();
        _restoreProgress();
      });
    } catch (e) {
      debugPrint('[PDFRX] Failed to load document: $e');
      // If this load came from a cached file (cacheKey != null), the
      // cached file is the most likely culprit (corrupt download, partial
      // bytes, server returned non-PDF that bypassed magic-byte check on a
      // previous version). Drop the entry so the next Retry re-downloads
      // from the source instead of looping on the same bad blob.
      if (cacheKey != null) {
        await PdfCacheService.invalidate(cacheKey);
      }
      if (mounted) {
        setState(() {
          _error = 'Failed to load PDF';
        });
      }
    }
  }

  // ── Progress ──────────────────────────────────────────────────────

  Future<void> _restoreProgress() async {
    if (widget.documentId == null) return;
    // Backend `/users/progress/document/<id>` only knows about library
    // documents. Ebooks live in a separate collection and the route 404s
    // for them — no point hitting it. Re-enable once backend exposes
    // /users/progress/ebook/<id> (or unifies the routes).
    if (widget.source == 'ebook') return;
    try {
      final progress =
          await _progressService.getDocumentProgress(widget.documentId!);
      final savedPage = (progress['page_number'] as num?)?.toInt() ?? 1;
      if (savedPage > 1 && mounted) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          // Immediate jump: an animated jump can be cancelled by a viewport
          // resize (keyboard / insets settling) and land on the wrong page.
          _pdfController.goToPage(
              pageNumber: savedPage, duration: Duration.zero);
        }
      }
    } catch (e) {
      debugPrint('Failed to restore progress: $e');
    } finally {
      _progressRestored = true;
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
    // See _restoreProgress — ebook IDs aren't valid for the document
    // progress route. Skip silently instead of spamming "Resource not
    // found" every page change.
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

  // ── Bookmarks ─────────────────────────────────────────────────────

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
      final bookmarkId = _bookmarkedPages[page]!;
      final savedNote = _bookmarkNotes[bookmarkId];
      setState(() {
        _bookmarkedPages.remove(page);
        _bookmarkNotes.remove(bookmarkId);
      });
      try {
        await _bookmarkService.deleteBookmark(bookmarkId);
      } catch (e) {
        if (mounted) {
          setState(() {
            _bookmarkedPages[page] = bookmarkId;
            _bookmarkNotes[bookmarkId] = savedNote;
          });
          showAppDialog(context,
              message: 'Failed to remove bookmark', type: AppDialogType.info);
        }
      }
    } else {
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
          // Show the server's actual reason (e.g. "already exists",
          // "Invalid page number") instead of an unexplained generic failure.
          final reason = e.toString().replaceFirst('Exception: ', '').trim();
          showAppDialog(context,
              message: reason.isEmpty ? 'Failed to add bookmark' : reason,
              type: AppDialogType.info);
        }
      }
    }
  }

  // ── Load highlights/underlines from backend ───────────────────────

  Future<void> _loadHighlights() async {
    if (widget.documentId == null || _highlightsLoaded) return;
    _highlightsLoaded = true;

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    try {
      final highlights =
          await _highlightService.getHighlights(widget.documentId!);

      // Text of every page that has a saved highlight, so each row can be
      // placed by the words it was made on (see HighlightPlacement).
      final pageText = await _loadPageTextForRows(highlights);
      if (!mounted) return;

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

          // Standalone notes have no on-page bounds — page is stored
          // explicitly in page_number. Track separately so they show in
          // the Notes panel even though they don't render on the page.
          if (annotationType == 'note') {
            _standaloneNotes[highlightId] = {
              'page_number': (h['page_number'] as num?)?.toInt() ?? 1,
              'note': note ?? '',
            };
            continue;
          }

          if (boundsData == null || boundsData.isEmpty) continue;

          // Stored bounds are top-left / y-down (the convention Syncfusion
          // writes); rows from older pdfrx builds are PDF-native y-up. Pick
          // the placement that lands on the row's own text and convert.
          final legacyYUp = HighlightPlacement.isYUp(
            bounds: boundsData.cast<Map<String, dynamic>>(),
            pageHeight: (p) {
              final doc = _document;
              if (doc == null || p < 1 || p > doc.pages.length) return null;
              return _userSpaceHeight(doc.pages[p - 1]);
            },
            pageText: (p) => pageText[p],
            startOffset: (h['start_offset'] as num?)?.toInt(),
          );
          final bounds = boundsData
              .map<AnnotationTextBounds>(
                  (b) => AnnotationTextBounds.fromJson(b as Map<String, dynamic>))
              .map<AnnotationTextBounds>(
                  (b) => legacyYUp ? _legacyYUpToYDown(b) : b)
              .toList();

          final data = _AnnotationData(
            bounds: bounds,
            color: annotationType == 'underline' ? underlineColor : color,
          );

          if (annotationType == 'underline') {
            _underlines[highlightId] = data;
          } else {
            _highlights[highlightId] = data;
          }

          _annotationNotes[highlightId] = note;
          _annotationTexts[highlightId] =
              (h['highlighted_text'] as String?) ?? '';
          _annotationBounds[highlightId] = bounds;
        } catch (e) {
          debugPrint('Failed to restore highlight: $e');
        }
      }

      if (mounted) _setAnnotationState(() {});
    } catch (e) {
      debugPrint('Failed to load highlights: $e');
    }
  }

  // ── Coordinate conversion ─────────────────────────────────────────

  /// Page height in PDF user space (rotation-independent), used to flip
  /// between the stored top-left/y-down bounds and pdfrx's bottom-left/y-up
  /// page coordinates.
  static double _userSpaceHeight(PdfPage page) =>
      (page.rotation.index & 1) == 1 ? page.width : page.height;

  /// Loads the text (with positions, top-left origin) of every page that has
  /// a saved highlight/underline, keyed by 1-based page number. Pages whose
  /// text cannot be read are simply left out.
  Future<Map<int, List<PageTextBox>>> _loadPageTextForRows(
      List<dynamic> rows) async {
    final doc = _document;
    final result = <int, List<PageTextBox>>{};
    if (doc == null) return result;

    final pages = <int>{};
    for (final h in rows) {
      final bounds = (h is Map) ? h['bounds_data'] : null;
      if (bounds is! List) continue;
      for (final b in bounds) {
        final p = (b is Map) ? (b['page_number'] as num?)?.toInt() : null;
        if (p != null && p >= 1 && p <= doc.pages.length) pages.add(p);
      }
    }

    for (final p in pages) {
      if (!mounted) break;
      try {
        final page = doc.pages[p - 1];
        final hu = _userSpaceHeight(page);
        final text = await page.loadText();
        result[p] = [
          for (final f in text.fragments)
            PageTextBox(
              Rect.fromLTRB(f.bounds.left, hu - f.bounds.top, f.bounds.right,
                  hu - f.bounds.bottom),
              f.text,
            ),
        ];
      } catch (e) {
        debugPrint('[PDFRX] page $p text unavailable for highlight placement: $e');
      }
    }
    return result;
  }

  AnnotationTextBounds _legacyYUpToYDown(AnnotationTextBounds b) {
    final doc = _document;
    if (doc == null || b.pageNumber < 1 || b.pageNumber > doc.pages.length) {
      return b;
    }
    final hu = _userSpaceHeight(doc.pages[b.pageNumber - 1]);
    return AnnotationTextBounds(
      left: b.left,
      top: hu - b.top, // old rows stored the PDF-space top edge
      width: b.width,
      height: b.height,
      text: b.text,
      pageNumber: b.pageNumber,
    );
  }

  Rect _boundsToScreenRect(
      AnnotationTextBounds bounds, PdfPage page, Rect pageRect) {
    // Stored bounds are top-left / y-down. Flip to pdfrx's PDF page space
    // (bottom-left / y-up) and let pdfrx's own conversion handle scale and
    // rotation.
    final hu = _userSpaceHeight(page);
    final pdfTop = hu - bounds.top;
    final pdfRect = PdfRect(
      bounds.left,
      pdfTop,
      bounds.left + bounds.width,
      pdfTop - bounds.height, // PDF coords: bottom = top - height
    );
    return pdfRect.toRectInPageRect(page: page, pageRect: pageRect);
  }

  // ── Canvas painting for annotations ───────────────────────────────

  void _paintAnnotations(Canvas canvas, Rect pageRect, PdfPage page) {
    final pageNumber = page.pageNumber;

    // Paint highlights
    for (final entry in _highlights.entries) {
      for (final bounds in entry.value.bounds) {
        if (bounds.pageNumber != pageNumber) continue;
        final rect = _boundsToScreenRect(bounds, page, pageRect);
        canvas.drawRect(
          rect,
          Paint()
            ..color = entry.value.color
            ..style = PaintingStyle.fill,
        );
      }
    }

    // Paint underlines
    for (final entry in _underlines.entries) {
      for (final bounds in entry.value.bounds) {
        if (bounds.pageNumber != pageNumber) continue;
        final rect = _boundsToScreenRect(bounds, page, pageRect);
        canvas.drawLine(
          Offset(rect.left, rect.bottom),
          Offset(rect.right, rect.bottom),
          Paint()
            ..color = underlineColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }
    }
  }

  // ── Page overlays for annotation tap targets ──────────────────────

  List<Widget> _buildPageOverlays(
      BuildContext context, Rect pageRect, PdfPage page) {
    final pageNumber = page.pageNumber;
    final widgets = <Widget>[];

    void addTapTargets(
        Map<String, _AnnotationData> map, bool isUnderline) {
      for (final entry in map.entries) {
        for (final bounds in entry.value.bounds) {
          if (bounds.pageNumber != pageNumber) continue;
          final rect = _boundsToScreenRect(bounds, page, pageRect);
          widgets.add(
            Positioned(
              left: rect.left - pageRect.left,
              top: rect.top - pageRect.top,
              width: rect.width,
              height: rect.height,
              child: GestureDetector(
                onTap: () => _showAnnotationMenu(entry.key, isUnderline),
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
            ),
          );
        }
      }
    }

    addTapTargets(_highlights, false);
    addTapTargets(_underlines, true);
    return widgets;
  }

  // ── Text selection handling ────────────────────────────────────────

  void _handleTextSelectionChange(List<PdfTextRanges> selections) {
    final hasSelection = selections.isNotEmpty &&
        selections.any((s) => s.isNotEmpty);
    if (hasSelection) {
      _contextMenuDebounce?.cancel();
      _removeContextMenu();

      _currentSelections = selections;
      _currentSelectedText =
          selections.map((s) => s.text).join(' ');

      _contextMenuDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted || _currentSelections == null) return;
        _showContextMenuFromSelection();
      });
    } else {
      _currentSelections = null;
      _currentSelectedText = null;
      _removeContextMenu();
    }
  }

  void _showContextMenuFromSelection() {
    if (_currentSelections == null || _currentSelections!.isEmpty) {
      return;
    }
    // Capture bounds NOW — by the time the user taps a button in the overlay,
    // the SelectionArea may have already cleared _currentSelections.
    _capturedBounds = _selectionToBounds(_currentSelections!);
    _capturedText = _currentSelectedText;

    // Anchor the menu to the selection itself, kept inside the reader's own
    // area. (It used to sit at a fixed spot near the top of the SCREEN, which
    // in the video split pane is on top of the video, far from the text.)
    final viewerRect = _viewerAreaGlobalRect();
    final selectionRect = _selectionGlobalRect(_capturedBounds!);
    if (selectionRect != null) {
      _showContextMenu(
        Offset(selectionRect.center.dx, selectionRect.top),
        belowY: selectionRect.bottom,
        within: viewerRect,
      );
    } else if (viewerRect != null) {
      _showContextMenu(Offset(viewerRect.center.dx, viewerRect.top),
          within: viewerRect);
    } else {
      final screenSize = MediaQuery.of(context).size;
      _showContextMenu(Offset(screenSize.width / 2, 120));
    }
  }

  /// Global (screen) rect of the area the PDF viewer occupies.
  Rect? _viewerAreaGlobalRect() {
    final box = _viewerAreaKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Global (screen) rect covering the selected lines, or null if it cannot
  /// be computed (e.g. layout not ready).
  Rect? _selectionGlobalRect(List<AnnotationTextBounds> bounds) {
    final doc = _document;
    if (doc == null || bounds.isEmpty) return null;
    try {
      final pageLayouts = _pdfController.layout.pageLayouts;
      Rect? union;
      for (final b in bounds) {
        if (b.pageNumber < 1 ||
            b.pageNumber > doc.pages.length ||
            b.pageNumber > pageLayouts.length) {
          continue;
        }
        final docRect = _boundsToScreenRect(
            b, doc.pages[b.pageNumber - 1], pageLayouts[b.pageNumber - 1]);
        final tl = _pdfController.documentToGlobal(docRect.topLeft);
        final br = _pdfController.documentToGlobal(docRect.bottomRight);
        if (tl == null || br == null) continue;
        final r = Rect.fromPoints(tl, br);
        union = union == null ? r : union.expandToInclude(r);
      }
      return union;
    } catch (e) {
      debugPrint('[PDFRX] selection rect unavailable: $e');
      return null;
    }
  }

  // ── Context menu ──────────────────────────────────────────────────

  /// Shows the annotation menu above [position] (global), or below [belowY]
  /// when there is no room above. When [within] is given (the viewer's global
  /// rect) the menu is kept inside it, so in the split pane it never covers
  /// the video.
  void _showContextMenu(Offset position, {double? belowY, Rect? within}) {
    _removeContextMenu();

    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final screenSize = MediaQuery.of(context).size;
    final safePadding = MediaQuery.of(context).padding;

    final menuWidth = isTablet ? 310.0 : 260.0;
    final menuHeight = isTablet ? 56.0 : 46.0;

    final areaLeft = within?.left ?? 0;
    final areaRight = within?.right ?? screenSize.width;
    final areaTop = math.max(within?.top ?? 0, safePadding.top);
    final areaBottom = math.min(within?.bottom ?? screenSize.height,
        screenSize.height - safePadding.bottom);

    double left = position.dx - menuWidth / 2;
    double top = position.dy - menuHeight - 12;

    final minLeft = math.max(areaLeft, safePadding.left) + 8;
    final maxLeft = math.max(
        minLeft, math.min(areaRight, screenSize.width - safePadding.right) - menuWidth - 8);
    left = left.clamp(minLeft, maxLeft);

    // No room above the selection: put the menu just below it.
    if (top < areaTop + 8) top = (belowY ?? position.dy) + 12;
    // Never past the bottom of the area, never above its top.
    if (top + menuHeight > areaBottom - 8) top = areaBottom - menuHeight - 8;
    if (top < areaTop + 8) top = areaTop + 8;

    final overlay = Overlay.of(context);
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
                Container(
                  width: 1,
                  height: isTablet ? 28 : 22,
                  margin: EdgeInsets.symmetric(horizontal: isTablet ? 6 : 4),
                  color: isDark ? Colors.white24 : Colors.black12,
                ),
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

  // ── Convert pdfrx selections to AnnotationTextBounds ───────────────
  //
  // PdfTextRanges uses PDF coordinates (bottom-left origin, Y-up).
  // Bounds are STORED in the same coordinate system as Syncfusion
  // (top-left origin, Y-down, page points) so a highlight made in either
  // viewer renders in the right place in the other. `top` is converted here
  // (userSpaceHeight - pdfTop) and `_boundsToScreenRect` converts back at
  // paint time. (Older pdfrx builds stored y-up; see _isLegacyYUpRow.)

  List<AnnotationTextBounds> _selectionToBounds(
      List<PdfTextRanges> selections) {
    // pdfrx returns one fragment per WORD (and one per whitespace run), so a
    // 5-line selection generates ~100 fragments. Backend validation rejects
    // payloads with that many bounds entries (and the JSON balloons past
    // request-size caps). We collapse fragments to one entry per VISUAL LINE
    // by grouping on the (page, top) tuple, taking left = min(left),
    // right = max(right), text = concatenation. The on-screen highlight is
    // identical because each per-line rect spans the same area as the union
    // of its word fragments.
    final result = <AnnotationTextBounds>[];
    for (final sel in selections) {
      final pageNumber = sel.pageNumber;
      final doc = _document;
      if (doc == null || pageNumber < 1 || pageNumber > doc.pages.length) {
        continue;
      }
      final userSpaceHeight = _userSpaceHeight(doc.pages[pageNumber - 1]);
      final byLine = <int, _LineAccumulator>{};
      for (final range in sel.ranges) {
        final withFrags = range.toTextRangeWithFragments(sel.pageText);
        if (withFrags == null) continue;
        for (final frag in withFrags.fragments) {
          final b = frag.bounds;
          final key = (b.top * 2).round(); // 0.5pt buckets
          final existing = byLine[key];
          if (existing == null) {
            byLine[key] = _LineAccumulator(
              top: b.top,
              bottom: b.bottom,
              left: b.left,
              right: b.right,
              text: frag.text,
            );
          } else {
            existing.merge(b.left, b.right, b.top, b.bottom, frag.text);
          }
        }
      }
      final lines = byLine.values.toList()
        ..sort((a, b) => b.top.compareTo(a.top));
      for (final acc in lines) {
        result.add(AnnotationTextBounds(
          left: acc.left,
          top: userSpaceHeight - acc.top, // y-down (top-left origin)
          width: acc.right - acc.left,
          height: acc.top - acc.bottom, // PDF coords: top > bottom
          text: acc.text,
          pageNumber: pageNumber,
        ));
      }
    }
    return result;
  }

  // ── Highlight creation ────────────────────────────────────────────

  /// Returns the backend highlight_id on success, or null on failure.
  Future<String?> _highlightSelectedText(String color) async {
    // Use captured bounds (frozen at context menu show time) so that
    // selection clearing from the overlay tap doesn't lose data.
    final bounds = _capturedBounds ??
        (_currentSelections != null ? _selectionToBounds(_currentSelections!) : null);
    if (bounds == null || bounds.isEmpty) return null;

    final selectedText = _capturedText ?? _currentSelectedText ?? '';
    final highlightColor =
        highlightColors[color] ?? highlightColors['yellow']!;
    final firstPage = bounds.first.pageNumber;

    // Optimistic UI
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final data = _AnnotationData(bounds: bounds, color: highlightColor);
    _setAnnotationState(() {
      _highlights[tempId] = data;
      _annotationTexts[tempId] = selectedText;
      _annotationBounds[tempId] = bounds;
    });

    _currentSelections = null;
    _currentSelectedText = null;
    _capturedBounds = null;
    _capturedText = null;
    // Remove the selection highlight + handles so the new annotation is
    // visible straight away (they used to stay until the next tap).
    _clearTextSelection();

    if (widget.documentId != null) {
      try {
        final boundsData = bounds.map((b) => b.toJson()).toList();
        // Char offsets, not pixel coords. Backend rejects start >= end.
        // Old code used bounds.first.left / bounds.last.right (pixels) —
        // worked single-line, broke multi-line because last line wraps
        // shorter (last.right < first.left).
        final clippedText = selectedText.length > 2000
            ? selectedText.substring(0, 2000)
            : selectedText;
        final result = await _highlightService.addHighlight(
          documentId: widget.documentId!,
          pageNumber: firstPage,
          // start >= 1 marks "bounds are y-down" (old pdfrx rows used
          // start == 0 with y-up bounds). Backend requires end > start.
          startOffset: 1,
          endOffset: clippedText.length + 1,
          highlightedText: clippedText,
          color: color,
          boundsData: boundsData,
        );

        final highlightId = result['highlight_id'] as String;
        _setAnnotationState(() {
          _highlights[highlightId] = _highlights.remove(tempId)!;
          _annotationNotes[highlightId] = null;
          _annotationTexts[highlightId] = _annotationTexts.remove(tempId)!;
          _annotationBounds[highlightId] = _annotationBounds.remove(tempId)!;
          _undoStack.add((id: highlightId, type: 'highlight'));
        });
        return highlightId;
      } catch (e) {
        debugPrint('Failed to save highlight: $e');
        _setAnnotationState(() {
          _highlights.remove(tempId);
          _annotationTexts.remove(tempId);
          _annotationBounds.remove(tempId);
        });
        if (mounted) {
          showAppDialog(context,
              message: 'Failed to save highlight', type: AppDialogType.info);
        }
        return null;
      }
    }
    return tempId;
  }

  Future<void> _quickHighlightAndNote() async {
    final highlightId = await _highlightSelectedText('yellow');
    if (highlightId != null && mounted) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) _showNoteDialog(highlightId);
    }
  }

  // ── Underline creation + toggle ───────────────────────────────────

  bool _boundsOverlap(
      List<AnnotationTextBounds> a, List<AnnotationTextBounds> b) {
    for (final lineA in a) {
      for (final lineB in b) {
        if (lineA.pageNumber != lineB.pageNumber) continue;
        // Two lines overlap only when BOTH their x-ranges and y-ranges
        // intersect (bounds are top-left / y-down). Checking x alone made any
        // selection on the same page that shared a column with an existing
        // underline/highlight toggle that one off instead of adding a new one.
        final aLeft = lineA.left;
        final aRight = lineA.left + lineA.width;
        final bLeft = lineB.left;
        final bRight = lineB.left + lineB.width;
        final aTop = lineA.top;
        final aBottom = lineA.top + lineA.height;
        final bTop = lineB.top;
        final bBottom = lineB.top + lineB.height;
        if (aLeft < bRight && aRight > bLeft && aTop < bBottom && aBottom > bTop) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _underlineSelectedText() async {
    final bounds = _capturedBounds ??
        (_currentSelections != null ? _selectionToBounds(_currentSelections!) : null);
    if (bounds == null || bounds.isEmpty) return;

    // Toggle: check overlap with existing underlines
    for (final entry in _underlines.entries) {
      final storedBounds = _annotationBounds[entry.key];
      if (storedBounds == null) continue;
      if (_boundsOverlap(bounds, storedBounds)) {
        _currentSelections = null;
        _currentSelectedText = null;
        _capturedBounds = null;
        _capturedText = null;
        _clearTextSelection();
        _removeAnnotation(entry.key, isUnderline: true);
        return;
      }
    }

    final selectedText = _capturedText ?? _currentSelectedText ?? '';
    final firstPage = bounds.first.pageNumber;

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final data = _AnnotationData(bounds: bounds, color: underlineColor);
    _setAnnotationState(() {
      _underlines[tempId] = data;
      _annotationTexts[tempId] = selectedText;
      _annotationBounds[tempId] = bounds;
    });

    _currentSelections = null;
    _currentSelectedText = null;
    _capturedBounds = null;
    _capturedText = null;
    // Remove the selection highlight + handles so the new annotation is
    // visible straight away (they used to stay until the next tap).
    _clearTextSelection();

    if (widget.documentId != null) {
      try {
        final boundsData = bounds.map((b) => b.toJson()).toList();
        // Char offsets, not pixel coords. See _highlightSelectedText for
        // full rationale — multi-line wrap breaks the pixel-based version.
        final clippedText = selectedText.length > 2000
            ? selectedText.substring(0, 2000)
            : selectedText;
        final result = await _highlightService.addHighlight(
          documentId: widget.documentId!,
          pageNumber: firstPage,
          // start >= 1 marks "bounds are y-down" (old pdfrx rows used
          // start == 0 with y-up bounds). Backend requires end > start.
          startOffset: 1,
          endOffset: clippedText.length + 1,
          highlightedText: clippedText,
          color: 'blue',
          annotationType: 'underline',
          boundsData: boundsData,
        );

        final highlightId = result['highlight_id'] as String;
        _setAnnotationState(() {
          _underlines[highlightId] = _underlines.remove(tempId)!;
          _annotationNotes[highlightId] = null;
          _annotationTexts[highlightId] = _annotationTexts.remove(tempId)!;
          _annotationBounds[highlightId] = _annotationBounds.remove(tempId)!;
          _undoStack.add((id: highlightId, type: 'underline'));
        });
      } catch (e) {
        debugPrint('Failed to save underline: $e');
        _setAnnotationState(() {
          _underlines.remove(tempId);
          _annotationTexts.remove(tempId);
          _annotationBounds.remove(tempId);
        });
        if (mounted) {
          showAppDialog(context,
              message: 'Failed to save underline', type: AppDialogType.info);
        }
      }
    }
  }

  // ── Annotation removal ────────────────────────────────────────────

  Future<void> _removeAnnotation(String annotationId,
      {bool isUnderline = false}) async {
    // Optimistic remove (covers highlights, underlines AND standalone notes
    // — backend stores them all in the same collection).
    final removedHighlight = _highlights.remove(annotationId);
    final removedUnderline = _underlines.remove(annotationId);
    _annotationNotes.remove(annotationId);
    final removedText = _annotationTexts.remove(annotationId);
    final removedBounds = _annotationBounds.remove(annotationId);
    final removedStandalone = _standaloneNotes.remove(annotationId);
    // Strip from the undo stack so we don't try to undo something the
    // user has already deleted via the Notes panel or context menu.
    _undoStack.removeWhere((e) => e.id == annotationId);
    _setAnnotationState(() {});

    // Skip backend call for temp annotations (not yet persisted)
    if (annotationId.startsWith('temp_')) return;

    try {
      await _highlightService.deleteHighlight(annotationId);
    } catch (e) {
      debugPrint('Failed to delete annotation: $e');
      // Restore on failure
      if (mounted) {
        _setAnnotationState(() {
          if (removedHighlight != null) _highlights[annotationId] = removedHighlight;
          if (removedUnderline != null) _underlines[annotationId] = removedUnderline;
          if (removedText != null) _annotationTexts[annotationId] = removedText;
          if (removedBounds != null) _annotationBounds[annotationId] = removedBounds;
          if (removedStandalone != null) _standaloneNotes[annotationId] = removedStandalone;
        });
        showAppDialog(context,
            message: 'Failed to remove annotation', type: AppDialogType.info);
      }
    }
  }

  // ── Annotation menu (bottom sheet) ────────────────────────────────

  void _showAnnotationMenu(String annotationId, bool isUnderline) {
    _removeContextMenu();

    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    final hasNote = _annotationNotes[annotationId] != null;
    final noteText = hasNote ? _annotationNotes[annotationId] : null;
    final annotationText = _annotationTexts[annotationId];

    Color indicatorColor;
    if (isUnderline) {
      indicatorColor = underlineColor;
    } else {
      indicatorColor = (_highlights[annotationId]?.color ??
              highlightColors['yellow']!)
          .withValues(alpha: 1.0);
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
              if (hasNote && noteText != null) ...[
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isTablet ? 14 : 12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              AppColors.primaryBlue.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.sticky_note_2_outlined,
                            size: isTablet ? 18 : 16,
                            color: AppColors.primaryBlue),
                        SizedBox(width: isTablet ? 10 : 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('YOUR NOTE',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: isTablet ? 11 : 10,
                                    color: AppColors.primaryBlue,
                                    letterSpacing: 0.8,
                                  )),
                              const SizedBox(height: 4),
                              Text(noteText,
                                  style: TextStyle(
                                    fontSize: isTablet ? 14 : 13,
                                    color: textColor,
                                    height: 1.4,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis),
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
                  color:
                      isDark ? AppColors.darkDivider : const Color(0xFFF0F0F0)),
              // Add/Edit Note
              InkWell(
                onTap: () {
                  Navigator.pop(sheetContext);
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted) _showNoteDialog(annotationId);
                  });
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20,
                      vertical: isTablet ? 16 : 14),
                  child: Row(
                    children: [
                      Container(
                        width: isTablet ? 36 : 32,
                        height: isTablet ? 36 : 32,
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                            hasNote ? Icons.edit_note : Icons.note_add_outlined,
                            size: isTablet ? 20 : 18,
                            color: AppColors.primaryBlue),
                      ),
                      SizedBox(width: isTablet ? 14 : 12),
                      Text(hasNote ? 'Edit Note' : 'Add Note',
                          style: TextStyle(
                              fontSize: isTablet ? 16 : 15,
                              fontWeight: FontWeight.w500,
                              color: textColor)),
                      const Spacer(),
                      Icon(Icons.chevron_right,
                          size: isTablet ? 22 : 20, color: subtitleColor),
                    ],
                  ),
                ),
              ),
              Divider(
                height: 1,
                indent: isTablet ? 70 : 64,
                endIndent: isTablet ? 24 : 20,
                color: isDark ? AppColors.darkDivider : const Color(0xFFF0F0F0),
              ),
              // Remove
              InkWell(
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removeAnnotation(annotationId, isUnderline: isUnderline);
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20,
                      vertical: isTablet ? 16 : 14),
                  child: Row(
                    children: [
                      Container(
                        width: isTablet ? 36 : 32,
                        height: isTablet ? 36 : 32,
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.delete_outline,
                            size: isTablet ? 20 : 18, color: AppColors.error),
                      ),
                      SizedBox(width: isTablet ? 14 : 12),
                      Text(
                          isUnderline
                              ? 'Remove Underline'
                              : 'Remove Highlight',
                          style: TextStyle(
                              fontSize: isTablet ? 16 : 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.error)),
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

  // ── Note dialog ───────────────────────────────────────────────────

  void _showNoteDialog(String annotationId) {
    final existingNote = _annotationNotes[annotationId];
    final controller = TextEditingController(text: existingNote ?? '');
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final annotationText = _annotationTexts[annotationId];

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
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
                  child: Row(
                    children: [
                      Icon(
                          existingNote != null
                              ? Icons.edit_note
                              : Icons.note_add_outlined,
                          size: isTablet ? 24 : 22,
                          color: AppColors.primaryBlue),
                      SizedBox(width: isTablet ? 10 : 8),
                      Text(existingNote != null ? 'Edit Note' : 'Add Note',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontWeight: FontWeight.w700,
                            fontSize: isTablet ? 20 : 18,
                            color: textColor,
                          )),
                    ],
                  ),
                ),
                if (annotationText != null && annotationText.isNotEmpty) ...[
                  SizedBox(height: isTablet ? 14 : 12),
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 24 : 20),
                    child: Container(
                      padding: EdgeInsets.all(isTablet ? 14 : 12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border(
                            left: BorderSide(
                                color: AppColors.primaryBlue, width: 3)),
                      ),
                      child: Text(annotationText,
                          style: TextStyle(
                            fontSize: isTablet ? 14 : 13,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : Colors.grey[700],
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                SizedBox(height: isTablet ? 16 : 14),
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
                  child: TextField(
                    controller: controller,
                    maxLines: 4,
                    maxLength: 500,
                    autofocus: true,
                    style: TextStyle(
                        color: textColor,
                        fontSize: isTablet ? 15 : 14,
                        height: 1.5),
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
                            color: AppColors.primaryBlue, width: 1.5),
                      ),
                      counterStyle: TextStyle(
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : Colors.grey,
                          fontSize: 11),
                    ),
                  ),
                ),
                SizedBox(height: isTablet ? 18 : 14),
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
                  child: Row(
                    children: [
                      if (existingNote != null)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _saveAnnotationNote(annotationId, null);
                          },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Remove'),
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.error),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: Text('Cancel',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            )),
                      ),
                      SizedBox(width: isTablet ? 12 : 8),
                      Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.blueGradient,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.primaryBlue.withValues(alpha: 0.3),
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
                              _saveAnnotationNote(
                                  annotationId, note.isEmpty ? null : note);
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 28 : 24,
                                  vertical: isTablet ? 12 : 10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check,
                                      size: isTablet ? 18 : 16,
                                      color: Colors.white),
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

  Future<void> _saveAnnotationNote(String annotationId, String? note) async {
    try {
      await _highlightService.updateHighlightNote(annotationId, note);
      if (mounted) {
        setState(() => _annotationNotes[annotationId] = note);
      }
    } catch (e) {
      debugPrint('Failed to save note: $e');
      if (mounted) {
        showAppDialog(context,
            message: 'Failed to save note', type: AppDialogType.info);
      }
    }
  }

  // ── All notes panel ───────────────────────────────────────────────

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
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                // Collect ids from all three sources, then sort by page so
                // the panel reads in document order rather than insertion
                // order. Standalone notes interleave with highlights/
                // underlines naturally.
                final allIds = <String>[
                  ..._highlights.keys,
                  ..._underlines.keys,
                  ..._standaloneNotes.keys,
                ]..sort((a, b) {
                    final pa = _pageForAnnotationId(a) ?? 0;
                    final pb = _pageForAnnotationId(b) ?? 0;
                    return pa.compareTo(pb);
                  });

                return Column(
                  children: [
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
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 24 : 20),
                      child: Row(
                        children: [
                          Icon(Icons.sticky_note_2_outlined,
                              size: isTablet ? 24 : 22,
                              color: AppColors.primaryBlue),
                          SizedBox(width: isTablet ? 10 : 8),
                          Text('Your Notes & Highlights',
                              style: TextStyle(
                                fontFamily: 'SF Pro Display',
                                fontWeight: FontWeight.w700,
                                fontSize: isTablet ? 20 : 18,
                                color: textColor,
                              )),
                          const Spacer(),
                          Text('${allIds.length}',
                              style: TextStyle(
                                fontSize: isTablet ? 15 : 13,
                                color: subtitleColor,
                                fontWeight: FontWeight.w500,
                              )),
                          SizedBox(width: isTablet ? 14 : 10),
                          // "+ Add Note" — opens the page-number + text
                          // dialog. setSheetState refreshes this list once
                          // the new note is saved.
                          ElevatedButton.icon(
                            onPressed: () =>
                                _showAddStandaloneNoteDialog(setSheetState),
                            icon: const Icon(Icons.add, size: 16),
                            label: Text('Note',
                                style: TextStyle(
                                    fontSize: isTablet ? 13 : 12,
                                    fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 14 : 10,
                                  vertical: isTablet ? 8 : 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isTablet ? 12 : 10),
                    Divider(
                        height: 1,
                        color: isDark
                            ? AppColors.darkDivider
                            : const Color(0xFFF0F0F0)),
                    Expanded(
                      child: allIds.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.note_alt_outlined,
                                      size: isTablet ? 48 : 40,
                                      color: subtitleColor),
                                  SizedBox(height: isTablet ? 12 : 8),
                                  Text('No highlights or notes yet',
                                      style: TextStyle(
                                          fontSize: isTablet ? 16 : 14,
                                          color: subtitleColor)),
                                  SizedBox(height: isTablet ? 6 : 4),
                                  Text(
                                      'Long-press text to highlight, or tap "+ Note"',
                                      style: TextStyle(
                                          fontSize: isTablet ? 13 : 12,
                                          color: subtitleColor)),
                                ],
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              padding: EdgeInsets.symmetric(
                                  vertical: isTablet ? 10 : 8),
                              itemCount: allIds.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                indent: isTablet ? 70 : 60,
                                endIndent: isTablet ? 24 : 20,
                                color: isDark
                                    ? AppColors.darkDivider
                                    : const Color(0xFFF0F0F0),
                              ),
                              itemBuilder: (context, index) {
                                final id = allIds[index];
                                final isStandalone =
                                    _standaloneNotes.containsKey(id);
                                final isHighlight =
                                    _highlights.containsKey(id);
                                final isUnderline =
                                    _underlines.containsKey(id);
                                final pageNum = _pageForAnnotationId(id);

                                // Row content + accent color depend on type.
                                String primaryText;
                                String? noteText;
                                IconData typeIcon;
                                Color accentColor;
                                if (isStandalone) {
                                  primaryText =
                                      _standaloneNotes[id]!['note']
                                              as String? ??
                                          '';
                                  noteText = null;
                                  typeIcon = Icons.sticky_note_2_outlined;
                                  accentColor = const Color(0xFF43A047);
                                } else if (isHighlight) {
                                  primaryText = _annotationTexts[id] ?? '';
                                  noteText = _annotationNotes[id];
                                  typeIcon = Icons.border_color;
                                  accentColor =
                                      (_highlights[id]?.color ??
                                              highlightColors['yellow']!)
                                          .withValues(alpha: 1.0);
                                } else {
                                  primaryText = _annotationTexts[id] ?? '';
                                  noteText = _annotationNotes[id];
                                  typeIcon = Icons.format_underlined;
                                  accentColor = underlineColor;
                                }
                                final hasNote =
                                    noteText != null && noteText.isNotEmpty;

                                return InkWell(
                                  // Tap on body always jumps to the page —
                                  // editing now lives behind the pen icon on
                                  // the right.
                                  onTap: () => _jumpToPageFromSheet(
                                      sheetContext, pageNum),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: isTablet ? 24 : 20,
                                        vertical: isTablet ? 14 : 12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
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
                                            typeIcon,
                                            size: isTablet ? 18 : 16,
                                            color: accentColor,
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Page badge — what the user
                                              // explicitly asked for.
                                              if (pageNum != null)
                                                Padding(
                                                  padding: EdgeInsets.only(
                                                      bottom:
                                                          isTablet ? 6 : 4),
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: AppColors
                                                              .primaryBlue
                                                          .withValues(
                                                              alpha: 0.12),
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(8),
                                                    ),
                                                    child: Text(
                                                      'p. $pageNum',
                                                      style: TextStyle(
                                                        fontFamily:
                                                            'SF Pro Display',
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: isTablet
                                                            ? 11
                                                            : 10,
                                                        color: AppColors
                                                            .primaryBlue,
                                                        height: 1.0,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              Text(
                                                  primaryText.isNotEmpty
                                                      ? primaryText
                                                      : '(empty)',
                                                  style: TextStyle(
                                                    fontSize:
                                                        isTablet ? 14 : 13,
                                                    color: textColor,
                                                    fontStyle: isStandalone
                                                        ? FontStyle.normal
                                                        : FontStyle.italic,
                                                    height: 1.3,
                                                  ),
                                                  maxLines: 3,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              if (hasNote) ...[
                                                SizedBox(
                                                    height:
                                                        isTablet ? 6 : 4),
                                                Row(
                                                  children: [
                                                    Icon(
                                                        Icons
                                                            .sticky_note_2_outlined,
                                                        size: isTablet
                                                            ? 14
                                                            : 12,
                                                        color: AppColors
                                                            .primaryBlue),
                                                    SizedBox(
                                                        width: isTablet
                                                            ? 6
                                                            : 4),
                                                    Expanded(
                                                      child: Text(noteText,
                                                          style: TextStyle(
                                                            fontSize: isTablet
                                                                ? 13
                                                                : 12,
                                                            color: AppColors
                                                                .primaryBlue,
                                                            height: 1.3,
                                                          ),
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow
                                                                  .ellipsis),
                                                    ),
                                                  ],
                                                ),
                                              ] else if (!isStandalone) ...[
                                                SizedBox(
                                                    height:
                                                        isTablet ? 4 : 2),
                                                Text('Tap to add note',
                                                    style: TextStyle(
                                                      fontSize: isTablet
                                                          ? 12
                                                          : 11,
                                                      color: subtitleColor,
                                                    )),
                                              ],
                                            ],
                                          ),
                                        ),
                                        // Edit — opens the note editor for
                                        // the annotation. Highlights/underlines
                                        // reuse the existing dialog; standalone
                                        // notes get a dedicated edit sheet.
                                        IconButton(
                                          tooltip: 'Edit note',
                                          onPressed: () {
                                            Navigator.pop(sheetContext);
                                            Future.delayed(
                                                const Duration(
                                                    milliseconds: 300), () {
                                              if (!mounted) return;
                                              if (isStandalone) {
                                                _showEditStandaloneNoteDialog(
                                                    id);
                                              } else {
                                                _showNoteDialog(id);
                                              }
                                            });
                                          },
                                          icon: Icon(Icons.edit_outlined,
                                              size: isTablet ? 22 : 20,
                                              color: AppColors.primaryBlue),
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(
                                              minWidth: isTablet ? 36 : 32,
                                              minHeight: isTablet ? 36 : 32),
                                        ),
                                        IconButton(
                                          tooltip: 'Delete',
                                          onPressed: () {
                                            _removeAnnotation(id,
                                                isUnderline: isUnderline);
                                            setSheetState(() {});
                                          },
                                          icon: Icon(Icons.delete_outline,
                                              size: isTablet ? 22 : 20,
                                              color: AppColors.error
                                                  .withValues(alpha: 0.7)),
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(
                                              minWidth: isTablet ? 36 : 32,
                                              minHeight: isTablet ? 36 : 32),
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

  // ── Outline (PDF table-of-contents) ───────────────────────────────

  /// Loads the PDF's embedded outline (chapter/subtopic tree) once the
  /// document is ready. Some PDFs (especially scans) have no outline —
  /// the result is then an empty list, which the toolbar uses to hide
  /// the TOC button.
  Future<void> _loadOutline() async {
    final doc = _document;
    if (doc == null) return;
    try {
      final outline = await doc.loadOutline();
      if (mounted) setState(() => _outline = outline);
    } catch (e) {
      debugPrint('[PDFRX] Failed to load outline: $e');
      if (mounted) setState(() => _outline = const []);
    }
  }

  /// Asks the user for a page number and jumps to it. Triggered by tapping
  /// the page-indicator badge in the toolbar — same pattern as Kindle's
  /// "Go to page" affordance.
  void _showGoToPageDialog() {
    if (_totalPages <= 0) return;
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    showDialog<void>(
      context: context,
      builder: (ctx) => _GoToPageDialog(
        initialPage: _currentPage.value,
        totalPages: _totalPages,
        isDark: isDark,
        isTablet: isTablet,
        onSubmit: (n) {
          // Defer jump until after dialog + keyboard close animations
          // settle. See _GoToPageDialog for full rationale.
          Future.delayed(const Duration(milliseconds: 350), () {
            // Immediate jump (no animation): hiding the keyboard resizes the
            // viewport, which cancels an in-flight animated jump and leaves
            // the viewer on a much earlier page.
            if (mounted) {
              _pdfController.goToPage(pageNumber: n, duration: Duration.zero);
            }
          });
        },
      ),
    );
  }

  /// Builds the left-side TOC drawer. Shown only when [_outline] is
  /// non-null and non-empty. Renders the outline tree recursively via
  /// [_buildOutlineNode]; each leaf entry jumps to its page on tap.
  Widget _buildOutlineDrawer(bool isDark, bool isTablet) {
    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;
    final subtitleColor =
        isDark ? AppColors.darkTextSecondary : Colors.grey[600]!;
    final dividerColor =
        isDark ? AppColors.darkDivider : const Color(0xFFF0F0F0);
    final outline = _outline ?? const [];
    return Drawer(
      backgroundColor: bgColor,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  isTablet ? 20 : 16, isTablet ? 16 : 12, isTablet ? 12 : 8, isTablet ? 12 : 10),
              child: Row(
                children: [
                  Icon(Icons.menu_book_outlined,
                      size: isTablet ? 24 : 22, color: AppColors.primaryBlue),
                  SizedBox(width: isTablet ? 10 : 8),
                  Expanded(
                    child: Text('Contents',
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontWeight: FontWeight.w700,
                          fontSize: isTablet ? 20 : 18,
                          color: textColor,
                        )),
                  ),
                  IconButton(
                    onPressed: () =>
                        _scaffoldKey.currentState?.closeDrawer(),
                    icon: Icon(Icons.close,
                        size: isTablet ? 22 : 20, color: textColor),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: dividerColor),
            Expanded(
              // Three states: loading, empty (no outline in the PDF), tree.
              child: _outline == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                          SizedBox(height: isTablet ? 14 : 10),
                          Text('Loading outline…',
                              style: TextStyle(
                                fontSize: isTablet ? 14 : 12,
                                color: subtitleColor,
                              )),
                        ],
                      ),
                    )
                  : outline.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.list_alt_outlined,
                                    size: isTablet ? 48 : 40,
                                    color: subtitleColor),
                                SizedBox(height: isTablet ? 12 : 8),
                                Text('No table of contents',
                                    style: TextStyle(
                                      fontSize: isTablet ? 16 : 14,
                                      color: subtitleColor,
                                    )),
                                SizedBox(height: isTablet ? 6 : 4),
                                Text(
                                  'This PDF doesn\'t include an embedded outline',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: isTablet ? 13 : 12,
                                    color: subtitleColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          padding: EdgeInsets.symmetric(
                              vertical: isTablet ? 8 : 6),
                          children: outline
                              .map((node) => _buildOutlineNode(
                                  node, 0, isDark, isTablet,
                                  textColor: textColor,
                                  subtitleColor: subtitleColor))
                              .toList(),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Recursive node builder. Leaves render as ListTile; nodes with
  /// children render as ExpansionTile with this method called recursively
  /// for each child. [depth] is used to indent nested entries.
  Widget _buildOutlineNode(
    PdfOutlineNode node,
    int depth,
    bool isDark,
    bool isTablet, {
    required Color textColor,
    required Color subtitleColor,
  }) {
    final pageNumber = node.dest?.pageNumber;
    final indent = (isTablet ? 16.0 : 12.0) + depth * (isTablet ? 16.0 : 12.0);
    final pageBadge = pageNumber == null
        ? null
        : Text('p. $pageNumber',
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontWeight: FontWeight.w500,
              fontSize: isTablet ? 12 : 11,
              color: subtitleColor,
            ));

    void jump() {
      if (pageNumber == null || pageNumber < 1) return;
      _scaffoldKey.currentState?.closeDrawer();
      // Defer slightly so the drawer-close animation runs first.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _pdfController.goToPage(pageNumber: pageNumber);
      });
    }

    if (node.children.isEmpty) {
      return InkWell(
        onTap: jump,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              indent, isTablet ? 12 : 10, isTablet ? 16 : 12, isTablet ? 12 : 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  node.title.isEmpty ? '(untitled)' : node.title,
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontWeight: FontWeight.w400,
                    fontSize: isTablet ? 15 : 13,
                    color: textColor,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (pageBadge != null) ...[
                SizedBox(width: isTablet ? 12 : 8),
                pageBadge,
              ],
            ],
          ),
        ),
      );
    }

    return Theme(
      // Strip the default ExpansionTile divider lines for a cleaner look.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.fromLTRB(
            indent, 0, isTablet ? 16 : 12, 0),
        childrenPadding: EdgeInsets.zero,
        iconColor: subtitleColor,
        collapsedIconColor: subtitleColor,
        title: GestureDetector(
          onTap: pageNumber != null ? jump : null,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: isTablet ? 4 : 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    node.title.isEmpty ? '(untitled)' : node.title,
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 15 : 13,
                      color: textColor,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (pageBadge != null) ...[
                  SizedBox(width: isTablet ? 12 : 8),
                  pageBadge,
                ],
              ],
            ),
          ),
        ),
        children: node.children
            .map((child) => _buildOutlineNode(
                child, depth + 1, isDark, isTablet,
                textColor: textColor, subtitleColor: subtitleColor))
            .toList(),
      ),
    );
  }

  /// Closes the Notes panel and jumps the viewer to [pageNumber].
  /// Used by both the per-row "Go to page" button and the row tap on
  /// standalone notes.
  void _jumpToPageFromSheet(BuildContext sheetContext, int? pageNumber) {
    if (pageNumber == null) return;
    Navigator.pop(sheetContext);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _pdfController.goToPage(pageNumber: pageNumber);
    });
  }

  // ── Undo last annotation ──────────────────────────────────────────

  /// Pops the most recent annotation off [_undoStack], removes it locally
  /// across all relevant maps, and tells the backend to delete it.
  /// Failures are logged but do NOT re-push the entry — the user can
  /// always recreate the annotation manually if needed, and a half-deleted
  /// state is worse than a stale stack entry.
  Future<void> _undoLastAnnotation() async {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    final id = entry.id;

    // Local cleanup across every map that might hold this id. We don't
    // distinguish by type here because cross-removal is harmless — only
    // the matching map(s) actually contain the id.
    _highlights.remove(id);
    _underlines.remove(id);
    _annotationNotes.remove(id);
    _annotationTexts.remove(id);
    _annotationBounds.remove(id);
    _standaloneNotes.remove(id);
    _setAnnotationState(() {});

    if (id.startsWith('temp_')) return;
    try {
      await _highlightService.deleteHighlight(id);
    } catch (e) {
      debugPrint('Failed to undo: $e');
      if (mounted) {
        showAppDialog(context,
            message: 'Failed to undo last action',
            type: AppDialogType.info);
      }
    }
  }

  // ── Standalone notes (page-only, no bounds) ───────────────────────

  /// Returns the page number an annotation belongs to. Highlights/underlines
  /// derive from their first AnnotationTextBounds; standalone notes use
  /// their stored page_number. Returns null if id is unknown.
  int? _pageForAnnotationId(String id) {
    final bounds = _annotationBounds[id];
    if (bounds != null && bounds.isNotEmpty) return bounds.first.pageNumber;
    final standalone = _standaloneNotes[id];
    if (standalone != null) return standalone['page_number'] as int?;
    return null;
  }

  /// Persists a new standalone note (annotation_type='note') and updates
  /// local state. The backend stores it in the same `highlights` collection
  /// with empty bounds_data. setSheetState (if non-null) is the StateSetter
  /// of the surrounding bottom sheet so the list refreshes after save.
  Future<void> _saveStandaloneNote(
      int pageNum, String note, StateSetter? setSheetState) async {
    if (widget.documentId == null) return;
    try {
      final result = await _highlightService.addHighlight(
        documentId: widget.documentId!,
        pageNumber: pageNum,
        startOffset: 0,
        endOffset: 0,
        highlightedText: '',
        note: note,
        boundsData: const [],
        annotationType: 'note',
      );
      final noteId = result['highlight_id'] as String;
      final entry = {
        'page_number': pageNum,
        'note': note,
      };
      _standaloneNotes[noteId] = entry;
      _undoStack.add((id: noteId, type: 'note'));
      if (mounted) {
        setState(() {});
        setSheetState?.call(() {});
      }
    } catch (e) {
      debugPrint('Failed to save standalone note: $e');
      if (mounted) {
        showAppDialog(context,
            message: 'Failed to save note', type: AppDialogType.info);
      }
    }
  }

  /// Bottom sheet that asks the user for a page number + note text and
  /// then calls [_saveStandaloneNote]. Mirrors the Syncfusion variant
  /// for parity. [setSheetState] is the parent Notes-panel StateSetter
  /// so the list refreshes when this sheet closes.
  void _showAddStandaloneNoteDialog(StateSetter? setSheetState) {
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;
    final pageController =
        TextEditingController(text: _currentPage.value.toString());
    final noteController = TextEditingController();
    final totalPages = _totalPages > 0 ? _totalPages : _pdfController.pageCount;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
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
                  padding:
                      EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
                  child: TextField(
                    controller: pageController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                        color: textColor, fontSize: isTablet ? 15 : 14),
                    decoration: InputDecoration(
                      hintText: 'Page number (1-$totalPages)',
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
                    ),
                  ),
                ),
                SizedBox(height: isTablet ? 12 : 8),
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
                  child: TextField(
                    controller: noteController,
                    maxLines: 4,
                    maxLength: 500,
                    autofocus: true,
                    style: TextStyle(
                        color: textColor,
                        fontSize: isTablet ? 15 : 14,
                        height: 1.5),
                    decoration: InputDecoration(
                      hintText: 'Write your note…',
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
                      counterStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.grey,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: isTablet ? 16 : 12),
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
                  child: Row(
                    children: [
                      const Spacer(),
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
                      SizedBox(width: isTablet ? 12 : 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          final pageNum =
                              int.tryParse(pageController.text.trim());
                          final note = noteController.text.trim();
                          if (pageNum == null ||
                              pageNum < 1 ||
                              pageNum > totalPages) {
                            showAppDialog(context,
                                message:
                                    'Enter a valid page number (1-$totalPages)',
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
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Save'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                              horizontal: isTablet ? 24 : 20,
                              vertical: isTablet ? 12 : 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
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

  /// Edits an existing standalone note's text. Page number stays put —
  /// there's no UX precedent for moving a saved note to a different
  /// page in this app, and the page badge already shows where it lives.
  void _showEditStandaloneNoteDialog(String noteId) {
    final entry = _standaloneNotes[noteId];
    if (entry == null) return;
    final existingNote = entry['note'] as String? ?? '';
    final pageNum = entry['page_number'] as int?;

    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;
    final controller = TextEditingController(text: existingNote);

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
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
                  child: Row(
                    children: [
                      Icon(Icons.edit_note,
                          size: isTablet ? 24 : 22,
                          color: AppColors.primaryBlue),
                      SizedBox(width: isTablet ? 10 : 8),
                      Text(
                          pageNum != null
                              ? 'Edit Note · p. $pageNum'
                              : 'Edit Note',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontWeight: FontWeight.w700,
                            fontSize: isTablet ? 20 : 18,
                            color: textColor,
                          )),
                    ],
                  ),
                ),
                SizedBox(height: isTablet ? 16 : 14),
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
                  child: TextField(
                    controller: controller,
                    maxLines: 4,
                    maxLength: 500,
                    autofocus: true,
                    style: TextStyle(
                        color: textColor,
                        fontSize: isTablet ? 15 : 14,
                        height: 1.5),
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
                            color: AppColors.primaryBlue, width: 1.5),
                      ),
                      counterStyle: TextStyle(
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : Colors.grey,
                          fontSize: 11),
                    ),
                  ),
                ),
                SizedBox(height: isTablet ? 18 : 14),
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
                  child: Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: Text('Cancel',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            )),
                      ),
                      SizedBox(width: isTablet ? 12 : 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          final note = controller.text.trim();
                          if (note.isEmpty) {
                            showAppDialog(context,
                                message: 'Note cannot be empty',
                                type: AppDialogType.info);
                            return;
                          }
                          Navigator.pop(sheetContext);
                          _updateStandaloneNoteText(noteId, note);
                        },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Save'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                              horizontal: isTablet ? 24 : 20,
                              vertical: isTablet ? 12 : 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
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

  Future<void> _updateStandaloneNoteText(String noteId, String note) async {
    try {
      await _highlightService.updateHighlightNote(noteId, note);
      if (mounted) {
        setState(() {
          final entry = _standaloneNotes[noteId];
          if (entry != null) entry['note'] = note;
        });
      }
    } catch (e) {
      debugPrint('Failed to update standalone note: $e');
      if (mounted) {
        showAppDialog(context,
            message: 'Failed to save note', type: AppDialogType.info);
      }
    }
  }

  // ── Search ────────────────────────────────────────────────────────

  void _toggleSearch() {
    setState(() => _isSearchOpen = !_isSearchOpen);
    if (!_isSearchOpen) {
      _textSearcher?.resetTextSearch();
      _searchController.clear();
    }
  }

  // ── Selection guard for bottom bar ────────────────────────────────

  void _requireSelectionOr(VoidCallback action) {
    // Also check captured bounds (from context menu) in case live selection cleared
    final hasSelection = (_currentSelections != null && _currentSelections!.isNotEmpty) ||
        (_capturedBounds != null && _capturedBounds!.isNotEmpty);
    if (!hasSelection) {
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

  // ── Build ─────────────────────────────────────────────────────────

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
      // Edge-swipe to open drawers is OFF. Otherwise Scaffold's
      // HorizontalDragGestureRecognizer wins the gesture arena against
      // pdfrx's pan recognizer for any horizontal-from-rest drag, blocking
      // horizontal pan when the PDF is zoomed. Drawers remain openable
      // via the overflow menu / scaffoldKey.openDrawer().
      drawerEnableOpenDragGesture: false,
      endDrawerEnableOpenDragGesture: false,
      // Left drawer is the PDF outline / TOC. Always available once the
      // document is loaded; the drawer itself renders one of three states:
      //   - loading (outline fetch in flight)
      //   - empty   (PDF has no embedded outline — explicit "no contents")
      //   - tree    (the chapter list)
      drawer: _document != null
          ? _buildOutlineDrawer(isDark, isTablet)
          : null,
      endDrawer: widget.documentId != null
          ? BookmarksDrawer(
              bookmarkedPages: _bookmarkedPages,
              bookmarkNotes: _bookmarkNotes,
              isDark: isDark,
              isTablet: isTablet,
              onJumpToPage: (page) {
                _scaffoldKey.currentState?.closeEndDrawer();
                _pdfController.goToPage(pageNumber: page);
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
                    showAppDialog(context,
                        message: 'Failed to delete bookmark',
                        type: AppDialogType.info);
                  }
                }
              },
              onUpdateNote: (bookmarkId, note) async {
                try {
                  await _bookmarkService.updateBookmarkNote(bookmarkId, note);
                  if (mounted) {
                    setState(() => _bookmarkNotes[bookmarkId] = note);
                  }
                } catch (e) {
                  if (mounted) {
                    showAppDialog(context,
                        message: 'Failed to update bookmark note',
                        type: AppDialogType.info);
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
              : _document == null
                  // PDF file resolved but pages still loading — show full-
                  // screen progress so the user CANNOT see / interact with
                  // a half-loaded document.
                  ? _buildPageLoadingView(isTablet, isDark)
                  // No safety-overlay here. _isPdfReady is now set
                  // synchronously with _document in _loadDocumentFully, so
                  // by the time we enter this branch (_document != null)
                  // the bottom action bar is always shown and there's no
                  // legitimate reason to render a "still loading" overlay.
                  // The previous Positioned.fill overlay was an opaque
                  // white sheet that visually merged with the PDF page
                  // background and looked like a stuck spinner.
                  : Column(
                      children: [
                        // Tapping the page hides the toolbar and the bottom
                        // action bar so the text gets the whole screen. They
                        // stay visible while searching, and in the video
                        // split pane (embedded) where the close button lives
                        // in the toolbar.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          alignment: Alignment.topCenter,
                          child: _showChrome
                              ? _buildToolbar(
                                  isDark, textColor, toolbarColor, isTablet)
                              // Keep the status-bar inset while hidden.
                              : SizedBox(
                                  width: double.infinity,
                                  height: MediaQuery.of(context).padding.top),
                        ),
                        Expanded(
                          child: Listener(
                            key: _viewerAreaKey,
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: _onViewerPointerDown,
                            onPointerUp: _onViewerPointerUp,
                            onPointerCancel: (_) => _tapPointer = null,
                            child: _buildPdfViewer(),
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          alignment: Alignment.bottomCenter,
                          child: _showChrome
                              ? _buildBottomActionBar(isDark, isTablet)
                              : SizedBox(
                                  width: double.infinity,
                                  height: MediaQuery.of(context).padding.bottom),
                        ),
                      ],
                    ),
    );
  }

  /// Full-screen progress view shown between "PDF file is ready on disk"
  /// and "all pages are measured". Blocks the user from seeing the partly-
  /// loaded document — which would otherwise let them try to scroll past
  /// pages that pdfrx hasn't measured yet.
  Widget _buildPageLoadingView(bool isTablet, bool isDark) {
    final hasTotal = _totalPages > 0;
    final progress = hasTotal ? _loadedPages / _totalPages : null;
    final pct = hasTotal ? ((_loadedPages / _totalPages) * 100).toInt() : 0;
    return Container(
      color: isDark ? AppColors.darkBackground : Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: isTablet ? 80 : 64,
              height: isTablet ? 80 : 64,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: isTablet ? 5 : 4,
                color: AppColors.primaryBlue,
                backgroundColor: (isDark
                        ? AppColors.darkDivider
                        : const Color(0xFFE0E0E0))
                    .withValues(alpha: 0.4),
              ),
            ),
            SizedBox(height: isTablet ? 28 : 24),
            Text(
              'Preparing document',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: isTablet ? 18 : 15,
                color: isDark ? AppColors.darkTextPrimary : Colors.black87,
              ),
            ),
            SizedBox(height: isTablet ? 12 : 10),
            Text(
              hasTotal
                  ? '$_loadedPages / $_totalPages pages  •  $pct%'
                  : 'Opening file…',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w400,
                fontSize: isTablet ? 14 : 12,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : const Color(0xFF666666),
              ),
            ),
            SizedBox(height: isTablet ? 8 : 6),
            Text(
              'Loading all pages so the document is fully scrollable',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w400,
                fontSize: isTablet ? 12 : 11,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : const Color(0xFF888888),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfViewer() {
    // Cache the viewer so setState never recreates it (which would reset
    // the document, scroll position, and internal pdfrx state).
    // Annotation repaints are triggered via _pdfController.invalidate().
    // Use the pre-loaded document via PdfDocumentRefDirect — by the time
    // _buildPdfViewer is called, _document is fully loaded (all pages
    // measured) so the viewer mounts ready-to-scroll, no progressive
    // loading races. autoDispose:false because we own the doc lifecycle
    // (disposed in screen dispose()).
    _cachedPdfViewer ??= PdfViewer(
      PdfDocumentRefDirect(_document!, autoDispose: false),
      controller: _pdfController,
      params: PdfViewerParams(
        enableTextSelection: true,
        // No surrounding whitespace — page fills viewport edge-to-edge.
        // pdfrx default is 8px which leaves a visible grey border around
        // and between pages.
        margin: 0,
        // Match the screen background so any non-page area (e.g. when the
        // viewer is in dark mode and the page hasn't rendered yet) doesn't
        // flash grey. Default is Colors.grey.
        backgroundColor: Colors.transparent,
        // Initial zoom = coverZoom -> page fills viewport WIDTH (overflowing
        // vertically, which is desired for vertical scrolling). pdfrx
        // default is fitZoom which leaves left/right whitespace because the
        // entire page is fitted into the viewport.
        calculateInitialZoom:
            (document, controller, fitZoom, coverZoom) => coverZoom,
        // Cap the rendered-page bitmap cache. pdfrx default is 100MB which
        // is too generous for mid-tier Android tablets where the per-app heap
        // is 256-384MB. 50MB holds 8-12 page bitmaps at typical sizes —
        // plenty for smooth scroll-back without dominating the heap.
        maxImageBytesCachedOnMemory: 50 * 1024 * 1024,
        // Custom layout that gives a final scroll extent IMMEDIATELY based
        // on page count + the first measured page's size. The default pdfrx
        // layout iterates pages as pdfium reports their sizes, so the scroll
        // extent grows from "1 page" to "1500 pages" over a few seconds —
        // during which time scrolling past the already-measured pages is
        // blocked. Estimating up-front lets the user scroll anywhere from
        // the first frame; layout refines silently as exact sizes arrive.
        layoutPages: (pages, params) {
          if (pages.isEmpty) {
            return PdfPageLayout(pageLayouts: const [], documentSize: Size.zero);
          }
          // Find any page that has already been measured (sizes load
          // asynchronously; early calls may have only the first page sized).
          // Manual loop instead of `firstWhere` because `pages` is a list of
          // pdfium-specific subtype (_PdfPagePdfium) and Dart's variance
          // rules reject an `orElse` returning the abstract `PdfPage`.
          double estW = pages.first.width;
          double estH = pages.first.height;
          for (final p in pages) {
            if (p.width > 0 && p.height > 0) {
              estW = p.width;
              estH = p.height;
              break;
            }
          }
          // Use the pre-fetched total page count so the scroll extent is
          // FINAL from the first call. Without this, pdfrx's progressive
          // loader grows the layout over ~10s for big docs and the user
          // cannot scroll past the loaded chunk.
          final pageCount =
              _totalPages > pages.length ? _totalPages : pages.length;
          // Document width = widest known page (or estimate if all unknown).
          double maxW = estW;
          for (final p in pages) {
            final w = p.width > 0 ? p.width : estW;
            if (w > maxW) maxW = w;
          }
          final docW = maxW + params.margin * 2;
          final layouts = <Rect>[];
          var y = params.margin;
          for (int i = 0; i < pageCount; i++) {
            final page = i < pages.length ? pages[i] : null;
            final w = (page != null && page.width > 0) ? page.width : estW;
            final h = (page != null && page.height > 0) ? page.height : estH;
            layouts.add(Rect.fromLTWH((docW - w) / 2, y, w, h));
            y += h + params.margin;
          }
          return PdfPageLayout(
              pageLayouts: layouts, documentSize: Size(docW, y));
        },
        // Suppress native copy/share/search toolbar on text selection
        selectableRegionInjector: (context, child) => SelectionArea(
          key: _selectionAreaKey,
          contextMenuBuilder: (context, selectableRegionState) =>
              const SizedBox.shrink(),
          child: child,
        ),
        viewerOverlayBuilder: (context, size, handleLinkTap) => [
          PdfViewerScrollThumb(
            controller: _pdfController,
            orientation: ScrollbarOrientation.right,
          ),
        ],
        pagePaintCallbacks: [
          _paintAnnotations,
          // Stable closure — defers to _textSearcher at paint time. Required
          // because _cachedPdfViewer is built once with _textSearcher == null
          // (the searcher needs _pdfController to be ready, which only
          // happens after the viewer mounts). Without this wrapper, the
          // painter callback is never registered and search highlights
          // never appear.
          (canvas, pageRect, page) =>
              _textSearcher?.pageTextMatchPaintCallback(canvas, pageRect, page),
        ],
        pageOverlaysBuilder: _buildPageOverlays,
        onPageChanged: (pageNumber) {
          if (pageNumber != null) {
            _currentPage.value = pageNumber;
            _debouncedSaveProgress(pageNumber);
          }
        },
        onDocumentChanged: (document) {
          if (document != null && !_isPdfReady) {
            setState(() => _isPdfReady = true);
            _textSearcher = PdfTextSearcher(_pdfController);
            _loadHighlights();
            _loadBookmarks();
            _restoreProgress();
          }
        },
        onTextSelectionChange: _handleTextSelectionChange,
      ),
    );

    // ColorFiltered is ALWAYS present so the widget tree at this slot
    // doesn't change shape on toggle — see the comment on
    // [_identityColorFilter] for why that matters. Only the matrix swaps.
    return ColorFiltered(
      colorFilter:
          _isPdfDarkMode ? _invertColorFilter : _identityColorFilter,
      child: _cachedPdfViewer!,
    );
  }

  // ── Toolbar ───────────────────────────────────────────────────────

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
                GestureDetector(
                  onTap: () {
                    if (widget.embedded) {
                      widget.onClose?.call();
                    } else {
                      context.pop();
                    }
                  },
                  child: Container(
                    width: isTablet ? 44 : 36,
                    height: isTablet ? 44 : 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? AppColors.darkSurface
                          : const Color(0xFFF5F5F5),
                    ),
                    child: Icon(widget.embedded ? Icons.close : Icons.arrow_back,
                        size: isTablet ? 22 : 18, color: textColor),
                  ),
                ),
                SizedBox(width: isTablet ? 12 : 8),
                Expanded(
                  child: Text(widget.title,
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 18 : 15,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                // Tappable page-indicator badge — opens "Go to page" dialog.
                // Hidden until _totalPages is known (avoids "1 / 0" flash).
                if (_totalPages > 0)
                  ValueListenableBuilder<int>(
                    valueListenable: _currentPage,
                    builder: (context, page, _) {
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
                            borderRadius:
                                BorderRadius.circular(isTablet ? 12 : 10),
                          ),
                          child: Text(
                            '$page / $_totalPages',
                            style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontWeight: FontWeight.w600,
                              fontSize: isTablet ? 13 : 11,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                // Current-page bookmark toggle stays on the toolbar — it's
                // the only one-tap action that depends on which page you're
                // on, so it earns its slot.
                if (widget.documentId != null)
                  ValueListenableBuilder<int>(
                    valueListenable: _currentPage,
                    builder: (context, currentPage, _) {
                      final isBookmarked =
                          _bookmarkedPages.containsKey(currentPage);
                      return GestureDetector(
                        onTap: _toggleBookmark,
                        child: Container(
                          width: isTablet ? 44 : 36,
                          height: isTablet ? 44 : 36,
                          margin: EdgeInsets.only(right: isTablet ? 4 : 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isBookmarked
                                ? AppColors.primaryBlue
                                    .withValues(alpha: 0.1)
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
                GestureDetector(
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
                // Overflow / hamburger — TOC, all-bookmarks list, and the
                // dark-reader toggle live here so the toolbar stays uncluttered.
                _buildOverflowMenu(isDark, textColor, isTablet),
              ],
            ),
            if (_isSearchOpen) ...[
              SizedBox(height: isTablet ? 10 : 8),
              _buildSearchBar(isDark, textColor, isTablet),
            ],
          ],
        ),
      ),
    );
  }

  /// Overflow menu for the toolbar — keeps the row uncluttered by housing
  /// affordances that don't need one-tap access: the dark-reader toggle
  /// and the bookmarks list (when there's at least one). The TOC entry
  /// is currently commented out (see block below); re-enable it together
  /// with the `hasDocument` local and the `'toc'` switch case to bring
  /// back the table-of-contents drawer affordance.
  Widget _buildOverflowMenu(bool isDark, Color textColor, bool isTablet) {
    final hasBookmarks =
        widget.documentId != null && _bookmarkedPages.isNotEmpty;
    // final hasDocument = _document != null; // re-enable with the TOC entry below
    final menuTextColor =
        isDark ? AppColors.darkTextPrimary : Colors.black87;
    return Container(
      width: isTablet ? 44 : 36,
      height: isTablet ? 44 : 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5),
      ),
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon:
            Icon(Icons.more_vert, size: isTablet ? 22 : 18, color: textColor),
        tooltip: 'More',
        color: isDark ? AppColors.darkCardBackground : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        onSelected: (value) {
          switch (value) {
            // case 'toc': // re-enable with the TOC PopupMenuItem below
            //   _scaffoldKey.currentState?.openDrawer();
            //   break;
            case 'bookmarks':
              _scaffoldKey.currentState?.openEndDrawer();
              break;
            case 'theme':
              setState(() => _isPdfDarkMode = !_isPdfDarkMode);
              break;
            case 'keep_screen_on':
              setState(() => _keepScreenOn = !_keepScreenOn);
              if (_keepScreenOn) {
                WakelockPlus.enable();
              } else {
                WakelockPlus.disable();
              }
              break;
            case 'lock_rotation':
              _toggleRotationLock();
              break;
          }
        },
        itemBuilder: (context) => [
          // Dark / light reader toggle promoted to the top slot — replaced
          // the Table-of-contents entry that used to live here.
          PopupMenuItem<String>(
            value: 'theme',
            child: Row(
              children: [
                Icon(_isPdfDarkMode ? Icons.light_mode : Icons.dark_mode,
                    size: 20,
                    color: _isPdfDarkMode
                        ? AppColors.primaryBlue
                        : menuTextColor),
                const SizedBox(width: 12),
                Text(_isPdfDarkMode ? 'Light reader' : 'Dark reader',
                    style: TextStyle(
                      color: _isPdfDarkMode
                          ? AppColors.primaryBlue
                          : menuTextColor,
                      fontWeight: FontWeight.w500,
                    )),
              ],
            ),
          ),
          // ── Table of contents — DISABLED (kept for easy re-enable) ──
          // The drawer + _loadOutline + _buildOutlineDrawer code paths are
          // still wired up; only the menu entry that opened the drawer is
          // commented out. Uncomment this block (and ensure `hasDocument`
          // stays in scope above) to bring the TOC affordance back.
          // if (hasDocument)
          //   PopupMenuItem<String>(
          //     value: 'toc',
          //     child: Row(
          //       children: [
          //         Icon(Icons.menu_book_outlined,
          //             size: 20, color: menuTextColor),
          //         const SizedBox(width: 12),
          //         Text('Table of contents',
          //             style: TextStyle(
          //               color: menuTextColor,
          //               fontWeight: FontWeight.w500,
          //             )),
          //       ],
          //     ),
          //   ),
          if (!widget.embedded)
            _menuToggleItem(
              value: 'keep_screen_on',
              icon: _keepScreenOn ? Icons.lightbulb : Icons.lightbulb_outline,
              label: _keepScreenOn ? 'Screen always on' : 'Keep screen on',
              active: _keepScreenOn,
              textColor: menuTextColor,
            ),
          if (!widget.embedded)
            _menuToggleItem(
              value: 'lock_rotation',
              icon: _orientationLocked
                  ? Icons.screen_lock_rotation
                  : Icons.screen_rotation,
              label: _orientationLocked ? 'Unlock rotation' : 'Lock rotation',
              active: _orientationLocked,
              textColor: menuTextColor,
            ),
          if (hasBookmarks)
            PopupMenuItem<String>(
              value: 'bookmarks',
              child: Row(
                children: [
                  Icon(Icons.collections_bookmark_outlined,
                      size: 20, color: menuTextColor),
                  const SizedBox(width: 12),
                  Text('All bookmarks',
                      style: TextStyle(
                        color: menuTextColor,
                        fontWeight: FontWeight.w500,
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuToggleItem({
    required String value,
    required IconData icon,
    required String label,
    required bool active,
    required Color textColor,
  }) {
    final color = active ? AppColors.primaryBlue : textColor;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  /// Locks the reader to its current orientation (portrait or landscape), or
  /// unlocks it again. Same behaviour as the Syncfusion reader's toggle.
  void _toggleRotationLock() {
    setState(() => _orientationLocked = !_orientationLocked);
    if (_orientationLocked) {
      final landscape =
          MediaQuery.of(context).orientation == Orientation.landscape;
      SystemChrome.setPreferredOrientations(landscape
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
            ]);
    } else {
      SystemChrome.setPreferredOrientations(_allOrientations);
    }
  }

  static const _allOrientations = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  Widget _buildSearchBar(bool isDark, Color textColor, bool isTablet) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: TextStyle(fontSize: isTablet ? 16 : 14, color: textColor),
            decoration: InputDecoration(
              hintText: 'Search in document...',
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
              if (value.isNotEmpty && _textSearcher != null) {
                _textSearcher!.startTextSearch(value);
              }
            },
          ),
        ),
        if (_textSearcher != null) ...[
          SizedBox(width: isTablet ? 8 : 4),
          GestureDetector(
            onTap: () => _textSearcher?.goToPrevMatch(),
            child: Icon(Icons.keyboard_arrow_up,
                size: isTablet ? 28 : 24, color: textColor),
          ),
          GestureDetector(
            onTap: () => _textSearcher?.goToNextMatch(),
            child: Icon(Icons.keyboard_arrow_down,
                size: isTablet ? 28 : 24, color: textColor),
          ),
        ],
      ],
    );
  }

  // ── Bottom action bar ─────────────────────────────────────────────

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
        // Each action gets an equal share of the width and scales down only
        // if it does not fit (e.g. a narrow split pane), instead of the row
        // overflowing and cutting buttons off. Normal widths look unchanged.
        child: Row(
          children: [
            for (final action in <Widget>[
            _buildBottomAction(
              icon: Icons.border_color,
              label: 'Highlight',
              color: const Color(0xFFFFEB3B),
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
            // Undo — always visible. Active (red, with stack-depth badge)
            // when something can be undone; muted grey + no-op when the
            // stack is empty so the user always knows the feature exists.
            Builder(builder: (_) {
              final canUndo = _undoStack.isNotEmpty;
              return _buildBottomAction(
                icon: Icons.undo,
                label: canUndo ? 'Undo (${_undoStack.length})' : 'Undo',
                color: canUndo
                    ? AppColors.error
                    : (isDark
                        ? AppColors.darkTextSecondary
                        : Colors.grey),
                onTap: canUndo ? _undoLastAnnotation : () {},
                isDark: isDark,
                isTablet: isTablet,
              );
            }),
            ])
              Expanded(
                child: Center(
                  child: FittedBox(fit: BoxFit.scaleDown, child: action),
                ),
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
            Text(label,
                style: TextStyle(
                  fontSize: isTablet ? 11 : 9,
                  fontWeight: FontWeight.w500,
                  color:
                      isDark ? AppColors.darkTextSecondary : Colors.grey[700],
                )),
          ],
        ),
      ),
    );
  }

  // ── Error / Loading views ─────────────────────────────────────────

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
            Text('${(_downloadProgress * 100).toInt()}%',
                style: TextStyle(
                    fontSize: isTablet ? 17 : 14, color: Colors.grey)),
          ],
        ],
      ),
    );
  }
}

/// Stateful go-to-page dialog. Owns its own FocusNode + TextEditingController
/// so iOS keyboard MQ rebuilds don't disposal-poison the autofocus path.
/// (Inline `autofocus: true` on a TextField inside an AlertDialog builder
/// crashes iOS with "FocusNode used after being disposed" because the
/// keyboard appearing triggers an AlertDialog rebuild that races the
/// autofocus' own requestFocus call against the prior FocusNode's dispose.)
class _GoToPageDialog extends StatefulWidget {
  final int initialPage;
  final int totalPages;
  final bool isDark;
  final bool isTablet;
  final void Function(int page) onSubmit;

  const _GoToPageDialog({
    required this.initialPage,
    required this.totalPages,
    required this.isDark,
    required this.isTablet,
    required this.onSubmit,
  });

  @override
  State<_GoToPageDialog> createState() => _GoToPageDialogState();
}

class _GoToPageDialogState extends State<_GoToPageDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPage.toString());
    _focusNode = FocusNode();
    // Focus AFTER first frame so the dialog is mounted and the FocusNode
    // is attached before requestFocus runs. Avoids the "used after being
    // disposed" race we got with TextField's built-in autofocus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final n = int.tryParse(_controller.text.trim());
    if (n == null || n < 1 || n > widget.totalPages) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(
              'Enter a page number between 1 and ${widget.totalPages}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }
    Navigator.pop(context);
    widget.onSubmit(n);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor =
        widget.isDark ? AppColors.darkTextPrimary : Colors.black;
    return AlertDialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text('Go to page',
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            fontWeight: FontWeight.w700,
            fontSize: widget.isTablet ? 19 : 17,
            color: textColor,
          )),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.number,
        onSubmitted: (_) => _submit(),
        style: TextStyle(
            color: textColor, fontSize: widget.isTablet ? 16 : 15),
        decoration: InputDecoration(
          hintText: 'Page number (1–${widget.totalPages})',
          hintStyle: TextStyle(
            color: widget.isDark ? Colors.white38 : Colors.grey[400],
            fontSize: widget.isTablet ? 15 : 14,
          ),
          filled: true,
          fillColor: widget.isDark
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
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: TextStyle(
                color: widget.isDark
                    ? AppColors.darkTextSecondary
                    : Colors.grey[600],
                fontWeight: FontWeight.w500,
              )),
        ),
        ElevatedButton(
          onPressed: _submit,
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
  }
}

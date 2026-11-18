import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart'
    show ScreenshotConfiguration, CompressFormat;
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/services/bookmark_service.dart';
import 'package:pgme/core/services/download_service.dart';
import 'package:pgme/core/services/ebook_access_service.dart';
import 'package:pgme/core/services/highlight_service.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/widgets/app_dialog.dart';
import 'package:pgme/features/notes/widgets/page_curl.dart';

class EpubViewerScreen extends StatefulWidget {
  final String? documentId;
  final String? epubUrl;
  final String title;

  const EpubViewerScreen({
    super.key,
    this.documentId,
    this.epubUrl,
    this.title = 'Reader',
  });

  @override
  State<EpubViewerScreen> createState() => _EpubViewerScreenState();
}

class _EpubViewerScreenState extends State<EpubViewerScreen>
    with SingleTickerProviderStateMixin {
  final EpubController _epubController = EpubController();
  final HighlightService _highlightService = HighlightService();
  final BookmarkService _bookmarkService = BookmarkService();

  String? _localPath;
  bool _isLoading = true;
  bool _isEpubReady = false;
  double _downloadProgress = 0;
  double _readProgress = 0;
  String? _error;
  bool _isSearchOpen = false;
  bool _isDarkMode = false;
  bool _isScrollMode = false;

  // Tapping the page hides/shows the header, progress row and bottom action
  // bar so the text gets the whole screen (matters most in landscape).
  bool _chromeVisible = true;
  // Touch tracking from the book's own onTouchDown/onTouchUp callbacks
  // (normalized 0..1 coordinates). Used for tap-to-toggle chrome and, on iOS,
  // swipe-to-turn-page.
  Offset? _touchDown;
  DateTime? _touchDownAt;
  bool _touchDownHadSelection = false;
  bool _hasSelection = false;

  // Book view size + pending re-align after a resize (see _onBookViewSize).
  Size? _bookViewSize;
  Timer? _reanchorTimer;
  // Reading-mode switches reload the book (see _toggleReadingMode).
  int _viewerGeneration = 0;
  String? _resumeCfi;

  // iOS flip mode: page turns play a paper-curl animation (see _turnPage).
  late final AnimationController _curlAnim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));
  late final Animation<double> _curlProgress =
      CurvedAnimation(parent: _curlAnim, curve: Curves.easeInOut);
  ui.FragmentProgram? _curlProgram;
  ui.Image? _curlImage; // still of the page that curls
  ui.Image? _curlBackdrop; // still under the curl (previous-page turns)
  bool _turning = false;
  bool? _queuedTurnForward;
  Completer<String?>? _turnRelocated;

  // Current selection
  String? _selectedCfi;
  String? _selectedText;

  // Current location
  String _currentChapter = '';
  String? _currentCfi;

  // Bookmarks — bookmarkId -> cfi (stored in bookmark's `note` field)
  final Map<String, String> _bookmarkCfis = {};
  bool _isCurrentLocationBookmarked = false;
  String? _currentBookmarkId;

  // Highlights — id -> {cfi, text, color}
  final Map<String, Map<String, String>> _highlights = {};
  // Underlines — id -> {cfi, text}
  final Map<String, Map<String, String>> _underlines = {};
  // Standalone notes
  final Map<String, Map<String, dynamic>> _standaloneNotes = {};

  // Undo
  String? _lastActionId;

  bool _dataLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _isDarkMode =
            Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
      }
    });
    if (Platform.isIOS) {
      PageCurl.load().then((program) => _curlProgram = program);
    }
    _loadEpub();
  }

  @override
  void dispose() {
    _reanchorTimer?.cancel();
    _curlAnim.dispose();
    _takeCurlImages().forEach((image) => image.dispose());
    super.dispose();
  }

  // ── EPUB loading ──────────────────────────────────────────────────

  Future<void> _loadEpub() async {
    try {
      if (widget.documentId != null) {
        final ebookFileName = 'ebook_${widget.documentId}.epub';
        final downloadedPath =
            await DownloadService().getDownloadedPath(ebookFileName);
        if (downloadedPath != null) {
          final file = File(downloadedPath);
          if (await file.exists() && await file.length() > 0) {
            if (mounted) setState(() { _localPath = downloadedPath; _isLoading = false; });
            return;
          }
        }
      }

      String epubUrl;
      if (widget.epubUrl != null) {
        epubUrl = widget.epubUrl!;
      } else if (widget.documentId != null) {
        final data = await EbookAccessService().getEbookViewUrl(widget.documentId!);
        epubUrl = data['url'] as String;
      } else {
        throw Exception('No EPUB source provided');
      }
      if (!mounted) return;

      final dir = await getTemporaryDirectory();
      final fileName = 'pgme_epub_${widget.documentId ?? epubUrl.hashCode}.epub';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      if (await file.exists() && await file.length() > 0) {
        if (mounted) setState(() { _localPath = filePath; _isLoading = false; });
        return;
      }

      await Dio().download(epubUrl, filePath, onReceiveProgress: (received, total) {
        if (total > 0 && mounted) setState(() => _downloadProgress = received / total);
      });
      if (mounted) setState(() { _localPath = filePath; _isLoading = false; });
    } catch (e) {
      debugPrint('EPUB load error: $e');
      if (mounted) setState(() { _error = 'Failed to load EPUB'; _isLoading = false; });
    }
  }

  // ── Load data from backend ────────────────────────────────────────

  Future<void> _loadData() async {
    if (_dataLoaded || widget.documentId == null) return;
    _dataLoaded = true;

    try {
      final highlights = await _highlightService.getHighlights(widget.documentId!);
      for (final h in highlights) {
        final id = h['highlight_id'] as String;
        final type = (h['annotation_type'] as String?) ?? 'highlight';
        final boundsData = h['bounds_data'] as List?;
        final cfi = (boundsData != null && boundsData.isNotEmpty)
            ? (boundsData.first['text'] as String? ?? '')
            : '';
        final text = (h['highlighted_text'] as String?) ?? '';
        final color = (h['color'] as String?) ?? 'yellow';

        if (type == 'note') {
          _standaloneNotes[id] = {
            'note': h['note'] as String? ?? '',
          };
        } else if (type == 'underline' && cfi.isNotEmpty) {
          _underlines[id] = {'cfi': cfi, 'text': text};
          _epubController.addUnderline(cfi: cfi);
        } else if (cfi.isNotEmpty) {
          _highlights[id] = {'cfi': cfi, 'text': text, 'color': color};
          _epubController.addHighlight(cfi: cfi, color: _colorFromName(color));
        }
      }
    } catch (_) {}

    try {
      final bookmarks = await _bookmarkService.getBookmarks(widget.documentId!);
      for (final b in bookmarks) {
        final id = b['bookmark_id'] as String;
        final cfi = b['note'] as String? ?? '';
        _bookmarkCfis[id] = cfi;
      }
      _updateBookmarkState();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Color _colorFromName(String name) {
    switch (name) {
      case 'green': return Colors.green;
      case 'blue': return Colors.blue;
      case 'pink': return Colors.pink;
      default: return Colors.yellow;
    }
  }

  // ── Bookmarks ─────────────────────────────────────────────────────

  void _updateBookmarkState() {
    if (_currentCfi == null) {
      _isCurrentLocationBookmarked = false;
      _currentBookmarkId = null;
      return;
    }
    for (final entry in _bookmarkCfis.entries) {
      if (entry.value == _currentCfi) {
        _isCurrentLocationBookmarked = true;
        _currentBookmarkId = entry.key;
        return;
      }
    }
    _isCurrentLocationBookmarked = false;
    _currentBookmarkId = null;
  }

  Future<void> _toggleBookmark() async {
    if (widget.documentId == null || _currentCfi == null) return;

    if (_isCurrentLocationBookmarked && _currentBookmarkId != null) {
      // Remove bookmark
      final id = _currentBookmarkId!;
      setState(() {
        _bookmarkCfis.remove(id);
        _isCurrentLocationBookmarked = false;
        _currentBookmarkId = null;
      });
      try {
        await _bookmarkService.deleteBookmark(id);
      } catch (_) {
        // Restore on failure
        if (mounted) {
          setState(() { _bookmarkCfis[id] = _currentCfi!; _updateBookmarkState(); });
        }
      }
    } else {
      // Add bookmark — store CFI in the note field, page_number as progress-based
      final progressPage = (_readProgress * 100).round().clamp(1, 9999);
      try {
        final result = await _bookmarkService.addBookmark(
          documentId: widget.documentId!,
          pageNumber: progressPage,
          note: _currentCfi,
        );
        if (mounted) {
          setState(() {
            _bookmarkCfis[result['bookmark_id'] as String] = _currentCfi!;
            _updateBookmarkState();
          });
        }
      } catch (e) {
        if (mounted) {
          showAppDialog(context,
              message: e.toString().replaceFirst('Exception: ', '').trim().isEmpty
                  ? 'Failed to add bookmark'
                  : e.toString().replaceFirst('Exception: ', '').trim(),
              type: AppDialogType.info);
        }
      }
    }
  }

  // ── Highlight / Underline ─────────────────────────────────────────

  void _highlightSelected(String color) {
    if (_selectedCfi == null || _selectedCfi!.isEmpty) {
      showAppDialog(context,
          message: 'Select text first by long-pressing on it',
          type: AppDialogType.info);
      return;
    }

    final cfi = _selectedCfi!;
    final text = _selectedText ?? '';

    _epubController.addHighlight(cfi: cfi, color: _colorFromName(color));
    _epubController.clearSelection();

    if (widget.documentId != null) {
      _highlightService.addHighlight(
        documentId: widget.documentId!,
        pageNumber: 1,
        startOffset: 0,
        endOffset: 0,
        highlightedText: text.length > 2000 ? text.substring(0, 2000) : text,
        color: color,
        annotationType: 'highlight',
        boundsData: [{'left': 0, 'top': 0, 'width': 0, 'height': 0, 'text': cfi, 'page_number': 1}],
      ).then((result) {
        final id = result['highlight_id'] as String;
        setState(() {
          _highlights[id] = {'cfi': cfi, 'text': text, 'color': color};
          _lastActionId = id;
        });
      }).catchError((_) {});
    }

    _selectedCfi = null;
    _selectedText = null;
  }

  void _underlineSelected() {
    if (_selectedCfi == null || _selectedCfi!.isEmpty) {
      showAppDialog(context,
          message: 'Select text first by long-pressing on it',
          type: AppDialogType.info);
      return;
    }

    final cfi = _selectedCfi!;
    final text = _selectedText ?? '';

    _epubController.addUnderline(cfi: cfi);
    _epubController.clearSelection();

    if (widget.documentId != null) {
      _highlightService.addHighlight(
        documentId: widget.documentId!,
        pageNumber: 1,
        startOffset: 0,
        endOffset: 0,
        highlightedText: text.length > 2000 ? text.substring(0, 2000) : text,
        color: 'blue',
        annotationType: 'underline',
        boundsData: [{'left': 0, 'top': 0, 'width': 0, 'height': 0, 'text': cfi, 'page_number': 1}],
      ).then((result) {
        final id = result['highlight_id'] as String;
        setState(() {
          _underlines[id] = {'cfi': cfi, 'text': text};
          _lastActionId = id;
        });
      }).catchError((_) {});
    }

    _selectedCfi = null;
    _selectedText = null;
  }

  void _removeAnnotation(String id) {
    if (_highlights.containsKey(id)) {
      _epubController.removeHighlight(cfi: _highlights[id]!['cfi']!);
      _highlights.remove(id);
    } else if (_underlines.containsKey(id)) {
      _epubController.removeUnderline(cfi: _underlines[id]!['cfi']!);
      _underlines.remove(id);
    }
    _standaloneNotes.remove(id);
    _highlightService.deleteHighlight(id).catchError((_) {});
    setState(() {});
  }

  void _undoLast(StateSetter setSheetState) {
    if (_lastActionId == null) return;
    _removeAnnotation(_lastActionId!);
    _lastActionId = null;
    setSheetState(() {});
  }

  // ── Notes panel ───────────────────────────────────────────────────

  void _showNotesPanel() {
    final isDark = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;
    final subtitleColor = isDark ? AppColors.darkTextSecondary : Colors.grey[600]!;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return StatefulBuilder(builder: (sheetContext, setSheetState) {
          final allIds = [..._highlights.keys, ..._underlines.keys, ..._standaloneNotes.keys];
          return DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.85,
            expand: false,
            builder: (context, scrollController) {
              return Column(children: [
                // Drag handle
                Center(child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2)))),
                // Header
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
                  child: Row(children: [
                    Icon(Icons.sticky_note_2_outlined, size: 22, color: AppColors.primaryBlue),
                    const SizedBox(width: 8),
                    Text('Notes & Highlights', style: TextStyle(
                      fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700,
                      fontSize: 18, color: textColor)),
                    const Spacer(),
                    if (_lastActionId != null)
                      _headerButton('Undo', Icons.undo, AppColors.error,
                          () => _undoLast(setSheetState)),
                    const SizedBox(width: 6),
                    _headerButton('Add Note', Icons.add, AppColors.primaryBlue,
                        () => _showAddNoteDialog(setSheetState)),
                  ])),
                const SizedBox(height: 10),
                Divider(height: 1, color: isDark ? AppColors.darkDivider : const Color(0xFFF0F0F0)),
                // List
                Expanded(
                  child: allIds.isEmpty
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.note_alt_outlined, size: 40, color: subtitleColor),
                          const SizedBox(height: 8),
                          Text('No highlights or notes yet', style: TextStyle(fontSize: 14, color: subtitleColor)),
                        ]))
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: allIds.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1, indent: 60, endIndent: 20,
                            color: isDark ? AppColors.darkDivider : const Color(0xFFF0F0F0)),
                          itemBuilder: (_, index) {
                            final id = allIds[index];

                            // Standalone note
                            if (_standaloneNotes.containsKey(id)) {
                              return _buildNoteItem(id, _standaloneNotes[id]!['note'] as String,
                                  textColor, setSheetState, sheetContext);
                            }

                            // Highlight
                            if (_highlights.containsKey(id)) {
                              final h = _highlights[id]!;
                              return _buildAnnotationItem(
                                id: id, text: h['text'] ?? '', isHighlight: true,
                                color: _colorFromName(h['color'] ?? 'yellow'),
                                cfi: h['cfi'] ?? '', textColor: textColor,
                                setSheetState: setSheetState, sheetContext: sheetContext);
                            }

                            // Underline
                            final u = _underlines[id]!;
                            return _buildAnnotationItem(
                              id: id, text: u['text'] ?? '', isHighlight: false,
                              color: Colors.blue, cfi: u['cfi'] ?? '',
                              textColor: textColor,
                              setSheetState: setSheetState, sheetContext: sheetContext);
                          },
                        ),
                ),
              ]);
            },
          );
        });
      },
    );
  }

  Widget _headerButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
        ]),
      ),
    );
  }

  Widget _buildNoteItem(String id, String noteText, Color textColor,
      StateSetter setSheetState, BuildContext sheetContext) {
    return InkWell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.15),
            child: Icon(Icons.note_outlined, size: 16, color: AppColors.primaryBlue)),
          const SizedBox(width: 10),
          Expanded(child: Text(noteText, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: textColor, height: 1.3))),
          GestureDetector(
            onTap: () { _removeAnnotation(id); setSheetState(() {}); },
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(Icons.delete_outline, size: 20,
                  color: AppColors.error.withValues(alpha: 0.7)))),
        ]),
      ),
    );
  }

  Widget _buildAnnotationItem({
    required String id, required String text, required bool isHighlight,
    required Color color, required String cfi, required Color textColor,
    required StateSetter setSheetState, required BuildContext sheetContext,
  }) {
    return InkWell(
      onTap: () {
        if (cfi.isNotEmpty) {
          _epubController.display(cfi: cfi);
          Navigator.pop(sheetContext);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(
              isHighlight ? Icons.border_color : Icons.format_underlined,
              size: 16, color: color)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (text.isNotEmpty)
                Text(text, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: textColor, fontStyle: FontStyle.italic, height: 1.3)),
              if (text.isEmpty)
                Text(isHighlight ? 'Highlight' : 'Underline',
                    style: TextStyle(fontSize: 13, color: textColor)),
            ],
          )),
          // Navigate to location
          GestureDetector(
            onTap: () {
              if (cfi.isNotEmpty) {
                _epubController.display(cfi: cfi);
                Navigator.pop(sheetContext);
              }
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(Icons.my_location, size: 20,
                  color: AppColors.primaryBlue.withValues(alpha: 0.7)))),
          // Delete
          GestureDetector(
            onTap: () { _removeAnnotation(id); setSheetState(() {}); },
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(Icons.delete_outline, size: 20,
                  color: AppColors.error.withValues(alpha: 0.7)))),
        ]),
      ),
    );
  }

  void _showAddNoteDialog(StateSetter setSheetState) {
    final isDark = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;
    final noteCtrl = TextEditingController();

    showModalBottomSheet(
      context: context, backgroundColor: bgColor, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 36, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2)))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Add Note', style: TextStyle(
                fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700,
                fontSize: 18, color: textColor))),
            const SizedBox(height: 12),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(controller: noteCtrl, maxLines: 4, maxLength: 500,
                autofocus: true,
                style: TextStyle(color: textColor, fontSize: 14, height: 1.5),
                decoration: InputDecoration(
                  hintText: 'Write your note...',
                  hintStyle: TextStyle(color: isDark ? AppColors.darkTextTertiary : Colors.grey[400]),
                  filled: true,
                  fillColor: isDark ? AppColors.darkSurface : const Color(0xFFF8F9FE),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5))))),
            const SizedBox(height: 14),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(
                    color: isDark ? AppColors.darkTextSecondary : Colors.grey[600]))),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(gradient: AppColors.blueGradient,
                    borderRadius: BorderRadius.circular(24)),
                  child: Material(color: Colors.transparent,
                    child: InkWell(borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        final note = noteCtrl.text.trim();
                        if (note.isEmpty) return;
                        Navigator.pop(ctx);
                        _saveStandaloneNote(note, setSheetState);
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                        child: Text('Save', style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)))))),
              ])),
            const SizedBox(height: 12),
          ],
        )),
      ),
    );
  }

  Future<void> _saveStandaloneNote(String note, StateSetter setSheetState) async {
    if (widget.documentId == null) return;
    try {
      final result = await _highlightService.addHighlight(
        documentId: widget.documentId!,
        pageNumber: 1, startOffset: 0, endOffset: 0,
        highlightedText: '', color: 'yellow', annotationType: 'note', note: note,
      );
      final id = result['highlight_id'] as String;
      setState(() {
        _standaloneNotes[id] = {'note': note};
        _lastActionId = id;
      });
      setSheetState(() {});
    } catch (_) {
      if (mounted) showAppDialog(context, message: 'Failed to save note', type: AppDialogType.info);
    }
  }

  // ── Annotation tap handler ────────────────────────────────────────

  void _onAnnotationClicked(String cfi) {
    // Find which annotation was clicked
    String? id;
    bool isHighlight = true;
    for (final entry in _highlights.entries) {
      if (entry.value['cfi'] == cfi) { id = entry.key; break; }
    }
    if (id == null) {
      for (final entry in _underlines.entries) {
        if (entry.value['cfi'] == cfi) { id = entry.key; isHighlight = false; break; }
      }
    }
    if (id == null) return;

    final isDark = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;

    showModalBottomSheet(
      context: context, backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 32, height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2))),
          InkWell(
            onTap: () {
              Navigator.pop(ctx);
              _removeAnnotation(id!);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                const SizedBox(width: 12),
                Text(isHighlight ? 'Remove Highlight' : 'Remove Underline',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.error)),
              ]))),
          const SizedBox(height: 8),
        ],
      )),
    );
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
      backgroundColor: backgroundColor,
      appBar: AppBar(
        toolbarHeight: 0, backgroundColor: toolbarColor,
        elevation: 0, scrolledUnderElevation: 0,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent)),
      body: Column(children: [
        // No size animation here: every intermediate size would make the
        // book engine re-layout mid-animation (see _onBookViewSize).
        _chromeVisible
              ? Column(children: [
                  _buildToolbar(isDark, textColor, toolbarColor, isTablet),
                  // Chapter + progress indicator. Space is reserved even
                  // before the book is ready so the book view keeps one size
                  // from the start (a resize right after the first page is
                  // drawn could leave the book on a blank page).
                  Visibility(
                    visible: _isEpubReady,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      color: toolbarColor,
                      child: Row(children: [
                        Expanded(child: Text(
                          _currentChapter.isNotEmpty ? _currentChapter : widget.title,
                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkTextTertiary : Colors.grey[500]),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                        // Tap the percentage to jump to a location.
                        GestureDetector(
                          onTap: _showGoToLocationDialog,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10)),
                            child: Text('${(_readProgress * 100).toInt()}%',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                color: AppColors.primaryBlue))),
                        ),
                      ]),
                    ),
                  ),
                  Visibility(
                    visible: _isEpubReady,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: LinearProgressIndicator(
                      value: _readProgress, backgroundColor: Colors.transparent,
                      color: AppColors.primaryBlue, minHeight: 2),
                  ),
                ])
              // Hidden: keep only the status-bar inset so text never sits
              // under the clock.
              : SizedBox(
                  width: double.infinity,
                  height: MediaQuery.of(context).padding.top),
        Expanded(
          child: _error != null
              ? _buildError(textColor, isTablet)
              : _isLoading ? _buildLoading(isTablet) : _buildEpubViewer(isDark)),
        _chromeVisible
            // Reserved (invisible, not tappable) until the book is ready.
            ? Visibility(
                visible: _isEpubReady,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: _buildBottomActionBar(isDark, isTablet),
              )
            : SizedBox(
                width: double.infinity,
                height: MediaQuery.of(context).padding.bottom),
      ]),
    );
  }

  // ── Page navigation + go-to-location ──────────────────────────────

  void _onBookTouchDown(double x, double y) {
    _touchDown = Offset(x, y);
    _touchDownAt = DateTime.now();
    _touchDownHadSelection = _hasSelection;
  }

  void _onBookTouchUp(double x, double y) {
    final down = _touchDown;
    final at = _touchDownAt;
    _touchDown = null;
    _touchDownAt = null;
    // While text is selected, taps and drags belong to the selection UI.
    if (down == null || at == null || !_isEpubReady) return;
    if (_touchDownHadSelection || _hasSelection) return;

    final dx = x - down.dx;
    final dy = y - down.dy;
    final heldMs = DateTime.now().difference(at).inMilliseconds;

    // A quick, stationary touch is a tap: show/hide the reader chrome. (A long
    // press starts a text selection and must not toggle anything.)
    if (dx.abs() < 0.03 && dy.abs() < 0.03 && heldMs < 350) {
      setState(() => _chromeVisible = !_chromeVisible);
      return;
    }

    // iOS only: swipe left/right turns the page in paginated mode. Android's
    // built-in swipe handler (enabled by the package on Android) already does
    // this, so doing it here too would turn two pages at once there.
    if (Platform.isIOS &&
        !_isScrollMode &&
        dx.abs() >= 0.2 &&
        dx.abs() > dy.abs() * 1.5) {
      _turnPage(forward: dx < 0);
    }
  }

  /// iOS flip mode: turn the page with a paper curl, like Apple Books. The
  /// book is drawn by a web view that Flutter cannot bend, so a still of the
  /// page is laid over it: for "next" the real page turns underneath and the
  /// still curls away to reveal it; for "previous" the previous page's still
  /// curls back in over a still of the current page. Without the shader, or
  /// if a still cannot be taken, the page just turns as before.
  Future<void> _turnPage({required bool forward}) async {
    if (!_isEpubReady || _isScrollMode) return;
    if (_turning) {
      _queuedTurnForward = forward; // play it once this turn finishes
      return;
    }
    void turnBook() => forward ? _epubController.next() : _epubController.prev();
    // While text is selected the book refuses to turn; nothing to animate.
    if (_curlProgram == null || _hasSelection) {
      turnBook();
      return;
    }
    _turning = true;
    final startCfi = _currentCfi;
    try {
      final current = await _snapshotBook();
      if (!mounted) {
        current?.dispose();
        return;
      }
      if (current == null) {
        turnBook();
        return;
      }
      // Cover the book with a plain still of the current page. It needs no
      // shader, so it reaches the screen straight away.
      setState(() => _curlBackdrop = current);
      // The still must be on screen before the page changes under it: let
      // this frame and one more go through.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final relocated = _turnRelocated = Completer<String?>();
      turnBook();
      final newCfi = await relocated.future
          .timeout(const Duration(seconds: 1), onTimeout: () => null);
      // First/last page: the book did not move, so there is nothing to turn.
      if (!mounted || newCfi == null || newCfi == startCfi) return;
      if (forward) {
        // Give the web view a moment to paint the new page underneath.
        await Future<void>.delayed(const Duration(milliseconds: 40));
        if (!mounted) return;
        // The still now curls away, revealing the new page.
        setState(() {
          _curlAnim.value = 0;
          _curlImage = current;
          _curlBackdrop = null;
        });
        await _curlAnim.forward(from: 0).orCancel;
      } else {
        final previous = await _snapshotBook();
        if (!mounted || previous == null) {
          previous?.dispose();
          return;
        }
        setState(() {
          _curlAnim.value = 1;
          _curlImage = previous;
        });
        await _curlAnim.reverse(from: 1).orCancel;
      }
    } on TickerCanceled {
      // Screen closed mid-turn.
    } finally {
      _turnRelocated = null;
      _turning = false;
      final stills = _takeCurlImages();
      if (mounted) {
        setState(() {});
        // Free the stills once the frame without them is drawn.
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => stills.forEach((image) => image.dispose()));
        final queued = _queuedTurnForward;
        _queuedTurnForward = null;
        if (queued != null) _turnPage(forward: queued);
      } else {
        for (final image in stills) {
          image.dispose();
        }
      }
    }
  }

  /// Removes the page-turn stills from the screen state and hands them back
  /// for disposal.
  List<ui.Image> _takeCurlImages() {
    final stills = <ui.Image>{
      if (_curlImage != null) _curlImage!,
      if (_curlBackdrop != null) _curlBackdrop!,
    }.toList();
    _curlImage = null;
    _curlBackdrop = null;
    return stills;
  }

  /// A still picture of the book as it is on screen now (null on failure).
  Future<ui.Image?> _snapshotBook() async {
    try {
      // PNG keeps the web view's transparent margins transparent (JPEG
      // would turn them black).
      final bytes = await _epubController.webViewController?.takeScreenshot(
          screenshotConfiguration:
              ScreenshotConfiguration(compressFormat: CompressFormat.PNG));
      if (bytes == null) return null;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (e) {
      debugPrint('[EPUB] page still failed: $e');
      return null;
    }
  }

  Future<void> _showGoToLocationDialog() async {
    if (!_isEpubReady) return;
    final isDark = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _GoToLocationDialog(
        initialPercent: (_readProgress * 100).round().clamp(0, 100),
        isDark: isDark,
      ),
    );
    if (value == null || !mounted) return;
    // Let the dialog and the keyboard finish closing first. Hiding the keyboard
    // resizes the web view, and epub.js responds to a resize by re-displaying
    // its previous location, which would undo a jump made at the same moment.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    _epubController.toProgressPercentage((value / 100).clamp(0.0, 1.0));
  }

  Widget _buildToolbar(bool isDark, Color textColor, Color toolbarColor, bool isTablet) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 12, vertical: isTablet ? 12 : 8),
        decoration: BoxDecoration(color: toolbarColor,
          border: Border(bottom: BorderSide(
            color: isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0), width: 0.5))),
        child: Column(children: [
          Row(children: [
            GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                width: isTablet ? 44 : 36, height: isTablet ? 44 : 36,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5)),
                child: Icon(Icons.arrow_back, size: isTablet ? 22 : 18, color: textColor))),
            SizedBox(width: isTablet ? 12 : 8),
            Expanded(child: Text(widget.title,
              style: TextStyle(fontFamily: 'SF Pro Display', fontWeight: FontWeight.w600,
                fontSize: isTablet ? 18 : 15, color: textColor),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            // Bookmark
            if (widget.documentId != null)
              GestureDetector(
                onTap: _toggleBookmark,
                child: Container(
                  width: isTablet ? 44 : 36, height: isTablet ? 44 : 36,
                  margin: EdgeInsets.only(right: isTablet ? 4 : 2),
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: _isCurrentLocationBookmarked
                        ? AppColors.primaryBlue.withValues(alpha: 0.1)
                        : (isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5))),
                  child: Icon(
                    _isCurrentLocationBookmarked ? Icons.bookmark : Icons.bookmark_border,
                    size: isTablet ? 22 : 18,
                    color: _isCurrentLocationBookmarked ? AppColors.primaryBlue : textColor))),
            // Scroll/page toggle
            GestureDetector(
              onTap: _toggleReadingMode,
              child: Container(
                width: isTablet ? 44 : 36, height: isTablet ? 44 : 36,
                margin: EdgeInsets.only(right: isTablet ? 4 : 2),
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: _isScrollMode
                      ? AppColors.primaryBlue.withValues(alpha: 0.1)
                      : (isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5))),
                child: Icon(
                  _isScrollMode ? Icons.view_day : Icons.auto_stories,
                  size: isTablet ? 22 : 18,
                  color: _isScrollMode ? AppColors.primaryBlue : textColor))),
            // Dark mode
            GestureDetector(
              onTap: () {
                setState(() => _isDarkMode = !_isDarkMode);
                _epubController.updateTheme(
                  theme: _isDarkMode ? EpubTheme.dark() : EpubTheme.light());
              },
              child: Container(
                width: isTablet ? 44 : 36, height: isTablet ? 44 : 36,
                margin: EdgeInsets.only(right: isTablet ? 4 : 2),
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: _isDarkMode
                      ? AppColors.primaryBlue.withValues(alpha: 0.1)
                      : (isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5))),
                child: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  size: isTablet ? 22 : 18,
                  color: _isDarkMode ? AppColors.primaryBlue : textColor))),
            // Search
            GestureDetector(
              onTap: () => setState(() => _isSearchOpen = !_isSearchOpen),
              child: Container(
                width: isTablet ? 44 : 36, height: isTablet ? 44 : 36,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: _isSearchOpen
                      ? AppColors.primaryBlue.withValues(alpha: 0.1)
                      : (isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5))),
                child: Icon(_isSearchOpen ? Icons.close : Icons.search,
                  size: isTablet ? 22 : 18,
                  color: _isSearchOpen ? AppColors.primaryBlue : textColor))),
          ]),
          if (_isSearchOpen) ...[
            SizedBox(height: isTablet ? 10 : 8),
            TextField(
              autofocus: true,
              style: TextStyle(fontSize: isTablet ? 16 : 14, color: textColor),
              decoration: InputDecoration(
                hintText: 'Search in book...',
                hintStyle: TextStyle(color: isDark ? AppColors.darkTextSecondary : Colors.grey),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 12, vertical: isTablet ? 12 : 10),
                filled: true,
                fillColor: isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(isTablet ? 12 : 8), borderSide: BorderSide.none)),
              onSubmitted: (value) async {
                if (value.isNotEmpty) {
                  final results = await _epubController.search(query: value);
                  if (results.isNotEmpty) _epubController.display(cfi: results.first.cfi);
                }
              }),
          ],
        ]),
      ),
    );
  }

  Widget _buildBottomActionBar(bool isDark, bool isTablet) {
    final barColor = isDark ? AppColors.darkCardBackground : Colors.white;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: isTablet ? 8 : 6),
      decoration: BoxDecoration(color: barColor,
        border: Border(top: BorderSide(
          color: isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0), width: 0.5))),
      child: SafeArea(top: false,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _bottomAction(Icons.border_color, 'Highlight', const Color(0xFFFFEB3B),
              () => _highlightSelected('yellow'), isDark, isTablet),
          _bottomAction(Icons.format_underlined, 'Underline', const Color(0xFF1565C0),
              _underlineSelected, isDark, isTablet),
          _bottomAction(Icons.sticky_note_2_outlined, 'Notes', const Color(0xFF43A047),
              _showNotesPanel, isDark, isTablet),
        ])),
    );
  }

  Widget _bottomAction(IconData icon, String label, Color color,
      VoidCallback onTap, bool isDark, bool isTablet) {
    return GestureDetector(
      onTap: onTap, behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isTablet ? 12 : 8, vertical: isTablet ? 4 : 2),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: isTablet ? 40 : 32, height: isTablet ? 40 : 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.22 : 0.14), shape: BoxShape.circle),
            child: Icon(icon, size: isTablet ? 20 : 16, color: color)),
          SizedBox(height: isTablet ? 4 : 2),
          Text(label, style: TextStyle(fontSize: isTablet ? 11 : 9, fontWeight: FontWeight.w500,
            color: isDark ? AppColors.darkTextSecondary : Colors.grey[700])),
        ])));
  }

  /// Flip (paginated) <-> scroll. The book engine's in-place flow switch
  /// leaves it unable to turn pages afterwards (next/prev stay on the same
  /// page), so the book is reloaded cleanly in the new mode, opening at the
  /// current location, and the saved highlights/underlines are re-applied.
  void _toggleReadingMode() {
    if (!_isEpubReady || _turning) return;
    _reanchorTimer?.cancel();
    setState(() {
      _isScrollMode = !_isScrollMode;
      _resumeCfi = _currentCfi;
      _viewerGeneration++;
      _isEpubReady = false;
    });
  }

  /// Puts the already-loaded highlights/underlines onto a freshly loaded book.
  void _reapplyAnnotations() {
    for (final h in _highlights.values) {
      final cfi = h['cfi'];
      if (cfi != null && cfi.isNotEmpty) {
        _epubController.addHighlight(
            cfi: cfi, color: _colorFromName(h['color'] ?? 'yellow'));
      }
    }
    for (final u in _underlines.values) {
      final cfi = u['cfi'];
      if (cfi != null && cfi.isNotEmpty) _epubController.addUnderline(cfi: cfi);
    }
  }

  Widget _buildEpubViewer(bool isDark) {
    final epubSource = _localPath != null
        ? EpubSource.fromFile(File(_localPath!))
        : EpubSource.fromUrl(widget.epubUrl!);

    return LayoutBuilder(builder: (context, constraints) {
      _onBookViewSize(constraints.biggest);
      return Stack(children: [
      EpubViewer(
        key: ValueKey('epub-viewer-$_viewerGeneration'),
        epubSource: epubSource,
        epubController: _epubController,
        initialCfi: _resumeCfi,
        displaySettings: EpubDisplaySettings(
          flow: _isScrollMode ? EpubFlow.scrolled : EpubFlow.paginated,
          // iOS: epub.js's snap paging never sees touches made inside the
          // book's iframe, so a drag free-scrolled the pages (half-turned or
          // blank pages) and a swipe could also trigger our own turn. Off on
          // iOS: pages turn only via next()/prev() (swipe + arrow buttons),
          // and _applyBookLayoutFixes stops drags from moving the pages.
          // Android scroll mode: no snap. The package turns snap into
          // disableVerticalScroll on the web view, so the book could not be
          // scrolled at all in scroll mode on Android.
          snap: !Platform.isIOS && !_isScrollMode,
          useSnapAnimationAndroid: false,
          theme: _isDarkMode ? EpubTheme.dark() : EpubTheme.light(),
          allowScriptedContent: false),
        selectionContextMenu: ContextMenu(
          menuItems: [
            ContextMenuItem(title: 'Highlight', id: 1,
                action: () => _highlightSelected('yellow')),
            ContextMenuItem(title: 'Underline', id: 2,
                action: _underlineSelected),
          ],
          settings: ContextMenuSettings(hideDefaultSystemContextMenuItems: true)),
        onChaptersLoaded: (chapters) {
          if (!_isEpubReady && mounted) {
            setState(() => _isEpubReady = true);
            if (_dataLoaded) {
              _reapplyAnnotations(); // reloaded after a reading-mode switch
            } else {
              _loadData();
            }
            _applyBookLayoutFixes();
          }
        },
        onEpubLoaded: () => debugPrint('EPUB loaded'),
        onRelocated: (value) {
          final pendingTurn = _turnRelocated;
          if (pendingTurn != null && !pendingTurn.isCompleted) {
            pendingTurn.complete(value.startCfi);
          }
          if (mounted) {
            _currentCfi = value.startCfi;
            setState(() {
              _readProgress = value.progress;
              _updateBookmarkState();
            });
          }
        },
        onTextSelected: (sel) {
          _selectedCfi = sel.selectionCfi;
          _selectedText = sel.selectedText;
          _hasSelection = true;
        },
        onDeselection: () => _hasSelection = false,
        onTouchDown: _onBookTouchDown,
        onTouchUp: _onBookTouchUp,
        onAnnotationClicked: (cfi, data) => _onAnnotationClicked(cfi),
      ),
      // Page turn in progress: stills of the page over the book (see
      // _turnPage). Touches on the book wait until the turn is done.
      if (_curlImage != null || _curlBackdrop != null)
        Positioned.fill(
          child: AbsorbPointer(
            child: Stack(fit: StackFit.expand, children: [
              // The stills have transparent margins (the web view is
              // transparent there), so they sit on the screen's background.
              if (_curlBackdrop != null)
                ColoredBox(
                  color: isDark ? AppColors.darkBackground : Colors.white,
                  child: RawImage(image: _curlBackdrop, fit: BoxFit.fill)),
              if (_curlImage != null && _curlProgram != null)
                PageCurl(
                  program: _curlProgram!,
                  image: _curlImage!,
                  progress: _curlProgress,
                  paperColor:
                      _isDarkMode ? const Color(0xff121212) : Colors.white,
                  backgroundColor:
                      isDark ? AppColors.darkBackground : Colors.white),
            ]),
          ),
        ),
      // iOS paginated mode: visible previous/next buttons. Swipe-to-turn goes
      // through the web view's touch events, which are not reliable on iOS;
      // these turn the page through the book's own prev()/next() so turning
      // pages always works.
      if (Platform.isIOS && !_isScrollMode && _isEpubReady) ...[
        Positioned(
          left: 4, top: 0, bottom: 0,
          child: Center(child: _pageTurnButton(
            icon: Icons.chevron_left, isDark: isDark, tooltip: 'Previous page',
            onTap: () => _turnPage(forward: false))),
        ),
        Positioned(
          right: 4, top: 0, bottom: 0,
          child: Center(child: _pageTurnButton(
            icon: Icons.chevron_right, isDark: isDark, tooltip: 'Next page',
            onTap: () => _turnPage(forward: true))),
        ),
      ],
      if (!_isEpubReady)
        Container(
          color: isDark ? AppColors.darkBackground : Colors.white,
          child: const Center(child: CircularProgressIndicator(color: AppColors.primaryBlue))),
    ]);
    });
  }

  /// Called on every layout of the book view. When its size changes after
  /// the book is shown (header hidden/shown, rotation), the book engine
  /// re-lays out its pages and can end up between pages (a blank page). Once
  /// the size has settled, re-display the current location to re-align.
  void _onBookViewSize(Size size) {
    final previous = _bookViewSize;
    _bookViewSize = size;
    if (previous == null || previous == size || !_isEpubReady) return;
    _reanchorTimer?.cancel();
    _reanchorTimer = Timer(const Duration(milliseconds: 400), () {
      final cfi = _currentCfi;
      if (!mounted || cfi == null || cfi.isEmpty) return;
      _epubController.display(cfi: cfi);
    });
  }

  /// Layout fixes for the reader page, applied each time a book loads.
  ///
  /// All platforms: the reader page sets the book's height to the web view's
  /// height as a bare number, which the browser ignores — except when that
  /// height is 0, i.e. when the book loads before the web view has been laid
  /// out. The book then gets a height of 0 and is centred in the page's
  /// 800pt-tall body, so every page shows 400pt too low (far down the screen,
  /// or blank on smaller phones). Clearing that inline height restores the
  /// page's own 100% height.
  ///
  /// iOS: snap is off here, which also leaves the web view free to scroll up
  /// and down; the body's 800pt minimum height (taller than most phone
  /// screens) is dropped so the page fits the view and cannot be dragged.
  /// In flip (paginated) mode finger drags must not scroll the page strip,
  /// so it never rests between two pages; next()/prev() still turn pages.
  Future<void> _applyBookLayoutFixes() async {
    final isIOS = Platform.isIOS;
    try {
      final result = await _epubController.webViewController?.evaluateJavascript(source: '''
        (function () {
          var viewer = document.getElementById('viewer');
          var stuckHeight = viewer ? viewer.style.height : '';
          if (viewer) viewer.style.height = '';
          if ($isIOS) {
            if (!document.getElementById('pgme-reader-fixes')) {
              var st = document.createElement('style');
              st.id = 'pgme-reader-fixes';
              st.textContent = 'body{min-height:0 !important;}' +
                'html.pgme-paginated .epub-container' +
                '{overflow:hidden !important;-webkit-overflow-scrolling:auto !important;}';
              document.head.appendChild(st);
            }
            document.documentElement.classList.toggle('pgme-paginated', ${!_isScrollMode});
          }
          return stuckHeight;
        })();
      ''');
      if (result is String && result.isNotEmpty) {
        debugPrint('[EPUB] book height was stuck at "$result"; reset');
      }
    } catch (e) {
      debugPrint('[EPUB] layout fixes not applied: $e');
    }
  }

  Widget _pageTurnButton({
    required IconData icon,
    required bool isDark,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 36, height: 56,
            child: Icon(icon, size: 26,
              color: isDark ? Colors.white70 : Colors.black54)),
        ),
      ),
    );
  }

  Widget _buildLoading(bool isTablet) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress : null),
      if (_downloadProgress > 0) ...[
        SizedBox(height: isTablet ? 21 : 16),
        Text('${(_downloadProgress * 100).toInt()}%',
          style: TextStyle(fontSize: isTablet ? 17 : 14, color: Colors.grey)),
      ],
    ]));
  }

  Widget _buildError(Color textColor, bool isTablet) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.error_outline, size: isTablet ? 64 : 48, color: Colors.grey),
      SizedBox(height: isTablet ? 21 : 16),
      Text(_error!, style: TextStyle(fontSize: isTablet ? 20 : 16, color: textColor)),
      SizedBox(height: isTablet ? 21 : 16),
      ElevatedButton(
        onPressed: () {
          setState(() { _error = null; _isLoading = true; _downloadProgress = 0; _isEpubReady = false; _dataLoaded = false; });
          _loadEpub();
        },
        child: const Text('Retry')),
    ]));
  }
}

/// "Go to location" dialog: jumps to a percentage of the book. Owns its text
/// controller and focus node so they are disposed with the dialog, and takes
/// focus after the first frame (same pattern as the PDF viewer's go-to-page
/// dialog; TextField's built-in autofocus races with disposal).
class _GoToLocationDialog extends StatefulWidget {
  final int initialPercent;
  final bool isDark;

  const _GoToLocationDialog({
    required this.initialPercent,
    required this.isDark,
  });

  @override
  State<_GoToLocationDialog> createState() => _GoToLocationDialogState();
}

class _GoToLocationDialogState extends State<_GoToLocationDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPercent.toString());
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection =
          TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_controller.text.trim());
    if (v == null || v < 0 || v > 100) {
      setState(() => _error = 'Enter a number from 0 to 100');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor:
          widget.isDark ? AppColors.darkCardBackground : Colors.white,
      title: const Text('Go to location'),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Percentage of the book',
          suffixText: '%',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: const Text('Go')),
      ],
    );
  }
}

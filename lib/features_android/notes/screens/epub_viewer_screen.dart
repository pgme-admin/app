import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/services/bookmark_service.dart';
import 'package:pgme/core_android/services/download_service.dart';
import 'package:pgme/core_android/services/ebook_access_service.dart';
import 'package:pgme/core_android/services/api_service.dart';
import 'package:pgme/core_android/services/storage_service.dart';
import 'package:pgme/core_android/constants/api_constants.dart';
import 'package:pgme/core/utils/epub_file.dart';
import 'package:pgme/core/utils/epub_image_zoom.dart';
import 'package:pgme/core/utils/epub_search.dart';
import 'package:pgme/core/utils/epub_reader_theme.dart';
import 'package:pgme/core/widgets/epub_line_guide.dart';
import 'package:pgme/core/widgets/epub_appearance_sheet.dart';
import 'package:pgme/core/widgets/epub_navigation_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pgme/core_android/services/highlight_service.dart';
import 'package:pgme/core_android/theme/app_theme.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';
import 'package:pgme/core_android/widgets/app_dialog.dart';

class EpubViewerScreen extends StatefulWidget {
  final String? documentId;
  final String? epubUrl;
  final String? source;
  final String title;

  const EpubViewerScreen({
    super.key,
    this.documentId,
    this.epubUrl,
    this.source,
    this.title = 'Reader',
  });

  @override
  State<EpubViewerScreen> createState() => _EpubViewerScreenState();
}

class _EpubViewerScreenState extends State<EpubViewerScreen> {
  final EpubController _epubController = EpubController();
  final HighlightService _highlightService = HighlightService();
  final BookmarkService _bookmarkService = BookmarkService();

  String? _localPath;
  Timer? _readerTimeout;
  CancelToken? _downloadCancelToken;
  bool _isLoading = true;
  bool _isEpubReady = false;
  bool _chaptersReady = false;
  bool _pageDisplayed = false;
  double _downloadProgress = 0;
  double _readProgress = 0;
  String? _error;
  bool _isSearchOpen = false;
  bool _isSearchBusy = false;
  bool _isDarkMode = false;
  bool _isScrollMode = false;
  int _fontSize = 15;
  bool _twoPageLayout = true;
  EpubReadingTheme _readingTheme = EpubReadingTheme.followApp;
  EpubReadingFont _readingFont = EpubReadingFont.original;
  bool _portraitLock = false;
  bool _lineGuide = false;
  double _guideDimming = 0.4;

  // Current selection
  String? _selectedCfi;
  String? _selectedText;

  // Current location
  String _currentChapter = '';
  String? _currentCfi;
  String? _readerUserId;
  String? _resumeCfi;
  int _viewerGeneration = 0;

  // Bookmarks — bookmarkId -> cfi (stored in bookmark's `note` field)
  final Map<String, String> _bookmarkCfis = {};
  List<EpubChapter> _chapters = [];
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
        final darkMode =
            Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
        if (_readingTheme == EpubReadingTheme.followApp &&
            _isDarkMode != darkMode) {
          setState(() => _isDarkMode = darkMode);
          if (_isEpubReady) {
            unawaited(_epubController.updateTheme(
                theme: _currentReadingTheme()));
          }
        }
      }
    });
    _loadAppearance();
    _loadEpub();
  }

  @override
  void dispose() {
    _readerTimeout?.cancel();
    _downloadCancelToken?.cancel();
    if (_portraitLock) {
      unawaited(SystemChrome.setPreferredOrientations(
          _defaultReaderOrientations()));
    }
    super.dispose();
  }

  Future<void> _loadAppearance() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final theme = readingThemeFromName(prefs.getString('epub_reading_theme'));
    final font = readingFontFromName(prefs.getString('epub_reading_font'));
    final savedScroll = prefs.getBool('epub_scroll_mode') ?? false;
    final modeChanged = savedScroll != _isScrollMode;
    final appDark = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    setState(() {
      _fontSize = (prefs.getInt('epub_font_size') ?? 15).clamp(13, 24).toInt();
      _twoPageLayout = prefs.getBool('epub_two_page_layout') ?? true;
      _readingTheme = theme;
      _readingFont = font;
      _isDarkMode = readingThemeIsDark(theme, appDark);
      _portraitLock = prefs.getBool('epub_portrait_lock') ?? false;
      _lineGuide = prefs.getBool('epub_line_guide') ?? false;
      _guideDimming =
          (prefs.getDouble('epub_guide_dimming') ?? 0.4).clamp(0.0, 0.7).toDouble();
    });
    if (_portraitLock) {
      unawaited(SystemChrome.setPreferredOrientations(
          const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]));
    }
    if (_isEpubReady) {
      unawaited(_epubController.setFontSize(fontSize: _fontSize.toDouble()));
      unawaited(_applySpread(_twoPageLayout));
      unawaited(_epubController.updateTheme(theme: _currentReadingTheme()));
    }
    if (modeChanged) _setReadingMode(savedScroll);
  }

  Future<void> _applySpread(bool twoPages) async {
    // flutter_epub_viewer 1.2.8 passes the enum's toString() to epub.js;
    // epub.js expects the bare value ('auto' or 'none').
    await _epubController.webViewController?.evaluateJavascript(
        source: 'setSpread("${twoPages ? 'auto' : 'none'}")');
    final cfi = _currentCfi;
    if (mounted && cfi != null && cfi.isNotEmpty) {
      _epubController.display(cfi: cfi);
    }
  }

  Future<void> _showNavigation() async {
    final cfi = await showEpubNavigationSheet(context, _chapters, _bookmarkCfis);
    if (mounted && cfi != null) _epubController.display(cfi: cfi);
  }

  void _showAppearanceSettings() {
    showEpubAppearanceSheet(
      context,
      fontSize: _fontSize,
      isTablet: ResponsiveHelper.isTablet(context),
      twoPageLayout: _twoPageLayout,
      isScrollMode: _isScrollMode,
      portraitLock: _portraitLock,
      lineGuide: _lineGuide,
      guideDimming: _guideDimming,
      readingTheme: _readingTheme,
      readingFont: _readingFont,
      accentColor: AppColors.primaryBlue,
      onFontSizeChanged: (value) {
        setState(() => _fontSize = value);
        if (_isEpubReady) {
          unawaited(_epubController.setFontSize(fontSize: value.toDouble()));
        }
        SharedPreferences.getInstance().then(
            (prefs) => prefs.setInt('epub_font_size', value));
      },
      onTwoPageLayoutChanged: (value) {
        setState(() => _twoPageLayout = value);
        if (_isEpubReady) unawaited(_applySpread(value));
        SharedPreferences.getInstance().then(
            (prefs) => prefs.setBool('epub_two_page_layout', value));
      },
      onReadingModeChanged: _setReadingMode,
      onReadingThemeChanged: _setReadingTheme,
      onReadingFontChanged: _setReadingFont,
      onPortraitLockChanged: _setPortraitLock,
      onLineGuideChanged: (value) {
        setState(() => _lineGuide = value);
        SharedPreferences.getInstance().then(
            (prefs) => prefs.setBool('epub_line_guide', value));
      },
      onGuideDimmingChanged: (value) {
        setState(() => _guideDimming = value);
        SharedPreferences.getInstance().then(
            (prefs) => prefs.setDouble('epub_guide_dimming', value));
      },
    );
  }

  EpubTheme _currentReadingTheme() => epubReadingTheme(
      _readingTheme,
      _readingFont,
      Provider.of<ThemeProvider>(context, listen: false).isDarkMode);

  void _setReadingTheme(EpubReadingTheme value) {
    if (_readingTheme == value) return;
    final appDark = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    setState(() {
      _readingTheme = value;
      _isDarkMode = readingThemeIsDark(value, appDark);
    });
    if (_isEpubReady) {
      unawaited(_epubController.updateTheme(theme: _currentReadingTheme()));
    }
    SharedPreferences.getInstance().then(
        (prefs) => prefs.setString('epub_reading_theme', value.name));
  }

  void _setReadingFont(EpubReadingFont value) {
    if (_readingFont == value) return;
    setState(() => _readingFont = value);
    if (_isEpubReady) {
      unawaited(_epubController.updateTheme(theme: _currentReadingTheme()));
    }
    SharedPreferences.getInstance().then(
        (prefs) => prefs.setString('epub_reading_font', value.name));
  }

  List<DeviceOrientation> _defaultReaderOrientations() => Platform.isIOS
      ? const [
          DeviceOrientation.portraitUp, DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
        ]
      : ResponsiveHelper.supportedOrientationsForDevice();

  void _setPortraitLock(bool value) {
    if (_portraitLock == value) return;
    setState(() => _portraitLock = value);
    unawaited(SystemChrome.setPreferredOrientations(value
        ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
        : _defaultReaderOrientations()));
    SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool('epub_portrait_lock', value));
  }

  void _startReaderTimeout(String path) {
    _readerTimeout?.cancel();
    _readerTimeout = Timer(const Duration(seconds: 90), () async {
      if (!mounted || _isEpubReady) return;
      // A ZIP may have a valid header but an unreadable EPUB package.
      try { await File(path).delete(); } catch (_) {}
      final id = widget.documentId;
      final userId = _readerUserId;
      if (id != null && userId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('epub_position_${userId}_${widget.source ?? 'ebook'}_$id');
        _resumeCfi = null;
      }
      if (mounted) setState(() {
        _error = 'This EPUB could not be opened. Tap Retry to download it again.';
        _localPath = null;
      });
    });
  }

  void _showLocalEpub(String path) {
    if (!mounted) return;
    _chaptersReady = false;
    _pageDisplayed = false;
    setState(() {
      _viewerGeneration++;
      _localPath = path;
      _isLoading = false;
    });
    _startReaderTimeout(path);
  }

  void _markReaderReady() {
    if (!mounted || _error != null || _isEpubReady ||
        !_chaptersReady || !_pageDisplayed) return;
    _readerTimeout?.cancel();
    setState(() => _isEpubReady = true);
    if (_dataLoaded) {
      _reapplyAnnotations();
    } else {
      _loadData();
    }
    unawaited(installEpubImageZoom(_epubController).catchError(
        (Object e) => debugPrint('[EPUB] Image zoom unavailable: $e')));
  }

  // ── EPUB loading ──────────────────────────────────────────────────

  Future<void> _loadEpub() async {
    File? partFile;
    try {
      final userId = await StorageService().getUserId();
      _readerUserId = userId;
      if (widget.documentId != null && userId != null) {
        final prefs = await SharedPreferences.getInstance();
        _resumeCfi = prefs.getString(
            'epub_position_${userId}_${widget.source ?? 'ebook'}_${widget.documentId}');
      }
      final id = widget.documentId;
      final isDocument = widget.source == 'document';
      final prefix = isDocument ? 'doc' : 'ebook';
      if (id != null && userId != null) {
        final downloadedPath = await DownloadService().getDownloadedPath(
            epubDownloadFileName(userId, id, isDocument: isDocument));
        if (downloadedPath != null) {
          final file = File(downloadedPath);
          if (await isEpubArchive(file)) {
            _showLocalEpub(downloadedPath);
            return;
          }
          // An older download may contain a PDF or an interrupted response.
          await file.delete();
        }
      }

      // Revalidate access before using the temporary cache. A different user
      // on the same device must not open a previously viewed paid book.
      String? url;
      if (id != null && isDocument) {
        final response = await ApiService().dio.get(ApiConstants.documentViewUrl(id));
        url = response.data['data']['url'] as String?;
      } else if (id != null) {
        final data = await EbookAccessService().getEbookViewUrl(id);
        url = data['url'] as String?;
      } else {
        url = widget.epubUrl;
      }
      if (url == null || url.isEmpty) throw StateError('No EPUB file URL');
      if (!mounted) return;

      // Uploads use a new object path, so a replaced book cannot reuse its
      // previous temporary copy. Query parameters on signed URLs are ignored.
      final objectName = Uri.parse(url).pathSegments.last
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/pgme_epub_${prefix}_${id ?? 'external'}_$objectName.epub';
      final file = File(filePath);
      if (await isEpubArchive(file)) {
        _showLocalEpub(filePath);
        return;
      }
      if (await file.exists()) await file.delete();

      partFile = File('$filePath.part.${DateTime.now().microsecondsSinceEpoch}');
      _downloadCancelToken = CancelToken();
      await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 5),
      )).download(url, partFile.path,
          cancelToken: _downloadCancelToken,
          onReceiveProgress: (received, total) {
        if (total > 0 && mounted) {
          setState(() => _downloadProgress = received / total);
        }
      });
      if (!await isEpubArchive(partFile)) {
        throw const FormatException('The downloaded file is not an EPUB archive');
      }
      await partFile.rename(filePath);
      _showLocalEpub(filePath);
    } catch (e) {
      debugPrint('EPUB load error: $e');
      if (partFile != null && await partFile.exists()) await partFile.delete();
      if (mounted) {
        setState(() {
          _error = e is FormatException
              ? 'This file is not a valid EPUB. Please contact support.'
              : 'Could not download this EPUB. Please try again.';
          _isLoading = false;
        });
      }
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
          showAppDialog(context, message: 'Failed to add bookmark', type: AppDialogType.info);
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
        _buildToolbar(isDark, textColor, toolbarColor, isTablet),
        // Chapter + progress indicator
        if (_isEpubReady)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: toolbarColor,
            child: Row(children: [
              Expanded(child: Text(
                _currentChapter.isNotEmpty ? _currentChapter : widget.title,
                style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkTextTertiary : Colors.grey[500]),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('${(_readProgress * 100).toInt()}%',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkTextTertiary : Colors.grey[500])),
            ]),
          ),
        if (_isEpubReady)
          LinearProgressIndicator(
            value: _readProgress, backgroundColor: Colors.transparent,
            color: AppColors.primaryBlue, minHeight: 2),
        Expanded(
          child: _error != null
              ? _buildError(textColor, isTablet)
              : _isLoading ? _buildLoading(isTablet) : _buildEpubViewer(isDark)),
        if (_isEpubReady) _buildBottomActionBar(isDark, isTablet),
      ]),
    );
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
              onTap: () => _setReadingTheme(_isDarkMode
                  ? EpubReadingTheme.light : EpubReadingTheme.dark),
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
                if (value.trim().isNotEmpty && _isEpubReady && !_isSearchBusy) {
                  _isSearchBusy = true;
                  try {
                    final results = await searchEpubBook(_epubController, value);
                    if (!mounted) return;
                    final cfi = await showEpubSearchResults(context, results);
                    if (mounted && cfi != null) _epubController.display(cfi: cfi);
                  } catch (e) {
                    if (mounted) {
                      showAppDialog(context,
                          message: 'Search could not finish. Please try again.');
                    }
                  } finally {
                    _isSearchBusy = false;
                  }
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
          _bottomAction(Icons.text_fields, 'Text', AppColors.primaryBlue,
              _showAppearanceSettings, isDark, isTablet),
          _bottomAction(Icons.menu_book_outlined, 'Contents', AppColors.primaryBlue,
              _showNavigation, isDark, isTablet),
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

  void _toggleReadingMode() => _setReadingMode(!_isScrollMode);

  void _setReadingMode(bool scroll) {
    if (_isScrollMode == scroll) return;
    setState(() {
      _isScrollMode = scroll;
      if (_localPath != null) {
        _resumeCfi = _currentCfi ?? _resumeCfi;
        _viewerGeneration++;
        _isEpubReady = false;
        _chaptersReady = false;
        _pageDisplayed = false;
      }
    });
    if (_localPath != null) _startReaderTimeout(_localPath!);
    SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool('epub_scroll_mode', scroll));
  }

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
    final generation = _viewerGeneration;

    return Stack(children: [
      EpubViewer(
        key: ValueKey('epub-viewer-$_viewerGeneration'),
        epubSource: epubSource,
        epubController: _epubController,
        initialCfi: _resumeCfi,
        displaySettings: EpubDisplaySettings(
          fontSize: _fontSize,
          spread: _twoPageLayout && ResponsiveHelper.isTablet(context)
              ? EpubSpread.auto : EpubSpread.none,
          flow: _isScrollMode ? EpubFlow.scrolled : EpubFlow.paginated,
          snap: !_isScrollMode, useSnapAnimationAndroid: false,
          theme: _currentReadingTheme(),
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
          if (generation != _viewerGeneration) return;
          _chapters = chapters;
          _chaptersReady = true;
          _markReaderReady();
        },
        onEpubLoaded: () {
          if (generation != _viewerGeneration) return;
          _pageDisplayed = true;
          _markReaderReady();
        },
        onRelocated: (value) {
          if (generation != _viewerGeneration) return;
          if (mounted) {
            _currentCfi = value.startCfi;
            if (widget.documentId != null && _readerUserId != null &&
                value.startCfi.isNotEmpty) {
              unawaited(SharedPreferences.getInstance().then((prefs) =>
                  prefs.setString(
                      'epub_position_${_readerUserId}_${widget.source ?? 'ebook'}_${widget.documentId}',
                      value.startCfi)));
            }
            setState(() {
              _readProgress = value.progress.isFinite
                  ? value.progress.clamp(0.0, 1.0) : 0.0;
              _updateBookmarkState();
            });
          }
        },
        onTextSelected: (sel) {
          _selectedCfi = sel.selectionCfi;
          _selectedText = sel.selectedText;
        },
        onAnnotationClicked: (cfi, data) => _onAnnotationClicked(cfi),
      ),
      if (_isEpubReady && _lineGuide)
        Positioned.fill(child: EpubLineGuide(
          dimming: _guideDimming, accentColor: AppColors.primaryBlue)),
      if (!_isEpubReady)
        Container(
          color: isDark ? AppColors.darkBackground : Colors.white,
          child: const Center(child: CircularProgressIndicator(color: AppColors.primaryBlue))),
    ]);
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

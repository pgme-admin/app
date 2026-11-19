import 'dart:async';
import 'dart:convert';
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
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/services/bookmark_service.dart';
import 'package:pgme/core_android/services/download_service.dart';
import 'package:pgme/core_android/services/ebook_access_service.dart';
import 'package:pgme/core_android/services/api_service.dart';
import 'package:pgme/core_android/services/storage_service.dart';
import 'package:pgme/core_android/constants/api_constants.dart';
import 'package:pgme/core/utils/epub_file.dart';
import 'package:pgme/core/utils/epub_annotation.dart';
import 'package:pgme/core/utils/epub_reader_bridge.dart';
import 'package:pgme/core/utils/epub_search.dart';
import 'package:pgme/core/utils/epub_reader_theme.dart';
import 'package:pgme/core/widgets/epub_line_guide.dart';
import 'package:pgme/core/widgets/epub_appearance_sheet.dart';
import 'package:pgme/core/widgets/epub_navigation_sheet.dart';
import 'package:pgme/core/widgets/epub_annotation_menu.dart';
import 'package:pgme/core/widgets/epub_image_focus.dart';
import 'package:pgme/core/widgets/epub_page_curl.dart';
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

/// The floating annotation menu: over a text selection ([keys] empty) or
/// over tapped annotations ([keys] = their EpubAnnotation keys).
class _ReaderMenu {
  const _ReaderMenu(this.rect, this.keys);
  final Rect rect;
  final List<String> keys;
  bool get forSelection => keys.isEmpty;
}

class _EpubViewerScreenState extends State<EpubViewerScreen>
    with TickerProviderStateMixin {
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
  int? _sectionPagesLeft;
  String? _error;
  bool _isSearchOpen = false;
  bool _isSearchBusy = false;
  bool _isDarkMode = false;
  bool _isScrollMode = false;
  int _fontSize = 15;
  bool _twoPageLayout = true;
  EpubReadingTheme _readingTheme = EpubReadingTheme.followApp;
  EpubReadingFont _readingFont = EpubReadingFont.original;
  EpubLineSpacing _lineSpacing = EpubLineSpacing.original;
  EpubPageTurn _pageTurn = EpubPageTurn.slide;
  bool _boldText = false;
  double _pageBrightness = 1;
  bool _portraitLock = false;
  bool _lineGuide = false;
  double _guideDimming = 0.4;
  int _guideLines = 2;
  final EpubLineGuideController _guide = EpubLineGuideController();
  bool _guideHint = false;
  // Measured distance between text lines (px), for a window of whole lines.
  double? _guidePitch;
  Timer? _guideHintTimer;
  Timer? _marksTimer;

  // Tapping the page hides/shows the header, progress row and bottom action
  // bar so the text gets the whole screen (matters most in landscape).
  bool _chromeVisible = true;
  // An image is being opened or shown in the focus view.
  bool _imageFocused = false;
  Timer? _selectionCheckTimer;
  final GlobalKey _bookKey = GlobalKey();
  _ReaderMenu? _menu;
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
  int _jumpSerial = 0;

  // Page turns (see _turnPage). The book is a web view that Flutter cannot
  // move or bend, so a turn is drawn with stills of the page laid over it.
  late final AnimationController _turnAnim = AnimationController(vsync: this);
  late final Animation<double> _turnCurve =
      CurvedAnimation(parent: _turnAnim, curve: Curves.easeInOut);
  ui.FragmentProgram? _curlProgram;
  ui.Image? _turnCover; // still under the moving page
  ui.Image? _turnImage; // the page that moves
  EpubPageTurn _turnStyle = EpubPageTurn.slide;
  bool _turning = false;
  bool? _queuedTurnForward;
  Completer<String?>? _turnRelocated;
  bool _atStart = false;
  bool _atEnd = false;
  // Web view stills: verified once per book; after repeated failures (e.g.
  // a device that returns blank stills) pages turn without animation.
  bool _snapshotsVerified = false;
  int _blankSnapshots = 0;
  int _snapshotFailures = 0;
  bool get _snapshotsUnavailable =>
      _blankSnapshots >= 2 || _snapshotFailures >= 2;

  // Current selection
  String? _selectedCfi;
  String? _selectedText;

  // Current location
  String _currentChapter = '';
  String? _currentCfi;
  String? _readerUserId;

  // Bookmarks — bookmarkId -> cfi (stored in bookmark's `note` field)
  final Map<String, String> _bookmarkCfis = {};
  List<EpubChapter> _chapters = [];
  bool _isCurrentLocationBookmarked = false;
  String? _currentBookmarkId;

  // Highlights and underlines, keyed by EpubAnnotation.key, in the order
  // they were made.
  final Map<String, EpubAnnotation> _annotations = {};
  // Standalone notes (not attached to text), keyed by server id.
  final Map<String, Map<String, dynamic>> _standaloneNotes = {};

  // Undo (bottom bar + Notes panel), most recent last: annotation keys or
  // standalone note ids, as in the PDF reader.
  final List<String> _undoStack = [];

  Color get _readerAccent => readingThemeIsDark(_readingTheme,
          Provider.of<ThemeProvider>(context, listen: false).isDarkMode)
      ? const Color(0xFF8ABFFF)
      : AppColors.primaryBlue;

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
            unawaited(_applyReaderTheme());
          }
        }
      }
    });
    _loadAppearance();
    _loadEpub();
    PageCurl.load().then((program) => _curlProgram = program);
  }

  @override
  void dispose() {
    _readerTimeout?.cancel();
    _selectionCheckTimer?.cancel();
    _guideHintTimer?.cancel();
    _marksTimer?.cancel();
    _guide.dispose();
    _downloadCancelToken?.cancel();
    if (_portraitLock) {
      unawaited(
          SystemChrome.setPreferredOrientations(_defaultReaderOrientations()));
    }
    _reanchorTimer?.cancel();
    _turnAnim.dispose();
    _turnCover?.dispose();
    _turnImage?.dispose();
    super.dispose();
  }

  Future<void> _loadAppearance() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final theme = readingThemeFromName(prefs.getString('epub_reading_theme'));
    final font = readingFontFromName(prefs.getString('epub_reading_font'));
    final savedScroll = prefs.getBool('epub_scroll_mode') ?? false;
    final modeChanged = savedScroll != _isScrollMode;
    final appDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    setState(() {
      _fontSize = (prefs.getInt('epub_font_size') ?? 15).clamp(13, 24).toInt();
      _twoPageLayout = prefs.getBool('epub_two_page_layout') ?? true;
      _readingTheme = theme;
      _readingFont = font;
      _lineSpacing = lineSpacingFromName(prefs.getString('epub_line_spacing'));
      _pageTurn = pageTurnFromName(prefs.getString('epub_page_turn'));
      _boldText = prefs.getBool('epub_bold_text') ?? false;
      _pageBrightness = (prefs.getDouble('epub_page_brightness') ?? 1)
          .clamp(0.75, 1.0)
          .toDouble();
      _isDarkMode = readingThemeIsDark(theme, appDark);
      _portraitLock = prefs.getBool('epub_portrait_lock') ?? false;
      _lineGuide = prefs.getBool('epub_line_guide') ?? false;
      _guideLines = (prefs.getInt('epub_guide_lines') ?? 2).clamp(1, 3).toInt();
      _guideDimming = (prefs.getDouble('epub_guide_dimming') ?? 0.4)
          .clamp(0.0, 0.7)
          .toDouble();
    });
    if (_portraitLock) {
      unawaited(SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown
      ]));
    }
    if (_isEpubReady) {
      unawaited(_epubController.setFontSize(fontSize: _fontSize.toDouble()));
      _refreshMarksSoon();
      unawaited(_applySpread(_wantsSpread(_bookViewSize)));
      unawaited(_applyReaderTheme());
    }
    if (modeChanged) _setReadingMode(savedScroll);
  }

  /// Two facing pages, as in Apple Books on iPad: only on a tablet held in
  /// landscape (two columns in portrait are too narrow to read), and only
  /// when the reader has the option on.
  bool _wantsSpread(Size? size) =>
      _twoPageLayout &&
      size != null &&
      ResponsiveHelper.isTablet(context) &&
      size.width > size.height &&
      size.width >= 800;

  bool get _isSpread => !_isScrollMode && _wantsSpread(_bookViewSize);

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
    _clearSelection();
    final cfi =
        await showEpubNavigationSheet(context, _chapters, _bookmarkCfis);
    if (mounted && cfi != null) _displayCfi(cfi);
  }

  /// epub.js knows the displayed page count for the current spine section.
  /// EPUBs do not guarantee a fixed page count for a whole chapter, so this
  /// label is intentionally scoped to the current section and is hidden when
  /// the book is being scrolled.
  Future<void> _refreshSectionPages(String cfi, {bool retry = true}) async {
    try {
      final result = await _epubController.webViewController
          ?.evaluateJavascript(source: '''(function () {
            if (typeof rendition === 'undefined' || !rendition.location) return null;
            var end = rendition.location.end;
            if (!end || !end.displayed) return null;
            var progress = (typeof book !== 'undefined' && book.locations &&
              book.locations.length() > 0)
              ? book.locations.percentageFromCfi(rendition.location.start.cfi)
              : null;
            return JSON.stringify({cfi: rendition.location.start.cfi,
              page: end.displayed.page, total: end.displayed.total,
              progress: progress, atStart: rendition.location.atStart === true,
              atEnd: rendition.location.atEnd === true});
          })()''');
      if (!mounted || cfi != _currentCfi || result == null) return;
      final data = result is String ? jsonDecode(result) : result;
      if (data is! Map || data['cfi'] != cfi) return;
      final page = data['page'];
      final total = data['total'];
      final remaining = page is num && total is num && total > 0
          ? (total - page).clamp(0, total).toInt()
          : null;
      final measured = data['progress'];
      final progress = measured is num && measured.isFinite
          ? measured.clamp(0.0, 1.0).toDouble()
          : null;
      final useProgress = progress != null &&
          (progress > 0 || _readProgress == 0 || data['atStart'] == true);
      _atStart = data['atStart'] == true;
      _atEnd = data['atEnd'] == true;
      if (_sectionPagesLeft != remaining ||
          (useProgress && _readProgress != progress)) {
        setState(() {
          _sectionPagesLeft = remaining;
          if (useProgress) _readProgress = progress;
        });
      }
      if (progress == null && retry) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (mounted && cfi == _currentCfi) {
          await _refreshSectionPages(cfi, retry: false);
        }
      }
    } catch (e) {
      debugPrint('[EPUB] section progress unavailable: $e');
    }
  }

  void _showAppearanceSettings() {
    var guideTurnedOn = false;
    showEpubAppearanceSheet(
      context,
      fontSize: _fontSize,
      isTablet: ResponsiveHelper.isTablet(context),
      supportsAnimatedPageTurns: true,
      twoPageLayout: _twoPageLayout,
      isScrollMode: _isScrollMode,
      portraitLock: _portraitLock,
      boldText: _boldText,
      pageBrightness: _pageBrightness,
      lineGuide: _lineGuide,
      guideDimming: _guideDimming,
      readingTheme: _readingTheme,
      readingFont: _readingFont,
      lineSpacing: _lineSpacing,
      pageTurn: _pageTurn,
      accentColor: _readerAccent,
      onFontSizeChanged: (value) {
        setState(() => _fontSize = value);
        if (_isEpubReady) {
          unawaited(_epubController.setFontSize(fontSize: value.toDouble()));
          _refreshMarksSoon();
        }
        SharedPreferences.getInstance()
            .then((prefs) => prefs.setInt('epub_font_size', value));
      },
      onTwoPageLayoutChanged: (value) {
        setState(() => _twoPageLayout = value);
        if (_isEpubReady) unawaited(_applySpread(_wantsSpread(_bookViewSize)));
        SharedPreferences.getInstance()
            .then((prefs) => prefs.setBool('epub_two_page_layout', value));
      },
      onReadingModeChanged: _setReadingMode,
      onReadingThemeChanged: _setReadingTheme,
      onReadingFontChanged: _setReadingFont,
      onLineSpacingChanged: (value) {
        setState(() => _lineSpacing = value);
        _refreshMarksSoon();
        if (_isEpubReady) {
          unawaited(_applyReaderTheme());
        }
        SharedPreferences.getInstance()
            .then((prefs) => prefs.setString('epub_line_spacing', value.name));
      },
      onPageTurnChanged: (value) {
        setState(() => _pageTurn = value);
        SharedPreferences.getInstance()
            .then((prefs) => prefs.setString('epub_page_turn', value.name));
      },
      onBoldTextChanged: (value) {
        setState(() => _boldText = value);
        if (_isEpubReady) {
          unawaited(_applyReaderTheme());
        }
        SharedPreferences.getInstance()
            .then((prefs) => prefs.setBool('epub_bold_text', value));
      },
      onPageBrightnessChanged: (value) {
        setState(() => _pageBrightness = value);
        SharedPreferences.getInstance()
            .then((prefs) => prefs.setDouble('epub_page_brightness', value));
      },
      onPortraitLockChanged: _setPortraitLock,
      guideLines: _guideLines,
      onGuideLinesChanged: (value) {
        setState(() => _guideLines = value);
        SharedPreferences.getInstance()
            .then((prefs) => prefs.setInt('epub_guide_lines', value));
      },
      onLineGuideChanged: (value) {
        setState(() => _lineGuide = value);
        guideTurnedOn = value;
        if (value) _moveGuideToTop();
        SharedPreferences.getInstance()
            .then((prefs) => prefs.setBool('epub_line_guide', value));
      },
      onGuideDimmingChanged: (value) {
        setState(() => _guideDimming = value);
        SharedPreferences.getInstance()
            .then((prefs) => prefs.setDouble('epub_guide_dimming', value));
      },
    ).then((_) {
      // Shown once the sheet is out of the way.
      if (mounted && guideTurnedOn && _lineGuide) {
        unawaited(_showGuideHintOnce());
      }
    });
  }

  EpubTheme _currentReadingTheme() => epubReadingTheme(
      _readingTheme,
      _readingFont,
      Provider.of<ThemeProvider>(context, listen: false).isDarkMode,
      boldText: _boldText,
      lineSpacing: _lineSpacing);

  Future<void> _applyReaderTheme() async {
    try {
      await _epubController.updateTheme(theme: _currentReadingTheme());
      if (mounted) {
        await applyEpubLinkContrast(_epubController, _isDarkMode);
        await EpubReaderBridge.setDark(_epubController, _isDarkMode);
        _refreshMarksSoon();
      }
    } catch (e) {
      debugPrint('[EPUB] theme update unavailable: $e');
    }
  }

  /// Highlights and underlines are drawn over the text by position; after a
  /// theme, font, size or spacing change re-lays out the text, redraw them
  /// so they stay on their words.
  void _refreshMarksSoon() {
    _guidePitch = null;
    _marksTimer?.cancel();
    _marksTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) unawaited(EpubReaderBridge.refreshMarks(_epubController));
    });
  }

  // ── Line guide ────────────────────────────────────────────────────

  /// Reading window height: [_guideLines] lines at the current text size
  /// and spacing, plus a little room.
  double get _guideBandHeight {
    final measured = _guidePitch;
    if (measured != null) return _guideLines * measured + 2;
    final pitch = measured ??
        _fontSize *
            switch (_lineSpacing) {
              EpubLineSpacing.compact => 1.4,
              EpubLineSpacing.relaxed => 1.75,
              EpubLineSpacing.original => 1.5,
            };
    return _guideLines * pitch + 8;
  }

  /// Puts the reading window on the text line at (x, y) (normalized), or,
  /// with [scan], on the first line below y. The window snaps to whole
  /// lines like Apple Books' guide; without text there it centres on y.
  Future<void> _moveGuideToLine(double x, double y, {bool scan = false}) async {
    final height = _bookViewSize?.height ?? 0;
    if (height <= 0) return;
    final line = await EpubReaderBridge.lineAt(_epubController, x, y, scan: scan);
    if (!mounted) return;
    if (line == null) {
      if (!scan) _guide.moveTo(y);
      return;
    }
    final pitch = line.pitch * height;
    if (_guidePitch == null || (pitch - _guidePitch!).abs() > 0.5) {
      setState(() => _guidePitch = pitch);
    }
    final top = line.top * height - 3;
    _guide.moveTo((top + _guideBandHeight / 2) / height);
  }

  void _moveGuideToTop() {
    final height = _bookViewSize?.height ?? 0;
    if (height <= 0) return;
    _guide.moveTo((_guideBandHeight / 2 + 20) / height);
    unawaited(_moveGuideToLine(0.2, 0.02, scan: true));
  }

  Future<void> _showGuideHintOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || (prefs.getBool('epub_line_guide_hint_seen') ?? false)) {
      return;
    }
    await prefs.setBool('epub_line_guide_hint_seen', true);
    if (!mounted) return;
    setState(() => _guideHint = true);
    _guideHintTimer?.cancel();
    _guideHintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _guideHint = false);
    });
  }

  void _setReadingTheme(EpubReadingTheme value) {
    if (_readingTheme == value) return;
    final appDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    setState(() {
      _readingTheme = value;
      _isDarkMode = readingThemeIsDark(value, appDark);
    });
    if (_isEpubReady) {
      unawaited(_applyReaderTheme());
    }
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString('epub_reading_theme', value.name));
  }

  void _setReadingFont(EpubReadingFont value) {
    if (_readingFont == value) return;
    setState(() => _readingFont = value);
    if (_isEpubReady) {
      unawaited(_applyReaderTheme());
    }
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString('epub_reading_font', value.name));
  }

  List<DeviceOrientation> _defaultReaderOrientations() => Platform.isIOS
      ? const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]
      : ResponsiveHelper.supportedOrientationsForDevice();

  void _setPortraitLock(bool value) {
    if (_portraitLock == value) return;
    setState(() => _portraitLock = value);
    unawaited(SystemChrome.setPreferredOrientations(value
        ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
        : _defaultReaderOrientations()));
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool('epub_portrait_lock', value));
  }

  void _startReaderTimeout(String path) {
    _readerTimeout?.cancel();
    _readerTimeout = Timer(const Duration(seconds: 90), () async {
      if (!mounted || _isEpubReady) return;
      // A ZIP may have a valid header but an unreadable EPUB package.
      try {
        await File(path).delete();
      } catch (_) {}
      final id = widget.documentId;
      final userId = _readerUserId;
      if (id != null && userId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs
            .remove('epub_position_${userId}_${widget.source ?? 'ebook'}_$id');
        _resumeCfi = null;
      }
      if (mounted)
        setState(() {
          _error =
              'This EPUB could not be opened. Tap Retry to download it again.';
          _localPath = null;
        });
    });
  }

  void _showLocalEpub(String path) {
    if (!mounted) return;
    _chaptersReady = false;
    _pageDisplayed = false;
    _sectionPagesLeft = null;
    setState(() {
      _viewerGeneration++;
      _localPath = path;
      _isLoading = false;
    });
    _startReaderTimeout(path);
  }

  void _markReaderReady() {
    if (!mounted ||
        _error != null ||
        _isEpubReady ||
        !_chaptersReady ||
        !_pageDisplayed) return;
    _readerTimeout?.cancel();
    setState(() {
      _isEpubReady = true;
      _hasSelection = false;
      _menu = null;
    });
    _applyBookLayoutFixes();
    unawaited(applyEpubLinkContrast(_epubController, _isDarkMode).catchError(
        (Object e) => debugPrint('[EPUB] link contrast unavailable: $e')));
    unawaited(_prepareReaderPage(_viewerGeneration));
  }

  /// Installs the reader helpers into the freshly loaded book page, then
  /// draws the saved annotations (loading them the first time).
  Future<void> _prepareReaderPage(int generation) async {
    try {
      await EpubReaderBridge.install(_epubController,
          dark: _isDarkMode,
          onTurnRequest: (forward) {
            if (mounted && generation == _viewerGeneration) {
              unawaited(_turnPage(forward: forward));
            }
          });
    } catch (e) {
      debugPrint('[EPUB] reader helpers unavailable: $e');
    }
    if (!mounted || generation != _viewerGeneration) return;
    // Annotations already in memory (made before a reload, or loaded) first,
    // then the saved ones the first time.
    _reapplyAnnotations();
    if (!_dataLoaded) await _loadData();
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
        final response =
            await ApiService().dio.get(ApiConstants.documentViewUrl(id));
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
      final objectName = Uri.parse(url)
          .pathSegments
          .last
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/pgme_epub_${prefix}_${id ?? 'external'}_$objectName.epub';
      final file = File(filePath);
      if (await isEpubArchive(file)) {
        _showLocalEpub(filePath);
        return;
      }
      if (await file.exists()) await file.delete();

      partFile =
          File('$filePath.part.${DateTime.now().microsecondsSinceEpoch}');
      _downloadCancelToken = CancelToken();
      await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 5),
      )).download(url, partFile.path, cancelToken: _downloadCancelToken,
          onReceiveProgress: (received, total) {
        if (total > 0 && mounted) {
          setState(() => _downloadProgress = received / total);
        }
      });
      if (!await isEpubArchive(partFile)) {
        throw const FormatException(
            'The downloaded file is not an EPUB archive');
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
      final highlights =
          await _highlightService.getHighlights(widget.documentId!);
      if (!mounted) return;
      for (final h in highlights) {
        final id = h['highlight_id'] as String?;
        if (id == null) continue;
        final type = (h['annotation_type'] as String?) ?? 'highlight';
        final note = (h['note'] as String?)?.trim();
        if (type == 'note') {
          _standaloneNotes[id] = {'note': note ?? ''};
          continue;
        }
        final boundsData = h['bounds_data'] as List?;
        final cfi = (boundsData != null && boundsData.isNotEmpty)
            ? (boundsData.first['text'] as String? ?? '')
            : '';
        if (!cfi.startsWith('epubcfi(')) continue;
        final kind = type == 'underline' ? 'underline' : 'highlight';
        final key = EpubAnnotation.keyFor(kind, cfi);
        final existing = _annotations[key];
        if (existing != null) {
          // Older versions could save the same annotation twice.
          existing.serverIds.add(id);
          if ((existing.note ?? '').isEmpty && (note ?? '').isNotEmpty) {
            existing.note = note;
          }
          continue;
        }
        final color = (h['color'] as String?) ?? 'yellow';
        final a = EpubAnnotation(
          cfi: cfi,
          type: kind,
          color: epubHighlightColors.containsKey(color) ? color : 'yellow',
          text: (h['highlighted_text'] as String?) ?? '',
          note: (note ?? '').isEmpty ? null : note,
        )..serverIds.add(id);
        _annotations[key] = a;
        _drawAnnotation(a);
      }
      setState(() {});
    } catch (e) {
      debugPrint('[EPUB] highlights unavailable: $e');
    }

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
          setState(() {
            _bookmarkCfis[id] = _currentCfi!;
            _updateBookmarkState();
          });
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
              message:
                  e.toString().replaceFirst('Exception: ', '').trim().isEmpty
                      ? 'Failed to add bookmark'
                      : e.toString().replaceFirst('Exception: ', '').trim(),
              type: AppDialogType.info);
        }
      }
    }
  }

  // ── Highlights, underlines and notes ─────────────────────────────

  void _drawAnnotation(EpubAnnotation a) {
    unawaited(EpubReaderBridge.addAnnotation(_epubController,
        cfi: a.cfi, type: a.type, color: a.color));
  }

  void _showSnack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    // Floats above the reader's bottom bar so it never covers Undo.
    final media = MediaQuery.of(context);
    final barHeight = _chromeVisible
        ? (ResponsiveHelper.isTablet(context) ? 84.0 : 66.0) +
            media.padding.bottom
        : media.padding.bottom + 26;
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      action: action,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, barHeight + 8),
      duration: Duration(seconds: action == null ? 2 : 4),
    ));
  }

  /// Runs backend work for [a] after any earlier work for it, so a quick
  /// colour change, note or removal never races the first save.
  void _sync(EpubAnnotation a, Future<void> Function() work) {
    a.saving = (a.saving ?? Future<void>.value())
        .then((_) => work())
        .catchError((Object e) => debugPrint('[EPUB] annotation sync: $e'));
  }

  Future<void> _postAnnotation(EpubAnnotation a) async {
    final documentId = widget.documentId;
    if (documentId == null || a.removed) return;
    try {
      final text = a.text.length > 2000 ? a.text.substring(0, 2000) : a.text;
      final result = await _highlightService.addHighlight(
        documentId: documentId,
        pageNumber: 1,
        startOffset: 0,
        endOffset: 0,
        highlightedText: text,
        color: a.isHighlight ? a.color : 'blue',
        note: a.note,
        annotationType: a.type,
        boundsData: [
          {
            'left': 0,
            'top': 0,
            'width': 0,
            'height': 0,
            'text': a.cfi,
            'page_number': 1
          }
        ],
      );
      final id = result['highlight_id'] as String?;
      if (id == null) return;
      if (a.removed) {
        await _deleteServerIds([id]);
      } else {
        a.serverIds.add(id);
      }
    } catch (e) {
      debugPrint('[EPUB] annotation not saved: $e');
      if (!a.removed) {
        _showSnack(a.isHighlight
            ? 'Highlight not saved. Check your connection.'
            : 'Underline not saved. Check your connection.');
      }
    }
  }

  Future<void> _deleteServerIds(List<String> ids) async {
    for (final id in ids) {
      try {
        await _highlightService.deleteHighlight(id);
      } catch (e) {
        debugPrint('[EPUB] annotation $id not deleted: $e');
      }
    }
  }

  List<String> _takeServerIds(EpubAnnotation a) {
    final ids = List<String>.of(a.serverIds);
    a.serverIds.clear();
    return ids;
  }

  /// Highlight or underline the current selection (selection menu or the
  /// bottom bar). Re-highlighting a highlight changes its colour.
  EpubAnnotation? _annotateSelection(
      {required String type, String color = 'yellow'}) {
    final cfi = _selectedCfi;
    final text = _selectedText ?? '';
    if (cfi == null || cfi.isEmpty) {
      showAppDialog(context,
          message: 'Select text first by long-pressing on it',
          type: AppDialogType.info);
      return null;
    }
    _clearSelection();
    return _addAnnotation(cfi: cfi, type: type, color: color, text: text);
  }

  EpubAnnotation _addAnnotation({
    required String cfi,
    required String type,
    String color = 'yellow',
    String text = '',
    String? note,
  }) {
    final key = EpubAnnotation.keyFor(type, cfi);
    final existing = _annotations[key];
    if (existing != null) {
      if (existing.isHighlight) _setHighlightColor(existing, color);
      return existing;
    }
    final a = EpubAnnotation(
        cfi: cfi, type: type, color: color, text: text, note: note);
    setState(() {
      _annotations[key] = a;
      _undoStack
        ..remove(key)
        ..add(key);
    });
    _drawAnnotation(a);
    _sync(a, () => _postAnnotation(a));
    return a;
  }

  void _setHighlightColor(EpubAnnotation a, String color) {
    if (a.color == color) return;
    setState(() => a.color = color);
    _drawAnnotation(a);
    // The backend has no colour update: save the new colour, then delete
    // the old row(s).
    _sync(a, () async {
      final stale = _takeServerIds(a);
      await _postAnnotation(a);
      await _deleteServerIds(stale);
    });
  }

  void _removeAnnotations(List<EpubAnnotation> list, {bool offerUndo = true}) {
    if (list.isEmpty) return;
    setState(() {
      for (final a in list) {
        a.removed = true;
        _annotations.remove(a.key);
        _undoStack.remove(a.key);
      }
      _menu = null;
    });
    for (final a in list) {
      unawaited(EpubReaderBridge.removeAnnotation(_epubController,
          cfi: a.cfi, type: a.type));
      _sync(a, () => _deleteServerIds(_takeServerIds(a)));
    }
    if (!offerUndo) return;
    final single = list.length == 1;
    _showSnack(
      single
          ? (list.first.isHighlight ? 'Highlight removed' : 'Underline removed')
          : 'Highlight and underline removed',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          if (!mounted) return;
          for (final a in list) {
            _addAnnotation(
                cfi: a.cfi,
                type: a.type,
                color: a.color,
                text: a.text,
                note: a.note);
          }
        },
      ),
    );
  }

  void _clearSelection() {
    _selectedCfi = null;
    _selectedText = null;
    _hasSelection = false;
    if (mounted && _menu != null) setState(() => _menu = null);
    unawaited(EpubReaderBridge.resetSelection(_epubController));
  }

  /// A tap normally clears the selection in the book itself; if the book
  /// does not report that, check it so the reader never stays blocked.
  void _verifySelectionSoon() {
    _selectionCheckTimer?.cancel();
    _selectionCheckTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted || !_hasSelection) return;
      final still = await EpubReaderBridge.hasSelection(_epubController);
      if (!mounted || still) return;
      _clearSelection();
    });
  }

  void _showAnnotationMenu(EpubTapTarget target) {
    final keys = [
      for (final hit in target.annotations)
        if (_annotations.containsKey(EpubAnnotation.keyFor(hit.type, hit.cfi)))
          EpubAnnotation.keyFor(hit.type, hit.cfi)
    ];
    final box = _bookKey.currentContext?.findRenderObject() as RenderBox?;
    final r = target.rect;
    if (keys.isEmpty || box == null || r == null) {
      setState(() => _chromeVisible = !_chromeVisible);
      return;
    }
    final size = box.size;
    setState(() => _menu = _ReaderMenu(
        Rect.fromLTWH(r.left * size.width, r.top * size.height,
            r.width * size.width, r.height * size.height),
        keys));
  }

  Widget _buildMenu(_ReaderMenu menu, Size area, bool isDark) {
    if (menu.forSelection) {
      return EpubAnnotationMenu(
        anchor: menu.rect,
        area: area,
        dark: isDark,
        accentColor: _readerAccent,
        onColor: (color) => _annotateSelection(type: 'highlight', color: color),
        onUnderline: () => _annotateSelection(type: 'underline'),
        onNote: () {
          final a = _annotateSelection(type: 'highlight');
          if (a != null) _editNote(a);
        },
      );
    }
    final items = [
      for (final key in menu.keys)
        if (_annotations[key] != null) _annotations[key]!
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    final highlight = items.where((a) => a.isHighlight).firstOrNull;
    final underline = items.where((a) => !a.isHighlight).firstOrNull;
    final primary = highlight ?? underline!;
    return EpubAnnotationMenu(
      anchor: menu.rect,
      area: area,
      dark: isDark,
      accentColor: _readerAccent,
      selectedColor: highlight?.color,
      underlined: underline != null,
      hasNote: (primary.note ?? '').isNotEmpty,
      onColor: (color) {
        setState(() => _menu = null);
        if (highlight != null) {
          _setHighlightColor(highlight, color);
        } else {
          _addAnnotation(
              cfi: primary.cfi,
              type: 'highlight',
              color: color,
              text: primary.text);
        }
      },
      onUnderline: () {
        setState(() => _menu = null);
        if (underline != null) {
          _removeAnnotations([underline]);
        } else {
          _addAnnotation(
              cfi: primary.cfi, type: 'underline', text: primary.text);
        }
      },
      onNote: () {
        setState(() => _menu = null);
        _editNote(primary);
      },
      removeLabel: items.length > 1
          ? 'Remove'
          : (primary.isHighlight ? 'Remove Highlight' : 'Remove Underline'),
      onRemove: () => _removeAnnotations(items),
    );
  }

  void _editNote(EpubAnnotation a) {
    _showNoteEditor(
      title: (a.note ?? '').isEmpty ? 'Add Note' : 'Edit Note',
      quote: a.text,
      initial: a.note ?? '',
      allowEmpty: true,
      onSave: (text) {
        final note = text.trim().isEmpty ? null : text.trim();
        if (note == a.note) return;
        setState(() => a.note = note);
        _sync(a, () async {
          if (a.removed) return;
          if (a.serverIds.isEmpty) {
            // Not saved yet (or the first save failed): save it with the note.
            await _postAnnotation(a);
            return;
          }
          try {
            await _highlightService.updateHighlightNote(
                a.serverIds.first, note);
          } catch (e) {
            debugPrint('[EPUB] note not saved: $e');
            _showSnack('Note not saved. Check your connection.');
          }
        });
      },
    );
  }

  void _deleteStandaloneNote(String id) {
    setState(() {
      _standaloneNotes.remove(id);
      _undoStack.remove(id);
    });
    _highlightService.deleteHighlight(id).catchError((_) {});
  }

  /// Undoes the most recent highlight, underline or note (like the PDF
  /// reader's Undo).
  void _undoLast([StateSetter? setSheetState]) {
    while (_undoStack.isNotEmpty) {
      final id = _undoStack.removeLast();
      final a = _annotations[id];
      if (a != null) {
        _removeAnnotations([a], offerUndo: false);
        _showSnack(a.isHighlight ? 'Highlight undone' : 'Underline undone');
        break;
      }
      if (_standaloneNotes.containsKey(id)) {
        _deleteStandaloneNote(id);
        _showSnack('Note undone');
        break;
      }
    }
    if (mounted) setState(() {});
    setSheetState?.call(() {});
  }

  // ── Notes panel ───────────────────────────────────────────────────

  void _showNotesPanel() {
    _clearSelection();
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return StatefulBuilder(builder: (sheetContext, setSheetState) {
          final annotations = _annotations.values.toList();
          final noteIds = _standaloneNotes.keys.toList();
          final count = annotations.length + noteIds.length;
          return DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.85,
            expand: false,
            builder: (context, scrollController) {
              return Column(children: [
                // Drag handle
                Center(
                    child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(top: 12, bottom: 16),
                        decoration: BoxDecoration(
                            color: isDark ? Colors.white24 : Colors.black12,
                            borderRadius: BorderRadius.circular(2)))),
                // Header
                Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
                    child: Row(children: [
                      Icon(Icons.sticky_note_2_outlined,
                          size: 22, color: _readerAccent),
                      const SizedBox(width: 8),
                      Text('Notes & Highlights',
                          style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: textColor)),
                      const Spacer(),
                      if (_undoStack.isNotEmpty)
                        _headerButton('Undo', Icons.undo, AppColors.error,
                            () => _undoLast(setSheetState)),
                      const SizedBox(width: 6),
                      _headerButton('Add Note', Icons.add, _readerAccent,
                          () => _showAddNoteDialog(setSheetState)),
                    ])),
                const SizedBox(height: 10),
                Divider(
                    height: 1,
                    color: isDark
                        ? AppColors.darkDivider
                        : const Color(0xFFF0F0F0)),
                // List
                Expanded(
                  child: count == 0
                      ? Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.note_alt_outlined,
                              size: 40, color: subtitleColor),
                          const SizedBox(height: 8),
                          Text('No highlights or notes yet',
                              style: TextStyle(
                                  fontSize: 14, color: subtitleColor)),
                        ]))
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: count,
                          separatorBuilder: (_, __) => Divider(
                              height: 1,
                              indent: 60,
                              endIndent: 20,
                              color: isDark
                                  ? AppColors.darkDivider
                                  : const Color(0xFFF0F0F0)),
                          itemBuilder: (_, index) {
                            if (index >= annotations.length) {
                              final id = noteIds[index - annotations.length];
                              return _buildNoteItem(
                                  id,
                                  _standaloneNotes[id]?['note'] as String? ??
                                      '',
                                  textColor,
                                  setSheetState);
                            }
                            return _buildAnnotationItem(
                                annotations[index],
                                textColor,
                                subtitleColor,
                                setSheetState,
                                sheetContext);
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

  Widget _headerButton(
      String label, IconData icon, Color color, VoidCallback onTap) {
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
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w500, color: color)),
        ]),
      ),
    );
  }

  Widget _buildNoteItem(String id, String noteText, Color textColor,
      StateSetter setSheetState) {
    return InkWell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
              radius: 15,
              backgroundColor: _readerAccent.withValues(alpha: 0.15),
              child: Icon(Icons.note_outlined, size: 16, color: _readerAccent)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(noteText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 13, color: textColor, height: 1.3))),
          GestureDetector(
              onTap: () {
                _deleteStandaloneNote(id);
                setSheetState(() {});
              },
              child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.delete_outline,
                      size: 20,
                      color: AppColors.error.withValues(alpha: 0.7)))),
        ]),
      ),
    );
  }

  Widget _buildAnnotationItem(
      EpubAnnotation a,
      Color textColor,
      Color subtitleColor,
      StateSetter setSheetState,
      BuildContext sheetContext) {
    final color = a.isHighlight
        ? epubHighlightColors[a.color] ?? epubHighlightColors['yellow']!
        : (_isDarkMode ? const Color(0xFF8ABFFF) : const Color(0xFF1565C0));
    void goTo() {
      Navigator.pop(sheetContext);
      _displayCfi(a.cfi);
    }

    return InkWell(
      onTap: goTo,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
              radius: 15,
              backgroundColor: color.withValues(alpha: 0.22),
              child: Icon(
                  a.isHighlight ? Icons.border_color : Icons.format_underlined,
                  size: 16,
                  color: a.isHighlight ? textColor : color)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  a.text.trim().isNotEmpty
                      ? a.text.trim()
                      : (a.isHighlight ? 'Highlight' : 'Underline'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: textColor,
                      fontStyle: a.text.trim().isNotEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                      height: 1.3)),
              if ((a.note ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(a.note!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: subtitleColor, height: 1.3)),
              ],
            ],
          )),
          // Navigate to location
          GestureDetector(
              onTap: goTo,
              child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.my_location,
                      size: 20, color: _readerAccent.withValues(alpha: 0.7)))),
          // Delete
          GestureDetector(
              onTap: () {
                _removeAnnotations([a]);
                setSheetState(() {});
              },
              child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.delete_outline,
                      size: 20,
                      color: AppColors.error.withValues(alpha: 0.7)))),
        ]),
      ),
    );
  }

  void _showAddNoteDialog(StateSetter setSheetState) {
    _showNoteEditor(
      title: 'Add Note',
      onSave: (note) => _saveStandaloneNote(note, setSheetState),
    );
  }

  /// Note editor sheet, shared by standalone notes and notes on highlights.
  void _showNoteEditor({
    required String title,
    required ValueChanged<String> onSave,
    String initial = '',
    String quote = '',
    bool allowEmpty = false,
  }) {
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;
    final noteCtrl = TextEditingController(text: initial);

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                        borderRadius: BorderRadius.circular(2)))),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(title,
                    style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: textColor))),
            if (quote.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Container(
                  padding: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                      border: Border(
                          left: BorderSide(color: _readerAccent, width: 3))),
                  child: Text(quote.trim(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : Colors.grey[700])),
                ),
              ),
            const SizedBox(height: 12),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                    controller: noteCtrl,
                    maxLines: 4,
                    maxLength: 500,
                    autofocus: true,
                    style:
                        TextStyle(color: textColor, fontSize: 14, height: 1.5),
                    decoration: InputDecoration(
                        hintText: 'Write your note...',
                        hintStyle: TextStyle(
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : Colors.grey[400]),
                        filled: true,
                        fillColor: isDark
                            ? AppColors.darkSurface
                            : const Color(0xFFF8F9FE),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: _readerAccent, width: 1.5))))),
            const SizedBox(height: 14),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Cancel',
                          style: TextStyle(
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : Colors.grey[600]))),
                  const SizedBox(width: 8),
                  Container(
                      decoration: BoxDecoration(
                          gradient: AppColors.blueGradient,
                          borderRadius: BorderRadius.circular(24)),
                      child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () {
                                final note = noteCtrl.text.trim();
                                if (note.isEmpty && !allowEmpty) return;
                                Navigator.pop(ctx);
                                onSave(note);
                              },
                              child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 10),
                                  child: Text('Save',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14)))))),
                ])),
            const SizedBox(height: 12),
          ],
        )),
      ),
    ).whenComplete(() {
      // Disposed after the sheet's closing animation.
      Future<void>.delayed(
          const Duration(milliseconds: 400), noteCtrl.dispose);
    });
  }

  Future<void> _saveStandaloneNote(
      String note, StateSetter setSheetState) async {
    if (widget.documentId == null) return;
    try {
      final result = await _highlightService.addHighlight(
        documentId: widget.documentId!,
        pageNumber: 1,
        startOffset: 0,
        endOffset: 0,
        highlightedText: '',
        color: 'yellow',
        annotationType: 'note',
        note: note,
      );
      final id = result['highlight_id'] as String;
      if (!mounted) return;
      setState(() {
        _standaloneNotes[id] = {'note': note};
        _undoStack.add(id);
      });
      setSheetState(() {});
    } catch (_) {
      if (mounted)
        showAppDialog(context,
            message: 'Failed to save note', type: AppDialogType.info);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = readingThemeIsDark(_readingTheme, themeProvider.isDarkMode);
    final isTablet = ResponsiveHelper.isTablet(context);
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;
    final toolbarColor = isDark ? AppColors.darkCardBackground : Colors.white;

    return PopScope(
      // Back first dismisses the selection/annotation menu.
      canPop: _menu == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _menu != null) _clearSelection();
      },
      child: Scaffold(
        // A location/search keyboard must not resize epub.js mid-navigation.
        resizeToAvoidBottomInset: false,
        backgroundColor: backgroundColor,
        appBar: AppBar(
            toolbarHeight: 0,
            backgroundColor: toolbarColor,
            elevation: 0,
            scrolledUnderElevation: 0,
            systemOverlayStyle: isDark
                ? SystemUiOverlayStyle.light
                    .copyWith(statusBarColor: Colors.transparent)
                : SystemUiOverlayStyle.dark
                    .copyWith(statusBarColor: Colors.transparent)),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      color: toolbarColor,
                      child: Row(children: [
                        Expanded(
                            child: Text(
                                !_isScrollMode && _sectionPagesLeft != null
                                    ? '${_sectionPagesLeft!} pages left in section'
                                    : _currentChapter.isNotEmpty
                                        ? _currentChapter
                                        : widget.title,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? AppColors.darkTextTertiary
                                        : Colors.grey[500]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                        // Tap the percentage to jump to a location.
                        GestureDetector(
                          onTap: _showGoToLocationDialog,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: _readerAccent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10)),
                              child: Text('${(_readProgress * 100).toInt()}%',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _readerAccent))),
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
                        value: _readProgress,
                        backgroundColor: Colors.transparent,
                        color: _readerAccent,
                        minHeight: 2),
                  ),
                ])
              // Hidden (immersive, as in Apple Books): just the book title
              // under the status bar.
              : _immersiveBar(
                  top: true,
                  text: widget.title,
                  inset: MediaQuery.of(context).padding.top,
                  isDark: isDark),
          Expanded(
              child: _error != null
                  ? _buildError(textColor, isTablet)
                  : _isLoading
                      ? _buildLoading(isTablet)
                      : _buildEpubViewer(isDark)),
          _chromeVisible
              // Reserved (invisible, not tappable) until the book is ready.
              ? Visibility(
                  visible: _isEpubReady,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: _buildBottomActionBar(isDark, isTablet),
                )
              // Hidden: where you are in the chapter.
              : _immersiveBar(
                  top: false,
                  text: !_isEpubReady
                      ? ''
                      : !_isScrollMode && _sectionPagesLeft != null
                          ? (_sectionPagesLeft == 0
                              ? 'Last page in chapter · ${(_readProgress * 100).toInt()}%'
                              : '${_sectionPagesLeft!} ${_sectionPagesLeft == 1 ? 'page' : 'pages'} left in chapter · ${(_readProgress * 100).toInt()}%')
                          : '${(_readProgress * 100).toInt()}%',
                  inset: MediaQuery.of(context).padding.bottom,
                  isDark: isDark),
        ]),
      ),
    );
  }

  /// Title / position line shown while the reader controls are hidden.
  Widget _immersiveBar({
    required bool top,
    required String text,
    required double inset,
    required bool isDark,
  }) {
    const height = 26.0;
    final label = Text(text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
            color: isDark ? AppColors.darkTextTertiary : Colors.grey[500]));
    return SizedBox(
      width: double.infinity,
      height: inset + height,
      child: Padding(
        padding: EdgeInsets.only(
            top: top ? inset : 0,
            bottom: top ? 0 : inset,
            left: 48,
            right: 48),
        child: Center(child: label),
      ),
    );
  }

  // ── Page navigation + go-to-location ──────────────────────────────

  /// Navigation inside the book. The book refuses to move while text is
  /// selected, so the selection is cleared first.
  void _displayCfi(String cfi) {
    if (cfi.isEmpty) return;
    if (_hasSelection || _menu != null) _clearSelection();
    _epubController.display(cfi: cfi);
  }

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
    if (down == null || at == null || !_isEpubReady || _imageFocused) return;
    final hadSelection = _touchDownHadSelection || _hasSelection;

    final dx = x - down.dx;
    final dy = y - down.dy;
    final heldMs = DateTime.now().difference(at).inMilliseconds;

    // A quick, stationary touch is a tap. (A long press starts a text
    // selection and must not toggle anything.)
    if (dx.abs() < 0.03 && dy.abs() < 0.03 && heldMs < 350) {
      if (_menu != null && !_menu!.forSelection) {
        setState(() => _menu = null);
        return;
      }
      // The book clears its own selection on a tap.
      if (hadSelection) {
        _verifySelectionSoon();
        return;
      }
      unawaited(_handleTap(x, y));
      return;
    }

    // While text is selected, drags belong to the selection handles.
    if (hadSelection) return;

    // iOS only: swipe left/right turns the page in paginated mode. On
    // Android the book page detects swipes itself and asks for the turn
    // (EpubReaderBridge), so doing it here too would turn two pages.
    if (Platform.isIOS &&
        !_isScrollMode &&
        dx.abs() >= 0.12 &&
        dx.abs() > dy.abs() * 1.5) {
      unawaited(_turnPage(forward: dx < 0));
    }
  }

  /// Tap on the book: open an image, show the menu for a highlight, follow
  /// a link (the book does that), or show/hide the reader controls.
  Future<void> _handleTap(double x, double y) async {
    final generation = _viewerGeneration;
    final target = await EpubReaderBridge.tapAt(_epubController, x, y);
    if (!mounted ||
        generation != _viewerGeneration ||
        _imageFocused ||
        _hasSelection ||
        _turning) {
      return;
    }
    switch (target.kind) {
      case 'image':
        await _openImage(target);
      case 'annotation':
        _showAnnotationMenu(target);
      case 'link':
        break;
      default:
        // Line guide on: a tap outside the reading window moves it to the
        // tapped line (Apple Books-style); inside it shows/hides controls.
        final height = _bookViewSize?.height ?? 0;
        if (_lineGuide && height > 0) {
          final band = EpubLineGuide.bandRect(
              _guide.value, _guideBandHeight, _bookViewSize!);
          if (!band.contains(Offset(band.center.dx, y * height))) {
            if (_guideHint) setState(() => _guideHint = false);
            unawaited(_moveGuideToLine(x, y));
            return;
          }
        }
        setState(() {
          _menu = null;
          _chromeVisible = !_chromeVisible;
        });
    }
  }

  Future<void> _openImage(EpubTapTarget target) async {
    final src = target.src;
    if (src == null) return;
    _imageFocused = true;
    try {
      final bytes = await EpubReaderBridge.imageBytes(_epubController, src);
      if (!mounted) return;
      if (bytes == null) {
        _showSnack('This image could not be opened.');
        return;
      }
      final screen = MediaQuery.sizeOf(context);
      var origin = Rect.fromCenter(
          center: screen.center(Offset.zero), width: 48, height: 48);
      final box = _bookKey.currentContext?.findRenderObject() as RenderBox?;
      final r = target.rect;
      if (box != null && box.attached && r != null) {
        final size = box.size;
        final o = box.localToGlobal(Offset.zero);
        origin = Rect.fromLTWH(o.dx + r.left * size.width,
            o.dy + r.top * size.height, r.width * size.width,
            r.height * size.height);
      }
      // The image leaves the page while it is focused, as in Apple Books,
      // and returns to the same spot on the same page when closed.
      await EpubReaderBridge.setFocusedImageHidden(_epubController, true);
      if (!mounted) return;
      await showEpubImageFocus(context,
          bytes: bytes, origin: origin, label: target.label);
    } finally {
      _imageFocused = false;
      unawaited(EpubReaderBridge.setFocusedImageHidden(_epubController, false));
    }
  }

  /// Turns the page with the chosen effect (Slide, Curl or Fast Fade).
  ///
  /// The book is a web view that Flutter cannot move or bend, so a turn is
  /// drawn with stills of the page laid over it: for "next" the real page
  /// turns underneath and the still of the old page moves away; for
  /// "previous" a still of the previous page moves back in over a still of
  /// the current one. Every wait is bounded, and without a usable still the
  /// page simply turns, so a turn can never leave the reader stuck.
  Future<void> _turnPage({required bool forward}) async {
    if (!_isEpubReady || _isScrollMode || _imageFocused) return;
    if (_hasSelection || _menu != null) _clearSelection();
    if (_turning) {
      _queuedTurnForward = forward; // played once this turn finishes
      return;
    }
    if (forward ? _atEnd : _atStart) {
      unawaited(HapticFeedback.selectionClick());
      return;
    }
    _turning = true;
    final generation = _viewerGeneration;
    final startCfi = _currentCfi;
    // Curl turns one sheet; in a two-page spread both pages would bend as
    // one, so spreads slide instead.
    final style = _pageTurn == EpubPageTurn.curl &&
            (_curlProgram == null || _isSpread)
        ? EpubPageTurn.slide
        : _pageTurn;
    final animate =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false) &&
            !_snapshotsUnavailable;
    try {
      final current = animate ? await _snapshotBook() : null;
      if (!mounted || generation != _viewerGeneration) {
        current?.dispose();
        return;
      }
      if (current != null) {
        // Cover the book with the still before it changes underneath.
        setState(() => _turnCover = current);
        await _nextFrames();
        if (!mounted) return;
      }
      final relocated = _turnRelocated = Completer<String?>();
      await EpubReaderBridge.turn(_epubController, forward);
      final newCfi = await relocated.future
          .timeout(const Duration(milliseconds: 900), onTimeout: () => null);
      // A new page starts reading at the top.
      if (mounted && _lineGuide && newCfi != null && newCfi != startCfi) {
        _moveGuideToTop();
      }
      // First/last page or a failed turn: nothing to animate.
      if (current == null ||
          !mounted ||
          generation != _viewerGeneration ||
          newCfi == null ||
          newCfi == startCfi) {
        return;
      }
      _turnAnim.duration = switch (style) {
        EpubPageTurn.curl => const Duration(milliseconds: 460),
        EpubPageTurn.slide => const Duration(milliseconds: 280),
        EpubPageTurn.fastFade => const Duration(milliseconds: 170),
      };
      if (forward) {
        // Give the web view a moment to paint the new page underneath.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;
        setState(() {
          _turnStyle = style;
          _turnAnim.value = 0;
          _turnImage = current;
          _turnCover = null;
        });
        await _turnAnim.forward(from: 0).orCancel;
      } else {
        final previous = await _snapshotBook();
        if (!mounted || previous == null) {
          previous?.dispose();
          return;
        }
        setState(() {
          _turnStyle = style;
          _turnAnim.value = 1;
          _turnImage = previous;
        });
        await _turnAnim.reverse(from: 1).orCancel;
      }
    } on TickerCanceled {
      // The reader closed during the turn.
    } catch (e) {
      debugPrint('[EPUB] page turn failed: $e');
    } finally {
      _turnRelocated = null;
      _turning = false;
      final stills = <ui.Image>{
        if (_turnCover != null) _turnCover!,
        if (_turnImage != null) _turnImage!,
      };
      _turnCover = null;
      _turnImage = null;
      if (mounted) {
        setState(() {});
        // Freed once a frame without them has been drawn.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final image in stills) {
            image.dispose();
          }
        });
        final queued = _queuedTurnForward;
        _queuedTurnForward = null;
        if (queued != null) unawaited(_turnPage(forward: queued));
      } else {
        for (final image in stills) {
          image.dispose();
        }
      }
    }
  }

  Future<void> _nextFrames() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }

  /// A still of the book as it is on screen now, or null (bounded wait).
  Future<ui.Image?> _snapshotBook() async {
    final webView = _epubController.webViewController;
    if (webView == null || _snapshotsUnavailable) return null;
    try {
      final bytes = await webView
          .takeScreenshot(
              // PNG keeps the web view's transparent margins transparent.
              screenshotConfiguration:
                  ScreenshotConfiguration(compressFormat: CompressFormat.PNG))
          .timeout(const Duration(milliseconds: 700));
      if (bytes == null || bytes.isEmpty) {
        _snapshotFailures++;
        return null;
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      if (!_snapshotsVerified) {
        if (await _isBlankImage(image)) {
          image.dispose();
          _blankSnapshots++;
          return null;
        }
        _snapshotsVerified = true;
      }
      _snapshotFailures = 0;
      return image;
    } on TimeoutException {
      _snapshotFailures++;
      debugPrint('[EPUB] page still timed out');
      return null;
    } catch (e) {
      _snapshotFailures++;
      debugPrint('[EPUB] page still failed: $e');
      return null;
    }
  }

  /// True when the still has a single colour (a capture-protected device
  /// can return blank stills; animating those would hide the page).
  Future<bool> _isBlankImage(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return true;
    final px = data.buffer.asUint8List();
    final first = data.lengthInBytes >= 4 ? data.getUint32(0) : 0;
    for (var i = 0; i + 3 < px.length; i += 4 * 397) {
      if (data.getUint32(i) != first) return false;
    }
    return true;
  }

  Future<void> _showGoToLocationDialog() async {
    if (!_isEpubReady) return;
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
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
    await _jumpToProgress((value / 100).clamp(0.0, 1.0));
  }

  Future<void> _jumpToProgress(double progress) async {
    final serial = ++_jumpSerial;
    final generation = _viewerGeneration;
    final webView = _epubController.webViewController;
    if (webView == null) return;
    try {
      // flutter_epub_viewer's toProgress() passes -1 to rendition.display()
      // while epub.js is still generating its location index. That can leave
      // the reader blank. Wait for a real CFI, without changing the page.
      for (var attempt = 0; attempt < 40; attempt++) {
        if (!mounted ||
            generation != _viewerGeneration ||
            serial != _jumpSerial) return;
        final cfi = await webView.evaluateJavascript(source: '''
          (function () {
            if (typeof book === 'undefined' || !book.locations ||
                book.locations.total < 1) return null;
            var cfi = book.locations.cfiFromPercentage($progress);
            return typeof cfi === 'string' && cfi.indexOf('epubcfi(') === 0
              ? cfi : null;
          })();
        ''');
        if (cfi is String && cfi.startsWith('epubcfi(')) {
          if (mounted &&
              generation == _viewerGeneration &&
              serial == _jumpSerial) _epubController.display(cfi: cfi);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      if (mounted && serial == _jumpSerial) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Book navigation is still preparing. Try again.')));
      }
    } catch (e) {
      debugPrint('[EPUB] location jump unavailable: $e');
      if (mounted && serial == _jumpSerial) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not jump to that location. Try again.')));
      }
    }
  }

  Widget _buildToolbar(
      bool isDark, Color textColor, Color toolbarColor, bool isTablet) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 16 : 12, vertical: isTablet ? 12 : 8),
        decoration: BoxDecoration(
            color: toolbarColor,
            border: Border(
                bottom: BorderSide(
                    color: isDark
                        ? AppColors.darkDivider
                        : const Color(0xFFE0E0E0),
                    width: 0.5))),
        child: Column(children: [
          Row(children: [
            GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                    width: isTablet ? 44 : 36,
                    height: isTablet ? 44 : 36,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? AppColors.darkSurface
                            : const Color(0xFFF5F5F5)),
                    child: Icon(Icons.arrow_back,
                        size: isTablet ? 22 : 18, color: textColor))),
            SizedBox(width: isTablet ? 12 : 8),
            Expanded(
                child: Text(widget.title,
                    style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 18 : 15,
                        color: textColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
            // Bookmark
            if (widget.documentId != null)
              GestureDetector(
                  onTap: _toggleBookmark,
                  child: Container(
                      width: isTablet ? 44 : 36,
                      height: isTablet ? 44 : 36,
                      margin: EdgeInsets.only(right: isTablet ? 4 : 2),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isCurrentLocationBookmarked
                              ? _readerAccent.withValues(alpha: 0.1)
                              : (isDark
                                  ? AppColors.darkSurface
                                  : const Color(0xFFF5F5F5))),
                      child: Icon(
                          _isCurrentLocationBookmarked
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          size: isTablet ? 22 : 18,
                          color: _isCurrentLocationBookmarked
                              ? _readerAccent
                              : textColor))),
            // Scroll/page toggle
            GestureDetector(
                onTap: _toggleReadingMode,
                child: Container(
                    width: isTablet ? 44 : 36,
                    height: isTablet ? 44 : 36,
                    margin: EdgeInsets.only(right: isTablet ? 4 : 2),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isScrollMode
                            ? _readerAccent.withValues(alpha: 0.1)
                            : (isDark
                                ? AppColors.darkSurface
                                : const Color(0xFFF5F5F5))),
                    child: Icon(
                        _isScrollMode ? Icons.view_day : Icons.auto_stories,
                        size: isTablet ? 22 : 18,
                        color: _isScrollMode ? _readerAccent : textColor))),
            // Dark mode
            GestureDetector(
                onTap: () => _setReadingTheme(_isDarkMode
                    ? EpubReadingTheme.light
                    : EpubReadingTheme.dark),
                child: Container(
                    width: isTablet ? 44 : 36,
                    height: isTablet ? 44 : 36,
                    margin: EdgeInsets.only(right: isTablet ? 4 : 2),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isDarkMode
                            ? _readerAccent.withValues(alpha: 0.1)
                            : (isDark
                                ? AppColors.darkSurface
                                : const Color(0xFFF5F5F5))),
                    child: Icon(
                        _isDarkMode ? Icons.light_mode : Icons.dark_mode,
                        size: isTablet ? 22 : 18,
                        color: _isDarkMode ? _readerAccent : textColor))),
            // Search
            GestureDetector(
                onTap: () => setState(() => _isSearchOpen = !_isSearchOpen),
                child: Container(
                    width: isTablet ? 44 : 36,
                    height: isTablet ? 44 : 36,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isSearchOpen
                            ? _readerAccent.withValues(alpha: 0.1)
                            : (isDark
                                ? AppColors.darkSurface
                                : const Color(0xFFF5F5F5))),
                    child: Icon(_isSearchOpen ? Icons.close : Icons.search,
                        size: isTablet ? 22 : 18,
                        color: _isSearchOpen ? _readerAccent : textColor))),
          ]),
          if (_isSearchOpen) ...[
            SizedBox(height: isTablet ? 10 : 8),
            TextField(
                autofocus: true,
                style:
                    TextStyle(fontSize: isTablet ? 16 : 14, color: textColor),
                decoration: InputDecoration(
                    hintText: 'Search in book...',
                    hintStyle: TextStyle(
                        color:
                            isDark ? AppColors.darkTextSecondary : Colors.grey),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 16 : 12,
                        vertical: isTablet ? 12 : 10),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.darkSurface
                        : const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
                        borderSide: BorderSide.none)),
                onSubmitted: (value) async {
                  if (value.trim().isNotEmpty &&
                      _isEpubReady &&
                      !_isSearchBusy) {
                    _isSearchBusy = true;
                    try {
                      final results =
                          await searchEpubBook(_epubController, value);
                      if (!mounted) return;
                      final cfi = await showEpubSearchResults(context, results);
                      if (mounted && cfi != null) _displayCfi(cfi);
                    } catch (e) {
                      if (mounted) {
                        showAppDialog(context,
                            message:
                                'Search could not finish. Please try again.');
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
      padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 24 : 16, vertical: isTablet ? 8 : 6),
      decoration: BoxDecoration(
          color: barColor,
          border: Border(
              top: BorderSide(
                  color:
                      isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0),
                  width: 0.5))),
      child: SafeArea(
          top: false,
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _bottomAction(
                Icons.border_color,
                'Highlight',
                const Color(0xFFFFEB3B),
                () => _annotateSelection(type: 'highlight'),
                isDark,
                isTablet),
            _bottomAction(
                Icons.format_underlined,
                'Underline',
                isDark ? const Color(0xFF8ABFFF) : const Color(0xFF1565C0),
                () => _annotateSelection(type: 'underline'),
                isDark,
                isTablet),
            _bottomAction(
                Icons.sticky_note_2_outlined,
                'Notes',
                isDark ? const Color(0xFF81D894) : const Color(0xFF43A047),
                _showNotesPanel,
                isDark,
                isTablet),
            // Undo — always visible, as in the PDF reader: red with a count
            // when something can be undone, muted otherwise.
            _bottomAction(
                Icons.undo,
                _undoStack.isEmpty ? 'Undo' : 'Undo (${_undoStack.length})',
                _undoStack.isEmpty
                    ? (isDark ? AppColors.darkTextSecondary : Colors.grey)
                    : AppColors.error,
                _undoStack.isEmpty ? () {} : () => _undoLast(),
                isDark,
                isTablet),
            _bottomAction(Icons.text_fields, 'Text', _readerAccent,
                _showAppearanceSettings, isDark, isTablet),
            _bottomAction(Icons.menu_book_outlined, 'Contents', _readerAccent,
                _showNavigation, isDark, isTablet),
          ])),
    );
  }

  Widget _bottomAction(IconData icon, String label, Color color,
      VoidCallback onTap, bool isDark, bool isTablet) {
    return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 12 : 8, vertical: isTablet ? 4 : 2),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: isTablet ? 40 : 32,
                  height: isTablet ? 40 : 32,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                      shape: BoxShape.circle),
                  child: Icon(icon, size: isTablet ? 20 : 16, color: color)),
              SizedBox(height: isTablet ? 4 : 2),
              Text(label,
                  style: TextStyle(
                      fontSize: isTablet ? 11 : 9,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : Colors.grey[700])),
            ])));
  }

  /// Flip (paginated) <-> scroll. The book engine's in-place flow switch
  /// leaves it unable to turn pages afterwards (next/prev stay on the same
  /// page), so the book is reloaded cleanly in the new mode, opening at the
  /// current location, and the saved highlights/underlines are re-applied.
  void _toggleReadingMode() => _setReadingMode(!_isScrollMode);

  void _setReadingMode(bool scroll) {
    if (_isScrollMode == scroll || _turning) return;
    _reanchorTimer?.cancel();
    setState(() {
      _isScrollMode = scroll;
      _sectionPagesLeft = null;
      if (_localPath != null) {
        _resumeCfi = _currentCfi ?? _resumeCfi;
        _viewerGeneration++;
        _isEpubReady = false;
        _chaptersReady = false;
        _pageDisplayed = false;
      }
    });
    if (_localPath != null) _startReaderTimeout(_localPath!);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool('epub_scroll_mode', scroll));
  }

  /// Puts the already-loaded highlights/underlines onto a freshly loaded book.
  void _reapplyAnnotations() {
    for (final a in _annotations.values) {
      _drawAnnotation(a);
    }
  }

  Widget _buildEpubViewer(bool isDark) {
    final epubSource = _localPath != null
        ? EpubSource.fromFile(File(_localPath!))
        : EpubSource.fromUrl(widget.epubUrl!);
    final generation = _viewerGeneration;
    final pageColor = isDark ? AppColors.darkBackground : Colors.white;

    return LayoutBuilder(builder: (context, constraints) {
      _onBookViewSize(constraints.biggest);
      return Stack(key: _bookKey, children: [
        EpubViewer(
          key: ValueKey('epub-viewer-$_viewerGeneration'),
          epubSource: epubSource,
          epubController: _epubController,
          initialCfi: _resumeCfi,
          displaySettings: EpubDisplaySettings(
              fontSize: _fontSize,
              spread: _wantsSpread(constraints.biggest)
                  ? EpubSpread.auto
                  : EpubSpread.none,
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
              theme: _currentReadingTheme(),
              allowScriptedContent: false),
          // The reader shows its own selection menu (EpubAnnotationMenu).
          // flutter_inappwebview's native custom menu items are not used:
          // on iOS they are kept on the web view class by memory address
          // after the web view is gone, and a later web view at the same
          // address runs the freed action (the Underline crash).
          suppressNativeContextMenu: true,
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
            final pendingTurn = _turnRelocated;
            if (pendingTurn != null && !pendingTurn.isCompleted) {
              pendingTurn.complete(value.startCfi);
            }
            if (mounted) {
              _currentCfi = value.startCfi;
              unawaited(_refreshSectionPages(value.startCfi));
              if (widget.documentId != null &&
                  _readerUserId != null &&
                  value.startCfi.isNotEmpty) {
                unawaited(SharedPreferences.getInstance().then((prefs) =>
                    prefs.setString(
                        'epub_position_${_readerUserId}_${widget.source ?? 'ebook'}_${widget.documentId}',
                        value.startCfi)));
              }
              setState(() {
                final reported = value.progress.isFinite
                    ? value.progress.clamp(0.0, 1.0)
                    : 0.0;
                // epub.js can relocate to a saved CFI before its location
                // index is generated. Keep the prior progress until the
                // measured value arrives from _refreshSectionPages.
                if (reported > 0 || _readProgress == 0) {
                  _readProgress = reported;
                }
                _menu = null;
                _updateBookmarkState();
              });
            }
          },
          onTextSelected: (sel) {
            if (generation != _viewerGeneration) return;
            _selectedCfi = sel.selectionCfi;
            _selectedText = sel.selectedText;
            _hasSelection = true;
          },
          onSelection: (text, cfi, rect, viewRect) {
            if (!mounted || generation != _viewerGeneration) return;
            if (cfi.isEmpty || _imageFocused) return;
            setState(() => _menu = _ReaderMenu(rect, const []));
          },
          onSelectionChanging: () {
            if (mounted && (_menu?.forSelection ?? false)) {
              setState(() => _menu = null);
            }
          },
          onDeselection: () {
            _hasSelection = false;
            if (mounted && (_menu?.forSelection ?? false)) {
              setState(() => _menu = null);
            }
          },
          onTouchDown: _onBookTouchDown,
          onTouchUp: _onBookTouchUp,
        ),
        // Page turn in progress: stills of the page over the book (see
        // _turnPage). Touches on the book wait until the turn is done.
        if (_turnCover != null || _turnImage != null)
          Positioned.fill(
            child: AbsorbPointer(
              child: Stack(fit: StackFit.expand, children: [
                // The stills have transparent margins (the web view is
                // transparent there), so they sit on the page colour.
                if (_turnCover != null)
                  ColoredBox(
                      color: pageColor,
                      child: RawImage(image: _turnCover, fit: BoxFit.fill)),
                if (_turnImage != null)
                  _buildTurningPage(_turnImage!, pageColor),
              ]),
            ),
          ),
        // iOS paginated mode: visible previous/next buttons. Swipe-to-turn goes
        // through the web view's touch events, which are not reliable on iOS;
        // these turn the page through the book's own prev()/next() so turning
        // pages always works.
        if (Platform.isIOS && !_isScrollMode && _isEpubReady) ...[
          Positioned(
            left: 4,
            top: 0,
            bottom: 0,
            child: Center(
                child: _pageTurnButton(
                    icon: Icons.chevron_left,
                    isDark: isDark,
                    tooltip: 'Previous page',
                    onTap: () => _turnPage(forward: false))),
          ),
          Positioned(
            right: 4,
            top: 0,
            bottom: 0,
            child: Center(
                child: _pageTurnButton(
                    icon: Icons.chevron_right,
                    isDark: isDark,
                    tooltip: 'Next page',
                    onTap: () => _turnPage(forward: true))),
          ),
        ],
        if (_isEpubReady && _pageBrightness < 1)
          Positioned.fill(
              child: IgnorePointer(
                  child: ColoredBox(
                      color: Colors.black
                          .withValues(alpha: 1 - _pageBrightness)))),
        if (_isEpubReady && _lineGuide)
          Positioned.fill(
              child: EpubLineGuide(
                  controller: _guide,
                  dimming: _guideDimming,
                  accentColor: _readerAccent,
                  bandHeight: _guideBandHeight,
                  stepHeight: _guidePitch == null
                      ? null
                      : _guideLines * _guidePitch!,
                  dark: isDark,
                  showHint: _guideHint)),
        if (_isEpubReady && _menu != null)
          _buildMenu(_menu!, constraints.biggest, isDark),
        if (!_isEpubReady)
          Container(
              color: pageColor,
              child: Center(
                  child: CircularProgressIndicator(color: _readerAccent))),
      ]);
    });
  }

  /// The page that moves during a turn. [_turnAnim] runs 0→1 for "next"
  /// (the old page leaves) and 1→0 for "previous" (the previous page comes
  /// back), so one drawing serves both directions.
  Widget _buildTurningPage(ui.Image image, Color pageColor) {
    final still = ColoredBox(
        color: pageColor, child: RawImage(image: image, fit: BoxFit.fill));
    switch (_turnStyle) {
      case EpubPageTurn.curl:
        return PageCurl(
            program: _curlProgram!,
            image: image,
            progress: _turnCurve,
            paperColor: _isDarkMode ? const Color(0xff121212) : Colors.white,
            backgroundColor: pageColor);
      case EpubPageTurn.fastFade:
        return AnimatedBuilder(
          animation: _turnAnim,
          builder: (context, child) =>
              Opacity(opacity: 1 - _turnAnim.value, child: child),
          child: still,
        );
      case EpubPageTurn.slide:
        return LayoutBuilder(
          builder: (context, constraints) => AnimatedBuilder(
            animation: _turnCurve,
            builder: (context, child) => Transform.translate(
              offset: Offset(-constraints.maxWidth * _turnCurve.value, 0),
              child: child,
            ),
            child: DecoratedBox(
              decoration: const BoxDecoration(boxShadow: [
                BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 18,
                    offset: Offset(6, 0)),
              ]),
              child: still,
            ),
          ),
        );
    }
  }

  /// Called on every layout of the book view. When its size changes after
  /// the book is shown (header hidden/shown, rotation), the book engine
  /// re-lays out its pages and can end up between pages (a blank page). Once
  /// the size has settled, re-display the current location to re-align.
  void _onBookViewSize(Size size) {
    final previous = _bookViewSize;
    _bookViewSize = size;
    if (previous == null || previous == size || !_isEpubReady) return;
    if (_wantsSpread(previous) != _wantsSpread(size)) {
      final spread = _wantsSpread(size);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_applySpread(spread));
      });
    }
    // A menu anchored to the old layout would point at the wrong text.
    if (_menu != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _menu != null) _clearSelection();
      });
    }
    _reanchorTimer?.cancel();
    _reanchorTimer = Timer(const Duration(milliseconds: 400), () {
      final cfi = _currentCfi;
      if (!mounted || cfi == null || cfi.isEmpty || _turning) return;
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
      final result = await _epubController.webViewController
          ?.evaluateJavascript(source: '''
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
              width: 36,
              height: 56,
              child: Icon(icon,
                  size: 26, color: isDark ? Colors.white70 : Colors.black54)),
        ),
      ),
    );
  }

  Widget _buildLoading(bool isTablet) {
    return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(
          value: _downloadProgress > 0 ? _downloadProgress : null),
      if (_downloadProgress > 0) ...[
        SizedBox(height: isTablet ? 21 : 16),
        Text('${(_downloadProgress * 100).toInt()}%',
            style: TextStyle(fontSize: isTablet ? 17 : 14, color: Colors.grey)),
      ],
    ]));
  }

  Widget _buildError(Color textColor, bool isTablet) {
    return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.error_outline, size: isTablet ? 64 : 48, color: Colors.grey),
      SizedBox(height: isTablet ? 21 : 16),
      Text(_error!,
          style: TextStyle(fontSize: isTablet ? 20 : 16, color: textColor)),
      SizedBox(height: isTablet ? 21 : 16),
      ElevatedButton(
          onPressed: () {
            setState(() {
              _error = null;
              _isLoading = true;
              _downloadProgress = 0;
              _isEpubReady = false;
              _dataLoaded = false;
              _annotations.clear();
              _standaloneNotes.clear();
              _bookmarkCfis.clear();
              _menu = null;
            });
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

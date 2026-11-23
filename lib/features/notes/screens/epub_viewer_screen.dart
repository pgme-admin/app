import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
import 'package:pgme/core/services/api_service.dart';
import 'package:pgme/core/services/storage_service.dart';
import 'package:pgme/core/constants/api_constants.dart';
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
import 'package:pgme/core/widgets/epub_markup_focus.dart';
import 'package:pgme/core/widgets/epub_page_curl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pgme/core/services/highlight_service.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/widgets/app_dialog.dart';

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
  // Touches on the book, seen by Flutter (a Listener over the web view).
  // The book page's own touch events do not reliably arrive from inside its
  // frame on iOS, so taps (images, tables, highlights, controls) and iOS
  // swipes are recognised here, then looked up in the page.
  int? _pointer;
  Offset? _pointerDown;
  DateTime? _pointerDownAt;
  bool _pointerMoved = false;
  bool _pointerMulti = false;
  bool _touchDownHadSelection = false;
  bool _hasSelection = false;

  // Book view size + pending re-align after a resize (see _onBookViewSize).
  Size? _bookViewSize;
  Timer? _reanchorTimer;
  // Where the reader was before the book view started changing size: the
  // page is re-anchored here, not on the start of the page as laid out at
  // an in-between size (that is earlier in the text, so every resize round
  // trip, e.g. search open/closed or controls hidden/shown, slid the
  // reader back a page). Kept across resizes; cleared when the reader
  // moves: a page turn, a jump, or scrolling (a relocation that is not
  // the re-layout after a resize).
  String? _layoutAnchor;
  DateTime _lastResizeAt = DateTime.fromMillisecondsSinceEpoch(0);
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
  final Map<String, DateTime> _bookmarkDates = {};
  List<EpubChapter> _chapters = [];
  // Bookmarks whose location is on the visible page (font changes move a
  // bookmark's location within the page, so it is matched by range).
  List<String> _pageBookmarkIds = const [];
  bool get _isCurrentLocationBookmarked => _pageBookmarkIds.isNotEmpty;
  bool _bookmarkBusy = false;

  // Page numbers (printed, fixed-layout or text-based), when the book has
  // them ready.
  EpubPageInfo? _pageInfo;

  // Highlights and underlines, keyed by EpubAnnotation.key, in the order
  // they were made.
  final Map<String, EpubAnnotation> _annotations = {};
  // Standalone notes (not attached to text), keyed by server id:
  // {'note': text, 'cfi': location or null (older notes)}.
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
    final saved = {
      for (final e in _bookmarkCfis.entries)
        if (!e.key.startsWith('__')) e.key: e.value
    };
    final places = {
      for (final p in await EpubReaderBridge.describe(
          _epubController, saved.values.toSet().toList()))
        p.cfi: p
    };
    if (!mounted) return;
    final order = places.keys.toList();
    final entries = [
      for (final e in saved.entries)
        EpubBookmarkEntry(
          id: e.key,
          cfi: e.value,
          chapter: places[e.value]?.chapter ?? '',
          page: places[e.value]?.page,
          created: _bookmarkDates[e.key],
        )
    ]..sort((a, b) {
        final ia = order.indexOf(a.cfi), ib = order.indexOf(b.cfi);
        return (ia < 0 ? 1 << 30 : ia).compareTo(ib < 0 ? 1 << 30 : ib);
      });
    final target = await showEpubNavigationSheet(
      context,
      chapters: _chapters,
      bookmarks: entries,
      onDeleteBookmark: _deleteBookmark,
      currentChapter: _currentChapter,
    );
    if (mounted && target != null) _displayCfi(target);
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
      // Page numbers follow the screen's page size (rebuilt after a font
      // or layout change; ready shortly after opening). Scroll mode numbers
      // pages as the same screen would in page mode, as Apple Books does.
      final layoutKey = _pageLayoutKey;
      final prefs = await SharedPreferences.getInstance();
      final view = _bookViewSize;
      if (!mounted || cfi != _currentCfi) return;
      if (view != null && !view.isEmpty) {
        unawaited(EpubReaderBridge.paginate(_epubController, layoutKey,
            knownSize: prefs.getInt(_pageSizePrefKey(layoutKey)) ?? 0,
            savedCounts: prefs.getString(_pageCountsPrefKey(layoutKey)),
            width: view.width,
            height: view.height,
            spread: _isSpread));
      }
      final pages = await EpubReaderBridge.pageInfo(_epubController);
      if (!mounted || cfi != _currentCfi) return;
      final pagesChanged = pages?.current != _pageInfo?.current ||
          pages?.total != _pageInfo?.total ||
          pages?.mode != _pageInfo?.mode;
      if (_sectionPagesLeft != remaining ||
          (useProgress && _readProgress != progress) ||
          pagesChanged) {
        setState(() {
          _sectionPagesLeft = remaining;
          if (useProgress) _readProgress = progress;
          _pageInfo = pages;
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

  /// The layout page numbers are counted for: text size, font, spacing,
  /// bold, spread and book view size. The book view size never includes a
  /// keyboard (see build).
  String get _pageLayoutKey {
    final view = _bookViewSize;
    return [
      _fontSize,
      _readingFont.name,
      _lineSpacing.name,
      _boldText,
      _isSpread,
      view?.width.round(),
      view?.height.round(),
    ].join('|');
  }

  /// Where the measured page size of this book in [layoutKey] is kept, so
  /// page numbers are the same every time the book is opened.
  String _pageSizePrefKey(String layoutKey) => 'epub_page_size_'
      '${_bookmarkKey('${widget.documentId ?? widget.epubUrl ?? ''}|$layoutKey')}';

  /// Where the exact page count of each chapter in [layoutKey] is kept.
  String _pageCountsPrefKey(String layoutKey) => 'epub_page_counts_'
      '${_bookmarkKey('${widget.documentId ?? widget.epubUrl ?? ''}|$layoutKey')}';

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
    final line =
        await EpubReaderBridge.lineAt(_epubController, x, y, scan: scan);
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
      await EpubReaderBridge.install(_epubController, dark: _isDarkMode,
          onTurnRequest: (forward) {
        if (mounted && generation == _viewerGeneration) {
          unawaited(_turnPage(forward: forward));
        }
      }, onPagesReady: (key, size, measured, counts) {
        if (key != null && ((size > 0 && measured) || counts != null)) {
          unawaited(SharedPreferences.getInstance().then((prefs) async {
            if (size > 0 && measured) {
              await prefs.setInt(_pageSizePrefKey(key), size);
            }
            if (counts != null) {
              await prefs.setString(_pageCountsPrefKey(key), counts);
            }
          }));
        }
        final cfi = _currentCfi;
        if (mounted && generation == _viewerGeneration && cfi != null) {
          unawaited(_refreshSectionPages(cfi));
        }
      });
      // The book's location index may be ready already (it is built while
      // the first page shows): number the pages now, without waiting for a
      // page turn.
      final cfi = _currentCfi;
      if (mounted && generation == _viewerGeneration && cfi != null) {
        unawaited(_refreshSectionPages(cfi));
      }
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
        final boundsData = h['bounds_data'] as List?;
        final cfi = (boundsData != null &&
                boundsData.isNotEmpty &&
                boundsData.first is Map)
            ? ((boundsData.first as Map)['text'] as String? ?? '')
            : '';
        if (type == 'note') {
          _standaloneNotes[id] = {
            'note': note ?? '',
            'cfi': cfi.startsWith('epubcfi(') ? cfi : null,
          };
          continue;
        }
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
        final id = b['bookmark_id'] as String?;
        final cfi = b['note'] as String? ?? '';
        if (id == null || !cfi.startsWith('epubcfi(')) continue;
        _bookmarkCfis[id] = cfi;
        final created = DateTime.tryParse('${b['created_at'] ?? ''}');
        if (created != null) _bookmarkDates[id] = created.toLocal();
      }
      unawaited(_updateBookmarkState());
    } catch (_) {}
  }

  // ── Bookmarks ─────────────────────────────────────────────────────

  /// Finds the bookmarks on the visible page. A bookmark keeps the exact
  /// location where it was made; after a font or layout change that
  /// location is somewhere inside a page, so it is matched by range.
  Future<void> _updateBookmarkState() async {
    final cfi = _currentCfi;
    if (cfi == null || _bookmarkCfis.isEmpty) {
      if (_pageBookmarkIds.isNotEmpty && mounted) {
        setState(() => _pageBookmarkIds = const []);
      }
      return;
    }
    final entries = Map<String, String>.of(_bookmarkCfis);
    final onScreen = await EpubReaderBridge.onScreen(
        _epubController, entries.values.toList());
    if (!mounted || cfi != _currentCfi) return;
    final ids = [
      for (final e in entries.entries)
        if (onScreen.contains(e.value) || e.value == cfi) e.key
    ];
    if (ids.length != _pageBookmarkIds.length ||
        !ids.every(_pageBookmarkIds.contains)) {
      setState(() => _pageBookmarkIds = ids);
    }
  }

  /// A stable number for a location: the backend keys a document's
  /// bookmarks by page number, and an EPUB has no fixed pages.
  static int _bookmarkKey(String cfi) {
    var hash = 0x811c9dc5;
    for (final unit in cfi.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 1000000 + hash % 1000000000;
  }

  Future<void> _toggleBookmark() async {
    final cfi = _currentCfi;
    if (widget.documentId == null || cfi == null || _bookmarkBusy) return;
    _bookmarkBusy = true;
    unawaited(HapticFeedback.selectionClick());
    try {
      if (_pageBookmarkIds.isNotEmpty) {
        // Remove every bookmark on this page.
        final removed = {
          for (final id in _pageBookmarkIds)
            if (_bookmarkCfis[id] != null) id: _bookmarkCfis[id]!
        };
        setState(() {
          _bookmarkCfis.removeWhere((id, _) => removed.containsKey(id));
          _pageBookmarkIds = const [];
        });
        for (final entry in removed.entries) {
          try {
            await _bookmarkService.deleteBookmark(entry.key);
          } catch (_) {
            if (!mounted) return;
            setState(() => _bookmarkCfis[entry.key] = entry.value);
            _showSnack('Bookmark not removed. Check your connection.');
          }
        }
        await _updateBookmarkState();
        return;
      }
      // Optimistic: the ribbon shows at once, the save follows.
      const pending = '__pending__';
      setState(() {
        _bookmarkCfis[pending] = cfi;
        _pageBookmarkIds = const [pending];
      });
      try {
        final result = await _bookmarkService.addBookmark(
          documentId: widget.documentId!,
          pageNumber: _bookmarkKey(cfi),
          note: cfi,
        );
        if (!mounted) return;
        final id = result['bookmark_id'] as String?;
        setState(() {
          _bookmarkCfis.remove(pending);
          if (id != null) {
            _bookmarkCfis[id] = cfi;
            _bookmarkDates[id] = DateTime.now();
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _bookmarkCfis.remove(pending));
        final message = e.toString().replaceFirst('Exception: ', '').trim();
        if (message.toLowerCase().contains('already exists')) {
          // Saved earlier (another device): reload so it can be removed.
          await _reloadBookmarks();
        } else {
          _showSnack('Bookmark not saved. Check your connection.');
        }
      }
      await _updateBookmarkState();
    } finally {
      _bookmarkBusy = false;
    }
  }

  Future<void> _reloadBookmarks() async {
    if (widget.documentId == null) return;
    try {
      final bookmarks = await _bookmarkService.getBookmarks(widget.documentId!);
      if (!mounted) return;
      setState(() {
        _bookmarkCfis.clear();
        for (final b in bookmarks) {
          final id = b['bookmark_id'] as String?;
          final cfi = b['note'] as String? ?? '';
          if (id == null || !cfi.startsWith('epubcfi(')) continue;
          _bookmarkCfis[id] = cfi;
          final created = DateTime.tryParse('${b['created_at'] ?? ''}');
          if (created != null) _bookmarkDates[id] = created.toLocal();
        }
      });
    } catch (_) {}
  }

  Future<void> _deleteBookmark(String id) async {
    final cfi = _bookmarkCfis[id];
    if (cfi == null) return;
    setState(() => _bookmarkCfis.remove(id));
    unawaited(_updateBookmarkState());
    try {
      await _bookmarkService.deleteBookmark(id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _bookmarkCfis[id] = cfi);
      unawaited(_updateBookmarkState());
      _showSnack('Bookmark not removed. Check your connection.');
    }
  }

  // ── Highlights, underlines and notes ─────────────────────────────

  void _drawAnnotation(EpubAnnotation a) {
    unawaited(EpubReaderBridge.addAnnotation(_epubController,
        cfi: a.cfi, type: a.type, color: a.color, hasNote: a.hasNote));
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
  /// bottom bar). Text that is already highlighted is never covered twice:
  /// the new mark joins the ones it overlaps (or recolours the highlight it
  /// lies inside), as in Apple Books.
  Future<EpubAnnotation?> _annotateSelection(
      {required String type, String color = 'yellow'}) async {
    final cfi = _selectedCfi;
    final text = _selectedText ?? '';
    if (cfi == null || cfi.isEmpty) {
      _showSnack('Select text first: touch and hold a word, then drag.');
      return null;
    }
    _clearSelection();
    unawaited(HapticFeedback.selectionClick());
    return _addMerged(cfi: cfi, type: type, color: color, text: text);
  }

  Future<EpubAnnotation> _addMerged({
    required String cfi,
    required String type,
    String color = 'yellow',
    String text = '',
  }) async {
    final exact = _annotations[EpubAnnotation.keyFor(type, cfi)];
    if (exact != null) {
      if (exact.isHighlight) _setHighlightColor(exact, color);
      return exact;
    }
    final overlap =
        await EpubReaderBridge.overlaps(_epubController, cfi: cfi, type: type);
    final covered = [
      for (final c in overlap?.cfis ?? const <String>[])
        if (_annotations[EpubAnnotation.keyFor(type, c)] != null)
          _annotations[EpubAnnotation.keyFor(type, c)]!
    ];
    if (!mounted || overlap == null || covered.isEmpty) {
      return _addAnnotation(cfi: cfi, type: type, color: color, text: text);
    }
    // Inside one existing mark: change its colour, add nothing.
    if (covered.length == 1 && overlap.union == covered.first.cfi) {
      if (covered.first.isHighlight) _setHighlightColor(covered.first, color);
      return covered.first;
    }
    final notes = [
      for (final a in covered)
        if (a.hasNote) a.note!.trim()
    ];
    _removeAnnotations(covered, offerUndo: false);
    final merged = _addAnnotation(
      cfi: overlap.union,
      type: type,
      color: color,
      text: overlap.text.trim().isNotEmpty ? overlap.text : text,
      note: notes.isEmpty ? null : _fitNote(notes.join('\n\n')),
    );
    merged.replaced = covered;
    return merged;
  }

  EpubAnnotation _addAnnotation({
    required String cfi,
    required String type,
    String color = 'yellow',
    String text = '',
    String? note,
    bool recordUndo = true,
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
      if (recordUndo) {
        _undoStack
          ..remove(key)
          ..add(key);
      }
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
        onNote: () async {
          final a = await _annotateSelection(type: 'highlight');
          if (a != null && mounted) _editNote(a);
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

  void _editNote(EpubAnnotation a, {VoidCallback? onSaved}) {
    _showNoteEditor(
      title: (a.note ?? '').isEmpty ? 'Add Note' : 'Edit Note',
      quote: a.text,
      initial: a.note ?? '',
      allowEmpty: true,
      onSave: (text) {
        // Removed while the editor was open (Undo, Notes panel): drawing it
        // again would leave a mark on the page that no longer exists.
        if (!mounted || a.removed) return;
        final note = text.trim().isEmpty ? null : _fitNote(text.trim());
        if (note == a.note) return;
        setState(() => a.note = note);
        onSaved?.call();
        // Shows (or hides) the note dot after the marked text.
        _drawAnnotation(a);
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

  /// The backend keeps notes up to 500 characters.
  static String _fitNote(String note) =>
      note.length <= 500 ? note : '${note.substring(0, 499)}…';

  void _deleteStandaloneNote(String id, {bool offerUndo = true}) {
    final removed = _standaloneNotes[id];
    if (removed == null) return;
    setState(() {
      _standaloneNotes.remove(id);
      _undoStack.remove(id);
    });
    _highlightService.deleteHighlight(id).catchError((_) {});
    if (!offerUndo) return;
    _showSnack('Note deleted',
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _saveStandaloneNote(removed['note'] as String? ?? '',
              cfi: removed['cfi'] as String?),
        ));
  }

  /// Undoes the most recent highlight, underline or note (like the PDF
  /// reader's Undo).
  void _undoLast([StateSetter? setSheetState]) {
    while (_undoStack.isNotEmpty) {
      final id = _undoStack.removeLast();
      final a = _annotations[id];
      if (a != null) {
        _removeAnnotations([a], offerUndo: false);
        // A merged mark gives back the marks it joined.
        for (final old in a.replaced) {
          _addAnnotation(
              cfi: old.cfi,
              type: old.type,
              color: old.color,
              text: old.text,
              note: old.note,
              recordUndo: false);
        }
        _showSnack(a.isHighlight ? 'Highlight undone' : 'Underline undone');
        break;
      }
      if (_standaloneNotes.containsKey(id)) {
        _deleteStandaloneNote(id, offerUndo: false);
        _showSnack('Note undone');
        break;
      }
    }
    if (mounted) setState(() {});
    setSheetState?.call(() {});
  }

  // ── Notes panel ───────────────────────────────────────────────────

  /// Notes & Highlights: everything marked in this book, in book order and
  /// grouped by chapter, with page numbers. Tap an item to go there.
  Future<void> _showNotesPanel() async {
    _clearSelection();
    final places = <String, EpubPlace>{};
    final order = <String, int>{};
    Future<void> locate() async {
      final cfis = <String>{
        for (final a in _annotations.values) a.cfi,
        for (final n in _standaloneNotes.values)
          if (n['cfi'] is String) n['cfi'] as String,
      }.toList();
      final found = await EpubReaderBridge.describe(_epubController, cfis);
      places
        ..clear()
        ..addEntries(found.map((p) => MapEntry(p.cfi, p)));
      order
        ..clear()
        ..addEntries(found.indexed.map((e) => MapEntry(e.$2.cfi, e.$1)));
    }

    await locate();
    if (!mounted) return;
    final isDark = readingThemeIsDark(_readingTheme,
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode);
    final isTablet = ResponsiveHelper.isTablet(context);
    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1C1C1E);
    final mutedColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF6B6B70);
    final dividerColor =
        isDark ? AppColors.darkDivider : const Color(0xFFEDEDF0);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return StatefulBuilder(builder: (sheetContext, setSheetState) {
          void refresh() {
            locate().then((_) {
              if (sheetContext.mounted) setSheetState(() {});
            });
          }

          final items = _notesItems(places, order);
          // Chapter headers between groups.
          final rows = <Object>[];
          String? chapter;
          for (final item in items) {
            final label = item.cfi == null
                ? 'Other notes'
                : (item.chapter.isEmpty ? 'This book' : item.chapter);
            if (label != chapter) {
              rows.add(label);
              chapter = label;
            }
            rows.add(item);
          }
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.35,
            maxChildSize: 0.92,
            expand: false,
            builder: (context, scrollController) {
              return Column(children: [
                Center(
                    child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(top: 10, bottom: 14),
                        decoration: BoxDecoration(
                            color: isDark ? Colors.white24 : Colors.black12,
                            borderRadius: BorderRadius.circular(2)))),
                Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: isTablet ? 24 : 20),
                    child: Row(children: [
                      Text('Notes & Highlights',
                          style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontWeight: FontWeight.w700,
                              fontSize: 19,
                              color: textColor)),
                      if (items.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text('${items.length}',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: mutedColor)),
                      ],
                      const Spacer(),
                      if (_undoStack.isNotEmpty) ...[
                        _headerButton('Undo', Icons.undo, AppColors.error, () {
                          _undoLast(setSheetState);
                          refresh();
                        }),
                        const SizedBox(width: 8),
                      ],
                      _headerButton('Note', Icons.add, _readerAccent,
                          () => _addPageNote(onSaved: refresh)),
                    ])),
                const SizedBox(height: 12),
                Divider(height: 1, color: dividerColor),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 36),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.edit_note_rounded,
                                size: 44, color: mutedColor),
                            const SizedBox(height: 10),
                            Text('No highlights or notes yet',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: textColor)),
                            const SizedBox(height: 6),
                            Text(
                                'Touch and hold text to highlight it, or tap '
                                'Note to write one for this page.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.4,
                                    color: mutedColor)),
                          ]),
                        ))
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: rows.length,
                          itemBuilder: (_, index) {
                            final row = rows[index];
                            if (row is String) {
                              return Padding(
                                padding: EdgeInsets.fromLTRB(
                                    isTablet ? 24 : 20, 18, 20, 6),
                                child: Text(row.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.6,
                                        color: mutedColor)),
                              );
                            }
                            return _notesRow(row as _NotesItem,
                                isDark: isDark,
                                textColor: textColor,
                                mutedColor: mutedColor,
                                sheetContext: sheetContext, onChanged: () {
                              setSheetState(() {});
                              refresh();
                            });
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

  List<_NotesItem> _notesItems(
      Map<String, EpubPlace> places, Map<String, int> order) {
    const unknown = 1 << 30;
    final items = <_NotesItem>[
      for (final a in _annotations.values)
        _NotesItem(
          annotation: a,
          cfi: a.cfi,
          chapter: places[a.cfi]?.chapter ?? '',
          page: places[a.cfi]?.page,
          order: order[a.cfi] ?? unknown,
        ),
      for (final e in _standaloneNotes.entries)
        _NotesItem(
          noteId: e.key,
          note: e.value['note'] as String? ?? '',
          cfi: e.value['cfi'] as String?,
          chapter: places[e.value['cfi']]?.chapter ?? '',
          page: places[e.value['cfi']]?.page,
          order: e.value['cfi'] == null
              ? unknown * 2
              : (order[e.value['cfi']] ?? unknown),
        ),
    ];
    items.sort((a, b) => a.order.compareTo(b.order));
    return items;
  }

  Widget _notesRow(
    _NotesItem item, {
    required bool isDark,
    required Color textColor,
    required Color mutedColor,
    required BuildContext sheetContext,
    required VoidCallback onChanged,
  }) {
    final a = item.annotation;
    final ink = isDark ? const Color(0xFF8ABFFF) : const Color(0xFF1565C0);
    final color = a == null
        ? _readerAccent
        : a.isHighlight
            ? epubHighlightColors[a.color] ?? epubHighlightColors['yellow']!
            : ink;
    final quote = a?.text.trim() ?? '';
    final note = (a != null ? a.note ?? '' : item.note).trim();
    final kind = a == null
        ? 'Note'
        : '${a.isHighlight ? 'Highlight' : 'Underline'}${a.hasNote ? ' · Note' : ''}';
    final meta = [if (item.page != null) 'Page ${item.page}', kind].join(' · ');

    void open() {
      final cfi = item.cfi;
      if (cfi == null) return;
      Navigator.pop(sheetContext);
      _displayCfi(cfi);
    }

    Future<void> delete() async {
      if (note.isNotEmpty) {
        final ok = await _confirm(
          title: a == null ? 'Delete this note?' : 'Delete highlight and note?',
          message: 'This cannot be undone.',
          action: 'Delete',
        );
        if (ok != true) return;
      }
      if (a != null) {
        _removeAnnotations([a], offerUndo: note.isEmpty);
      } else if (item.noteId != null) {
        _deleteStandaloneNote(item.noteId!, offerUndo: false);
      }
      onChanged();
    }

    void edit() {
      if (a != null) {
        _editNote(a, onSaved: onChanged);
      } else if (item.noteId != null) {
        _editStandaloneNote(item.noteId!, onSaved: onChanged);
      }
    }

    return InkWell(
      onTap: item.cfi == null ? edit : open,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 6, 10),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
                width: 4,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (quote.isNotEmpty)
                    Text(quote,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.38,
                            color: textColor.withValues(alpha: 0.88),
                            fontStyle: FontStyle.italic)),
                  if (note.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: quote.isEmpty ? 0 : 6),
                      child: Text(note,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              height: 1.38,
                              fontWeight: FontWeight.w500,
                              color: textColor)),
                    ),
                  const SizedBox(height: 6),
                  Text(meta,
                      style: TextStyle(fontSize: 11.5, color: mutedColor)),
                ],
              ),
            ),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                tooltip: note.isEmpty ? 'Add note' : 'Edit note',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                    note.isEmpty
                        ? Icons.note_add_outlined
                        : Icons.edit_note_rounded,
                    size: 21,
                    color: _readerAccent),
                onPressed: edit,
              ),
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline,
                    size: 20, color: AppColors.error.withValues(alpha: 0.8)),
                onPressed: delete,
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _headerButton(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      ),
    );
  }

  Future<bool?> _confirm(
      {required String title,
      required String message,
      required String action}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action,
                  style: const TextStyle(
                      color: AppColors.error, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  /// A note for the current page (not attached to selected text).
  Future<void> _addPageNote({VoidCallback? onSaved}) async {
    final cfi = _currentCfi;
    String? where;
    if (cfi != null) {
      final place =
          (await EpubReaderBridge.describe(_epubController, [cfi])).firstOrNull;
      if (!mounted) return;
      where = [
        if (place?.page != null) 'Page ${place!.page}',
        if ((place?.chapter ?? '').isNotEmpty) place!.chapter,
      ].join(' · ');
    }
    _showNoteEditor(
      title: 'New Note',
      subtitle: (where ?? '').isEmpty ? null : where,
      onSave: (note) async {
        await _saveStandaloneNote(note, cfi: cfi);
        onSaved?.call();
      },
    );
  }

  void _editStandaloneNote(String id, {VoidCallback? onSaved}) {
    final current = _standaloneNotes[id];
    if (current == null) return;
    _showNoteEditor(
      title: 'Edit Note',
      initial: current['note'] as String? ?? '',
      allowEmpty: true,
      onSave: (text) async {
        final note = text.trim();
        if (note.isEmpty) {
          _deleteStandaloneNote(id);
          onSaved?.call();
          return;
        }
        setState(() => current['note'] = note);
        onSaved?.call();
        try {
          await _highlightService.updateHighlightNote(id, note);
        } catch (e) {
          debugPrint('[EPUB] note not saved: $e');
          _showSnack('Note not saved. Check your connection.');
        }
      },
    );
  }

  /// Note editor sheet, shared by page notes and notes on highlights:
  /// Cancel / title / Save, as in Apple's apps. Unsaved text is never lost
  /// silently; an existing note can be deleted here.
  void _showNoteEditor({
    required String title,
    required ValueChanged<String> onSave,
    String initial = '',
    String quote = '',
    String? subtitle,
    bool allowEmpty = false,
  }) {
    final isDark = readingThemeIsDark(_readingTheme,
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode);
    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1C1C1E);
    final mutedColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF6B6B70);
    final noteCtrl = TextEditingController(text: initial);
    final original = initial.trim();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setEditor) {
        final value = noteCtrl.text.trim();
        final dirty = value != original;
        final canSave =
            dirty && (value.isNotEmpty || (allowEmpty && original.isNotEmpty));

        Future<void> close() async {
          if (dirty && value.isNotEmpty) {
            final discard = await showDialog<bool>(
              context: ctx,
              builder: (d) => AlertDialog(
                title: const Text('Discard changes?'),
                content: const Text('Your note has not been saved.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: const Text('Keep Editing')),
                  TextButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: const Text('Discard',
                          style: TextStyle(color: AppColors.error))),
                ],
              ),
            );
            if (discard != true) return;
          }
          if (ctx.mounted) Navigator.pop(ctx);
        }

        void save() {
          if (!canSave) return;
          Navigator.pop(ctx);
          onSave(value);
        }

        return PopScope(
          canPop: !dirty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) close();
          },
          child: Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(children: [
                      TextButton(
                          onPressed: close,
                          child: Text('Cancel',
                              style:
                                  TextStyle(fontSize: 16, color: mutedColor))),
                      Expanded(
                          child: Text(title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily: 'SF Pro Display',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 17,
                                  color: textColor))),
                      TextButton(
                          onPressed: canSave ? save : null,
                          child: Text('Save',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: canSave
                                      ? _readerAccent
                                      : mutedColor.withValues(alpha: 0.5)))),
                    ]),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: mutedColor)),
                    ),
                  if (quote.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.only(left: 10),
                        decoration: BoxDecoration(
                            border: Border(
                                left: BorderSide(
                                    color: _readerAccent, width: 3))),
                        child: Text(quote.trim(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.5,
                                height: 1.35,
                                fontStyle: FontStyle.italic,
                                color: mutedColor)),
                      ),
                    ),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: TextField(
                          controller: noteCtrl,
                          minLines: 4,
                          maxLines: 8,
                          maxLength: 500,
                          autofocus: true,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setEditor(() {}),
                          style: TextStyle(
                              color: textColor, fontSize: 15, height: 1.45),
                          decoration: InputDecoration(
                              hintText: 'Write your note…',
                              hintStyle: TextStyle(
                                  color: mutedColor.withValues(alpha: 0.7)),
                              filled: true,
                              fillColor: isDark
                                  ? AppColors.darkSurface
                                  : const Color(0xFFF6F6F8),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                      color: _readerAccent, width: 1.5))))),
                  if (allowEmpty && original.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            onSave('');
                          },
                          icon: const Icon(Icons.delete_outline,
                              size: 18, color: AppColors.error),
                          label: const Text('Delete Note',
                              style: TextStyle(color: AppColors.error)),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      }),
    ).whenComplete(() {
      // Disposed after the sheet's closing animation.
      Future<void>.delayed(const Duration(milliseconds: 400), noteCtrl.dispose);
    });
  }

  Future<void> _saveStandaloneNote(String note, {String? cfi}) async {
    if (widget.documentId == null || note.trim().isEmpty) return;
    try {
      final result = await _highlightService.addHighlight(
        documentId: widget.documentId!,
        pageNumber: 1,
        startOffset: 0,
        endOffset: 0,
        highlightedText: '',
        color: 'yellow',
        annotationType: 'note',
        note: _fitNote(note.trim()),
        boundsData: cfi == null
            ? null
            : [
                {
                  'left': 0,
                  'top': 0,
                  'width': 0,
                  'height': 0,
                  'text': cfi,
                  'page_number': 1
                }
              ],
      );
      final id = result['highlight_id'] as String?;
      if (id == null || !mounted) return;
      setState(() {
        _standaloneNotes[id] = {'note': _fitNote(note.trim()), 'cfi': cfi};
        _undoStack.add(id);
      });
    } catch (_) {
      _showSnack('Note not saved. Check your connection.');
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
    final pageColor = epubPageColor(_readingTheme, themeProvider.isDarkMode);
    // The reader's layout must not change while a keyboard is up (note
    // editor, search, go to page). Flutter drops the bottom safe-area
    // padding while the keyboard shows, which made the bottom bar shorter
    // and the book view taller by that inset, then shorter again frame by
    // frame as the keyboard closed: the book re-laid out at every step and
    // ended on another page, with its page numbers rebuilt.
    final steadyMedia = readerMediaWithoutKeyboard(MediaQuery.of(context));

    return PopScope(
      // Back first dismisses the selection/annotation menu.
      canPop: _menu == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _menu != null) _clearSelection();
      },
      child: MediaQuery(
        data: steadyMedia,
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
                          // Tap the page number (or percentage) to jump.
                          GestureDetector(
                            onTap: _showGoToDialog,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                    color: _readerAccent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Text(_positionChipLabel,
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
                    inset: steadyMedia.padding.top,
                    isDark: isDark),
            // The reading area is the page colour from the first frame
            // (download, loading), so the page never shows another colour.
            Expanded(
                child: ColoredBox(
                    color: pageColor,
                    child: _error != null
                        ? _buildError(textColor, isTablet)
                        : _isLoading
                            ? _buildLoading(isTablet)
                            : _buildEpubViewer(isDark, pageColor))),
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
                    text: !_isEpubReady ? '' : _immersivePositionText,
                    inset: steadyMedia.padding.bottom,
                    isDark: isDark),
          ]),
        ),
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
            top: top ? inset : 0, bottom: top ? 0 : inset, left: 48, right: 48),
        child: Center(child: label),
      ),
    );
  }

  // ── Page navigation + go-to-location ──────────────────────────────

  /// Navigation inside the book. The book refuses to move while text is
  /// selected, so the selection is cleared first. [flash] briefly marks the
  /// text at the target (search results).
  void _displayCfi(String cfi, {bool flash = false}) {
    if (cfi.isEmpty) return;
    _layoutAnchor = null;
    if (_hasSelection || _menu != null) _clearSelection();
    unawaited(
        EpubReaderBridge.goTo(_epubController, cfi, flash: flash).then((ok) {
      if (!ok && mounted) _epubController.display(cfi: cfi);
    }));
  }

  // ── Touches on the book ───────────────────────────────────────────
  //
  // Seen by a Listener over the web view (not the book page's own touch
  // events, which do not reliably arrive from inside its frame on iOS).
  // The web view still gets every touch for text selection and scrolling.

  static const _tapSlop = 12.0;

  void _onPointerDown(PointerDownEvent e) {
    if (_pointer != null) {
      // A second finger: a pinch or two-finger gesture, never a tap.
      _pointerMulti = true;
      return;
    }
    _pointer = e.pointer;
    _pointerDown = e.localPosition;
    _pointerDownAt = DateTime.now();
    _pointerMoved = false;
    _pointerMulti = false;
    _touchDownHadSelection = _hasSelection;
  }

  void _onPointerMove(PointerMoveEvent e) {
    final down = _pointerDown;
    if (e.pointer != _pointer || down == null) return;
    if ((e.localPosition - down).distance > _tapSlop) _pointerMoved = true;
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer == _pointer) _pointer = null;
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    final down = _pointerDown;
    final at = _pointerDownAt;
    final multi = _pointerMulti;
    _pointer = null;
    final size = _bookViewSize;
    if (down == null ||
        at == null ||
        multi ||
        size == null ||
        size.isEmpty ||
        !_isEpubReady ||
        _imageFocused ||
        _turning) {
      return;
    }
    final hadSelection = _touchDownHadSelection || _hasSelection;
    final delta = e.localPosition - down;
    final heldMs = DateTime.now().difference(at).inMilliseconds;
    final x = (e.localPosition.dx / size.width).clamp(0.0, 1.0);
    final y = (e.localPosition.dy / size.height).clamp(0.0, 1.0);

    // A quick, stationary touch is a tap. (Touch and hold selects text.)
    if (!_pointerMoved && delta.distance <= _tapSlop && heldMs < 450) {
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

    // iOS only: a horizontal flick turns the page in paginated mode. On
    // Android the book page detects swipes itself and asks for the turn
    // (EpubReaderBridge), so doing it here too would turn two pages.
    if (Platform.isIOS &&
        !_isScrollMode &&
        heldMs < 700 &&
        delta.dx.abs() >= math.max(40.0, size.width * 0.12) &&
        delta.dx.abs() > delta.dy.abs() * 1.5) {
      unawaited(_turnPage(forward: delta.dx < 0));
    }
  }

  /// Tap on the book: open an image, table or figure; the menu (or note)
  /// of a highlight; follow a link (the book does that); turn the page at
  /// the left/right edge; or show/hide the reader controls.
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
        return;
      case 'table':
      case 'figure':
        await _openFocusMarkup(target);
        return;
      case 'annotation':
        if (target.noteTap) {
          final withNote = [
            for (final hit in target.annotations)
              if (_annotations[EpubAnnotation.keyFor(hit.type, hit.cfi)]
                      ?.hasNote ??
                  false)
                _annotations[EpubAnnotation.keyFor(hit.type, hit.cfi)]!
          ];
          if (withNote.isNotEmpty) {
            _editNote(withNote.first);
            return;
          }
        }
        _showAnnotationMenu(target);
        return;
      case 'link':
        return;
    }
    // Line guide on: a tap outside the reading window moves it to the
    // tapped line (Apple Books-style).
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
    // Paginated: the outer edges turn the page, as in Apple Books.
    if (!_isScrollMode && (x < 0.12 || x > 0.88)) {
      if (_menu != null) setState(() => _menu = null);
      unawaited(_turnPage(forward: x > 0.5));
      return;
    }
    setState(() {
      _menu = null;
      _chromeVisible = !_chromeVisible;
    });
  }

  /// A table or figure, enlarged on its own (pinch to zoom, scroll), as in
  /// Apple Books.
  Future<void> _openFocusMarkup(EpubTapTarget target) async {
    _imageFocused = true;
    try {
      final markup = await EpubReaderBridge.focusMarkup(_epubController);
      if (!mounted) return;
      if (markup == null) {
        _showSnack(target.kind == 'table'
            ? 'This table could not be opened.'
            : 'This figure could not be opened.');
        return;
      }
      final isDark = readingThemeIsDark(_readingTheme,
          Provider.of<ThemeProvider>(context, listen: false).isDarkMode);
      await showEpubMarkupFocus(
        context,
        markup: markup,
        origin: _globalRect(target.rect),
        dark: isDark,
        title: (target.label ?? '').trim().isNotEmpty
            ? target.label!.trim()
            : (target.kind == 'table' ? 'Table' : 'Figure'),
      );
    } finally {
      _imageFocused = false;
    }
  }

  /// Screen rectangle of a normalized rectangle in the book view.
  Rect _globalRect(Rect? r) {
    final screen = MediaQuery.sizeOf(context);
    final fallback = Rect.fromCenter(
        center: screen.center(Offset.zero), width: 48, height: 48);
    final box = _bookKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || r == null) return fallback;
    final size = box.size;
    final o = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(o.dx + r.left * size.width, o.dy + r.top * size.height,
        r.width * size.width, r.height * size.height);
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
      final origin = _globalRect(target.rect);
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
    _layoutAnchor = null;
    final generation = _viewerGeneration;
    final startCfi = _currentCfi;
    // Curl turns one sheet; in a two-page spread both pages would bend as
    // one, so spreads slide instead.
    final style =
        _pageTurn == EpubPageTurn.curl && (_curlProgram == null || _isSpread)
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

  /// "12 / 340" when the book has page numbers, otherwise "37%".
  String get _positionChipLabel {
    final pages = _pageInfo;
    if (pages != null && pages.current != null) {
      return '${pages.current} / ${pages.total}';
    }
    return '${(_readProgress * 100).toInt()}%';
  }

  /// Bottom line while the controls are hidden: page, then what is left of
  /// the chapter.
  String get _immersivePositionText {
    final pages = _pageInfo;
    final parts = <String>[
      if (pages != null && pages.current != null)
        'Page ${pages.current} of ${pages.total}'
      else
        '${(_readProgress * 100).toInt()}%',
      if (!_isScrollMode && _sectionPagesLeft != null)
        _sectionPagesLeft == 0
            ? 'Last page in chapter'
            : '${_sectionPagesLeft!} ${_sectionPagesLeft == 1 ? 'page' : 'pages'} left in chapter',
    ];
    return parts.join(' · ');
  }

  /// Go to a page (or, before the book's page numbers are ready, to a
  /// percentage of the book).
  Future<void> _showGoToDialog() async {
    if (!_isEpubReady) return;
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final pages = _pageInfo;
    final value = await showDialog<int>(
      context: context,
      builder: (_) => pages != null
          ? _GoToLocationDialog(
              title: 'Go to page',
              label: 'Page (1–${pages.total})',
              min: 1,
              max: pages.total,
              initial: pages.current ?? 1,
              isDark: isDark,
            )
          : _GoToLocationDialog(
              title: 'Go to location',
              label: 'Percentage of the book',
              suffix: '%',
              min: 0,
              max: 100,
              initial: (_readProgress * 100).round().clamp(0, 100),
              isDark: isDark,
            ),
    );
    if (value == null || !mounted) return;
    // Let the dialog and the keyboard finish closing first. Hiding the keyboard
    // resizes the web view, and epub.js responds to a resize by re-displaying
    // its previous location, which would undo a jump made at the same moment.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    if (pages != null) {
      await _jumpToPage(value);
    } else {
      await _jumpToProgress((value / 100).clamp(0.0, 1.0));
    }
  }

  Future<void> _jumpToPage(int page) async {
    if (_hasSelection || _menu != null) _clearSelection();
    _layoutAnchor = null;
    final shown = await EpubReaderBridge.goToPage(_epubController, page);
    if (!mounted || shown) return;
    _showSnack('Page $page could not be found in this book.');
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
                    hintText: _pageInfo != null
                        ? 'Search the book or enter a page number'
                        : 'Search in book...',
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
                textInputAction: TextInputAction.search,
                onSubmitted: (value) async {
                  if (value.trim().isNotEmpty &&
                      _isEpubReady &&
                      !_isSearchBusy) {
                    _isSearchBusy = true;
                    try {
                      // A number can be a page to go to (offered first, as
                      // in Apple Books) as well as text to find.
                      final asPage = int.tryParse(value.trim());
                      final pages = _pageInfo;
                      final page = asPage != null &&
                              pages != null &&
                              asPage >= 1 &&
                              asPage <= pages.total
                          ? asPage
                          : null;
                      final results =
                          await searchEpubBook(_epubController, value);
                      if (!mounted) return;
                      final choice = await showEpubSearchResults(
                          context, results,
                          page: page, totalPages: pages?.total, query: value);
                      if (!mounted || choice == null) return;
                      FocusManager.instance.primaryFocus?.unfocus();
                      if (choice.page != null) {
                        // Let the keyboard close first (it resizes the book).
                        await Future<void>.delayed(
                            const Duration(milliseconds: 350));
                        if (mounted) await _jumpToPage(choice.page!);
                      } else if (choice.cfi != null) {
                        await Future<void>.delayed(
                            const Duration(milliseconds: 350));
                        if (mounted) _displayCfi(choice.cfi!, flash: true);
                      }
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

  Widget _buildEpubViewer(bool isDark, Color pageColor) {
    final epubSource = _localPath != null
        ? EpubSource.fromFile(File(_localPath!))
        : EpubSource.fromUrl(widget.epubUrl!);
    final generation = _viewerGeneration;

    return LayoutBuilder(builder: (context, constraints) {
      _onBookViewSize(constraints.biggest);
      return Stack(key: _bookKey, children: [
        Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: EpubViewer(
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
            // The book's own location index is ready: page numbers can be
            // counted now (they used to wait for the first page turn).
            onLocationLoaded: () {
              final cfi = _currentCfi;
              if (!mounted || generation != _viewerGeneration || cfi == null) {
                return;
              }
              unawaited(_refreshSectionPages(cfi));
            },
            onRelocated: (value) {
              if (generation != _viewerGeneration) return;
              final pendingTurn = _turnRelocated;
              if (pendingTurn != null && !pendingTurn.isCompleted) {
                pendingTurn.complete(value.startCfi);
              }
              if (mounted) {
                // Not the re-layout after a resize: the reader moved.
                if (!(_reanchorTimer?.isActive ?? false) &&
                    DateTime.now().difference(_lastResizeAt) >
                        const Duration(milliseconds: 1200)) {
                  _layoutAnchor = null;
                }
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
                });
                unawaited(_updateBookmarkState());
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
          ),
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
                    onTap: (at) => _onPageTurnButton(false, at))),
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
                    onTap: (at) => _onPageTurnButton(true, at))),
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
                  stepHeight:
                      _guidePitch == null ? null : _guideLines * _guidePitch!,
                  dark: isDark,
                  showHint: _guideHint)),
        // Bookmarked page: a ribbon at the top corner, as in Apple Books.
        if (_isEpubReady && !_isScrollMode)
          Positioned(
            top: 0,
            right: 18,
            child: IgnorePointer(
              child: AnimatedSlide(
                offset: _isCurrentLocationBookmarked
                    ? Offset.zero
                    : const Offset(0, -1),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _isCurrentLocationBookmarked ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: CustomPaint(
                    size: const Size(16, 26),
                    painter: _BookmarkRibbonPainter(isDark
                        ? const Color(0xFFFF6961)
                        : const Color(0xFFE5484D)),
                  ),
                ),
              ),
            ),
          ),
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
        // The back of the sheet is the same paper as the page (warm paper
        // on Warm), as in Apple Books.
        return PageCurl(
            program: _curlProgram!,
            image: image,
            progress: _turnCurve,
            paperColor: pageColor,
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
    _layoutAnchor ??= _currentCfi;
    _lastResizeAt = DateTime.now();
    _reanchorTimer?.cancel();
    _reanchorTimer = Timer(const Duration(milliseconds: 400), () {
      final cfi = _layoutAnchor ?? _currentCfi;
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

  /// A page-turn button was tapped at [at] (global position). Note dots
  /// sit in the right margin, where the button is: a tap right on a dot
  /// opens that note; any other tap turns the page.
  Future<void> _onPageTurnButton(bool forward, Offset? at) async {
    final box = _bookKey.currentContext?.findRenderObject() as RenderBox?;
    final size = _bookViewSize;
    final hasNotes = _annotations.values.any((a) => a.hasNote);
    if (at != null &&
        hasNotes &&
        box != null &&
        box.attached &&
        size != null &&
        !size.isEmpty &&
        !_turning &&
        !_hasSelection) {
      final local = box.globalToLocal(at);
      final target = await EpubReaderBridge.tapAt(
          _epubController,
          (local.dx / size.width).clamp(0.0, 1.0),
          (local.dy / size.height).clamp(0.0, 1.0));
      if (!mounted) return;
      if (target.kind == 'annotation' && target.noteTap) {
        final withNote = [
          for (final hit in target.annotations)
            if (_annotations[EpubAnnotation.keyFor(hit.type, hit.cfi)]
                    ?.hasNote ??
                false)
              _annotations[EpubAnnotation.keyFor(hit.type, hit.cfi)]!
        ];
        if (withNote.isNotEmpty) {
          _editNote(withNote.first);
          return;
        }
      }
    }
    unawaited(_turnPage(forward: forward));
  }

  Widget _pageTurnButton({
    required IconData icon,
    required bool isDark,
    required String tooltip,
    required ValueChanged<Offset?> onTap,
  }) {
    Offset? at;
    return Material(
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTapDown: (details) => at = details.globalPosition,
        onTap: () => onTap(at),
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
/// The bookmark ribbon drawn at the top corner of a bookmarked page.
class _BookmarkRibbonPainter extends CustomPainter {
  const _BookmarkRibbonPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final notch = size.height * 0.24;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - notch)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BookmarkRibbonPainter old) =>
      old.color != color;
}

/// One row of the Notes & Highlights panel: a highlight/underline or a
/// note, with where it is in the book.
class _NotesItem {
  const _NotesItem({
    this.annotation,
    this.noteId,
    this.note = '',
    this.cfi,
    this.chapter = '',
    this.page,
    required this.order,
  });
  final EpubAnnotation? annotation;
  final String? noteId;
  final String note;
  final String? cfi;
  final String chapter;
  final int? page;
  final int order;
}

class _GoToLocationDialog extends StatefulWidget {
  const _GoToLocationDialog({
    required this.title,
    required this.label,
    required this.min,
    required this.max,
    required this.initial,
    required this.isDark,
    this.suffix,
  });

  final String title;
  final String label;
  final String? suffix;
  final int min;
  final int max;
  final int initial;
  final bool isDark;

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
    _controller = TextEditingController(text: widget.initial.toString());
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
    if (v == null || v < widget.min || v > widget.max) {
      setState(
          () => _error = 'Enter a number from ${widget.min} to ${widget.max}');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor:
          widget.isDark ? AppColors.darkCardBackground : Colors.white,
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.go,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.label,
          suffixText: widget.suffix,
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

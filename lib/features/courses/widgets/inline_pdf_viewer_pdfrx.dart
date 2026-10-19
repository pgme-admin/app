import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/models/selectable_document.dart';
import 'package:pgme/core/services/api_service.dart';
import 'package:pgme/core/services/download_service.dart';
import 'package:pgme/core/services/ebook_access_service.dart';
import 'package:pgme/core/services/pdf_cache_service.dart';

/// pdfrx-backed twin of [InlinePdfViewer]. Same constructor surface so a
/// caller can swap the import without touching anything else, but renders
/// via pdfrx's viewport-based engine instead of Syncfusion. Used to test
/// pdfrx in the video-player split view.
///
/// Loads the document fully (via PdfDocument.loadPagesProgressively) BEFORE
/// mounting the viewer — same blocking-progress pattern as the standalone
/// pdfrx test viewer — so the user never sees a half-loaded document and
/// onPdfReady fires only when the document is genuinely ready to interact.
class InlinePdfViewerPdfrx extends StatefulWidget {
  final SelectableDocument document;
  final VoidCallback onClose;

  /// Fires once the PDF has both downloaded AND fully loaded all page
  /// metadata. The split-view host uses this to resume the paused video.
  final VoidCallback? onPdfReady;

  const InlinePdfViewerPdfrx({
    super.key,
    required this.document,
    required this.onClose,
    this.onPdfReady,
  });

  @override
  State<InlinePdfViewerPdfrx> createState() => _InlinePdfViewerPdfrxState();
}

class _InlinePdfViewerPdfrxState extends State<InlinePdfViewerPdfrx> {
  final PdfViewerController _pdfController = PdfViewerController();

  // Download state
  bool _isLoading = true;
  double _downloadProgress = 0;
  String? _error;
  CancelToken? _cancelToken;

  // Document state — viewer mounts only after _document is non-null.
  PdfDocument? _document;
  int _totalPages = 0;
  int _loadedPages = 0;
  bool _readyFired = false;

  // Current page indicator (top-right overlay). ValueNotifier so only the
  // overlay rebuilds on page change — not the cached PdfViewer.
  final ValueNotifier<int> _currentPage = ValueNotifier(1);

  // Scroll-head: a prominent centered "Page X of Y" pill that pops up
  // while the user is actively flipping through and fades out after a
  // moment of stillness. Mirrors Syncfusion's scroll-head UX so users
  // moving from the old viewer don't lose the orientation cue. Driven
  // by [_scrollHeadVisible] + [_scrollHeadHideTimer]; the page value
  // itself piggybacks on [_currentPage].
  final ValueNotifier<bool> _scrollHeadVisible = ValueNotifier(false);
  Timer? _scrollHeadHideTimer;
  static const Duration _scrollHeadHideDelay = Duration(milliseconds: 900);

  Widget? _cachedViewer;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  @override
  void dispose() {
    _cancelToken?.cancel('Widget disposed');
    // PdfViewerController has no dispose() in pdfrx — it auto-cleans when
    // the PdfViewer widget unmounts. We only own the PdfDocument lifecycle
    // (because we passed PdfDocumentRefDirect with autoDispose: false).
    _document?.dispose();
    _document = null;
    _currentPage.dispose();
    _scrollHeadHideTimer?.cancel();
    _scrollHeadVisible.dispose();
    super.dispose();
  }

  /// Pops the scroll-head overlay open and resets the auto-hide timer.
  /// Called from onPageChanged so any page transition (scroll, jump,
  /// programmatic) re-asserts visibility.
  void _bumpScrollHead() {
    if (!_scrollHeadVisible.value) _scrollHeadVisible.value = true;
    _scrollHeadHideTimer?.cancel();
    _scrollHeadHideTimer = Timer(_scrollHeadHideDelay, () {
      if (mounted) _scrollHeadVisible.value = false;
    });
  }

  // ── Step 1: get the file on disk ──────────────────────────────────

  Future<void> _loadPdf() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _downloadProgress = 0;
      _cachedViewer = null;
    });

    try {
      final docFileName = 'doc_${widget.document.id}.pdf';
      final ebookFileName = 'ebook_${widget.document.id}.pdf';
      final downloadedPath =
          await DownloadService().getDownloadedPath(docFileName) ??
              await DownloadService().getDownloadedPath(ebookFileName);

      if (downloadedPath != null) {
        final file = File(downloadedPath);
        if (await file.exists() && await file.length() > 0) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          _loadDocumentFully(downloadedPath);
          return;
        }
      }

      String pdfUrl;
      if (widget.document.source == DocumentSource.ebook) {
        final data =
            await EbookAccessService().getEbookViewUrl(widget.document.id);
        pdfUrl = data['url'] as String;
      } else {
        final response = await ApiService()
            .dio
            .get(ApiConstants.documentViewUrl(widget.document.id));
        pdfUrl = response.data['data']['url'] as String;
      }

      if (!mounted) return;

      // Shares the same cache key as the standalone pdfrx viewer so opening
      // a doc here warms the cache for the full-screen viewer (and vice
      // versa). Persistent (TTL + LRU) — the OS only purges under genuine
      // storage pressure, never between launches.
      final cacheKey = widget.document.id;
      final cached = await PdfCacheService.getCachedFile(cacheKey);
      if (cached != null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        // Pass the key so a parse failure (corrupt cached file) drops the
        // entry; the next mount will re-download cleanly.
        _loadDocumentFully(cached.path, cacheKey: cacheKey);
        return;
      }

      _cancelToken = CancelToken();
      final downloaded = await PdfCacheService.cacheFromUrl(
        cacheKey,
        pdfUrl,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      if (!mounted) return;
      setState(() => _isLoading = false);
      _loadDocumentFully(downloaded.path, cacheKey: cacheKey);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      if (mounted) {
        setState(() {
          _error = 'Download failed: ${e.message}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  // ── Step 2: open + fully load the document before showing viewer ─

  Future<void> _loadDocumentFully(String filePath, {String? cacheKey}) async {
    if (!mounted) return;
    try {
      final doc = await PdfDocument.openFile(
        filePath,
        useProgressiveLoading: true,
      );
      if (!mounted) {
        await doc.dispose();
        return;
      }
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
      setState(() => _document = doc);
      // Fire onPdfReady once — split-view host resumes video.
      if (!_readyFired) {
        _readyFired = true;
        widget.onPdfReady?.call();
      }
    } catch (e) {
      debugPrint('[InlinePdfViewerPdfrx] Failed to load document: $e');
      // Drop the cache entry on parse failure so the next mount
      // re-downloads instead of looping on the same corrupt file.
      if (cacheKey != null) {
        await PdfCacheService.invalidate(cacheKey);
      }
      if (mounted) {
        setState(() => _error = 'Failed to load PDF');
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          if (_isLoading)
            _buildDownloadProgress()
          else if (_error != null)
            _buildError()
          else if (_document == null)
            _buildPageLoadingProgress()
          else
            _buildPdfViewer(),
          // Close button overlay — same position/style as Syncfusion variant.
          Positioned(
            top: 4,
            left: 4,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          // Page indicator overlay — only shown once the doc is ready and
          // we know the total. Mirrors the full-screen viewer's "X / Y"
          // header. ValueListenableBuilder rebuilds only this badge when
          // the page changes; the PdfViewer itself is never rebuilt.
          if (_document != null && _totalPages > 0)
            Positioned(
              top: 4,
              right: 4,
              child: ValueListenableBuilder<int>(
                valueListenable: _currentPage,
                builder: (context, page, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '$page / $_totalPages',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  );
                },
              ),
            ),
          // Scroll-head overlay — large centered "Page X of Y" pill that
          // pops up while the user is scrolling and fades out after
          // [_scrollHeadHideDelay] of stillness. Centers itself near the
          // bottom of the viewport so it doesn't obscure the page content
          // the user is reading. IgnorePointer keeps it from intercepting
          // touch events meant for the PDF.
          if (_document != null && _totalPages > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: IgnorePointer(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _scrollHeadVisible,
                  builder: (context, visible, _) {
                    return AnimatedOpacity(
                      opacity: visible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: Center(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _currentPage,
                          builder: (context, page, _) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.78),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                'Page $page of $_totalPages',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPdfViewer() {
    // Cache the viewer so setState rebuilds reuse the same widget instance
    // (matches the cache pattern in the standalone pdfrx test viewer).
    _cachedViewer ??= PdfViewer(
      PdfDocumentRefDirect(_document!, autoDispose: false),
      controller: _pdfController,
      params: PdfViewerParams(
        // Edge-to-edge inside the split pane, no grey backdrop.
        margin: 0,
        backgroundColor: Colors.transparent,
        // Fill the pane width; scroll vertically through the doc.
        calculateInitialZoom:
            (document, controller, fitZoom, coverZoom) => coverZoom,
        // Cap rendered-page bitmap cache for the heap-constrained tablets
        // that prompted this whole exercise.
        maxImageBytesCachedOnMemory: 50 * 1024 * 1024,
        // Drive the top-right page indicator AND the centered scroll-head
        // overlay without rebuilding the viewer. Bumping the scroll head
        // from here means any page transition (scroll, programmatic jump,
        // pinch-zoom-induced reflow) shows the indicator and resets its
        // auto-hide timer.
        onPageChanged: (pageNumber) {
          if (pageNumber != null) {
            _currentPage.value = pageNumber;
            _bumpScrollHead();
          }
        },
        // Pre-sized layout so scroll extent is correct from frame one.
        // (See standalone pdfrx viewer for the full rationale.)
        layoutPages: (pages, params) {
          if (pages.isEmpty) {
            return PdfPageLayout(
                pageLayouts: const [], documentSize: Size.zero);
          }
          double estW = pages.first.width;
          double estH = pages.first.height;
          for (final p in pages) {
            if (p.width > 0 && p.height > 0) {
              estW = p.width;
              estH = p.height;
              break;
            }
          }
          final pageCount =
              _totalPages > pages.length ? _totalPages : pages.length;
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
      ),
    );
    return _cachedViewer!;
  }

  Widget _buildDownloadProgress() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              value: _downloadProgress > 0 ? _downloadProgress : null,
              color: Colors.white54,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _downloadProgress > 0
                ? '${(_downloadProgress * 100).toInt()}%'
                : 'Downloading…',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageLoadingProgress() {
    final hasTotal = _totalPages > 0;
    final progress = hasTotal ? _loadedPages / _totalPages : null;
    final pct = hasTotal ? ((_loadedPages / _totalPages) * 100).toInt() : 0;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              value: progress,
              color: Colors.white54,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasTotal ? '$_loadedPages / $_totalPages  •  $pct%' : 'Opening…',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Preparing pages',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white38, size: 32),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Failed to load document',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadPdf,
              child: const Text('Retry',
                  style: TextStyle(color: Color(0xFF00BEFA), fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

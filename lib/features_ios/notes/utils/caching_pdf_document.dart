import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// PdfDocument wrapper that memoizes [PdfPage.loadText] per page.
///
/// pdfrx 1.3.5's [PdfPageTextOverlay] calls `page.loadText()` in initState
/// every time it mounts. Until that future resolves the overlay returns an
/// empty SizedBox and text selection is impossible. With no caching at the
/// pdfrx or pdfium-bindings layer, every page revisit re-extracts text on a
/// single background isolate worker, costing 200ms-1s per page.
///
/// Wrapping the document so each page memoizes its own loadText future means
/// the second mount of a given page returns instantly. Selection becomes
/// available the moment the user reaches the page (after the first
/// extraction completes once).
PdfDocument wrapWithTextCache(PdfDocument inner) => _CachingPdfDocument(inner);

class _CachingPdfDocument extends PdfDocument {
  _CachingPdfDocument(this._inner) : super(sourceName: _inner.sourceName);

  final PdfDocument _inner;
  List<PdfPage>? _pagesCache;

  @override
  PdfPermissions? get permissions => _inner.permissions;

  @override
  bool get isEncrypted => _inner.isEncrypted;

  @override
  Future<void> dispose() => _inner.dispose();

  @override
  Stream<PdfDocumentEvent> get events => _inner.events;

  @override
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
  }) {
    _pagesCache = null;
    return _inner.loadPagesProgressively(
      onPageLoadProgress: onPageLoadProgress,
      data: data,
      loadUnitDuration: loadUnitDuration,
    );
  }

  @override
  List<PdfPage> get pages {
    final innerPages = _inner.pages;
    final cache = _pagesCache;
    if (cache != null && cache.length == innerPages.length) return cache;
    return _pagesCache = List<PdfPage>.unmodifiable(
      innerPages.map((p) => _CachingPdfPage(this, p)),
    );
  }

  @override
  Future<List<PdfOutlineNode>> loadOutline() => _inner.loadOutline();

  @override
  bool isIdenticalDocumentHandle(Object? other) {
    if (other is _CachingPdfDocument) {
      return _inner.isIdenticalDocumentHandle(other._inner);
    }
    return _inner.isIdenticalDocumentHandle(other);
  }
}

class _CachingPdfPage extends PdfPage {
  _CachingPdfPage(this._document, this._inner);

  final _CachingPdfDocument _document;
  final PdfPage _inner;
  Future<PdfPageText>? _cachedText;

  @override
  PdfDocument get document => _document;

  @override
  int get pageNumber => _inner.pageNumber;

  @override
  double get width => _inner.width;

  @override
  double get height => _inner.height;

  @override
  PdfPageRotation get rotation => _inner.rotation;

  @override
  bool get isLoaded => _inner.isLoaded;

  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    Color? backgroundColor,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
  }) =>
      _inner.render(
        x: x,
        y: y,
        width: width,
        height: height,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
        backgroundColor: backgroundColor,
        annotationRenderingMode: annotationRenderingMode,
        flags: flags,
        cancellationToken: cancellationToken,
      );

  @override
  PdfPageRenderCancellationToken createCancellationToken() =>
      _inner.createCancellationToken();

  @override
  Future<PdfPageText> loadText() => _cachedText ??= _inner.loadText();

  @override
  Future<List<PdfLink>> loadLinks({
    bool compact = false,
    bool enableAutoLinkDetection = true,
  }) =>
      _inner.loadLinks(
        compact: compact,
        enableAutoLinkDetection: enableAutoLinkDetection,
      );
}


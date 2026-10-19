import 'package:flutter/foundation.dart';

/// Canonical annotation, platform-independent. Coordinates are **PDF points,
/// bottom-left origin, unrotated** so a highlight created on iOS (PDFKit) and
/// one created on Android (Jetpack PDF) describe the same region and render
/// identically on either platform.
///
/// This mirrors the `anchor_v2` record the backend stores. While old and new
/// app versions coexist, the sync layer also writes the legacy `bounds_data`
/// field; that translation lives in the sync layer, not here.
@immutable
class ReaderAnnotation {
  /// Client-generated id, used as the idempotency key for offline retries.
  final String clientId;

  /// 0-based page index.
  final int pageIndex;

  /// One quad per visual line: [x1,y1, x2,y2, x3,y3, x4,y4] in PDF points.
  final List<List<double>> quads;

  final ReaderAnnotationType type;
  final String color;
  final String? note;

  /// Exact selected text plus a little surrounding context, used to
  /// re-anchor if the underlying PDF is ever re-uploaded.
  final String? textExact;

  const ReaderAnnotation({
    required this.clientId,
    required this.pageIndex,
    required this.quads,
    required this.type,
    required this.color,
    this.note,
    this.textExact,
  });

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'page_index': pageIndex,
        'quads': quads,
        'type': type.name,
        'color': color,
        if (note != null) 'note': note,
        if (textExact != null) 'text_quote': {'exact': textExact},
      };

  factory ReaderAnnotation.fromJson(Map<String, dynamic> json) {
    final rawQuads = (json['quads'] as List?) ?? const [];
    return ReaderAnnotation(
      clientId: json['client_id'] as String,
      pageIndex: (json['page_index'] as num).toInt(),
      quads: rawQuads
          .map<List<double>>((q) =>
              (q as List).map((n) => (n as num).toDouble()).toList())
          .toList(),
      type: ReaderAnnotationType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => ReaderAnnotationType.highlight,
      ),
      color: (json['color'] as String?) ?? 'yellow',
      note: json['note'] as String?,
      textExact: (json['text_quote'] as Map?)?['exact'] as String?,
    );
  }
}

enum ReaderAnnotationType { highlight, underline }

/// The seam between Dart and the native readers. Both the Android
/// (Jetpack PDF) and iOS (PDFKit) platform-view controllers implement this;
/// the Phase 1 spike implements it against a real document to pin down the
/// behaviours the plan flags as unverified (annotation-bounds units,
/// scroll-to-page, batch windowing). Keeping every native call behind this
/// interface is what lets a beta-API change stay a one-file fix.
///
/// No implementation exists yet — this phase defines the contract only.
abstract class NativePdfBridge {
  /// Open [filePathOrUri] and show [initialPage] (0-based) first, without a
  /// visible jump from page 1. Completes when the first page is on screen.
  Future<void> open({required String filePathOrUri, required int initialPage});

  /// Current page (0-based) as the user scrolls. Drives progress saving.
  Stream<int> get pageChanges;

  /// Text the user has selected, as canonical PDF-point quads, or null when
  /// the selection is cleared. The creation UI turns this into a
  /// [ReaderAnnotation].
  Stream<List<List<double>>?> get selectionQuads;

  /// Draw these annotations for the pages currently in the window. Called on
  /// open and whenever the window moves. Must not modify or rewrite the PDF.
  Future<void> renderAnnotations(List<ReaderAnnotation> annotations);

  /// Keep a window of pages around [centerPage] loaded and release the rest —
  /// the batch-loading requirement. Window size comes from `/app-settings`.
  Future<void> setActiveWindow({required int centerPage});

  Future<void> goToPage(int pageIndex);

  Future<void> dispose();
}

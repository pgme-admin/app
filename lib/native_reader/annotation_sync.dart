import 'package:dio/dio.dart';

import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/services/api_service.dart';
import 'package:pgme/native_reader/native_pdf_bridge.dart';

/// Talks to the existing `/users/document-highlights` endpoints for the
/// native reader, using the canonical [ReaderAnnotation] model.
///
/// It round-trips the backend's additive native-reader fields (`anchor_v2`,
/// `client_id`, `revision`) added in the backend `feat/native-pdf-reader`
/// branch, while also writing the legacy `bounds_data` so a user still on the
/// old Syncfusion/pdfrx viewer sees annotations made in the native reader.
///
/// This service is standalone and imported by nothing yet; the current
/// viewers keep using `HighlightService` untouched.
///
/// ## Legacy bounds caveat
///
/// The legacy `bounds_data` format stores top-left-origin page points (the
/// Syncfusion convention of the shipped viewer). Converting the canonical
/// bottom-left-origin [ReaderAnnotation.quads] to that convention needs the
/// page height, which only the native view knows at creation time. So the
/// caller passes already-converted [LegacyBounds] in [create]; this service
/// does not guess. The exact conversion is confirmed by the P1 spike before
/// it is relied on for cross-viewer fidelity.
class AnnotationSyncService {
  AnnotationSyncService({Dio? dio}) : _dio = dio ?? ApiService().dio;

  final Dio _dio;

  /// Fetch annotations for a page window. Omitting both bounds fetches all.
  /// Rows that already carry `anchor_v2` are returned as canonical
  /// [ReaderAnnotation]s; legacy rows (no `anchor_v2`) are skipped here and
  /// handled by the viewer's legacy-bounds path, since they can't be
  /// expressed as canonical quads without the original page geometry.
  Future<List<ReaderAnnotation>> fetchWindow(
    String documentId, {
    int? pageFrom,
    int? pageTo,
  }) async {
    final response = await _dio.get(
      ApiConstants.documentHighlights,
      queryParameters: {
        'document_id': documentId,
        if (pageFrom != null) 'page_from': pageFrom,
        if (pageTo != null) 'page_to': pageTo,
      },
    );

    final list = (response.data['data']?['highlights'] as List?) ?? const [];
    final result = <ReaderAnnotation>[];
    for (final raw in list) {
      final map = Map<String, dynamic>.from(raw as Map);
      final anchor = map['anchor_v2'];
      if (anchor is Map) {
        // Carry the server highlight_id across as the client_id when the row
        // predates client_id, so deletes still resolve.
        final merged = Map<String, dynamic>.from(anchor);
        merged['client_id'] =
            map['client_id'] ?? map['highlight_id'] ?? merged['client_id'];
        merged['color'] ??= map['color'];
        merged['note'] ??= map['note'];
        merged['type'] ??= map['annotation_type'];
        result.add(ReaderAnnotation.fromJson(merged));
      }
    }
    return result;
  }

  /// Create (or idempotently update) an annotation. [legacy] is the
  /// pre-converted top-left bounds for old-viewer compatibility; pass null to
  /// skip legacy dual-write. Returns the backend `highlight_id`.
  Future<String> create(
    String documentId,
    ReaderAnnotation annotation, {
    LegacyBounds? legacy,
  }) async {
    final body = <String, dynamic>{
      'document_id': documentId,
      // Legacy required/enum fields kept valid for old clients and the
      // existing schema validators.
      'page_number': annotation.pageIndex + 1,
      'annotation_type': annotation.type.name,
      'color': annotation.color,
      if (annotation.note != null) 'note': annotation.note,
      if (annotation.textExact != null) 'highlighted_text': annotation.textExact,
      // Canonical native-reader fields.
      'client_id': annotation.clientId,
      'anchor_v2': annotation.toJson(),
      if (legacy != null) 'bounds_data': legacy.toJson(),
    };

    final response = await _dio.post(
      ApiConstants.documentHighlights,
      data: body,
    );
    return (response.data['data']?['highlight_id'] ??
            response.data['highlight_id'])
        .toString();
  }

  Future<void> delete(String highlightId) async {
    await _dio.delete(ApiConstants.documentHighlight(highlightId));
  }

  Future<void> updateNote(String highlightId, String? note) async {
    await _dio.put(
      ApiConstants.documentHighlightNote(highlightId),
      data: {'note': note},
    );
  }
}

/// Pre-converted legacy bounds (top-left-origin page points), supplied by the
/// native view which knows the page height at creation time.
class LegacyBounds {
  final List<Map<String, dynamic>> lines;
  const LegacyBounds(this.lines);
  List<Map<String, dynamic>> toJson() => lines;
}

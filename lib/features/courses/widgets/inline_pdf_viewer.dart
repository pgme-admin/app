import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/models/selectable_document.dart';
import 'package:pgme/core/services/api_service.dart';
import 'package:pgme/core/services/download_service.dart';
import 'package:pgme/core/services/ebook_access_service.dart';

/// Lightweight inline PDF viewer for split-view alongside the video player.
/// Read-only — text selection disabled due to Syncfusion crash in split layouts.
class InlinePdfViewer extends StatefulWidget {
  final SelectableDocument document;
  final VoidCallback onClose;
  /// Fires when the PDF has finished downloading AND Syncfusion has parsed
  /// the document and rendered the first page. Used by the split-view host
  /// to resume the video player once the heavy PDF-load phase is over.
  final VoidCallback? onPdfReady;

  const InlinePdfViewer({
    super.key,
    required this.document,
    required this.onClose,
    this.onPdfReady,
  });

  @override
  State<InlinePdfViewer> createState() => _InlinePdfViewerState();
}

class _InlinePdfViewerState extends State<InlinePdfViewer> {
  final PdfViewerController _pdfController = PdfViewerController();

  String? _localPath;
  bool _isLoading = true;
  double _downloadProgress = 0;
  String? _error;
  CancelToken? _cancelToken;
  Widget? _cachedViewer;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  @override
  void dispose() {
    _cancelToken?.cancel('Widget disposed');
    _pdfController.dispose();
    super.dispose();
  }

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
          if (mounted) {
            setState(() {
              _localPath = downloadedPath;
              _isLoading = false;
            });
          }
          return;
        }
      }

      String pdfUrl;
      if (widget.document.source == DocumentSource.ebook) {
        final data = await EbookAccessService()
            .getEbookViewUrl(widget.document.id);
        pdfUrl = data['url'] as String;
      } else {
        final response = await ApiService().dio.get(
          ApiConstants.documentViewUrl(widget.document.id),
        );
        pdfUrl = response.data['data']['url'] as String;
      }

      if (!mounted) return;

      final dir = await getTemporaryDirectory();
      final fileName = 'pgme_inline_${widget.document.id}.pdf';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      if (await file.exists() && await file.length() > 0) {
        if (mounted) {
          setState(() {
            _localPath = filePath;
            _isLoading = false;
          });
        }
        return;
      }

      _cancelToken = CancelToken();
      await Dio().download(
        pdfUrl,
        filePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      if (mounted) {
        setState(() {
          _localPath = filePath;
          _isLoading = false;
        });
      }
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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          if (_isLoading)
            _buildLoading()
          else if (_error != null)
            _buildError()
          else if (_localPath != null)
            _buildPdfViewer(),
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
        ],
      ),
    );
  }

  Widget _buildPdfViewer() {
    _cachedViewer ??= SfPdfViewer.file(
      File(_localPath!),
      controller: _pdfController,
      canShowTextSelectionMenu: false,
      enableTextSelection: false,
      enableDoubleTapZooming: true,
      maxZoomLevel: 3.0,
      pageSpacing: 2,
      onDocumentLoaded: (PdfDocumentLoadedDetails details) {
        widget.onPdfReady?.call();
      },
    );
    return _cachedViewer!;
  }

  Widget _buildLoading() {
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
                : 'Loading document...',
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

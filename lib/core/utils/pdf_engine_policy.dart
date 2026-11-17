import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// Both reader screens are named `PdfViewerScreen`, so each gets a prefix.
import 'package:pgme/features/notes/screens/pdf_viewer_screen.dart'
    as syncfusion_reader;
import 'package:pgme/features/notes/screens/pdf_viewer_screen_pdfrx.dart'
    as pdfrx_reader;

/// Decides which PDF engine renders a standalone PDF reader.
///
/// Policy:
///  * Android with API level below 35, or Android whose version could not be
///    determined  ->  pdfrx. The Syncfusion viewer is slow and memory-hungry
///    on old devices, and the native androidx.pdf viewer needs Android 15
///    (API 35), so pdfrx is the engine that old devices always get.
///  * iOS  ->  pdfrx. Measured on a 1,502-page book, Syncfusion did ~3x the
///    per-frame work of pdfrx while scrolling (spikes 39 ms vs 7 ms), froze
///    ~0.25 s on open and used several times more memory; pdfrx renders with
///    PDFium off the UI thread and is already the split-pane reader on iOS.
///  * Every other case (Android 35+, anything else)  ->  the existing
///    Syncfusion reader, unchanged.
///
/// Call [init] once at startup. It never throws. If it never ran (or has not
/// finished yet) the getters stay safe: Android falls back to pdfrx, iOS uses
/// pdfrx, other platforms keep Syncfusion.
class PdfEnginePolicy {
  PdfEnginePolicy._();

  /// First Android API level with the native PDF viewer (Android 15).
  static const int nativeViewerMinSdk = 35;

  static int? _androidSdkInt;
  static Future<void>? _initFuture;

  /// Reads and caches the Android API level. Safe to call repeatedly and
  /// concurrently; the lookup runs once. Never throws and cannot hang
  /// startup (the platform query is capped by a timeout).
  static Future<void> init() => _initFuture ??= _load();

  static Future<void> _load() async {
    try {
      if (kIsWeb || !Platform.isAndroid) return;
      final info = await DeviceInfoPlugin()
          .androidInfo
          .timeout(const Duration(seconds: 3));
      _androidSdkInt = info.version.sdkInt;
    } catch (e) {
      // Leave the API level unknown: on Android that selects pdfrx.
      debugPrint('PdfEnginePolicy: could not read Android SDK level: $e');
    }
  }

  /// Pure decision function (no platform access).
  @visibleForTesting
  static bool decide({
    required bool isAndroid,
    required int? androidSdkInt,
    bool isIOS = false,
  }) {
    if (isIOS) return true;
    if (!isAndroid) return false;
    if (androidSdkInt == null) return true;
    return androidSdkInt < nativeViewerMinSdk;
  }

  /// True when standalone PDF readers must use pdfrx instead of Syncfusion.
  static bool get usePdfrx {
    try {
      return decide(
        isAndroid: !kIsWeb && Platform.isAndroid,
        isIOS: !kIsWeb && Platform.isIOS,
        androidSdkInt: _androidSdkInt,
      );
    } catch (_) {
      return false;
    }
  }

  /// Builds the standalone PDF reader for the active engine. Arguments mirror
  /// the shared constructor surface of both screens.
  ///
  /// [source] only exists on the pdfrx screen (it selects the ebook URL
  /// endpoint when only a [documentId] is given); the Syncfusion screen has no
  /// such parameter, so it is ignored there.
  static Widget buildReader({
    Key? key,
    String? documentId,
    String? pdfUrl,
    String? filePath,
    String title = 'PDF Viewer',
    String? source,
  }) {
    if (usePdfrx) {
      return pdfrx_reader.PdfViewerScreen(
        key: key,
        documentId: documentId,
        pdfUrl: pdfUrl,
        filePath: filePath,
        title: title,
        source: source,
      );
    }
    return syncfusion_reader.PdfViewerScreen(
      key: key,
      documentId: documentId,
      pdfUrl: pdfUrl,
      filePath: filePath,
      title: title,
    );
  }
}

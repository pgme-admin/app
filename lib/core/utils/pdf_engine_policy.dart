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
///  * iOS and every Android version  ->  pdfrx.
///    - Measured on a 1,502-page book, Syncfusion did ~3x the per-frame work
///      of pdfrx while scrolling (spikes 39 ms vs 7 ms), froze ~0.25 s on open
///      and used several times more memory (~3.7 GB peak vs ~0.8 GB); pdfrx
///      renders with PDFium off the UI thread.
///    - The ebook fixes the client asked for (Nov 2026) exist only in the
///      pdfrx reader and cannot be made in Syncfusion: opening on one whole
///      page (Syncfusion's scrolling mode always fills the width), highlights
///      that leave the text black (Syncfusion paints its own translucent
///      layer over the words), aligned underlines, the colour menu next to
///      the selection and clearing the selection after an annotation.
///    - Android 15+ used to keep Syncfusion, reserved for a native
///      androidx.pdf viewer that was never merged into this codebase.
///  * Anything else (no such builds today)  ->  the Syncfusion reader.
///
/// [androidSdkInt] is still read at startup: [nativeViewerMinSdk] marks where
/// a native Android viewer would plug in, should one be added.
///
/// Call [init] once at startup. It never throws.
class PdfEnginePolicy {
  PdfEnginePolicy._();

  /// First Android API level with the platform PDF viewer (androidx.pdf,
  /// Android 15). Not used for the decision today; see the class comment.
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
      // Leave the API level unknown; the engine choice does not depend on it.
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
    return isIOS || isAndroid;
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

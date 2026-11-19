import 'dart:io';

/// Offline copies belong to the signed-in account, even on a shared device.
String epubDownloadFileName(String userId, String id, {required bool isDocument}) =>
    '${userId}_${isDocument ? 'doc' : 'ebook'}_$id.epub';

/// The older iOS and Android ebook services wrap transport errors in this
/// message. Server refusals have a different message and must not use offline
/// fallback.
bool isLegacyEbookNetworkError(Object error) =>
    error.toString().startsWith('Exception: Network error:');

/// Reject a PDF, HTML error page, or interrupted download before handing it to
/// the EPUB web reader. EPUB files are ZIP archives; the reader checks their
/// internal package when it opens them.
Future<bool> isEpubArchive(File file) async {
  if (!await file.exists() || await file.length() < 4) return false;
  final input = await file.open();
  try {
    final signature = await input.read(4);
    return signature.length == 4 &&
        signature[0] == 0x50 &&
        signature[1] == 0x4b &&
        signature[2] == 0x03 &&
        signature[3] == 0x04;
  } finally {
    await input.close();
  }
}

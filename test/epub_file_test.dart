import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pgme/core/utils/epub_file.dart';

void main() {
  test('accepts a ZIP based EPUB and rejects failed downloads', () async {
    final dir = await Directory.systemTemp.createTemp('pgme_epub_test_');
    try {
      final epub = File('${dir.path}/book.epub')
        ..writeAsBytesSync([0x50, 0x4b, 0x03, 0x04, 1]);
      final pdf = File('${dir.path}/wrong.epub')
        ..writeAsStringSync('%PDF-1.7');
      final errorPage = File('${dir.path}/error.epub')
        ..writeAsStringSync('<html>Access denied</html>');
      final partial = File('${dir.path}/partial.epub')
        ..writeAsBytesSync([0x50, 0x4b]);

      expect(await isEpubArchive(epub), isTrue);
      expect(await isEpubArchive(pdf), isFalse);
      expect(await isEpubArchive(errorPage), isFalse);
      expect(await isEpubArchive(partial), isFalse);
      expect(await isEpubArchive(File('${dir.path}/missing.epub')), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('offline filenames are isolated by account and source', () {
    expect(epubDownloadFileName('userA', 'book1', isDocument: true),
        'userA_doc_book1.epub');
    expect(epubDownloadFileName('userB', 'book1', isDocument: true),
        isNot(epubDownloadFileName('userA', 'book1', isDocument: true)));
    expect(epubDownloadFileName('userA', 'book1', isDocument: false),
        isNot(epubDownloadFileName('userA', 'book1', isDocument: true)));
  });

  test('legacy offline fallback excludes server refusals', () {
    expect(isLegacyEbookNetworkError(Exception('Network error: timed out')),
        isTrue);
    expect(isLegacyEbookNetworkError(Exception('Access denied')), isFalse);
  });
}

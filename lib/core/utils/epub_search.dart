import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

/// flutter_epub_viewer 1.2.8 interpolates the query inside JavaScript quotes.
/// JSON encoding preserves quotes, backslashes, and newlines in medical terms.
Future<List<EpubSearchResult>> searchEpubBook(
    EpubController controller, String query) async {
  final webView = controller.webViewController;
  if (webView == null || query.trim().isEmpty) return [];
  final completer = Completer<List<EpubSearchResult>>();
  controller.searchResultCompleter = completer;
  await webView.evaluateJavascript(
      source: 'searchInBook(${jsonEncode(query.trim())})');
  return completer.future.timeout(const Duration(seconds: 20));
}

/// What the reader picked in the search results: a page or a text match.
class EpubSearchChoice {
  const EpubSearchChoice.page(int this.page) : cfi = null;
  const EpubSearchChoice.match(String this.cfi) : page = null;
  final int? page;
  final String? cfi;
}

/// Search results sheet. When the query is a page number of this book, the
/// first row goes to that page (as in Apple Books); text matches follow.
Future<EpubSearchChoice?> showEpubSearchResults(
  BuildContext context,
  List<EpubSearchResult> results, {
  int? page,
  int? totalPages,
  String query = '',
}) {
  final count = results.length;
  return showModalBottomSheet<EpubSearchChoice>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      final muted = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7);
      return SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  count == 0
                      ? 'Search results'
                      : '$count ${count == 1 ? 'match' : 'matches'}',
                  style: theme.textTheme.titleLarge),
            ),
          ),
          if (page != null) ...[
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text('Go to page $page'),
              subtitle: totalPages == null ? null : Text('of $totalPages'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, EpubSearchChoice.page(page)),
            ),
            const Divider(height: 1),
          ],
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(
                        page != null
                            ? 'No text matches'
                            : 'No matches in this book',
                        style: TextStyle(color: muted)))
                : ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) => ListTile(
                      title: Text.rich(
                          searchExcerpt(results[index].excerpt.trim(), query),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(
                          context, EpubSearchChoice.match(results[index].cfi)),
                    ),
                  ),
          ),
        ]),
      );
    },
  );
}

/// [excerpt] with every occurrence of [query] in bold.
@visibleForTesting
TextSpan searchExcerpt(String excerpt, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return TextSpan(text: excerpt);
  final lower = excerpt.toLowerCase();
  final spans = <TextSpan>[];
  var from = 0;
  while (true) {
    final at = lower.indexOf(q, from);
    if (at < 0) break;
    if (at > from) spans.add(TextSpan(text: excerpt.substring(from, at)));
    spans.add(TextSpan(
        text: excerpt.substring(at, at + q.length),
        style: const TextStyle(fontWeight: FontWeight.w700)));
    from = at + q.length;
  }
  if (from < excerpt.length) spans.add(TextSpan(text: excerpt.substring(from)));
  return TextSpan(children: spans);
}

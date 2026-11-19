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
  await webView.evaluateJavascript(source: 'searchInBook(${jsonEncode(query.trim())})');
  return completer.future.timeout(const Duration(seconds: 20));
}

Future<String?> showEpubSearchResults(
    BuildContext context, List<EpubSearchResult> results) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.65,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Search results · ${results.length}',
                style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? const Center(child: Text('No matches in this book'))
              : ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => ListTile(
                    title: Text(results[index].excerpt.trim(),
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, results[index].cfi),
                  ),
                ),
        ),
      ]),
    ),
  );
}

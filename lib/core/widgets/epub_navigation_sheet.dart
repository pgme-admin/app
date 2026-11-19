import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

Future<String?> showEpubNavigationSheet(
  BuildContext context,
  List<EpubChapter> chapters,
  Map<String, String> bookmarks,
) {
  final locations = bookmarks.values.where((cfi) => cfi.isNotEmpty).toList();
  final contents = <(EpubChapter, int)>[];
  void addChapters(List<EpubChapter> items, int depth) {
    for (final chapter in items) {
      contents.add((chapter, depth));
      addChapters(chapter.subitems, depth + 1);
    }
  }
  addChapters(chapters, 0);

  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DefaultTabController(
      length: 2,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Navigate book',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          const TabBar(tabs: [Tab(text: 'Contents'), Tab(text: 'Bookmarks')]),
          Expanded(child: TabBarView(children: [
            contents.isEmpty
                ? const Center(child: Text('No contents listed in this book'))
                : ListView.builder(
                    itemCount: contents.length,
                    itemBuilder: (context, index) {
                      final (chapter, depth) = contents[index];
                      return ListTile(
                        contentPadding: EdgeInsets.only(
                            left: 20.0 + depth * 16.0, right: 20),
                        title: Text(chapter.title,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: chapter.href.isEmpty
                            ? null
                            : () => Navigator.pop(context, chapter.href),
                      );
                    },
                  ),
            locations.isEmpty
                ? const Center(
                    child: Text('Use the bookmark icon to save a page.'))
                : ListView.builder(
                    itemCount: locations.length,
                    itemBuilder: (context, index) => ListTile(
                      leading: const Icon(Icons.bookmark_outline),
                      title: Text('Saved location ${index + 1}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, locations[index]),
                    ),
                  ),
          ])),
        ]),
      ),
    ),
  );
}

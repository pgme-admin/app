import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:intl/intl.dart';

/// A bookmark as listed in the Contents sheet.
class EpubBookmarkEntry {
  const EpubBookmarkEntry({
    required this.id,
    required this.cfi,
    this.chapter = '',
    this.page,
    this.created,
  });
  final String id;
  final String cfi;
  final String chapter;
  final int? page;
  final DateTime? created;
}

/// Contents and Bookmarks of the book. Returns where to go (a chapter href
/// or a bookmark's CFI), or null.
///
/// Bookmarks are listed in book order with their chapter, page and date;
/// swipe one away (or tap its bin) to delete it.
Future<String?> showEpubNavigationSheet(
  BuildContext context, {
  required List<EpubChapter> chapters,
  required List<EpubBookmarkEntry> bookmarks,
  required Future<void> Function(String id) onDeleteBookmark,
  String currentChapter = '',
  int initialTab = 0,
}) {
  final contents = <(EpubChapter, int)>[];
  void addChapters(List<EpubChapter> items, int depth) {
    for (final chapter in items) {
      contents.add((chapter, depth));
      addChapters(chapter.subitems, depth + 1);
    }
  }

  addChapters(chapters, 0);
  final saved = List<EpubBookmarkEntry>.of(bookmarks);
  final dateFormat = DateFormat('d MMM yyyy');

  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      final accent = theme.colorScheme.primary;
      final muted = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75);
      return DefaultTabController(
        length: 2,
        initialIndex: initialTab.clamp(0, 1),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(children: [
            const TabBar(tabs: [Tab(text: 'Contents'), Tab(text: 'Bookmarks')]),
            Expanded(
              child: TabBarView(children: [
                contents.isEmpty
                    ? const Center(
                        child: Text('No contents listed in this book'))
                    : ListView.builder(
                        itemCount: contents.length,
                        itemBuilder: (context, index) {
                          final (chapter, depth) = contents[index];
                          final current = currentChapter.isNotEmpty &&
                              chapter.title.trim() == currentChapter.trim();
                          return ListTile(
                            contentPadding: EdgeInsets.only(
                                left: 20.0 + depth * 16.0, right: 20),
                            title: Text(chapter.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: current
                                    ? TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w600)
                                    : null),
                            trailing: current
                                ? Icon(Icons.circle, size: 8, color: accent)
                                : null,
                            onTap: chapter.href.isEmpty
                                ? null
                                : () => Navigator.pop(context, chapter.href),
                          );
                        },
                      ),
                StatefulBuilder(builder: (context, setList) {
                  if (saved.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 36),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.bookmark_outline, size: 40, color: muted),
                          const SizedBox(height: 10),
                          const Text('No bookmarks yet',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(
                              'Tap the bookmark icon at the top to save a page.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: muted)),
                        ]),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: saved.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 64),
                    itemBuilder: (context, index) {
                      final b = saved[index];
                      final details = [
                        if (b.page != null) 'Page ${b.page}',
                        if (b.created != null) dateFormat.format(b.created!),
                      ].join(' · ');
                      Future<void> delete() async {
                        setList(() => saved.remove(b));
                        await onDeleteBookmark(b.id);
                      }

                      return Dismissible(
                        key: ValueKey('bookmark-${b.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: theme.colorScheme.error,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete_outline,
                              color: Colors.white),
                        ),
                        onDismissed: (_) => delete(),
                        child: ListTile(
                          leading: Icon(Icons.bookmark, color: accent),
                          title: Text(
                              b.chapter.isEmpty ? 'Bookmark' : b.chapter,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          subtitle: details.isEmpty ? null : Text(details),
                          trailing: IconButton(
                            tooltip: 'Delete bookmark',
                            icon: Icon(Icons.delete_outline, color: muted),
                            onPressed: delete,
                          ),
                          onTap: () => Navigator.pop(context, b.cfi),
                        ),
                      );
                    },
                  );
                }),
              ]),
            ),
          ]),
        ),
      );
    },
  );
}

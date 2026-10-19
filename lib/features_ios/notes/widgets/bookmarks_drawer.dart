import 'package:flutter/material.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';

class BookmarksDrawer extends StatelessWidget {
  final Map<int, String> bookmarkedPages;
  final Map<String, String?> bookmarkNotes;
  final bool isDark;
  final bool isTablet;
  final Function(int pageNumber) onJumpToPage;
  final Function(String bookmarkId, int pageNumber) onDeleteBookmark;
  final Function(String bookmarkId, String? note) onUpdateNote;

  const BookmarksDrawer({
    super.key,
    required this.bookmarkedPages,
    required this.bookmarkNotes,
    required this.isDark,
    required this.isTablet,
    required this.onJumpToPage,
    required this.onDeleteBookmark,
    required this.onUpdateNote,
  });

  @override
  Widget build(BuildContext context) {
    final sortedPages = bookmarkedPages.keys.toList()..sort();
    final backgroundColor =
        isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;
    final subtitleColor =
        isDark ? AppColors.darkTextSecondary : Colors.grey[600]!;

    return Drawer(
      width: isTablet ? 360 : 300,
      backgroundColor: backgroundColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: EdgeInsets.all(isTablet ? 20 : 16),
              child: Row(
                children: [
                  Icon(
                    Icons.collections_bookmark,
                    color: AppColors.primaryBlue,
                    size: isTablet ? 26 : 22,
                  ),
                  SizedBox(width: isTablet ? 12 : 8),
                  Expanded(
                    child: Text(
                      'Bookmarks',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontWeight: FontWeight.w700,
                        fontSize: isTablet ? 20 : 17,
                        color: textColor,
                      ),
                    ),
                  ),
                  Text(
                    '${sortedPages.length}',
                    style: TextStyle(
                      fontSize: isTablet ? 15 : 13,
                      color: subtitleColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0),
            ),
            // Bookmark list
            Expanded(
              child: sortedPages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bookmark_border,
                            size: isTablet ? 48 : 40,
                            color: subtitleColor,
                          ),
                          SizedBox(height: isTablet ? 12 : 8),
                          Text(
                            'No bookmarks yet',
                            style: TextStyle(
                              fontSize: isTablet ? 16 : 14,
                              color: subtitleColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.symmetric(
                          vertical: isTablet ? 8 : 4),
                      itemCount: sortedPages.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: isTablet ? 20 : 16,
                        endIndent: isTablet ? 20 : 16,
                        color: isDark
                            ? AppColors.darkDivider
                            : const Color(0xFFF0F0F0),
                      ),
                      itemBuilder: (context, index) {
                        final page = sortedPages[index];
                        final bookmarkId = bookmarkedPages[page]!;
                        final note = bookmarkNotes[bookmarkId];

                        return _BookmarkTile(
                          pageNumber: page,
                          bookmarkId: bookmarkId,
                          note: note,
                          isDark: isDark,
                          isTablet: isTablet,
                          textColor: textColor,
                          subtitleColor: subtitleColor,
                          onTap: () => onJumpToPage(page),
                          onDelete: () =>
                              onDeleteBookmark(bookmarkId, page),
                          onEditNote: () => _showNoteDialog(
                            context,
                            bookmarkId,
                            note,
                            pageNumber: page,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNoteDialog(
      BuildContext context, String bookmarkId, String? existingNote,
      {int? pageNumber}) {
    final controller = TextEditingController(text: existingNote ?? '');

    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.black;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 20),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Title with bookmark icon
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: Row(
                    children: [
                      Container(
                        width: isTablet ? 40 : 36,
                        height: isTablet ? 40 : 36,
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          existingNote != null
                              ? Icons.edit_note
                              : Icons.note_add_outlined,
                          size: isTablet ? 22 : 20,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      SizedBox(width: isTablet ? 12 : 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              existingNote != null
                                  ? 'Edit Bookmark Note'
                                  : 'Add Bookmark Note',
                              style: TextStyle(
                                fontFamily: 'SF Pro Display',
                                fontWeight: FontWeight.w700,
                                fontSize: isTablet ? 20 : 18,
                                color: textColor,
                              ),
                            ),
                            if (pageNumber != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Page $pageNumber',
                                style: TextStyle(
                                  fontSize: isTablet ? 13 : 12,
                                  color: isDark
                                      ? AppColors.darkTextSecondary
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isTablet ? 18 : 16),
                // Styled text field
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: TextField(
                    controller: controller,
                    maxLines: 4,
                    maxLength: 500,
                    autofocus: true,
                    style: TextStyle(
                      color: textColor,
                      fontSize: isTablet ? 15 : 14,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Write your thoughts...',
                      hintStyle: TextStyle(
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : Colors.grey[400],
                        fontSize: isTablet ? 15 : 14,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? AppColors.darkSurface
                          : const Color(0xFFF8F9FE),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.primaryBlue,
                          width: 1.5,
                        ),
                      ),
                      counterStyle: TextStyle(
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : Colors.grey,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: isTablet ? 18 : 14),
                // Action buttons
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20),
                  child: Row(
                    children: [
                      if (existingNote != null)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            onUpdateNote(bookmarkId, null);
                          },
                          icon: const Icon(Icons.delete_outline,
                              size: 18),
                          label: const Text('Remove'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                          ),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(width: isTablet ? 12 : 8),
                      // Gradient save button
                      Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.blueGradient,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryBlue
                                  .withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              final note = controller.text.trim();
                              onUpdateNote(bookmarkId,
                                  note.isEmpty ? null : note);
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: isTablet ? 28 : 24,
                                vertical: isTablet ? 12 : 10,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check,
                                    size: isTablet ? 18 : 16,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: isTablet ? 6 : 4),
                                  Text(
                                    'Save',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: isTablet ? 15 : 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isTablet ? 16 : 12),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  final int pageNumber;
  final String bookmarkId;
  final String? note;
  final bool isDark;
  final bool isTablet;
  final Color textColor;
  final Color subtitleColor;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEditNote;

  const _BookmarkTile({
    required this.pageNumber,
    required this.bookmarkId,
    required this.note,
    required this.isDark,
    required this.isTablet,
    required this.textColor,
    required this.subtitleColor,
    required this.onTap,
    required this.onDelete,
    required this.onEditNote,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 20 : 16,
          vertical: isTablet ? 14 : 12,
        ),
        child: Row(
          children: [
            // Page icon
            Container(
              width: isTablet ? 40 : 34,
              height: isTablet ? 40 : 34,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
              ),
              child: Center(
                child: Text(
                  '$pageNumber',
                  style: TextStyle(
                    fontSize: isTablet ? 14 : 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
            ),
            SizedBox(width: isTablet ? 14 : 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Page $pageNumber',
                    style: TextStyle(
                      fontSize: isTablet ? 15 : 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  if (note != null && note!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      note!,
                      style: TextStyle(
                        fontSize: isTablet ? 13 : 12,
                        color: subtitleColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Note button
            GestureDetector(
              onTap: onEditNote,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  note != null ? Icons.edit_note : Icons.note_add_outlined,
                  size: isTablet ? 22 : 20,
                  color: subtitleColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Delete button
            GestureDetector(
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: isTablet ? 20 : 18,
                  color: subtitleColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

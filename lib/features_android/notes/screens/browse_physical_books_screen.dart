import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_android/models/book_model.dart';
import 'package:pgme/core_android/models/subject_model.dart';
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/services/onboarding_service.dart';
import 'package:pgme/core_android/theme/app_theme.dart';
import 'package:pgme/features_android/books/providers/book_provider.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';
import 'package:pgme/core_android/widgets/app_dialog.dart';

class BrowsePhysicalBooksScreen extends StatefulWidget {
  const BrowsePhysicalBooksScreen({super.key});

  @override
  State<BrowsePhysicalBooksScreen> createState() => _BrowsePhysicalBooksScreenState();
}

class _BrowsePhysicalBooksScreenState extends State<BrowsePhysicalBooksScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<SubjectModel> _subjects = [];
  String? _selectedSubjectId;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<BookProvider>(context, listen: false);
      if (provider.books.isEmpty) {
        provider.loadBooks();
      }
    });

    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadSubjects() async {
    try {
      final subjects = await OnboardingService().getSubjects();
      if (mounted) {
        setState(() => _subjects = subjects);
      }
    } catch (e) {
      debugPrint('Error loading subjects: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final provider = Provider.of<BookProvider>(context, listen: false);
      provider.loadMoreBooks();
    }
  }

  void _onSearch(String query) {
    final provider = Provider.of<BookProvider>(context, listen: false);
    if (query.isEmpty) {
      provider.loadBooks(subjectId: _selectedSubjectId, refresh: true);
    } else {
      provider.loadBooks(subjectId: _selectedSubjectId, search: query, refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final cardBgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final surfaceColor = isDark ? AppColors.darkSurface : Colors.white;
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);
    final buttonColor = isDark ? const Color(0xFF1A1A4D) : const Color(0xFF000080);
    final cardFooterBgColor = isDark ? AppColors.darkCardBackground : const Color(0xFFE4F4FF);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: EdgeInsets.only(top: topPadding + (isTablet ? 21 : 16), left: hPadding, right: hPadding),
            child: Row(
              children: [
                // Back Arrow
                GestureDetector(
                  onTap: () => context.pop(),
                  child: SizedBox(
                    width: isTablet ? 30 : 24,
                    height: isTablet ? 30 : 24,
                    child: Icon(
                      Icons.arrow_back,
                      size: isTablet ? 30 : 24,
                      color: textColor,
                    ),
                  ),
                ),
                const Spacer(),
                // Title
                Text(
                  Platform.isIOS ? 'Browse Books' : 'Order Books',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 25 : 20,
                    height: 1.0,
                    letterSpacing: -0.5,
                    color: textColor,
                  ),
                ),
                const Spacer(),
                // Cart icon with badge
                Consumer<BookProvider>(
                  builder: (context, provider, _) {
                    return GestureDetector(
                      onTap: () => context.push('/book-cart'),
                      child: Stack(
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: isTablet ? 30 : 24,
                            color: textColor,
                          ),
                          if (provider.cartItemCount > 0)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: EdgeInsets.all(isTablet ? 3 : 2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(isTablet ? 12 : 10),
                                ),
                                constraints: BoxConstraints(
                                  minWidth: isTablet ? 20 : 16,
                                  minHeight: isTablet ? 20 : 16,
                                ),
                                child: Text(
                                  '${provider.cartItemCount}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: isTablet ? 12 : 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          SizedBox(height: isTablet ? 21 : 16),

          // Search Bar
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hPadding),
            child: Container(
              width: double.infinity,
              height: isTablet ? 56 : 48,
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(isTablet ? 23 : 18),
                border: Border.all(
                  color: iconColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(width: isTablet ? 20 : 16),
                  Icon(
                    Icons.search,
                    size: isTablet ? 30 : 24,
                    color: secondaryTextColor,
                  ),
                  SizedBox(width: isTablet ? 16 : 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearch,
                      decoration: InputDecoration(
                        hintText: 'Search the book you want...',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 15 : 12,
                          fontWeight: FontWeight.w500,
                          height: 20 / 12,
                          letterSpacing: -0.5,
                          color: textColor.withValues(alpha: 0.4),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isTablet ? 15 : 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.5,
                        color: textColor,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _onSearch('');
                      },
                      child: Icon(
                        Icons.close,
                        size: isTablet ? 25 : 20,
                        color: secondaryTextColor,
                      ),
                    ),
                  SizedBox(width: isTablet ? 20 : 16),
                ],
              ),
            ),
          ),

          // Subject filter chips
          if (_subjects.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: isTablet ? 21 : 16),
              child: SizedBox(
                height: isTablet ? 44 : 36,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  itemCount: _subjects.length + 1,
                  itemBuilder: (context, index) {
                    final isAll = index == 0;
                    final isSelected = isAll
                        ? _selectedSubjectId == null
                        : _selectedSubjectId == _subjects[index - 1].subjectId;
                    final label = isAll ? 'All' : _subjects[index - 1].name;

                    return Padding(
                      padding: EdgeInsets.only(right: isTablet ? 10 : 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedSubjectId = isAll ? null : _subjects[index - 1].subjectId;
                          });
                          final provider = Provider.of<BookProvider>(context, listen: false);
                          provider.loadBooks(
                            subjectId: _selectedSubjectId,
                            search: _searchController.text.isNotEmpty ? _searchController.text : null,
                            refresh: true,
                          );
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: isTablet ? 18 : 14, vertical: isTablet ? 10 : 7),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? iconColor
                                : (isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5)),
                            borderRadius: BorderRadius.circular(isTablet ? 22 : 18),
                            border: Border.all(
                              color: isSelected
                                  ? iconColor
                                  : borderColor,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              fontSize: isTablet ? 14 : 12,
                              color: isSelected
                                  ? Colors.white
                                  : secondaryTextColor,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          SizedBox(height: _subjects.isEmpty ? (isTablet ? 21 : 16) : 0),

          // Books Grid
          Expanded(
            child: Consumer<BookProvider>(
              builder: (context, provider, _) {
                if (provider.isLoadingBooks && provider.books.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.booksError != null && provider.books.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: isTablet ? 64 : 48, color: secondaryTextColor),
                        SizedBox(height: isTablet ? 21 : 16),
                        Text(
                          provider.booksError!,
                          style: TextStyle(color: secondaryTextColor, fontSize: isTablet ? 17 : 14),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: isTablet ? 21 : 16),
                        ElevatedButton(
                          onPressed: () => provider.loadBooks(subjectId: _selectedSubjectId, refresh: true),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (provider.books.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.menu_book_outlined, size: isTablet ? 64 : 48, color: secondaryTextColor),
                        SizedBox(height: isTablet ? 21 : 16),
                        Text(
                          'No books available',
                          style: TextStyle(
                            color: secondaryTextColor,
                            fontSize: isTablet ? 20 : 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => provider.loadBooks(subjectId: _selectedSubjectId, refresh: true),
                  child: GridView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                    padding: EdgeInsets.only(left: hPadding, right: hPadding, bottom: bottomPadding + (isTablet ? 130 : 100)),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isTablet ? 3 : 2,
                      crossAxisSpacing: isTablet ? 20 : 16,
                      mainAxisSpacing: isTablet ? 20 : 16,
                      childAspectRatio: 16 / 9,
                    ),
                    itemCount: provider.books.length + (provider.pagination?.hasNext == true ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= provider.books.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final book = provider.books[index];
                      return _buildBookCard(
                        context: context,
                        book: book,
                        provider: provider,
                        isDark: isDark,
                        isTablet: isTablet,
                        textColor: textColor,
                        cardBgColor: cardBgColor,
                        borderColor: borderColor,
                        cardFooterBgColor: cardFooterBgColor,
                        buttonColor: buttonColor,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildBookCard({
    required BuildContext context,
    required BookModel book,
    required BookProvider provider,
    required bool isDark,
    required bool isTablet,
    required Color textColor,
    required Color cardBgColor,
    required Color borderColor,
    required Color cardFooterBgColor,
    required Color buttonColor,
  }) {
    final placeholderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final isInCart = provider.isInCart(book.bookId);

    final cardRadius = isTablet ? 20.0 : 14.0;
    final footerPadH = isTablet ? 14.0 : 8.0;
    final footerPadV = isTablet ? 12.0 : 6.0;
    final titleSize = isTablet ? 18.0 : 12.0;
    final authorSize = isTablet ? 15.0 : 10.0;
    final priceSize = isTablet ? 20.0 : 14.0;
    final strikePriceSize = isTablet ? 15.0 : 10.0;
    final btnHeight = isTablet ? 42.0 : 30.0;
    final btnFontSize = isTablet ? 15.0 : 12.0;
    final btnRadius = isTablet ? 12.0 : 7.0;
    final placeholderW = isTablet ? 100.0 : 71.0;
    final placeholderH = isTablet ? 96.0 : 68.0;
    final placeholderIcon = isTablet ? 44.0 : 32.0;

    return GestureDetector(
      onTap: () => context.push('/book/${book.bookId}'),
      child: Container(
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(cardRadius),
          border: Border.all(
            color: borderColor,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            // Upper part - with image
            Expanded(
              flex: 163,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(cardRadius),
                    topRight: Radius.circular(cardRadius),
                  ),
                ),
                child: book.thumbnailUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(cardRadius),
                          topRight: Radius.circular(cardRadius),
                        ),
                        child: Image.network(
                          book.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Container(
                              width: placeholderW,
                              height: placeholderH,
                              color: placeholderColor,
                              child: Icon(
                                Icons.menu_book,
                                size: placeholderIcon,
                                color: textColor.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Container(
                          width: placeholderW,
                          height: placeholderH,
                          color: placeholderColor,
                          child: Icon(
                            Icons.menu_book,
                            size: placeholderIcon,
                            color: textColor.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
              ),
            ),
            // Lower part - with details
            Expanded(
              flex: isTablet ? 135 : 121,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cardFooterBgColor,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(cardRadius),
                    bottomRight: Radius.circular(cardRadius),
                  ),
                ),
                padding: EdgeInsets.symmetric(horizontal: footerPadH, vertical: footerPadV),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Book Name
                    Text(
                      book.title,
                      maxLines: isTablet ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: titleSize,
                        height: 1.2,
                        color: textColor,
                      ),
                    ),
                    SizedBox(height: isTablet ? 2 : 0),
                    // Author Name
                    Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: authorSize,
                        height: 1.2,
                        color: textColor.withValues(alpha: 0.5),
                      ),
                    ),
                    SizedBox(height: isTablet ? 8 : 4),
                    // Price
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '\u{20B9}${book.actualPrice}',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: priceSize,
                              height: 1.2,
                              color: textColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (book.hasDiscount) ...[
                          SizedBox(width: isTablet ? 6 : 4),
                          Text(
                            '\u{20B9}${book.originalPrice}',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w400,
                              fontSize: strikePriceSize,
                              height: 1.2,
                              color: textColor.withValues(alpha: 0.5),
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Spacer(),
                    // Add to Cart / In Cart Button
                    GestureDetector(
                      onTap: () {
                        if (!isInCart) {
                          provider.addToCart(book);
                          showAppDialog(context, message: '${book.title} added to cart', type: AppDialogType.info, actionLabel: 'View Cart', onAction: () => context.push('/book-cart'));
                        } else {
                          context.push('/book-cart');
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: btnHeight,
                        decoration: BoxDecoration(
                          color: isInCart ? Colors.green : buttonColor,
                          borderRadius: BorderRadius.circular(btnRadius),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: isTablet ? 8 : 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isTablet)
                              Icon(
                                isInCart ? Icons.check : Icons.add_shopping_cart,
                                size: 18,
                                color: Colors.white,
                              ),
                            if (isTablet) const SizedBox(width: 6),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                isInCart ? 'In Cart' : (isTablet ? 'Add to Cart' : 'Add'),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w500,
                                  fontSize: btnFontSize,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

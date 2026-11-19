import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pgme/core/widgets/app_scaffold.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/models/book_model.dart';
import 'package:pgme/core/models/gateway_models.dart';
import 'package:pgme/core/services/book_service.dart';
import 'package:pgme/core/services/ebook_access_service.dart';
import 'package:pgme/core/services/download_service.dart';
import 'package:pgme/core/services/storage_service.dart';
import 'package:pgme/core/utils/epub_file.dart';
import 'package:pgme/core/services/pdf_cache_service.dart';
import 'package:pgme/core/widgets/gateway_widget.dart';
import 'package:pgme/core/widgets/address_bottom_sheet.dart';
import 'package:pgme/core/models/address_model.dart';
import 'package:pgme/core/services/user_service.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/utils/web_store_launcher.dart';
import 'package:pgme/core/widgets/app_dialog.dart';
import 'package:pgme/core/models/subject_model.dart';
import 'package:pgme/core/services/onboarding_service.dart';

class EbookListScreen extends StatefulWidget {
  final String? initialBookId;
  const EbookListScreen({super.key, this.initialBookId});

  @override
  State<EbookListScreen> createState() => _EbookListScreenState();
}

class _EbookListScreenState extends State<EbookListScreen>
    with WidgetsBindingObserver {
  final BookService _bookService = BookService();
  final EbookAccessService _ebookOrderService = EbookAccessService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<BookModel> _ebooks = [];
  Set<String> _purchasedBookIds = {};
  List<SubjectModel> _subjects = [];
  String? _selectedSubjectId;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isPurchasing = false;
  String? _readingBookId;
  String? _error;
  String _searchQuery = '';
  int _currentPage = 1;
  bool _hasMore = true;

  bool _initialBookHandled = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) WidgetsBinding.instance.addObserver(this);
    _loadInitialData();
    _loadSubjects();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadInitialData() async {
    await Future.wait([_loadEbooks(), _loadPurchasedEbooks()]);
    if (widget.initialBookId != null && !_initialBookHandled && mounted) {
      _initialBookHandled = true;
      _openInitialBook(widget.initialBookId!);
    }
  }

  Future<void> _openInitialBook(String bookId) async {
    try {
      final book = await _bookService.getBookById(bookId);
      if (!mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final isTablet = ResponsiveHelper.isTablet(context);
      final isPurchased = _purchasedBookIds.contains(book.bookId);
      _showBookDetailModal(book, isPurchased: isPurchased, isDark: isDark, isTablet: isTablet);
    } catch (e) {
      debugPrint('Error opening initial book: $e');
    }
  }

  @override
  void dispose() {
    if (Platform.isIOS) WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed &&
        WebStoreLauncher.awaitingExternalPurchase) {
      WebStoreLauncher.clearAwaitingPurchase();
      _loadEbooks();
      _loadPurchasedEbooks();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
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

  Future<void> _loadEbooks({bool reset = true}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _currentPage = 1;
      });
    }

    try {
      final response = await _bookService.getBooks(
        ebook: true,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        subjectId: _selectedSubjectId,
        page: _currentPage,
        limit: 20,
      );

      if (mounted) {
        setState(() {
          if (reset) {
            _ebooks = response.books;
          } else {
            _ebooks.addAll(response.books);
          }
          _hasMore = response.pagination.hasNext;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    _currentPage++;
    await _loadEbooks(reset: false);
  }

  Future<void> _loadPurchasedEbooks() async {
    try {
      final purchased = await _ebookOrderService.getUserAccessibleEbooks();
      if (mounted) {
        setState(() {
          _purchasedBookIds = purchased.map((e) => e.bookId).toSet();
        });
      }
    } catch (e) {
      debugPrint('Error loading purchased ebooks: $e');
    }
  }

  String _formatPrice(int price) {
    if (Platform.isIOS) return '';
    return '₹${price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  Future<void> _handleBuy(BookModel book) async {
    if (_isPurchasing) return;

    // iOS: redirect to web store to avoid Apple IAP requirement
    if (WebStoreLauncher.shouldUseWebStore) {
      WebStoreLauncher.openProductPage(
        context,
        productType: 'ebooks',
        productId: book.bookId,
      );
      return;
    }

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDark = themeProvider.isDarkMode;

    // Show confirmation dialog
    final shouldBuy = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) => _buildBuyDialog(dialogContext, book, isDark),
    );

    if (shouldBuy != true || !mounted) return;

    // Show billing address bottom sheet before payment
    Address? savedAddress;
    try {
      final user = await UserService().getProfile();
      if (user.billingAddress != null && user.billingAddress!.isNotEmpty) {
        savedAddress = Address.fromJson(user.billingAddress!);
      }
    } catch (_) {}

    if (!mounted) return;

    final addressResult = await showAddressSheet(
      context,
      initialAddress: savedAddress,
      couponPurchaseType: 'ebook',
      couponProductId: book.bookId,
    );

    if (addressResult == null || !mounted) return;
    final billingAddress = addressResult['billing']!;
    final couponCode = addressResult['coupon_code'] as String?;
    final termsAccepted = addressResult['terms_accepted'] as bool?;

    setState(() => _isPurchasing = true);

    try {
      // Step 1: Create payment session
      final paymentSession = await _ebookOrderService.initSession(
        book.bookId,
        billingAddress: billingAddress.toJson(),
        couponCode: couponCode,
        termsAccepted: termsAccepted,
      );

      if (!mounted) return;

      // Step 2: Show Zoho payment widget
      final result = await Navigator.of(context, rootNavigator: true).push<GatewayResponse>(
        MaterialPageRoute(
          builder: (context) => GatewayWidget(
            paymentSession: paymentSession,
            onPaymentComplete: (response) {
              Navigator.pop(context, response);
            },
          ),
          fullscreenDialog: true,
        ),
      );

      // Step 3: Handle payment response
      if (result != null && mounted) {
        if (result.isSuccess) {
          final verification = await _ebookOrderService.confirmSession(
            paymentSessionId: result.paymentSessionId!,
            paymentId: result.paymentId!,
            signature: result.signature,
          );

          if (verification.success && mounted) {
            setState(() {
              _purchasedBookIds.add(book.bookId);
              _isPurchasing = false;
            });
            _showSuccess(Platform.isIOS ? 'eBook unlocked successfully!' : 'eBook purchased successfully!');
          } else if (mounted) {
            _showError(Platform.isIOS ? 'Verification failed. Please contact support.' : 'Payment verification failed. Please contact support.');
          }
        } else if (result.isFailed) {
          _showError(Platform.isIOS ? 'Failed: ${result.errorMessage ?? "Unknown error"}' : 'Payment failed: ${result.errorMessage ?? "Unknown error"}');
        } else if (result.isCancelled) {
          _showInfo(Platform.isIOS ? 'Cancelled' : 'Payment cancelled');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Error: ${e.toString().replaceAll("Exception: ", "")}');
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _handleRead(BookModel book) async {
    if (_readingBookId != null) return;
    setState(() => _readingBookId = book.bookId);
    try {
      final data = await _ebookOrderService.getEbookViewUrl(book.bookId);
      if (mounted) {
        final url = data['url'] as String?;
        final title = data['title'] as String? ?? book.title;
        final fileFormat = (data['file_format'] as String? ?? 'pdf').toLowerCase();
        if (url != null) {
          if (fileFormat == 'epub') {
            context.pushNamed(
              'epub-viewer',
              queryParameters: {
                'documentId': book.bookId,
                'epubUrl': url,
                'title': title,
              },
            );
          } else {
            context.pushNamed(
              'pdf-viewer',
              queryParameters: {
                'documentId': book.bookId,
                'pdfUrl': url,
                'title': title,
                'source': 'ebook',
              },
            );
          }
        }
      }
    } catch (e) {
      if (isNoConnectionError(e) &&
          book.ebookFileFormat?.toLowerCase() == 'epub') {
        final userId = await StorageService().getUserId();
        final path = userId == null ? null : await DownloadService().getDownloadedPath(
            epubDownloadFileName(userId, book.bookId, isDocument: false));
        if (path != null && await isEpubArchive(File(path))) {
          if (mounted) {
            context.pushNamed('epub-viewer', queryParameters: {
              'documentId': book.bookId,
              'title': book.title,
            });
          }
          return;
        }
      }
      // Offline: a PDF already on this device still opens (the reader falls
      // back to it when the server can't be reached).
      if (isNoConnectionError(e) &&
          await PdfCacheService.isAvailableOffline(book.bookId)) {
        if (mounted) {
          context.pushNamed('pdf-viewer', queryParameters: {
            'documentId': book.bookId,
            'title': book.title,
            'source': 'ebook',
          });
        }
        return;
      }
      if (mounted) {
        _showError('Failed to open eBook: ${e.toString().replaceAll("Exception: ", "")}');
      }
    } finally {
      if (mounted) setState(() => _readingBookId = null);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showAppDialog(context, message: message);
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    showAppDialog(context, message: message, type: AppDialogType.success);
  }

  void _showInfo(String message) {
    if (!mounted) return;
    showAppDialog(context, message: message, type: AppDialogType.info);
  }

  Widget _buildBuyDialog(BuildContext dialogContext, BookModel book, bool isDark) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final dialogBgColor = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final buttonColor = isDark ? const Color(0xFF0047CF) : const Color(0xFF0000D1);
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);

    final dialogRadius = isTablet ? 28.0 : 20.0;
    final titleSize = isTablet ? 22.0 : 18.0;
    final descSize = isTablet ? 15.0 : 13.0;
    final priceSize = isTablet ? 28.0 : 22.0;
    final btnFontSize = isTablet ? 18.0 : 15.0;
    final btnRadius = isTablet ? 14.0 : 10.0;
    final hPad = isTablet ? 28.0 : 20.0;
    final imgHeight = isTablet ? 160.0 : 120.0;
    final imgWidth = imgHeight * 16 / 9;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isTablet ? 80 : 32,
        vertical: isTablet ? 40 : 24,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: dialogBgColor,
          borderRadius: BorderRadius.circular(dialogRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.18),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(dialogRadius),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Book info ───────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, isTablet ? 24 : 20, hPad, isTablet ? 20 : 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Close button
                    Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        onTap: () => Navigator.of(dialogContext).pop(false),
                        child: Container(
                          width: isTablet ? 32 : 28,
                          height: isTablet ? 32 : 28,
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close, size: isTablet ? 18 : 16, color: secondaryTextColor),
                        ),
                      ),
                    ),

                    SizedBox(height: isTablet ? 12 : 10),

                    // Book thumbnail (centered, original large size)
                    if (book.thumbnailUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
                        child: CachedNetworkImage(
                          imageUrl: book.thumbnailUrl!,
                          width: imgWidth,
                          height: imgHeight,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: imgWidth,
                            height: imgHeight,
                            color: isDark ? AppColors.darkCardBackground : const Color(0xFFF0F0F0),
                            child: Icon(Icons.menu_book, size: isTablet ? 40 : 30, color: secondaryTextColor),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: imgWidth,
                            height: imgHeight,
                            color: isDark ? AppColors.darkCardBackground : const Color(0xFFF0F0F0),
                            child: Icon(Icons.menu_book, size: isTablet ? 40 : 30, color: secondaryTextColor),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: imgWidth,
                        height: imgHeight,
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkCardBackground : const Color(0xFFF0F0F0),
                          borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
                        ),
                        child: Icon(Icons.menu_book, size: isTablet ? 40 : 30, color: secondaryTextColor),
                      ),

                    SizedBox(height: isTablet ? 18 : 14),

                    // Title
                    Text(
                      book.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: titleSize,
                        color: textColor,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    SizedBox(height: isTablet ? 6 : 4),

                    // Author
                    Text(
                      book.author,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: descSize,
                        color: secondaryTextColor,
                      ),
                    ),

                    SizedBox(height: isTablet ? 16 : 12),
                    Divider(height: 1, color: borderColor),
                    SizedBox(height: isTablet ? 16 : 12),

                    // Price
                    Text(
                      _formatPrice(book.actualPrice),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: priceSize,
                        color: textColor,
                      ),
                    ),

                    if (book.hasDiscount) ...[
                      SizedBox(height: isTablet ? 4 : 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _formatPrice(book.originalPrice ?? book.price),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: descSize,
                              color: secondaryTextColor,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          SizedBox(width: isTablet ? 8 : 6),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: isTablet ? 8 : 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${book.discount}% OFF',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 12 : 10,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF4CAF50),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // ── Separator ───────────────────────────────────────────────
              Container(height: 1, color: borderColor),

              // ── Buttons — GestureDetector+Container, padding-based height
              // ElevatedButton uses Material(clipBehavior: Clip.antiAlias) which
              // clips text when SizedBox height is tight. This approach never clips.
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, isTablet ? 16 : 14, hPad, isTablet ? 24 : 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(dialogContext).pop(true),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(vertical: isTablet ? 16 : 14),
                        decoration: BoxDecoration(
                          color: buttonColor,
                          borderRadius: BorderRadius.circular(btnRadius),
                        ),
                        child: Center(
                          child: Text(
                            Platform.isIOS ? 'Learn More' : 'Buy Now',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: btnFontSize,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: isTablet ? 10 : 8),
                    GestureDetector(
                      onTap: () => Navigator.of(dialogContext).pop(false),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(vertical: isTablet ? 15 : 13),
                        decoration: BoxDecoration(
                          border: Border.all(color: borderColor, width: 1.5),
                          borderRadius: BorderRadius.circular(btnRadius),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w500,
                              fontSize: btnFontSize,
                              color: secondaryTextColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final searchBarColor = isDark ? AppColors.darkSurface : Colors.white;
    final searchBarBorderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Center(
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
                        GestureDetector(
                          onTap: () => context.pop(),
                          child: Icon(
                            Icons.arrow_back_ios_new,
                            size: isTablet ? 24 : 20,
                            color: textColor,
                          ),
                        ),
                        SizedBox(width: isTablet ? 16 : 12),
                        Text(
                          'eBook Store',
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
                        GestureDetector(
                          onTap: () {
                            _loadEbooks();
                            _loadPurchasedEbooks();
                          },
                          child: Icon(
                            Icons.refresh,
                            size: isTablet ? 28 : 24,
                            color: textColor,
                          ),
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
                        color: searchBarColor,
                        borderRadius: BorderRadius.circular(isTablet ? 23 : 18),
                        border: Border.all(color: searchBarBorderColor, width: 1),
                      ),
                      child: Row(
                        children: [
                          SizedBox(width: isTablet ? 20 : 16),
                          Icon(Icons.search, size: isTablet ? 30 : 24, color: secondaryTextColor),
                          SizedBox(width: isTablet ? 16 : 12),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (value) {
                                _searchQuery = value;
                              },
                              onSubmitted: (_) => _loadEbooks(),
                              decoration: InputDecoration(
                                hintText: 'Search eBooks...',
                                hintStyle: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: isTablet ? 15 : 12,
                                  fontWeight: FontWeight.w500,
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
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                _searchQuery = '';
                                _loadEbooks();
                              },
                              child: Icon(Icons.clear, size: isTablet ? 24 : 20, color: secondaryTextColor),
                            ),
                          SizedBox(width: isTablet ? 20 : 16),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: isTablet ? 12 : 8),

                  // Subject filter chips
                  if (_subjects.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(bottom: isTablet ? 12 : 8),
                      child: SizedBox(
                        height: isTablet ? 40 : 34,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(horizontal: hPadding),
                          itemCount: _subjects.length + 1,
                          separatorBuilder: (_, __) => SizedBox(width: isTablet ? 10 : 8),
                          itemBuilder: (context, index) {
                            final isAll = index == 0;
                            final isSelected = isAll
                                ? _selectedSubjectId == null
                                : _selectedSubjectId == _subjects[index - 1].subjectId;
                            final label = isAll ? 'All' : _subjects[index - 1].name;

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedSubjectId = isAll ? null : _subjects[index - 1].subjectId;
                                });
                                _loadEbooks();
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 12, vertical: isTablet ? 8 : 6),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? iconColor
                                      : (isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5)),
                                  borderRadius: BorderRadius.circular(isTablet ? 20 : 17),
                                  border: isSelected
                                      ? null
                                      : Border.all(color: isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0), width: 1),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                    fontSize: isTablet ? 13 : 11,
                                    color: isSelected
                                        ? Colors.white
                                        : (isDark ? AppColors.darkTextSecondary : const Color(0xFF666666)),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  // Content
                  Expanded(
                    child: _isLoading
                        ? Center(child: CircularProgressIndicator(color: iconColor))
                        : _error != null
                            ? _buildErrorState(textColor, secondaryTextColor, iconColor, isTablet)
                            : _ebooks.isEmpty
                                ? _buildEmptyState(textColor, secondaryTextColor, isTablet)
                                : RefreshIndicator(
                                    onRefresh: () async {
                                      await _loadEbooks();
                                      await _loadPurchasedEbooks();
                                    },
                                    child: GridView.builder(
                                      controller: _scrollController,
                                      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                                      // Clear the floating bottom nav (and mini
                                      // player) so the last row's Read button
                                      // is never covered.
                                      padding: EdgeInsets.only(
                                        left: hPadding,
                                        right: hPadding,
                                        bottom: AppScaffold.bottomContentInset(context),
                                      ),
                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: isTablet ? 3 : 2,
                                        crossAxisSpacing: isTablet ? 16 : 12,
                                        mainAxisSpacing: isTablet ? 16 : 12,
                                        childAspectRatio: isTablet ? 0.58 : 0.52,
                                      ),
                                      itemCount: _ebooks.length + (_isLoadingMore ? 1 : 0),
                                      itemBuilder: (context, index) {
                                        if (index == _ebooks.length) {
                                          return Center(
                                            child: Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: CircularProgressIndicator(color: iconColor),
                                            ),
                                          );
                                        }
                                        return _buildEbookCard(
                                          _ebooks[index],
                                          isDark: isDark,
                                          isTablet: isTablet,
                                          textColor: textColor,
                                          secondaryTextColor: secondaryTextColor,
                                          iconColor: iconColor,
                                        );
                                      },
                                    ),
                                  ),
                  ),
                ],
              ),
            ),
          ),

          // Loading overlay during purchase
          if (_isPurchasing)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Color textColor, Color secondaryTextColor, Color iconColor, bool isTablet) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: isTablet ? 64 : 48, color: secondaryTextColor),
          SizedBox(height: isTablet ? 21 : 16),
          Text(
            'Failed to load eBooks',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: isTablet ? 20 : 16,
              color: textColor,
            ),
          ),
          SizedBox(height: isTablet ? 10 : 8),
          Text(
            _error!.replaceAll('Exception: ', ''),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: isTablet ? 15 : 12,
              color: secondaryTextColor,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: isTablet ? 21 : 16),
          ElevatedButton(
            onPressed: _loadEbooks,
            style: ElevatedButton.styleFrom(backgroundColor: iconColor),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color textColor, Color secondaryTextColor, bool isTablet) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: isTablet ? 80 : 64,
            color: secondaryTextColor,
          ),
          SizedBox(height: isTablet ? 21 : 16),
          Text(
            'No eBooks available',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: isTablet ? 20 : 16,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
          SizedBox(height: isTablet ? 10 : 8),
          Text(
            'Check back later for new eBooks',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: isTablet ? 17 : 14,
              color: secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEbookCard(
    BookModel book, {
    required bool isDark,
    required bool isTablet,
    required Color textColor,
    required Color secondaryTextColor,
    required Color iconColor,
  }) {
    final isPurchased = _purchasedBookIds.contains(book.bookId);
    final cardBgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE8EEF4);
    final buttonColor = isDark ? const Color(0xFF0047CF) : const Color(0xFF0000D1);
    const purchasedColor = Color(0xFF4CAF50);

    final titleSize = isTablet ? 15.0 : 13.0;
    final metaSize = isTablet ? 12.0 : 10.0;
    final priceSize = isTablet ? 16.0 : 14.0;
    final btnFontSize = isTablet ? 14.0 : 12.0;
    final cardRadius = isTablet ? 16.0 : 12.0;
    final imgHeight = isTablet ? 160.0 : 130.0;

    return GestureDetector(
      onTap: isPurchased
          ? () => _handleRead(book)
          : () => _showBookDetailModal(book, isPurchased: isPurchased, isDark: isDark, isTablet: isTablet),
      child: Container(
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(cardRadius),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(cardRadius),
                topRight: Radius.circular(cardRadius),
              ),
              child: book.thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: book.thumbnailUrl!,
                      width: double.infinity,
                      height: imgHeight,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => _buildPlaceholder(imgHeight, isDark, secondaryTextColor),
                      errorWidget: (context, url, error) => _buildPlaceholder(imgHeight, isDark, secondaryTextColor),
                    )
                  : _buildPlaceholder(imgHeight, isDark, secondaryTextColor),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isTablet ? 12 : 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      book.title,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: titleSize,
                        height: 1.2,
                        color: textColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    SizedBox(height: isTablet ? 4 : 2),

                    // Author
                    Text(
                      book.author,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: metaSize,
                        color: secondaryTextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Subject badge. Not Flexible: a Flexible here shared the
                    // card's free space with the Spacer below, so cards with
                    // a subject had their Read/Buy button lifted half-way up
                    // and buttons in the same row did not line up.
                    if (book.subject != null) ...[
                      SizedBox(height: isTablet ? 4 : 3),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: isTablet ? 7 : 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          book.subject!.name,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: isTablet ? 10 : 9,
                            color: iconColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],

                    const Spacer(),

                    // Format badge + pages
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: isTablet ? 6 : 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            (book.ebookFileFormat ?? 'PDF').toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isTablet ? 10 : 9,
                              fontWeight: FontWeight.w600,
                              color: iconColor,
                            ),
                          ),
                        ),
                        SizedBox(width: isTablet ? 8 : 6),
                        if (book.pages != null)
                          Flexible(
                            child: Text(
                              '${book.pages} pages',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: metaSize,
                                color: secondaryTextColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),

                    SizedBox(height: isTablet ? 8 : 6),

                    // Price + Buy/Read button
                    if (isPurchased)
                      SizedBox(
                        width: double.infinity,
                        height: isTablet ? 36 : 32,
                        child: ElevatedButton.icon(
                          onPressed: _readingBookId == book.bookId ? null : () => _handleRead(book),
                          icon: _readingBookId == book.bookId
                              ? SizedBox(
                                  width: isTablet ? 16 : 13,
                                  height: isTablet ? 16 : 13,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(Icons.menu_book, size: isTablet ? 18 : 14),
                          label: Text(
                            _readingBookId == book.bookId ? 'Opening...' : 'Read',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: btnFontSize,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: purchasedColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: purchasedColor.withValues(alpha: 0.7),
                            disabledForegroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                            ),
                            elevation: 0,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          // Price
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatPrice(book.actualPrice),
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    fontSize: priceSize,
                                    color: textColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (book.hasDiscount)
                                  Text(
                                    _formatPrice(book.originalPrice ?? book.price),
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: metaSize,
                                      color: secondaryTextColor,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          // Buy button
                          SizedBox(
                            height: isTablet ? 36 : 32,
                            child: ElevatedButton(
                              onPressed: () => _handleBuy(book),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: buttonColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                                ),
                                elevation: 0,
                                padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 12),
                              ),
                              child: Text(
                                Platform.isIOS ? 'View' : 'Buy',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600,
                                  fontSize: btnFontSize,
                                ),
                              ),
                            ),
                          ),
                        ],
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

  void _showBookDetailModal(BookModel book, {required bool isPurchased, required bool isDark, required bool isTablet}) {
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);
    final sheetBgColor = isDark ? AppColors.darkSurface : Colors.white;
    final buttonColor = isDark ? const Color(0xFF0047CF) : const Color(0xFF0000D1);
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    const purchasedColor = Color(0xFF4CAF50);

    final imgHeight = isTablet ? 200.0 : 160.0;
    final hPad = isTablet ? 28.0 : 20.0;
    final titleSize = isTablet ? 22.0 : 18.0;
    final descSize = isTablet ? 15.0 : 13.0;
    final metaSize = isTablet ? 13.0 : 11.0;
    final priceSize = isTablet ? 26.0 : 20.0;
    final btnFontSize = isTablet ? 18.0 : 15.0;
    final btnRadius = isTablet ? 14.0 : 10.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: sheetBgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Scrollable content
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Book image (centered)
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
                          child: book.thumbnailUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: book.thumbnailUrl!,
                                  width: imgHeight * 16 / 9,
                                  height: imgHeight,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    width: imgHeight * 16 / 9,
                                    height: imgHeight,
                                    color: isDark ? AppColors.darkCardBackground : const Color(0xFFF0F0F0),
                                    child: Icon(Icons.menu_book, size: isTablet ? 40 : 30, color: secondaryTextColor),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    width: imgHeight * 16 / 9,
                                    height: imgHeight,
                                    color: isDark ? AppColors.darkCardBackground : const Color(0xFFF0F0F0),
                                    child: Icon(Icons.menu_book, size: isTablet ? 40 : 30, color: secondaryTextColor),
                                  ),
                                )
                              : Container(
                                  width: imgHeight * 16 / 9,
                                  height: imgHeight,
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.darkCardBackground : const Color(0xFFF0F0F0),
                                    borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
                                  ),
                                  child: Icon(Icons.menu_book, size: isTablet ? 40 : 30, color: secondaryTextColor),
                                ),
                        ),
                      ),

                      SizedBox(height: isTablet ? 20 : 16),

                      // Title
                      Text(
                        book.title,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: titleSize,
                          height: 1.3,
                          color: textColor,
                        ),
                      ),

                      SizedBox(height: isTablet ? 4 : 2),

                      // Author
                      Text(
                        book.author,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: descSize,
                          color: secondaryTextColor,
                        ),
                      ),

                      SizedBox(height: isTablet ? 12 : 8),

                      // Meta row: format, pages, publisher
                      Wrap(
                        spacing: isTablet ? 12 : 8,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: isTablet ? 8 : 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              (book.ebookFileFormat ?? 'PDF').toUpperCase(),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: metaSize,
                                fontWeight: FontWeight.w600,
                                color: iconColor,
                              ),
                            ),
                          ),
                          if (book.pages != null)
                            Text(
                              '${book.pages} pages',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: metaSize,
                                color: secondaryTextColor,
                              ),
                            ),
                          if (book.publisher != null)
                            Text(
                              book.publisher!,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: metaSize,
                                color: secondaryTextColor,
                              ),
                            ),
                          if (book.subject != null)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: isTablet ? 8 : 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: iconColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                book.subject!.name,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: metaSize,
                                  fontWeight: FontWeight.w500,
                                  color: iconColor,
                                ),
                              ),
                            ),
                        ],
                      ),

                      // Description
                      if (book.description != null && book.description!.isNotEmpty) ...[
                        SizedBox(height: isTablet ? 16 : 12),
                        Divider(height: 1, color: borderColor),
                        SizedBox(height: isTablet ? 16 : 12),
                        Text(
                          book.description!,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w400,
                            fontSize: descSize,
                            height: 1.5,
                            color: textColor,
                          ),
                        ),
                      ],

                      SizedBox(height: isTablet ? 24 : 20),
                    ],
                  ),
                ),
              ),

              // Bottom action bar
              Container(
                padding: EdgeInsets.fromLTRB(
                  hPad,
                  isTablet ? 16 : 12,
                  hPad,
                  (isTablet ? 20.0 : 16.0) + MediaQuery.of(sheetContext).padding.bottom,
                ),
                decoration: BoxDecoration(
                  color: sheetBgColor,
                  border: Border(top: BorderSide(color: borderColor, width: 1)),
                ),
                child: isPurchased
                    ? SizedBox(
                        width: double.infinity,
                        height: isTablet ? 52 : 46,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _handleRead(book);
                          },
                          icon: Icon(Icons.menu_book, size: isTablet ? 20 : 18),
                          label: Text(
                            'Read Now',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: btnFontSize,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: purchasedColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(btnRadius),
                            ),
                            elevation: 0,
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          // Price section
                          if (!Platform.isIOS)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatPrice(book.actualPrice),
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w700,
                                      fontSize: priceSize,
                                      color: textColor,
                                    ),
                                  ),
                                  if (book.hasDiscount)
                                    Row(
                                      children: [
                                        Text(
                                          _formatPrice(book.originalPrice ?? book.price),
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: metaSize,
                                            color: secondaryTextColor,
                                            decoration: TextDecoration.lineThrough,
                                          ),
                                        ),
                                        SizedBox(width: isTablet ? 6 : 4),
                                        Text(
                                          '${book.discount}% OFF',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: isTablet ? 12 : 10,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF4CAF50),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          if (Platform.isIOS) const Spacer(),
                          SizedBox(
                            height: isTablet ? 52 : 46,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                _handleBuy(book);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: buttonColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(btnRadius),
                                ),
                                elevation: 0,
                                padding: EdgeInsets.symmetric(horizontal: isTablet ? 32 : 24),
                              ),
                              child: Text(
                                Platform.isIOS ? 'View in Store' : 'Buy Now',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600,
                                  fontSize: btnFontSize,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder(double height, bool isDark, Color iconColor) {
    return Container(
      width: double.infinity,
      height: height,
      color: isDark ? AppColors.darkCardBackground : const Color(0xFFF0F0F0),
      child: Center(
        child: Icon(
          Icons.menu_book_rounded,
          size: 40,
          color: iconColor.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

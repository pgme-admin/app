import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/services/access_record_service.dart';
import 'package:pgme/core/widgets/shimmer_widgets.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/utils/web_store_launcher.dart';
import 'package:pgme/features/notes/screens/pdf_viewer_screen.dart';
import 'package:pgme/core/widgets/app_dialog.dart';

class MyRecordsScreen extends StatefulWidget {
  const MyRecordsScreen({super.key});

  @override
  State<MyRecordsScreen> createState() => _MyRecordsScreenState();
}

class _MyRecordsScreenState extends State<MyRecordsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final AccessRecordService _accessRecordService = AccessRecordService();
  late TabController _tabController;

  AllRecordsData? _data;
  bool _isLoading = true;
  String? _error;
  final Set<String> _loadingPackageInvoices = {};
  final Set<String> _loadingBookInvoices = {};
  final Set<String> _loadingSessionInvoices = {};

  final List<String> _tabs = [
    'Packages',
    'Books',
    'Sessions',
    Platform.isIOS ? 'Records' : 'Invoices',
  ];

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    if (Platform.isIOS) WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed &&
        WebStoreLauncher.awaitingExternalPurchase) {
      WebStoreLauncher.clearAwaitingPurchase();
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await _accessRecordService.getAllRecords();
      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _openPackageInvoice(PackageRecordItem pkg) async {
    if (_loadingPackageInvoices.contains(pkg.purchaseId)) return;

    // Find matching invoice from already-loaded data
    // Match by purchase_type == 'package' and closest created_at to purchased_at
    final invoices = _data?.invoices ?? [];
    final packageInvoices =
        invoices.where((inv) => inv.purchaseType == 'package').toList();

    InvoiceItem? invoice;
    if (packageInvoices.length == 1) {
      invoice = packageInvoices.first;
    } else if (packageInvoices.length > 1 && pkg.purchasedAt != null) {
      // Match by closest date
      final purchaseDate = DateTime.tryParse(pkg.purchasedAt!);
      if (purchaseDate != null) {
        packageInvoices.sort((a, b) {
          final aDate = DateTime.tryParse(a.createdAt ?? '');
          final bDate = DateTime.tryParse(b.createdAt ?? '');
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          final aDiff = aDate.difference(purchaseDate).abs();
          final bDiff = bDate.difference(purchaseDate).abs();
          return aDiff.compareTo(bDiff);
        });
        invoice = packageInvoices.first;
      }
    }

    if (invoice == null || invoice.invoiceId.isEmpty) {
      if (!mounted) return;
      showAppDialog(context,
          message: 'Invoice not available for this purchase yet',
          type: AppDialogType.info);
      return;
    }

    setState(() => _loadingPackageInvoices.add(pkg.purchaseId));

    try {
      final pdfBytes =
          await _accessRecordService.downloadRecordPdf(invoice.invoiceId);

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${invoice.invoiceNumber}.pdf');
      await file.writeAsBytes(pdfBytes);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            filePath: file.path,
            title: invoice!.invoiceNumber,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showAppDialog(context,
          message: 'Failed to download invoice',
          type: AppDialogType.info);
    } finally {
      if (mounted) setState(() => _loadingPackageInvoices.remove(pkg.purchaseId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    final backgroundColor =
        isDark ? AppColors.darkBackground : const Color(0xFFF5F7FA);
    final headerColor = isDark ? AppColors.darkSurface : Colors.white;
    final textColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final cardColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final accentColor =
        isDark ? const Color(0xFF00BEFA) : const Color(0xFF0000C8);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          // Header
          Container(
            color: headerColor,
            padding: EdgeInsets.only(top: topPadding + 16, bottom: 0),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isTablet ? ResponsiveHelper.horizontalPadding(context) : 16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Icon(Icons.arrow_back, size: isTablet ? 30 : 24, color: textColor),
                      ),
                      const Spacer(),
                      Text(
                        Platform.isIOS ? 'My Records' : 'My Orders',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: isTablet ? 25 : 20,
                          color: textColor,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(width: isTablet ? 30 : 24),
                    ],
                  ),
                ),
                SizedBox(height: isTablet ? 20 : 16),
                // Tab bar
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: accentColor,
                  unselectedLabelColor: secondaryTextColor,
                  labelStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 17 : 14,
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: isTablet ? 17 : 14,
                  ),
                  indicatorColor: accentColor,
                  indicatorWeight: 3,
                  dividerColor: borderColor,
                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 12 : 8),
                  tabs: _tabs.map((t) => Tab(text: t)).toList(),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? ShimmerWidgets.purchasesTabShimmer(isDark: isDark)
                : _error != null
                    ? _buildErrorState(textColor, secondaryTextColor, isTablet)
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildPackagesTab(
                              isDark, textColor, secondaryTextColor,
                              cardColor, borderColor, accentColor, isTablet),
                          _buildBooksTab(
                              isDark, textColor, secondaryTextColor,
                              cardColor, borderColor, accentColor, isTablet),
                          _buildSessionsTab(
                              isDark, textColor, secondaryTextColor,
                              cardColor, borderColor, accentColor, isTablet),
                          _buildInvoicesTab(
                              isDark, textColor, secondaryTextColor,
                              cardColor, borderColor, accentColor, isTablet),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Color textColor, Color secondaryTextColor, bool isTablet) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 32 : 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: isTablet ? 64 : 48, color: secondaryTextColor),
            SizedBox(height: isTablet ? 20 : 16),
            Text(
              _error!,
              style: TextStyle(color: secondaryTextColor, fontSize: isTablet ? 17 : 14),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isTablet ? 20 : 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
      String message, IconData icon, Color textColor, Color secondaryTextColor, bool isTablet) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: isTablet ? 80 : 64, color: secondaryTextColor.withValues(alpha: 0.5)),
          SizedBox(height: isTablet ? 20 : 16),
          Text(
            message,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: isTablet ? 20 : 16,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
          SizedBox(height: isTablet ? 10 : 8),
          Text(
            'Your purchases will appear here',
            style: TextStyle(fontSize: isTablet ? 17 : 14, color: secondaryTextColor),
          ),
        ],
      ),
    );
  }

  Future<void> _openBookInvoice(BookRequestItem book) async {
    if (_loadingBookInvoices.contains(book.orderId)) return;

    final invoices = _data?.invoices ?? [];
    final bookInvoices = invoices
        .where((inv) => inv.purchaseType == 'book' || inv.purchaseType == 'ebook')
        .toList();

    InvoiceItem? invoice;
    if (bookInvoices.length == 1) {
      invoice = bookInvoices.first;
    } else if (bookInvoices.length > 1 && book.purchasedAt != null) {
      final purchaseDate = DateTime.tryParse(book.purchasedAt!);
      if (purchaseDate != null) {
        bookInvoices.sort((a, b) {
          final aDate = DateTime.tryParse(a.createdAt ?? '');
          final bDate = DateTime.tryParse(b.createdAt ?? '');
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          final aDiff = aDate.difference(purchaseDate).abs();
          final bDiff = bDate.difference(purchaseDate).abs();
          return aDiff.compareTo(bDiff);
        });
        invoice = bookInvoices.first;
      }
    }

    if (invoice == null || invoice.invoiceId.isEmpty) {
      if (!mounted) return;
      showAppDialog(context,
          message: 'Invoice not available for this order yet',
          type: AppDialogType.info);
      return;
    }

    setState(() => _loadingBookInvoices.add(book.orderId));

    try {
      final pdfBytes =
          await _accessRecordService.downloadRecordPdf(invoice.invoiceId);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${invoice.invoiceNumber}.pdf');
      await file.writeAsBytes(pdfBytes);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            filePath: file.path,
            title: invoice!.invoiceNumber,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showAppDialog(context,
          message: 'Failed to download invoice',
          type: AppDialogType.info);
    } finally {
      if (mounted) setState(() => _loadingBookInvoices.remove(book.orderId));
    }
  }

  Future<void> _openSessionInvoice(SessionRecordItem session) async {
    if (_loadingSessionInvoices.contains(session.purchaseId)) return;

    final invoices = _data?.invoices ?? [];
    final sessionInvoices =
        invoices.where((inv) => inv.purchaseType == 'session').toList();

    InvoiceItem? invoice;
    if (sessionInvoices.length == 1) {
      invoice = sessionInvoices.first;
    } else if (sessionInvoices.length > 1 && session.purchasedAt != null) {
      final purchaseDate = DateTime.tryParse(session.purchasedAt!);
      if (purchaseDate != null) {
        sessionInvoices.sort((a, b) {
          final aDate = DateTime.tryParse(a.createdAt ?? '');
          final bDate = DateTime.tryParse(b.createdAt ?? '');
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          final aDiff = aDate.difference(purchaseDate).abs();
          final bDiff = bDate.difference(purchaseDate).abs();
          return aDiff.compareTo(bDiff);
        });
        invoice = sessionInvoices.first;
      }
    }

    if (invoice == null || invoice.invoiceId.isEmpty) {
      if (!mounted) return;
      showAppDialog(context,
          message: 'Invoice not available for this session yet',
          type: AppDialogType.info);
      return;
    }

    setState(() => _loadingSessionInvoices.add(session.purchaseId));

    try {
      final pdfBytes =
          await _accessRecordService.downloadRecordPdf(invoice.invoiceId);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${invoice.invoiceNumber}.pdf');
      await file.writeAsBytes(pdfBytes);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            filePath: file.path,
            title: invoice!.invoiceNumber,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showAppDialog(context,
          message: 'Failed to download invoice',
          type: AppDialogType.info);
    } finally {
      if (mounted)
        setState(() => _loadingSessionInvoices.remove(session.purchaseId));
    }
  }

  // ── Packages Tab ──

  Widget _buildPackagesTab(bool isDark, Color textColor,
      Color secondaryTextColor, Color cardColor, Color borderColor, Color accentColor, bool isTablet) {
    final packages = _data?.packages ?? [];
    if (packages.isEmpty) {
      return _buildEmptyState(
          'No package purchases', Icons.inventory_2_outlined, textColor, secondaryTextColor, isTablet);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
            padding: EdgeInsets.all(isTablet ? 20 : 16),
            itemCount: packages.length,
            itemBuilder: (context, index) {
              final pkg = packages[index];
              return _buildPackageCard(pkg, isDark, textColor, secondaryTextColor,
                  cardColor, borderColor, accentColor, isTablet);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPackageCard(
      PackageRecordItem pkg,
      bool isDark,
      Color textColor,
      Color secondaryTextColor,
      Color cardColor,
      Color borderColor,
      Color accentColor,
      bool isTablet) {
    final isActive = pkg.isActive && pkg.daysRemaining > 0;
    final statusColor = isActive ? AppColors.success : Colors.orange;

    String formattedDate = '-';
    try {
      if (pkg.purchasedAt != null) {
        formattedDate =
            DateFormat('MMM dd, yyyy').format(DateTime.parse(pkg.purchasedAt!));
      }
    } catch (_) {}

    final isLoadingInvoice = _loadingPackageInvoices.contains(pkg.purchaseId);

    return GestureDetector(
      onTap: () => _openPackageInvoice(pkg),
      child: Container(
      margin: EdgeInsets.only(bottom: isTablet ? 16 : 12),
      padding: EdgeInsets.all(isTablet ? 20 : 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: isTablet ? 55 : 44,
                height: isTablet ? 55 : 44,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(isTablet ? 13 : 10),
                ),
                child: Icon(Icons.school_outlined, color: accentColor, size: isTablet ? 30 : 24),
              ),
              SizedBox(width: isTablet ? 16 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pkg.name,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 19 : 15,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        if (pkg.packageType != null) pkg.packageType!,
                        if (pkg.tierName != null) pkg.tierName!,
                      ].join(' - '),
                      style: TextStyle(fontSize: isTablet ? 16 : 13, color: secondaryTextColor),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: isTablet ? 13 : 10, vertical: isTablet ? 5 : 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                ),
                child: Text(
                  isActive ? 'Active' : 'Expired',
                  style: TextStyle(
                    fontSize: isTablet ? 15 : 12,
                    fontWeight: FontWeight.w500,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isTablet ? 16 : 12),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: isTablet ? 18 : 14, color: secondaryTextColor),
              SizedBox(width: isTablet ? 8 : 6),
              Text(formattedDate,
                  style: TextStyle(fontSize: isTablet ? 16 : 13, color: secondaryTextColor)),
              const Spacer(),
              Text(
                '\u{20B9}${pkg.amountPaid}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 19 : 15,
                  color: textColor,
                ),
              ),
            ],
          ),
          if (isActive) ...[
            SizedBox(height: isTablet ? 10 : 8),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: isTablet ? 18 : 14, color: accentColor),
                SizedBox(width: isTablet ? 8 : 6),
                Expanded(
                  child: Text(
                    '${pkg.daysRemaining} days remaining',
                    style: TextStyle(
                      fontSize: isTablet ? 16 : 13,
                      fontWeight: FontWeight.w500,
                      color: accentColor,
                    ),
                  ),
                ),
                if (pkg.tierName != null)
                  GestureDetector(
                    onTap: () {
                      if (WebStoreLauncher.shouldUseWebStore) {
                        WebStoreLauncher.openProductPage(context, productType: 'packages', productId: pkg.packageId);
                      } else {
                        context.push('/package-access?packageId=${pkg.packageId}');
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 14 : 10,
                        vertical: isTablet ? 6 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.upgrade, size: isTablet ? 16 : 14, color: accentColor),
                          SizedBox(width: isTablet ? 6 : 4),
                          Text(
                            Platform.isIOS ? 'Change Plan' : 'Upgrade',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isTablet ? 14 : 12,
                              fontWeight: FontWeight.w600,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (isLoadingInvoice) ...[
            SizedBox(height: isTablet ? 10 : 8),
            Row(
              children: [
                SizedBox(
                  width: isTablet ? 16 : 14,
                  height: isTablet ? 16 : 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accentColor,
                  ),
                ),
                SizedBox(width: isTablet ? 8 : 6),
                Text(
                  'Opening invoice...',
                  style: TextStyle(
                    fontSize: isTablet ? 15 : 12,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
    );
  }

  // ── Books Tab ──

  Widget _buildBooksTab(bool isDark, Color textColor,
      Color secondaryTextColor, Color cardColor, Color borderColor, Color accentColor, bool isTablet) {
    final books = _data?.books ?? [];
    if (books.isEmpty) {
      return _buildEmptyState(
          'No book orders', Icons.menu_book_outlined, textColor, secondaryTextColor, isTablet);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
            padding: EdgeInsets.all(isTablet ? 20 : 16),
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              return _buildBookCard(book, isDark, textColor, secondaryTextColor,
                  cardColor, borderColor, accentColor, isTablet);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBookCard(
      BookRequestItem book,
      bool isDark,
      Color textColor,
      Color secondaryTextColor,
      Color cardColor,
      Color borderColor,
      Color accentColor,
      bool isTablet) {
    Color statusColor;
    switch (book.orderStatus) {
      case 'confirmed':
      case 'delivered':
        statusColor = AppColors.success;
        break;
      case 'processing':
      case 'shipped':
        statusColor = Colors.blue;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.orange;
    }

    String formattedDate = '-';
    try {
      if (book.purchasedAt != null) {
        formattedDate =
            DateFormat('MMM dd, yyyy').format(DateTime.parse(book.purchasedAt!));
      }
    } catch (_) {}

    final isLoadingInvoice = _loadingBookInvoices.contains(book.orderId);

    return GestureDetector(
      onTap: () => _openBookInvoice(book),
      child: Container(
      margin: EdgeInsets.only(bottom: isTablet ? 16 : 12),
      padding: EdgeInsets.all(isTablet ? 20 : 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: isTablet ? 55 : 44,
                height: isTablet ? 55 : 44,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(isTablet ? 13 : 10),
                ),
                child: Icon(Icons.menu_book, color: Colors.orange, size: isTablet ? 30 : 24),
              ),
              SizedBox(width: isTablet ? 16 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.orderNumber,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 17 : 14,
                        color: textColor,
                      ),
                    ),
                    Text(
                      '${book.itemsCount} item${book.itemsCount > 1 ? 's' : ''}',
                      style:
                          TextStyle(fontSize: isTablet ? 16 : 13, color: secondaryTextColor),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: isTablet ? 13 : 10, vertical: isTablet ? 5 : 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                ),
                child: Text(
                  book.orderStatus[0].toUpperCase() +
                      book.orderStatus.substring(1),
                  style: TextStyle(
                    fontSize: isTablet ? 15 : 12,
                    fontWeight: FontWeight.w500,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isTablet ? 16 : 12),
          // Items list
          ...book.items.map((item) => Padding(
                padding: EdgeInsets.only(bottom: isTablet ? 5 : 4),
                child: Row(
                  children: [
                    SizedBox(width: isTablet ? 5 : 4),
                    Icon(Icons.circle, size: isTablet ? 8 : 6, color: secondaryTextColor),
                    SizedBox(width: isTablet ? 10 : 8),
                    Expanded(
                      child: Text(
                        '${item.title} (x${item.quantity})',
                        style: TextStyle(fontSize: isTablet ? 16 : 13, color: secondaryTextColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
          SizedBox(height: isTablet ? 10 : 8),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: isTablet ? 18 : 14, color: secondaryTextColor),
              SizedBox(width: isTablet ? 8 : 6),
              Text(formattedDate,
                  style: TextStyle(fontSize: isTablet ? 16 : 13, color: secondaryTextColor)),
              const Spacer(),
              Text(
                '\u{20B9}${book.totalAmount}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 19 : 15,
                  color: textColor,
                ),
              ),
            ],
          ),
          if (book.trackingNumber != null) ...[
            SizedBox(height: isTablet ? 10 : 8),
            Row(
              children: [
                Icon(Icons.local_shipping_outlined,
                    size: isTablet ? 18 : 14, color: secondaryTextColor),
                SizedBox(width: isTablet ? 8 : 6),
                Text(
                  'Tracking: ${book.trackingNumber}',
                  style: TextStyle(fontSize: isTablet ? 16 : 13, color: secondaryTextColor),
                ),
              ],
            ),
          ],
          if (isLoadingInvoice) ...[
            SizedBox(height: isTablet ? 10 : 8),
            Row(
              children: [
                SizedBox(
                  width: isTablet ? 16 : 14,
                  height: isTablet ? 16 : 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                ),
                SizedBox(width: isTablet ? 8 : 6),
                Text(
                  'Opening invoice...',
                  style: TextStyle(fontSize: isTablet ? 15 : 12, color: accentColor),
                ),
              ],
            ),
          ],
        ],
      ),
      ),
    );
  }

  // ── Sessions Tab ──

  Widget _buildSessionsTab(bool isDark, Color textColor,
      Color secondaryTextColor, Color cardColor, Color borderColor, Color accentColor, bool isTablet) {
    final sessions = _data?.liveSessions ?? [];
    if (sessions.isEmpty) {
      return _buildEmptyState('No session purchases',
          Icons.videocam_outlined, textColor, secondaryTextColor, isTablet);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
            padding: EdgeInsets.all(isTablet ? 20 : 16),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              return _buildSessionCard(session, isDark, textColor,
                  secondaryTextColor, cardColor, borderColor, accentColor, isTablet);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSessionCard(
      SessionRecordItem session,
      bool isDark,
      Color textColor,
      Color secondaryTextColor,
      Color cardColor,
      Color borderColor,
      Color accentColor,
      bool isTablet) {
    Color statusColor;
    switch (session.sessionStatus) {
      case 'completed':
        statusColor = AppColors.success;
        break;
      case 'live':
        statusColor = Colors.red;
        break;
      case 'scheduled':
        statusColor = Colors.blue;
        break;
      case 'cancelled':
        statusColor = Colors.grey;
        break;
      default:
        statusColor = Colors.orange;
    }

    String formattedDate = '-';
    try {
      if (session.scheduledStartTime != null) {
        formattedDate = DateFormat('MMM dd, yyyy \u2022 hh:mm a')
            .format(DateTime.parse(session.scheduledStartTime!));
      }
    } catch (_) {}

    final isLoadingInvoice = _loadingSessionInvoices.contains(session.purchaseId);

    return GestureDetector(
      onTap: () => _openSessionInvoice(session),
      child: Container(
      margin: EdgeInsets.only(bottom: isTablet ? 16 : 12),
      padding: EdgeInsets.all(isTablet ? 20 : 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: isTablet ? 55 : 44,
                height: isTablet ? 55 : 44,
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(isTablet ? 13 : 10),
                ),
                child: Icon(Icons.videocam_outlined,
                    color: Colors.purple, size: isTablet ? 30 : 24),
              ),
              SizedBox(width: isTablet ? 16 : 12),
              Expanded(
                child: Text(
                  session.name,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 19 : 15,
                    color: textColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: isTablet ? 13 : 10, vertical: isTablet ? 5 : 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                ),
                child: Text(
                  (session.sessionStatus ?? 'pending')[0].toUpperCase() +
                      (session.sessionStatus ?? 'pending').substring(1),
                  style: TextStyle(
                    fontSize: isTablet ? 15 : 12,
                    fontWeight: FontWeight.w500,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isTablet ? 16 : 12),
          if (session.facultyName != null)
            Padding(
              padding: EdgeInsets.only(bottom: isTablet ? 5 : 4),
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: isTablet ? 18 : 14, color: secondaryTextColor),
                  SizedBox(width: isTablet ? 8 : 6),
                  Text(
                    session.facultyName!,
                    style: TextStyle(fontSize: isTablet ? 16 : 13, color: secondaryTextColor),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Icon(Icons.schedule_outlined,
                  size: isTablet ? 18 : 14, color: secondaryTextColor),
              SizedBox(width: isTablet ? 8 : 6),
              Expanded(
                child: Text(formattedDate,
                    style: TextStyle(fontSize: isTablet ? 16 : 13, color: secondaryTextColor)),
              ),
              Text(
                '\u{20B9}${session.amountPaid}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 19 : 15,
                  color: textColor,
                ),
              ),
            ],
          ),
          if (isLoadingInvoice) ...[
            SizedBox(height: isTablet ? 10 : 8),
            Row(
              children: [
                SizedBox(
                  width: isTablet ? 16 : 14,
                  height: isTablet ? 16 : 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                ),
                SizedBox(width: isTablet ? 8 : 6),
                Text(
                  'Opening invoice...',
                  style: TextStyle(fontSize: isTablet ? 15 : 12, color: accentColor),
                ),
              ],
            ),
          ],
        ],
      ),
      ),
    );
  }

  // ── Invoices Tab ──

  Widget _buildInvoicesTab(bool isDark, Color textColor,
      Color secondaryTextColor, Color cardColor, Color borderColor, Color accentColor, bool isTablet) {
    final invoices = _data?.invoices ?? [];
    if (invoices.isEmpty) {
      return _buildEmptyState(
          'No invoices', Icons.receipt_long_outlined, textColor, secondaryTextColor, isTablet);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
            padding: EdgeInsets.all(isTablet ? 20 : 16),
            itemCount: invoices.length,
            itemBuilder: (context, index) {
              final invoice = invoices[index];
              return _buildInvoiceCard(invoice, isDark, textColor,
                  secondaryTextColor, cardColor, borderColor, accentColor, isTablet);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceCard(
      InvoiceItem invoice,
      bool isDark,
      Color textColor,
      Color secondaryTextColor,
      Color cardColor,
      Color borderColor,
      Color accentColor,
      bool isTablet) {
    final isPaid = invoice.paymentStatus == 'paid';

    String formattedDate = '-';
    try {
      if (invoice.createdAt != null) {
        formattedDate =
            DateFormat('MMM dd, yyyy').format(DateTime.parse(invoice.createdAt!));
      }
    } catch (_) {}

    String typeLabel;
    IconData typeIcon;
    Color typeColor;
    switch (invoice.purchaseType) {
      case 'session':
        typeLabel = 'Live Session';
        typeIcon = Icons.videocam_outlined;
        typeColor = Colors.purple;
        break;
      case 'book':
        typeLabel = Platform.isIOS ? 'Book Request' : 'Book Order';
        typeIcon = Icons.menu_book;
        typeColor = Colors.orange;
        break;
      case 'ebook':
        typeLabel = 'eBook';
        typeIcon = Icons.auto_stories_outlined;
        typeColor = Colors.teal;
        break;
      default:
        typeLabel = 'Package';
        typeIcon = Icons.school_outlined;
        typeColor = accentColor;
    }

    return Container(
      margin: EdgeInsets.only(bottom: isTablet ? 16 : 12),
      padding: EdgeInsets.all(isTablet ? 20 : 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: isTablet ? 55 : 44,
                height: isTablet ? 55 : 44,
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(isTablet ? 13 : 10),
                ),
                child: Icon(typeIcon, color: typeColor, size: isTablet ? 30 : 24),
              ),
              SizedBox(width: isTablet ? 16 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.invoiceNumber,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 17 : 14,
                        color: textColor,
                      ),
                    ),
                    Text(
                      typeLabel,
                      style:
                          TextStyle(fontSize: isTablet ? 16 : 13, color: secondaryTextColor),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: isTablet ? 13 : 10, vertical: isTablet ? 5 : 4),
                decoration: BoxDecoration(
                  color: (isPaid ? AppColors.success : Colors.orange)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                ),
                child: Text(
                  isPaid ? 'Paid' : 'Unpaid',
                  style: TextStyle(
                    fontSize: isTablet ? 15 : 12,
                    fontWeight: FontWeight.w500,
                    color: isPaid ? AppColors.success : Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isTablet ? 16 : 12),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: isTablet ? 18 : 14, color: secondaryTextColor),
              SizedBox(width: isTablet ? 8 : 6),
              Text(formattedDate,
                  style: TextStyle(fontSize: isTablet ? 16 : 13, color: secondaryTextColor)),
              const Spacer(),
              Text(
                '\u{20B9}${(invoice.amount).toStringAsFixed(2)}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 19 : 15,
                  color: textColor,
                ),
              ),
            ],
          ),
          if (invoice.invoiceId.isNotEmpty) ...[
            SizedBox(height: isTablet ? 13 : 10),
            _InvoiceDownloadButton(
              invoice: invoice,
              accessRecordService: _accessRecordService,
              accentColor: accentColor,
              isTablet: isTablet,
            ),
          ],
        ],
      ),
    );
  }
}

/// Stateful button that handles invoice PDF download with loading state
class _InvoiceDownloadButton extends StatefulWidget {
  final InvoiceItem invoice;
  final AccessRecordService accessRecordService;
  final Color accentColor;
  final bool isTablet;

  const _InvoiceDownloadButton({
    required this.invoice,
    required this.accessRecordService,
    required this.accentColor,
    required this.isTablet,
  });

  @override
  State<_InvoiceDownloadButton> createState() => _InvoiceDownloadButtonState();
}

class _InvoiceDownloadButtonState extends State<_InvoiceDownloadButton> {
  bool _isDownloading = false;

  Future<void> _downloadAndOpenPdf() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      final pdfBytes = await widget.accessRecordService.downloadRecordPdf(
        widget.invoice.invoiceId,
      );

      // Save to temp directory
      final dir = await getTemporaryDirectory();
      final fileName = '${widget.invoice.invoiceNumber}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);

      if (!mounted) return;

      // Open in the in-app PDF viewer
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            filePath: file.path,
            title: widget.invoice.invoiceNumber,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showAppDialog(context, message: 'Failed to download invoice: ${e.toString().replaceAll('Exception: ', '')}', type: AppDialogType.info);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _isDownloading ? null : _downloadAndOpenPdf,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: widget.isTablet ? 6 : 4),
        child: Row(
          children: [
            if (_isDownloading)
              SizedBox(
                width: widget.isTablet ? 24 : 20,
                height: widget.isTablet ? 24 : 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.accentColor,
                ),
              )
            else
              Icon(Icons.download_outlined, size: widget.isTablet ? 24 : 20, color: widget.accentColor),
            SizedBox(width: widget.isTablet ? 8 : 6),
            Text(
              _isDownloading ? 'Downloading...' : 'Download Invoice',
              style: TextStyle(
                fontSize: widget.isTablet ? 16 : 14,
                fontWeight: FontWeight.w500,
                color: widget.accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

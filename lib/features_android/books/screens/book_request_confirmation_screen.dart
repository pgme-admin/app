import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_android/models/book_request_model.dart';
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/theme/app_theme.dart';
import 'package:pgme/features_android/books/providers/book_provider.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';

class BookRequestConfirmationScreen extends StatefulWidget {
  final String requestId;

  const BookRequestConfirmationScreen({
    super.key,
    required this.requestId,
  });

  @override
  State<BookRequestConfirmationScreen> createState() =>
      _BookRequestConfirmationScreenState();
}

class _BookRequestConfirmationScreenState
    extends State<BookRequestConfirmationScreen> {
  BookRequestModel? _order;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    try {
      final provider = Provider.of<BookProvider>(context, listen: false);
      final order = await provider.getOrderById(widget.requestId);
      if (mounted) {
        setState(() {
          _order = order;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final cardBgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final buttonColor = isDark ? const Color(0xFF1A1A4D) : const Color(0xFF000080);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: isTablet ? 64 : 48, color: secondaryTextColor),
              SizedBox(height: isTablet ? 21 : 16),
              Text(
                'Failed to load order',
                style: TextStyle(fontSize: isTablet ? 20 : 16, color: textColor),
              ),
              SizedBox(height: isTablet ? 10 : 8),
              Text(
                _error!,
                style: TextStyle(fontSize: isTablet ? 17 : 14, color: secondaryTextColor),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isTablet ? 21 : 16),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
            child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isTablet ? 32 : 24),
                child: Column(
                  children: [
                    SizedBox(height: isTablet ? 52 : 40),
                    // Success Icon
                    Container(
                      width: isTablet ? 125 : 100,
                      height: isTablet ? 125 : 100,
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_circle,
                        size: isTablet ? 80 : 64,
                        color: Colors.green,
                      ),
                    ),
                    SizedBox(height: isTablet ? 31 : 24),

                    // Success Text
                    Text(
                      Platform.isIOS ? 'Request Placed!' : 'Order Placed!',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: isTablet ? 30 : 24,
                        color: textColor,
                      ),
                    ),
                    SizedBox(height: isTablet ? 10 : 8),
                    Text(
                      Platform.isIOS ? 'Your request has been placed successfully' : 'Your order has been placed successfully',
                      style: TextStyle(
                        fontSize: isTablet ? 17 : 14,
                        color: secondaryTextColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isTablet ? 42 : 32),

                    // Order Details Card
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isTablet ? 26 : 20),
                      decoration: BoxDecoration(
                        color: cardBgColor,
                        borderRadius: BorderRadius.circular(isTablet ? 20 : 16),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Platform.isIOS ? 'Details' : 'Order Details',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: isTablet ? 20 : 16,
                              color: textColor,
                            ),
                          ),
                          SizedBox(height: isTablet ? 21 : 16),
                          _buildDetailRow(
                            Platform.isIOS ? 'Request Number' : 'Order Number',
                            _order?.orderNumber ?? '-',
                            textColor,
                            secondaryTextColor,
                            isTablet: isTablet,
                          ),
                          SizedBox(height: isTablet ? 16 : 12),
                          _buildDetailRow(
                            'Items',
                            '${_order?.itemsCount ?? 0} items',
                            textColor,
                            secondaryTextColor,
                            isTablet: isTablet,
                          ),
                          SizedBox(height: isTablet ? 16 : 12),
                          _buildDetailRow(
                            'Total Amount',
                            '\u{20B9}${_order?.totalAmount ?? 0}',
                            textColor,
                            secondaryTextColor,
                            isTablet: isTablet,
                          ),
                          SizedBox(height: isTablet ? 16 : 12),
                          _buildDetailRow(
                            'Status',
                            _order?.statusDisplayText ?? '-',
                            textColor,
                            secondaryTextColor,
                            isTablet: isTablet,
                            isStatus: true,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isTablet ? 21 : 16),

                    // Shipping Info Card
                    if (_order?.shippingAddress != null)
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(isTablet ? 26 : 20),
                        decoration: BoxDecoration(
                          color: cardBgColor,
                          borderRadius: BorderRadius.circular(isTablet ? 20 : 16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Shipping Address',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: isTablet ? 20 : 16,
                                color: textColor,
                              ),
                            ),
                            SizedBox(height: isTablet ? 16 : 12),
                            Text(
                              _order?.recipientName ?? '',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: isTablet ? 17 : 14,
                                color: textColor,
                              ),
                            ),
                            SizedBox(height: isTablet ? 5 : 4),
                            Text(
                              _order?.shippingPhone ?? '',
                              style: TextStyle(
                                fontSize: isTablet ? 17 : 14,
                                color: secondaryTextColor,
                              ),
                            ),
                            SizedBox(height: isTablet ? 5 : 4),
                            Text(
                              _order?.shippingAddress ?? '',
                              style: TextStyle(
                                fontSize: isTablet ? 17 : 14,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Bottom Buttons
            Container(
              padding: EdgeInsets.fromLTRB(hPadding, isTablet ? 20 : 16, hPadding, bottomPadding + (isTablet ? 100 : 80)),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: isTablet ? 60 : 50,
                    child: ElevatedButton(
                      onPressed: () => context.push('/book-requests'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buttonColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                        ),
                      ),
                      child: Text(
                        Platform.isIOS ? 'View All Requests' : 'View All Orders',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: isTablet ? 20 : 16,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isTablet ? 16 : 12),
                  SizedBox(
                    width: double.infinity,
                    height: isTablet ? 60 : 50,
                    child: OutlinedButton(
                      onPressed: () => context.go('/'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: buttonColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                        ),
                      ),
                      child: Text(
                        Platform.isIOS ? 'Continue Browsing' : 'Continue Shopping',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: isTablet ? 20 : 16,
                          color: buttonColor,
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
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    Color textColor,
    Color secondaryTextColor, {
    bool isTablet = false,
    bool isStatus = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTablet ? 17 : 14,
            color: secondaryTextColor,
          ),
        ),
        isStatus
            ? Container(
                padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 12, vertical: isTablet ? 5 : 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                ),
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: isTablet ? 17 : 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.green,
                  ),
                ),
              )
            : Text(
                value,
                style: TextStyle(
                  fontSize: isTablet ? 17 : 14,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
      ],
    );
  }
}

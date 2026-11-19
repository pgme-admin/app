import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_android/models/book_request_model.dart';
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/theme/app_theme.dart';
import 'package:pgme/features_android/books/providers/book_provider.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';
import 'package:pgme/core_android/utils/web_store_launcher.dart';

class BookCartScreen extends StatelessWidget {
  const BookCartScreen({super.key});

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
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final buttonColor = isDark ? const Color(0xFF1A1A4D) : const Color(0xFF000080);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: Column(
        children: [
          // Header
          Padding(
            padding: EdgeInsets.only(top: topPadding + (isTablet ? 21 : 16), left: hPadding, right: hPadding),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Icon(Icons.arrow_back, size: isTablet ? 30 : 24, color: textColor),
                ),
                const Spacer(),
                Text(
                  'Shopping Cart',
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

          SizedBox(height: isTablet ? 21 : 16),

          // Cart Items
          Expanded(
            child: Consumer<BookProvider>(
              builder: (context, provider, _) {
                if (provider.isCartEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: isTablet ? 80 : 64,
                          color: secondaryTextColor,
                        ),
                        SizedBox(height: isTablet ? 21 : 16),
                        Text(
                          'Your cart is empty',
                          style: TextStyle(
                            fontSize: isTablet ? 22 : 18,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                        SizedBox(height: isTablet ? 10 : 8),
                        Text(
                          'Add some books to get started',
                          style: TextStyle(
                            fontSize: isTablet ? 17 : 14,
                            color: secondaryTextColor,
                          ),
                        ),
                        SizedBox(height: isTablet ? 31 : 24),
                        ElevatedButton(
                          onPressed: () => context.pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonColor,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Browse Books'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.only(left: hPadding, right: hPadding, bottom: isTablet ? 21 : 16),
                  itemCount: provider.cartItems.length,
                  itemBuilder: (context, index) {
                    final item = provider.cartItems[index];
                    return _buildCartItem(
                      context: context,
                      item: item,
                      provider: provider,
                      isDark: isDark,
                      isTablet: isTablet,
                      textColor: textColor,
                      secondaryTextColor: secondaryTextColor,
                      cardBgColor: cardBgColor,
                      borderColor: borderColor,
                    );
                  },
                );
              },
            ),
          ),

          // Bottom Summary and Checkout
          Consumer<BookProvider>(
            builder: (context, provider, _) {
              if (provider.isCartEmpty) return const SizedBox.shrink();

              return Container(
                padding: EdgeInsets.fromLTRB(hPadding, isTablet ? 20 : 16, hPadding, bottomPadding + (isTablet ? 150 : 120)),
                decoration: BoxDecoration(
                  color: cardBgColor,
                  border: Border(
                    top: BorderSide(color: borderColor),
                  ),
                ),
                child: Column(
                  children: [
                    // Subtotal
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Subtotal',
                          style: TextStyle(
                            fontSize: isTablet ? 17 : 14,
                            color: secondaryTextColor,
                          ),
                        ),
                        Text(
                          '\u{20B9}${provider.cartSubtotal}',
                          style: TextStyle(
                            fontSize: isTablet ? 17 : 14,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isTablet ? 10 : 8),
                    // Shipping
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Shipping',
                          style: TextStyle(
                            fontSize: isTablet ? 17 : 14,
                            color: secondaryTextColor,
                          ),
                        ),
                        Text(
                          '\u{20B9}${provider.shippingCost}',
                          style: TextStyle(
                            fontSize: isTablet ? 17 : 14,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isTablet ? 10 : 8),
                    Divider(color: borderColor),
                    SizedBox(height: isTablet ? 10 : 8),
                    // Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total',
                          style: TextStyle(
                            fontSize: isTablet ? 22 : 18,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        Text(
                          '\u{20B9}${provider.cartTotal}',
                          style: TextStyle(
                            fontSize: isTablet ? 22 : 18,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isTablet ? 21 : 16),
                    // Checkout Button
                    SizedBox(
                      width: double.infinity,
                      height: isTablet ? 60 : 50,
                      child: ElevatedButton(
                        onPressed: () {
                          if (WebStoreLauncher.shouldUseWebStore) {
                            WebStoreLauncher.openProductPage(context, productType: 'books', productId: '');
                          } else {
                            context.push('/book-confirm');
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: buttonColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                          ),
                        ),
                        child: Text(
                          Platform.isIOS ? 'Proceed (${provider.cartItemCount} items)' : 'Proceed to Checkout (${provider.cartItemCount} items)',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: isTablet ? 20 : 16,
                          ),
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
      ),
    );
  }

  Widget _buildCartItem({
    required BuildContext context,
    required CartItem item,
    required BookProvider provider,
    required bool isDark,
    required bool isTablet,
    required Color textColor,
    required Color secondaryTextColor,
    required Color cardBgColor,
    required Color borderColor,
  }) {
    final placeholderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);

    return Container(
      margin: EdgeInsets.only(bottom: isTablet ? 16 : 12),
      padding: EdgeInsets.all(isTablet ? 16 : 12),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Book Image
          Container(
            width: isTablet ? 100 : 80,
            height: isTablet ? 125 : 100,
            decoration: BoxDecoration(
              color: placeholderColor,
              borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
            ),
            child: item.thumbnailUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                    child: Image.network(
                      item.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.menu_book,
                        size: isTablet ? 40 : 32,
                        color: textColor.withValues(alpha: 0.3),
                      ),
                    ),
                  )
                : Icon(
                    Icons.menu_book,
                    size: isTablet ? 40 : 32,
                    color: textColor.withValues(alpha: 0.3),
                  ),
          ),
          SizedBox(width: isTablet ? 16 : 12),
          // Book Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 17 : 14,
                    color: textColor,
                  ),
                ),
                if (item.author != null)
                  Text(
                    item.author!,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 15 : 12,
                      color: secondaryTextColor,
                    ),
                  ),
                SizedBox(height: isTablet ? 10 : 8),
                Text(
                  '\u{20B9}${item.price}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 20 : 16,
                    color: textColor,
                  ),
                ),
                SizedBox(height: isTablet ? 10 : 8),
                // Quantity Controls
                Row(
                  children: [
                    _buildQuantityButton(
                      icon: Icons.remove,
                      onTap: () => provider.decrementQuantity(item.bookId),
                      isDark: isDark,
                      isTablet: isTablet,
                    ),
                    Container(
                      width: isTablet ? 50 : 40,
                      alignment: Alignment.center,
                      child: Text(
                        '${item.quantity}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: isTablet ? 20 : 16,
                          color: textColor,
                        ),
                      ),
                    ),
                    _buildQuantityButton(
                      icon: Icons.add,
                      onTap: () => provider.incrementQuantity(item.bookId),
                      isDark: isDark,
                      isTablet: isTablet,
                    ),
                    const Spacer(),
                    // Remove button
                    IconButton(
                      onPressed: () => provider.removeFromCart(item.bookId),
                      icon: Icon(
                        Icons.delete_outline,
                        size: isTablet ? 30 : 24,
                        color: Colors.red.shade400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
    required bool isTablet,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isTablet ? 40 : 32,
        height: isTablet ? 40 : 32,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
        ),
        child: Icon(icon, size: isTablet ? 22 : 18),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_android/models/access_record_model.dart';
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/theme/app_theme.dart';
import 'package:pgme/features_android/settings/providers/access_record_provider.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';

class ManagePlansScreen extends StatefulWidget {
  const ManagePlansScreen({super.key});

  @override
  State<ManagePlansScreen> createState() => _ManagePlansScreenState();
}

class _ManagePlansScreenState extends State<ManagePlansScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AccessRecordProvider>().loadSubscriptionData();
    });
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  String _formatCurrency(int amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '\u20B9',
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : const Color(0xFFF5F7FA);
    final headerBgColor = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF000000).withValues(alpha: 0.5);
    final cardBgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final backButtonBgColor = isDark ? AppColors.darkBackground : const Color(0xFFF5F7FA);
    final primaryColor = isDark ? const Color(0xFF0047CF) : const Color(0xFF0000D1);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.only(top: topPadding + 16, left: isTablet ? hPadding : 16, right: isTablet ? hPadding : 16, bottom: 16),
            decoration: BoxDecoration(
              color: headerBgColor,
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black.withValues(alpha: 0.2) : const Color(0x0A000000),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    width: isTablet ? 54 : 44,
                    height: isTablet ? 54 : 44,
                    decoration: BoxDecoration(
                      color: backButtonBgColor,
                      borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        size: isTablet ? 22 : 18,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: isTablet ? 20 : 16),
                Expanded(
                  child: Text(
                    'Manage Plans',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 25 : 20,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: Consumer<AccessRecordProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: isTablet ? 64 : 48, color: secondaryTextColor),
                        SizedBox(height: isTablet ? 20 : 16),
                        Text(
                          provider.error!,
                          style: TextStyle(color: secondaryTextColor, fontSize: isTablet ? 17 : 14),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: isTablet ? 20 : 16),
                        ElevatedButton(
                          onPressed: () => provider.loadSubscriptionData(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final activePurchases = provider.activeRecords;

                return RefreshIndicator(
                  onRefresh: provider.refresh,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                    padding: EdgeInsets.only(top: 20, bottom: bottomPadding + 20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Active Plans Section
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: hPadding),
                              child: Text(
                                'Active Plans',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: isTablet ? 20 : 16,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                            ),
                            SizedBox(height: isTablet ? 16 : 12),

                            // Active Plan Cards - Horizontally Scrollable
                            if (activePurchases.isNotEmpty)
                              SizedBox(
                                height: isTablet ? 175 : 145,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                                  itemCount: activePurchases.length,
                                  itemBuilder: (context, index) {
                                    final purchase = activePurchases[index];
                                    final isLast = index == activePurchases.length - 1;
                                    return Padding(
                                      padding: EdgeInsets.only(right: isLast ? 0 : isTablet ? 16 : 12),
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: _buildActivePlanCard(purchase, isDark, primaryColor, isTablet),
                                      ),
                                    );
                                  },
                                ),
                              )
                            else
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: hPadding),
                                child: _buildNoPlanCard(isDark, cardBgColor, textColor, secondaryTextColor, primaryColor, isTablet),
                              ),

                            SizedBox(height: isTablet ? 26 : 20),

                            // Actions Section
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: hPadding),
                              child: Text(
                                'Actions',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: isTablet ? 20 : 16,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                            ),
                            SizedBox(height: isTablet ? 16 : 12),

                            // Action Buttons
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: hPadding),
                              child: _buildActionItem(
                                icon: Icons.card_giftcard_outlined,
                                title: 'See more Plans',
                                subtitle: 'Explore available plans',
                                onTap: () {
                                  context.push('/all-packages');
                                },
                                isDark: isDark,
                                cardBgColor: cardBgColor,
                                textColor: textColor,
                                secondaryTextColor: secondaryTextColor,
                                primaryColor: primaryColor,
                                isTablet: isTablet,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePlanCard(AccessRecordModel plan, bool isDark, Color primaryColor, bool isTablet) {
    final packageName = plan.package.name;
    final packageType = plan.package.type ?? '';
    final price = _formatCurrency(plan.amountPaid);
    final expiryDate = _formatDate(plan.expiresAt);
    final daysLeft = plan.daysRemaining;

    // Use different colors for Theory vs Practical
    final isTheory = packageType.toLowerCase().contains('theory');
    final gradientColors = isDark
        ? (isTheory
            ? [const Color(0xFF0D2A5C), const Color(0xFF2D5A9E)]
            : [const Color(0xFF0D4D4D), const Color(0xFF2D9E9E)])
        : (isTheory
            ? [const Color(0xFF0000D1), const Color(0xFF4B4BFF)]
            : [const Color(0xFF00897B), const Color(0xFF4DB6AC)]);

    return Container(
      width: isTablet ? 300 : 250,
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 18 : 14, vertical: isTablet ? 16 : 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(isTablet ? 18 : 14),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Badge row
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: isTablet ? 8 : 6, vertical: isTablet ? 3 : 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'ACTIVE',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: isTablet ? 10 : 8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(width: isTablet ? 8 : 6),
              if (packageType.isNotEmpty)
                Flexible(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 8 : 6, vertical: isTablet ? 3 : 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      packageType,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isTablet ? 10 : 8,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: isTablet ? 10 : 8),
          // Plan Name
          Text(
            packageName,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: isTablet ? 19 : 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: isTablet ? 3 : 2),
          // Price
          Text(
            price,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: isTablet ? 25 : 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          SizedBox(height: isTablet ? 10 : 8),
          // Divider
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          SizedBox(height: isTablet ? 10 : 8),
          // Expiry Info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'EXPIRES',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isTablet ? 10 : 8,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                        color: Colors.white.withValues(alpha: 0.6),
                        height: 1.2,
                      ),
                    ),
                    Text(
                      expiryDate,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isTablet ? 12 : 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: isTablet ? 8 : 6),
              Container(
                padding: EdgeInsets.symmetric(horizontal: isTablet ? 10 : 8, vertical: isTablet ? 5 : 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$daysLeft days',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: isTablet ? 11 : 9,
                    fontWeight: FontWeight.w600,
                    color: gradientColors[0],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoPlanCard(bool isDark, Color cardBgColor, Color textColor, Color secondaryTextColor, Color primaryColor, bool isTablet) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 26 : 20, vertical: isTablet ? 30 : 24),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(isTablet ? 21 : 16),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.workspace_premium_outlined,
            size: isTablet ? 56 : 44,
            color: secondaryTextColor,
          ),
          SizedBox(height: isTablet ? 16 : 12),
          Text(
            Platform.isIOS ? 'No Active Plan' : 'No Active Subscription',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: isTablet ? 20 : 16,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          SizedBox(height: isTablet ? 8 : 6),
          Text(
            Platform.isIOS ? 'Choose a plan to unlock premium content' : 'Subscribe to a plan to unlock premium content',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: isTablet ? 16 : 13,
              color: secondaryTextColor,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: isTablet ? 20 : 16),
          GestureDetector(
            onTap: () => context.push('/all-packages'),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: isTablet ? 26 : 20, vertical: isTablet ? 13 : 10),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(isTablet ? 13 : 10),
              ),
              child: Text(
                'Explore Plans',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: isTablet ? 16 : 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
    required bool isDark,
    required Color cardBgColor,
    required Color textColor,
    required Color secondaryTextColor,
    required Color primaryColor,
    bool isTablet = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(isTablet ? 20 : 16),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(isTablet ? 18 : 14),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: isTablet ? 55 : 44,
              height: isTablet ? 55 : 44,
              decoration: BoxDecoration(
                color: isDestructive
                    ? const Color(0xFFFF5252).withValues(alpha: 0.1)
                    : primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: isTablet ? 27 : 22,
                  color: isDestructive ? const Color(0xFFFF5252) : primaryColor,
                ),
              ),
            ),
            SizedBox(width: isTablet ? 18 : 14),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 17 : 14,
                      fontWeight: FontWeight.w600,
                      color: isDestructive ? const Color(0xFFFF5252) : textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isTablet ? 3 : 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 14 : 11,
                      fontWeight: FontWeight.w400,
                      color: secondaryTextColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: isTablet ? 10 : 8),
            // Arrow
            Icon(
              Icons.arrow_forward_ios,
              size: isTablet ? 18 : 14,
              color: isDestructive
                  ? const Color(0xFFFF5252).withValues(alpha: 0.5)
                  : textColor.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

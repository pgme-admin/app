import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';

class RefundPolicyScreen extends StatelessWidget {
  const RefundPolicyScreen({super.key});

  List<Map<String, String>> _getSections() {
    return _getIOSSections();
  }

  List<Map<String, String>> _getDefaultSections() {
    return [
      {
        'title': '1. Scope',
        'content':
            'This Refund & Cancellation Policy governs all purchases, subscriptions, and payments made through the PGME platform.\nBy completing a purchase, you acknowledge that you have read, understood, and agreed to this policy.',
      },
      {
        'title': '2. General Refund Policy',
        'content':
            'All payments made for subscriptions, courses, packages, live sessions, or academic materials are final and non-refundable once access has been granted.\n\nAccess is considered granted when:\n\n• The subscription is activated, or\n• Course content becomes accessible to the user account.',
      },
      {
        'title': '3. Limited Exceptions',
        'content':
            'Refunds may be considered only under the following circumstances:\n\n• Duplicate payment for the same order\n• Verified billing error\n• Payment successful but subscription not activated due to system failure\n\nRefund requests must be submitted within 72 hours of payment.\nNo refund requests will be entertained after access has been initiated.',
      },
      {
        'title': '4. Non-Refundable Circumstances',
        'content':
            'Refunds will not be granted for:\n\n• Change of mind\n• Dissatisfaction after accessing content\n• Partial usage of subscription\n• Missed or attended live sessions\n• Downloaded or accessed study materials\n• Promotional, discounted, bundled, or limited-period offers\n• Failure to use subscription within validity period',
      },
      {
        'title': '5. Subscription Cancellation',
        'content':
            'Users may cancel auto-renewal (if applicable) at any time.\n\nCancellation:\n\n• Prevents future billing\n• Does not entitle user to refund for remaining period\n• Does not extend subscription validity\n\nAccess will continue until the subscription expiry date.',
      },
      {
        'title': '6. GST Treatment of Approved Refunds',
        'content':
            'If a refund is approved under Section 3:\n\n• A GST-compliant Credit Note will be issued\n• Refund will be processed to the original payment method\n• Applicable GST adjustments will be made as per law\n\nProcessing timelines depend on the payment provider or bank.',
      },
      {
        'title': '7. Payment Disputes & Chargebacks',
        'content':
            'In case of payment disputes or chargebacks initiated without contacting PGME support:\n\n• PGME reserves the right to suspend account access\n• Transaction logs and access records may be submitted to the payment provider as proof of service delivery\n• Fraudulent or abusive chargeback activity may result in permanent account termination.',
      },
      {
        'title': '8. Technical Issues',
        'content':
            'If you experience technical access issues:\n\n• You must notify support within 48 hours\n• PGME will attempt resolution within a reasonable timeframe\n• Refund eligibility (if any) will depend on inability to provide access within 5 days.\n\nMinor technical inconveniences that do not prevent access shall not qualify for refund.',
      },
      {
        'title': '9. Limitation of Liability',
        'content':
            'To the maximum extent permitted by applicable law:\n\n• PGME shall not be liable for indirect, incidental, or consequential damages\n• Total liability shall not exceed the amount paid for the specific subscription\n• PGME does not guarantee examination results, academic ranks, or professional outcomes',
      },
      {
        'title': '10. Intellectual Property Protection',
        'content':
            'All course materials, recordings, PDFs, and academic content are the exclusive intellectual property of PGME.\n\nUnauthorized sharing, reproduction, distribution, or commercial use may result in:\n\n• Immediate termination of access\n• Legal action under applicable Indian laws\n\nNo refund shall be granted in cases of policy violation.',
      },
      {
        'title': '11. Governing Law & Jurisdiction',
        'content':
            'This policy shall be governed by the laws of India.\nAll disputes shall be subject to the exclusive jurisdiction of courts located in Jalandhar, Punjab.',
      },
      {
        'title': '12. Amendments',
        'content':
            'PGME reserves the right to modify this policy at any time. Changes become effective upon publication on the platform.\nContinued use of the platform constitutes acceptance of the updated policy.',
      },
      {
        'title': '13. Contact Information',
        'content':
            'For refund-related queries:\n\nEmail: support@pgmemedicalteaching.com\n\nPlease include your Order ID and transaction details.',
      },
    ];
  }

  List<Map<String, String>> _getIOSSections() {
    return [
      {
        'title': '1. Scope',
        'content':
            'This Cancellation Policy governs your use of the PGME platform.\nBy using the platform, you acknowledge that you have read, understood, and agreed to this policy.',
      },
      {
        'title': '2. Subscription Cancellation',
        'content':
            'Users may cancel their subscription at any time.\n\nCancellation:\n\n• Prevents future access renewal\n• Does not extend current access validity\n\nAccess will continue until the current subscription expiry date.',
      },
      {
        'title': '3. Technical Issues',
        'content':
            'If you experience technical access issues:\n\n• You must notify support within 48 hours\n• PGME will attempt resolution within a reasonable timeframe\n\nMinor technical inconveniences that do not prevent access shall not qualify for service restoration.',
      },
      {
        'title': '4. Limitation of Liability',
        'content':
            'To the maximum extent permitted by applicable law:\n\n• PGME shall not be liable for indirect, incidental, or consequential damages\n• PGME does not guarantee examination results, academic ranks, or professional outcomes',
      },
      {
        'title': '5. Intellectual Property Protection',
        'content':
            'All course materials, recordings, PDFs, and academic content are the exclusive intellectual property of PGME.\n\nUnauthorized sharing, reproduction, distribution, or commercial use may result in:\n\n• Immediate termination of access\n• Legal action under applicable Indian laws',
      },
      {
        'title': '6. Governing Law & Jurisdiction',
        'content':
            'This policy shall be governed by the laws of India.\nAll disputes shall be subject to the exclusive jurisdiction of courts located in Jalandhar, Punjab.',
      },
      {
        'title': '7. Amendments',
        'content':
            'PGME reserves the right to modify this policy at any time. Changes become effective upon publication on the platform.\nContinued use of the platform constitutes acceptance of the updated policy.',
      },
      {
        'title': '8. Contact Information',
        'content':
            'For queries:\n\nEmail: support@pgmemedicalteaching.com',
      },
    ];
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
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF000000).withValues(alpha: 0.7);
    final cardBgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final backButtonBgColor = isDark ? AppColors.darkBackground : const Color(0xFFF5F7FA);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;
    final sections = _getSections();
    final screenTitle = 'Cancellation Policy';

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.only(top: topPadding + (isTablet ? 20 : 16), left: hPadding, right: hPadding, bottom: isTablet ? 20 : 16),
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
                    screenTitle,
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
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                top: isTablet ? 26 : 20,
                left: hPadding,
                right: hPadding,
                bottom: bottomPadding + (isTablet ? 26 : 20),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isTablet ? 26 : 20),
                    decoration: BoxDecoration(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(isTablet ? 21 : 16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Last Updated: February 23, 2026',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 15 : 12,
                            fontStyle: FontStyle.italic,
                            color: secondaryTextColor,
                          ),
                        ),
                        SizedBox(height: isTablet ? 26 : 20),

                        ...sections.map((section) => _buildSection(
                          section['title']!,
                          section['content']!,
                          textColor,
                          secondaryTextColor,
                          isTablet: isTablet,
                        )),

                        // Refund notice hidden on iOS
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String content, Color titleColor, Color contentColor, {bool isTablet = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isTablet ? 26 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: isTablet ? 20 : 16,
              fontWeight: FontWeight.w600,
              color: titleColor,
            ),
          ),
          SizedBox(height: isTablet ? 10 : 8),
          Text(
            content,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: isTablet ? 17 : 14,
              height: 1.6,
              color: contentColor,
            ),
          ),
        ],
      ),
    );
  }
}

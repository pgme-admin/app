import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pgme/core/services/api_service.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/features/auth/providers/auth_provider.dart';

class WebStoreLauncher {
  static final ApiService _apiService = ApiService();

  /// Returns true if the current platform should use the web store for digital purchases
  static bool get shouldUseWebStore => Platform.isIOS;

  /// Tracks whether the user was redirected to the external store for a purchase.
  /// Screens use this to auto-refresh data when the app resumes.
  static bool _awaitingExternalPurchase = false;
  static bool get awaitingExternalPurchase => _awaitingExternalPurchase;
  static void clearAwaitingPurchase() => _awaitingExternalPurchase = false;

  /// Generate a web-login token and open Safari to the product page
  static Future<void> openProductPage(
    BuildContext context, {
    required String productType,
    required String productId,
  }) async {
    // Show confirmation modal before redirecting
    final confirmed = await _showRedirectConfirmation(context);
    if (confirmed != true) return;

    if (!context.mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    bool dialogShowing = true;

    // Show loading overlay
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          dialogShowing = false;
        },
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );

    void dismissDialog() {
      if (dialogShowing) {
        dialogShowing = false;
        try {
          navigator.pop();
        } catch (_) {}
      }
    }

    try {
      final redirectPath = '/$productType/$productId';

      final response = await _apiService.dio.post(
        ApiConstants.webLoginToken,
        data: {'redirect_path': redirectPath},
      );

      // Always dismiss loading before opening Safari
      dismissDialog();

      final token = response.data['data']['token'] as String;
      final url = Uri.parse(
        '${ApiConstants.webStoreBaseUrl}$redirectPath?token=$token',
      );

      final launched = await launchUrl(url, mode: LaunchMode.externalApplication);

      if (launched) {
        _awaitingExternalPurchase = true;
      }

      if (!launched) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Could not open the store. Please visit store.pgme.in in your browser.'),
          ),
        );
      }
    } catch (e) {
      // Dismiss loading if still showing
      dismissDialog();

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again or visit store.pgme.in'),
        ),
      );
    }
  }

  /// Shows a styled confirmation dialog before browser redirect
  static Future<bool?> _showRedirectConfirmation(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkSurface : Colors.white;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final dividerColor = isDark ? AppColors.darkDivider : AppColors.divider;

    final phoneNumber = context.read<AuthProvider>().user?.phoneNumber;
    final maskedPhone = phoneNumber != null && phoneNumber.length >= 4
        ? '******${phoneNumber.substring(phoneNumber.length - 4)}'
        : phoneNumber;

    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.open_in_browser_rounded,
                    color: AppColors.primaryBlue,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                // Title
                Text(
                  'Leaving the App',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                    fontFamily: 'Poppins',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Message
                Text(
                  'You will be redirected to our website in your browser to continue.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: textSecondary,
                    fontFamily: 'Poppins',
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (maskedPhone != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: AppColors.primaryBlue.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: 'Please login with the same number ',
                              children: [
                                TextSpan(
                                  text: maskedPhone,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const TextSpan(text: ' on the website.'),
                              ],
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: textPrimary.withValues(alpha: 0.75),
                              fontFamily: 'Poppins',
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                // Continue button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.blueGradient,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Cancel button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textSecondary,
                      side: BorderSide(color: dividerColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Poppins',
                        color: textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

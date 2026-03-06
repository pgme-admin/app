import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/models/package_model.dart';
import 'package:pgme/core/models/address_model.dart';
import 'package:pgme/core/models/gateway_models.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/services/dashboard_service.dart';
import 'package:pgme/core/services/user_service.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/widgets/address_bottom_sheet.dart';
import 'package:pgme/core/widgets/gateway_widget.dart';
import 'package:pgme/core/widgets/app_dialog.dart';
import 'package:pgme/core/utils/web_store_launcher.dart';

/// Shows an upgrade bottom sheet for a tiered package.
///
/// [package] - The package with tiers
/// [currentTierIndex] - The user's current tier index
/// [packageId] - The package ID for API calls
Future<bool?> showTierChangeSheet(
  BuildContext context, {
  required PackageModel package,
  required int currentTierIndex,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _UpgradeSheet(
      package: package,
      currentTierIndex: currentTierIndex,
    ),
  );
}

class _UpgradeSheet extends StatefulWidget {
  final PackageModel package;
  final int currentTierIndex;

  const _UpgradeSheet({
    required this.package,
    required this.currentTierIndex,
  });

  @override
  State<_UpgradeSheet> createState() => _UpgradeSheetState();
}

class _UpgradeSheetState extends State<_UpgradeSheet> {
  final DashboardService _dashboardService = DashboardService();
  int? _selectedTierIndex;
  Map<String, dynamic>? _upgradePreview;
  bool _isLoadingPreview = false;
  bool _isProcessing = false;
  String? _error;

  List<PackageTier> get _availableTiers {
    if (widget.package.tiers == null) return [];
    return widget.package.tiers!
        .where((t) => t.index > widget.currentTierIndex)
        .toList();
  }

  PackageTier? get _currentTier {
    if (widget.package.tiers == null) return null;
    try {
      return widget.package.tiers!.firstWhere((t) => t.index == widget.currentTierIndex);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    if (_availableTiers.isNotEmpty) {
      _selectedTierIndex = _availableTiers.first.index;
      _loadPreview();
    }
  }

  Future<void> _loadPreview() async {
    if (_selectedTierIndex == null) return;
    setState(() {
      _isLoadingPreview = true;
      _error = null;
    });
    try {
      final preview = await _dashboardService.calculateUpgradePrice(
        widget.package.packageId,
        _selectedTierIndex!,
      );
      if (mounted) {
        setState(() {
          _upgradePreview = preview;
          _isLoadingPreview = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _isLoadingPreview = false;
        });
      }
    }
  }

  String _formatPrice(num price) {
    return '\u{20B9}${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  String _formatDuration(int days) {
    if (days >= 365) {
      final years = days ~/ 365;
      return '$years ${years == 1 ? 'year' : 'years'}';
    } else if (days >= 30) {
      final months = days ~/ 30;
      return '$months ${months == 1 ? 'month' : 'months'}';
    } else {
      return '$days ${days == 1 ? 'day' : 'days'}';
    }
  }

  Future<void> _processUpgrade() async {
    if (_selectedTierIndex == null) return;

    // iOS: redirect to web store
    if (WebStoreLauncher.shouldUseWebStore) {
      WebStoreLauncher.openProductPage(
        context,
        productType: 'packages',
        productId: widget.package.packageId,
      );
      return;
    }

    // Collect billing address
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
    );
    if (addressResult == null || !mounted) return;
    final billingAddress = addressResult['billing']!;

    setState(() => _isProcessing = true);

    try {
      final result = await _dashboardService.createUpgradeOrder(
        widget.package.packageId,
        _selectedTierIndex!,
        billingAddress: billingAddress.toJson(),
      );

      if (!mounted) return;

      // Check if it's a free upgrade
      if (result['free_upgrade'] == true) {
        setState(() => _isProcessing = false);
        if (mounted) {
          Navigator.of(context).pop(true);
          showAppDialog(context, message: Platform.isIOS ? 'Plan changed successfully!' : 'Upgrade successful!', type: AppDialogType.info);
        }
        return;
      }

      // Paid upgrade - launch payment widget
      final paymentSession = GatewaySession.fromJson(result);

      if (!mounted) return;

      final paymentResult = await Navigator.of(context, rootNavigator: true).push<GatewayResponse>(
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

      if (paymentResult != null && mounted) {
        if (paymentResult.isSuccess) {
          final verification = await _dashboardService.verifyUpgradePayment(
            paymentSessionId: paymentResult.paymentSessionId!,
            paymentId: paymentResult.paymentId!,
            signature: paymentResult.signature,
          );

          if (verification.success && mounted) {
            Navigator.of(context).pop(true);
            context.go('/success?purchaseId=${verification.purchaseId}');
          } else if (mounted) {
            _showError('Payment verification failed. Please contact support.');
          }
        } else if (paymentResult.isFailed) {
          _showError('Payment failed: ${paymentResult.errorMessage ?? "Unknown error"}');
        } else if (paymentResult.isCancelled) {
          _showInfo('Payment cancelled');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Error: ${e.toString().replaceAll('Exception: ', '')}');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showAppDialog(context, message: message, type: AppDialogType.info);
  }

  void _showInfo(String message) {
    if (!mounted) return;
    showAppDialog(context, message: message, type: AppDialogType.info);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    final bgColor = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryText = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final accentColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF0000D1);
    const successColor = Color(0xFF4CAF50);

    final currentTier = _currentTier;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isTablet ? 28 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    Platform.isIOS ? 'Change Your Plan' : 'Upgrade Your Plan',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 24 : 20,
                      color: textColor,
                    ),
                  ),
                  SizedBox(height: isTablet ? 6 : 4),
                  Text(
                    widget.package.name,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 16 : 13,
                      color: secondaryText,
                    ),
                  ),

                  SizedBox(height: isTablet ? 24 : 16),

                  // Current tier info
                  if (currentTier != null) ...[
                    Container(
                      padding: EdgeInsets.all(isTablet ? 16 : 12),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
                        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: isTablet ? 22 : 18, color: accentColor),
                          SizedBox(width: isTablet ? 12 : 8),
                          Expanded(
                            child: Text(
                              'Current plan: ${currentTier.name} (${_formatDuration(currentTier.durationDays)})',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 15 : 13,
                                color: accentColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isTablet ? 20 : 16),
                  ],

                  // Available upgrade tiers
                  Text(
                    Platform.isIOS ? 'Change to' : 'Upgrade to',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 18 : 15,
                      color: textColor,
                    ),
                  ),
                  SizedBox(height: isTablet ? 12 : 8),

                  if (_availableTiers.isEmpty)
                    Text(
                      'You are on the highest tier.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isTablet ? 16 : 14,
                        color: secondaryText,
                      ),
                    )
                  else
                    ...List.generate(_availableTiers.length, (i) {
                      final tier = _availableTiers[i];
                      final isSelected = _selectedTierIndex == tier.index;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedTierIndex = tier.index);
                          _loadPreview();
                        },
                        child: Container(
                          margin: EdgeInsets.only(bottom: isTablet ? 12 : 8),
                          padding: EdgeInsets.all(isTablet ? 16 : 12),
                          decoration: BoxDecoration(
                            color: isSelected ? accentColor.withValues(alpha: 0.08) : Colors.transparent,
                            borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
                            border: Border.all(
                              color: isSelected ? accentColor : borderColor,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: isSelected ? accentColor : secondaryText,
                                size: isTablet ? 24 : 20,
                              ),
                              SizedBox(width: isTablet ? 14 : 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tier.name,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w600,
                                        fontSize: isTablet ? 17 : 14,
                                        color: textColor,
                                      ),
                                    ),
                                    Text(
                                      _formatDuration(tier.durationDays),
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: isTablet ? 14 : 12,
                                        color: secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _formatPrice(tier.effectivePrice),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600,
                                  fontSize: isTablet ? 18 : 15,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                  // Upgrade price preview
                  if (_isLoadingPreview) ...[
                    SizedBox(height: isTablet ? 20 : 16),
                    Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                      ),
                    ),
                  ] else if (_upgradePreview != null) ...[
                    SizedBox(height: isTablet ? 20 : 16),
                    Divider(color: borderColor),
                    SizedBox(height: isTablet ? 16 : 12),
                    // Credit line
                    _buildPreviewRow(
                      'Pro-rata credit',
                      '- ${_formatPrice(_upgradePreview!['credit'] ?? 0)}',
                      secondaryText,
                      successColor,
                      isTablet,
                    ),
                    SizedBox(height: isTablet ? 10 : 6),
                    _buildPreviewRow(
                      Platform.isIOS ? 'Change amount' : 'Upgrade amount',
                      _formatPrice(_upgradePreview!['upgrade_base_price'] ?? 0),
                      secondaryText,
                      textColor,
                      isTablet,
                    ),
                    SizedBox(height: isTablet ? 10 : 6),
                    _buildPreviewRow(
                      'GST (18%)',
                      _formatPrice(_upgradePreview!['gst_amount'] ?? 0),
                      secondaryText,
                      textColor,
                      isTablet,
                    ),
                    SizedBox(height: isTablet ? 10 : 6),
                    Divider(color: borderColor),
                    SizedBox(height: isTablet ? 10 : 6),
                    _buildPreviewRow(
                      'Total to pay',
                      _formatPrice(_upgradePreview!['total_amount'] ?? 0),
                      textColor,
                      accentColor,
                      isTablet,
                      isBold: true,
                    ),
                    if ((_upgradePreview!['total_amount'] ?? 0) == 0) ...[
                      SizedBox(height: isTablet ? 10 : 6),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 12 : 8,
                          vertical: isTablet ? 6 : 4,
                        ),
                        decoration: BoxDecoration(
                          color: successColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          Platform.isIOS ? 'Free! Your existing credit covers the full amount.' : 'Free upgrade! Your existing credit covers the full amount.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 14 : 12,
                            color: successColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],

                  if (_error != null) ...[
                    SizedBox(height: isTablet ? 16 : 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isTablet ? 15 : 13,
                        color: Colors.red,
                      ),
                    ),
                  ],

                  SizedBox(height: isTablet ? 28 : 20),

                  // Upgrade button
                  if (_availableTiers.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      height: isTablet ? 56 : 48,
                      child: ElevatedButton(
                        onPressed: _isProcessing || _isLoadingPreview ? null : _processUpgrade,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          disabledBackgroundColor: accentColor.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                          ),
                        ),
                        child: _isProcessing
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                Platform.isIOS ? 'Change Plan' : 'Upgrade Now',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600,
                                  fontSize: isTablet ? 18 : 16,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),

                  SizedBox(height: MediaQuery.of(context).padding.bottom),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(
    String label,
    String value,
    Color labelColor,
    Color valueColor,
    bool isTablet, {
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: isTablet ? 16 : 14,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
            color: labelColor,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: isTablet ? 18 : 15,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

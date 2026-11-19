import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
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

/// Bottom sheet for a credited combo purchase — "complete your set".
///
/// The customer already holds one or more packages the combo bundles, so they
/// pay the combo price minus the unused value of what they own. Structure
/// deliberately mirrors [showTierChangeSheet]: preview → billing address →
/// order → gateway → verify → success.
///
/// [quote] may be passed when the caller already priced the offer (the combo
/// card does), which saves a redundant round trip; otherwise it is fetched.
Future<bool?> showComboUpgradeSheet(
  BuildContext context, {
  required String comboPackageId,
  Map<String, dynamic>? quote,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    // Present above the ShellRoute scaffold, otherwise the floating
    // bottom nav bar draws on top of the sheet and hides its actions.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ComboUpgradeSheet(
      comboPackageId: comboPackageId,
      initialQuote: quote,
    ),
  );
}

class _ComboUpgradeSheet extends StatefulWidget {
  final String comboPackageId;
  final Map<String, dynamic>? initialQuote;

  const _ComboUpgradeSheet({
    required this.comboPackageId,
    this.initialQuote,
  });

  @override
  State<_ComboUpgradeSheet> createState() => _ComboUpgradeSheetState();
}

class _ComboUpgradeSheetState extends State<_ComboUpgradeSheet> {
  final DashboardService _dashboardService = DashboardService();
  Map<String, dynamic>? _quote;
  bool _isLoading = false;
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _quote = widget.initialQuote;
    if (_quote == null) _loadQuote();
  }

  Future<void> _loadQuote() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final quote = await _dashboardService.calculateComboUpgrade(widget.comboPackageId);
      if (mounted) {
        setState(() {
          _quote = quote;
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

  String _formatPrice(num price) {
    return '\u{20B9}${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  Future<void> _processUpgrade() async {
    final quote = _quote;
    if (quote == null) return;

    Address? savedAddress;
    try {
      final user = await UserService().getProfile();
      if (user.billingAddress != null && user.billingAddress!.isNotEmpty) {
        savedAddress = Address.fromJson(user.billingAddress!);
      }
    } catch (_) {}

    if (!mounted) return;

    final addressResult = await showAddressSheet(context, initialAddress: savedAddress);
    if (addressResult == null || !mounted) return;
    final billingAddress = addressResult['billing']!;

    setState(() => _isProcessing = true);

    try {
      final result = await _dashboardService.createComboUpgradeOrder(
        widget.comboPackageId,
        billingAddress: billingAddress.toJson(),
      );

      if (!mounted) return;

      // Credit covered the whole combo — the purchase is already complete
      // server-side, so there is no gateway to open.
      if (result['free_upgrade'] == true) {
        setState(() => _isProcessing = false);
        if (mounted) {
          Navigator.of(context).pop(true);
          context.go('/success?purchaseId=${result['purchase_id']}');
        }
        return;
      }

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
          // Combo orders are ordinary package purchases server-side, so they
          // confirm through the package verify endpoint, not the tier one.
          final verification = await _dashboardService.verifyPackagePayment(
            paymentSessionId: paymentResult.paymentSessionId!,
            paymentId: paymentResult.paymentId!,
            signature: paymentResult.signature,
          );

          if (verification.success && mounted) {
            Navigator.of(context).pop(true);
            context.go('/success?purchaseId=${verification.purchaseId}');
          } else if (mounted) {
            _showMessage('Payment verification failed. Please contact support.');
          }
        } else if (paymentResult.isFailed) {
          _showMessage('Payment failed: ${paymentResult.errorMessage ?? "Unknown error"}');
        } else if (paymentResult.isCancelled) {
          _showMessage('Payment cancelled');
        }
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Error: ${e.toString().replaceAll('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showMessage(String message) {
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

    final quote = _quote;
    final combo = quote?['combo'] as Map<String, dynamic>?;
    final breakdown = (quote?['credit_breakdown'] as List?) ?? const [];

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
                  Text(
                    'Get the Combo',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 24 : 20,
                      color: textColor,
                    ),
                  ),
                  if (combo != null) ...[
                    SizedBox(height: isTablet ? 6 : 4),
                    Text(
                      combo['name']?.toString() ?? 'Combo package',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isTablet ? 16 : 13,
                        color: secondaryText,
                      ),
                    ),
                  ],

                  SizedBox(height: isTablet ? 24 : 16),

                  if (_isLoading)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: isTablet ? 40 : 28),
                      child: Center(child: CircularProgressIndicator(color: accentColor)),
                    )
                  else if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isTablet ? 16 : 14,
                        color: secondaryText,
                      ),
                    )
                  else if (quote != null && combo != null) ...[
                    // What the credit is made of — one line per package held.
                    Container(
                      padding: EdgeInsets.all(isTablet ? 16 : 12),
                      decoration: BoxDecoration(
                        color: successColor.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
                        border: Border.all(color: successColor.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Credit for what you already own',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: isTablet ? 15 : 13,
                              color: successColor,
                            ),
                          ),
                          SizedBox(height: isTablet ? 10 : 6),
                          ...breakdown.map((c) {
                            final item = c as Map<String, dynamic>;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item['package_name']?.toString() ?? 'Package',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: isTablet ? 14 : 12,
                                        color: secondaryText,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _formatPrice((item['credit'] as num?) ?? 0),
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: isTablet ? 14 : 12,
                                      color: secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          Text(
                            'Based on the unused days of your current access.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isTablet ? 13 : 11,
                              color: secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: isTablet ? 22 : 16),

                    _priceRow('Combo price', _formatPrice((combo['price'] as num?) ?? 0),
                        isTablet, secondaryText, secondaryText),
                    SizedBox(height: isTablet ? 10 : 6),
                    _priceRow('Your credit', '- ${_formatPrice((quote['credit'] as num?) ?? 0)}',
                        isTablet, successColor, successColor),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: isTablet ? 12 : 8),
                      child: Divider(height: 1, color: borderColor),
                    ),
                    _priceRow(
                      'You pay',
                      _formatPrice((quote['upgrade_base_price'] as num?) ?? 0),
                      isTablet,
                      textColor,
                      textColor,
                      bold: true,
                    ),

                    if ((quote['granted_days'] as num?) != null) ...[
                      SizedBox(height: isTablet ? 12 : 8),
                      Text(
                        'Your current access is replaced by the combo, valid for ${quote['granted_days']} more days.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 13 : 11,
                          color: secondaryText,
                        ),
                      ),
                    ],

                    SizedBox(height: isTablet ? 12 : 8),
                    Text(
                      'GST is added at payment.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isTablet ? 13 : 11,
                        color: secondaryText,
                      ),
                    ),
                  ],

                  SizedBox(height: isTablet ? 28 : 20),

                  SizedBox(
                    width: double.infinity,
                    height: isTablet ? 56 : 48,
                    child: ElevatedButton(
                      onPressed: (_isProcessing || quote == null) ? null : _processUpgrade,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        disabledBackgroundColor: accentColor.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                        ),
                        elevation: 0,
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              quote?['is_free_upgrade'] == true ? 'Get the Combo — Free' : 'Continue',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: isTablet ? 18 : 16,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  // viewInsets covers the keyboard; padding.bottom clears the system
                  // gesture bar, which the sheet now draws behind.
                  SizedBox(
                    height: MediaQuery.of(context).viewInsets.bottom +
                        MediaQuery.of(context).padding.bottom +
                        (isTablet ? 16 : 8),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceRow(
    String label,
    String value,
    bool isTablet,
    Color labelColor,
    Color valueColor, {
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: isTablet ? 16 : 14,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            color: labelColor,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: isTablet ? 18 : 15,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

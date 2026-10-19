import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/models/package_model.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/services/dashboard_service.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/utils/web_store_launcher.dart';
import 'package:pgme/features/purchase/widgets/combo_offer_card.dart';
import 'package:pgme/features/purchase/widgets/combo_upgrade_sheet.dart';
import 'package:pgme/features/purchase/widgets/tier_change_sheet.dart';

/// What a customer can do with a package they already own.
///
/// Reached from the Upgrade button on both My Orders and the Active Packages
/// cards. Those used to just push /package-access and leave the customer to
/// work out that they had to pick a longer tier themselves; this answers the
/// question directly, the way the web store's upgrade modal does:
///
///  * extend / move up a tier on this package — credited for unused days, or
///  * take the combo this package belongs to — credited the same way.
///
/// Whichever applies is offered; if both do, both are shown; if neither, the
/// customer is told so rather than being dropped on a purchase screen.
Future<bool?> showUpgradeOptionsSheet(
  BuildContext context, {
  required String packageId,
  int? currentTierIndex,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    // Present above the ShellRoute scaffold, otherwise the floating
    // bottom nav bar draws on top of the sheet and hides its actions.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _UpgradeOptionsSheet(
      packageId: packageId,
      currentTierIndex: currentTierIndex,
    ),
  );
}

class _UpgradeOptionsSheet extends StatefulWidget {
  final String packageId;
  final int? currentTierIndex;

  const _UpgradeOptionsSheet({required this.packageId, this.currentTierIndex});

  @override
  State<_UpgradeOptionsSheet> createState() => _UpgradeOptionsSheetState();
}

class _UpgradeOptionsSheetState extends State<_UpgradeOptionsSheet> {
  final DashboardService _dashboardService = DashboardService();

  PackageModel? _package;
  Map<String, dynamic>? _comboOffer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Both lookups are optional: whichever succeeds decides what we can offer.
    final results = await Future.wait([
      _dashboardService.getPackageDetails(widget.packageId).catchError((_) => null),
      _dashboardService.getComboOffer(widget.packageId),
    ]);

    if (!mounted) return;
    setState(() {
      _package = results[0] as PackageModel?;
      _comboOffer = results[1] as Map<String, dynamic>?;
      _isLoading = false;
    });
  }

  /// Tiers above the one the customer holds — the "extend your plan" options.
  List<PackageTier> get _higherTiers {
    final tiers = _package?.tiers;
    if (tiers == null) return const [];
    final current = widget.currentTierIndex ?? _package?.currentTier?.tierIndex ?? _package?.currentTierIndex;
    if (current == null) return const [];
    return tiers.where((t) => t.index > current).toList();
  }

  Future<void> _openTierUpgrade() async {
    final package = _package;
    final current = widget.currentTierIndex ?? package?.currentTier?.tierIndex ?? package?.currentTierIndex;
    if (package == null || current == null) return;

    Navigator.of(context).pop(true);
    await showTierChangeSheet(context, package: package, currentTierIndex: current);
  }

  Future<void> _openComboUpgrade() async {
    final offer = _comboOffer;
    final comboId = (offer?['combo'] as Map<String, dynamic>?)?['package_id']?.toString();
    if (comboId == null) return;

    Navigator.of(context).pop(true);
    await showComboUpgradeSheet(context, comboPackageId: comboId, quote: offer);
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

    final higherTiers = _higherTiers;
    final hasTierUpgrade = higherTiers.isNotEmpty;
    final hasCombo = _comboOffer != null;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
                    'Upgrade your plan',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 24 : 20,
                      color: textColor,
                    ),
                  ),
                  if (_package != null) ...[
                    SizedBox(height: isTablet ? 6 : 4),
                    Text(
                      _package!.name,
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
                  else ...[
                    if (hasCombo) ...[
                      ComboOfferCard(
                        offer: _comboOffer!,
                        isDark: isDark,
                        isTablet: isTablet,
                        onTake: _openComboUpgrade,
                      ),
                      SizedBox(height: isTablet ? 20 : 16),
                    ],

                    if (hasTierUpgrade)
                      _optionTile(
                        icon: Icons.schedule,
                        title: hasCombo ? 'Or extend this package' : 'Extend this package',
                        subtitle:
                            'Move to a longer plan — you are credited for the days you have not used.',
                        isDark: isDark,
                        isTablet: isTablet,
                        onTap: _openTierUpgrade,
                      ),

                    if (!hasCombo && !hasTierUpgrade) ...[
                      Text(
                        'You are on the longest plan for this package, and there is no combo '
                        'that bundles it. Browse the catalogue for other packages.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 16 : 13,
                          color: secondaryText,
                        ),
                      ),
                      SizedBox(height: isTablet ? 20 : 16),
                      _optionTile(
                        icon: Icons.grid_view,
                        title: 'See all packages',
                        subtitle: 'Theory, Practical and Combos.',
                        isDark: isDark,
                        isTablet: isTablet,
                        onTap: () {
                          Navigator.of(context).pop(false);
                          if (WebStoreLauncher.shouldUseWebStore) {
                            WebStoreLauncher.openProductPage(
                              context,
                              productType: 'packages',
                              productId: widget.packageId,
                            );
                          } else {
                            context.push('/all-packages');
                          }
                        },
                      ),
                    ],
                  ],

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

  Widget _optionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    required bool isTablet,
    required VoidCallback onTap,
  }) {
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryText = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final accentColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF0000D1);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(isTablet ? 18 : 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: isTablet ? 44 : 36,
              height: isTablet ? 44 : 36,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(isTablet ? 12 : 10),
              ),
              child: Icon(icon, size: isTablet ? 22 : 18, color: accentColor),
            ),
            SizedBox(width: isTablet ? 14 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 17 : 14,
                      color: textColor,
                    ),
                  ),
                  SizedBox(height: isTablet ? 4 : 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 14 : 11,
                      color: secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: isTablet ? 24 : 20, color: secondaryText),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:pgme/core/services/dashboard_service.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/utils/web_store_launcher.dart';

/// Self-loading wrapper around [ComboOfferCard].
///
/// Drop this into any purchase popup: it asks the backend whether a credited
/// combo applies and renders nothing at all when one doesn't, so the four
/// purchase dialogs need no state or loading code of their own — and the offer
/// cannot end up worded differently on different screens.
///
/// [isCombo] flips the question being asked. For an ordinary package it's
/// "which combo bundling this should I offer?"; for a combo it's "price this
/// combo for what the customer already owns", so someone who navigates to the
/// combo directly is still credited.
class ComboOfferSection extends StatefulWidget {
  final String packageId;
  final bool isCombo;
  final bool isPurchased;
  final bool isDark;
  final bool isTablet;
  final void Function(Map<String, dynamic> offer) onTake;

  const ComboOfferSection({
    super.key,
    required this.packageId,
    required this.isDark,
    required this.isTablet,
    required this.onTake,
    this.isCombo = false,
    this.isPurchased = false,
  });

  @override
  State<ComboOfferSection> createState() => _ComboOfferSectionState();
}

class _ComboOfferSectionState extends State<ComboOfferSection> {
  Map<String, dynamic>? _offer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // iOS is reader-only: no purchase or payment surfaces at all.
    if (WebStoreLauncher.shouldUseWebStore || widget.isPurchased) return;

    try {
      final service = DashboardService();
      final offer = widget.isCombo
          ? await service.calculateComboUpgrade(widget.packageId)
          : await service.getComboOffer(widget.packageId);
      if (mounted) setState(() => _offer = offer);
    } catch (_) {
      // No offer is the common case (owns nothing bundled). Never surface it.
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    if (offer == null) return const SizedBox.shrink();

    final secondaryText =
        widget.isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);

    return Column(
      children: [
        ComboOfferCard(
          offer: offer,
          isDark: widget.isDark,
          isTablet: widget.isTablet,
          onTake: () => widget.onTake(offer),
        ),
        SizedBox(height: widget.isTablet ? 16 : 12),
        Text(
          'or continue with just this package',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: widget.isTablet ? 14 : 11,
            color: secondaryText,
          ),
        ),
        SizedBox(height: widget.isTablet ? 14 : 10),
      ],
    );
  }
}

/// The credited combo offer shown inside a purchase dialog.
///
/// A customer holding an active package that a combo bundles pays the combo
/// price minus the unused value of what they own. This card is the moment they
/// find out — it sits above the ordinary "buy just this package" content in
/// every purchase popup, so the offer cannot drift between screens.
///
/// [offer] is the payload from `GET /packages/:id/combo-offer`, which is the
/// same shape the combo upgrade sheet consumes.
class ComboOfferCard extends StatelessWidget {
  final Map<String, dynamic> offer;
  final bool isDark;
  final bool isTablet;
  final VoidCallback onTake;

  const ComboOfferCard({
    super.key,
    required this.offer,
    required this.isDark,
    required this.isTablet,
    required this.onTake,
  });

  String _formatPrice(num price) {
    return '\u{20B9}${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  @override
  Widget build(BuildContext context) {
    final combo = offer['combo'] as Map<String, dynamic>?;
    if (combo == null) return const SizedBox.shrink();

    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryText = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final accentColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF0000D1);
    const successColor = Color(0xFF4CAF50);

    final breakdown = (offer['credit_breakdown'] as List?) ?? const [];
    final ownedNames = breakdown
        .map((c) => (c as Map<String, dynamic>)['package_name']?.toString() ?? 'a package')
        .join(', ');

    final labelSize = isTablet ? 14.0 : 11.0;
    final nameSize = isTablet ? 18.0 : 14.0;
    final rowSize = isTablet ? 15.0 : 12.0;
    final paySize = isTablet ? 18.0 : 15.0;

    return Container(
      padding: EdgeInsets.all(isTablet ? 18 : 14),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: isTablet ? 18 : 14, color: accentColor),
              SizedBox(width: isTablet ? 8 : 6),
              Expanded(
                child: Text(
                  'You already own $ownedNames',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: labelSize,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isTablet ? 10 : 8),

          Text(
            combo['name']?.toString() ?? 'Combo package',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: nameSize,
              color: textColor,
            ),
          ),
          SizedBox(height: isTablet ? 10 : 8),

          _row('Combo price', _formatPrice((combo['price'] as num?) ?? 0), rowSize, secondaryText),
          const SizedBox(height: 3),
          _row('Your credit', '- ${_formatPrice((offer['credit'] as num?) ?? 0)}', rowSize, successColor),
          SizedBox(height: isTablet ? 8 : 6),
          _row(
            'You pay',
            _formatPrice((offer['upgrade_base_price'] as num?) ?? 0),
            paySize,
            textColor,
            bold: true,
          ),

          SizedBox(height: isTablet ? 14 : 10),
          // GestureDetector + padding rather than a fixed-height
          // ElevatedButton: Material clips the label when the height is tight,
          // which cut "Get the Combo" in half. Same fix as the ebook buy
          // dialog — padding sizes the button, so the text can never clip.
          GestureDetector(
            onTap: onTake,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: isTablet ? 14 : 11),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(isTablet ? 24 : 20),
              ),
              child: Center(
                child: Text(
                  offer['is_free_upgrade'] == true ? 'Get the Combo — Free' : 'Get the Combo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 17 : 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, double size, Color color, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: size,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            color: color,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: size,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/models/workshop_model.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/services/workshop_service.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/utils/responsive_helper.dart';

/// Browse upcoming multi-day workshops.
///
/// Mirrors the layout language of the session screens: centred header with a
/// back arrow, cards on the shared `cardBgColor`, Poppins throughout.
class WorkshopsListScreen extends StatefulWidget {
  const WorkshopsListScreen({super.key});

  @override
  State<WorkshopsListScreen> createState() => _WorkshopsListScreenState();
}

class _WorkshopsListScreenState extends State<WorkshopsListScreen> {
  final WorkshopService _workshopService = WorkshopService();

  List<WorkshopModel> _workshops = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final workshops = await _workshopService.getWorkshops(upcomingOnly: true);
      if (mounted) {
        setState(() {
          _workshops = workshops;
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
    final topPadding = MediaQuery.of(context).padding.top;
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    final backgroundColor = isDark ? AppColors.darkBackground : AppColors.background;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final secondaryTextColor =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final cardBgColor =
        isDark ? AppColors.darkCardBackground : const Color(0xFFE4F4FF);
    final iconColor =
        isDark ? AppColors.secondaryBlue : AppColors.primaryBlue;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          SizedBox(height: topPadding),
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 17),
            child: Stack(
              children: [
                Positioned(
                  left: hPadding,
                  child: GestureDetector(
                    onTap: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/home');
                      }
                    },
                    child: SizedBox(
                      width: isTablet ? 30 : 24,
                      height: isTablet ? 30 : 24,
                      child: Icon(Icons.arrow_back,
                          size: isTablet ? 30 : 24, color: textColor),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    'Workshops',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: isTablet ? 26 : 20,
                      height: 1.0,
                      letterSpacing: -0.5,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError(textColor, iconColor)
                    : _workshops.isEmpty
                        ? _buildEmpty(textColor, secondaryTextColor, iconColor)
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(
                                  hPadding, 4, hPadding, 100),
                              itemCount: _workshops.length,
                              separatorBuilder: (_, __) =>
                                  SizedBox(height: isTablet ? 18 : 12),
                              itemBuilder: (context, i) => _WorkshopCard(
                                workshop: _workshops[i],
                                isDark: isDark,
                                textColor: textColor,
                                secondaryTextColor: secondaryTextColor,
                                cardBgColor: cardBgColor,
                                iconColor: iconColor,
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(Color textColor, Color iconColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: iconColor),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Failed to load workshops',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 16, color: textColor),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(
      Color textColor, Color secondaryTextColor, Color iconColor) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          Icon(Icons.calendar_month_outlined,
              size: isTablet ? 80 : 64, color: iconColor.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            'No workshops available',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              fontSize: isTablet ? 20 : 16,
              color: textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Check back later for upcoming workshops',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: isTablet ? 16 : 13,
              color: secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// A workshop in the list. The day count is the headline differentiator from a
/// one-off live session, so it sits on the thumbnail.
class _WorkshopCard extends StatelessWidget {
  final WorkshopModel workshop;
  final bool isDark;
  final Color textColor;
  final Color secondaryTextColor;
  final Color cardBgColor;
  final Color iconColor;

  const _WorkshopCard({
    required this.workshop,
    required this.isDark,
    required this.textColor,
    required this.secondaryTextColor,
    required this.cardBgColor,
    required this.iconColor,
  });

  /// "12–14 Mar" for a run, "12 Mar" for a single day.
  String _dateRange() {
    try {
      final s = DateTime.parse(workshop.startDate).toLocal();
      final e = DateTime.parse(workshop.endDate).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      if (s.year == e.year && s.month == e.month && s.day == e.day) {
        return '${months[s.month - 1]} ${s.day}';
      }
      if (s.month == e.month && s.year == e.year) {
        return '${s.day}–${e.day} ${months[s.month - 1]}';
      }
      return '${months[s.month - 1]} ${s.day} – ${months[e.month - 1]} ${e.day}';
    } catch (_) {
      return '';
    }
  }

  String _priceLabel() {
    if (Platform.isIOS) return '';
    final p = workshop.price;
    return '₹${p.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);

    return GestureDetector(
      onTap: () => context.push('/workshop/${workshop.workshopId}'),
      child: Container(
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(isTablet ? 26 : 18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: workshop.thumbnailUrl != null
                      ? Image.network(
                          workshop.thumbnailUrl!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                // Day count — what makes this a workshop rather than a session
                Positioned(
                  top: 10,
                  left: 10,
                  child: _chip(
                    '${workshop.dayCount} DAY${workshop.dayCount == 1 ? '' : 'S'}',
                    AppColors.primaryBlue.withValues(alpha: 0.92),
                    isTablet,
                  ),
                ),
                if (workshop.isLive)
                  Positioned(
                    bottom: 10,
                    left: 10,
                    child: _chip('LIVE NOW', AppColors.error, isTablet),
                  ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: workshop.hasAccess
                      ? _chip('ENROLLED', AppColors.success, isTablet)
                      : (!workshop.isPaid
                          ? _chip('FREE', AppColors.success, isTablet)
                          : const SizedBox.shrink()),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.all(isTablet ? 18 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (workshop.subjectName != null) ...[
                    Text(
                      workshop.subjectName!.toUpperCase(),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: isTablet ? 12 : 10,
                        letterSpacing: 0.4,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    workshop.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: isTablet ? 20 : 16,
                      height: 1.25,
                      letterSpacing: -0.3,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: isTablet ? 16 : 13, color: iconColor),
                      const SizedBox(width: 6),
                      Text(
                        _dateRange(),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: isTablet ? 15 : 12,
                          color: textColor,
                        ),
                      ),
                      if (workshop.totalDurationMinutes > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '· ${(workshop.totalDurationMinutes / 60).round()}h total',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w400,
                            fontSize: isTablet ? 15 : 12,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: workshop.facultyNames.isEmpty
                            ? const SizedBox.shrink()
                            : Row(
                                children: [
                                  Container(
                                    width: isTablet ? 28 : 22,
                                    height: isTablet ? 28 : 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isDark
                                          ? AppColors.darkDivider
                                          : AppColors.divider,
                                    ),
                                    child: ClipOval(
                                      child: workshop.facultyPhotoUrls.isNotEmpty
                                          ? Image.network(
                                              workshop.facultyPhotoUrls.first,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Icon(
                                                  Icons.person,
                                                  size: 14,
                                                  color: secondaryTextColor),
                                            )
                                          : Icon(Icons.person,
                                              size: 14,
                                              color: secondaryTextColor),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      workshop.facultyNames.length > 1
                                          ? '${workshop.facultyNames.first} +${workshop.facultyNames.length - 1}'
                                          : workshop.facultyNames.first,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w400,
                                        fontSize: isTablet ? 15 : 12,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      if (workshop.hasAccess)
                        Text(
                          'Enrolled',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: isTablet ? 15 : 12,
                            color: AppColors.success,
                          ),
                        )
                      else if (!workshop.isPaid)
                        Text(
                          'FREE',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: isTablet ? 15 : 12,
                            color: AppColors.success,
                          ),
                        )
                      // iOS hides prices in-app (App Store policy), so the
                      // price cell collapses rather than showing an empty gap.
                      else if (!Platform.isIOS)
                        Text(
                          _priceLabel(),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: isTablet ? 17 : 14,
                            color: textColor,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: iconColor.withValues(alpha: 0.08),
      child: Icon(Icons.calendar_month_outlined, size: 44, color: iconColor),
    );
  }

  Widget _chip(String text, Color color, bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 12 : 9, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(41),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: isTablet ? 12 : 9,
          letterSpacing: 0.3,
          color: Colors.white,
        ),
      ),
    );
  }
}

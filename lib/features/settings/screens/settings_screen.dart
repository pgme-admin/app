import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/services/app_settings_service.dart';
import 'package:pgme/core/utils/responsive_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushNotifications = true;
  final AppSettingsService _appSettingsService = AppSettingsService();
  String? _whatsappSupportUrl;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _appSettingsService.getSettings();
    final url = settings['whatsapp_support_url']?.toString();
    if (mounted) {
      setState(() {
        if (url != null && url.isNotEmpty) {
          _whatsappSupportUrl = url;
        } else {
          // Try constructing from support phone/number
          final phone = settings['whatsapp_support_number']?.toString() ??
              settings['support_phone']?.toString();
          if (phone != null && phone.isNotEmpty) {
            final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
            _whatsappSupportUrl = 'https://wa.me/$digits';
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : const Color(0xFFE4F4FF);
    final headerColor = isDark ? AppColors.darkSurface : Colors.white;
    final cardColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final dividerColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2D75DF);
    final toggleBgOff = isDark ? const Color(0xFF3D3D3D) : const Color(0xFFE4F4FF);
    final toggleBgOn = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2D75DF);
    final toggleKnobColor = isDark ? Colors.white : const Color(0xFF000080);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            height: (isTablet ? 97 : 87) + topPadding,
            color: headerColor,
            child: Stack(
              children: [
                // Back Arrow
                Positioned(
                  top: topPadding + 16,
                  left: isTablet ? hPadding : 16,
                  child: GestureDetector(
                    onTap: () {
                      context.pop();
                    },
                    child: SizedBox(
                      width: isTablet ? 30 : 24,
                      height: isTablet ? 30 : 24,
                      child: Icon(
                        Icons.arrow_back,
                        size: isTablet ? 30 : 24,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                // Title
                Positioned(
                  top: topPadding + 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      'System Settings',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: isTablet ? 25 : 20,
                        height: 1.0,
                        letterSpacing: -0.5,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: isTablet ? 16 : 12),

                      // Preferences Title
                      Padding(
                        padding: EdgeInsets.only(left: hPadding, top: isTablet ? 44 : 34),
                        child: Text(
                          'Preferences',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: isTablet ? 20 : 16,
                            height: 1.25,
                            letterSpacing: -0.5,
                            color: textColor,
                          ),
                        ),
                      ),

                      SizedBox(height: isTablet ? 23 : 18),

                      // Preferences Box
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPadding),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(isTablet ? 21 : 16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Dark Mode
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: isTablet ? 30 : 24, vertical: isTablet ? 20 : 16),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.dark_mode_outlined,
                                      size: isTablet ? 30 : 24,
                                      color: iconColor,
                                    ),
                                    SizedBox(width: isTablet ? 20 : 16),
                                    Expanded(
                                      child: Text(
                                        'Dark Mode',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w400,
                                          fontSize: isTablet ? 20 : 16,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        themeProvider.toggleDarkMode();
                                      },
                                      child: Container(
                                        width: isTablet ? 66 : 54,
                                        height: isTablet ? 29 : 23.625,
                                        decoration: BoxDecoration(
                                          color: isDark ? toggleBgOn : toggleBgOff,
                                          borderRadius: BorderRadius.circular(43.88),
                                        ),
                                        child: AnimatedAlign(
                                          duration: const Duration(milliseconds: 200),
                                          alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
                                          child: Container(
                                            width: isTablet ? 23 : 18.5625,
                                            height: isTablet ? 23 : 18.5625,
                                            margin: const EdgeInsets.symmetric(horizontal: 2.5),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: toggleKnobColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Divider
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: isTablet ? 27 : 21),
                                child: Container(
                                  height: 1,
                                  color: dividerColor,
                                ),
                              ),
                              // Push Notifications
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: isTablet ? 30 : 24, vertical: isTablet ? 20 : 16),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.notifications_outlined,
                                      size: isTablet ? 30 : 24,
                                      color: iconColor,
                                    ),
                                    SizedBox(width: isTablet ? 20 : 16),
                                    Expanded(
                                      child: Text(
                                        'Push Notifications',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w400,
                                          fontSize: isTablet ? 20 : 16,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _pushNotifications = !_pushNotifications;
                                        });
                                      },
                                      child: Container(
                                        width: isTablet ? 66 : 54,
                                        height: isTablet ? 29 : 23.625,
                                        decoration: BoxDecoration(
                                          color: _pushNotifications ? toggleBgOn : toggleBgOff,
                                          borderRadius: BorderRadius.circular(43.88),
                                        ),
                                        child: AnimatedAlign(
                                          duration: const Duration(milliseconds: 200),
                                          alignment: _pushNotifications ? Alignment.centerRight : Alignment.centerLeft,
                                          child: Container(
                                            width: isTablet ? 23 : 18.5625,
                                            height: isTablet ? 23 : 18.5625,
                                            margin: const EdgeInsets.symmetric(horizontal: 2.5),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: toggleKnobColor,
                                            ),
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

                      SizedBox(height: isTablet ? 44 : 34),

                      // Support Channels Title
                      Padding(
                        padding: EdgeInsets.only(left: hPadding),
                        child: Text(
                          'Support Channels',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: isTablet ? 20 : 16,
                            height: 1.25,
                            letterSpacing: -0.5,
                            color: textColor,
                          ),
                        ),
                      ),

                      if (_whatsappSupportUrl != null) ...[
                        SizedBox(height: isTablet ? 23 : 18),

                        // Support Channels Box
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: hPadding),
                          child: GestureDetector(
                            onTap: () async {
                              final whatsappUrl = Uri.parse(_whatsappSupportUrl!);
                              if (await canLaunchUrl(whatsappUrl)) {
                                await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
                              }
                            },
                            child: Container(
                              width: double.infinity,
                              height: isTablet ? 100 : 81,
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(isTablet ? 22 : 17),
                                boxShadow: isDark
                                    ? null
                                    : const [
                                        BoxShadow(
                                          color: Color(0x4D000000),
                                          blurRadius: 3,
                                          offset: Offset(0, 1),
                                        ),
                                        BoxShadow(
                                          color: Color(0x26000000),
                                          blurRadius: 8,
                                          spreadRadius: 3,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: isTablet ? 30 : 24, vertical: isTablet ? 20 : 16),
                                child: Row(
                                  children: [
                                    Image.asset(
                                      'assets/icons/whatsapp_logo.png',
                                      width: isTablet ? 38 : 30,
                                      height: isTablet ? 38 : 30,
                                    ),
                                    SizedBox(width: isTablet ? 20 : 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Whatsapp Support',
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w500,
                                              fontSize: isTablet ? 20 : 16,
                                              color: textColor,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Message to get direct Assistance',
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w400,
                                              fontSize: isTablet ? 15 : 12,
                                              color: secondaryTextColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_back_ios,
                                      size: isTablet ? 20 : 16,
                                      color: textColor,
                                      textDirection: TextDirection.rtl,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],

                      SizedBox(height: isTablet ? 44 : 34),

                      // Account Section Title
                      Padding(
                        padding: EdgeInsets.only(left: hPadding),
                        child: Text(
                          'Account',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: isTablet ? 20 : 16,
                            height: 1.25,
                            letterSpacing: -0.5,
                            color: textColor,
                          ),
                        ),
                      ),

                      SizedBox(height: isTablet ? 23 : 18),

                      // Account Box
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPadding),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(isTablet ? 21 : 16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!Platform.isIOS) ...[
                                // My Orders (Android only)
                                _buildLegalItem(
                                  icon: Icons.shopping_bag_outlined,
                                  title: 'My Orders',
                                  onTap: () {
                                    context.push('/my-records');
                                  },
                                  textColor: textColor,
                                  iconColor: iconColor,
                                  isTablet: isTablet,
                                ),
                                // Divider
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 27 : 21),
                                  child: Container(
                                    height: 1,
                                    color: dividerColor,
                                  ),
                                ),
                              ],
                              // Join PGME - Careers
                              _buildLegalItem(
                                icon: Icons.work_outline,
                                title: 'Join PGME - Careers',
                                onTap: () {
                                  context.push('/careers');
                                },
                                textColor: textColor,
                                iconColor: iconColor,
                                isTablet: isTablet,
                              ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: isTablet ? 44 : 34),

                      // Legal Compliances Title
                      Padding(
                        padding: EdgeInsets.only(left: hPadding),
                        child: Text(
                          'Legal Compliances',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: isTablet ? 20 : 16,
                            height: 1.25,
                            letterSpacing: -0.5,
                            color: textColor,
                          ),
                        ),
                      ),

                      SizedBox(height: isTablet ? 28 : 22),

                      // Legal Compliances Box
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPadding),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(isTablet ? 21 : 16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Terms And Conditions
                              _buildLegalItem(
                                icon: Icons.description_outlined,
                                title: 'Terms And Conditions',
                                onTap: () => context.push('/terms-and-conditions'),
                                textColor: textColor,
                                iconColor: iconColor,
                                isTablet: isTablet,
                              ),
                              // Divider
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: isTablet ? 27 : 21),
                                child: Container(
                                  height: 1,
                                  color: dividerColor,
                                ),
                              ),
                              // Privacy Policy
                              _buildLegalItem(
                                icon: Icons.security_outlined,
                                title: 'Privacy Policy',
                                onTap: () => context.push('/privacy-policy'),
                                textColor: textColor,
                                iconColor: iconColor,
                                isTablet: isTablet,
                              ),
                              if (!Platform.isIOS) ...[
                                // Divider
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 27 : 21),
                                  child: Container(
                                    height: 1,
                                    color: dividerColor,
                                  ),
                                ),
                                // Refund Policy
                                _buildLegalItem(
                                  icon: Icons.refresh,
                                  title: 'Refund Policy',
                                  onTap: () => context.push('/refund-policy'),
                                  textColor: textColor,
                                  iconColor: iconColor,
                                  isTablet: isTablet,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Bottom padding to prevent nav bar overlap
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required Color textColor,
    required Color iconColor,
    bool isTablet = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isTablet ? 30 : 24, vertical: isTablet ? 26 : 20),
        child: Row(
          children: [
            Icon(
              icon,
              size: isTablet ? 30 : 24,
              color: iconColor,
            ),
            SizedBox(width: isTablet ? 20 : 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w400,
                  fontSize: isTablet ? 20 : 16,
                  color: textColor,
                ),
              ),
            ),
            Icon(
              Icons.arrow_back_ios,
              size: isTablet ? 20 : 16,
              color: textColor,
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
      ),
    );
  }
}

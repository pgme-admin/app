import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/services/app_settings_service.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final AppSettingsService _appSettingsService = AppSettingsService();
  Map<String, dynamic> _appSettings = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final settings = await _appSettingsService.getSettings();

    if (mounted) {
      setState(() {
        _appSettings = settings;
        _isLoading = false;
      });
    }
  }

  /// WhatsApp URL: always use app-level support number (not subject community)
  String? get _whatsAppUrl {
    final url = _appSettings['whatsapp_support_url']?.toString();
    if (url != null && url.isNotEmpty) return url;
    final phone = _appSettings['whatsapp_support_number']?.toString() ??
        _appSettings['support_phone']?.toString();
    if (phone == null || phone.isEmpty) return null;
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    return 'https://wa.me/$digits';
  }

  String? get _supportEmail {
    final email = _appSettings['support_email']?.toString();
    return (email != null && email.isNotEmpty) ? email : null;
  }

  String? get _supportPhone {
    final phone = _appSettings['support_phone']?.toString();
    return (phone != null && phone.isNotEmpty) ? phone : null;
  }

  Future<void> _launchWhatsApp() async {
    final baseUrl = _whatsAppUrl;
    if (baseUrl == null) return;
    const message = 'Hi, I need help with the PGME app.';
    final separator = baseUrl.contains('?') ? '&' : '?';
    final url = Uri.parse('$baseUrl${separator}text=${Uri.encodeComponent(message)}');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchEmail() async {
    final email = _supportEmail;
    if (email == null) return;
    final url = Uri.parse(
      'mailto:$email?subject=PGME App Support&body=Hi, I need help with...',
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _launchPhone() async {
    final phone = _supportPhone;
    if (phone == null) return;
    final url = Uri.parse('tel:$phone');

    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final cardColor = isDark ? AppColors.darkCardBackground : const Color(0xFFF5F5F5);
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: EdgeInsets.all(isTablet ? 20 : 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: isTablet ? 54 : 44,
                      height: isTablet ? 54 : 44,
                      decoration: BoxDecoration(
                        color: cardColor,
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
                  Text(
                    'Help & Support',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 25 : 20,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: hPadding),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
                    child: _isLoading
                        ? Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: isTablet ? 60 : 40),
                              child: CircularProgressIndicator(
                                color: isDark ? const Color(0xFF90CAF9) : const Color(0xFF0000D1),
                              ),
                            ),
                          )
                        : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Contact Support Section
                        if (_whatsAppUrl != null || _supportEmail != null || _supportPhone != null) ...[
                          Text(
                            'Contact Support',
                            style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontWeight: FontWeight.w500,
                              fontSize: isTablet ? 20 : 16,
                              letterSpacing: -0.5,
                              color: textColor,
                            ),
                          ),
                          SizedBox(height: isTablet ? 16 : 12),
                        ],

                        // WhatsApp Card
                        if (_whatsAppUrl != null) ...[
                          _buildContactCard(
                            icon: Icons.chat_outlined,
                            title: 'WhatsApp',
                            subtitle: 'Chat with us on WhatsApp',
                            iconBgColor: isDark ? const Color(0xFF1A4D1A) : const Color(0xFFE8F5E9),
                            iconColor: Colors.green,
                            cardColor: cardColor,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            onTap: _launchWhatsApp,
                            isTablet: isTablet,
                          ),
                          SizedBox(height: isTablet ? 16 : 12),
                        ],

                        // Email Card
                        if (_supportEmail != null) ...[
                          _buildContactCard(
                            icon: Icons.mail_outline,
                            title: 'Email',
                            subtitle: _supportEmail!,
                            iconBgColor: isDark ? const Color(0xFF1A1A4D) : const Color(0xFFE3F2FD),
                            iconColor: isDark ? const Color(0xFF90CAF9) : const Color(0xFF1976D2),
                            cardColor: cardColor,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            onTap: _launchEmail,
                            isTablet: isTablet,
                          ),
                          SizedBox(height: isTablet ? 16 : 12),
                        ],

                        // Phone Card
                        if (_supportPhone != null) ...[
                          _buildContactCard(
                            icon: Icons.phone_outlined,
                            title: 'Call Us',
                            subtitle: _supportPhone!,
                            iconBgColor: isDark ? const Color(0xFF4D4D1A) : const Color(0xFFFFF8E1),
                            iconColor: Colors.orange,
                            cardColor: cardColor,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            onTap: _launchPhone,
                            isTablet: isTablet,
                          ),
                        ],

                        SizedBox(height: isTablet ? 30 : 24),

                        // Support Hours
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(isTablet ? 20 : 16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1A1A4D)
                                : const Color(0xFF0000D1).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF3D3D8C)
                                  : const Color(0xFF0000D1).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.access_time_outlined,
                                size: isTablet ? 40 : 32,
                                color: isDark ? const Color(0xFF90CAF9) : const Color(0xFF0000D1),
                              ),
                              SizedBox(height: isTablet ? 10 : 8),
                              Text(
                                'Support Hours',
                                style: TextStyle(
                                  fontFamily: 'SF Pro Display',
                                  fontWeight: FontWeight.w600,
                                  fontSize: isTablet ? 20 : 16,
                                  color: textColor,
                                ),
                              ),
                              SizedBox(height: isTablet ? 6 : 4),
                              Text(
                                'Monday - Saturday',
                                style: TextStyle(
                                  fontFamily: 'SF Pro Display',
                                  fontSize: isTablet ? 17 : 14,
                                  color: secondaryTextColor,
                                ),
                              ),
                              Text(
                                '9:00 AM - 6:00 PM IST',
                                style: TextStyle(
                                  fontFamily: 'SF Pro Display',
                                  fontWeight: FontWeight.w500,
                                  fontSize: isTablet ? 17 : 14,
                                  color: isDark ? const Color(0xFF90CAF9) : const Color(0xFF0000D1),
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: isTablet ? 40 : 32),
                      ],
                    ),
                  ),
                ),
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconBgColor,
    required Color iconColor,
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
    required VoidCallback onTap,
    bool isTablet = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(isTablet ? 20 : 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
        ),
        child: Row(
          children: [
            Container(
              width: isTablet ? 60 : 48,
              height: isTablet ? 60 : 48,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: isTablet ? 30 : 24,
                  color: iconColor,
                ),
              ),
            ),
            SizedBox(width: isTablet ? 20 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 19 : 15,
                      color: textColor,
                    ),
                  ),
                  SizedBox(height: isTablet ? 3 : 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: isTablet ? 16 : 13,
                      color: secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: isTablet ? 20 : 16,
              color: secondaryTextColor,
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pgme/core_android/constants/api_constants.dart';
import 'package:pgme/core_android/models/user_model.dart';
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/services/api_service.dart';
import 'package:pgme/core_android/services/auth_service.dart';
import 'package:pgme/core_android/services/user_service.dart';
import 'package:pgme/core_android/theme/app_theme.dart';
import 'package:pgme/features_android/settings/screens/settings_screen.dart';
import 'package:pgme/core_android/widgets/shimmer_widgets.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';
import 'package:pgme/core_android/services/app_settings_service.dart';
import 'package:pgme/features_android/courses/providers/download_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserService _userService = UserService();
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final AppSettingsService _appSettingsService = AppSettingsService();

  UserModel? _user;
  Map<String, dynamic>? _subscriptionStatus;
  Map<String, dynamic>? _selectedSubject;
  Map<String, dynamic>? _appSettings;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load user profile, subscription status, selected subject, and app settings in parallel
      final results = await Future.wait([
        _userService.getProfile(),
        _loadSubscriptionStatus(),
        _loadSelectedSubject(),
        _appSettingsService.getSettings(),
      ]);

      setState(() {
        _user = results[0] as UserModel;
        _subscriptionStatus = results[1] as Map<String, dynamic>?;
        _selectedSubject = results[2] as Map<String, dynamic>?;
        _appSettings = results[3] as Map<String, dynamic>?;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _loadSubscriptionStatus() async {
    try {
      final response = await _apiService.dio.get(
        ApiConstants.activeAccessLevel,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error loading subscription status: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _loadSelectedSubject() async {
    try {
      final response = await _apiService.dio.get(
        ApiConstants.subjectSelections,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final selections = response.data['data']['selections'] as List?;
        if (selections != null && selections.isNotEmpty) {
          // Return the primary subject or the first one
          final primary = selections.firstWhere(
            (s) => s['is_primary'] == true,
            orElse: () => selections.first,
          );
          return primary as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error loading selected subject: $e');
      return null;
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _authService.logout();
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final cardColor = isDark ? AppColors.darkCardBackground : const Color(0xFFE4F4FF);
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);
    final iconBgColor = isDark ? AppColors.darkSurface : Colors.white;
    final iconColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final dividerColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final borderColor = isDark ? AppColors.darkDivider : const Color(0x5C000080);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: ShimmerWidgets.profileShimmer(isDark: isDark),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isTablet ? 32 : 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: isTablet ? 64 : 48, color: secondaryTextColor),
                SizedBox(height: isTablet ? 20 : 16),
                Text(
                  'Failed to load profile',
                  style: TextStyle(fontSize: isTablet ? 20 : 16, color: textColor),
                ),
                SizedBox(height: isTablet ? 10 : 8),
                Text(
                  _error!,
                  style: TextStyle(fontSize: isTablet ? 17 : 14, color: secondaryTextColor),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: isTablet ? 32 : 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _loadData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: isTablet ? 32 : 24, vertical: isTablet ? 16 : 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                        ),
                      ),
                      child: const Text('Retry'),
                    ),
                    SizedBox(width: isTablet ? 20 : 16),
                    OutlinedButton(
                      onPressed: _handleLogout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? const Color(0xFFEF9A9A) : const Color(0xFFD32F2F),
                        side: BorderSide(
                          color: isDark ? const Color(0xFFEF9A9A) : const Color(0xFFD32F2F),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: isTablet ? 32 : 24, vertical: isTablet ? 16 : 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                        ),
                      ),
                      child: const Text('Log Out'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Get active package info - combine all packages with their type
    final theoryPackages = (_subscriptionStatus?['theory_packages'] as List? ?? [])
        .map((p) => {...(p as Map<String, dynamic>), 'type': 'Theory'})
        .toList();
    final practicalPackages = (_subscriptionStatus?['practical_packages'] as List? ?? [])
        .map((p) => {...(p as Map<String, dynamic>), 'type': 'Practical'})
        .toList();

    // Combine all active packages
    final allActivePackages = [...theoryPackages, ...practicalPackages];

    return Scaffold(
      backgroundColor: backgroundColor,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top curved box with profile info
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(isTablet ? 52 : 40),
                        bottomRight: Radius.circular(isTablet ? 52 : 40),
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(isTablet ? 26 : 20, isTablet ? 10 : 8, isTablet ? 26 : 20, isTablet ? 30 : 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => context.pop(),
                              child: Container(
                                width: isTablet ? 50 : 40,
                                height: isTablet ? 50 : 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isDark ? AppColors.darkSurface : Colors.white,
                                ),
                                child: Icon(
                                  Icons.arrow_back,
                                  size: isTablet ? 25 : 20,
                                  color: textColor,
                                ),
                              ),
                            ),
                            SizedBox(height: isTablet ? 16 : 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Profile picture on the left
                                Container(
                                  width: isTablet ? 100 : 80,
                                  height: isTablet ? 100 : 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF555555) : const Color(0xFFCCCCCC),
                                      width: 2,
                                    ),
                                    color: Colors.transparent,
                                    image: _user?.photoUrl != null
                                        ? DecorationImage(
                                            image: NetworkImage(_user!.photoUrl!),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: _user?.photoUrl == null
                                      ? Center(
                                          child: Icon(
                                            Icons.person_outline,
                                            size: isTablet ? 45 : 36,
                                            color: secondaryTextColor,
                                          ),
                                        )
                                      : null,
                                ),
                                SizedBox(width: isTablet ? 20 : 16),
                                // User details on the right
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Name
                                      Text(
                                        _user?.name ?? 'User',
                                        style: TextStyle(
                                          fontFamily: 'SF Pro Display',
                                          fontWeight: FontWeight.w700,
                                          fontSize: isTablet ? 22 : 18,
                                          color: textColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: isTablet ? 6 : 4),
                                      // Phone number
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.phone_outlined,
                                            size: isTablet ? 18 : 14,
                                            color: secondaryTextColor,
                                          ),
                                          SizedBox(width: isTablet ? 6 : 4),
                                          Text(
                                            _user?.phoneNumber ?? '',
                                            style: TextStyle(
                                              fontFamily: 'SF Pro Display',
                                              fontWeight: FontWeight.w400,
                                              fontSize: isTablet ? 16 : 13,
                                              color: secondaryTextColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: isTablet ? 10 : 8),
                                      // Subject selection - tappable
                                      GestureDetector(
                                        onTap: () async {
                                          // Await the push so we can detect when
                                          // the subject selection screen has finished.
                                          // SubjectSelectionScreen returns true when
                                          // a subject change was successfully applied.
                                          final changed = await context.push<bool>('/subject-selection');
                                          if (changed == true && mounted) {
                                            // Reload profile to reflect new subject
                                            // name and any updated community links.
                                            _loadData();
                                          }
                                        },
                                        child: Container(
                                          padding: EdgeInsets.symmetric(horizontal: isTablet ? 13 : 10, vertical: isTablet ? 8 : 6),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? const Color(0xFF1A1A4D)
                                                : const Color(0xFF0000D1).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                                            border: Border.all(
                                              color: isDark
                                                  ? const Color(0xFF3D3D8C)
                                                  : const Color(0xFF0000D1).withValues(alpha: 0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.menu_book_outlined,
                                                size: isTablet ? 18 : 14,
                                                color: isDark ? const Color(0xFF90CAF9) : const Color(0xFF0000D1),
                                              ),
                                              SizedBox(width: isTablet ? 8 : 6),
                                              Flexible(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'Primary Subject',
                                                      style: TextStyle(
                                                        fontFamily: 'SF Pro Display',
                                                        fontWeight: FontWeight.w400,
                                                        fontSize: isTablet ? 11 : 9,
                                                        color: (isDark ? const Color(0xFF90CAF9) : const Color(0xFF0000D1)).withValues(alpha: 0.7),
                                                        height: 1.2,
                                                      ),
                                                    ),
                                                    Text(
                                                      _selectedSubject?['subject_name'] ?? 'Not selected',
                                                      style: TextStyle(
                                                        fontFamily: 'SF Pro Display',
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: isTablet ? 14 : 11,
                                                        color: isDark ? const Color(0xFF90CAF9) : const Color(0xFF0000D1),
                                                        height: 1.3,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              SizedBox(width: isTablet ? 6 : 4),
                                              Icon(
                                                Icons.chevron_right,
                                                size: isTablet ? 20 : 16,
                                                color: isDark ? const Color(0xFF90CAF9) : const Color(0xFF0000D1),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: isTablet ? 16 : 12),

                  // Active Packages Section
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Active Packages',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontWeight: FontWeight.w500,
                            fontSize: isTablet ? 20 : 16,
                            height: 20 / 16,
                            letterSpacing: -0.5,
                            color: textColor,
                          ),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            context.push('/manage-plans');
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: isTablet ? 12 : 8, vertical: isTablet ? 10 : 8),
                            child: Text(
                              'Manage',
                              style: TextStyle(
                                fontFamily: 'SF Pro Display',
                                fontWeight: FontWeight.w600,
                                fontSize: isTablet ? 18 : 15,
                                letterSpacing: -0.5,
                                color: isDark ? const Color(0xFF90CAF9) : const Color(0xFF0000D1),
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: isTablet ? 22 : 17),

                  // Active Package Cards - Horizontally Scrollable
                  if (allActivePackages.isNotEmpty)
                    SizedBox(
                      height: isTablet ? 140 : 115,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(horizontal: hPadding),
                        itemCount: allActivePackages.length,
                        itemBuilder: (context, index) {
                          final package = allActivePackages[index];
                          final isLast = index == allActivePackages.length - 1;
                          return Padding(
                            padding: EdgeInsets.only(right: isLast ? 0 : isTablet ? 16 : 12),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: _buildActivePackageCard(
                                package: package,
                                isDark: isDark,
                                isTablet: isTablet,
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  else
                    // No active package
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: hPadding),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(isTablet ? 30 : 24),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(isTablet ? 18 : 14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.card_membership_outlined, size: isTablet ? 64 : 48, color: secondaryTextColor),
                            SizedBox(height: isTablet ? 16 : 12),
                            Text(
                              'No Active Packages',
                              style: TextStyle(
                                fontFamily: 'SF Pro Display',
                                fontWeight: FontWeight.w600,
                                fontSize: isTablet ? 20 : 16,
                                color: textColor,
                              ),
                            ),
                            SizedBox(height: isTablet ? 10 : 8),
                            Text(
                              'Browse our packages to start learning',
                              style: TextStyle(
                                fontSize: isTablet ? 17 : 14,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  SizedBox(height: isTablet ? 20 : 16),

                  // Basic Information Section
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Basic Information',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontWeight: FontWeight.w500,
                            fontSize: isTablet ? 20 : 16,
                            height: 20 / 16,
                            letterSpacing: -0.5,
                            color: textColor,
                          ),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            if (_user != null) {
                              final result = await context.push('/edit-profile', extra: _user);
                              if (result == true && mounted) {
                                // Profile was updated, reload data
                                _loadData();
                              }
                            }
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: isTablet ? 12 : 8, vertical: isTablet ? 10 : 8),
                            child: Text(
                              'Edit',
                              style: TextStyle(
                                fontFamily: 'SF Pro Display',
                                fontWeight: FontWeight.w600,
                                fontSize: isTablet ? 18 : 15,
                                letterSpacing: -0.5,
                                color: isDark ? const Color(0xFF90CAF9) : const Color(0xFF0000D1),
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: isTablet ? 12 : 9),

                  // Basic Information Box
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                        border: Border.all(
                          color: borderColor,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Student ID
                          _buildInfoRow(
                            icon: Icons.badge_outlined,
                            label: 'STUDENT ID',
                            value: _user?.studentId ?? 'Not assigned',
                            showDivider: true,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            iconBgColor: iconBgColor,
                            iconColor: iconColor,
                            dividerColor: dividerColor,
                            isTablet: isTablet,
                          ),
                          // Full Name
                          _buildInfoRow(
                            icon: Icons.person_outline,
                            label: 'FULL NAME',
                            value: _user?.name ?? 'Not set',
                            showDivider: true,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            iconBgColor: iconBgColor,
                            iconColor: iconColor,
                            dividerColor: dividerColor,
                            isTablet: isTablet,
                          ),
                          // Email
                          _buildInfoRow(
                            icon: Icons.mail_outline,
                            label: 'EMAIL',
                            value: _user?.email ?? 'Not set',
                            showDivider: true,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            iconBgColor: iconBgColor,
                            iconColor: iconColor,
                            dividerColor: dividerColor,
                            isTablet: isTablet,
                          ),
                          // Phone Number
                          _buildInfoRow(
                            icon: Icons.phone_outlined,
                            label: 'PHONE NUMBER',
                            value: _user?.phoneNumber ?? 'Not set',
                            showDivider: true,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            iconBgColor: iconBgColor,
                            iconColor: iconColor,
                            dividerColor: dividerColor,
                            isTablet: isTablet,
                          ),
                          // Gender
                          _buildInfoRow(
                            icon: Icons.wc_outlined,
                            label: 'GENDER',
                            value: _user?.gender ?? 'Not set',
                            showDivider: false,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            iconBgColor: iconBgColor,
                            iconColor: iconColor,
                            dividerColor: dividerColor,
                            isTablet: isTablet,
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: isTablet ? 20 : 16),

                  // Address Section (only if address exists)
                  if (_user?.address != null && _user!.address!.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: hPadding),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Address',
                            style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontWeight: FontWeight.w500,
                              fontSize: isTablet ? 20 : 16,
                              height: 20 / 16,
                              letterSpacing: -0.5,
                              color: textColor,
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () async {
                              if (_user != null) {
                                final result = await context.push('/edit-profile', extra: _user);
                                if (result == true && mounted) {
                                  // Profile was updated, reload data
                                  _loadData();
                                }
                              }
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: isTablet ? 12 : 8, vertical: isTablet ? 10 : 8),
                              child: Text(
                                'Edit',
                                style: TextStyle(
                                  fontFamily: 'SF Pro Display',
                                  fontWeight: FontWeight.w600,
                                  fontSize: isTablet ? 18 : 15,
                                  letterSpacing: -0.5,
                                  color: isDark ? const Color(0xFF90CAF9) : const Color(0xFF0000D1),
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: isTablet ? 12 : 9),

                    // Address Box
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: hPadding),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(isTablet ? 20 : 16),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Location icon circle
                            Container(
                              width: isTablet ? 52 : 42,
                              height: isTablet ? 52 : 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: iconBgColor,
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.location_on_outlined,
                                  size: isTablet ? 25 : 20,
                                  color: iconColor,
                                ),
                              ),
                            ),
                            SizedBox(width: isTablet ? 16 : 12),
                            // Address text
                            Expanded(
                              child: Text(
                                _user!.address!,
                                style: TextStyle(
                                  fontFamily: 'SF Pro Display',
                                  fontWeight: FontWeight.w500,
                                  fontSize: isTablet ? 17 : 14,
                                  height: 1.4,
                                  color: textColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: isTablet ? 20 : 16),
                  ],

                  // Quick Actions Section
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    child: Text(
                      'Quick Actions',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontWeight: FontWeight.w500,
                        fontSize: isTablet ? 20 : 16,
                        height: 20 / 16,
                        letterSpacing: -0.5,
                        color: textColor,
                      ),
                    ),
                  ),

                  SizedBox(height: isTablet ? 16 : 12),

                  // Downloads Card
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    child: GestureDetector(
                      onTap: () => context.push('/downloads'),
                      child: Consumer<DownloadProvider>(
                        builder: (context, downloadProvider, _) {
                          return Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(isTablet ? 20 : 16),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: isTablet ? 55 : 44,
                                  height: isTablet ? 55 : 44,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1A4D3D) : const Color(0xFFE0F2F1),
                                    borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.download_done_rounded,
                                      size: isTablet ? 27 : 22,
                                      color: isDark ? const Color(0xFF80CBC4) : const Color(0xFF00796B),
                                    ),
                                  ),
                                ),
                                SizedBox(width: isTablet ? 16 : 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Downloads',
                                        style: TextStyle(
                                          fontFamily: 'SF Pro Display',
                                          fontWeight: FontWeight.w600,
                                          fontSize: isTablet ? 17 : 14,
                                          color: textColor,
                                        ),
                                      ),
                                      SizedBox(height: isTablet ? 4 : 2),
                                      Text(
                                        downloadProvider.hasActiveDownloads
                                            ? '${downloadProvider.activeDownloads.length} downloading${downloadProvider.downloadedCount > 0 ? '  •  ${downloadProvider.downloadedCount} saved' : ''}'
                                            : downloadProvider.downloadedCount > 0
                                                ? '${downloadProvider.downloadedCount} videos  •  ${downloadProvider.formattedTotalStorage}'
                                                : 'No offline videos',
                                        style: TextStyle(
                                          fontFamily: 'SF Pro Display',
                                          fontWeight: FontWeight.w400,
                                          fontSize: isTablet ? 14 : 12,
                                          color: downloadProvider.hasActiveDownloads
                                              ? (isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4))
                                              : secondaryTextColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  size: isTablet ? 24 : 20,
                                  color: secondaryTextColor,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  SizedBox(height: isTablet ? 16 : 12),

                  // Quick Actions Grid
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    child: Row(
                      children: [
                        if (!Platform.isIOS) ...[
                          // My Orders (Android only)
                          Expanded(
                            child: _buildQuickActionCard(
                              icon: Icons.shopping_bag_outlined,
                              label: 'My Orders',
                              subtitle: 'View orders',
                              onTap: () => context.push('/my-records'),
                              cardColor: cardColor,
                              iconBgColor: isDark ? const Color(0xFF1A4D1A) : const Color(0xFFE8F5E9),
                              iconColor: Colors.green,
                              textColor: textColor,
                              secondaryTextColor: secondaryTextColor,
                              isTablet: isTablet,
                            ),
                          ),
                          SizedBox(width: isTablet ? 16 : 12),
                        ],
                        // Settings
                        Expanded(
                          child: _buildQuickActionCard(
                            icon: Icons.settings_outlined,
                            label: 'Settings',
                            subtitle: 'Preferences',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const SettingsScreen(),
                                ),
                              );
                            },
                            cardColor: cardColor,
                            iconBgColor: isDark ? const Color(0xFF1A1A4D) : const Color(0xFFE3F2FD),
                            iconColor: isDark ? const Color(0xFF90CAF9) : const Color(0xFF1976D2),
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            isTablet: isTablet,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: isTablet ? 16 : 12),

                  // Help & About Row
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    child: Row(
                      children: [
                        // Help & Support
                        Expanded(
                          child: _buildQuickActionCard(
                            icon: Icons.help_outline,
                            label: 'Help',
                            subtitle: 'Get support',
                            onTap: () => context.push('/help'),
                            cardColor: cardColor,
                            iconBgColor: isDark ? const Color(0xFF4D4D1A) : const Color(0xFFFFF8E1),
                            iconColor: Colors.orange,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            isTablet: isTablet,
                          ),
                        ),
                        SizedBox(width: isTablet ? 16 : 12),
                        // About
                        Expanded(
                          child: _buildQuickActionCard(
                            icon: Icons.info_outline,
                            label: 'About',
                            subtitle: 'App info',
                            onTap: () => context.push('/about'),
                            cardColor: cardColor,
                            iconBgColor: isDark ? const Color(0xFF4D1A4D) : const Color(0xFFF3E5F5),
                            iconColor: isDark ? const Color(0xFFCE93D8) : const Color(0xFF7B1FA2),
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            isTablet: isTablet,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: isTablet ? 16 : 12),

                  // Join PGME Row
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    child: Builder(
                      builder: (context) {
                        final instagramUrl = _appSettings?['instagram_url']?.toString();
                        final youtubeUrl = _appSettings?['youtube_url']?.toString();
                        final twitterUrl = _appSettings?['twitter_url']?.toString();
                        // Only show subject-specific WhatsApp community link (not support)
                        final subjectWhatsapp = _selectedSubject?['whatsapp_community_link']?.toString();
                        final whatsappLink = (subjectWhatsapp != null && subjectWhatsapp.isNotEmpty)
                            ? subjectWhatsapp
                            : null;

                        final hasAnyLink = (instagramUrl != null && instagramUrl.isNotEmpty) ||
                            (youtubeUrl != null && youtubeUrl.isNotEmpty) ||
                            (twitterUrl != null && twitterUrl.isNotEmpty) ||
                            whatsappLink != null;

                        final joinPgmeCard = _buildQuickActionCard(
                          icon: Icons.work_outline,
                          label: 'Join PGME',
                          subtitle: 'Apply to our team',
                          onTap: () => context.push('/careers'),
                          cardColor: cardColor,
                          iconBgColor: isDark ? const Color(0xFF4D1A1A) : const Color(0xFFFFEBEE),
                          iconColor: isDark ? const Color(0xFFEF9A9A) : const Color(0xFFE53935),
                          textColor: textColor,
                          secondaryTextColor: secondaryTextColor,
                          isTablet: isTablet,
                        );

                        if (!hasAnyLink) {
                          return Row(
                            children: [
                              Expanded(child: joinPgmeCard),
                              SizedBox(width: isTablet ? 16 : 12),
                              const Expanded(child: SizedBox()),
                            ],
                          );
                        }

                        final topRow = <Widget>[
                          if (instagramUrl != null && instagramUrl.isNotEmpty)
                            _buildCommunityIcon(
                              icon: FontAwesomeIcons.instagram,
                              color: const Color(0xFFE1306C),
                              url: instagramUrl,
                              isTablet: isTablet,
                            ),
                          if (youtubeUrl != null && youtubeUrl.isNotEmpty)
                            _buildCommunityIcon(
                              icon: FontAwesomeIcons.youtube,
                              color: const Color(0xFFFF0000),
                              url: youtubeUrl,
                              isTablet: isTablet,
                            ),
                        ];

                        final bottomRow = <Widget>[
                          if (twitterUrl != null && twitterUrl.isNotEmpty)
                            _buildCommunityIcon(
                              icon: FontAwesomeIcons.xTwitter,
                              color: isDark ? Colors.white : const Color(0xFF000000),
                              url: twitterUrl,
                              isTablet: isTablet,
                            ),
                          if (whatsappLink != null)
                            _buildCommunityIcon(
                              icon: FontAwesomeIcons.whatsapp,
                              color: const Color(0xFF25D366),
                              url: whatsappLink,
                              isTablet: isTablet,
                            ),
                        ];

                        return Row(
                          children: [
                            Expanded(child: joinPgmeCard),
                            SizedBox(width: isTablet ? 16 : 12),
                            // Community links 2x2 grid
                            Expanded(
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 28 : 22,
                                  vertical: isTablet ? 24 : 20,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.darkCardBackground : Colors.white,
                                  borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (topRow.isNotEmpty)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                                        children: topRow,
                                      ),
                                    if (topRow.isNotEmpty && bottomRow.isNotEmpty)
                                      SizedBox(height: isTablet ? 28 : 24),
                                    if (bottomRow.isNotEmpty)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                                        children: bottomRow,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  SizedBox(height: isTablet ? 30 : 24),

                  // Log Out Button
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    child: GestureDetector(
                      onTap: _handleLogout,
                      child: Container(
                        width: double.infinity,
                        height: isTablet ? 62 : 52,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF4D1A1A) : const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF8B3A3A) : const Color(0xFFEF9A9A),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.logout_rounded,
                              size: isTablet ? 25 : 20,
                              color: isDark ? const Color(0xFFEF9A9A) : const Color(0xFFD32F2F),
                            ),
                            SizedBox(width: isTablet ? 10 : 8),
                            Text(
                              'Log Out',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: isTablet ? 19 : 15,
                                color: isDark ? const Color(0xFFEF9A9A) : const Color(0xFFD32F2F),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: MediaQuery.of(context).padding.bottom + (isTablet ? 120 : 32)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatExpiryDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  Widget _buildActivePackageCard({
    required Map<String, dynamic> package,
    required bool isDark,
    bool isTablet = false,
  }) {
    final packageName = package['package_name'] ?? 'Package';
    final packageType = package['type'] ?? '';
    final expiresAt = package['expires_at'];
    final daysRemaining = package['days_remaining'] ?? 0;

    // Use different colors for Theory vs Practical
    final isTheory = packageType == 'Theory';
    final cardColor = isDark
        ? (isTheory ? const Color(0xFF1A1A4D) : const Color(0xFF1A4D4D))
        : (isTheory ? const Color(0xFF0000D1) : const Color(0xFF00897B));

    return Container(
      width: isTablet ? 290 : 240,
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 18 : 14, vertical: isTablet ? 16 : 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(isTablet ? 18 : 14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row with ACTIVE badge and package type
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
                    fontFamily: 'SF Pro Display',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 10 : 8,
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
              fontFamily: 'SF Pro Display',
              fontWeight: FontWeight.w600,
              fontSize: isTablet ? 17 : 14,
              color: Colors.white,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: isTablet ? 12 : 10),
          // Divider
          Opacity(
            opacity: 0.3,
            child: Container(
              height: 1,
              color: Colors.white,
            ),
          ),
          SizedBox(height: isTablet ? 10 : 8),
          // Expires and Days Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: 0.6,
                      child: Text(
                        'EXPIRES',
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontWeight: FontWeight.w500,
                          fontSize: isTablet ? 10 : 8,
                          letterSpacing: 0.5,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                    ),
                    Text(
                      _formatExpiryDate(expiresAt),
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 12 : 10,
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
                  '$daysRemaining days',
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 11 : 9,
                    color: cardColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData? icon,
    required String label,
    required String value,
    required bool showDivider,
    required Color textColor,
    required Color secondaryTextColor,
    required Color iconBgColor,
    required Color iconColor,
    required Color dividerColor,
    bool isTablet = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 16 : 12),
          child: Row(
            children: [
              // Icon circle
              Container(
                width: isTablet ? 52 : 42,
                height: isTablet ? 52 : 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconBgColor,
                ),
                child: icon != null
                    ? Center(
                        child: Icon(
                          icon,
                          size: isTablet ? 27 : 22,
                          color: iconColor,
                        ),
                      )
                    : null,
              ),
              SizedBox(width: isTablet ? 16 : 12),
              // Label and Value
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 13 : 10,
                        height: 1.5,
                        color: secondaryTextColor,
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontWeight: FontWeight.w500,
                        fontSize: isTablet ? 17 : 14,
                        height: 1.4,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16),
            child: Divider(
              height: 1,
              color: dividerColor,
            ),
          ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    required Color cardColor,
    required Color iconBgColor,
    required Color iconColor,
    required Color textColor,
    required Color secondaryTextColor,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: isTablet ? 55 : 44,
              height: isTablet ? 55 : 44,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: isTablet ? 27 : 22,
                  color: iconColor,
                ),
              ),
            ),
            SizedBox(height: isTablet ? 16 : 12),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: isTablet ? 17 : 14,
                color: textColor,
              ),
            ),
            SizedBox(height: isTablet ? 3 : 2),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w400,
                fontSize: isTablet ? 14 : 11,
                color: secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommunityIcon({
    // font_awesome_flutter 11 moved FontAwesomeIcons.* from IconData to its
    // own FaIconData type, which is also what FaIcon now takes.
    required FaIconData icon,
    required Color color,
    required String url,
    required bool isTablet,
  }) {
    final iconSize = isTablet ? 38.0 : 32.0;

    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: FaIcon(icon, size: iconSize, color: color),
    );
  }
}

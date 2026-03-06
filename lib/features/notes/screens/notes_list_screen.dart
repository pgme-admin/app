import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/services/dashboard_service.dart';
import 'package:pgme/core/models/subject_selection_model.dart';
import 'package:pgme/core/models/package_model.dart';
import 'package:pgme/core/utils/responsive_helper.dart';

class NotesListScreen extends StatefulWidget {
  final bool isSubscribed;

  const NotesListScreen({
    super.key,
    this.isSubscribed = false,
  });

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  final DashboardService _dashboardService = DashboardService();
  SubjectSelectionModel? _primarySubject;
  List<PackageModel> _packages = [];
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
      // Fetch subject selections and packages in parallel
      final results = await Future.wait([
        _dashboardService.getSubjectSelections(isPrimary: true),
        _dashboardService.getPackages(),
      ]);

      if (mounted) {
        final subjectSelections = results[0] as List<SubjectSelectionModel>;
        final packages = results[1] as List<PackageModel>;

        setState(() {
          _primarySubject = subjectSelections.isNotEmpty ? subjectSelections.first : null;
          _packages = packages;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF718BA9);
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with back arrow, title, and search
            Padding(
              padding: EdgeInsets.only(top: topPadding + (isTablet ? 21 : 16), left: hPadding, right: hPadding),
              child: Row(
                children: [
                  // Back Arrow - navigates to home
                  GestureDetector(
                    onTap: () {
                      // Navigate back to home tab
                      context.go('/home?subscribed=${widget.isSubscribed}');
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
                  const Spacer(),
                  // Title
                  Text(
                    'My Enrolled Courses',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 20 : 16,
                      height: 1.0,
                      letterSpacing: -0.5,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  // Search icon
                  GestureDetector(
                    onTap: () {
                      // Search functionality
                    },
                    child: SizedBox(
                      width: isTablet ? 30 : 24,
                      height: isTablet ? 30 : 24,
                      child: Icon(
                        Icons.search,
                        size: isTablet ? 30 : 24,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: isTablet ? 31 : 24),

            // Show different content based on subscription status
            if (widget.isSubscribed)
              _buildSubscribedContent(isDark, textColor, secondaryTextColor, iconColor, isTablet, hPadding)
            else
              _buildGuestContent(context, isDark, textColor, secondaryTextColor, iconColor, isTablet, hPadding),

            SizedBox(height: isTablet ? 130 : 100), // Space for bottom nav
          ],
        ),
      ),
        ),
      ),
    );
  }

  // Guest content - Free samples
  Widget _buildGuestContent(BuildContext context, bool isDark, Color textColor, Color secondaryTextColor, Color iconColor, bool isTablet, double hPadding) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Two Gradient Boxes Row
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPadding),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Lecture Box
              _buildLectureBox(context, isSubscribed: widget.isSubscribed, isDark: isDark, isTablet: isTablet),
              SizedBox(width: isTablet ? 16 : 12),
              // Notes Box
              _buildNotesBox(context, isSubscribed: widget.isSubscribed, isDark: isDark, isTablet: isTablet),
            ],
          ),
        ),

        SizedBox(height: isTablet ? 42 : 32),

        // Subject Title Section
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Subject Title',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 25 : 20,
                  height: 1.0,
                  letterSpacing: -0.5,
                  color: textColor,
                ),
              ),
              SizedBox(height: isTablet ? 16 : 12),
              Text(
                'aliqua dolor proident exercitation cillum exercitation laboris voluptate ea reprehenderit eu consequat pariatur qui eu aliqua dolor proident exercitation cillum exercitation laboris voluptate ea reprehenderit eu consequat pariatur qui eu',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w400,
                  fontSize: isTablet ? 17 : 14,
                  height: 1.5,
                  letterSpacing: 0,
                  color: secondaryTextColor,
                ),
              ),
              SizedBox(height: isTablet ? 31 : 24),
              Text(
                'Inclusions',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 25 : 20,
                  height: 1.0,
                  letterSpacing: -0.5,
                  color: textColor,
                ),
              ),
              SizedBox(height: isTablet ? 21 : 16),
              _buildInclusionItem('Ensure your Student ID is visible in your profile name.', textColor, iconColor, isTablet),
              SizedBox(height: isTablet ? 16 : 12),
              _buildInclusionItem('Mute your microphone upon entry to avoid echo in the OR.', textColor, iconColor, isTablet),
              SizedBox(height: isTablet ? 16 : 12),
              _buildInclusionItem('Q&A session will follow the primary procedure.', textColor, iconColor, isTablet),
              SizedBox(height: isTablet ? 16 : 12),
              _buildInclusionItem('Recording will be available 24 hours after the session', textColor, iconColor, isTablet),
            ],
          ),
        ),
      ],
    );
  }

  // Subscribed content - Same layout as guest, just different box text
  Widget _buildSubscribedContent(bool isDark, Color textColor, Color secondaryTextColor, Color iconColor, bool isTablet, double hPadding) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Two Gradient Boxes Row
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPadding),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Lecture Box
              _buildLectureBox(context, isSubscribed: true, isDark: isDark, isTablet: isTablet),
              SizedBox(width: isTablet ? 16 : 12),
              // Notes Box
              _buildNotesBox(context, isSubscribed: true, isDark: isDark, isTablet: isTablet),
            ],
          ),
        ),

        SizedBox(height: isTablet ? 42 : 32),

        // Subject Title Section
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Subject Title',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 25 : 20,
                  height: 1.0,
                  letterSpacing: -0.5,
                  color: textColor,
                ),
              ),
              SizedBox(height: isTablet ? 16 : 12),
              Text(
                'aliqua dolor proident exercitation cillum exercitation laboris voluptate ea reprehenderit eu consequat pariatur qui eu aliqua dolor proident exercitation cillum exercitation laboris voluptate ea reprehenderit eu consequat pariatur qui eu',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w400,
                  fontSize: isTablet ? 17 : 14,
                  height: 1.5,
                  letterSpacing: 0,
                  color: secondaryTextColor,
                ),
              ),
              SizedBox(height: isTablet ? 31 : 24),
              Text(
                'Details',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 25 : 20,
                  height: 1.0,
                  letterSpacing: -0.5,
                  color: textColor,
                ),
              ),
              SizedBox(height: isTablet ? 21 : 16),
              _buildInclusionItem('Ensure your Student ID is visible in your profile name.', textColor, iconColor, isTablet),
              SizedBox(height: isTablet ? 16 : 12),
              _buildInclusionItem('Mute your microphone upon entry to avoid echo in the OR.', textColor, iconColor, isTablet),
              SizedBox(height: isTablet ? 16 : 12),
              _buildInclusionItem('Q&A session will follow the primary procedure.', textColor, iconColor, isTablet),
              SizedBox(height: isTablet ? 16 : 12),
              _buildInclusionItem('Recording will be available 24 hours after the session', textColor, iconColor, isTablet),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLectureBox(BuildContext context, {required bool isSubscribed, required bool isDark, required bool isTablet}) {
    final titleText = isSubscribed ? 'Watch Lecture\nVideo' : 'Free Sample\nLecture';
    final buttonText = isSubscribed ? 'Watch' : 'Check Out';
    final buttonBgColor = isDark ? AppColors.darkSurface : Colors.white;
    final buttonTextColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);

    return Expanded(
      child: Container(
        height: isTablet ? 260 : 211,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(isTablet ? 26 : 20),
          gradient: LinearGradient(
            begin: const Alignment(-0.7, 0.7),
            end: const Alignment(0.7, -0.7),
            colors: isDark
                ? [const Color(0xFF1A3A5C), const Color(0xFF2D5A9E)]
                : [const Color(0xFFEBF3FC), const Color(0xFF8EC6FF)],
            stops: const [0.1752, 0.8495],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Title text
            Positioned(
              top: isTablet ? 26 : 20,
              left: isTablet ? 20 : 16,
              child: Text(
                titleText,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 22 : 18,
                  height: 1.3,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : const Color(0xFF000000),
                ),
              ),
            ),
            // 3.png Image
            Positioned(
              bottom: isTablet ? -80 : -65,
              left: 0,
              child: IgnorePointer(
                child: Image.asset(
                  'assets/illustrations/3.png',
                  width: isTablet ? 310 : 250,
                  height: isTablet ? 310 : 250,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return SizedBox(width: isTablet ? 310 : 250, height: isTablet ? 310 : 250);
                  },
                ),
              ),
            ),
            // Button
            Positioned(
              top: isTablet ? 105 : 84,
              left: isTablet ? 13 : 10,
              child: GestureDetector(
                onTap: () {
                  // Navigate to lecture video
                  // Using Anatomy - Fundamentals series as default
                  if (isSubscribed) {
                    context.push('/lecture/6981eb434c02eb97b950ecdb?subscribed=true');
                  } else {
                    context.push('/lecture/6981eb434c02eb97b950ecdb');
                  }
                },
                child: Container(
                  width: isTablet ? 115 : 92,
                  height: isTablet ? 34 : 27,
                  decoration: BoxDecoration(
                    color: buttonBgColor,
                    borderRadius: BorderRadius.circular(isTablet ? 14 : 10.87),
                  ),
                  child: Center(
                    child: Text(
                      buttonText,
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontWeight: FontWeight.w500,
                        fontSize: isTablet ? 17 : 14,
                        height: 16.73 / 14,
                        letterSpacing: -0.42,
                        color: buttonTextColor,
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

  Widget _buildNotesBox(BuildContext context, {required bool isSubscribed, required bool isDark, required bool isTablet}) {
    final titleText = isSubscribed ? 'View\nNotes' : 'Free Sample\nNotes';
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          // Navigate to available notes with valid series ID
          // Using Anatomy - Fundamentals series as default
          context.push('/available-notes/6981eb434c02eb97b950ecdb');
        },
        child: Container(
          height: isTablet ? 260 : 211,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isTablet ? 26 : 20),
            gradient: LinearGradient(
              begin: const Alignment(-0.7, 0.7),
              end: const Alignment(0.7, -0.7),
              colors: isDark
                  ? [const Color(0xFF1A3A5C), const Color(0xFF2D5A9E)]
                  : [const Color(0xFFEBF3FC), const Color(0xFF8EC6FF)],
              stops: const [0.1752, 0.8495],
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 4.png Image (flipped horizontally) - placed first so title is on top
              Positioned(
                top: isTablet ? -45 : -35,
                right: isTablet ? -170 : -145,
                child: IgnorePointer(
                  child: Transform.flip(
                    flipX: true,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(isTablet ? 18 : 14),
                      child: Image.asset(
                        'assets/illustrations/4.png',
                        width: isTablet ? 480 : 400,
                        height: isTablet ? 480 : 400,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 163,
                            height: 114,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(isTablet ? 18 : 14),
                            ),
                            child: Icon(
                              Icons.folder_outlined,
                              size: isTablet ? 50 : 40,
                              color: iconColor,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              // Title text
              Positioned(
                top: isTablet ? 26 : 20,
                left: isTablet ? 20 : 16,
                child: Text(
                  titleText,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 22 : 18,
                    height: 1.3,
                    letterSpacing: -0.5,
                    color: isDark ? Colors.white : const Color(0xFF000000),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInclusionItem(String text, Color textColor, Color iconColor, bool isTablet) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: isTablet ? 25 : 20,
          height: isTablet ? 25 : 20,
          margin: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.link,
            size: isTablet ? 22 : 18,
            color: iconColor,
          ),
        ),
        SizedBox(width: isTablet ? 16 : 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: isTablet ? 17 : 14,
              height: 1.4,
              letterSpacing: 0,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }
}

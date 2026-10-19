import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/models/subject_model.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';
import 'package:pgme/core_ios/widgets/app_dialog.dart';
import 'package:pgme/features_ios/auth/providers/auth_provider.dart';
import 'package:pgme/features_ios/home/providers/dashboard_provider.dart';
import 'package:pgme/features_ios/onboarding/providers/onboarding_provider.dart';

class SubjectSelectionScreen extends StatefulWidget {
  const SubjectSelectionScreen({super.key});

  @override
  State<SubjectSelectionScreen> createState() => _SubjectSelectionScreenState();
}

class _SubjectSelectionScreenState extends State<SubjectSelectionScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch subjects when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchSubjects();
    });
  }

  Future<void> _fetchSubjects() async {
    try {
      final onboardingProvider = context.read<OnboardingProvider>();
      await onboardingProvider.fetchSubjects();

      // Pre-select the user's current primary subject if available
      if (onboardingProvider.selectedSubject == null && mounted) {
        final primarySubject = context.read<DashboardProvider>().primarySubject;
        if (primarySubject != null) {
          final match = onboardingProvider.subjects.cast<SubjectModel?>().firstWhere(
            (s) => s!.subjectId == primarySubject.subjectId,
            orElse: () => null,
          );
          if (match != null) {
            onboardingProvider.selectSubject(match);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        showAppDialog(context, message: e.toString().replaceAll('Exception: ', ''), actionLabel: 'Retry', onAction: _fetchSubjects);
      }
    }
  }

  /// Check if we're changing subject (already onboarded) vs initial onboarding
  bool get _isChangingSubject {
    final dashboardProvider = context.read<DashboardProvider>();
    return dashboardProvider.primarySubject != null;
  }

  Future<void> _onContinue() async {
    final provider = context.read<OnboardingProvider>();

    if (!provider.hasSelectedSubject) {
      showAppDialog(context, message: 'Please select a subject to continue');
      return;
    }

    // Capture selected subject before any async gap so it's safe to use after await
    final selectedSubject = provider.selectedSubject!;

    try {
      final success = await provider.submitSubjectSelection();
      if (success && mounted) {
        // Use canPop() as the definitive check: if we were pushed onto the
        // stack (from Profile/Dashboard) we can pop back; if we were placed
        // here via context.go() (sign-up / splash) the stack is empty.
        if (_isChangingSubject && context.canPop()) {
          // Changing subject from profile — apply change to dashboard then pop.
          await context.read<DashboardProvider>().applySubjectChange(selectedSubject);
          if (mounted) {
            context.pop(true);
          }
        } else {
          // Initial onboarding — verify profile is complete before finishing
          final user = context.read<AuthProvider>().user;
          final hasProfileData = user != null &&
              (user.name ?? '').trim().isNotEmpty &&
              (user.email ?? '').trim().isNotEmpty &&
              (user.dateOfBirth ?? '').trim().isNotEmpty &&
              (user.gender ?? '').trim().isNotEmpty &&
              (user.address ?? '').trim().isNotEmpty &&
              (user.ugCollege ?? '').trim().isNotEmpty &&
              (user.pgCollege ?? '').trim().isNotEmpty &&
              (user.affiliatedOrganisation ?? '').trim().isNotEmpty &&
              (user.currentDesignation ?? '').trim().isNotEmpty;

          if (!hasProfileData) {
            // Profile incomplete — send to data collection first
            if (mounted) {
              context.go('/data-collection');
            }
          } else {
            await provider.completeOnboarding();
            if (mounted) {
              context.go('/home');
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        showAppDialog(context, message: e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);

    // Responsive sizes
    final backBtnSize = isTablet ? 56.0 : 48.0;
    final backIconSize = isTablet ? 24.0 : 20.0;
    final backBtnRadius = isTablet ? 14.0 : 12.0;
    final logoWidth = isTablet ? 280.0 : 200.0;
    final logoHeight = isTablet ? 74.0 : 53.0;
    final titleSize = isTablet ? 36.0 : 28.0;
    final subtitleSize = isTablet ? 18.0 : 16.0;
    final headerPadding = isTablet ? 24.0 : 16.0;
    final gridHPadding = isTablet ? 40.0 : 24.0;
    const gridCrossCount = 2;
    final gridSpacing = isTablet ? 24.0 : 16.0;
    final gridAspectRatio = isTablet ? 1.15 : 1.0;
    final btnHeight = isTablet ? 72.0 : 54.0;
    final btnFontSize = isTablet ? 20.0 : 16.0;
    final btnRadius = isTablet ? 30.0 : 22.0;
    final btnPadding = isTablet ? 32.0 : 24.0;
    final titleLogoGap = isTablet ? 28.0 : 32.0;
    final titleSubGap = isTablet ? 10.0 : 12.0;
    final subGridGap = isTablet ? 28.0 : 32.0;
    final maxContentWidth = isTablet ? 780.0 : double.infinity;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header with back button
            Padding(
              padding: EdgeInsets.all(headerPadding),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (context.canPop()) {
                        context.pop();
                      }
                    },
                    child: Container(
                      width: backBtnSize,
                      height: backBtnSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(backBtnRadius),
                        border: Border.all(color: AppColors.divider, width: 1),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          size: backIconSize,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Logo
            Image.asset(
              'assets/illustrations/logo2.png',
              width: logoWidth,
              height: logoHeight,
              errorBuilder: (context, error, stackTrace) {
                return SizedBox(width: logoWidth, height: logoHeight);
              },
            ),

            SizedBox(height: titleLogoGap),

            // Title
            Text(
              'Select Your Primary Subject',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: titleSize,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF000000),
              ),
            ),

            SizedBox(height: titleSubGap),

            // Subtitle
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isTablet ? 48.0 : 32.0),
              child: Text(
                'Choose the subject you want to focus on',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: subtitleSize,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
            ),

            SizedBox(height: subGridGap),

            // Subjects Grid
            Expanded(
              child: Consumer<OnboardingProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoadingSubjects) {
                    return const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                      ),
                    );
                  }

                  if (provider.subjects.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: isTablet ? 80 : 64,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No subjects available',
                            style: TextStyle(
                              fontSize: isTablet ? 22 : 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Please try again later',
                            style: TextStyle(
                              fontSize: isTablet ? 16 : 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _fetchSubjects,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                              ),
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxContentWidth),
                      child: GridView.builder(
                        padding: EdgeInsets.symmetric(horizontal: gridHPadding, vertical: 16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: gridCrossCount,
                          crossAxisSpacing: gridSpacing,
                          mainAxisSpacing: gridSpacing,
                          childAspectRatio: gridAspectRatio,
                        ),
                        itemCount: provider.subjects.length,
                        itemBuilder: (context, index) {
                          final subject = provider.subjects[index];
                          final isSelected = provider.selectedSubject?.id == subject.id;

                          return _SubjectCard(
                            subject: subject,
                            isSelected: isSelected,
                            isTablet: isTablet,
                            onTap: () => provider.selectSubject(subject),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),

            // Continue Button
            Padding(
              padding: EdgeInsets.all(btnPadding),
              child: Consumer<OnboardingProvider>(
                builder: (context, provider, _) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isTablet ? 520.0 : double.infinity),
                      child: SizedBox(
                        width: double.infinity,
                        height: btnHeight,
                        child: ElevatedButton(
                          onPressed: provider.isSubmitting ? null : _onContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(btnRadius),
                            ),
                            elevation: 0,
                            padding: EdgeInsets.zero,
                            alignment: Alignment.center,
                          ),
                          child: provider.isSubmitting
                              ? SizedBox(
                                  width: isTablet ? 26 : 20,
                                  height: isTablet ? 26 : 20,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  'Continue',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: btnFontSize,
                                    fontWeight: FontWeight.w600,
                                    height: 1.0,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final SubjectModel subject;
  final bool isSelected;
  final bool isTablet;
  final VoidCallback onTap;

  const _SubjectCard({
    required this.subject,
    required this.isSelected,
    required this.isTablet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardPadding = isTablet ? 16.0 : 12.0;
    final cardRadius = isTablet ? 20.0 : 16.0;
    final iconSize = isTablet ? 60.0 : 48.0;
    final nameSize = isTablet ? 16.0 : 14.0;
    final badgeFontSize = isTablet ? 12.0 : 10.0;
    final badgePaddingH = isTablet ? 12.0 : 8.0;
    final badgePaddingV = isTablet ? 4.0 : 2.0;
    final badgeRadius = isTablet ? 12.0 : 10.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryBlue.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(cardRadius),
          border: Border.all(
            color: isSelected ? AppColors.primaryBlue : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryBlue.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon or placeholder
            if (subject.iconUrl != null && subject.iconUrl!.isNotEmpty)
              Image.network(
                subject.iconUrl!,
                width: iconSize,
                height: iconSize,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.school_outlined,
                    size: iconSize,
                    color: AppColors.primaryBlue,
                  );
                },
              )
            else
              Icon(
                Icons.school_outlined,
                size: iconSize,
                color: AppColors.primaryBlue,
              ),

            SizedBox(height: isTablet ? 12 : 8),

            // Subject name
            Flexible(
              child: Text(
                subject.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: nameSize,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppColors.primaryBlue : AppColors.textPrimary,
                ),
              ),
            ),

            // Selected indicator
            if (isSelected) ...[
              SizedBox(height: isTablet ? 8 : 6),
              Container(
                padding: EdgeInsets.symmetric(horizontal: badgePaddingH, vertical: badgePaddingV),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(badgeRadius),
                ),
                child: Text(
                  'Selected',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: badgeFontSize,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

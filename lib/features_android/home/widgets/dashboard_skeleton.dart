import 'package:flutter/material.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';
import 'package:pgme/core_android/widgets/shimmer_skeleton.dart';

/// Skeleton loading widget for the dashboard
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isTablet = ResponsiveHelper.isTablet(context);

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.getMaxContentWidth(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Skeleton
              _buildHeaderSkeleton(topPadding, isTablet),

              SizedBox(height: isTablet ? 32 : 25),

              // Live Class Banner Skeleton
              _buildLiveClassSkeleton(context, isTablet),

              SizedBox(height: isTablet ? 30 : 24),

              // Subject Badge Skeleton
              _buildSubjectBadgeSkeleton(context, isTablet),

              SizedBox(height: isTablet ? 30 : 24),

              // For You Section Skeleton
              _buildForYouSkeleton(context, isTablet),

              SizedBox(height: isTablet ? 30 : 24),

              // Faculty Section Skeleton
              _buildFacultySkeleton(context, isTablet),

              SizedBox(height: isTablet ? 120 : 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSkeleton(double topPadding, bool isTablet) {
    return Padding(
      padding: EdgeInsets.only(
        top: topPadding + (isTablet ? 20 : 16),
        left: isTablet ? 32 : 23,
        right: isTablet ? 32 : 16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hello text and subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerSkeleton(
                  width: isTablet ? 240 : 180,
                  height: isTablet ? 32 : 24,
                  borderRadius: isTablet ? 8 : 6,
                ),
                SizedBox(height: isTablet ? 10 : 8),
                ShimmerSkeleton(
                  width: isTablet ? 300 : 220,
                  height: isTablet ? 22 : 16,
                  borderRadius: isTablet ? 6 : 4,
                ),
              ],
            ),
          ),
          // Get Help Button and Notification
          Row(
            children: [
              ShimmerSkeleton(
                width: isTablet ? 130 : 103,
                height: isTablet ? 40 : 31,
                borderRadius: 30,
              ),
              SizedBox(width: isTablet ? 16 : 12),
              ShimmerSkeleton.circle(size: isTablet ? 32 : 24),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveClassSkeleton(BuildContext context, bool isTablet) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? ResponsiveHelper.horizontalPadding(context) : 16,
          ),
          child: ShimmerSkeleton(
            width: double.infinity,
            height: isTablet ? 260 : 140,
            borderRadius: isTablet ? 28 : 16,
          ),
        ),
        SizedBox(height: isTablet ? 16 : 12),
        // Indicator dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            3,
            (index) => Padding(
              padding: EdgeInsets.symmetric(horizontal: isTablet ? 6 : 4),
              child: ShimmerSkeleton(
                width: index == 0 ? (isTablet ? 32 : 24) : (isTablet ? 10 : 8),
                height: isTablet ? 10 : 8,
                borderRadius: isTablet ? 5 : 4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectBadgeSkeleton(BuildContext context, bool isTablet) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? ResponsiveHelper.horizontalPadding(context) : 16,
      ),
      child: ShimmerSkeleton(
        width: isTablet ? 160 : 120,
        height: isTablet ? 48 : 36,
        borderRadius: isTablet ? 24 : 20,
      ),
    );
  }

  Widget _buildForYouSkeleton(BuildContext context, bool isTablet) {
    return Column(
      children: [
        // Section Header
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? ResponsiveHelper.horizontalPadding(context) : 16,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShimmerSkeleton(
                width: isTablet ? 110 : 80,
                height: isTablet ? 32 : 24,
                borderRadius: isTablet ? 8 : 6,
              ),
              ShimmerSkeleton(
                width: isTablet ? 90 : 70,
                height: isTablet ? 22 : 16,
                borderRadius: isTablet ? 6 : 4,
              ),
            ],
          ),
        ),
        SizedBox(height: isTablet ? 20 : 16),

        // Content Cards
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? ResponsiveHelper.horizontalPadding(context) : 16,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              const gap = 9.0;
              final resumeCardWidth = (availableWidth - gap) * 0.49;
              final rightColumnWidth = (availableWidth - gap) * 0.51;
              final cardHeight = isTablet ? 420.0 : 281.0;
              final rightCardHeight = isTablet ? 205.5 : 136.0;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Resume Card (Left - Tall)
                  ShimmerSkeleton(
                    width: resumeCardWidth,
                    height: cardHeight,
                    borderRadius: isTablet ? 24 : 18,
                  ),
                  const SizedBox(width: gap),

                  // Right Column
                  SizedBox(
                    width: rightColumnWidth,
                    child: Column(
                      children: [
                        ShimmerSkeleton(
                          width: rightColumnWidth,
                          height: rightCardHeight,
                          borderRadius: isTablet ? 24 : 18,
                        ),
                        const SizedBox(height: 9),
                        ShimmerSkeleton(
                          width: rightColumnWidth,
                          height: rightCardHeight,
                          borderRadius: isTablet ? 24 : 18,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFacultySkeleton(BuildContext context, bool isTablet) {
    return Column(
      children: [
        // Section Header
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? ResponsiveHelper.horizontalPadding(context) : 16,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShimmerSkeleton(
                width: isTablet ? 160 : 120,
                height: isTablet ? 32 : 24,
                borderRadius: isTablet ? 8 : 6,
              ),
              ShimmerSkeleton(
                width: isTablet ? 90 : 70,
                height: isTablet ? 22 : 16,
                borderRadius: isTablet ? 6 : 4,
              ),
            ],
          ),
        ),
        SizedBox(height: isTablet ? 20 : 16),

        // Faculty Cards - using Row instead of ListView
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? ResponsiveHelper.horizontalPadding(context) : 16,
          ),
          child: Row(
            children: List.generate(4, (index) {
              return Padding(
                padding: EdgeInsets.only(right: isTablet ? 16 : 12),
                child: Column(
                  children: [
                    ShimmerSkeleton(
                      width: isTablet ? 140 : 100,
                      height: isTablet ? 140 : 100,
                      borderRadius: isTablet ? 16 : 12,
                    ),
                    SizedBox(height: isTablet ? 10 : 8),
                    ShimmerSkeleton(
                      width: isTablet ? 110 : 80,
                      height: isTablet ? 18 : 14,
                      borderRadius: isTablet ? 6 : 4,
                    ),
                    SizedBox(height: isTablet ? 6 : 4),
                    ShimmerSkeleton(
                      width: isTablet ? 80 : 60,
                      height: isTablet ? 16 : 12,
                      borderRadius: isTablet ? 6 : 4,
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

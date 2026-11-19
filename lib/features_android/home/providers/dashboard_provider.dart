import 'package:flutter/foundation.dart';
import 'package:pgme/core_android/constants/api_constants.dart';
import 'package:pgme/core_android/models/live_session_model.dart';
import 'package:pgme/core_android/models/package_model.dart';
import 'package:pgme/core_android/models/package_type_model.dart';
import 'package:pgme/core_android/models/access_record_model.dart';
import 'package:pgme/core_android/models/video_model.dart';
import 'package:pgme/core_android/models/faculty_model.dart';
import 'package:pgme/core_android/models/subject_model.dart';
import 'package:pgme/core_android/models/subject_selection_model.dart';
import 'package:pgme/core_android/models/banner_model.dart';
import 'package:pgme/core_android/models/home_section_model.dart';
import 'package:pgme/core_android/services/api_service.dart';
import 'package:pgme/core_android/services/dashboard_service.dart';
import 'package:pgme/core_android/services/offline_storage_service.dart';
import 'package:pgme/core_android/services/storage_service.dart';
import 'package:pgme/core_android/services/user_service.dart';
import 'package:pgme/core_android/services/push_notification_service.dart';

class DashboardProvider with ChangeNotifier {
  final DashboardService _dashboardService = DashboardService();
  final StorageService _storageService = StorageService();
  final UserService _userService = UserService();
  final ApiService _apiService = ApiService();

  // State
  String? _userName;
  SubjectSelectionModel? _primarySubject;
  List<LiveSessionModel> _upcomingSessions = [];
  List<PackageModel> _packages = [];
  List<PackageTypeModel> _packageTypes = [];
  VideoModel? _lastWatchedVideo;
  List<FacultyModel> _facultyList = [];
  List<SubjectModel> _allSubjects = [];
  List<BannerModel> _banners = [];
  List<HomeSectionModel> _homeSections = [];

  // Loading states (per section)
  bool _isInitialLoading = true; // Initial dashboard load
  bool _isLoadingSession = false;
  bool _isLoadingSubjects = false;
  bool _isLoadingContent = false;
  bool _isLoadingFaculty = false;
  bool _isRefreshing = false;
  bool _isLoadingAllSubjects = false;
  bool _isChangingSubject = false;

  // Error states (per section)
  String? _sessionError;
  String? _subjectError;
  String? _contentError;
  String? _facultyError;

  // Purchase status (determines For You vs What We Offer)
  bool? _hasActivePurchase;

  // Package-specific subscription status
  bool _hasTheorySubscription = false;
  bool _hasPracticalSubscription = false;
  List<AccessRecordModel> _activePurchases = [];

  // Getters
  String? get userName => _userName;
  SubjectSelectionModel? get primarySubject => _primarySubject;
  List<LiveSessionModel> get upcomingSessions => _upcomingSessions;
  List<PackageModel> get packages => _packages;
  List<PackageTypeModel> get packageTypes => _packageTypes;
  VideoModel? get lastWatchedVideo => _lastWatchedVideo;
  List<FacultyModel> get facultyList => _facultyList;
  List<BannerModel> get banners => _banners;
  List<HomeSectionModel> get homeSections => _homeSections;

  bool get isInitialLoading => _isInitialLoading;
  bool get isLoadingSession => _isLoadingSession;
  bool get isLoadingSubjects => _isLoadingSubjects;
  bool get isLoadingContent => _isLoadingContent;
  bool get isLoadingFaculty => _isLoadingFaculty;
  bool get isRefreshing => _isRefreshing;
  bool get isLoadingAllSubjects => _isLoadingAllSubjects;
  bool get isChangingSubject => _isChangingSubject;
  List<SubjectModel> get allSubjects => _allSubjects;

  String? get sessionError => _sessionError;
  String? get subjectError => _subjectError;
  String? get contentError => _contentError;
  String? get facultyError => _facultyError;

  bool? get hasActivePurchase => _hasActivePurchase;
  bool get hasTheorySubscription => _hasTheorySubscription;
  bool get hasPracticalSubscription => _hasPracticalSubscription;
  List<AccessRecordModel> get activePurchases => _activePurchases;

  /// Main dashboard load method
  /// Loads primary subject first, then other sections in parallel
  Future<void> loadDashboard() async {
    debugPrint('=== DashboardProvider: Loading dashboard ===');

    // Get user name from storage
    _userName = await _getUserName();

    // Load primary subject first (other sections depend on it for filtering)
    await _loadPrimarySubject();

    // Load all other sections in parallel (don't stop on first error)
    await Future.wait([
      // _loadUpcomingSession(), // Disabled: live sessions now shown via banners
      _loadFacultyList(),
      _loadContentSection(),
      _loadBanners(),
      _loadHomeSections(),
    ], eagerError: false);

    // Mark initial loading as complete
    _isInitialLoading = false;
    notifyListeners();
    debugPrint('✓ Dashboard loaded');
  }

  /// Refresh dashboard (for pull-to-refresh)
  Future<void> refresh() async {
    debugPrint('=== DashboardProvider: Refreshing dashboard ===');
    _isRefreshing = true;

    // Clear cache so pull-to-refresh always fetches fresh data
    _dashboardService.clearCache();

    await loadDashboard();

    _isRefreshing = false;
    debugPrint('✓ Dashboard refreshed');
  }

  /// Get user name from storage or user model
  Future<String> _getUserName() async {
    try {
      // Try to get user ID from storage and fetch profile if needed
      final userId = await _storageService.getUserId();
      if (userId != null && userId.isNotEmpty) {
        // For now, return a default greeting
        // In future, you could fetch user profile here if needed
        return 'User';
      }
      return 'User';
    } catch (e) {
      debugPrint('✗ Error getting user name: $e');
      return 'User';
    }
  }

  /// Load primary subject
  Future<void> _loadPrimarySubject() async {
    _isLoadingSubjects = true;
    _subjectError = null;

    try {
      debugPrint('Loading primary subject...');
      final selections = await _dashboardService.getSubjectSelections(isPrimary: true);

      if (selections.isNotEmpty) {
        _primarySubject = selections.first;
        debugPrint('✓ Primary subject loaded: ${_primarySubject!.subjectName}');
      } else {
        _primarySubject = null;
        debugPrint('⚠ No primary subject found');
      }
    } catch (e) {
      _subjectError = e.toString().replaceAll('Exception: ', '');
      debugPrint('✗ Error loading primary subject: $_subjectError');
    } finally {
      _isLoadingSubjects = false;
    }
  }

  /// Load upcoming live sessions (multiple for carousel)
  Future<void> _loadUpcomingSession() async {
    _isLoadingSession = true;
    _sessionError = null;

    try {
      debugPrint('Loading upcoming sessions...');

      // Fetch upcoming/live sessions for carousel (no subject filter —
      // users should see all live sessions regardless of their primary subject)
      final sessions = await _dashboardService.getLiveSessions(
        upcomingOnly: true,
        limit: 5,
      );

      final userSubjectIds = _primarySubject != null ? [_primarySubject!.subjectId] : <String>[];
      _upcomingSessions = sessions.where((session) {
        if (session.visibleTo == 'subject') {
          if (session.visibleToSubjects.isEmpty) return false;
          if (userSubjectIds.isEmpty) return false;
          return session.visibleToSubjects.any((id) => userSubjectIds.contains(id));
        }
        return true;
      }).toList();

      if (sessions.isNotEmpty) {
        debugPrint('✓ ${sessions.length} upcoming sessions loaded');
      } else {
        debugPrint('⚠ No upcoming sessions');
      }
    } catch (e) {
      _sessionError = e.toString().replaceAll('Exception: ', '');
      debugPrint('✗ Error loading upcoming sessions: $_sessionError');
    } finally {
      _isLoadingSession = false;
    }
  }

  /// Load faculty list filtered by primary subject
  Future<void> _loadFacultyList() async {
    _isLoadingFaculty = true;
    _facultyError = null;

    try {
      debugPrint('Loading faculty list...');

      // Filter faculty by primary subject's ID
      _facultyList = await _dashboardService.getFaculty(
        limit: 10,
        subjectId: _primarySubject?.subjectId,
      );

      debugPrint('✓ Faculty list loaded: ${_facultyList.length} members'
          '${_primarySubject != null ? ' (filtered by ${_primarySubject!.subjectName})' : ''}');
    } catch (e) {
      _facultyError = e.toString().replaceAll('Exception: ', '');
      debugPrint('✗ Error loading faculty: $_facultyError');
    } finally {
      _isLoadingFaculty = false;
    }
  }

  /// Load banners for carousel
  Future<void> _loadBanners() async {
    try {
      debugPrint('Loading banners...');
      final allBanners = await _dashboardService.getBanners();
      debugPrint('[BANNER_DEBUG] Fetched ${allBanners.length} banners from API');

      for (final b in allBanners) {
        debugPrint('[BANNER_DEBUG] Banner "${b.title}": visibleTo="${b.visibleTo}", visibleToSubjects=${b.visibleToSubjects}');
      }

      // App-level visibility filter — only use primary (current) subject
      final userSubjectIds = _primarySubject != null ? [_primarySubject!.subjectId] : <String>[];
      debugPrint('[BANNER_DEBUG] User primary subject: $userSubjectIds');

      _banners = allBanners.where((banner) {
        if (banner.visibleTo == 'subject') {
          if (banner.visibleToSubjects.isEmpty) {
            debugPrint('[BANNER_DEBUG] HIDE "${banner.title}": visibleTo=subject but empty subjects list');
            return false;
          }
          if (userSubjectIds.isEmpty) {
            debugPrint('[BANNER_DEBUG] HIDE "${banner.title}": user has no subjects');
            return false;
          }
          final match = banner.visibleToSubjects.any(
            (subjectId) => userSubjectIds.contains(subjectId),
          );
          debugPrint('[BANNER_DEBUG] ${match ? "SHOW" : "HIDE"} "${banner.title}": bannerSubjects=${banner.visibleToSubjects} vs userSubjects=$userSubjectIds');
          return match;
        }
        debugPrint('[BANNER_DEBUG] SHOW "${banner.title}": visibleTo="${banner.visibleTo}" (pass-through)');
        return true;
      }).toList();

      debugPrint('[BANNER_DEBUG] Final: ${_banners.length} banners after filter');
    } catch (e) {
      debugPrint('✗ Error loading banners: $e');
      _banners = [];
    }
  }

  /// Load dynamic home sections (public endpoint) with client-side visibility filtering
  Future<void> _loadHomeSections() async {
    try {
      debugPrint('Loading home sections...');
      final allSections = await _dashboardService.getHomeSections();

      // Client-side visibility filter — same logic as banners
      final userSubjectIds = _primarySubject != null ? [_primarySubject!.subjectId] : <String>[];

      _homeSections = allSections.where((section) {
        if (section.visibleTo == 'subject') {
          if (section.visibleToSubjects.isEmpty) return false;
          if (userSubjectIds.isEmpty) return false;
          return section.visibleToSubjects.any(
            (subjectId) => userSubjectIds.contains(subjectId),
          );
        }
        return true;
      }).toList();

      debugPrint('✓ Home sections loaded: ${_homeSections.length} (from ${allSections.length})');
    } catch (e) {
      debugPrint('✗ Error loading home sections: $e');
      _homeSections = [];
    }
  }

  /// Load content section (For You or What We Offer)
  /// Determines purchase status and loads appropriate content
  Future<void> _loadContentSection() async {
    _isLoadingContent = true;
    _contentError = null;

    try {
      debugPrint('Loading content section...');

      // Check if user has any active package purchases
      _hasActivePurchase = await _dashboardService.hasActivePurchases();
      debugPrint('✓ Active purchase status: $_hasActivePurchase');

      // Load package-specific subscriptions
      await _loadSubscriptionsByType();

      // Always load packages for the current subject (they now include is_purchased flag)
      try {
        debugPrint('Loading packages...');
        _packages = await _dashboardService.getPackages(
          subjectId: _primarySubject?.subjectId,
        );
        debugPrint('✓ ${_packages.length} packages loaded');

        // Update subscription flags based on packages' isPurchased status
        _hasTheorySubscription = _packages.any((p) => p.isPurchased && p.type?.toLowerCase() == 'theory');
        _hasPracticalSubscription = _packages.any((p) => p.isPurchased && p.type?.toLowerCase() == 'practical');
        debugPrint('  Theory subscription: $_hasTheorySubscription');
        debugPrint('  Practical subscription: $_hasPracticalSubscription');
      } catch (e) {
        _contentError = e.toString().replaceAll('Exception: ', '');
        debugPrint('✗ Error loading packages: $_contentError');
      }

      if (_hasActivePurchase == true) {
        // User has active purchase - try to get last watched video
        try {
          final videos = await _dashboardService.getLastWatchedVideos(
            limit: 1,
            subjectId: _primarySubject?.subjectId,
          );
          if (videos.isNotEmpty) {
            _lastWatchedVideo = videos.first;
            debugPrint('  Last watched: ${_lastWatchedVideo!.title}');
            // Cache locally for offline fallback
            await OfflineStorageService()
                .saveLastWatchedVideo(_lastWatchedVideo!.toJson());
          }
        } catch (e) {
          debugPrint('⚠ Error getting watch history (trying local): $e');
          // Offline fallback — show whatever was cached from last session
          try {
            final localJson =
                await OfflineStorageService().getLastWatchedVideo();
            if (localJson != null) {
              _lastWatchedVideo = VideoModel.fromJson(localJson);
              debugPrint(
                  '  Last watched (local): ${_lastWatchedVideo!.title}');
            }
          } catch (localErr) {
            debugPrint('⚠ Error loading local last watched: $localErr');
          }
        }
      } else {
        // No active purchase - load package types for "What We Offer" section
        _lastWatchedVideo = null;
        try {
          debugPrint('Loading package types for What We Offer section...');
          _packageTypes = await _dashboardService.getPackageTypes();
          debugPrint('✓ ${_packageTypes.length} package types loaded');
        } catch (e) {
          debugPrint('⚠ Error loading package types: $e');
        }
      }
    } catch (e) {
      _contentError = e.toString().replaceAll('Exception: ', '');
      debugPrint('✗ Error loading content section: $_contentError');
    } finally {
      _isLoadingContent = false;
    }
  }

  /// Load user's subscription status from dedicated API
  Future<void> _loadSubscriptionsByType() async {
    try {
      debugPrint('Loading subscription status from API...');

      final response = await _apiService.dio.get(
        ApiConstants.activeAccessLevel,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'];

        _hasTheorySubscription = data['has_theory'] == true;
        _hasPracticalSubscription = data['has_practical'] == true;

        debugPrint('✓ Subscription status loaded from API:');
        debugPrint('  Theory: $_hasTheorySubscription');
        debugPrint('  Practical: $_hasPracticalSubscription');
        debugPrint('  Has Both: ${data['has_both']}');
        debugPrint('  Total Active: ${data['total_active_subscriptions']}');

        // Log package details if available
        final theoryPackages = data['theory_packages'] as List?;
        final practicalPackages = data['practical_packages'] as List?;

        if (theoryPackages != null && theoryPackages.isNotEmpty) {
          for (final pkg in theoryPackages) {
            debugPrint('  Theory Package: ${pkg['package_name']} (expires: ${pkg['expires_at']})');
          }
        }

        if (practicalPackages != null && practicalPackages.isNotEmpty) {
          for (final pkg in practicalPackages) {
            debugPrint('  Practical Package: ${pkg['package_name']} (expires: ${pkg['expires_at']})');
          }
        }
      } else {
        throw Exception('Failed to load subscription status');
      }
    } catch (e) {
      debugPrint('⚠ Error loading subscription status: $e');
      // On error, keep existing subscription values instead of locking content.
      // The package list load (below) will also set these flags as a fallback.
    }
  }

  /// Optimistically update the resume card after the user finishes watching a
  /// video. Call this from the video player screen on pop (or listen to route
  /// changes) so the home screen shows the correct last-watched title and
  /// remaining time without a full dashboard reload.
  void updateLastWatchedLocally(VideoModel video) {
    _lastWatchedVideo = video;
    notifyListeners();
  }

  /// Retry loading primary subject
  Future<void> retrySubject() async {
    debugPrint('=== Retrying primary subject ===');
    await _loadPrimarySubject();
    notifyListeners();
  }

  /// Retry loading upcoming session
  Future<void> retrySession() async {
    debugPrint('=== Retrying upcoming session ===');
    // await _loadUpcomingSession(); // Disabled: live sessions now shown via banners
    notifyListeners();
  }

  /// Retry loading faculty list
  Future<void> retryFaculty() async {
    debugPrint('=== Retrying faculty list ===');
    await _loadFacultyList();
    notifyListeners();
  }

  /// Retry loading content section
  Future<void> retryContent() async {
    debugPrint('=== Retrying content section ===');
    await _loadContentSection();
    notifyListeners();
  }

  /// Fetch all available subjects for subject picker
  Future<void> fetchAllSubjects() async {
    if (_allSubjects.isNotEmpty) {
      // Already loaded
      return;
    }

    _isLoadingAllSubjects = true;
    notifyListeners();

    try {
      debugPrint('Fetching all subjects...');
      final subjectsData = await _userService.getSubjects();
      _allSubjects = subjectsData
          .map((json) => SubjectModel.fromJson(json))
          .where((s) => s.isActive)
          .toList();
      debugPrint('✓ ${_allSubjects.length} subjects loaded');
    } catch (e) {
      debugPrint('✗ Error fetching subjects: $e');
    } finally {
      _isLoadingAllSubjects = false;
      notifyListeners();
    }
  }

  /// Apply a subject change after the backend has already been updated
  /// (e.g. via OnboardingService). Optimistically updates the local
  /// [_primarySubject] state immediately so the home screen reflects the
  /// new subject at once, then reloads all subject-dependent content.
  Future<void> applySubjectChange(SubjectModel subject) async {
    _isChangingSubject = true;

    // Optimistic update — home screen shows new subject name instantly
    _primarySubject = SubjectSelectionModel(
      selectionId: 'local_${subject.subjectId}',
      subjectId: subject.subjectId,
      subjectName: subject.name,
      subjectDescription: subject.description,
      subjectIconUrl: subject.iconUrl,
      isPrimary: true,
      selectedAt: DateTime.now().toIso8601String(),
    );
    notifyListeners();

    try {
      // Subscribe to FCM topic for the new subject
      PushNotificationService().subscribeToSubject(subject.subjectId);

      // Clear cache so all content APIs fetch fresh data for the new subject
      _dashboardService.clearCache();

      // Reload all subject-dependent sections in parallel
      await Future.wait([
        // _loadUpcomingSession(), // Disabled: live sessions now shown via banners
        _loadContentSection(),
        _loadFacultyList(),
      ]);
    } finally {
      _isChangingSubject = false;
      notifyListeners();
    }
  }

  /// Change primary subject
  Future<bool> changePrimarySubject(SubjectModel subject) async {
    _isChangingSubject = true;
    notifyListeners();

    try {
      debugPrint('Changing primary subject to: ${subject.name}');

      // Update on backend
      await _userService.updateSubjectSelection(
        subjectId: subject.subjectId,
        isPrimary: true,
      );

      // Subscribe to FCM topic for this subject
      PushNotificationService().subscribeToSubject(subject.subjectId);

      // Update local state
      _primarySubject = SubjectSelectionModel(
        selectionId: 'local_${subject.subjectId}',
        subjectId: subject.subjectId,
        subjectName: subject.name,
        subjectDescription: subject.description,
        subjectIconUrl: subject.iconUrl,
        isPrimary: true,
        selectedAt: DateTime.now().toIso8601String(),
      );

      debugPrint('✓ Primary subject changed to: ${subject.name}');

      // Clear cache and reload dashboard content
      _dashboardService.clearCache();

      // Reload sessions, content, and faculty with new subject
      await Future.wait([
        // _loadUpcomingSession(), // Disabled: live sessions now shown via banners
        _loadContentSection(),
        _loadFacultyList(),
      ]);

      _isChangingSubject = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('✗ Error changing subject: $e');
      _isChangingSubject = false;
      notifyListeners();
      return false;
    }
  }

  /// Clear all dashboard data
  void clearDashboard() {
    debugPrint('=== DashboardProvider: Clearing dashboard ===');

    _userName = null;
    _primarySubject = null;
    _upcomingSessions = [];
    _packages = [];
    _packageTypes = [];
    _lastWatchedVideo = null;
    _facultyList = [];
    _banners = [];
    _homeSections = [];

    _isInitialLoading = true; // Reset for next login
    _isLoadingSession = false;
    _isLoadingSubjects = false;
    _isLoadingContent = false;
    _isLoadingFaculty = false;
    _isRefreshing = false;

    _sessionError = null;
    _subjectError = null;
    _contentError = null;
    _facultyError = null;

    _hasActivePurchase = null;
    _hasTheorySubscription = false;
    _hasPracticalSubscription = false;
    _activePurchases = [];

    _dashboardService.clearCache();

    notifyListeners();
    debugPrint('✓ Dashboard cleared');
  }
}

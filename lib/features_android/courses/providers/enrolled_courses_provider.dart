import 'package:flutter/foundation.dart';
import 'package:pgme/core_android/models/access_record_model.dart';
import 'package:pgme/core_android/models/series_model.dart';
import 'package:pgme/core_android/models/progress_model.dart';
import 'package:pgme/core_android/models/library_model.dart';
import 'package:pgme/core_android/services/enrolled_courses_service.dart';

class EnrolledCoursesProvider with ChangeNotifier {
  final EnrolledCoursesService _enrolledCoursesService = EnrolledCoursesService();

  // State - Purchases
  List<AccessRecordModel> _purchases = [];
  AccessRecordModel? _selectedPurchase;

  // State - Series
  List<SeriesModel> _theorySeries = [];
  List<SeriesModel> _practicalSeries = [];

  // State - Progress
  List<ProgressModel> _progressList = [];
  List<ProgressModel> _continueWatchingList = [];

  // State - Library
  List<LibraryModel> _libraryItems = [];

  // Loading states (per section)
  bool _isLoadingPurchases = false;
  bool _isLoadingDetails = false;
  bool _isLoadingSeries = false;
  bool _isLoadingProgress = false;
  bool _isLoadingLibrary = false;
  bool _isRefreshing = false;

  // Error states (per section)
  String? _purchasesError;
  String? _detailsError;
  String? _seriesError;
  String? _progressError;
  String? _libraryError;

  // Getters - State
  List<AccessRecordModel> get purchases => _purchases;
  AccessRecordModel? get selectedPurchase => _selectedPurchase;
  List<SeriesModel> get theorySeries => _theorySeries;
  List<SeriesModel> get practicalSeries => _practicalSeries;
  List<ProgressModel> get progressList => _progressList;
  List<ProgressModel> get continueWatchingList => _continueWatchingList;
  List<LibraryModel> get libraryItems => _libraryItems;

  // Getters - Loading states
  bool get isLoadingPurchases => _isLoadingPurchases;
  bool get isLoadingDetails => _isLoadingDetails;
  bool get isLoadingSeries => _isLoadingSeries;
  bool get isLoadingProgress => _isLoadingProgress;
  bool get isLoadingLibrary => _isLoadingLibrary;
  bool get isRefreshing => _isRefreshing;

  // Getters - Error states
  String? get purchasesError => _purchasesError;
  String? get detailsError => _detailsError;
  String? get seriesError => _seriesError;
  String? get progressError => _progressError;
  String? get libraryError => _libraryError;

  // Computed getters
  List<AccessRecordModel> get activePurchases =>
      _purchases.where((p) => p.isActive).toList();

  List<AccessRecordModel> get expiredPurchases =>
      _purchases.where((p) => !p.isActive).toList();

  bool get hasActivePurchases => activePurchases.isNotEmpty;

  /// Load all purchases for the user
  Future<void> loadPurchases() async {
    _isLoadingPurchases = true;
    _purchasesError = null;
    notifyListeners();

    try {
      debugPrint('=== EnrolledCoursesProvider: Loading purchases ===');
      _purchases = await _enrolledCoursesService.getPurchases();
      debugPrint('✓ ${_purchases.length} purchases loaded');
    } catch (e) {
      _purchasesError = e.toString().replaceAll('Exception: ', '');
      debugPrint('✗ Error loading purchases: $_purchasesError');
    } finally {
      _isLoadingPurchases = false;
      notifyListeners();
    }
  }

  /// Load recent progress for Continue Watching section
  /// Gets the most recent 5 incomplete videos across all purchases
  Future<void> loadRecentProgress() async {
    _isLoadingProgress = true;
    _progressError = null;
    notifyListeners();

    try {
      debugPrint('=== EnrolledCoursesProvider: Loading recent progress ===');

      final allProgress = await _enrolledCoursesService.getProgress(
        limit: 5,
        isCompleted: false,
      );

      _progressList = allProgress;
      _continueWatchingList = allProgress
          .where((p) => !p.isCompleted && p.completionPercentage > 0)
          .toList();

      debugPrint('✓ ${_continueWatchingList.length} items in continue watching');
    } catch (e) {
      _progressError = e.toString().replaceAll('Exception: ', '');
      debugPrint('✗ Error loading recent progress: $_progressError');
    } finally {
      _isLoadingProgress = false;
      notifyListeners();
    }
  }

  /// Load purchase details by ID
  /// Sets the selectedPurchase and loads related data
  Future<void> loadPurchaseDetails(String purchaseId) async {
    _isLoadingDetails = true;
    _detailsError = null;
    notifyListeners();

    try {
      debugPrint('=== EnrolledCoursesProvider: Loading purchase details ===');
      _selectedPurchase = await _enrolledCoursesService.getPurchaseDetails(purchaseId);
      debugPrint('✓ Purchase details loaded: ${_selectedPurchase!.package.name}');

      // Load series and progress for this purchase in parallel
      await Future.wait([
        _loadSeriesForPurchase(purchaseId),
        _loadProgressForPurchase(purchaseId),
      ], eagerError: false);
    } catch (e) {
      _detailsError = e.toString().replaceAll('Exception: ', '');
      debugPrint('✗ Error loading purchase details: $_detailsError');
    } finally {
      _isLoadingDetails = false;
      notifyListeners();
    }
  }

  /// Load series for a purchase (theory and practical)
  Future<void> _loadSeriesForPurchase(String purchaseId, {bool forceRefresh = false}) async {
    _isLoadingSeries = true;
    _seriesError = null;

    try {
      debugPrint('Loading series for purchase...');

      final allSeries = await _enrolledCoursesService.getSeries(
        purchaseId: purchaseId,
        forceRefresh: forceRefresh,
      );

      // Separate theory and practical series
      _theorySeries = allSeries.where((s) => s.type == 'theory').toList();
      _practicalSeries = allSeries.where((s) => s.type == 'practical').toList();

      debugPrint('✓ Series loaded: ${_theorySeries.length} theory, ${_practicalSeries.length} practical');
    } catch (e) {
      _seriesError = e.toString().replaceAll('Exception: ', '');
      debugPrint('✗ Error loading series: $_seriesError');
    } finally {
      _isLoadingSeries = false;
    }
  }

  /// Load progress for a purchase
  Future<void> _loadProgressForPurchase(String purchaseId) async {
    _isLoadingProgress = true;
    _progressError = null;

    try {
      debugPrint('Loading progress for purchase...');

      _progressList = await _enrolledCoursesService.getProgress(
        purchaseId: purchaseId,
      );

      // Filter incomplete progress for "Continue Watching" section
      _continueWatchingList = _progressList
          .where((p) => !p.isCompleted && p.completionPercentage > 0)
          .toList();

      debugPrint('✓ Progress loaded: ${_progressList.length} total, ${_continueWatchingList.length} in progress');
    } catch (e) {
      _progressError = e.toString().replaceAll('Exception: ', '');
      debugPrint('✗ Error loading progress: $_progressError');
    } finally {
      _isLoadingProgress = false;
    }
  }

  /// Update or create progress for a lecture
  /// Call this when user watches a video
  Future<bool> updateLectureProgress({
    required String lectureId,
    required int lastWatchedPositionSeconds,
    required int watchTimeSeconds,
    required bool isCompleted,
    required int completionPercentage,
  }) async {
    try {
      debugPrint('=== EnrolledCoursesProvider: Updating lecture progress ===');

      final updatedProgress = await _enrolledCoursesService.updateProgress(
        lectureId: lectureId,
        lastWatchedPositionSeconds: lastWatchedPositionSeconds,
        watchTimeSeconds: watchTimeSeconds,
        isCompleted: isCompleted,
        completionPercentage: completionPercentage,
      );

      // Update the progress in local state
      final index = _progressList.indexWhere((p) => p.lecture.lectureId == lectureId);
      if (index != -1) {
        _progressList[index] = updatedProgress;
      } else {
        _progressList.add(updatedProgress);
      }

      // Update continue watching list
      _continueWatchingList = _progressList
          .where((p) => !p.isCompleted && p.completionPercentage > 0)
          .toList();

      notifyListeners();
      debugPrint('✓ Progress updated successfully');
      return true;
    } catch (e) {
      debugPrint('✗ Error updating progress: $e');
      return false;
    }
  }

  /// Load library items
  Future<void> loadLibrary({String? purchaseId}) async {
    _isLoadingLibrary = true;
    _libraryError = null;
    notifyListeners();

    try {
      debugPrint('=== EnrolledCoursesProvider: Loading library ===');
      _libraryItems = await _enrolledCoursesService.getLibrary(
        purchaseId: purchaseId,
      );
      debugPrint('✓ ${_libraryItems.length} library items loaded');
    } catch (e) {
      _libraryError = e.toString().replaceAll('Exception: ', '');
      debugPrint('✗ Error loading library: $_libraryError');
    } finally {
      _isLoadingLibrary = false;
      notifyListeners();
    }
  }

  /// Add a document to library
  Future<bool> addDocumentToLibrary(String documentId) async {
    try {
      debugPrint('=== EnrolledCoursesProvider: Adding to library ===');

      final libraryItem = await _enrolledCoursesService.addToLibrary(
        documentId: documentId,
      );

      // Add to local state
      _libraryItems.insert(0, libraryItem);
      notifyListeners();

      debugPrint('✓ Document added to library');
      return true;
    } catch (e) {
      debugPrint('✗ Error adding to library: $e');
      return false;
    }
  }

  /// Remove a document from library
  Future<bool> removeDocumentFromLibrary(String libraryId) async {
    try {
      debugPrint('=== EnrolledCoursesProvider: Removing from library ===');

      final success = await _enrolledCoursesService.removeFromLibrary(
        libraryId: libraryId,
      );

      if (success) {
        // Remove from local state
        _libraryItems.removeWhere((item) => item.libraryId == libraryId);
        notifyListeners();
        debugPrint('✓ Document removed from library');
      }

      return success;
    } catch (e) {
      debugPrint('✗ Error removing from library: $e');
      return false;
    }
  }

  /// Refresh purchases list (for pull-to-refresh)
  Future<void> refreshPurchases() async {
    _isRefreshing = true;

    await loadPurchases();

    _isRefreshing = false;
    notifyListeners();
  }

  /// Refresh purchase details and related data
  Future<void> refreshPurchaseDetails() async {
    if (_selectedPurchase == null) return;

    _isRefreshing = true;
    notifyListeners();

    await loadPurchaseDetails(_selectedPurchase!.purchaseId);

    _isRefreshing = false;
    notifyListeners();
  }

  /// Refresh library
  Future<void> refreshLibrary({String? purchaseId}) async {
    _isRefreshing = true;
    notifyListeners();

    await loadLibrary(purchaseId: purchaseId);

    _isRefreshing = false;
    notifyListeners();
  }

  /// Retry loading purchases
  Future<void> retryPurchases() async {
    debugPrint('=== Retrying purchases ===');
    await loadPurchases();
  }

  /// Retry loading purchase details
  Future<void> retryDetails() async {
    if (_selectedPurchase == null) return;

    debugPrint('=== Retrying purchase details ===');
    await loadPurchaseDetails(_selectedPurchase!.purchaseId);
  }

  /// Retry loading series
  Future<void> retrySeries() async {
    if (_selectedPurchase == null) return;

    debugPrint('=== Retrying series ===');
    await _loadSeriesForPurchase(_selectedPurchase!.purchaseId, forceRefresh: true);
    notifyListeners();
  }

  /// Retry loading progress
  Future<void> retryProgress() async {
    if (_selectedPurchase == null) return;

    debugPrint('=== Retrying progress ===');
    await _loadProgressForPurchase(_selectedPurchase!.purchaseId);
    notifyListeners();
  }

  /// Retry loading library
  Future<void> retryLibrary({String? purchaseId}) async {
    debugPrint('=== Retrying library ===');
    await loadLibrary(purchaseId: purchaseId);
  }

  /// Clear all enrolled courses data
  void clearEnrolledCourses() {
    debugPrint('=== EnrolledCoursesProvider: Clearing enrolled courses ===');

    _purchases = [];
    _selectedPurchase = null;
    _theorySeries = [];
    _practicalSeries = [];
    _progressList = [];
    _continueWatchingList = [];
    _libraryItems = [];

    _isLoadingPurchases = false;
    _isLoadingDetails = false;
    _isLoadingSeries = false;
    _isLoadingProgress = false;
    _isLoadingLibrary = false;
    _isRefreshing = false;

    _purchasesError = null;
    _detailsError = null;
    _seriesError = null;
    _progressError = null;
    _libraryError = null;

    _enrolledCoursesService.clearCache();

    notifyListeners();
    debugPrint('✓ Enrolled courses cleared');
  }

  /// Select a purchase and load its details
  Future<void> selectPurchase(String purchaseId) async {
    debugPrint('=== EnrolledCoursesProvider: Selecting purchase ===');
    await loadPurchaseDetails(purchaseId);
  }

  /// Get progress for a specific lecture
  ProgressModel? getProgressForLecture(String lectureId) {
    try {
      return _progressList.firstWhere((p) => p.lecture.lectureId == lectureId);
    } catch (e) {
      return null;
    }
  }

  /// Check if a document is in library
  bool isDocumentInLibrary(String documentId) {
    return _libraryItems.any((item) => item.document.documentId == documentId);
  }

  /// Get library item by document ID
  LibraryModel? getLibraryItemByDocumentId(String documentId) {
    try {
      return _libraryItems.firstWhere((item) => item.document.documentId == documentId);
    } catch (e) {
      return null;
    }
  }
}

import 'package:flutter/material.dart';
import 'package:pgme/core_android/models/subject_model.dart';
import 'package:pgme/core_android/services/onboarding_service.dart';
import 'package:pgme/core_android/services/storage_service.dart';
import 'package:pgme/core_android/services/push_notification_service.dart';

class OnboardingProvider with ChangeNotifier {
  final OnboardingService _onboardingService = OnboardingService();
  final StorageService _storageService = StorageService();

  // Carousel state
  int _currentPage = 0;
  bool _hasSeenOnboarding = false;

  // Subject selection state
  List<SubjectModel> _subjects = [];
  SubjectModel? _selectedSubject;
  bool _isLoadingSubjects = false;
  bool _isSubmitting = false;
  String? _error;

  // Getters - Carousel
  int get currentPage => _currentPage;
  bool get hasSeenOnboarding => _hasSeenOnboarding;

  // Getters - Subjects
  List<SubjectModel> get subjects => _subjects;
  SubjectModel? get selectedSubject => _selectedSubject;
  bool get isLoadingSubjects => _isLoadingSubjects;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;
  bool get hasSelectedSubject => _selectedSubject != null;

  // Carousel methods
  void setCurrentPage(int page) {
    _currentPage = page;
    notifyListeners();
  }

  void nextPage() {
    if (_currentPage < 3) {
      _currentPage++;
      notifyListeners();
    }
  }

  void previousPage() {
    if (_currentPage > 0) {
      _currentPage--;
      notifyListeners();
    }
  }

  void reset() {
    _currentPage = 0;
    notifyListeners();
  }

  // Subject selection methods

  /// Fetch all subjects from API
  Future<void> fetchSubjects() async {
    _isLoadingSubjects = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('OnboardingProvider: Fetching subjects');
      _subjects = await _onboardingService.getSubjects();
      debugPrint('OnboardingProvider: Fetched ${_subjects.length} subjects');
    } catch (e) {
      debugPrint('OnboardingProvider: Error fetching subjects: $e');
      _error = e.toString().replaceAll('Exception: ', '');
      rethrow;
    } finally {
      _isLoadingSubjects = false;
      notifyListeners();
    }
  }

  /// Select a subject
  void selectSubject(SubjectModel subject) {
    _selectedSubject = subject;
    _error = null;
    notifyListeners();
    debugPrint('OnboardingProvider: Selected subject: ${subject.name}');
  }

  /// Clear subject selection
  void clearSelection() {
    _selectedSubject = null;
    notifyListeners();
  }

  /// Submit subject selection to API
  Future<bool> submitSubjectSelection() async {
    if (_selectedSubject == null) {
      _error = 'Please select a subject';
      notifyListeners();
      return false;
    }

    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('OnboardingProvider: Submitting subject selection');
      await _onboardingService.updateSubjectSelection(_selectedSubject!.subjectId);
      debugPrint('OnboardingProvider: Subject selection submitted successfully');

      // Subscribe to FCM topic for this subject
      PushNotificationService().subscribeToSubject(_selectedSubject!.subjectId);

      return true;
    } catch (e) {
      debugPrint('OnboardingProvider: Error submitting subject: $e');
      _error = e.toString().replaceAll('Exception: ', '');
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Complete onboarding process
  Future<bool> completeOnboarding() async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('OnboardingProvider: Completing onboarding');
      await _onboardingService.completeOnboarding();

      // Update local storage
      await _storageService.saveOnboardingStatus(true);
      _hasSeenOnboarding = true;

      debugPrint('OnboardingProvider: Onboarding completed successfully');
      return true;
    } catch (e) {
      debugPrint('OnboardingProvider: Error completing onboarding: $e');
      _error = e.toString().replaceAll('Exception: ', '');
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Clear error message
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Reset all onboarding state
  void resetOnboarding() {
    _currentPage = 0;
    _selectedSubject = null;
    _subjects = [];
    _error = null;
    _isLoadingSubjects = false;
    _isSubmitting = false;
    notifyListeners();
  }
}

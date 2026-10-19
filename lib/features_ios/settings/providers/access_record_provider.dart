import 'package:flutter/foundation.dart';
import 'package:pgme/core_ios/models/access_record_model.dart';
import 'package:pgme/core_ios/services/access_record_service.dart';

class AccessRecordProvider with ChangeNotifier {
  final AccessRecordService _accessRecordService = AccessRecordService();

  // State
  List<AccessRecordModel> _records = [];
  AccessLevel? _accessStatus;
  bool _isLoading = false;
  String? _error;

  // Getters
  List<AccessRecordModel> get records => _records;
  AccessLevel? get accessStatus => _accessStatus;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Get active records only
  List<AccessRecordModel> get activeRecords =>
      _records.where((p) => p.isActive && p.daysRemaining > 0).toList();

  /// Get expired records
  List<AccessRecordModel> get expiredRecords =>
      _records.where((p) => !p.isActive || p.daysRemaining <= 0).toList();

  /// Get the primary active access (most recent or longest remaining)
  AccessRecordModel? get primaryAccess {
    final active = activeRecords;
    if (active.isEmpty) return null;
    // Return the one with most days remaining
    active.sort((a, b) => b.daysRemaining.compareTo(a.daysRemaining));
    return active.first;
  }

  /// Check if user has any active access
  bool get hasActiveAccess => activeRecords.isNotEmpty;

  /// Load all access record data
  Future<void> loadSubscriptionData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('Loading access record data...');

      // Load both in parallel
      final results = await Future.wait([
        _accessRecordService.getUserRecords(limit: 50),
        _accessRecordService.getAccessLevel(),
      ]);

      _records = results[0] as List<AccessRecordModel>;
      _accessStatus = results[1] as AccessLevel;

      debugPrint('✓ Loaded ${_records.length} records');
      debugPrint('✓ Active: ${activeRecords.length}, Expired: ${expiredRecords.length}');
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      debugPrint('✗ Error loading access records: $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh access record data
  Future<void> refresh() async {
    await loadSubscriptionData();
  }

  /// Clear data (on logout)
  void clear() {
    _records = [];
    _accessStatus = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}

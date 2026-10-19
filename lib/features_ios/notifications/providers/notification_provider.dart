import 'package:flutter/material.dart';
import 'package:pgme/core_ios/models/notification_model.dart';
import 'package:pgme/core_ios/services/notification_service.dart';

class NotificationProvider with ChangeNotifier {
  final NotificationService _notificationService = NotificationService();

  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;
  int _total = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  int _currentOffset = 0;
  static const int _pageSize = 20;

  List<NotificationModel> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  int get total => _total;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _notifications.length < _total;

  /// Load notifications (initial load)
  Future<void> loadNotifications() async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    _currentOffset = 0;
    notifyListeners();

    try {
      final response = await _notificationService.getNotifications(
        limit: _pageSize,
        offset: 0,
      );

      _notifications = response.notifications;
      _unreadCount = response.unreadCount;
      _total = response.total;
      _currentOffset = _notifications.length;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load more notifications (pagination)
  Future<void> loadMore() async {
    if (_isLoadingMore || !hasMore) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final response = await _notificationService.getNotifications(
        limit: _pageSize,
        offset: _currentOffset,
      );

      _notifications.addAll(response.notifications);
      _unreadCount = response.unreadCount;
      _total = response.total;
      _currentOffset = _notifications.length;
    } catch (e) {
      debugPrint('Load more notifications error: $e');
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Refresh notifications
  Future<void> refresh() async {
    _currentOffset = 0;
    _error = null;

    try {
      final response = await _notificationService.getNotifications(
        limit: _pageSize,
        offset: 0,
      );

      _notifications = response.notifications;
      _unreadCount = response.unreadCount;
      _total = response.total;
      _currentOffset = _notifications.length;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }
    notifyListeners();
  }

  /// Mark notification as read
  Future<bool> markAsRead(String notificationId) async {
    try {
      await _notificationService.markAsRead(notificationId);

      // Update local state
      final index = _notifications.indexWhere((n) => n.notificationId == notificationId);
      if (index != -1 && !_notifications[index].isRead) {
        _notifications[index] = _notifications[index].copyWith(readAt: DateTime.now());
        _unreadCount = (_unreadCount - 1).clamp(0, _total);
        notifyListeners();
      }

      return true;
    } catch (e) {
      debugPrint('Mark as read error: $e');
      return false;
    }
  }

  /// Delete notification
  Future<bool> deleteNotification(String notificationId) async {
    try {
      await _notificationService.deleteNotification(notificationId);

      // Update local state
      final index = _notifications.indexWhere((n) => n.notificationId == notificationId);
      if (index != -1) {
        final wasUnread = !_notifications[index].isRead;
        _notifications.removeAt(index);
        _total = (_total - 1).clamp(0, _total);
        if (wasUnread) {
          _unreadCount = (_unreadCount - 1).clamp(0, _total);
        }
        notifyListeners();
      }

      return true;
    } catch (e) {
      debugPrint('Delete notification error: $e');
      return false;
    }
  }

  /// Remove notification from local state only (optimistic delete for undo support)
  void removeNotificationLocally(NotificationModel notification) {
    final index = _notifications.indexWhere((n) => n.notificationId == notification.notificationId);
    if (index != -1) {
      final wasUnread = !_notifications[index].isRead;
      _notifications.removeAt(index);
      _total = (_total - 1).clamp(0, _total);
      if (wasUnread) {
        _unreadCount = (_unreadCount - 1).clamp(0, _total);
      }
      notifyListeners();
    }
  }

  /// Restore a previously removed notification (for undo support)
  void restoreNotification(NotificationModel notification) {
    // Insert back in sorted order by sentAt (most recent first)
    final insertIndex = _notifications.indexWhere(
      (n) => n.sentAt.isBefore(notification.sentAt),
    );
    if (insertIndex == -1) {
      _notifications.add(notification);
    } else {
      _notifications.insert(insertIndex, notification);
    }
    _total = _total + 1;
    if (!notification.isRead) {
      _unreadCount = _unreadCount + 1;
    }
    notifyListeners();
  }

  /// Delete notification from server only (no local state change)
  Future<void> deleteNotificationOnServer(String notificationId) async {
    try {
      await _notificationService.deleteNotification(notificationId);
    } catch (e) {
      debugPrint('Delete notification from server error: $e');
    }
  }

  /// Clear all data (on logout)
  void clear() {
    _notifications = [];
    _unreadCount = 0;
    _total = 0;
    _error = null;
    _currentOffset = 0;
    notifyListeners();
  }
}

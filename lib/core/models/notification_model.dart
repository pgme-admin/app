class NotificationModel {
  final String notificationId;
  final String title;
  final String message;
  final String notificationType;
  final DateTime sentAt;
  final DateTime? readAt;
  final String? clickUrl;

  NotificationModel({
    required this.notificationId,
    required this.title,
    required this.message,
    required this.notificationType,
    required this.sentAt,
    this.readAt,
    this.clickUrl,
  });

  bool get isRead => readAt != null;

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      notificationId: json['notification_id'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      notificationType: json['notification_type'] as String,
      sentAt: DateTime.parse(json['sent_at'] as String),
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at'] as String) : null,
      clickUrl: json['click_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'notification_id': notificationId,
      'title': title,
      'message': message,
      'notification_type': notificationType,
      'sent_at': sentAt.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'click_url': clickUrl,
    };
  }

  NotificationModel copyWith({
    String? notificationId,
    String? title,
    String? message,
    String? notificationType,
    DateTime? sentAt,
    DateTime? readAt,
    String? clickUrl,
  }) {
    return NotificationModel(
      notificationId: notificationId ?? this.notificationId,
      title: title ?? this.title,
      message: message ?? this.message,
      notificationType: notificationType ?? this.notificationType,
      sentAt: sentAt ?? this.sentAt,
      readAt: readAt ?? this.readAt,
      clickUrl: clickUrl ?? this.clickUrl,
    );
  }
}

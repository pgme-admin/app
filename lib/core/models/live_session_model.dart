import 'package:json_annotation/json_annotation.dart';

part 'live_session_model.g.dart';

@JsonSerializable()
class LiveSessionModel {
  @JsonKey(name: 'session_id')
  final String sessionId;

  final String title;

  final String? description;

  @JsonKey(name: 'subject_id')
  final String? subjectId;

  @JsonKey(name: 'subject_name')
  final String? subjectName;

  @JsonKey(name: 'series_id')
  final String? seriesId;

  @JsonKey(name: 'series_name')
  final String? seriesName;

  @JsonKey(name: 'faculty_id')
  final String? facultyId;

  @JsonKey(name: 'faculty_name')
  final String? facultyName;

  @JsonKey(name: 'faculty_photo_url')
  final String? facultyPhotoUrl;

  @JsonKey(name: 'faculty_specialization')
  final String? facultySpecialization;

  @JsonKey(name: 'scheduled_start_time')
  final String scheduledStartTime;

  @JsonKey(name: 'scheduled_end_time')
  final String scheduledEndTime;

  @JsonKey(name: 'duration_minutes')
  final int durationMinutes;

  @JsonKey(name: 'meeting_link')
  final String? meetingLink;

  @JsonKey(name: 'zoom_meeting_id')
  final String? zoomMeetingId;

  final String platform;

  final String status; // "scheduled", "live", "completed", "cancelled"

  @JsonKey(name: 'max_attendees')
  final int? maxAttendees;

  @JsonKey(name: 'thumbnail_url')
  final String? thumbnailUrl;

  final int price;

  @JsonKey(name: 'compare_at_price')
  final int? compareAtPrice;

  @JsonKey(name: 'is_free')
  final bool isFree;

  // Enrollment system fields
  @JsonKey(name: 'enrollment_mode')
  final String? enrollmentMode; // 'open', 'enrollment_required', 'disabled'

  @JsonKey(name: 'capacity_mode')
  final String? capacityMode; // 'limited', 'unlimited'

  @JsonKey(name: 'current_attendees')
  final int? currentAttendees;

  @JsonKey(name: 'guaranteed_seats_for_paid')
  final bool? guaranteedSeatsForPaid;

  @JsonKey(name: 'auto_admit_users')
  final bool? autoAdmitUsers;

  @JsonKey(name: 'allow_join_before_host')
  final bool? allowJoinBeforeHost;

  @JsonKey(name: 'createdAt')
  final String? createdAt;

  @JsonKey(name: 'updatedAt')
  final String? updatedAt;

  LiveSessionModel({
    required this.sessionId,
    required this.title,
    this.description,
    this.subjectId,
    this.subjectName,
    this.seriesId,
    this.seriesName,
    this.facultyId,
    this.facultyName,
    this.facultyPhotoUrl,
    this.facultySpecialization,
    required this.scheduledStartTime,
    required this.scheduledEndTime,
    required this.durationMinutes,
    this.meetingLink,
    this.zoomMeetingId,
    required this.platform,
    required this.status,
    this.maxAttendees,
    this.thumbnailUrl,
    this.price = 0,
    this.compareAtPrice,
    this.isFree = true,
    this.enrollmentMode,
    this.capacityMode,
    this.currentAttendees,
    this.guaranteedSeatsForPaid,
    this.autoAdmitUsers,
    this.allowJoinBeforeHost,
    this.createdAt,
    this.updatedAt,
  });

  factory LiveSessionModel.fromJson(Map<String, dynamic> json) =>
      _$LiveSessionModelFromJson(json);

  Map<String, dynamic> toJson() => _$LiveSessionModelToJson(this);

  LiveSessionModel copyWith({
    String? sessionId,
    String? title,
    String? description,
    String? subjectId,
    String? subjectName,
    String? seriesId,
    String? seriesName,
    String? facultyId,
    String? facultyName,
    String? facultyPhotoUrl,
    String? facultySpecialization,
    String? scheduledStartTime,
    String? scheduledEndTime,
    int? durationMinutes,
    String? meetingLink,
    String? zoomMeetingId,
    String? platform,
    String? status,
    int? maxAttendees,
    String? thumbnailUrl,
    int? price,
    int? compareAtPrice,
    bool? isFree,
    String? enrollmentMode,
    String? capacityMode,
    int? currentAttendees,
    bool? guaranteedSeatsForPaid,
    bool? autoAdmitUsers,
    bool? allowJoinBeforeHost,
    String? createdAt,
    String? updatedAt,
  }) {
    return LiveSessionModel(
      sessionId: sessionId ?? this.sessionId,
      title: title ?? this.title,
      description: description ?? this.description,
      subjectId: subjectId ?? this.subjectId,
      subjectName: subjectName ?? this.subjectName,
      seriesId: seriesId ?? this.seriesId,
      seriesName: seriesName ?? this.seriesName,
      facultyId: facultyId ?? this.facultyId,
      facultyName: facultyName ?? this.facultyName,
      facultyPhotoUrl: facultyPhotoUrl ?? this.facultyPhotoUrl,
      facultySpecialization: facultySpecialization ?? this.facultySpecialization,
      scheduledStartTime: scheduledStartTime ?? this.scheduledStartTime,
      scheduledEndTime: scheduledEndTime ?? this.scheduledEndTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      meetingLink: meetingLink ?? this.meetingLink,
      zoomMeetingId: zoomMeetingId ?? this.zoomMeetingId,
      platform: platform ?? this.platform,
      status: status ?? this.status,
      maxAttendees: maxAttendees ?? this.maxAttendees,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      price: price ?? this.price,
      compareAtPrice: compareAtPrice ?? this.compareAtPrice,
      isFree: isFree ?? this.isFree,
      enrollmentMode: enrollmentMode ?? this.enrollmentMode,
      capacityMode: capacityMode ?? this.capacityMode,
      currentAttendees: currentAttendees ?? this.currentAttendees,
      guaranteedSeatsForPaid: guaranteedSeatsForPaid ?? this.guaranteedSeatsForPaid,
      autoAdmitUsers: autoAdmitUsers ?? this.autoAdmitUsers,
      allowJoinBeforeHost: allowJoinBeforeHost ?? this.allowJoinBeforeHost,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

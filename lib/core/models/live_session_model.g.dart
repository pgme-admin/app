// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_session_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LiveSessionModel _$LiveSessionModelFromJson(Map<String, dynamic> json) =>
    LiveSessionModel(
      sessionId: json['session_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      subjectId: json['subject_id'] as String?,
      subjectName: json['subject_name'] as String?,
      seriesId: json['series_id'] as String?,
      seriesName: json['series_name'] as String?,
      facultyId: json['faculty_id'] as String?,
      facultyName: json['faculty_name'] as String?,
      facultyPhotoUrl: json['faculty_photo_url'] as String?,
      facultySpecialization: json['faculty_specialization'] as String?,
      scheduledStartTime: json['scheduled_start_time'] as String,
      scheduledEndTime: json['scheduled_end_time'] as String,
      durationMinutes: (json['duration_minutes'] as num).toInt(),
      meetingLink: json['meeting_link'] as String?,
      zoomMeetingId: json['zoom_meeting_id'] as String?,
      platform: json['platform'] as String,
      status: json['status'] as String,
      maxAttendees: (json['max_attendees'] as num?)?.toInt(),
      thumbnailUrl: json['thumbnail_url'] as String?,
      price: (json['price'] as num?)?.toInt() ?? 0,
      compareAtPrice: (json['compare_at_price'] as num?)?.toInt(),
      isFree: json['is_free'] as bool? ?? true,
      enrollmentMode: json['enrollment_mode'] as String?,
      capacityMode: json['capacity_mode'] as String?,
      currentAttendees: (json['current_attendees'] as num?)?.toInt(),
      guaranteedSeatsForPaid: json['guaranteed_seats_for_paid'] as bool?,
      autoAdmitUsers: json['auto_admit_users'] as bool?,
      allowJoinBeforeHost: json['allow_join_before_host'] as bool?,
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
    );

Map<String, dynamic> _$LiveSessionModelToJson(LiveSessionModel instance) =>
    <String, dynamic>{
      'session_id': instance.sessionId,
      'title': instance.title,
      'description': instance.description,
      'subject_id': instance.subjectId,
      'subject_name': instance.subjectName,
      'series_id': instance.seriesId,
      'series_name': instance.seriesName,
      'faculty_id': instance.facultyId,
      'faculty_name': instance.facultyName,
      'faculty_photo_url': instance.facultyPhotoUrl,
      'faculty_specialization': instance.facultySpecialization,
      'scheduled_start_time': instance.scheduledStartTime,
      'scheduled_end_time': instance.scheduledEndTime,
      'duration_minutes': instance.durationMinutes,
      'meeting_link': instance.meetingLink,
      'zoom_meeting_id': instance.zoomMeetingId,
      'platform': instance.platform,
      'status': instance.status,
      'max_attendees': instance.maxAttendees,
      'thumbnail_url': instance.thumbnailUrl,
      'price': instance.price,
      'compare_at_price': instance.compareAtPrice,
      'is_free': instance.isFree,
      'enrollment_mode': instance.enrollmentMode,
      'capacity_mode': instance.capacityMode,
      'current_attendees': instance.currentAttendees,
      'guaranteed_seats_for_paid': instance.guaranteedSeatsForPaid,
      'auto_admit_users': instance.autoAdmitUsers,
      'allow_join_before_host': instance.allowJoinBeforeHost,
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
    };

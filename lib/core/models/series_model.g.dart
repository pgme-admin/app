// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'series_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SeriesModel _$SeriesModelFromJson(Map<String, dynamic> json) => SeriesModel(
      seriesId: json['series_id'] as String,
      packageId: json['package_id'] as String?,
      title: json['name'] as String,
      description: json['description'] as String?,
      sequenceNumber: (json['display_order'] as num?)?.toInt() ?? 0,
      moduleCount: (json['module_count'] as num?)?.toInt(),
      totalLectures: (json['total_videos'] as num?)?.toInt(),
      totalDocuments: (json['total_documents'] as num?)?.toInt(),
      totalPages: (json['total_pages'] as num?)?.toInt(),
      createdAt: json['created_at'] as String?,
      type: json['type'] as String?,
      subject: json['subject'] == null
          ? null
          : SubjectModel.fromJson(json['subject'] as Map<String, dynamic>),
      thumbnailUrl: json['thumbnail_url'] as String?,
      totalDurationMinutes: (json['total_duration_minutes'] as num?)?.toInt(),
      isFree: json['is_free'] as bool? ?? false,
      isLocked: json['is_locked'] as bool? ?? false,
    );

Map<String, dynamic> _$SeriesModelToJson(SeriesModel instance) =>
    <String, dynamic>{
      'series_id': instance.seriesId,
      'package_id': instance.packageId,
      'name': instance.title,
      'description': instance.description,
      'display_order': instance.sequenceNumber,
      'module_count': instance.moduleCount,
      'total_videos': instance.totalLectures,
      'total_documents': instance.totalDocuments,
      'total_pages': instance.totalPages,
      'created_at': instance.createdAt,
      'type': instance.type,
      'subject': instance.subject,
      'thumbnail_url': instance.thumbnailUrl,
      'total_duration_minutes': instance.totalDurationMinutes,
      'is_free': instance.isFree,
      'is_locked': instance.isLocked,
    };

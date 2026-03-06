import 'package:json_annotation/json_annotation.dart';
import 'package:pgme/core/models/subject_model.dart';

part 'series_model.g.dart';

@JsonSerializable()
class SeriesModel {
  @JsonKey(name: 'series_id')
  final String seriesId;

  @JsonKey(name: 'package_id')
  final String? packageId;

  @JsonKey(name: 'name')
  final String title;

  final String? description;

  @JsonKey(name: 'display_order', defaultValue: 0)
  final int sequenceNumber;

  @JsonKey(name: 'module_count')
  final int? moduleCount;

  @JsonKey(name: 'total_videos')
  final int? totalLectures;

  @JsonKey(name: 'total_documents')
  final int? totalDocuments;

  @JsonKey(name: 'total_pages')
  final int? totalPages;

  @JsonKey(name: 'created_at')
  final String? createdAt;

  // Optional fields that may not come from all endpoints
  final String? type; // "theory", "practical"
  final SubjectModel? subject;

  @JsonKey(name: 'thumbnail_url')
  final String? thumbnailUrl;

  @JsonKey(name: 'total_duration_minutes')
  final int? totalDurationMinutes;

  @JsonKey(name: 'is_free', defaultValue: false)
  final bool? isFree;

  @JsonKey(name: 'is_locked', defaultValue: false)
  final bool isLocked;

  SeriesModel({
    required this.seriesId,
    this.packageId,
    required this.title,
    this.description,
    this.sequenceNumber = 0,
    this.moduleCount,
    this.totalLectures,
    this.totalDocuments,
    this.totalPages,
    this.createdAt,
    this.type,
    this.subject,
    this.thumbnailUrl,
    this.totalDurationMinutes,
    this.isFree,
    this.isLocked = false,
  });

  factory SeriesModel.fromJson(Map<String, dynamic> json) =>
      _$SeriesModelFromJson(json);

  Map<String, dynamic> toJson() => _$SeriesModelToJson(this);

  SeriesModel copyWith({
    String? seriesId,
    String? packageId,
    String? title,
    String? description,
    String? type,
    SubjectModel? subject,
    String? thumbnailUrl,
    int? totalLectures,
    int? totalDurationMinutes,
    int? sequenceNumber,
    bool? isFree,
    bool? isLocked,
    String? createdAt,
  }) {
    return SeriesModel(
      seriesId: seriesId ?? this.seriesId,
      packageId: packageId ?? this.packageId,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      subject: subject ?? this.subject,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      totalLectures: totalLectures ?? this.totalLectures,
      totalDurationMinutes: totalDurationMinutes ?? this.totalDurationMinutes,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      isFree: isFree ?? this.isFree,
      isLocked: isLocked ?? this.isLocked,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Computed property for formatted duration
  String get formattedDuration {
    if (totalDurationMinutes == null) return 'N/A';
    final hours = totalDurationMinutes! ~/ 60;
    final minutes = totalDurationMinutes! % 60;
    if (hours > 0) {
      return '$hours hrs ${minutes > 0 ? "$minutes mins" : ""}';
    }
    return '$minutes mins';
  }
}

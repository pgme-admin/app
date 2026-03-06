// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'faculty_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FacultyModel _$FacultyModelFromJson(Map<String, dynamic> json) => FacultyModel(
      facultyId: json['faculty_id'] as String,
      name: json['name'] as String,
      photoUrl: json['photo_url'] as String?,
      bio: json['bio'] as String?,
      qualifications: json['qualifications'] as String?,
      experienceYears: (json['experience_years'] as num?)?.toInt(),
      specialization: json['specialization'] as String,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['createdAt'] as String?,
    );

Map<String, dynamic> _$FacultyModelToJson(FacultyModel instance) =>
    <String, dynamic>{
      'faculty_id': instance.facultyId,
      'name': instance.name,
      'photo_url': instance.photoUrl,
      'bio': instance.bio,
      'qualifications': instance.qualifications,
      'experience_years': instance.experienceYears,
      'specialization': instance.specialization,
      'is_active': instance.isActive,
      'createdAt': instance.createdAt,
    };

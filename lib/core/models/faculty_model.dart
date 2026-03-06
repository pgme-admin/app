import 'package:json_annotation/json_annotation.dart';

part 'faculty_model.g.dart';

@JsonSerializable()
class FacultyModel {
  @JsonKey(name: 'faculty_id')
  final String facultyId;

  final String name;

  @JsonKey(name: 'photo_url')
  final String? photoUrl;

  final String? bio;

  final String? qualifications;

  @JsonKey(name: 'experience_years')
  final int? experienceYears;

  final String specialization;

  @JsonKey(name: 'is_active', defaultValue: true)
  final bool isActive;

  @JsonKey(name: 'createdAt')
  final String? createdAt;

  FacultyModel({
    required this.facultyId,
    required this.name,
    this.photoUrl,
    this.bio,
    this.qualifications,
    this.experienceYears,
    required this.specialization,
    required this.isActive,
    this.createdAt,
  });

  factory FacultyModel.fromJson(Map<String, dynamic> json) =>
      _$FacultyModelFromJson(json);

  Map<String, dynamic> toJson() => _$FacultyModelToJson(this);

  FacultyModel copyWith({
    String? facultyId,
    String? name,
    String? photoUrl,
    String? bio,
    String? qualifications,
    int? experienceYears,
    String? specialization,
    bool? isActive,
    String? createdAt,
  }) {
    return FacultyModel(
      facultyId: facultyId ?? this.facultyId,
      name: name ?? this.name,
      photoUrl: photoUrl ?? this.photoUrl,
      bio: bio ?? this.bio,
      qualifications: qualifications ?? this.qualifications,
      experienceYears: experienceYears ?? this.experienceYears,
      specialization: specialization ?? this.specialization,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

import 'package:json_annotation/json_annotation.dart';

part 'banner_model.g.dart';

@JsonSerializable()
class BannerModel {
  @JsonKey(name: '_id')
  final String id;
  final String title;
  final String? description;
  final String imageUrl;
  final String? linkUrl;
  final String? linkType; // 'internal', 'external', 'none'
  final bool isActive;
  final int displayOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  BannerModel({
    required this.id,
    required this.title,
    this.description,
    required this.imageUrl,
    this.linkUrl,
    this.linkType,
    this.isActive = true,
    this.displayOrder = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory BannerModel.fromJson(Map<String, dynamic> json) =>
      _$BannerModelFromJson(json);

  Map<String, dynamic> toJson() => _$BannerModelToJson(this);
}

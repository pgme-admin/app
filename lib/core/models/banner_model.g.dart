// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'banner_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BannerModel _$BannerModelFromJson(Map<String, dynamic> json) => BannerModel(
      id: json['_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String,
      linkUrl: json['linkUrl'] as String?,
      linkType: json['linkType'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$BannerModelToJson(BannerModel instance) =>
    <String, dynamic>{
      '_id': instance.id,
      'title': instance.title,
      'description': instance.description,
      'imageUrl': instance.imageUrl,
      'linkUrl': instance.linkUrl,
      'linkType': instance.linkType,
      'isActive': instance.isActive,
      'displayOrder': instance.displayOrder,
      'createdAt': instance.createdAt?.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
    };

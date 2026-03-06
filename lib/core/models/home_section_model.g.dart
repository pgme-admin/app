// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_section_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HomeSectionModel _$HomeSectionModelFromJson(Map<String, dynamic> json) =>
    HomeSectionModel(
      id: json['_id'] as String,
      title: json['title'] as String?,
      subtitle: json['subtitle'] as String?,
      backgroundColor: json['backgroundColor'] as String?,
      textColor: json['textColor'] as String?,
      displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) =>
                  HomeSectionItemModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$HomeSectionModelToJson(HomeSectionModel instance) =>
    <String, dynamic>{
      '_id': instance.id,
      'title': instance.title,
      'subtitle': instance.subtitle,
      'backgroundColor': instance.backgroundColor,
      'textColor': instance.textColor,
      'displayOrder': instance.displayOrder,
      'items': instance.items,
    };

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_section_item_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HomeSectionItemModel _$HomeSectionItemModelFromJson(
        Map<String, dynamic> json) =>
    HomeSectionItemModel(
      id: json['_id'] as String,
      cardType: json['cardType'] as String,
      title: json['title'] as String?,
      subtitle: json['subtitle'] as String?,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      iconUrl: json['iconUrl'] as String?,
      tagLabel: json['tagLabel'] as String?,
      tagColor: json['tagColor'] as String?,
      backgroundColor: json['backgroundColor'] as String?,
      textColor: json['textColor'] as String?,
      borderColor: json['borderColor'] as String?,
      buttonText: json['buttonText'] as String?,
      buttonColor: json['buttonColor'] as String?,
      buttonTextColor: json['buttonTextColor'] as String?,
      linkType: json['linkType'] as String?,
      externalUrl: json['externalUrl'] as String?,
      internalRoute: json['internalRoute'] as String?,
      internalParams: json['internalParams'] as Map<String, dynamic>?,
      secondaryButtonText: json['secondaryButtonText'] as String?,
      secondaryLinkType: json['secondaryLinkType'] as String?,
      secondaryExternalUrl: json['secondaryExternalUrl'] as String?,
      secondaryInternalRoute: json['secondaryInternalRoute'] as String?,
      secondaryInternalParams:
          json['secondaryInternalParams'] as Map<String, dynamic>?,
      metadata: (json['metadata'] as List<dynamic>?)
              ?.map((e) => MetadataEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$HomeSectionItemModelToJson(
        HomeSectionItemModel instance) =>
    <String, dynamic>{
      '_id': instance.id,
      'cardType': instance.cardType,
      'title': instance.title,
      'subtitle': instance.subtitle,
      'description': instance.description,
      'imageUrl': instance.imageUrl,
      'iconUrl': instance.iconUrl,
      'tagLabel': instance.tagLabel,
      'tagColor': instance.tagColor,
      'backgroundColor': instance.backgroundColor,
      'textColor': instance.textColor,
      'borderColor': instance.borderColor,
      'buttonText': instance.buttonText,
      'buttonColor': instance.buttonColor,
      'buttonTextColor': instance.buttonTextColor,
      'linkType': instance.linkType,
      'externalUrl': instance.externalUrl,
      'internalRoute': instance.internalRoute,
      'internalParams': instance.internalParams,
      'secondaryButtonText': instance.secondaryButtonText,
      'secondaryLinkType': instance.secondaryLinkType,
      'secondaryExternalUrl': instance.secondaryExternalUrl,
      'secondaryInternalRoute': instance.secondaryInternalRoute,
      'secondaryInternalParams': instance.secondaryInternalParams,
      'metadata': instance.metadata,
      'displayOrder': instance.displayOrder,
    };

MetadataEntry _$MetadataEntryFromJson(Map<String, dynamic> json) =>
    MetadataEntry(
      label: json['label'] as String,
      value: json['value'] as String,
      iconUrl: json['icon_url'] as String?,
    );

Map<String, dynamic> _$MetadataEntryToJson(MetadataEntry instance) =>
    <String, dynamic>{
      'label': instance.label,
      'value': instance.value,
      'icon_url': instance.iconUrl,
    };

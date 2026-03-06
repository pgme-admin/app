import 'package:json_annotation/json_annotation.dart';

part 'home_section_item_model.g.dart';

@JsonSerializable()
class HomeSectionItemModel {
  @JsonKey(name: '_id')
  final String id;
  final String cardType;

  // Content
  final String? title;
  final String? subtitle;
  final String? description;
  final String? imageUrl;
  final String? iconUrl;
  final String? tagLabel;
  final String? tagColor;

  // Styling
  final String? backgroundColor;
  final String? textColor;
  final String? borderColor;

  // Primary action
  final String? buttonText;
  final String? buttonColor;
  final String? buttonTextColor;
  final String? linkType; // 'internal', 'external', 'none'
  final String? externalUrl;
  final String? internalRoute;
  final Map<String, dynamic>? internalParams;

  // Secondary action
  final String? secondaryButtonText;
  final String? secondaryLinkType; // 'internal', 'external', 'none'
  final String? secondaryExternalUrl;
  final String? secondaryInternalRoute;
  final Map<String, dynamic>? secondaryInternalParams;

  // Metadata
  @JsonKey(defaultValue: [])
  final List<MetadataEntry> metadata;

  // Ordering
  @JsonKey(defaultValue: 0)
  final int displayOrder;

  HomeSectionItemModel({
    required this.id,
    required this.cardType,
    this.title,
    this.subtitle,
    this.description,
    this.imageUrl,
    this.iconUrl,
    this.tagLabel,
    this.tagColor,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
    this.buttonText,
    this.buttonColor,
    this.buttonTextColor,
    this.linkType,
    this.externalUrl,
    this.internalRoute,
    this.internalParams,
    this.secondaryButtonText,
    this.secondaryLinkType,
    this.secondaryExternalUrl,
    this.secondaryInternalRoute,
    this.secondaryInternalParams,
    this.metadata = const [],
    this.displayOrder = 0,
  });

  factory HomeSectionItemModel.fromJson(Map<String, dynamic> json) =>
      _$HomeSectionItemModelFromJson(json);

  Map<String, dynamic> toJson() => _$HomeSectionItemModelToJson(this);
}

@JsonSerializable()
class MetadataEntry {
  final String label;
  final String value;
  @JsonKey(name: 'icon_url')
  final String? iconUrl;

  MetadataEntry({
    required this.label,
    required this.value,
    this.iconUrl,
  });

  factory MetadataEntry.fromJson(Map<String, dynamic> json) =>
      _$MetadataEntryFromJson(json);

  Map<String, dynamic> toJson() => _$MetadataEntryToJson(this);
}

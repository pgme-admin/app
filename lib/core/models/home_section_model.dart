import 'package:json_annotation/json_annotation.dart';
import 'package:pgme/core/models/home_section_item_model.dart';

part 'home_section_model.g.dart';

@JsonSerializable()
class HomeSectionModel {
  @JsonKey(name: '_id')
  final String id;
  final String? title;
  final String? subtitle;
  final String? backgroundColor;
  final String? textColor;
  @JsonKey(defaultValue: 0)
  final int displayOrder;
  @JsonKey(defaultValue: [])
  final List<HomeSectionItemModel> items;

  HomeSectionModel({
    required this.id,
    this.title,
    this.subtitle,
    this.backgroundColor,
    this.textColor,
    this.displayOrder = 0,
    this.items = const [],
  });

  factory HomeSectionModel.fromJson(Map<String, dynamic> json) =>
      _$HomeSectionModelFromJson(json);

  Map<String, dynamic> toJson() => _$HomeSectionModelToJson(this);
}

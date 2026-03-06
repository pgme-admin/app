import 'package:json_annotation/json_annotation.dart';

part 'series_document_model.g.dart';

@JsonSerializable()
class SeriesDocumentModel {
  @JsonKey(name: 'document_id')
  final String documentId;

  final String title;

  final String? description;

  @JsonKey(name: 'file_url')
  final String? fileUrl;

  @JsonKey(name: 'preview_url')
  final String? previewUrl;

  @JsonKey(name: 'file_format', defaultValue: 'pdf')
  final String fileFormat;

  @JsonKey(name: 'file_size_mb')
  final double? fileSizeMb;

  @JsonKey(name: 'page_count')
  final int? pageCount;

  @JsonKey(name: 'is_free', defaultValue: false)
  final bool isFree;

  @JsonKey(name: 'is_in_library', defaultValue: false)
  final bool isInLibrary;

  @JsonKey(name: 'display_order', defaultValue: 0)
  final int displayOrder;

  @JsonKey(name: 'created_at')
  final String? createdAt;

  SeriesDocumentModel({
    required this.documentId,
    required this.title,
    this.description,
    this.fileUrl,
    this.previewUrl,
    this.fileFormat = 'pdf',
    this.fileSizeMb,
    this.pageCount,
    this.isFree = false,
    this.isInLibrary = false,
    this.displayOrder = 0,
    this.createdAt,
  });

  factory SeriesDocumentModel.fromJson(Map<String, dynamic> json) =>
      _$SeriesDocumentModelFromJson(json);

  Map<String, dynamic> toJson() => _$SeriesDocumentModelToJson(this);

  // Computed property for formatted file size
  String get formattedFileSize {
    if (fileSizeMb == null) return 'N/A';
    if (fileSizeMb! < 1) {
      return '${(fileSizeMb! * 1024).toStringAsFixed(0)} KB';
    }
    return '${fileSizeMb!.toStringAsFixed(1)} MB';
  }

  // Computed property for file extension
  String get fileExtension {
    return fileFormat.toUpperCase();
  }
}

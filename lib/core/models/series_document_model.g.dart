// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'series_document_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SeriesDocumentModel _$SeriesDocumentModelFromJson(Map<String, dynamic> json) =>
    SeriesDocumentModel(
      documentId: json['document_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      fileUrl: json['file_url'] as String?,
      previewUrl: json['preview_url'] as String?,
      fileFormat: json['file_format'] as String? ?? 'pdf',
      fileSizeMb: (json['file_size_mb'] as num?)?.toDouble(),
      pageCount: (json['page_count'] as num?)?.toInt(),
      isFree: json['is_free'] as bool? ?? false,
      isInLibrary: json['is_in_library'] as bool? ?? false,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] as String?,
    );

Map<String, dynamic> _$SeriesDocumentModelToJson(
        SeriesDocumentModel instance) =>
    <String, dynamic>{
      'document_id': instance.documentId,
      'title': instance.title,
      'description': instance.description,
      'file_url': instance.fileUrl,
      'preview_url': instance.previewUrl,
      'file_format': instance.fileFormat,
      'file_size_mb': instance.fileSizeMb,
      'page_count': instance.pageCount,
      'is_free': instance.isFree,
      'is_in_library': instance.isInLibrary,
      'display_order': instance.displayOrder,
      'created_at': instance.createdAt,
    };

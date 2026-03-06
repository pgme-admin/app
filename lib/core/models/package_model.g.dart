// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'package_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PackageTier _$PackageTierFromJson(Map<String, dynamic> json) => PackageTier(
      index: (json['index'] as num).toInt(),
      name: json['name'] as String,
      durationDays: (json['duration_days'] as num).toInt(),
      price: (json['price'] as num).toInt(),
      originalPrice: (json['original_price'] as num?)?.toInt(),
      effectivePrice: (json['effective_price'] as num).toInt(),
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$PackageTierToJson(PackageTier instance) =>
    <String, dynamic>{
      'index': instance.index,
      'name': instance.name,
      'duration_days': instance.durationDays,
      'price': instance.price,
      'original_price': instance.originalPrice,
      'effective_price': instance.effectivePrice,
      'display_order': instance.displayOrder,
    };

CurrentTierInfo _$CurrentTierInfoFromJson(Map<String, dynamic> json) =>
    CurrentTierInfo(
      tierIndex: (json['tier_index'] as num?)?.toInt(),
      tierName: json['tier_name'] as String?,
      expiresAt: json['expires_at'] as String?,
      daysRemaining: (json['days_remaining'] as num?)?.toInt(),
      purchaseId: json['purchase_id'] as String?,
    );

Map<String, dynamic> _$CurrentTierInfoToJson(CurrentTierInfo instance) =>
    <String, dynamic>{
      'tier_index': instance.tierIndex,
      'tier_name': instance.tierName,
      'expires_at': instance.expiresAt,
      'days_remaining': instance.daysRemaining,
      'purchase_id': instance.purchaseId,
    };

PackageModel _$PackageModelFromJson(Map<String, dynamic> json) => PackageModel(
      packageId: json['package_id'] as String,
      name: json['name'] as String,
      type: json['package_type'] as String?,
      description: json['description'] as String?,
      price: (json['price'] as num).toInt(),
      originalPrice: (json['original_price'] as num?)?.toInt(),
      isOnSale: json['is_on_sale'] as bool? ?? false,
      salePrice: (json['sale_price'] as num?)?.toInt(),
      saleEndDate: json['sale_end_date'] as String?,
      saleDiscountPercent: (json['sale_discount_percent'] as num?)?.toInt(),
      durationDays: (json['duration_days'] as num?)?.toInt(),
      thumbnailUrl: json['thumbnail_url'] as String?,
      trailerVideoUrl: json['trailer_video_url'] as String?,
      features: _featuresFromJson(json['features']),
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      isPurchased: json['is_purchased'] as bool? ?? false,
      expiresAt: json['expires_at'] as String?,
      hasTiers: json['has_tiers'] as bool? ?? false,
      tiers: (json['tiers'] as List<dynamic>?)
          ?.map((e) => PackageTier.fromJson(e as Map<String, dynamic>))
          .toList(),
      startingPrice: (json['starting_price'] as num?)?.toInt(),
      currentTierIndex: (json['current_tier_index'] as num?)?.toInt(),
      currentTierName: json['current_tier_name'] as String?,
      currentTier: json['current_tier'] == null
          ? null
          : CurrentTierInfo.fromJson(
              json['current_tier'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PackageModelToJson(PackageModel instance) =>
    <String, dynamic>{
      'package_id': instance.packageId,
      'name': instance.name,
      'package_type': instance.type,
      'description': instance.description,
      'price': instance.price,
      'original_price': instance.originalPrice,
      'is_on_sale': instance.isOnSale,
      'sale_price': instance.salePrice,
      'sale_end_date': instance.saleEndDate,
      'sale_discount_percent': instance.saleDiscountPercent,
      'duration_days': instance.durationDays,
      'thumbnail_url': instance.thumbnailUrl,
      'trailer_video_url': instance.trailerVideoUrl,
      'features': instance.features,
      'display_order': instance.displayOrder,
      'is_purchased': instance.isPurchased,
      'expires_at': instance.expiresAt,
      'has_tiers': instance.hasTiers,
      'tiers': instance.tiers,
      'starting_price': instance.startingPrice,
      'current_tier_index': instance.currentTierIndex,
      'current_tier_name': instance.currentTierName,
      'current_tier': instance.currentTier,
    };

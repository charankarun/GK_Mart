import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class AppCachedNetworkImage extends StatelessWidget {
  const AppCachedNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.borderRadius,
    this.placeholder,
    this.errorPlaceholder,
    this.memCacheWidth,
    this.memCacheHeight,
    this.maxWidthDiskCache,
    this.maxHeightDiskCache,
    this.filterQuality = FilterQuality.medium,
    this.cacheKey,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorPlaceholder;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final int? maxWidthDiskCache;
  final int? maxHeightDiskCache;
  final FilterQuality filterQuality;
  final String? cacheKey;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = imageUrl.trim();
    final loading = placeholder ?? const AppImagePlaceholder();
    final error = errorPlaceholder ??
        const AppImagePlaceholder(icon: Icons.image_not_supported_outlined);

    Widget child;
    if (trimmedUrl.isEmpty) {
      child = error;
    } else {
      child = CachedNetworkImage(
        imageUrl: trimmedUrl,
        cacheKey: cacheKey,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        maxWidthDiskCache: maxWidthDiskCache,
        maxHeightDiskCache: maxHeightDiskCache,
        useOldImageOnUrlChange: true,
        fadeInDuration: const Duration(milliseconds: 140),
        fadeOutDuration: const Duration(milliseconds: 90),
        placeholder: (_, __) => loading,
        errorWidget: (_, __, ___) => error,
      );
    }

    child = SizedBox(width: width, height: height, child: child);

    final radius = borderRadius;
    if (radius == null) return child;

    return ClipRRect(
      borderRadius: radius,
      child: child,
    );
  }
}

class AppImagePlaceholder extends StatelessWidget {
  const AppImagePlaceholder({
    super.key,
    this.icon = Icons.local_grocery_store_rounded,
    this.iconSize = 32,
    this.backgroundColor = AppColors.softGreen,
    this.iconColor = AppColors.primary,
  });

  final IconData icon;
  final double iconSize;
  final Color backgroundColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: backgroundColor),
      child: Center(
        child: Icon(icon, color: iconColor, size: iconSize),
      ),
    );
  }
}

// ==============================================================================
// FILE: lib/core/images/image_upload_processor.dart
// PURPOSE: Client-side compression, resizing, and validation processor for image uploads.
// LAYER: Core / Media Services
// DEPENDENCIES: image package
//
// ARCHITECTURAL ROLE:
// Ensures uploaded files conform to maximum boundary dimensions and memory sizes
// before storage transmission. Normalizes PNG/WEBP files into standard JPEGs,
// scales down overflow sizes, and reduces compression quality progressively to fit bounds.
// ==============================================================================

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Holds the output bytes and dimensions of a validated, compressed image upload.
class ProcessedImageUpload {
  const ProcessedImageUpload({
    required this.bytes,
    required this.fileName,
    required this.contentType,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
  final int width;
  final int height;
}

/// Thrown when selected images fail content type, dimension, or size rules.
class ImageValidationException implements Exception {
  const ImageValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Dynamic compressor and validator enforcing standard constraints.
class ImageUploadProcessor {
  const ImageUploadProcessor._();

  static const jpegContentType = 'image/jpeg';
  static const _allowedContentTypes = {
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
  };

  static Future<ProcessedImageUpload> process({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required double maxDimension,
    required int maxSourceBytes,
    required int maxUploadBytes,
    required int quality,
    int minQuality = 62,
  }) async {
    if (bytes.isEmpty) {
      throw const ImageValidationException('Selected image is empty');
    }

    if (bytes.lengthInBytes > maxSourceBytes) {
      throw ImageValidationException(
        'Choose an image under ${_formatSize(maxSourceBytes)}.',
      );
    }

    final normalizedContentType = _normalizeContentType(
      contentType: contentType,
      fileName: fileName,
    );
    if (!_allowedContentTypes.contains(normalizedContentType)) {
      throw const ImageValidationException(
        'Choose a JPG, PNG, or WEBP image.',
      );
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw const ImageValidationException('Selected image is not valid.');
    }

    final resized = _resizeIfNeeded(decoded, maxDimension);
    final outputBytes = _encodeWithinLimit(
      resized,
      maxBytes: maxUploadBytes,
      quality: quality,
      minQuality: minQuality,
    );

    return ProcessedImageUpload(
      bytes: outputBytes,
      fileName: _jpegFileName(fileName),
      contentType: jpegContentType,
      width: resized.width,
      height: resized.height,
    );
  }

  static img.Image _resizeIfNeeded(img.Image image, double maxDimension) {
    final largestSide = math.max(image.width, image.height);
    if (largestSide <= maxDimension) return image;

    final scale = maxDimension / largestSide;
    final targetWidth = math.max(1, (image.width * scale).round());
    final targetHeight = math.max(1, (image.height * scale).round());

    return img.copyResize(
      image,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.average,
    );
  }

  static Uint8List _encodeWithinLimit(
    img.Image image, {
    required int maxBytes,
    required int quality,
    required int minQuality,
  }) {
    var currentQuality = quality.clamp(minQuality, 100).toInt();
    Uint8List output = Uint8List.fromList(
      img.encodeJpg(image, quality: currentQuality),
    );

    while (output.lengthInBytes > maxBytes && currentQuality > minQuality) {
      currentQuality = math.max(minQuality, currentQuality - 6);
      output = Uint8List.fromList(
        img.encodeJpg(image, quality: currentQuality),
      );
    }

    if (output.lengthInBytes > maxBytes) {
      throw ImageValidationException(
        'Compressed image is still over ${_formatSize(maxBytes)}.',
      );
    }

    return output;
  }

  static String _normalizeContentType({
    required String contentType,
    required String fileName,
  }) {
    final normalized = contentType.trim().toLowerCase();
    if (_allowedContentTypes.contains(normalized)) return normalized;

    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png')) return 'image/png';
    if (lowerName.endsWith('.webp')) return 'image/webp';
    if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
      return jpegContentType;
    }

    return '';
  }

  static String _jpegFileName(String fileName) {
    final sanitized = fileName.trim().replaceAll(
          RegExp(r'[^A-Za-z0-9._-]+'),
          '_',
        );
    final baseName = sanitized.replaceFirst(
      RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false),
      '',
    );
    final visibleBaseName = baseName.isEmpty ? 'image' : baseName;
    return '$visibleBaseName.jpg';
  }

  static String _formatSize(int bytes) {
    final megabytes = bytes / (1024 * 1024);
    if (megabytes >= 1) return '${megabytes.toStringAsFixed(1)} MB';

    final kilobytes = bytes / 1024;
    return '${kilobytes.toStringAsFixed(0)} KB';
  }
}

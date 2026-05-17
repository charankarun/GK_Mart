import 'dart:typed_data';

class CategoryImageUpload {
  const CategoryImageUpload({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
}

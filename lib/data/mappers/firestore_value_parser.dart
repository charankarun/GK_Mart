import 'package:cloud_firestore/cloud_firestore.dart';

String readString(
  Map<String, dynamic> data,
  String key, {
  String fallback = '',
}) {
  final value = data[key]?.toString().trim();
  return value == null || value.isEmpty ? fallback : value;
}

double readDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int readInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? readDateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

List<String> readStringList(dynamic value) {
  if (value is String) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  if (value is! Iterable) return const [];
  return value.map((item) => item.toString().trim()).where((item) {
    return item.isNotEmpty;
  }).toList();
}

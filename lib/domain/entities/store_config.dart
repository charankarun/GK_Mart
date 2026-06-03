class StoreConfig {
  final bool storeEnabled;
  final int openHour;
  final int openMinute;
  final int closeHour;
  final int closeMinute;
  final DateTime? updatedAt;

  const StoreConfig({
    required this.storeEnabled,
    required this.openHour,
    required this.openMinute,
    required this.closeHour,
    required this.closeMinute,
    this.updatedAt,
  });

  factory StoreConfig.fromMap(Map<String, dynamic> map) {
    return StoreConfig(
      storeEnabled: map['storeEnabled'] as bool? ?? false,
      openHour: map['openHour'] as int? ?? 0,
      openMinute: map['openMinute'] as int? ?? 0,
      closeHour: map['closeHour'] as int? ?? 23,
      closeMinute: map['closeMinute'] as int? ?? 59,
      updatedAt: map['updatedAt'] is DateTime
          ? map['updatedAt'] as DateTime
          : null, // Conversion from timestamp is done in the data layer
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'storeEnabled': storeEnabled,
      'openHour': openHour,
      'openMinute': openMinute,
      'closeHour': closeHour,
      'closeMinute': closeMinute,
      'updatedAt': updatedAt,
    };
  }

  bool isOpenAt(DateTime time) {
    if (!storeEnabled) return false;
    final currentMinutes = time.hour * 60 + time.minute;
    final openMinutes = openHour * 60 + openMinute;
    final closeMinutes = closeHour * 60 + closeMinute;

    if (openMinutes < closeMinutes) {
      return currentMinutes >= openMinutes && currentMinutes < closeMinutes;
    } else {
      return currentMinutes >= openMinutes || currentMinutes < closeMinutes;
    }
  }

  bool get isOpen => isOpenAt(DateTime.now());

  String get formattedOpenTime => _formatTime(openHour, openMinute);
  String get formattedCloseTime => _formatTime(closeHour, closeMinute);

  static String _formatTime(int hour, int minute) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final formattedHour = hour % 12 == 0 ? 12 : hour % 12;
    final formattedMinute = minute.toString().padLeft(2, '0');
    return '$formattedHour:$formattedMinute $period';
  }
}

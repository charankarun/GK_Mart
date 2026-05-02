class OrderItem {
  const OrderItem({
    this.productId = '',
    required this.name,
    required this.price,
    this.discountPrice = 0,
    required this.quantity,
    this.imageUrl = '',
    this.unit = '',
  });

  final String productId;
  final String name;
  final double price;
  final double discountPrice;
  final int quantity;
  final String imageUrl;
  final String unit;

  double get effectivePrice {
    if (discountPrice > 0 && discountPrice < price) return discountPrice;
    return price;
  }

  double get lineTotal => effectivePrice * quantity;

  double get lineSavings => (price - effectivePrice) * quantity;
}

class Order {
  const Order({
    required this.id,
    required this.userId,
    required this.userName,
    required this.phone,
    required this.items,
    required this.totalAmount,
    required this.totalSavings,
    required this.address,
    this.pincode = '',
    required this.status,
    this.paymentMethod = 'COD',
    this.createdAt,
  });

  final String id;
  final String userId;
  final String userName;
  final String phone;
  final List<OrderItem> items;
  final double totalAmount;
  final double totalSavings;
  final String address;
  final String pincode;
  final String status;
  final String paymentMethod;
  final DateTime? createdAt;

  String get customerName => userName;

  double get total => totalAmount;

  String get customerDisplayName {
    if (userName.trim().isNotEmpty) return userName.trim();
    return 'Customer';
  }
}

typedef CustomerOrder = Order;

class CreateOrderRequest {
  const CreateOrderRequest({
    required this.userId,
    required this.userName,
    required this.phone,
    required this.address,
    required this.pincode,
    required this.items,
    required this.totalAmount,
    required this.totalSavings,
    this.paymentMethod = 'COD',
  });

  final String userId;
  final String userName;
  final String phone;
  final String address;
  final String pincode;
  final List<OrderItem> items;
  final double totalAmount;
  final double totalSavings;
  final String paymentMethod;
}

class OrderStatus {
  static const placed = 'Placed';
  static const packed = 'Packed';
  static const outForDelivery = 'Out for Delivery';
  static const delivered = 'Delivered';

  static const values = [
    placed,
    packed,
    outForDelivery,
    delivered,
  ];

  static String normalize(String? status) {
    final trimmed = status?.trim();
    if (trimmed == null || trimmed.isEmpty) return placed;
    final lowerStatus = trimmed.toLowerCase();

    if (lowerStatus == 'pending') return placed;
    if (lowerStatus == 'processing') return packed;

    for (final value in values) {
      if (value.toLowerCase() == lowerStatus) return value;
    }

    return placed;
  }
}

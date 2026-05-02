import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../../domain/entities/cart_item.dart';
import '../../domain/entities/customer_order.dart';
import '../../domain/repositories/order_repository.dart';
import '../mappers/firestore_value_parser.dart';

class FirestoreOrderRepository implements OrderRepository {
  FirestoreOrderRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _orders {
    return _firestore.collection('orders');
  }

  @override
  Stream<List<Order>> watchUserOrders(String userId) {
    return _orders
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map(_fromDocument).toList();
    });
  }

  @override
  Stream<List<Order>> watchAllOrders({int limit = 100}) {
    return _orders
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map(_fromDocument).toList();
    });
  }

  @override
  Stream<Order?> watchOrder(String orderId) {
    return _orders.doc(orderId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return _fromDocument(doc);
    });
  }

  @override
  Future<String> createOrder(CreateOrderRequest request) async {
    final doc = _orders.doc();
    final orderId = doc.id;

    await doc.set({
      'orderId': orderId,
      'userId': request.userId,
      'userName': request.userName.trim(),
      'customerName': request.userName.trim(),
      'phone': request.phone.trim(),
      'address': request.address.trim(),
      'pincode': request.pincode.trim(),
      'items': request.items.map(_orderItemToMap).toList(),
      'totalAmount': request.totalAmount,
      'total': request.totalAmount,
      'totalSavings': request.totalSavings,
      'status': OrderStatus.placed,
      'paymentMethod': request.paymentMethod,
      'createdAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
    });

    return orderId;
  }

  @override
  Future<String> placeOrder({
    required String userId,
    required String customerName,
    required List<CartItem> cartItems,
    required double total,
    required String address,
    required String paymentMethod,
  }) async {
    return createOrder(
      CreateOrderRequest(
        userId: userId,
        userName: customerName,
        phone: '',
        address: address,
        pincode: '',
        items: cartItems.map(_cartItemToOrderItem).toList(),
        totalAmount: total,
        totalSavings: cartItems.fold<double>(
          0,
          (runningTotal, item) => runningTotal + item.lineSavings,
        ),
        paymentMethod: paymentMethod,
      ),
    );
  }

  @override
  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
  }) {
    return _orders.doc(orderId).set({
      'status': OrderStatus.normalize(status),
    }, SetOptions(merge: true));
  }

  Order _fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};

    return Order(
      id: doc.id,
      userId: readString(data, 'userId'),
      userName: readString(
        data,
        'userName',
        fallback: readString(data, 'customerName'),
      ),
      phone: readString(data, 'phone'),
      items: _readItems(data['items']),
      totalAmount: readDouble(
        data['totalAmount'] ?? data['total'],
      ),
      totalSavings: readDouble(data['totalSavings']),
      address: readString(data, 'address', fallback: 'No address added'),
      pincode: readString(data, 'pincode'),
      status: OrderStatus.normalize(data['status']?.toString()),
      paymentMethod: readString(data, 'paymentMethod', fallback: 'COD'),
      createdAt: readDateTime(data['createdAt'] ?? data['timestamp']),
    );
  }

  List<OrderItem> _readItems(dynamic value) {
    if (value is! List) return const [];

    return value.whereType<Map>().map((item) {
      final data = Map<String, dynamic>.from(item);
      return OrderItem(
        productId: readString(data, 'productId'),
        name: readString(data, 'name', fallback: 'Product'),
        price: readDouble(data['price']),
        discountPrice: readDouble(data['discountPrice']),
        quantity: readInt(data['quantity']),
        imageUrl:
            readString(data, 'imageUrl', fallback: readString(data, 'image')),
        unit: readString(data, 'unit'),
      );
    }).toList();
  }

  OrderItem _cartItemToOrderItem(CartItem item) {
    return OrderItem(
      productId: item.productId,
      name: item.name,
      price: item.price,
      discountPrice: item.discountPrice,
      quantity: item.quantity,
      imageUrl: item.imageUrl,
      unit: item.unit,
    );
  }

  Map<String, dynamic> _orderItemToMap(OrderItem item) {
    return {
      'productId': item.productId,
      'name': item.name,
      'price': item.price,
      'discountPrice': item.discountPrice,
      'unit': item.unit,
      'quantity': item.quantity,
      'imageUrl': item.imageUrl,
      'lineTotal': item.lineTotal,
      'lineSavings': item.lineSavings,
    };
  }
}

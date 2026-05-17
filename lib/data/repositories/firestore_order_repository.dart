import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../../core/constants/app_constants.dart';
import '../../core/errors/repository_exception.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/customer_order.dart';
import '../../domain/entities/order_analytics.dart';
import '../../domain/entities/order_page.dart';
import '../../domain/repositories/order_repository.dart';
import '../mappers/firestore_value_parser.dart';

class FirestoreOrderRepository implements OrderRepository {
  FirestoreOrderRepository(this._firestore);

  final FirebaseFirestore _firestore;
  static final Random _random = Random.secure();
  static const _defaultUserOrderLimit = 20;
  static const _defaultAdminOrderLimit = 50;
  static const _maxPageLimit = 60;
  static const _orderIdAttempts = 12;
  static const _orderIdAlphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  CollectionReference<Map<String, dynamic>> get _orders {
    return _firestore.collection(FirestoreCollections.orders);
  }

  @override
  Stream<List<Order>> watchUserOrders(
    String userId, {
    int limit = _defaultUserOrderLimit,
  }) {
    final safeLimit = _safeLimit(limit);
    if (safeLimit <= 0 || userId.trim().isEmpty) {
      return Stream.value(const <Order>[]);
    }

    return RepositoryGuard.watch(
      message: 'Unable to load orders.',
      create: () {
        return _orders
            .where('userId', isEqualTo: userId.trim())
            .orderBy('timestamp', descending: true)
            .limit(safeLimit)
            .snapshots()
            .map((snapshot) => snapshot.docs.map(_fromDocument).toList());
      },
    );
  }

  @override
  Stream<List<Order>> watchAllOrders({int limit = _defaultAdminOrderLimit}) {
    final safeLimit = _safeLimit(limit);
    if (safeLimit <= 0) return Stream.value(const <Order>[]);

    return RepositoryGuard.watch(
      message: 'Unable to load orders.',
      create: () {
        return _orders
            .orderBy('timestamp', descending: true)
            .limit(safeLimit)
            .snapshots()
            .map((snapshot) => snapshot.docs.map(_fromDocument).toList());
      },
    );
  }

  @override
  Stream<Order?> watchOrder(String orderId) {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return Stream.value(null);

    return RepositoryGuard.watch(
      message: 'Unable to load order.',
      create: () {
        return _orders.doc(normalizedOrderId).snapshots().map((doc) {
          if (!doc.exists) return null;
          return _fromDocument(doc);
        });
      },
    );
  }

  @override
  Future<OrderPage> fetchUserOrdersPage({
    required String userId,
    required int limit,
    OrderPageCursor? cursor,
  }) {
    return RepositoryGuard.run(
      message: 'Unable to load orders.',
      action: () async {
        final safeLimit = _safeLimit(limit);
        final normalizedUserId = userId.trim();
        if (safeLimit <= 0 || normalizedUserId.isEmpty) {
          return const OrderPage(orders: <Order>[], hasMore: false);
        }

        Query<Map<String, dynamic>> query = _orders
            .where('userId', isEqualTo: normalizedUserId)
            .orderBy('timestamp', descending: true)
            .limit(safeLimit);
        query = await _startAfterOrderCursor(query: query, cursor: cursor);

        final snapshot = await query.get().timeout(AppDurations.networkTimeout);
        return _pageFromSnapshot(snapshot, safeLimit);
      },
    );
  }

  @override
  Future<OrderPage> fetchAllOrdersPage({
    required int limit,
    OrderPageCursor? cursor,
  }) {
    return RepositoryGuard.run(
      message: 'Unable to load orders.',
      action: () async {
        final safeLimit = _safeLimit(limit);
        if (safeLimit <= 0) {
          return const OrderPage(orders: <Order>[], hasMore: false);
        }

        Query<Map<String, dynamic>> query =
            _orders.orderBy('timestamp', descending: true).limit(safeLimit);
        query = await _startAfterOrderCursor(query: query, cursor: cursor);

        final snapshot = await query.get().timeout(AppDurations.networkTimeout);
        return _pageFromSnapshot(snapshot, safeLimit);
      },
    );
  }

  @override
  Future<OrderAnalytics> fetchOrderAnalytics() {
    return RepositoryGuard.run(
      message: 'Unable to load order analytics.',
      action: () async {
        final allOrders = _orders;
        final pendingOrders = _orders.where(
          'status',
          whereIn: [
            OrderStatus.placed,
            OrderStatus.packed,
            OrderStatus.outForDelivery,
          ],
        );
        final deliveredOrders = _orders.where(
          'status',
          isEqualTo: OrderStatus.delivered,
        );

        final allSnapshot = await allOrders
            .aggregate(count(), sum('total'))
            .get()
            .timeout(AppDurations.networkTimeout);
        final pendingSnapshot = await pendingOrders
            .count()
            .get()
            .timeout(AppDurations.networkTimeout);
        final deliveredSnapshot = await deliveredOrders
            .count()
            .get()
            .timeout(AppDurations.networkTimeout);

        return OrderAnalytics(
          totalOrders: allSnapshot.count ?? 0,
          revenue: allSnapshot.getSum('total') ?? 0,
          pendingOrders: pendingSnapshot.count ?? 0,
          deliveredOrders: deliveredSnapshot.count ?? 0,
        );
      },
    );
  }

  @override
  Future<String> createOrder(CreateOrderRequest request) async {
    return RepositoryGuard.run(
      message: 'Unable to create order.',
      action: () async {
        final normalizedUserId = request.userId.trim();
        if (normalizedUserId.isEmpty) {
          throw ArgumentError.value(request.userId, 'userId', 'Required');
        }
        if (request.items.isEmpty) {
          throw ArgumentError.value(request.items, 'items', 'Required');
        }

        FirebaseException? lastPermissionDenied;
        for (var attempt = 0; attempt < _orderIdAttempts; attempt += 1) {
          final orderId = _generateOrderId(DateTime.now());
          final orderRef = _orders.doc(orderId);

          try {
            await orderRef
                .set(_orderData(
                  orderId: orderId,
                  request: request,
                  userId: normalizedUserId,
                ))
                .timeout(AppDurations.networkTimeout);
            return orderId;
          } on FirebaseException catch (error) {
            if (error.code != 'permission-denied') rethrow;
            lastPermissionDenied = error;
          }
        }

        throw RepositoryException(
          'Unable to reserve a unique order ID. Please try again.',
          code: 'order-id-collision',
          cause: lastPermissionDenied,
        );
      },
    );
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
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) {
      throw ArgumentError.value(orderId, 'orderId', 'Required');
    }

    return RepositoryGuard.run(
      message: 'Unable to update order status.',
      action: () {
        return _orders.doc(normalizedOrderId).set({
          'status': OrderStatus.normalize(status),
        }, SetOptions(merge: true)).timeout(AppDurations.networkTimeout);
      },
    );
  }

  Future<Query<Map<String, dynamic>>> _startAfterOrderCursor({
    required Query<Map<String, dynamic>> query,
    required OrderPageCursor? cursor,
  }) async {
    if (cursor == null) return query;

    final cursorDoc = await _orders.doc(cursor.id).get().timeout(
          AppDurations.networkTimeout,
        );
    if (cursorDoc.exists) return query.startAfterDocument(cursorDoc);

    final createdAt = cursor.createdAt;
    if (createdAt == null) return query;
    return query.startAfter([Timestamp.fromDate(createdAt)]);
  }

  OrderPage _pageFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    int limit,
  ) {
    final orders = snapshot.docs.map(_fromDocument).toList();

    OrderPageCursor? nextCursor;
    if (orders.isNotEmpty) {
      final lastOrder = orders.last;
      nextCursor = OrderPageCursor(
        id: lastOrder.id,
        createdAt: lastOrder.createdAt,
      );
    }

    return OrderPage(
      orders: orders,
      nextCursor: nextCursor,
      hasMore: snapshot.docs.length == limit,
    );
  }

  Map<String, dynamic> _orderData({
    required String orderId,
    required CreateOrderRequest request,
    required String userId,
  }) {
    return {
      'orderId': orderId,
      'userId': userId,
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
    };
  }

  static String _generateOrderId(DateTime date) {
    return 'SLV-${_dateStamp(date)}-${_randomSuffix()}';
  }

  static String _dateStamp(DateTime date) {
    final localDate = date.toLocal();
    final year = localDate.year.toString().padLeft(4, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    final day = localDate.day.toString().padLeft(2, '0');
    return '$year$month$day';
  }

  static String _randomSuffix() {
    return String.fromCharCodes(
      List.generate(4, (_) {
        return _orderIdAlphabet.codeUnitAt(
          _random.nextInt(_orderIdAlphabet.length),
        );
      }),
    );
  }

  static int _safeLimit(int limit) {
    if (limit <= 0) return 0;
    return limit > _maxPageLimit ? _maxPageLimit : limit;
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

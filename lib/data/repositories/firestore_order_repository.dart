import 'dart:developer' as developer;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../../core/constants/app_constants.dart';
import '../../core/errors/repository_exception.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/cart_pricing.dart';
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
  static const _prefixSearchTerminator = '\uf8ff';
  static const _maxOrderSearchTokens = 120;
  static const _revenueFields = ['totalAmount', 'total', 'paymentAmount'];
  static const _dateFields = ['timestamp', 'createdAt', 'orderDate'];
  static const _dashboardLogName = 'AdminDashboard';
  static const _debugLoggingEnabled = !bool.fromEnvironment('dart.vm.product');

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
  Future<OrderPage> searchAdminOrders({
    required String query,
    required int limit,
  }) {
    return RepositoryGuard.run(
      message: 'Unable to search orders.',
      action: () async {
        final safeLimit = _safeLimit(limit);
        final searchText = query.trim();
        final searchToken = _searchTokenFor(searchText);
        if (safeLimit <= 0 || searchText.isEmpty) {
          return const OrderPage(orders: <Order>[], hasMore: false);
        }

        final ordersById = <String, Order>{};

        for (final candidateId in _candidateOrderIds(searchText)) {
          final doc = await _orders.doc(candidateId).get().timeout(
                AppDurations.networkTimeout,
              );
          if (doc.exists) {
            final order = _fromDocument(doc);
            ordersById[order.id] = order;
          }
        }

        if (searchToken.length >= 3) {
          final tokenSnapshot = await _orders
              .where('searchTokens', arrayContains: searchToken)
              .orderBy('timestamp', descending: true)
              .limit(safeLimit)
              .get()
              .timeout(AppDurations.networkTimeout);
          for (final doc in tokenSnapshot.docs) {
            final order = _fromDocument(doc);
            ordersById[order.id] = order;
          }
        }

        final prefix = searchText.toUpperCase();
        if (prefix.length >= 3) {
          final prefixSnapshot = await _orders
              .orderBy('orderId')
              .startAt([prefix])
              .endAt(['$prefix$_prefixSearchTerminator'])
              .limit(safeLimit)
              .get()
              .timeout(AppDurations.networkTimeout);
          for (final doc in prefixSnapshot.docs) {
            final order = _fromDocument(doc);
            ordersById[order.id] = order;
          }
        }

        final orders = ordersById.values.toList()
          ..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });

        return OrderPage(
          orders: orders.take(safeLimit).toList(),
          hasMore: false,
        );
      },
    );
  }

  @override
  Future<OrderAnalytics> fetchOrderAnalytics({DateTime? date}) {
    return RepositoryGuard.run(
      message: 'Unable to load order analytics.',
      action: () async {
        final selectedDate = _dateOnly(date ?? DateTime.now());
        final nextDate = selectedDate.add(const Duration(days: 1));
        _dashboardLog(
          'Dashboard analytics initialization selectedDate='
          '${selectedDate.toIso8601String()}',
        );
        _dashboardLog(
          'Date filter query start=${selectedDate.toIso8601String()} '
          'end=${nextDate.toIso8601String()} fields=$_dateFields',
        );
        _dashboardLog('Orders query start collection=orders');

        final ordersSnapshot =
            await _orders.get().timeout(AppDurations.dashboardTimeout);
        _dashboardLog('Orders query result count=${ordersSnapshot.docs.length}');

        _dashboardLog('Revenue query start fields=$_revenueFields');
        final analytics = _analyticsFromOrdersSnapshot(
          ordersSnapshot,
          selectedDate: selectedDate,
          nextDate: nextDate,
        );
        _dashboardLog(
          'Revenue query result count=${ordersSnapshot.docs.length} '
          'revenue=${analytics.revenue} '
          'selectedDateRevenue=${analytics.selectedDateRevenue}',
        );

        return analytics;
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
      () {
        final pricing = CartPricingSummary.fromCartItems(cartItems);
        return CreateOrderRequest(
          userId: userId,
          userName: customerName,
          phone: '',
          address: address,
          pincode: '',
          items: cartItems.map(_cartItemToOrderItem).toList(),
          originalAmount: pricing.originalAmount,
          cartDiscount: pricing.cartDiscount,
          deliveryFee: pricing.deliveryFee,
          totalAmount: pricing.finalPayable,
          totalSavings: pricing.totalSavings,
          paymentMethod: paymentMethod,
        );
      }(),
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
    final originalAmount = request.originalAmount > 0
        ? request.originalAmount
        : request.items.fold<double>(
            0,
            (total, item) => total + item.lineTotal,
          );

    return {
      'orderId': orderId,
      'userId': userId,
      'userName': request.userName.trim(),
      'customerName': request.userName.trim(),
      'phone': request.phone.trim(),
      'address': request.address.trim(),
      'pincode': request.pincode.trim(),
      'items': request.items.map(_orderItemToMap).toList(),
      'originalAmount': originalAmount,
      'cartDiscount': request.cartDiscount,
      'deliveryFee': request.deliveryFee,
      'totalAmount': request.totalAmount,
      'total': request.totalAmount,
      'totalSavings': request.totalSavings,
      'searchTokens': _orderSearchTokens(orderId),
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

  OrderAnalytics _analyticsFromOrdersSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required DateTime selectedDate,
    required DateTime nextDate,
  }) {
    var totalOrders = 0;
    var pendingOrders = 0;
    var deliveredOrders = 0;
    var selectedDateOrders = 0;
    var revenue = 0.0;
    var selectedDateRevenue = 0.0;
    var missingDateCount = 0;
    var missingRevenueCount = 0;

    for (final doc in snapshot.docs) {
      totalOrders += 1;
      final data = doc.data();
      final status = OrderStatus.normalize(data['status']?.toString());
      if (status == OrderStatus.delivered) {
        deliveredOrders += 1;
      } else if (status == OrderStatus.placed ||
          status == OrderStatus.packed ||
          status == OrderStatus.outForDelivery) {
        pendingOrders += 1;
      }

      final amount = _readOrderRevenue(data);
      if (amount == null) {
        missingRevenueCount += 1;
      } else {
        revenue += amount;
      }

      final orderDate = _readOrderDate(data);
      if (orderDate == null) {
        missingDateCount += 1;
        continue;
      }

      if (!_dateOnly(orderDate).isBefore(selectedDate) &&
          orderDate.isBefore(nextDate)) {
        selectedDateOrders += 1;
        selectedDateRevenue += amount ?? 0;
      }
    }

    if (missingDateCount > 0 || missingRevenueCount > 0) {
      _dashboardLog(
        'Order analytics schema gaps missingDate=$missingDateCount '
        'missingRevenue=$missingRevenueCount',
      );
    }

    return OrderAnalytics(
      totalOrders: totalOrders,
      revenue: revenue,
      pendingOrders: pendingOrders,
      deliveredOrders: deliveredOrders,
      selectedDate: selectedDate,
      selectedDateOrders: selectedDateOrders,
      selectedDateRevenue: selectedDateRevenue,
    );
  }

  static double? _readOrderRevenue(Map<String, dynamic> data) {
    for (final field in _revenueFields) {
      final amount = _readNumericAmount(data[field]);
      if (amount != null) return amount < 0 ? 0 : amount;
    }
    return null;
  }

  static double? _readNumericAmount(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  static DateTime? _readOrderDate(Map<String, dynamic> data) {
    for (final field in _dateFields) {
      final date = readDateTime(data[field]);
      if (date != null) return date;
    }
    return null;
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
      originalAmount: readDouble(data['originalAmount']),
      cartDiscount: readDouble(data['cartDiscount']),
      deliveryFee: readDouble(data['deliveryFee']),
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

  static DateTime _dateOnly(DateTime date) {
    final localDate = date.toLocal();
    return DateTime(localDate.year, localDate.month, localDate.day);
  }

  static void _dashboardLog(String message) {
    if (!_debugLoggingEnabled) return;
    developer.log(message, name: _dashboardLogName);
  }

  static Set<String> _candidateOrderIds(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <String>{};
    return {
      trimmed,
      trimmed.toUpperCase(),
    };
  }

  static String _searchTokenFor(String query) {
    return query.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static List<String> _orderSearchTokens(String orderId) {
    final normalized = orderId.trim().toLowerCase();
    final compact = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final tokens = <String>{
      if (normalized.length >= 3) normalized,
      if (compact.length >= 3) compact,
      for (final part in normalized.split(RegExp(r'[^a-z0-9]+')))
        if (part.length >= 3) part,
    };

    void addPrefixes(String value) {
      final maxLength = value.length > 20 ? 20 : value.length;
      for (var length = 3; length <= maxLength; length += 1) {
        tokens.add(value.substring(0, length));
        if (tokens.length >= _maxOrderSearchTokens) return;
      }
    }

    void addSuffixes(String value) {
      final maxLength = value.length > 20 ? 20 : value.length;
      for (var length = 3; length <= maxLength; length += 1) {
        tokens.add(value.substring(value.length - length));
        if (tokens.length >= _maxOrderSearchTokens) return;
      }
    }

    void addSubstrings(String value) {
      for (var start = 0; start < value.length; start += 1) {
        for (var length = 3; length <= 8; length += 1) {
          final end = start + length;
          if (end > value.length) break;
          tokens.add(value.substring(start, end));
          if (tokens.length >= _maxOrderSearchTokens) return;
        }
      }
    }

    for (final value in {normalized, compact}) {
      if (value.length < 3) continue;
      addPrefixes(value);
      addSuffixes(value);
      addSubstrings(value);
      if (tokens.length >= _maxOrderSearchTokens) break;
    }

    return tokens.take(_maxOrderSearchTokens).toList();
  }
}

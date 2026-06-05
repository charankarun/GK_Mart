import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../../core/constants/app_constants.dart';
import '../../core/errors/repository_exception.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/cart_pricing.dart';
import '../../domain/entities/customer_order.dart';
import '../../domain/entities/order_analytics.dart';
import '../../domain/entities/order_page.dart';
import '../../domain/repositories/order_repository.dart';
import '../../domain/entities/store_config.dart';
import '../mappers/firestore_value_parser.dart';

class FirestoreOrderRepository implements OrderRepository {
  FirestoreOrderRepository(this._firestore);

  final FirebaseFirestore _firestore;
  static const _defaultUserOrderLimit = 20;
  static const _defaultAdminOrderLimit = 50;
  static const _maxPageLimit = 60;
  static const _orderIdPrefix = 'GK';
  static const _orderIdMinDigits = 5;
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
    String? status,
    bool descending = true,
  }) {
    return RepositoryGuard.run(
      message: 'Unable to load orders.',
      action: () async {
        final safeLimit = _safeLimit(limit);
        if (safeLimit <= 0) {
          return const OrderPage(orders: <Order>[], hasMore: false);
        }

        Query<Map<String, dynamic>> query = _orders;
        final normalizedStatus = _normalizedStatusFilter(status);
        if (normalizedStatus != null) {
          query = query.where('status', isEqualTo: normalizedStatus);
        }

        query = query.orderBy('timestamp', descending: descending).limit(safeLimit);
        query = await _startAfterOrderCursor(query: query, cursor: cursor);

        final snapshot = await query.get().timeout(AppDurations.networkTimeout);
        return _pageFromSnapshot(snapshot, safeLimit);
      },
    );
  }

  @override
  Future<OrderPage> fetchOrdersByDatePage({
    required DateTime date,
    required int limit,
    OrderPageCursor? cursor,
    String? status,
    bool descending = true,
  }) {
    return RepositoryGuard.run(
      message: 'Unable to load orders.',
      action: () async {
        final safeLimit = _safeLimit(limit);
        if (safeLimit <= 0) {
          return const OrderPage(orders: <Order>[], hasMore: false);
        }

        final startDate = _dateOnly(date);
        final endDate = startDate.add(const Duration(days: 1));
        final startTimestamp = Timestamp.fromDate(startDate);
        final endTimestamp = Timestamp.fromDate(endDate);
        Query<Map<String, dynamic>> query = _orders
            .where('timestamp', isGreaterThanOrEqualTo: startTimestamp)
            .where('timestamp', isLessThan: endTimestamp);

        final normalizedStatus = _normalizedStatusFilter(status);
        if (normalizedStatus != null) {
          query = query.where('status', isEqualTo: normalizedStatus);
        }

        query = query.orderBy('timestamp', descending: descending).limit(
              safeLimit,
            );
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
    String? status,
    bool descending = true,
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

        final normalizedStatus = _normalizedStatusFilter(status);
        final ordersById = <String, Order>{};

        // 1. Direct ID lookup candidates
        for (final candidateId in _candidateOrderIds(searchText)) {
          final doc = await _orders.doc(candidateId).get().timeout(
                AppDurations.networkTimeout,
              );
          if (doc.exists) {
            final order = _fromDocument(doc);
            if (_matchesStatus(order, normalizedStatus)) {
              ordersById[order.id] = order;
            }
          }
        }

        // 2. Token-based query candidates
        if (searchToken.length >= 2) {
          Query<Map<String, dynamic>> tokenQuery = _orders
              .where('searchTokens', arrayContains: searchToken);
          if (normalizedStatus != null) {
            tokenQuery = tokenQuery.where('status', isEqualTo: normalizedStatus);
          }
          tokenQuery = tokenQuery
              .orderBy('timestamp', descending: descending)
              .limit(safeLimit);

          final tokenSnapshot = await tokenQuery
              .get()
              .timeout(AppDurations.networkTimeout);
          for (final doc in tokenSnapshot.docs) {
            final order = _fromDocument(doc);
            ordersById[order.id] = order;
          }
        }

        // 3. Prefix-based query candidates
        final prefix = searchText.toUpperCase();
        if (prefix.length >= 2) {
          Query<Map<String, dynamic>> prefixQuery = _orders
              .orderBy('orderId')
              .startAt([prefix])
              .endAt(['$prefix$_prefixSearchTerminator']);
          if (normalizedStatus != null) {
            prefixQuery = prefixQuery.where('status', isEqualTo: normalizedStatus);
          }
          prefixQuery = prefixQuery.limit(safeLimit);

          final prefixSnapshot = await prefixQuery
              .get()
              .timeout(AppDurations.networkTimeout);
          for (final doc in prefixSnapshot.docs) {
            final order = _fromDocument(doc);
            ordersById[order.id] = order;
          }
        }

        // 4. Fetch the last 200 orders to locally scan as candidates for product names / older format search
        try {
          final recentSnapshot = await _orders
              .orderBy('timestamp', descending: descending)
              .limit(200)
              .get()
              .timeout(AppDurations.networkTimeout);
          for (final doc in recentSnapshot.docs) {
            final order = _fromDocument(doc);
            ordersById[order.id] = order;
          }
        } catch (e) {
          developer.log('Failed to fetch recent orders for local search', error: e);
        }

        // 5. Client-side filter across the four indices
        final queryLower = searchText.toLowerCase();
        final filteredOrders = ordersById.values.where((order) {
          if (!_matchesStatus(order, normalizedStatus)) return false;

          final idMatch = order.id.toLowerCase().contains(queryLower);
          final nameMatch = order.customerDisplayName.toLowerCase().contains(queryLower);
          final phoneMatch = order.phone.toLowerCase().contains(queryLower);
          final productMatch = order.items.any(
            (item) => item.name.toLowerCase().contains(queryLower),
          );

          return idMatch || nameMatch || phoneMatch || productMatch;
        }).toList();

        filteredOrders.sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return descending ? bDate.compareTo(aDate) : aDate.compareTo(bDate);
        });

        return OrderPage(
          orders: filteredOrders.take(safeLimit).toList(),
          hasMore: false,
        );
      },
    );
  }

  @override
  Future<OrderPage> searchAdminOrdersByDate({
    required String query,
    required DateTime date,
    required int limit,
    String? status,
    bool descending = true,
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

        final startDate = _dateOnly(date);
        final endDate = startDate.add(const Duration(days: 1));
        final startTimestamp = Timestamp.fromDate(startDate);
        final endTimestamp = Timestamp.fromDate(endDate);
        final normalizedStatus = _normalizedStatusFilter(status);
        final ordersById = <String, Order>{};

        // 1. Direct ID lookup candidates
        for (final candidateId in _candidateOrderIds(searchText)) {
          final doc = await _orders.doc(candidateId).get().timeout(
                AppDurations.networkTimeout,
              );
          if (!doc.exists) continue;
          final order = _fromDocument(doc);
          if (_isOrderInDateRange(order, startDate, endDate) &&
              _matchesStatus(order, normalizedStatus)) {
            ordersById[order.id] = order;
          }
        }

        // 2. Token-based query candidates
        if (searchToken.length >= 2) {
          Query<Map<String, dynamic>> tokenQuery = _orders
              .where('searchTokens', arrayContains: searchToken)
              .where('timestamp', isGreaterThanOrEqualTo: startTimestamp)
              .where('timestamp', isLessThan: endTimestamp);

          if (normalizedStatus != null) {
            tokenQuery =
                tokenQuery.where('status', isEqualTo: normalizedStatus);
          }

          tokenQuery = tokenQuery
              .orderBy('timestamp', descending: descending)
              .limit(safeLimit);

          final tokenSnapshot =
              await tokenQuery.get().timeout(AppDurations.networkTimeout);
          for (final doc in tokenSnapshot.docs) {
            final order = _fromDocument(doc);
            ordersById[order.id] = order;
          }
        }

        // 3. Fetch all orders for the date to scan locally
        try {
          final dateQuerySnapshot = await _orders
              .where('timestamp', isGreaterThanOrEqualTo: startTimestamp)
              .where('timestamp', isLessThan: endTimestamp)
              .get()
              .timeout(AppDurations.networkTimeout);
          for (final doc in dateQuerySnapshot.docs) {
            final order = _fromDocument(doc);
            ordersById[order.id] = order;
          }
        } catch (e) {
          developer.log('Failed to fetch orders by date for local search', error: e);
        }

        // 4. Client-side filter across the four indices
        final queryLower = searchText.toLowerCase();
        final filteredOrders = ordersById.values.where((order) {
          if (!_matchesStatus(order, normalizedStatus)) return false;
          if (!_isOrderInDateRange(order, startDate, endDate)) return false;

          final idMatch = order.id.toLowerCase().contains(queryLower);
          final nameMatch = order.customerDisplayName.toLowerCase().contains(queryLower);
          final phoneMatch = order.phone.toLowerCase().contains(queryLower);
          final productMatch = order.items.any(
            (item) => item.name.toLowerCase().contains(queryLower),
          );

          return idMatch || nameMatch || phoneMatch || productMatch;
        }).toList();

        filteredOrders.sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return descending ? bDate.compareTo(aDate) : aDate.compareTo(bDate);
        });

        return OrderPage(
          orders: filteredOrders.take(safeLimit).toList(),
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
        _dashboardLog(
            'Orders query result count=${ordersSnapshot.docs.length}');

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

        developer.log('Firestore write started', name: 'OrderCreation');
        try {
          // Verify store settings configuration
          final configDoc = await _firestore.collection('store_settings').doc('config').get();
          
          final configData = configDoc.data();
          final bool storeEnabled;
          final int openHour;
          final int openMinute;
          final int closeHour;
          final int closeMinute;
          
          if (!configDoc.exists || configData == null) {
            storeEnabled = true;
            openHour = 6;
            openMinute = 0;
            closeHour = 22;
            closeMinute = 0;
          } else {
            storeEnabled = configData['storeEnabled'] as bool? ?? false;
            openHour = configData['openHour'] as int? ?? 6;
            openMinute = configData['openMinute'] as int? ?? 0;
            closeHour = configData['closeHour'] as int? ?? 22;
            closeMinute = configData['closeMinute'] as int? ?? 0;
          }
          
          final now = DateTime.now();
          final config = StoreConfig(
            storeEnabled: storeEnabled,
            openHour: openHour,
            openMinute: openMinute,
            closeHour: closeHour,
            closeMinute: closeMinute,
          );
          
          if (!config.isOpenAt(now)) {
            throw RepositoryException(
              'Store is currently closed.',
              code: 'store-closed',
            );
          }

          final orderRef = _orders.doc();
          final orderId = orderRef.id;

          await orderRef.set(
            _orderData(
              orderId: orderId,
              request: request,
              userId: normalizedUserId,
              status: OrderStatus.pending,
            ),
          ).timeout(AppDurations.networkTimeout);

          developer.log('Firestore write succeeded', name: 'OrderCreation');
          return orderId;
        } catch (error, stackTrace) {
          developer.log(
            'Firestore write failed',
            name: 'OrderCreation',
            error: error,
            stackTrace: stackTrace,
          );
          rethrow;
        }
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

  @override
  Future<void> cancelOrder({
    required String orderId,
    required String userId,
  }) async {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) {
      developer.log('FirestoreOrderRepository: cancelOrder aborted - orderId is empty', name: 'OrderCancelTrace');
      throw ArgumentError.value(orderId, 'orderId', 'Required');
    }

    developer.log('FirestoreOrderRepository: cancelOrder started for orderId: $normalizedOrderId', name: 'OrderCancelTrace');

    return RepositoryGuard.run(
      message: 'Unable to cancel order.',
      action: () async {
        final orderRef = _orders.doc(normalizedOrderId);
        await orderRef.update({
          'status': OrderStatus.cancellationRequested,
          'updatedAt': FieldValue.serverTimestamp(),
          'timestamp': FieldValue.serverTimestamp(),
        }).timeout(AppDurations.networkTimeout);
        developer.log('FirestoreOrderRepository: Order cancellation requested successfully', name: 'OrderCancelTrace');
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
    String status = OrderStatus.placed,
  }) {
    // Compute originalAmount first, then round every monetary field to 2dp.
    // This ensures the Firestore security rule check
    //   totalAmount == originalAmount - cartDiscount + deliveryFee
    // always holds exactly, avoiding IEEE 754 floating-point mismatches.
    final rawOriginalAmount = request.originalAmount > 0
        ? request.originalAmount
        : request.items.fold<double>(
            0,
            (total, item) => total + item.lineTotal,
          );

    final originalAmount = _roundMoney(rawOriginalAmount);
    final cartDiscount = _roundMoney(request.cartDiscount);
    final deliveryFee = _roundMoney(request.deliveryFee);
    final totalSavings = _roundMoney(request.totalSavings);
    // Recompute totalAmount from the rounded components so the Firestore
    // rule equation is guaranteed to hold without any rounding error.
    final totalAmount = _roundMoney(originalAmount - cartDiscount + deliveryFee);

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
      'cartDiscount': cartDiscount,
      'deliveryFee': deliveryFee,
      'totalAmount': totalAmount,
      'total': totalAmount,
      'totalSavings': totalSavings,
      'searchTokens': _orderSearchTokens([
        orderId,
        request.userName,
        request.phone,
        ...request.items.map((item) => item.name),
      ]),
      'status': status,
      'paymentMethod': request.paymentMethod,
      'createdAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
    };
  }

  /// Rounds a monetary value to 2 decimal places to prevent IEEE 754
  /// floating-point mismatch when Firestore security rules re-evaluate
  /// the arithmetic equality check.
  static double _roundMoney(double value) {
    return (value * 100).roundToDouble() / 100;
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

  static String? _normalizedStatusFilter(String? status) {
    final normalized = OrderStatus.normalize(status);
    final trimmed = status?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return OrderStatus.values.contains(normalized) ? normalized : null;
  }

  static bool _isOrderInDateRange(
    Order order,
    DateTime startDate,
    DateTime endDate,
  ) {
    final createdAt = order.createdAt;
    if (createdAt == null) return false;
    return !createdAt.isBefore(startDate) && createdAt.isBefore(endDate);
  }

  static bool _matchesStatus(Order order, String? status) {
    if (status == null) return true;
    return OrderStatus.normalize(order.status) == status;
  }

  static void _dashboardLog(String message) {
    if (!_debugLoggingEnabled) return;
    developer.log(message, name: _dashboardLogName);
  }

  static Set<String> _candidateOrderIds(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <String>{};
    final candidates = {
      trimmed,
      trimmed.toUpperCase(),
    };
    final compact = _searchTokenFor(trimmed).toUpperCase();
    if (RegExp(r'^[0-9]{1,8}$').hasMatch(compact)) {
      candidates
          .add('$_orderIdPrefix${compact.padLeft(_orderIdMinDigits, '0')}');
    }
    return candidates;
  }

  static String _searchTokenFor(String query) {
    return query.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static List<String> _orderSearchTokens(Iterable<String> values) {
    final tokens = <String>{};

    void addCoreTokens(String value) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) return;
      final compact = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normalized.length >= 2) tokens.add(normalized);
      if (compact.length >= 2) tokens.add(compact);
      for (final part in normalized.split(RegExp(r'[^a-z0-9]+'))) {
        if (part.length >= 2) tokens.add(part);
      }
    }

    void addPrefixes(String value) {
      final maxLength = value.length > 20 ? 20 : value.length;
      for (var length = 2; length <= maxLength; length += 1) {
        tokens.add(value.substring(0, length));
        if (tokens.length >= _maxOrderSearchTokens) return;
      }
    }

    void addSuffixes(String value) {
      final maxLength = value.length > 20 ? 20 : value.length;
      for (var length = 2; length <= maxLength; length += 1) {
        tokens.add(value.substring(value.length - length));
        if (tokens.length >= _maxOrderSearchTokens) return;
      }
    }

    void addSubstrings(String value) {
      for (var start = 0; start < value.length; start += 1) {
        for (var length = 2; length <= 8; length += 1) {
          final end = start + length;
          if (end > value.length) break;
          tokens.add(value.substring(start, end));
          if (tokens.length >= _maxOrderSearchTokens) return;
        }
      }
    }

    for (final rawValue in values) {
      addCoreTokens(rawValue);
      final compact = rawValue.trim().toLowerCase().replaceAll(
            RegExp(r'[^a-z0-9]'),
            '',
          );
      if (compact.length < 2) continue;
      addPrefixes(compact);
      addSuffixes(compact);
      addSubstrings(compact);
      if (tokens.length >= _maxOrderSearchTokens) break;
    }

    return tokens.take(_maxOrderSearchTokens).toList();
  }
}

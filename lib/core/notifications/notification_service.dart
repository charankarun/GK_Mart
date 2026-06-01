import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../constants/app_constants.dart';
import 'notification_payload.dart';

typedef NotificationSelectionHandler = void Function(
  NotificationPayload payload,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.showBackgroundNotification(message);
}

@pragma('vm:entry-point')
void localNotificationTapBackground(NotificationResponse response) {}

class NotificationService {
  NotificationService._({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    FlutterLocalNotificationsPlugin? localNotifications,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _localNotifications =
            localNotifications ?? FlutterLocalNotificationsPlugin();

  static final NotificationService instance = NotificationService._();

  static const String orderUpdatesChannelId = 'order_updates';
  static const String _orderUpdatesChannelName = 'Order updates';
  static const String _orderUpdatesChannelDescription =
      'Updates about placed, packed, out for delivery, and delivered orders.';

  static const AndroidNotificationChannel _androidOrderChannel =
      AndroidNotificationChannel(
    orderUpdatesChannelId,
    _orderUpdatesChannelName,
    description: _orderUpdatesChannelDescription,
    importance: Importance.high,
  );

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FlutterLocalNotificationsPlugin _localNotifications;

  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  NotificationSelectionHandler? _onNotificationSelected;
  bool _isInitialized = false;
  bool _localNotificationsInitialized = false;
  String? _registeredUid;

  Future<void> initialize({
    required NotificationSelectionHandler onNotificationSelected,
  }) async {
    _onNotificationSelected = onNotificationSelected;
    if (_isInitialized) return;

    await _initializeLocalNotifications();
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    await requestPermissions();

    _foregroundMessageSubscription =
        FirebaseMessaging.onMessage.listen((message) {
      unawaited(_showForegroundNotification(message));
    });
    _messageOpenedSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessageOpen);

    await _handleInitialRemoteMessage();
    await _handleInitialLocalNotification();

    _isInitialized = true;
  }

  Future<void> dispose() async {
    await _foregroundMessageSubscription?.cancel();
    await _messageOpenedSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
  }

  Future<NotificationSettings> requestPermissions() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    final androidImplementation =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();

    return settings;
  }

  Future<void> registerDeviceForUser(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return;

    final settings = await requestPermissions();
    if (!_canUseNotifications(settings.authorizationStatus)) return;

    final token = await _messaging.getToken().timeout(
          AppDurations.networkTimeout,
        );
    if (token == null || token.trim().isEmpty) return;

    await _saveToken(normalizedUid, token.trim());
    _registeredUid = normalizedUid;

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((newToken) {
      final activeUid = _registeredUid;
      if (activeUid == null || activeUid.isEmpty) return;
      unawaited(_saveToken(activeUid, newToken.trim()));
    });
  }

  Future<void> unregisterDeviceForUser(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return;

    _registeredUid = null;
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;

    try {
      final token = await _messaging.getToken().timeout(
            AppDurations.networkTimeout,
          );
      if (token == null || token.trim().isEmpty) return;

      await _tokenDocument(normalizedUid, token.trim()).delete().timeout(
            AppDurations.networkTimeout,
          );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'notification_service',
          context: ErrorDescription('while unregistering an FCM token'),
        ),
      );
    }
  }

  Future<void> showOrderStatusNotification({
    required String orderId,
    required String status,
  }) async {
    await _initializeLocalNotifications();

    final payload = NotificationPayload.orderStatus(
      orderId: orderId,
      status: status,
    );
    final copy = OrderNotificationCopy.forStatus(
      status: payload.normalizedStatus,
      orderId: payload.orderId,
    );

    await _showLocalNotification(
      title: copy.title,
      body: copy.body,
      payload: payload,
    );
  }

  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    if (message.notification != null) return;

    final payload = NotificationPayload.fromMap(message.data);
    if (payload == null || !payload.isOrderNotification) return;

    final service = NotificationService._();
    await service._initializeLocalNotifications();
    await service._showRemoteMessageNotification(message, payload);
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) return;

    const androidSettings = AndroidInitializationSettings('ic_notification');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _handleLocalNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          localNotificationTapBackground,
    );

    final androidImplementation =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.createNotificationChannel(
      _androidOrderChannel,
    );

    _localNotificationsInitialized = true;
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final payload = NotificationPayload.fromMap(message.data);
    await _showRemoteMessageNotification(message, payload);
  }

  Future<void> _showRemoteMessageNotification(
    RemoteMessage message,
    NotificationPayload? payload,
  ) async {
    final notification = message.notification;
    final copy = payload?.isOrderNotification == true
        ? OrderNotificationCopy.forStatus(
            status: payload!.normalizedStatus,
            orderId: payload.orderId,
          )
        : null;

    final title = notification?.title?.trim().isNotEmpty == true
        ? notification!.title!.trim()
        : copy?.title;
    final body = notification?.body?.trim().isNotEmpty == true
        ? notification!.body!.trim()
        : copy?.body;

    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    await _showLocalNotification(
      title: title ?? _orderUpdatesChannelName,
      body: body ?? '',
      payload: payload,
    );
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required NotificationPayload? payload,
  }) {
    final encodedPayload = payload?.toJson();
    final key = encodedPayload ?? '$title|$body';

    const androidDetails = AndroidNotificationDetails(
      orderUpdatesChannelId,
      _orderUpdatesChannelName,
      channelDescription: _orderUpdatesChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    return _localNotifications.show(
      id: _notificationId(key),
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: encodedPayload,
    );
  }

  void _handleRemoteMessageOpen(RemoteMessage message) {
    final payload = NotificationPayload.fromMap(message.data);
    if (payload == null) return;
    _onNotificationSelected?.call(payload);
  }

  void _handleLocalNotificationResponse(NotificationResponse response) {
    final payload = NotificationPayload.fromJson(response.payload);
    if (payload == null) return;
    _onNotificationSelected?.call(payload);
  }

  Future<void> _handleInitialRemoteMessage() async {
    final message = await _messaging.getInitialMessage();
    if (message == null) return;
    _handleRemoteMessageOpen(message);
  }

  Future<void> _handleInitialLocalNotification() async {
    final launchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp != true) return;

    final response = launchDetails?.notificationResponse;
    final payload = NotificationPayload.fromJson(response?.payload);
    if (payload == null) return;
    _onNotificationSelected?.call(payload);
  }

  Future<void> _saveToken(String uid, String token) async {
    if (uid.isEmpty || token.isEmpty) return;

    final doc = _tokenDocument(uid, token);
    await _firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(doc);
      final data = snapshot.data();
      final hasCreatedAt = data?.containsKey('createdAt') ?? false;
      final now = FieldValue.serverTimestamp();

      transaction.set(
        doc,
        {
          'token': token,
          'platform': _platformName,
          'enabled': true,
          if (!snapshot.exists || !hasCreatedAt) 'createdAt': now,
          'updatedAt': now,
          'lastSeenAt': now,
        },
        SetOptions(merge: true),
      );
    }).timeout(AppDurations.networkTimeout);
  }

  DocumentReference<Map<String, dynamic>> _tokenDocument(
    String uid,
    String token,
  ) {
    final tokenId = base64Url.encode(utf8.encode(token)).replaceAll('=', '');
    return _firestore
        .collection(FirestoreCollections.users)
        .doc(uid)
        .collection(FirestoreSubcollections.fcmTokens)
        .doc(tokenId);
  }

  static bool _canUseNotifications(AuthorizationStatus status) {
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  static int _notificationId(String key) {
    var hash = 0;
    for (final codeUnit in key.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash == 0
        ? DateTime.now().millisecondsSinceEpoch & 0x7fffffff
        : hash;
  }

  static String get _platformName {
    if (kIsWeb) return 'web';

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}

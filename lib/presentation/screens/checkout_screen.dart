import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error_handler.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone_number_normalizer.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/cart_pricing.dart';
import '../../domain/entities/order.dart';
import '../../services/analytics_service.dart';
import '../providers/auth_providers.dart';
import '../providers/commerce_providers.dart';
import '../providers/order_providers.dart';
import '../providers/repository_providers.dart';
import '../providers/store_providers.dart';
import '../widgets/app_cached_network_image.dart';
import '../widgets/app_state_widgets.dart';
import 'address_screen.dart';
import 'order_success_screen.dart';
import '../../core/errors/repository_exception.dart';
import '../navigation/customer_navigation_scope.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  final pincodeController = TextEditingController();
  bool hasSeededProfile = false;
  bool hasLoggedBeginCheckout = false;
  bool isEditingDetails = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cartSyncProvider.notifier).syncCart();
    });
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    pincodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(CheckoutText.title)),
        body: const Center(child: Text(CheckoutText.loginRequired)),
      );
    }

    final activeAddress = ref.watch(activeAddressProvider);
    final profileAsync = ref.watch(currentUserProfileProvider);
    final isProfileLoading = profileAsync.isLoading && !hasSeededProfile;

    if (isProfileLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text(CheckoutText.title)),
        body: const _CheckoutSkeleton(),
      );
    }

    final profile = profileAsync.maybeWhen(
          data: (user) => user,
          orElse: () => null,
        );
    if (!hasSeededProfile && profile != null) {
      hasSeededProfile = true;
      nameController.text = profile.name.trim();
      phoneController.text = _normalizedPhoneOrOriginal(profile.phone);
      final seedAddress = activeAddress.isNotEmpty ? activeAddress : profile.address.trim();
      // Bug 1 fix: parse the stored address so the 'Pincode: ...' line is
      // separated into pincodeController — preventing duplicate pincode display.
      final parsed = ParsedAddress.from(seedAddress);
      addressController.text = _buildDisplayAddress(parsed);
      pincodeController.text = parsed.pincode.isNotEmpty
          ? parsed.pincode
          : _extractPincode(seedAddress);
    }

    final syncState = ref.watch(cartSyncProvider);
    final List<CartItem> cartItems = syncState.recalculatedItems ?? ref.watch(cartItemsProvider);
    final CartPricingSummary pricing = syncState.recalculatedPricing ?? ref.watch(cartPricingSummaryProvider);
    final orderCreationState = ref.watch(orderCreationControllerProvider);
    final isLoading = orderCreationState.isLoading;
    final hasUnavailable = syncState.unavailableProductIds.isNotEmpty;

    if (!hasLoggedBeginCheckout && cartItems.isNotEmpty) {
      hasLoggedBeginCheckout = true;
      ref.read(analyticsServiceProvider).logBeginCheckout(
        value: pricing.finalPayable,
        totalItems: cartItems.length,
      );
    }

    final storeConfig = ref.watch(storeConfigProvider).maybeWhen(
          data: (config) => config,
          orElse: () => null,
        );

    final String? storeClosedMessage;
    final bool isStoreClosed;
    if (storeConfig != null) {
      if (!storeConfig.isOpen) {
        storeClosedMessage = 'Store is currently closed.\nReopens at ${storeConfig.formattedOpenTime}.';
        isStoreClosed = true;
      } else {
        storeClosedMessage = null;
        isStoreClosed = false;
      }
    } else {
      storeClosedMessage = null;
      isStoreClosed = false;
    }

    final hasAddress = addressController.text.trim().isNotEmpty;
    final hasName = nameController.text.trim().isNotEmpty;
    final hasPhone = phoneController.text.trim().isNotEmpty;
    final hasPincode = pincodeController.text.trim().isNotEmpty;
    final showForm = isEditingDetails || !hasAddress || !hasName || !hasPhone || !hasPincode;

    return Scaffold(
      appBar: AppBar(title: const Text(CheckoutText.title)),
      body: cartItems.isEmpty
          ? const _EmptyCheckout()
          : Form(
              key: formKey,
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        if (syncState.syncMessage != null) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _SyncWarningBanner(message: syncState.syncMessage!),
                          ),
                        ],
                        if (storeClosedMessage != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(AppRadii.md),
                              border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.storefront_rounded, color: AppColors.danger),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    storeClosedMessage,
                                    style: const TextStyle(
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _OrderItemsPreview(
                          items: cartItems,
                          onTap: () => _showAllItemsBottomSheet(context, cartItems),
                        ),
                        const SizedBox(height: 12),
                        if (showForm) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(AppRadii.lg),
                              border: Border.all(color: AppColors.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Delivery Details',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        TextButton(
                                          onPressed: _openAddressScreen,
                                          style: TextButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                          ),
                                          child: const Text('Saved Address'),
                                        ),
                                        if (hasAddress && hasName && hasPhone && hasPincode) ...[
                                          const SizedBox(width: 8),
                                          TextButton.icon(
                                            onPressed: () {
                                              if (formKey.currentState?.validate() == true) {
                                                setState(() {
                                                  isEditingDetails = false;
                                                });
                                              }
                                            },
                                            icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                                            label: const Text('Save'),
                                            style: TextButton.styleFrom(
                                              visualDensity: VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _CheckoutFields(
                                  nameController: nameController,
                                  phoneController: phoneController,
                                  addressController: addressController,
                                  pincodeController: pincodeController,
                                  serviceablePincodes: ref.watch(
                                    serviceablePincodesProvider,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          _SavedAddressCard(
                            name: nameController.text.trim(),
                            phone: phoneController.text.trim(),
                            address: addressController.text.trim(),
                            pincode: pincodeController.text.trim(),
                            onChangeAddress: _openAddressScreen,
                            onEditDetails: () {
                              setState(() {
                                isEditingDetails = true;
                              });
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        const _DeliveryEtaCard(),
                        const SizedBox(height: 12),
                        const _PaymentMethodCard(),
                      ],
                    ),
                  ),
                  _CheckoutSummary(
                    pricing: pricing,
                    isLoading: isLoading,
                    isStoreClosed: isStoreClosed,
                    onPlaceOrder: hasUnavailable
                        ? null
                        : () {
                            _placeOrder(
                              userId: session.uid,
                              cartItems: cartItems,
                              pricing: pricing,
                            );
                          },
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _placeOrder({
    required String userId,
    required List<CartItem> cartItems,
    required CartPricingSummary pricing,
  }) async {
    _logCheckoutOrder('Place Order clicked');
    if (ref.read(orderCreationControllerProvider).isLoading) return;

    final hasAddress = addressController.text.trim().isNotEmpty;
    final hasName = nameController.text.trim().isNotEmpty;
    final hasPhone = phoneController.text.trim().isNotEmpty;
    final hasPincode = pincodeController.text.trim().isNotEmpty;
    final showForm = isEditingDetails || !hasAddress || !hasName || !hasPhone || !hasPincode;

    if (!showForm) {
      final name = nameController.text.trim();
      final phone = phoneController.text.trim();
      final address = addressController.text.trim();
      final pincode = pincodeController.text.trim();

      if (name.isEmpty || address.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill all delivery details.')),
        );
        setState(() {
          isEditingDetails = true;
        });
        return;
      }

      if (!PhoneNumberNormalizer.isIndianLocalNumber(phone)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid 10-digit phone number')),
        );
        setState(() {
          isEditingDetails = true;
        });
        return;
      }

      if (!RegExp(r'^[0-9]{6}$').hasMatch(pincode)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid 6-digit pincode')),
        );
        setState(() {
          isEditingDetails = true;
        });
        return;
      }

      final serviceablePincodes = ref.read(serviceablePincodesProvider);
      if (!serviceablePincodes.contains(pincode)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sorry! Delivery is currently available only in Pincode 515301.')),
        );
        setState(() {
          isEditingDetails = true;
        });
        return;
      }
    } else {
      if (formKey.currentState?.validate() != true) {
        _logCheckoutOrder(
            'Stopped before order request: checkout validation failed.');
        return;
      }
    }

    _logCheckoutOrder('Validation passed');
    if (cartItems.isEmpty) {
      _logCheckoutOrder('Stopped before order request: cart is empty.');
      return;
    }

    // Double check stock levels before placing the order
    try {
      final productIds = cartItems.map((item) => item.productId).toList();
      final latestProducts = await ref.read(productRepositoryProvider).fetchProductsByIds(productIds);
      for (final cartItem in cartItems) {
        final idx = latestProducts.indexWhere((p) => p.id == cartItem.productId);
        if (idx != -1) {
          final product = latestProducts[idx];
          if (!product.isAvailable || product.isStockEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(
                  content: Text('${product.name} is out of stock.'),
                  duration: const Duration(seconds: 5),
                ),
              );
            return;
          }
          if (product.trackStock) {
            final stock = product.stockQuantity ?? 0;
            if (stock < cartItem.quantity) {
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                    content: Text('Only $stock items available for this product.'),
                    duration: const Duration(seconds: 5),
                  ),
                );
              return;
            }
          }
        }
      }
    } catch (e) {
      _logCheckoutOrder('Stock validation check failed dynamically: $e');
    }

    if (!mounted) return;

    final normalizedPhone = PhoneNumberNormalizer.toIndianLocalNumber(
      phoneController.text,
    );
    _logCheckoutOrder(
      'Creating order request '
      'userIdPresent=${userId.trim().isNotEmpty} '
      'items=${cartItems.length} '
      'phoneNormalized=${normalizedPhone.isNotEmpty}',
    );

    final request = CreateOrderRequest(
      userId: userId,
      userName: nameController.text.trim(),
      phone: normalizedPhone,
      address: addressController.text.trim(),
      pincode: pincodeController.text.trim(),
      items: cartItems.map(_toOrderItem).toList(),
      originalAmount: pricing.originalAmount,
      cartDiscount: pricing.cartDiscount,
      deliveryFee: pricing.deliveryFee,
      totalAmount: pricing.finalPayable,
      totalSavings: pricing.totalSavings,
    );
    _logCheckoutOrder('CreateOrderRequest created');

    try {
      _logCheckoutOrder('_placeOrder: calling createOrder...');
      ref.read(analyticsServiceProvider).logPurchaseAttempt(
        orderId: 'attempt_${DateTime.now().millisecondsSinceEpoch}',
        value: pricing.finalPayable,
      );
      final orderId =
          await ref.read(orderCreationControllerProvider.notifier).createOrder(
                request,
              );
      _logCheckoutOrder('Order created successfully orderId=$orderId.');

      final uid = userId;
      ref.invalidate(userOrderListProvider(uid));
      await ref.read(userOrderListProvider(uid).notifier).loadInitial();

      ref.invalidate(adminOrderListProvider);
      ref.invalidate(dashboardRecentOrdersProvider);

      _logCheckoutOrder('Backend will handle notification');
      ref.read(cartControllerProvider.notifier).clear();
      ref.read(orderCreationControllerProvider.notifier).reset();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OrderSuccessScreen()),
      );
    } catch (error) {
      _logCheckoutOrder(
        '_placeOrder: order creation FAILED.',
        error: error,
      );

      if (!mounted) return;

      final isTimeout = error is RepositoryException && error.code == 'timeout';
      if (isTimeout) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('Order Still Processing'),
            content: const Text(
              'Your order processing is taking longer than expected. '
              'The process is still running in the background. '
              'We are redirecting you to your Orders history to check status.'
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  CustomerNavigationScope.openOrders(context);
                },
                child: const Text('Go to Orders'),
              ),
            ],
          ),
        );
        return;
      }

      final String message;
      if (kDebugMode) {
        message = AppErrorHandler.messageFor(
          error,
          fallback: CheckoutText.placeOrderError,
        );
      } else {
        message = AppErrorHandler.isPermissionDenied(error)
            ? CheckoutText.placeOrderError
            : AppErrorHandler.messageFor(
                error,
                fallback: CheckoutText.placeOrderError,
              );
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 8),
          ),
        );

      ref.read(cartSyncProvider.notifier).syncCart();
    }
  }

  Future<void> _openAddressScreen() async {
    // Bug 2 fix: open AddressScreen in selection mode so tapping a card
    // immediately returns the address instead of opening the edit form.
    final savedAddress = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const AddressScreen(selectMode: true)),
    );

    if (!mounted) return;
    if (savedAddress == null || savedAddress.trim().isEmpty) return;

    ref.read(activeAddressProvider.notifier).selectAddress(savedAddress.trim());

    // Bug 1 fix: strip the 'Pincode: ...' line from the address text so the
    // pincode field is the only place it appears.
    final parsed = ParsedAddress.from(savedAddress.trim());
    addressController.text = _buildDisplayAddress(parsed);
    if (parsed.pincode.isNotEmpty) {
      pincodeController.text = parsed.pincode;
    } else {
      final pincode = _extractPincode(savedAddress);
      if (pincode.isNotEmpty) pincodeController.text = pincode;
    }
  }

  void _showAllItemsBottomSheet(BuildContext context, List<CartItem> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AllItemsBottomSheet(items: items),
    );
  }

  OrderItem _toOrderItem(CartItem item) {
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

  String _extractPincode(String address) {
    final match = RegExp(r'\b[0-9]{6}\b').firstMatch(address);
    return match?.group(0) ?? '';
  }

  /// Reconstructs a display-ready address string from a [ParsedAddress],
  /// including the landmark line but NOT the pincode line.
  String _buildDisplayAddress(ParsedAddress parsed) {
    final parts = <String>[parsed.address];
    if (parsed.landmark.isNotEmpty) {
      parts.add('${AddressText.landmarkPrefix} ${parsed.landmark}');
    }
    return parts.join('\n');
  }

  String _normalizedPhoneOrOriginal(String value) {
    final normalized = PhoneNumberNormalizer.toIndianLocalNumber(value);
    if (normalized.isNotEmpty) return normalized;
    return value.trim();
  }
}

class _OrderItemsPreview extends StatelessWidget {
  const _OrderItemsPreview({
    required this.items,
    required this.onTap,
  });

  final List<CartItem> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final displayedItems = items.take(3).toList();
    final remainingCount = items.length - displayedItems.length;

    return _CheckoutSection(
      title: 'Order Items (${items.length})',
      child: SizedBox(
        height: 72,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: displayedItems.length + (remainingCount > 0 ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            if (index < displayedItems.length) {
              final item = displayedItems[index];
              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: AppCachedNetworkImage(
                          imageUrl: item.imageUrl.trim(),
                          fit: BoxFit.cover,
                          placeholder: const AppSkeletonPulse(width: 64, height: 64),
                          errorPlaceholder: const _ThumbnailErrorPlaceholder(),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: Text(
                          'x${item.quantity}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            } else {
              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.softGreen,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Center(
                    child: Text(
                      '+$remainingCount\nmore',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}

class _ThumbnailErrorPlaceholder extends StatelessWidget {
  const _ThumbnailErrorPlaceholder({this.iconSize = 16});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.background),
      child: Center(
        child: Icon(
          Icons.local_grocery_store_rounded,
          color: AppColors.mutedText,
          size: iconSize,
        ),
      ),
    );
  }
}

class _AllItemsBottomSheet extends ConsumerWidget {
  const _AllItemsBottomSheet({required this.items});

  final List<CartItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(cartSyncProvider);
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.65; // ~65% screen height

    int totalQty = 0;
    double subtotalValue = 0.0;
    for (final item in items) {
      totalQty += item.quantity;
      subtotalValue += item.lineTotal;
    }

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Items in Cart (${items.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, color: AppColors.border),
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isPriceChanged = syncState.priceChangedProductIds.contains(item.productId);
                    final isUnavailable = syncState.unavailableProductIds.contains(item.productId);
                    final oldPrice = syncState.oldPrices[item.productId];
                    final newPrice = syncState.newPrices[item.productId];

                    return Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isUnavailable
                                  ? AppColors.danger
                                  : isPriceChanged
                                      ? AppColors.accent
                                      : AppColors.border,
                              width: (isUnavailable || isPriceChanged) ? 1.5 : 1.0,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: AppCachedNetworkImage(
                              imageUrl: item.imageUrl.trim(),
                              fit: BoxFit.cover,
                              placeholder: const AppSkeletonPulse(width: 40, height: 40),
                              errorPlaceholder: const _ThumbnailErrorPlaceholder(iconSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: isUnavailable ? AppColors.danger : AppColors.text,
                                  decoration: isUnavailable ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              if (isUnavailable) ...[
                                const SizedBox(height: 2),
                                const Text(
                                  "This product is no longer available.",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                              if (isPriceChanged && oldPrice != null && newPrice != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  "⚠ Price Updated (Old: ₹${_formatPrice(oldPrice)}, New: ₹${_formatPrice(newPrice)})",
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                              if (!isUnavailable && item.unit.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  item.unit,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.mutedText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'x${item.quantity}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '₹${_formatPrice(item.lineTotal)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.border),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Subtotal',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.mutedText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$totalQty ${totalQty == 1 ? "item" : "items"}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '₹${_formatPrice(subtotalValue)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPrice(double price) {
    return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
  }
}

class _SavedAddressCard extends StatelessWidget {
  const _SavedAddressCard({
    required this.name,
    required this.phone,
    required this.address,
    required this.pincode,
    required this.onChangeAddress,
    required this.onEditDetails,
  });

  final String name;
  final String phone;
  final String address;
  final String pincode;
  final VoidCallback onChangeAddress;
  final VoidCallback onEditDetails;

  @override
  Widget build(BuildContext context) {
    return _CheckoutSection(
      title: 'Delivery Address',
      trailing: TextButton.icon(
        onPressed: onChangeAddress,
        icon: const Icon(Icons.edit_location_alt_rounded, size: 16),
        label: const Text('Change'),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            phone,
                            style: const TextStyle(
                              color: AppColors.mutedText,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onEditDetails,
                      icon: const Icon(Icons.edit_rounded, size: 16, color: AppColors.primary),
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$address, $pincode',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutFields extends StatelessWidget {
  const _CheckoutFields({
    required this.nameController,
    required this.phoneController,
    required this.addressController,
    required this.pincodeController,
    required this.serviceablePincodes,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final TextEditingController pincodeController;
  final Set<String> serviceablePincodes;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CheckoutInput(
          controller: nameController,
          label: CheckoutText.name,
          validator: _required,
        ),
        const SizedBox(height: 12),
        _CheckoutInput(
          controller: phoneController,
          label: CheckoutText.phone,
          keyboardType: TextInputType.phone,
          validator: _phoneValidator,
        ),
        const SizedBox(height: 12),
        _CheckoutInput(
          controller: addressController,
          label: CheckoutText.address,
          maxLines: 3,
          validator: _required,
        ),
        const SizedBox(height: 12),
        _CheckoutInput(
          controller: pincodeController,
          label: CheckoutText.pincode,
          keyboardType: TextInputType.number,
          validator: _pincodeValidator,
        ),
      ],
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return CheckoutText.requiredField;
    }
    return null;
  }

  String? _phoneValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return CheckoutText.requiredField;
    if (!PhoneNumberNormalizer.isIndianLocalNumber(trimmed)) {
      return CheckoutText.invalidPhone;
    }
    return null;
  }

  String? _pincodeValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return CheckoutText.requiredField;
    if (!RegExp(r'^[0-9]{6}$').hasMatch(trimmed)) {
      return CheckoutText.invalidPincode;
    }
    if (!serviceablePincodes.contains(trimmed)) {
      return CheckoutText.unserviceablePincode;
    }
    return null;
  }
}

class _CheckoutInput extends StatelessWidget {
  const _CheckoutInput({
    required this.controller,
    required this.label,
    required this.validator,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String> validator;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: maxLines > 1,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        errorMaxLines: 3,
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard();

  @override
  Widget build(BuildContext context) {
    return _CheckoutSection(
      title: CheckoutText.payment,
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.payments_rounded, color: AppColors.primary),
              SizedBox(width: 10),
              Text(
                CheckoutText.cashOnDelivery,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              Spacer(),
              Icon(Icons.check_circle_rounded, color: AppColors.primary),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_rounded, color: Colors.green.shade700, size: 16),
              const SizedBox(width: 6),
              Text(
                'Safe & Secure Checkout',
                style: TextStyle(
                  color: Colors.green.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckoutSection extends StatelessWidget {
  const _CheckoutSection({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _CheckoutSummary extends StatefulWidget {
  const _CheckoutSummary({
    required this.pricing,
    required this.isLoading,
    this.onPlaceOrder,
    this.isStoreClosed = false,
  });

  final CartPricingSummary pricing;
  final bool isLoading;
  final VoidCallback? onPlaceOrder;
  final bool isStoreClosed;

  @override
  State<_CheckoutSummary> createState() => _CheckoutSummaryState();
}

class _CheckoutSummaryState extends State<_CheckoutSummary> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      children: [
                        const Text(
                          'Bill Details',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.text,
                          ),
                        ),
                        if (widget.pricing.totalSavings > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.softGreen,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '🎉',
                                  style: TextStyle(fontSize: 10),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Saved \u20B9${_formatPrice(widget.pricing.totalSavings)}',
                                  style: const TextStyle(
                                    color: AppColors.primaryDark,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Spacer(),
                        AnimatedRotation(
                          turns: _isExpanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOutCubic,
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: AppColors.mutedText,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: _isExpanded
                      ? Column(
                          children: [
                            const SizedBox(height: 8),
                            _SummaryRow(
                              label: CheckoutText.originalAmount,
                              value: '\u20B9${_formatPrice(widget.pricing.originalAmount)}',
                              labelColor: AppColors.mutedText,
                              fontSize: 13,
                            ),
                            if (widget.pricing.productSavings > 0) ...[
                              const SizedBox(height: 6),
                              _SummaryRow(
                                label: 'Product Savings',
                                value: '-\u20B9${_formatPrice(widget.pricing.productSavings)}',
                                valueColor: AppColors.primary,
                                labelColor: AppColors.mutedText,
                                fontSize: 13,
                              ),
                            ],
                            const SizedBox(height: 6),
                            _SummaryRow(
                              label: CheckoutText.cartDiscount,
                              value: widget.pricing.cartDiscount > 0
                                  ? '-\u20B9${_formatPrice(widget.pricing.cartDiscount)}'
                                  : '\u20B90',
                              valueColor: AppColors.primary,
                              labelColor: AppColors.mutedText,
                              fontSize: 13,
                            ),
                            const SizedBox(height: 6),
                            _SummaryRow(
                              label: CheckoutText.deliveryFee,
                              value: widget.pricing.deliveryFee > 0
                                  ? '\u20B9${_formatPrice(widget.pricing.deliveryFee)}'
                                  : CheckoutText.free,
                              valueColor: widget.pricing.deliveryFee > 0 ? null : AppColors.primary,
                              labelColor: AppColors.mutedText,
                              fontSize: 13,
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: AppColors.border),
                ),
                _SummaryRow(
                  label: CheckoutText.finalPayable,
                  value: '\u20B9${_formatPrice(widget.pricing.finalPayable)}',
                  isBold: true,
                  fontSize: 14,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                elevation: 0,
              ),
              onPressed: widget.isLoading || widget.isStoreClosed ? null : widget.onPlaceOrder,
              child: widget.isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Processing Order...',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bolt_rounded, size: 18, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          'Place Order \u2022 \u20B9${_formatPrice(widget.pricing.finalPayable)}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrice(double price) {
    return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
  }
}

class _DeliveryEtaCard extends StatelessWidget {
  const _DeliveryEtaCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.softGreen.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delivery Today',
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Estimated Delivery: 20\u201330 mins',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutSkeleton extends StatelessWidget {
  const _CheckoutSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSkeletonPulse(width: 100, height: 16),
              const SizedBox(height: 12),
              Row(
                children: const [
                  AppSkeletonPulse(width: 64, height: 64),
                  SizedBox(width: 12),
                  AppSkeletonPulse(width: 64, height: 64),
                  SizedBox(width: 12),
                  AppSkeletonPulse(width: 64, height: 64),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  AppSkeletonPulse(width: 120, height: 16),
                  AppSkeletonPulse(width: 60, height: 14),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppSkeletonPulse(width: 40, height: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        AppSkeletonPulse(width: 150, height: 14),
                        SizedBox(height: 6),
                        AppSkeletonPulse(width: 220, height: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: const [
              AppSkeletonPulse(width: 36, height: 36, borderRadius: 18),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeletonPulse(width: 100, height: 14),
                  SizedBox(height: 6),
                  AppSkeletonPulse(width: 160, height: 12),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: const [
              AppSkeletonPulse(width: 24, height: 24),
              SizedBox(width: 12),
              AppSkeletonPulse(width: 140, height: 14),
              Spacer(),
              AppSkeletonPulse(width: 20, height: 20, borderRadius: 10),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyCheckout extends StatelessWidget {
  const _EmptyCheckout();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.softGreen,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  '🛒',
                  style: TextStyle(fontSize: 40),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Your cart is empty',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add items to your cart before checking out.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.mutedText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 200,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pop(context); // Go back to cart/home
                },
                child: const Text(
                  'Go Back',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.labelColor,
    this.isBold = false,
    this.fontSize = 13,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final Color? labelColor;
  final bool isBold;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final weight = isBold ? FontWeight.w900 : FontWeight.w600;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: weight,
              fontSize: fontSize,
              color: labelColor ?? AppColors.text,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.text,
            fontWeight: weight,
            fontSize: fontSize,
          ),
        ),
      ],
    );
  }
}

class CheckoutText {
  const CheckoutText._();

  static const title = 'Checkout';
  static const loginRequired = 'Please login to checkout';
  static const emptyCart = 'Your cart is empty';
  static const items = 'Items';
  static const savedAddress = 'Saved Address';
  static const noSavedAddress = 'No saved address yet';
  static const addAddress = 'Add';
  static const changeAddress = 'Change';
  static const deliveryDetails = 'Delivery Details';
  static const name = 'Name';
  static const phone = 'Phone';
  static const address = 'Address';
  static const pincode = 'Pincode';
  static const payment = 'Payment';
  static const cashOnDelivery = 'Cash on Delivery';
  static const originalAmount = 'Original Amount';
  static const cartDiscount = 'Cart Discount';
  static const deliveryFee = 'Delivery Fee';
  static const totalSavings = 'Total Savings';
  static const finalPayable = 'Final Payable';
  static const free = 'Free';
  static const placeOrder = 'Place Order';
  static const placeOrderError = 'Unable to place order';
  static const requiredField = 'Required';
  static const invalidPhone = 'Enter a valid 10-digit phone number';
  static const invalidPincode = 'Enter a valid 6-digit pincode';
  static const unserviceablePincode = 'Sorry! Delivery is currently available only in Pincode 515301.';
}

const _checkoutOrderLogName = 'CheckoutOrder';
const _checkoutDebugLoggingEnabled = !bool.fromEnvironment('dart.vm.product');

void _logCheckoutOrder(
  String message, {
  Object? error,
}) {
  if (!_checkoutDebugLoggingEnabled) return;
  developer.log(message, name: _checkoutOrderLogName, error: error);
}


class _SyncWarningBanner extends StatelessWidget {
  const _SyncWarningBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.softOrange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


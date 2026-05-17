import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error_handler.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/order.dart';
import '../providers/auth_providers.dart';
import '../providers/commerce_providers.dart';
import '../providers/order_providers.dart';
import 'address_screen.dart';
import 'order_success_screen.dart';

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

    final profile = ref.watch(currentUserProfileProvider).maybeWhen(
          data: (user) => user,
          orElse: () => null,
        );
    if (!hasSeededProfile && profile != null) {
      hasSeededProfile = true;
      nameController.text = profile.name.trim();
      phoneController.text = profile.phone.trim();
      addressController.text = profile.address.trim();
      pincodeController.text = _extractPincode(profile.address);
    }

    final cartItems = ref.watch(cartItemsProvider);
    final total = ref.watch(cartTotalProvider);
    final savings = ref.watch(cartSavingsProvider);
    final orderCreationState = ref.watch(orderCreationControllerProvider);
    final isLoading = orderCreationState.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text(CheckoutText.title)),
      body: cartItems.isEmpty
          ? const Center(child: Text(CheckoutText.emptyCart))
          : Form(
              key: formKey,
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        _OrderItemsPreview(items: cartItems),
                        const SizedBox(height: 12),
                        _SavedAddressCard(
                          address: profile?.address ?? '',
                          onManageAddress: _openAddressScreen,
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
                        const SizedBox(height: 12),
                        const _PaymentMethodCard(),
                      ],
                    ),
                  ),
                  _CheckoutSummary(
                    total: total,
                    savings: savings,
                    isLoading: isLoading,
                    onPlaceOrder: () {
                      _placeOrder(
                        userId: session.uid,
                        cartItems: cartItems,
                        total: total,
                        savings: savings,
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
    required double total,
    required double savings,
  }) async {
    if (ref.read(orderCreationControllerProvider).isLoading) return;
    if (formKey.currentState?.validate() != true || cartItems.isEmpty) return;

    final request = CreateOrderRequest(
      userId: userId,
      userName: nameController.text.trim(),
      phone: phoneController.text.trim(),
      address: addressController.text.trim(),
      pincode: pincodeController.text.trim(),
      items: cartItems.map(_toOrderItem).toList(),
      totalAmount: total,
      totalSavings: savings,
    );

    try {
      final orderId =
          await ref.read(orderCreationControllerProvider.notifier).createOrder(
                request,
              );
      unawaited(
        NotificationService.instance.showOrderStatusNotification(
          orderId: orderId,
          status: OrderStatus.placed,
        ),
      );
      ref.read(cartControllerProvider.notifier).clear();
      ref.read(orderCreationControllerProvider.notifier).reset();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OrderSuccessScreen()),
      );
    } catch (error) {
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: CheckoutText.placeOrderError,
      );
    }
  }

  Future<void> _openAddressScreen() async {
    final savedAddress = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const AddressScreen()),
    );

    if (!mounted) return;
    if (savedAddress == null || savedAddress.trim().isEmpty) return;

    addressController.text = savedAddress.trim();
    final pincode = _extractPincode(savedAddress);
    if (pincode.isNotEmpty) pincodeController.text = pincode;
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
}

class _OrderItemsPreview extends StatelessWidget {
  const _OrderItemsPreview({required this.items});

  final List<CartItem> items;

  @override
  Widget build(BuildContext context) {
    return _CheckoutSection(
      title: CheckoutText.items,
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.name} x ${item.quantity}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '\u20B9${_formatPrice(item.lineTotal)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
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

class _SavedAddressCard extends StatelessWidget {
  const _SavedAddressCard({
    required this.address,
    required this.onManageAddress,
  });

  final String address;
  final VoidCallback onManageAddress;

  @override
  Widget build(BuildContext context) {
    final visibleAddress = address.trim();

    return _CheckoutSection(
      title: CheckoutText.savedAddress,
      trailing: TextButton.icon(
        onPressed: onManageAddress,
        icon: Icon(
          visibleAddress.isEmpty ? Icons.add_location_alt : Icons.edit_location,
          size: 18,
        ),
        label: Text(
          visibleAddress.isEmpty
              ? CheckoutText.addAddress
              : CheckoutText.changeAddress,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: visibleAddress.isEmpty
                  ? AppColors.softOrange
                  : AppColors.softGreen,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(
              Icons.location_on_rounded,
              color:
                  visibleAddress.isEmpty ? AppColors.accent : AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              visibleAddress.isEmpty
                  ? CheckoutText.noSavedAddress
                  : visibleAddress,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color:
                    visibleAddress.isEmpty ? AppColors.accent : AppColors.text,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
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
    return _CheckoutSection(
      title: CheckoutText.deliveryDetails,
      child: Column(
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
      ),
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
    if (!RegExp(r'^[0-9]{10}$').hasMatch(trimmed)) {
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
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard();

  @override
  Widget build(BuildContext context) {
    return const _CheckoutSection(
      title: CheckoutText.payment,
      child: Row(
        children: [
          Icon(Icons.payments, color: AppColors.primary),
          SizedBox(width: 10),
          Text(CheckoutText.cashOnDelivery),
          Spacer(),
          Icon(Icons.check_circle, color: AppColors.primary),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
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

class _CheckoutSummary extends StatelessWidget {
  const _CheckoutSummary({
    required this.total,
    required this.savings,
    required this.isLoading,
    required this.onPlaceOrder,
  });

  final double total;
  final double savings;
  final bool isLoading;
  final VoidCallback onPlaceOrder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: CheckoutText.total,
            value: '\u20B9${_formatPrice(total)}',
            isBold: true,
          ),
          const SizedBox(height: 6),
          _SummaryRow(
            label: CheckoutText.savings,
            value: '\u20B9${_formatPrice(savings)}',
            valueColor: AppColors.primary,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
              onPressed: isLoading ? null : onPlaceOrder,
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(CheckoutText.placeOrder),
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

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    final weight = isBold ? FontWeight.bold : FontWeight.w600;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: weight)),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: weight,
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
  static const total = 'Total';
  static const savings = 'Total Savings';
  static const placeOrder = 'Place Order';
  static const placeOrderError = 'Unable to place order';
  static const requiredField = 'Required';
  static const invalidPhone = 'Enter a valid 10-digit phone number';
  static const invalidPincode = 'Enter a valid 6-digit pincode';
  static const unserviceablePincode = 'Delivery is not available here';
}

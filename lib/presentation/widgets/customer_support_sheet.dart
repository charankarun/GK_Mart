import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

Future<void> showCustomerSupportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
    ),
    builder: (_) => const _CustomerSupportSheet(),
  );
}

class _CustomerSupportSheet extends StatelessWidget {
  const _CustomerSupportSheet();

  static const _channel = MethodChannel('gk_mart/customer_support');

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: AppColors.softGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.support_agent_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        CustomerSupportText.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        CustomerSupportText.subtitle,
                        style: TextStyle(
                          color: AppColors.mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: const Row(
                children: [
                  Icon(Icons.phone_rounded, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      CustomerSupportText.phone,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _dialShopkeeper(context),
                icon: const Icon(Icons.call_rounded),
                label: const Text(CustomerSupportText.callNow),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _dialShopkeeper(BuildContext context) async {
    try {
      await _channel.invokeMethod<void>('dialPhone', {
        'phoneNumber': CustomerSupportText.phoneDialValue,
      });
    } on PlatformException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(CustomerSupportText.callError)),
      );
    }
  }
}

class CustomerSupportText {
  const CustomerSupportText._();

  static const title = 'Customer Support';
  static const subtitle = 'Call the shopkeeper for quick help.';
  static const phone = '+91 98765 43210';
  static const phoneDialValue = '+919876543210';
  static const callNow = 'Call Now';
  static const callError = 'Unable to open phone dialer';
}

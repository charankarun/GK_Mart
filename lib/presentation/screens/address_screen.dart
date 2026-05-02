import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_providers.dart';
import '../providers/repository_providers.dart';

class AddressScreen extends ConsumerStatefulWidget {
  const AddressScreen({super.key});

  @override
  ConsumerState<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends ConsumerState<AddressScreen> {
  final addressController = TextEditingController();
  bool isLoading = false;
  bool didSeedAddress = false;

  Future<void> saveAddress() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    setState(() => isLoading = true);

    await ref.read(userRepositoryProvider).updateAddress(
          uid: session.uid,
          address: addressController.text,
        );

    if (!mounted) return;

    setState(() => isLoading = false);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProfileProvider).maybeWhen(
          data: (user) => user,
          orElse: () => null,
        );

    if (!didSeedAddress && user?.address.isNotEmpty == true) {
      didSeedAddress = true;
      addressController.text = user!.address;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Address')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: addressController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter your full address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : saveAddress,
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Save Address'),
            ),
          ],
        ),
      ),
    );
  }
}

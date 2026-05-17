import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error_handler.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/app_user.dart';
import '../providers/auth_providers.dart';
import '../providers/repository_providers.dart';
import '../widgets/app_state_widgets.dart';

class AddressScreen extends ConsumerStatefulWidget {
  const AddressScreen({super.key});

  @override
  ConsumerState<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends ConsumerState<AddressScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _pincodeController = TextEditingController();

  bool _isFormVisible = false;
  bool _isSaving = false;
  int? _editingIndex;
  List<String>? _optimisticAddresses;

  @override
  void dispose() {
    _addressController.dispose();
    _landmarkController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(AddressText.title)),
        body: const Center(child: Text(AddressText.loginRequired)),
      );
    }

    final userAsync = ref.watch(currentUserProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text(AddressText.title)),
      body: userAsync.when(
        data: (user) {
          final savedAddresses = _normalizeAddresses(_visibleAddresses(user));

          if (_isFormVisible) {
            return _AddressFormView(
              formKey: _formKey,
              isSaving: _isSaving,
              isEditingExisting: _editingIndex != null,
              addressController: _addressController,
              landmarkController: _landmarkController,
              pincodeController: _pincodeController,
              onCancel: _closeForm,
              onSave: () => _saveAddress(user),
            );
          }

          return _AddressListView(
            savedAddresses: savedAddresses,
            onAddAddress: _openAddAddress,
            onEditAddress: _openEditAddress,
          );
        },
        loading: () => const AppLoadingState(),
        error: (error, _) => AppRetryState(
          icon: Icons.error_outline_rounded,
          title: AddressText.loadError,
          message: AppErrorHandler.messageFor(
            error,
            fallback: AddressText.loadErrorSubtitle,
          ),
          onRetry: () => ref.invalidate(currentUserProfileProvider),
        ),
      ),
    );
  }

  List<String> _visibleAddresses(AppUser? user) {
    final optimisticAddresses = _optimisticAddresses;
    if (optimisticAddresses != null) return optimisticAddresses;
    return user?.savedAddresses ?? const <String>[];
  }

  void _openAddAddress() {
    _addressController.clear();
    _landmarkController.clear();
    _pincodeController.clear();
    setState(() {
      _editingIndex = null;
      _isFormVisible = true;
    });
  }

  void _openEditAddress(int index, String savedAddress) {
    final parsed = ParsedAddress.from(savedAddress);
    _addressController.text = parsed.address;
    _landmarkController.text = parsed.landmark;
    _pincodeController.text = parsed.pincode;
    setState(() {
      _editingIndex = index;
      _isFormVisible = true;
    });
  }

  void _closeForm() {
    setState(() {
      _isFormVisible = false;
      _editingIndex = null;
    });
  }

  Future<void> _saveAddress(AppUser? currentUser) async {
    if (_isSaving) return;
    if (_formKey.currentState?.validate() != true) return;

    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    final nextAddress = _composeAddress();
    final nextAddresses = [..._visibleAddresses(currentUser)];
    final editingIndex = _editingIndex;

    if (editingIndex == null) {
      nextAddresses.add(nextAddress);
    } else if (editingIndex >= 0 && editingIndex < nextAddresses.length) {
      nextAddresses[editingIndex] = nextAddress;
    } else {
      nextAddresses.add(nextAddress);
    }

    final normalizedAddresses = _normalizeAddresses(nextAddresses);
    final primaryAddress =
        normalizedAddresses.isEmpty ? '' : normalizedAddresses.first;

    setState(() => _isSaving = true);

    try {
      await ref.read(userRepositoryProvider).upsertUser(
            AppUser(
              uid: session.uid,
              name: currentUser?.name ?? '',
              email: currentUser?.email ?? session.email ?? '',
              phone: currentUser?.phone ?? session.phoneNumber ?? '',
              address: primaryAddress,
              addresses: normalizedAddresses,
              photoUrl: currentUser?.photoUrl ?? '',
              createdAt: currentUser?.createdAt,
            ),
          );
      ref.invalidate(currentUserProfileProvider);

      if (!mounted) return;
      setState(() {
        _optimisticAddresses = normalizedAddresses;
        _isFormVisible = false;
        _isSaving = false;
        _editingIndex = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            editingIndex == null
                ? AddressText.addSuccess
                : AddressText.updateSuccess,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_saveErrorMessage(error))),
      );
    }
  }

  String _saveErrorMessage(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('permission-denied')) {
      return AddressText.permissionError;
    }
    if (message.contains('unavailable') || message.contains('network')) {
      return AddressText.networkError;
    }
    return AddressText.saveError;
  }

  String _composeAddress() {
    final address = _addressController.text.trim();
    final landmark = _landmarkController.text.trim();
    final pincode = _pincodeController.text.trim();

    return [
      address,
      if (landmark.isNotEmpty) '${AddressText.landmarkPrefix} $landmark',
      '${AddressText.pincodePrefix} $pincode',
    ].join('\n');
  }

  static List<String> _normalizeAddresses(List<String> addresses) {
    final normalized = <String>[];
    final seenAddresses = <String>{};

    for (final address in addresses) {
      final trimmed = address.trim();
      if (trimmed.isEmpty) continue;

      final key = trimmed.toLowerCase();
      if (seenAddresses.contains(key)) continue;

      normalized.add(trimmed);
      seenAddresses.add(key);
    }

    return normalized;
  }
}

class _AddressListView extends StatelessWidget {
  const _AddressListView({
    required this.savedAddresses,
    required this.onAddAddress,
    required this.onEditAddress,
  });

  final List<String> savedAddresses;
  final VoidCallback onAddAddress;
  final void Function(int index, String address) onEditAddress;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const _AddressHeader(),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Text(
                AddressText.savedAddresses,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onAddAddress,
              icon: const Icon(Icons.add_location_alt_rounded, size: 18),
              label: const Text(AddressText.addAddress),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (savedAddresses.isEmpty)
          const _EmptyAddressCard()
        else
          for (var index = 0; index < savedAddresses.length; index += 1) ...[
            _SavedAddressCard(
              address: savedAddresses[index],
              isDefault: index == 0,
              onEdit: () => onEditAddress(index, savedAddresses[index]),
            ),
            if (index != savedAddresses.length - 1) const SizedBox(height: 12),
          ],
        const SizedBox(height: 18),
        SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: onAddAddress,
            icon: const Icon(Icons.add_rounded),
            label: const Text(AddressText.addAddress),
          ),
        ),
      ],
    );
  }
}

class _AddressHeader extends StatelessWidget {
  const _AddressHeader();

  @override
  Widget build(BuildContext context) {
    return _CardSurface(
      child: const Row(
        children: [
          _AddressIcon(),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AddressText.manageAddress,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  AddressText.helper,
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
    );
  }
}

class _SavedAddressCard extends StatelessWidget {
  const _SavedAddressCard({
    required this.address,
    required this.isDefault,
    required this.onEdit,
  });

  final String address;
  final bool isDefault;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: isDefault
                  ? AppColors.primary.withValues(alpha: 0.34)
                  : AppColors.border,
            ),
            boxShadow: AppShadows.soft,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AddressIcon(isDefault: isDefault),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isDefault
                                ? AddressText.defaultAddress
                                : AddressText.savedAddress,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (isDefault) const _DefaultBadge(),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      address,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.mutedText,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(
                          Icons.edit_location_alt_rounded,
                          size: 18,
                        ),
                        label: const Text(AddressText.updateAddress),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.mutedText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        AddressText.defaultBadge,
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EmptyAddressCard extends StatelessWidget {
  const _EmptyAddressCard();

  @override
  Widget build(BuildContext context) {
    return _CardSurface(
      child: const Row(
        children: [
          Icon(Icons.location_off_rounded, color: AppColors.accent),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              AddressText.noSavedAddress,
              style: TextStyle(
                color: AppColors.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressFormView extends StatelessWidget {
  const _AddressFormView({
    required this.formKey,
    required this.isSaving,
    required this.isEditingExisting,
    required this.addressController,
    required this.landmarkController,
    required this.pincodeController,
    required this.onCancel,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final bool isSaving;
  final bool isEditingExisting;
  final TextEditingController addressController;
  final TextEditingController landmarkController;
  final TextEditingController pincodeController;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _AddressFormHeader(isEditingExisting: isEditingExisting),
          const SizedBox(height: 16),
          _AddressFormCard(
            addressController: addressController,
            landmarkController: landmarkController,
            pincodeController: pincodeController,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: isSaving ? null : onCancel,
                    child: const Text(AddressText.cancel),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: isSaving ? null : onSave,
                    icon: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_rounded),
                    label: Text(
                      isEditingExisting
                          ? AddressText.updateAddress
                          : AddressText.saveAddress,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddressFormHeader extends StatelessWidget {
  const _AddressFormHeader({required this.isEditingExisting});

  final bool isEditingExisting;

  @override
  Widget build(BuildContext context) {
    return _CardSurface(
      child: Row(
        children: [
          const _AddressIcon(),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              isEditingExisting
                  ? AddressText.editSavedAddress
                  : AddressText.addNewAddress,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressFormCard extends StatelessWidget {
  const _AddressFormCard({
    required this.addressController,
    required this.landmarkController,
    required this.pincodeController,
  });

  final TextEditingController addressController;
  final TextEditingController landmarkController;
  final TextEditingController pincodeController;

  @override
  Widget build(BuildContext context) {
    return _CardSurface(
      child: Column(
        children: [
          TextFormField(
            controller: addressController,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            validator: _addressValidator,
            decoration: const InputDecoration(
              labelText: AddressText.addressLabel,
              hintText: AddressText.addressHint,
              prefixIcon: Icon(Icons.home_work_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: landmarkController,
            textCapitalization: TextCapitalization.sentences,
            validator: _landmarkValidator,
            decoration: const InputDecoration(
              labelText: AddressText.landmarkLabel,
              hintText: AddressText.landmarkHint,
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: pincodeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            validator: _pincodeValidator,
            decoration: const InputDecoration(
              labelText: AddressText.pincodeLabel,
              hintText: AddressText.pincodeHint,
              prefixIcon: Icon(Icons.pin_drop_outlined),
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }

  String? _addressValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return AddressText.requiredField;
    if (trimmed.length < 10) return AddressText.shortAddress;
    return null;
  }

  String? _landmarkValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return AddressText.requiredField;
    if (trimmed.length < 3) return AddressText.shortLandmark;
    return null;
  }

  String? _pincodeValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return AddressText.requiredField;
    if (!RegExp(r'^[0-9]{6}$').hasMatch(trimmed)) {
      return AddressText.invalidPincode;
    }
    return null;
  }
}

class _AddressIcon extends StatelessWidget {
  const _AddressIcon({this.isDefault = true});

  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: isDefault ? AppColors.softGreen : AppColors.softOrange,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.location_on_rounded,
        color: isDefault ? AppColors.primary : AppColors.accent,
      ),
    );
  }
}

class _CardSurface extends StatelessWidget {
  const _CardSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: child,
    );
  }
}

class ParsedAddress {
  const ParsedAddress({
    required this.address,
    required this.landmark,
    required this.pincode,
  });

  final String address;
  final String landmark;
  final String pincode;

  factory ParsedAddress.from(String savedAddress) {
    final lines = savedAddress
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    var landmark = '';
    var pincode = '';
    final addressLines = <String>[];

    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.startsWith(AddressText.landmarkPrefix.toLowerCase())) {
        landmark = line.substring(AddressText.landmarkPrefix.length).trim();
      } else if (lower.startsWith(AddressText.pincodePrefix.toLowerCase())) {
        pincode = line.substring(AddressText.pincodePrefix.length).trim();
      } else {
        addressLines.add(line);
      }
    }

    if (pincode.isEmpty) {
      final match = RegExp(r'\b[0-9]{6}\b').firstMatch(savedAddress);
      pincode = match?.group(0) ?? '';
    }

    return ParsedAddress(
      address:
          addressLines.isEmpty ? savedAddress.trim() : addressLines.join('\n'),
      landmark: landmark,
      pincode: pincode,
    );
  }
}

class AddressText {
  const AddressText._();

  static const title = 'My Addresses';
  static const loginRequired = 'Please login to manage your addresses';
  static const loadError = 'Unable to load saved addresses';
  static const loadErrorSubtitle = 'Please try again in a moment.';
  static const manageAddress = 'Manage delivery addresses';
  static const helper =
      'Tap an address to update it. The first one is default.';
  static const savedAddresses = 'Saved Addresses';
  static const savedAddress = 'Saved Address';
  static const defaultAddress = 'Default Address';
  static const defaultBadge = 'Default';
  static const noSavedAddress = 'No saved address yet';
  static const addAddress = 'Add Address';
  static const addNewAddress = 'Add new address';
  static const editAddress = 'Edit address';
  static const editSavedAddress = 'Update address';
  static const addressLabel = 'Complete address';
  static const addressHint = 'House no, building, street, area';
  static const landmarkLabel = 'Landmark';
  static const landmarkHint = 'Nearby shop, building, or street';
  static const pincodeLabel = 'Pincode';
  static const pincodeHint = '6-digit pincode';
  static const saveAddress = 'Save Address';
  static const updateAddress = 'Update Address';
  static const cancel = 'Cancel';
  static const addSuccess = 'Address added';
  static const updateSuccess = 'Address updated';
  static const saveError = 'Unable to save address';
  static const permissionError =
      'Address save is not allowed. Check Firestore rules.';
  static const networkError = 'Network issue while saving address. Try again.';
  static const requiredField = 'Required';
  static const shortAddress = 'Enter a more complete address';
  static const shortLandmark = 'Enter a clear landmark';
  static const invalidPincode = 'Enter a valid 6-digit pincode';
  static const landmarkPrefix = 'Landmark:';
  static const pincodePrefix = 'Pincode:';
}

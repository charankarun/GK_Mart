import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_error_handler.dart';
import '../../core/firebase/firebase_providers.dart';
import '../../core/images/image_upload_processor.dart';
import '../../core/storage/storage_image_uploader.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone_number_normalizer.dart';
import '../../domain/entities/app_user.dart';
import '../providers/auth_providers.dart';
import '../providers/repository_providers.dart';
import '../widgets/app_cached_network_image.dart';
import '../widgets/app_state_widgets.dart';
import 'address_screen.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _didSeedProfile = false;
  bool _isSaving = false;
  bool _isPickingImage = false;
  Uint8List? _imageBytes;
  String? _imageFileName;
  String _imageContentType = EditProfileConfig.defaultImageContentType;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _pincodeController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(EditProfileText.title)),
        body: const Center(child: Text(EditProfileText.loginRequired)),
      );
    }

    final userAsync = ref.watch(currentUserProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text(EditProfileText.title)),
      body: userAsync.when(
        data: (user) {
          _seedProfileIfNeeded(
            user: user,
            fallbackPhone: session.phoneNumber ?? '',
          );

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _ProfilePhotoPicker(
                  imageBytes: _imageBytes,
                  imageUrl: user?.photoUrl ?? '',
                  isPickingImage: _isPickingImage,
                  onPickImage: _pickImage,
                ),
                const SizedBox(height: 16),
                _ProfileFormCard(
                  nameController: _nameController,
                  phoneController: _phoneController,
                  addressController: _addressController,
                  pincodeController: _pincodeController,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : () => _saveProfile(user),
                    icon: _isSaving
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
                      _isSaving ? EditProfileText.saving : EditProfileText.save,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const AppLoadingState(),
        error: (error, _) => AppRetryState(
          icon: Icons.error_outline_rounded,
          title: EditProfileText.loadError,
          message: AppErrorHandler.messageFor(
            error,
            fallback: EditProfileText.loadErrorSubtitle,
          ),
          onRetry: () => ref.invalidate(currentUserProfileProvider),
        ),
      ),
    );
  }

  void _seedProfileIfNeeded({
    required AppUser? user,
    required String fallbackPhone,
  }) {
    if (_didSeedProfile) return;

    _didSeedProfile = true;
    _nameController.text = user?.name ?? '';
    _phoneController.text =
        user?.phone.trim().isNotEmpty == true ? user!.phone : fallbackPhone;

    final parsed = ParsedAddress.from(user?.address ?? '');
    _addressController.text = parsed.address;
    _pincodeController.text = parsed.pincode;
  }

  Future<void> _pickImage() async {
    setState(() => _isPickingImage = true);

    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: EditProfileConfig.imageQuality,
        maxWidth: EditProfileConfig.maxImageDimension,
        maxHeight: EditProfileConfig.maxImageDimension,
      );
      if (image == null) return;

      final processed = await ImageUploadProcessor.process(
        bytes: await image.readAsBytes(),
        fileName: image.name,
        contentType: image.mimeType ?? _contentTypeFor(image.name),
        maxDimension: EditProfileConfig.maxImageDimension,
        maxSourceBytes: EditProfileConfig.maxSourceImageBytes,
        maxUploadBytes: EditProfileConfig.maxUploadImageBytes,
        quality: EditProfileConfig.imageQuality,
      );

      if (!mounted) return;
      setState(() {
        _imageBytes = processed.bytes;
        _imageFileName = processed.fileName;
        _imageContentType = processed.contentType;
      });
    } on ImageValidationException catch (error) {
      if (!mounted) return;
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: EditProfileText.imagePickError,
      );
    } catch (error) {
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: EditProfileText.imagePickError,
      );
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _saveProfile(AppUser? currentUser) async {
    if (_isSaving) return;
    if (_formKey.currentState?.validate() != true) return;

    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    setState(() => _isSaving = true);

    try {
      final photoUrl = await _resolvePhotoUrl(
        uid: session.uid,
        existingPhotoUrl: currentUser?.photoUrl ?? '',
      );
      final phone = PhoneNumberNormalizer.toIndianLocalNumber(
        _phoneController.text,
      );

      final existingAddress = currentUser?.address ?? '';
      final parsed = ParsedAddress.from(existingAddress);

      final nextAddress = [
        _addressController.text.trim(),
        if (parsed.landmark.isNotEmpty) '${AddressText.landmarkPrefix} ${parsed.landmark}',
        if (_pincodeController.text.trim().isNotEmpty) '${AddressText.pincodePrefix} ${_pincodeController.text.trim()}',
      ].join('\n');

      final nextAddresses = [...(currentUser?.addresses ?? const <String>[])];
      if (nextAddresses.isNotEmpty) {
        nextAddresses[0] = nextAddress;
      } else if (nextAddress.trim().isNotEmpty) {
        nextAddresses.add(nextAddress);
      }

      await ref.read(userRepositoryProvider).upsertUser(
            AppUser(
              uid: session.uid,
              name: _nameController.text.trim(),
              email: currentUser?.email ?? '',
              phone: phone,
              address: nextAddress,
              addresses: nextAddresses,
              photoUrl: photoUrl,
              createdAt: currentUser?.createdAt,
            ),
          );
      ref.invalidate(currentUserProfileProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(EditProfileText.saveSuccess)),
      );
      Navigator.pop(context);
    } catch (error) {
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: EditProfileText.saveError,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<String> _resolvePhotoUrl({
    required String uid,
    required String existingPhotoUrl,
  }) async {
    final bytes = _imageBytes;
    if (bytes == null) return existingPhotoUrl.trim();

    final safeFileName = _safeFileName(_imageFileName);
    final storage = ref.read(firebaseStorageProvider);
    final storageRef = storage.ref().child(
          '${FirebaseStoragePaths.profileImages}/'
          '${uid}_${DateTime.now().millisecondsSinceEpoch}_$safeFileName',
        );
    return StorageImageUploader.uploadBytesWithRetry(
      ref: storageRef,
      bytes: bytes,
      metadata: SettableMetadata(
        contentType: _imageContentType,
        cacheControl: EditProfileConfig.imageCacheControl,
      ),
      uploadTimeout: AppDurations.uploadTimeout,
      downloadUrlTimeout: AppDurations.networkTimeout,
      logName: 'ProfileImageUpload',
    );
  }

  static String _safeFileName(String? fileName) {
    final normalized = (fileName ?? EditProfileConfig.imageFileName)
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (normalized.isEmpty) return EditProfileConfig.imageFileName;
    return normalized;
  }

  static String _contentTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return EditProfileConfig.defaultImageContentType;
  }
}

class _ProfilePhotoPicker extends StatelessWidget {
  const _ProfilePhotoPicker({
    required this.imageBytes,
    required this.imageUrl,
    required this.isPickingImage,
    required this.onPickImage,
  });

  final Uint8List? imageBytes;
  final String imageUrl;
  final bool isPickingImage;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    return _CardSurface(
      child: Row(
        children: [
          _ProfileAvatar(imageBytes: imageBytes, imageUrl: imageUrl),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  EditProfileText.profilePicture,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  EditProfileText.profilePictureHelp,
                  style: TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: isPickingImage ? null : onPickImage,
                  icon: isPickingImage
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_camera_outlined),
                  label: Text(
                    imageBytes == null && imageUrl.trim().isEmpty
                        ? EditProfileText.pickPhoto
                        : EditProfileText.changePhoto,
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

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.imageBytes,
    required this.imageUrl,
  });

  final Uint8List? imageBytes;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes;
    final trimmedUrl = imageUrl.trim();

    return ClipOval(
      child: SizedBox(
        width: 78,
        height: 78,
        child: bytes != null
            ? Image.memory(
                bytes,
                cacheWidth: EditProfileConfig.avatarImageCacheExtent,
                cacheHeight: EditProfileConfig.avatarImageCacheExtent,
                fit: BoxFit.cover,
              )
            : trimmedUrl.isNotEmpty
                ? AppCachedNetworkImage(
                    imageUrl: trimmedUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: EditProfileConfig.avatarImageCacheExtent,
                    memCacheHeight: EditProfileConfig.avatarImageCacheExtent,
                    maxWidthDiskCache:
                        EditProfileConfig.avatarImageDiskCacheExtent,
                    maxHeightDiskCache:
                        EditProfileConfig.avatarImageDiskCacheExtent,
                    placeholder: const _AvatarFallback(),
                    errorPlaceholder: const _AvatarFallback(),
                  )
                : const _AvatarFallback(),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: AppColors.softGreen),
      child: Icon(
        Icons.person_rounded,
        color: AppColors.primary,
        size: 38,
      ),
    );
  }
}

class _ProfileFormCard extends StatelessWidget {
  const _ProfileFormCard({
    required this.nameController,
    required this.phoneController,
    required this.addressController,
    required this.pincodeController,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final TextEditingController pincodeController;

  @override
  Widget build(BuildContext context) {
    return _CardSurface(
      child: Column(
        children: [
          TextFormField(
            controller: nameController,
            textCapitalization: TextCapitalization.words,
            validator: _nameValidator,
            decoration: const InputDecoration(
              labelText: EditProfileText.name,
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            validator: _phoneValidator,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
            ],
            decoration: const InputDecoration(
              labelText: EditProfileText.phone,
              helperText: EditProfileText.phoneHelp,
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: addressController,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Address',
              prefixIcon: Icon(Icons.home_work_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: pincodeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            validator: _pincodeValidator,
            decoration: const InputDecoration(
              labelText: 'Pincode',
              prefixIcon: Icon(Icons.pin_drop_outlined),
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }

  String? _nameValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return EditProfileText.requiredField;
    return null;
  }

  String? _phoneValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    return PhoneNumberNormalizer.isIndianMobileNumber(trimmed)
        ? null
        : EditProfileText.invalidPhone;
  }

  String? _pincodeValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (!RegExp(r'^[0-9]{6}$').hasMatch(trimmed)) {
      return 'Enter a valid 6-digit pincode';
    }
    return null;
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

class EditProfileConfig {
  const EditProfileConfig._();

  static const imageQuality = 82;
  static const maxImageDimension = 800.0;
  static const maxSourceImageBytes = 5 * 1024 * 1024;
  static const maxUploadImageBytes = 1024 * 1024;
  static const avatarImageCacheExtent = 180;
  static const avatarImageDiskCacheExtent = 240;
  static const imageFileName = 'profile_photo.jpg';
  static const defaultImageContentType = 'image/jpeg';
  static const imageCacheControl = 'public,max-age=31536000,immutable';
}

class EditProfileText {
  const EditProfileText._();

  static const title = 'Edit Profile';
  static const loginRequired = 'Please login to edit profile';
  static const loadError = 'Unable to load profile';
  static const loadErrorSubtitle = 'Please try again in a moment.';
  static const profilePicture = 'Profile picture';
  static const profilePictureHelp = 'Shown on your account page.';
  static const pickPhoto = 'Pick Photo';
  static const changePhoto = 'Change Photo';
  static const imagePickError = 'Unable to pick profile picture';
  static const emptyImage = 'Selected image is empty';
  static const name = 'Name';
  static const email = 'Email';
  static const phone = 'Phone';
  static const phoneHelp = 'Use a 10-digit mobile number or +91 format.';
  static const requiredField = 'Required';
  static const invalidEmail = 'Enter a valid email';
  static const invalidPhone = 'Enter a valid 10-digit mobile number';
  static const save = 'Save Profile';
  static const saving = 'Saving...';
  static const saveSuccess = 'Profile updated';
  static const saveError = 'Unable to update profile';
}

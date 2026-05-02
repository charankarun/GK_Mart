import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase/firebase_providers.dart';
import '../../data/repositories/category_repository_impl.dart';
import '../../data/repositories/firebase_auth_repository.dart';
import '../../data/repositories/firebase_phone_auth_repository.dart';
import '../../data/repositories/firestore_admin_repository.dart';
import '../../data/repositories/firestore_cart_repository.dart';
import '../../data/repositories/firestore_order_repository.dart';
import '../../data/repositories/firestore_search_repository.dart';
import '../../data/repositories/firestore_user_repository.dart';
import '../../data/repositories/firestore_wishlist_repository.dart';
import '../../data/repositories/product_repository_impl.dart';
import '../../domain/repositories/admin_repository.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/cart_repository.dart';
import '../../domain/repositories/category_repository.dart';
import '../../domain/repositories/order_repository.dart';
import '../../domain/repositories/phone_auth_repository.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/search_repository.dart';
import '../../domain/repositories/user_repository.dart';
import '../../domain/repositories/wishlist_repository.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return FirestoreUserRepository(ref.watch(firestoreProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(
    auth: ref.watch(firebaseAuthProvider),
    userRepository: ref.watch(userRepositoryProvider),
  );
});

final phoneAuthRepositoryProvider = Provider<PhoneAuthRepository>((ref) {
  return FirebasePhoneAuthRepository(
    auth: ref.watch(firebaseAuthProvider),
    userRepository: ref.watch(userRepositoryProvider),
  );
});

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return FirestoreAdminRepository(ref.watch(firestoreProvider));
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepositoryImpl(
    firestore: ref.watch(firestoreProvider),
    storage: ref.watch(firebaseStorageProvider),
  );
});

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepositoryImpl(ref.watch(firestoreProvider));
});

final cartRepositoryProvider = Provider<CartRepository>((ref) {
  return FirestoreCartRepository(ref.watch(firestoreProvider));
});

final wishlistRepositoryProvider = Provider<WishlistRepository>((ref) {
  return FirestoreWishlistRepository(ref.watch(firestoreProvider));
});

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return FirestoreSearchRepository(ref.watch(firestoreProvider));
});

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return FirestoreOrderRepository(ref.watch(firestoreProvider));
});

import 'package:flutter/material.dart';

class AppDurations {
  const AppDurations._();

  static const startupTimeout = Duration(seconds: 12);
  static const dashboardTimeout = Duration(seconds: 8);
  static const networkTimeout = Duration(seconds: 15);
  static const uploadTimeout = Duration(seconds: 45);
  static const splashMinimumDuration = Duration(milliseconds: 1200);
}

class AppPadding {
  const AppPadding._();

  static const screen = EdgeInsets.all(16);
  static const screenHorizontal = EdgeInsets.symmetric(horizontal: 16);
  static const card = EdgeInsets.all(14);
}

class AppAssets {
  const AppAssets._();

  static const logo = 'assets/gk_mart_logo.png';
}

class FirestoreCollections {
  const FirestoreCollections._();

  static const adminConfig = 'admin_config';
  static const carts = 'carts';
  static const cartItems = 'items';
  static const categories = 'categories';
  static const orders = 'orders';
  static const products = 'products';
  static const users = 'users';
  static const wishlist = 'wishlist';
}

class FirestoreSubcollections {
  const FirestoreSubcollections._();

  static const fcmTokens = 'fcmTokens';
}

class FirestoreDocuments {
  const FirestoreDocuments._();

  static const admins = 'admins';
}

class FirestoreFields {
  const FirestoreFields._();

  static const productIds = 'productIds';
}

class FirebaseStoragePaths {
  const FirebaseStoragePaths._();

  static const categoryImages = 'category_images';
  static const productImages = 'product_images';
  static const profileImages = 'profile_images';
}

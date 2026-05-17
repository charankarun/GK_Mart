import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/repository_exception.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/category_image_upload.dart';
import '../../domain/entities/category_page.dart';
import '../../domain/repositories/category_repository.dart';
import '../models/category_model.dart';

class CategoryRepositoryImpl implements CategoryRepository {
  CategoryRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
  })  : _firestore = firestore,
        _storage = storage;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  static const _collectionPath = FirestoreCollections.categories;
  static const _storagePath = FirebaseStoragePaths.categoryImages;
  static const _defaultWatchLimit = 50;
  static const _maxPageLimit = 60;
  static const _maxUploadBytes = 1024 * 1024;
  static const _imageCacheControl = 'public,max-age=31536000,immutable';
  static const _allowedImageContentTypes = {
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
  };
  static final Map<String, Category> _categoryCache = <String, Category>{};

  CollectionReference<Map<String, dynamic>> get _categories {
    return _firestore.collection(_collectionPath);
  }

  @override
  Stream<List<Category>> watchCategories({int limit = _defaultWatchLimit}) {
    final safeLimit = _safeLimit(limit);
    if (safeLimit <= 0) return Stream.value(const <Category>[]);

    return RepositoryGuard.watch(
      message: 'Unable to load categories.',
      create: () async* {
        final cachedCategories = _cachedCategories(limit: safeLimit);
        if (cachedCategories.isNotEmpty) yield cachedCategories;

        yield* _categories
            .orderBy(CategoryField.name)
            .limit(safeLimit)
            .snapshots()
            .map((snapshot) {
          final categories =
              snapshot.docs.map(CategoryModel.fromFirestore).toList();
          _cacheCategories(categories);
          return categories;
        });
      },
    );
  }

  @override
  Future<CategoryPage> fetchCategoriesPage({
    required int limit,
    CategoryPageCursor? cursor,
  }) {
    return RepositoryGuard.run(
      message: 'Unable to load categories.',
      action: () async {
        final safeLimit = _safeLimit(limit);
        if (safeLimit <= 0) {
          return const CategoryPage(categories: <Category>[], hasMore: false);
        }

        Query<Map<String, dynamic>> query =
            _categories.orderBy(CategoryField.name).limit(safeLimit);

        if (cursor != null) {
          final cursorDoc = await _categories.doc(cursor.id).get().timeout(
                AppDurations.networkTimeout,
              );
          query = cursorDoc.exists
              ? query.startAfterDocument(cursorDoc)
              : query.startAfter([cursor.name]);
        }

        final snapshot = await query.get().timeout(AppDurations.networkTimeout);
        final categories =
            snapshot.docs.map(CategoryModel.fromFirestore).toList();
        _cacheCategories(categories);

        CategoryPageCursor? nextCursor;
        if (categories.isNotEmpty) {
          final lastCategory = categories.last;
          nextCursor = CategoryPageCursor(
            id: lastCategory.id,
            name: lastCategory.name,
          );
        }

        return CategoryPage(
          categories: categories,
          nextCursor: nextCursor,
          hasMore: snapshot.docs.length == safeLimit,
        );
      },
    );
  }

  @override
  Future<void> addCategory(Category category) {
    return RepositoryGuard.run(
      message: 'Unable to add category.',
      action: () {
        final model = CategoryModel.fromEntity(category);
        return _categories
            .add(model.toFirestore(includeCreatedAt: true))
            .timeout(AppDurations.networkTimeout);
      },
    );
  }

  @override
  Future<void> updateCategory(Category category) {
    final categoryId = category.id.trim();
    if (categoryId.isEmpty) {
      throw ArgumentError.value(category.id, 'category.id', 'Required');
    }

    return RepositoryGuard.run(
      message: 'Unable to update category.',
      action: () {
        final model = CategoryModel.fromEntity(category);
        return _categories
            .doc(categoryId)
            .set(
              model.toFirestore(includeCreatedAt: false),
              SetOptions(merge: true),
            )
            .timeout(AppDurations.networkTimeout);
      },
    );
  }

  @override
  Future<void> deleteCategory(String categoryId) {
    final normalizedCategoryId = categoryId.trim();
    if (normalizedCategoryId.isEmpty) {
      throw ArgumentError.value(categoryId, 'categoryId', 'Required');
    }

    return RepositoryGuard.run(
      message: 'Unable to delete category.',
      action: () {
        return _categories.doc(normalizedCategoryId).delete().timeout(
              AppDurations.networkTimeout,
            );
      },
    );
  }

  @override
  Future<String> uploadCategoryImage(CategoryImageUpload upload) async {
    if (upload.bytes.isEmpty) {
      throw ArgumentError.value(upload.bytes, 'upload.bytes', 'Required');
    }
    if (upload.bytes.lengthInBytes > _maxUploadBytes) {
      throw ArgumentError.value(
        upload.bytes.lengthInBytes,
        'upload.bytes.lengthInBytes',
        'Category image is too large',
      );
    }
    if (!_isAllowedImageContentType(upload.contentType)) {
      throw ArgumentError.value(
        upload.contentType,
        'upload.contentType',
        'Unsupported image type',
      );
    }

    return RepositoryGuard.run(
      message: 'Unable to upload category image.',
      action: () async {
        final fileName = _safeFileName(upload.fileName);
        final ref = _storage.ref().child(
              '$_storagePath/${DateTime.now().millisecondsSinceEpoch}_$fileName',
            );
        final task = await ref
            .putData(
              upload.bytes,
              SettableMetadata(
                contentType: upload.contentType,
                cacheControl: _imageCacheControl,
              ),
            )
            .timeout(AppDurations.uploadTimeout);

        return task.ref.getDownloadURL().timeout(AppDurations.networkTimeout);
      },
    );
  }

  static int _safeLimit(int limit) {
    if (limit <= 0) return 0;
    return limit > _maxPageLimit ? _maxPageLimit : limit;
  }

  static List<Category> _cachedCategories({required int limit}) {
    final categories = _categoryCache.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return categories.take(limit).toList();
  }

  static void _cacheCategories(Iterable<Category> categories) {
    for (final category in categories) {
      if (category.id.trim().isEmpty) continue;
      _categoryCache[category.id] = category;
    }
  }

  static String _safeFileName(String fileName) {
    final normalizedFileName = fileName.trim().replaceAll(
          RegExp(r'[^a-zA-Z0-9._-]+'),
          '_',
        );

    if (normalizedFileName.isEmpty) return 'category_image.jpg';
    return normalizedFileName;
  }

  static bool _isAllowedImageContentType(String contentType) {
    return _allowedImageContentTypes.contains(contentType.trim().toLowerCase());
  }
}

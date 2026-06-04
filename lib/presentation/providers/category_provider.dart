import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/entities/category.dart';
import '../../domain/entities/category_image_upload.dart';
import '../../domain/entities/category_page.dart';
import 'repository_providers.dart';

final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchCategories();
});

final categoriesProvider = categoriesStreamProvider;

final adminCategoryListProvider = StateNotifierProvider.autoDispose<
    AdminCategoryListController, AsyncValue<CategoryListState>>((ref) {
  return AdminCategoryListController(ref)..loadInitial();
});

final adminCategoryControllerProvider =
    StateNotifierProvider<AdminCategoryController, AsyncValue<void>>((ref) {
  return AdminCategoryController(ref);
});

final addCategoryProvider = Provider<Future<void> Function(Category)>((ref) {
  return (category) {
    return ref.read(categoryRepositoryProvider).addCategory(category);
  };
});

final updateCategoryProvider = Provider<Future<void> Function(Category)>((ref) {
  return (category) {
    return ref.read(categoryRepositoryProvider).updateCategory(category);
  };
});

final deleteCategoryProvider = Provider<Future<void> Function(String)>((ref) {
  return (categoryId) {
    return ref.read(categoryRepositoryProvider).deleteCategory(categoryId);
  };
});

class AdminCategoryController extends StateNotifier<AsyncValue<void>> {
  AdminCategoryController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  Future<void> saveCategory(AdminCategoryInput input) async {
    if (state.isLoading) return;

    state = const AsyncLoading();

    try {
      final imageUrl = await _resolveImageUrl(input);
      final category = Category(
        id: input.categoryId ?? '',
        name: input.name,
        imageUrl: imageUrl,
      );

      final repository = _ref.read(categoryRepositoryProvider);
      if (input.isEditing) {
        await repository.updateCategory(category);
      } else {
        await repository.addCategory(category);
      }

      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> deleteCategory(String categoryId) async {
    if (state.isLoading) return;

    state = const AsyncLoading();

    try {
      await _ref.read(categoryRepositoryProvider).deleteCategory(categoryId);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<String> _resolveImageUrl(AdminCategoryInput input) async {
    final imageBytes = input.imageBytes;
    if (imageBytes == null) {
      final existingImageUrl = input.existingImageUrl.trim();
      if (existingImageUrl.isEmpty) {
        throw ArgumentError('Category image is required');
      }
      return existingImageUrl;
    }

    return _ref.read(categoryRepositoryProvider).uploadCategoryImage(
          CategoryImageUpload(
            bytes: imageBytes,
            fileName:
                input.imageFileName ?? CategoryProviderConfig.imageFileName,
            contentType: input.imageContentType,
          ),
        );
  }
}

class AdminCategoryListController
    extends StateNotifier<AsyncValue<CategoryListState>> {
  AdminCategoryListController(this._ref) : super(const AsyncLoading());

  final Ref _ref;

  Future<void> loadInitial() async {
    state = const AsyncLoading();

    try {
      final page =
          await _ref.read(categoryRepositoryProvider).fetchCategoriesPage(
                limit: CategoryProviderConfig.pageSize,
              );
      if (!mounted) return;
      state = AsyncData(CategoryListState.fromPage(page));
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> loadNext() async {
    final currentState = _currentState;
    if (currentState == null ||
        currentState.isLoadingMore ||
        !currentState.hasMore) {
      return;
    }

    state = AsyncData(currentState.copyWith(isLoadingMore: true));

    try {
      final page =
          await _ref.read(categoryRepositoryProvider).fetchCategoriesPage(
                limit: CategoryProviderConfig.pageSize,
                cursor: currentState.nextCursor,
              );
      if (!mounted) return;
      state = AsyncData(currentState.appendPage(page));
    } catch (_) {
      if (!mounted) return;
      state = AsyncData(currentState.copyWith(isLoadingMore: false));
      rethrow;
    }
  }

  CategoryListState? get _currentState {
    return state.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
  }
}

class CategoryListState {
  const CategoryListState({
    required this.categories,
    required this.hasMore,
    this.nextCursor,
    this.isLoadingMore = false,
  });

  final List<Category> categories;
  final CategoryPageCursor? nextCursor;
  final bool hasMore;
  final bool isLoadingMore;

  factory CategoryListState.fromPage(CategoryPage page) {
    return CategoryListState(
      categories: page.categories,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  CategoryListState copyWith({
    List<Category>? categories,
    CategoryPageCursor? nextCursor,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return CategoryListState(
      categories: categories ?? this.categories,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  CategoryListState appendPage(CategoryPage page) {
    return CategoryListState(
      categories: [...categories, ...page.categories],
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }
}

class AdminCategoryInput {
  const AdminCategoryInput({
    required this.name,
    required this.existingImageUrl,
    this.categoryId,
    this.imageBytes,
    this.imageFileName,
    this.imageContentType = CategoryProviderConfig.defaultImageContentType,
  });

  final String? categoryId;
  final String name;
  final String existingImageUrl;
  final Uint8List? imageBytes;
  final String? imageFileName;
  final String imageContentType;

  bool get isEditing => categoryId != null && categoryId!.trim().isNotEmpty;
}

class CategoryProviderConfig {
  const CategoryProviderConfig._();

  static const pageSize = 20;
  static const imageFileName = 'category_image.jpg';
  static const defaultImageContentType = 'image/jpeg';
}

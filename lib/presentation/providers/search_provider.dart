import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import 'repository_providers.dart';

final productSearchQueryProvider = StateProvider.autoDispose<String>((ref) {
  return '';
});

final debouncedSearchQueryProvider = FutureProvider.autoDispose<String>((ref) {
  final query = ref.watch(productSearchQueryProvider).trim();
  if (query.isEmpty) return Future.value('');

  final completer = Completer<String>();
  final timer = Timer(SearchConfig.debounceDuration, () {
    if (!completer.isCompleted) completer.complete(query);
  });

  ref.onDispose(() {
    timer.cancel();
    if (!completer.isCompleted) completer.complete('');
  });

  return completer.future;
});

final productSearchSuggestionsProvider =
    StreamProvider.autoDispose<List<Product>>((ref) async* {
  final query = ref.watch(productSearchQueryProvider).trim();
  if (query.isEmpty) {
    yield const <Product>[];
    return;
  }

  final repository = ref.watch(searchRepositoryProvider);
  var disposed = false;
  final completer = Completer<void>();
  final timer = Timer(SearchConfig.debounceDuration, () {
    if (!completer.isCompleted) completer.complete();
  });

  ref.onDispose(() {
    disposed = true;
    timer.cancel();
    if (!completer.isCompleted) completer.complete();
  });

  await completer.future;
  if (disposed) return;

  yield* repository.watchProductSuggestions(
    query: query,
    limit: SearchConfig.maxSuggestions,
  );
});

final categorySearchSuggestionsProvider =
    FutureProvider.autoDispose.family<List<Category>, String>((ref, query) {
  final normalizedQuery = query.trim();
  if (normalizedQuery.isEmpty) return Future.value(const <Category>[]);

  return ref.watch(searchRepositoryProvider).fetchCategorySuggestions(
        query: normalizedQuery,
        limit: SearchConfig.maxCategorySuggestions,
      );
});

class SearchConfig {
  const SearchConfig._();

  static const debounceDuration = Duration(milliseconds: 300);
  static const maxSuggestions = 20;
  static const maxCategorySuggestions = 6;
  static const loadMoreExtent = 420.0;
}

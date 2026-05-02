import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/entities/product.dart';
import 'repository_providers.dart';

final productSearchQueryProvider = StateProvider.autoDispose<String>((ref) {
  return '';
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

class SearchConfig {
  const SearchConfig._();

  static const debounceDuration = Duration(milliseconds: 300);
  static const maxSuggestions = 8;
}

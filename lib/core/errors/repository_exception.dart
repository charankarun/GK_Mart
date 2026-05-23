import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

class RepositoryException implements Exception {
  const RepositoryException(
    this.message, {
    this.code,
    this.cause,
  });

  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() => message;
}

class RepositoryGuard {
  const RepositoryGuard._();

  static Future<T> run<T>({
    required String message,
    required Future<T> Function() action,
  }) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_map(error, message), stackTrace);
    }
  }

  static Stream<T> watch<T>({
    required String message,
    required Stream<T> Function() create,
  }) async* {
    try {
      yield* create();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_map(error, message), stackTrace);
    }
  }

  static RepositoryException _map(Object error, String fallbackMessage) {
    if (error is RepositoryException) return error;

    if (error is TimeoutException) {
      return RepositoryException(
        'The request timed out. Please check your connection and try again.',
        code: 'timeout',
        cause: error,
      );
    }

    if (error is FirebaseException) {
      return RepositoryException(
        _firebaseMessage(error) ?? fallbackMessage,
        code: error.code,
        cause: error,
      );
    }

    return RepositoryException(fallbackMessage, cause: error);
  }

  static String? _firebaseMessage(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return null;
      case 'unavailable':
      case 'network-request-failed':
        return 'Network issue. Please check your connection and try again.';
      case 'deadline-exceeded':
        return 'The request timed out. Please try again.';
      case 'failed-precondition':
        return 'Required Firestore index or precondition is missing.';
      case 'resource-exhausted':
        return 'Service is busy right now. Please try again shortly.';
      case 'unauthenticated':
        return 'Please login and try again.';
    }

    return null;
  }
}

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'repository_exception.dart';

class AppErrorHandler {
  AppErrorHandler._();

  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  static void initialize() {
    FlutterError.onError = (details) {
      if (kDebugMode) FlutterError.presentError(details);
      showGlobalError(details.exception);
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      report(error, stackTrace);
      return true;
    };
  }

  static void report(Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      FlutterError.presentError(
        FlutterErrorDetails(exception: error, stack: stackTrace),
      );
    }
    showGlobalError(error);
  }

  static void showGlobalError(Object? error, {String? fallbackMessage}) {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    if (isPermissionDenied(error)) {
      messenger.clearSnackBars();
      return;
    }

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(messageFor(error, fallback: fallbackMessage))),
      );
  }

  static void showErrorSnackBar(
    BuildContext context,
    Object? error, {
    String? fallbackMessage,
  }) {
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (isPermissionDenied(error)) {
      messenger.clearSnackBars();
      return;
    }

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(messageFor(error, fallback: fallbackMessage))),
      );
  }

  static bool isPermissionDenied(Object? error) {
    if (error is RepositoryException) {
      return error.code == 'permission-denied' ||
          isPermissionDenied(error.cause);
    }

    if (error is FirebaseException) {
      return error.code == 'permission-denied';
    }

    final message = error?.toString().toLowerCase() ?? '';
    return message.contains('permission-denied') ||
        message.contains('missing or insufficient permissions') ||
        message.contains("don't have permission") ||
        message.contains('do not have permission') ||
        message.contains('permission to perform this action');
  }

  static String messageFor(Object? error, {String? fallback}) {
    if (isPermissionDenied(error)) {
      return fallback ?? 'Unable to complete this action right now.';
    }

    if (error is RepositoryException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'The request timed out. Please check your connection and try again.';
    }

    if (error is FirebaseException) {
      return _firebaseMessage(error) ?? fallback ?? 'Something went wrong.';
    }

    final message = error?.toString().toLowerCase() ?? '';
    if (message.contains('timeout')) {
      return 'The request timed out. Please try again.';
    }
    if (message.contains('network') ||
        message.contains('unavailable') ||
        message.contains('socket') ||
        message.contains('host lookup')) {
      return 'Network issue. Please check your connection and try again.';
    }

    return fallback ?? 'Something went wrong. Please try again.';
  }

  static String? _firebaseMessage(FirebaseException error) {
    switch (error.code) {
      case 'network-request-failed':
      case 'unavailable':
        return 'Network issue. Please check your connection and try again.';
      case 'deadline-exceeded':
        return 'The request timed out. Please try again.';
      case 'permission-denied':
        return null;
      case 'not-found':
        return 'The requested data could not be found.';
      case 'cancelled':
        return 'The request was cancelled. Please try again.';
      case 'already-exists':
        return 'This item already exists.';
      case 'resource-exhausted':
        return 'Service is busy right now. Please try again shortly.';
      case 'unauthenticated':
        return 'Please login and try again.';
    }

    return null;
  }
}

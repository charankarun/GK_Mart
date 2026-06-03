import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../presentation/navigation/notification_navigation_service.dart';
import 'repository_exception.dart';

class AppErrorHandler {
  AppErrorHandler._();

  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  static void initialize() {
    FlutterError.onError = (details) {
      if (kDebugMode) FlutterError.presentError(details);
      _logFlutterError(details);
      if (!_isLayoutError(details.exception)) {
        showGlobalError(details.exception);
      }
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      report(error, stackTrace);
      return true;
    };
  }

  static void report(Object error, StackTrace stackTrace) {
    _logError('Unhandled async exception', error, stackTrace);
    if (kDebugMode) {
      FlutterError.presentError(
        FlutterErrorDetails(exception: error, stack: stackTrace),
      );
    }
    showGlobalError(error);
  }

  static void showGlobalError(Object? error, {String? fallbackMessage}) {
    try {
      final messenger = scaffoldMessengerKey.currentState;
      if (messenger == null || !messenger.mounted) {
        return;
      }

      final navContext = NotificationNavigationService.navigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) {
        return;
      }

      ScaffoldMessengerState? safeMessenger;
      try {
        safeMessenger = ScaffoldMessenger.maybeOf(navContext);
      } catch (_) {
        // Suppress and fallback
      }

      if (safeMessenger == null || safeMessenger != messenger || !safeMessenger.mounted) {
        return;
      }

      final schedulerPhase = SchedulerBinding.instance.schedulerPhase;
      final isBuilding = schedulerPhase == SchedulerPhase.persistentCallbacks ||
                         schedulerPhase == SchedulerPhase.midFrameMicrotasks;

      if (isBuilding) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _safeShowSnackBar(messenger, error, fallbackMessage);
        });
      } else {
        _safeShowSnackBar(messenger, error, fallbackMessage);
      }
    } catch (e, s) {
      _logError('Secondary error in showGlobalError', e, s);
    }
  }

  static void showErrorSnackBar(
    BuildContext context,
    Object? error, {
    String? fallbackMessage,
  }) {
    try {
      if (!context.mounted) return;

      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null || !messenger.mounted) return;

      final schedulerPhase = SchedulerBinding.instance.schedulerPhase;
      final isBuilding = schedulerPhase == SchedulerPhase.persistentCallbacks ||
                         schedulerPhase == SchedulerPhase.midFrameMicrotasks;

      if (isBuilding) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _safeShowSnackBar(messenger, error, fallbackMessage);
        });
      } else {
        _safeShowSnackBar(messenger, error, fallbackMessage);
      }
    } catch (e, s) {
      _logError('Failed to handle showErrorSnackBar', e, s);
    }
  }

  static void _safeShowSnackBar(
    ScaffoldMessengerState messenger,
    Object? error,
    String? fallbackMessage,
  ) {
    try {
      if (!messenger.mounted) return;
      if (isPermissionDenied(error)) {
        messenger.clearSnackBars();
        return;
      }

      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(messageFor(error, fallback: fallbackMessage))),
        );
    } catch (e, s) {
      _logError('Failed to display SnackBar safely', e, s);
    }
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
    if (kDebugMode) {
      final debugMessage = _debugMessageFor(error);
      if (debugMessage != null) return debugMessage;
    }

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

  static String? _debugMessageFor(Object? error) {
    if (error == null) return null;

    if (error is RepositoryException) {
      final code = error.code == null ? '' : ' (${error.code})';
      final causeMessage = _debugMessageFor(error.cause);
      if (causeMessage == null) {
        return 'RepositoryException$code: ${error.message}';
      }
      return 'RepositoryException$code: ${error.message}\nCause: $causeMessage';
    }

    if (error is FirebaseException) {
      final message = error.message?.trim();
      return 'FirebaseException (${error.code}): '
          '${message == null || message.isEmpty ? error : message}';
    }

    if (error is TimeoutException ||
        error is StateError ||
        error is TypeError ||
        error is ArgumentError ||
        error is NoSuchMethodError) {
      return error.toString();
    }

    final message = error.toString();
    if (message.contains('Null check operator used on a null value') ||
        message.toLowerCase().contains('null')) {
      return message;
    }

    return null;
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

  static bool _isLayoutError(Object? error) {
    final message = error?.toString() ?? '';
    return message.contains('A RenderFlex overflowed') ||
        message.contains('A RenderBox overflowed');
  }

  static void _logFlutterError(FlutterErrorDetails details) {
    _logError(
      details.context?.toDescription() ?? 'Flutter framework exception',
      details.exception,
      details.stack,
    );
  }

  static void _logError(
    String message,
    Object error,
    StackTrace? stackTrace,
  ) {
    developer.log(
      message,
      name: 'AppErrorHandler',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

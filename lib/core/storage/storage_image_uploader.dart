import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

const _debugLoggingEnabled = !bool.fromEnvironment('dart.vm.product');

class StorageImageUploader {
  const StorageImageUploader._();

  static Future<String> uploadBytesWithRetry({
    required Reference ref,
    required Uint8List bytes,
    required SettableMetadata metadata,
    required Duration uploadTimeout,
    required Duration downloadUrlTimeout,
    required String logName,
    int maxAttempts = 2,
  }) async {
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;

    for (var attempt = 1; attempt <= attempts; attempt += 1) {
      try {
        final uploadTask = ref.putData(bytes, metadata);
        final snapshot = await uploadTask.timeout(
          uploadTimeout,
          onTimeout: () {
            unawaited(uploadTask.cancel());
            throw TimeoutException('Storage image upload timed out.');
          },
        );
        return snapshot.ref.getDownloadURL().timeout(downloadUrlTimeout);
      } catch (error, stackTrace) {
        _logUploadError(
          logName: logName,
          attempt: attempt,
          maxAttempts: attempts,
          error: error,
          stackTrace: stackTrace,
        );
        if (attempt >= attempts || !_shouldRetry(error)) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      }
    }

    throw StateError('Storage upload retry loop exited unexpectedly.');
  }

  static bool _shouldRetry(Object error) {
    if (error is TimeoutException) return true;
    if (error is FirebaseException) {
      return error.code == 'unavailable' ||
          error.code == 'deadline-exceeded' ||
          error.code == 'network-request-failed' ||
          error.code == 'retry-limit-exceeded' ||
          error.code == 'unknown';
    }
    return false;
  }

  static void _logUploadError({
    required String logName,
    required int attempt,
    required int maxAttempts,
    required Object error,
    required StackTrace stackTrace,
  }) {
    if (!_debugLoggingEnabled) return;

    developer.log(
      'Storage image upload failed attempt=$attempt/$maxAttempts',
      name: logName,
      error: error,
      stackTrace: stackTrace,
    );
    if (error is FirebaseException) {
      developer.log(
        'FirebaseException code=${error.code} message=${error.message}',
        name: logName,
      );
    }
  }
}

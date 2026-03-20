import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

final cleanupServiceProvider = Provider((ref) => CleanupService());

class CleanupService {
  /// Deletes a file from Cloud Storage given its URL.
  Future<void> deleteCloudFile(String? url) async {
    if (url == null || url.isEmpty || !url.startsWith('http')) return;
    try {
      debugPrint('CleanupService: deleteCloudFile not implemented for $url');
    } catch (e) {
      debugPrint('CleanupService: Error deleting cloud file: $e');
    }
  }

  /// Deletes a file from the local filesystem given its path.
  Future<void> deleteLocalFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('CleanupService: Deleted local file at $path');
      }
    } catch (e) {
      debugPrint('CleanupService: Error deleting local file: $e');
    }
  }

  /// Deletes an entire folder (prefix) from Cloud Storage.
  Future<void> deleteStorageFolder(String path) async {
    if (path.isEmpty) return;
    try {
      debugPrint(
        'CleanupService: deleteStorageFolder not implemented for $path',
      );
    } catch (e) {
      debugPrint('CleanupService: Error deleting storage folder: $e');
    }
  }
}

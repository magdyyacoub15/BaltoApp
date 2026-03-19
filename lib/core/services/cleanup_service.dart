import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

final cleanupServiceProvider = Provider((ref) => CleanupService());

class CleanupService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Deletes a file from Firebase Storage given its URL.
  Future<void> deleteCloudFile(String? url) async {
    if (url == null || url.isEmpty || !url.startsWith('http')) return;
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
      debugPrint('CleanupService: Deleted cloud file at $url');
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

  /// Deletes an entire folder (prefix) from Firebase Storage.
  /// Useful for deleting all clinic-related assets.
  Future<void> deleteStorageFolder(String path) async {
    if (path.isEmpty) return;
    try {
      final listResult = await _storage.ref(path).listAll();

      // Delete all files in the current folder
      for (var item in listResult.items) {
        await item.delete();
      }

      // Recursively delete sub-folders
      for (var prefix in listResult.prefixes) {
        await deleteStorageFolder(prefix.fullPath);
      }

      debugPrint('CleanupService: Deleted storage folder at $path');
    } catch (e) {
      debugPrint('CleanupService: Error deleting storage folder: $e');
    }
  }
}

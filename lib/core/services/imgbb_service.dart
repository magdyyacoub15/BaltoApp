import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

final imgbbServiceProvider = Provider((ref) => ImgBBService());

class ImgBBService {
  final String _apiKey = '5b4d7c307a17ca146e1c6d831148e1d4';

  Future<ImgBBUploadResult?> uploadImage(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final uri = Uri.parse('https://api.imgbb.com/1/upload');
      final request = http.MultipartRequest('POST', uri);
      request.fields['key'] = _apiKey;
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: imageFile.name,
        ),
      );

      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonMap = json.decode(responseData);
        if (jsonMap['success'] == true) {
          final url = jsonMap['data']['url'] as String;
          final deleteUrl = jsonMap['data']['delete_url'] as String? ?? '';
          debugPrint('ImgBBService: Image uploaded: $url');
          return ImgBBUploadResult(url: url, deleteUrl: deleteUrl);
        } else {
          debugPrint('ImgBBService: Upload failed: ${jsonMap['error']}');
        }
      } else {
        debugPrint('ImgBBService: HTTP Error ${response.statusCode}: $responseData');
      }
    } catch (e) {
      debugPrint('ImgBBService: Error uploading image: $e');
    }
    return null;
  }

  /// Deletes an image from ImgBB using the delete URL stored at upload time.
  Future<void> deleteImage(String deleteUrl) async {
    if (deleteUrl.isEmpty) return;
    try {
      final response = await http.get(Uri.parse(deleteUrl));
      if (response.statusCode == 200) {
        debugPrint('ImgBBService: Image deleted via deleteUrl');
      } else {
        debugPrint('ImgBBService: Delete failed — status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('ImgBBService: Error deleting image: $e');
    }
  }
}

class ImgBBUploadResult {
  final String url;
  final String deleteUrl;
  const ImgBBUploadResult({required this.url, required this.deleteUrl});
}

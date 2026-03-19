import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

final imgbbServiceProvider = Provider((ref) => ImgBBService());

class ImgBBService {
  final String _apiKey = '5b4d7c307a17ca146e1c6d831148e1d4';

  Future<String?> uploadImage(File imageFile) async {
    try {
      final uri = Uri.parse('https://api.imgbb.com/1/upload');
      final request = http.MultipartRequest('POST', uri);
      request.fields['key'] = _apiKey;
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonMap = json.decode(responseData);
        if (jsonMap['success'] == true) {
          final url = jsonMap['data']['url'] as String;
          debugPrint('ImgBBService: Image uploaded successfully: $url');
          return url;
        } else {
          debugPrint('ImgBBService: Upload failed: ${jsonMap['error']}');
        }
      } else {
        debugPrint(
          'ImgBBService: HTTP Error ${response.statusCode}: $responseData',
        );
      }
    } catch (e) {
      debugPrint('ImgBBService: Error uploading image: $e');
    }
    return null;
  }
}

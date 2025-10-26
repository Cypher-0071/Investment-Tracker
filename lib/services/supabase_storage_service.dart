import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseStorageService {
  static final SupabaseClient _client = Supabase.instance.client;

  /// Upload a file to Supabase Storage
  /// [file] - The file to upload
  /// [storagePath] - The path in Supabase Storage (e.g., 'images/profile_pictures/user123.jpg')
  /// Returns the download URL
  static Future<String> uploadFile(File file, String storagePath) async {
    try {
      // Check if file exists
      if (!await file.exists()) {
        throw Exception('File does not exist: ${file.path}');
      }

      // Read file bytes
      final fileBytes = await file.readAsBytes();
      
      // Upload file
      await _client.storage.from('profile_images').uploadBinary(
        storagePath,
        fileBytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );
      
      // Get download URL
      final downloadUrl = _client.storage
          .from('profile_images')
          .getPublicUrl(storagePath);
      
      return downloadUrl;
    } catch (e) {
      print('Supabase Storage upload error: $e');
      throw Exception('Failed to upload file: $e');
    }
  }

  /// Upload bytes data to Supabase Storage
  /// [bytes] - The bytes data to upload
  /// [storagePath] - The path in Supabase Storage
  /// Returns the download URL
  static Future<String> uploadBytes(Uint8List bytes, String storagePath) async {
    try {
      await _client.storage.from('profile_images').uploadBinary(
        storagePath,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );
      
      final downloadUrl = _client.storage
          .from('profile_images')
          .getPublicUrl(storagePath);
      
      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to upload bytes: $e');
    }
  }

  /// Download a file from Supabase Storage
  /// [storagePath] - The path in Supabase Storage
  /// Returns the download URL
  static Future<String> getDownloadURL(String storagePath) async {
    try {
      final downloadUrl = _client.storage
          .from('profile_images')
          .getPublicUrl(storagePath);
      
      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to get download URL: $e');
    }
  }

  /// Delete a file from Supabase Storage
  /// [storagePath] - The path in Supabase Storage
  static Future<void> deleteFile(String storagePath) async {
    try {
      await _client.storage.from('profile_images').remove([storagePath]);
    } catch (e) {
      throw Exception('Failed to delete file: $e');
    }
  }

  /// List files in a directory
  /// [storagePath] - The directory path in Supabase Storage
  /// Returns a list of file names
  static Future<List<String>> listFiles(String storagePath) async {
    try {
      final files = await _client.storage
          .from('profile_images')
          .list(path: storagePath);
      
      return files.map((file) => file.name).toList();
    } catch (e) {
      throw Exception('Failed to list files: $e');
    }
  }

  /// Upload with progress tracking
  /// [file] - The file to upload
  /// [storagePath] - The path in Supabase Storage
  /// [onProgress] - Callback for progress updates
  /// Returns the download URL
  static Future<String> uploadFileWithProgress(
    File file,
    String storagePath,
    Function(double progress)? onProgress,
  ) async {
    try {
      // Check if file exists
      if (!await file.exists()) {
        throw Exception('File does not exist: ${file.path}');
      }

      // Read file bytes
      final fileBytes = await file.readAsBytes();
      
      // Upload file
      await _client.storage.from('profile_images').uploadBinary(
        storagePath,
        fileBytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );
      
      // Notify progress (Supabase doesn't have built-in progress, so we simulate)
      onProgress?.call(1.0);
      
      final downloadUrl = _client.storage
          .from('profile_images')
          .getPublicUrl(storagePath);
      
      return downloadUrl;
    } catch (e) {
      print('Supabase Storage upload with progress error: $e');
      throw Exception('Failed to upload file with progress: $e');
    }
  }

  /// Generate a unique filename with timestamp
  /// [originalName] - The original filename
  /// Returns a unique filename
  static String generateUniqueFileName(String originalName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = path.extension(originalName);
    final nameWithoutExtension = path.basenameWithoutExtension(originalName);
    return '${nameWithoutExtension}_$timestamp$extension';
  }
}


import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class ReceiptStorageService {
  final ImagePicker _picker;

  ReceiptStorageService({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  /// Captures or picks an image and saves it to local app receipts storage.
  /// Applies client-side compression: max 1600x1600 at 80% quality.
  Future<String?> pickAndStoreReceipt(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );

      if (pickedFile == null) return null;

      if (kIsWeb) {
        // On web, return path/URI or data URL as applicable
        return pickedFile.path;
      }

      final baseDir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final year = now.year.toString();
      final month = now.month.toString().padLeft(2, '0');

      final receiptsDir = Directory(
        p.join(baseDir.path, 'receipts', year, month),
      );

      if (!await receiptsDir.exists()) {
        await receiptsDir.create(recursive: true);
      }

      final ext = p.extension(pickedFile.path).isNotEmpty
          ? p.extension(pickedFile.path)
          : '.jpg';
      final fileName = '${const Uuid().v4()}$ext';
      final destPath = p.join(receiptsDir.path, fileName);

      final destFile = await File(pickedFile.path).copy(destPath);
      return destFile.path;
    } catch (e) {
      debugPrint('ReceiptStorageService error: $e');
      rethrow;
    }
  }

  /// Deletes a stored receipt file from disk if it exists.
  Future<void> deleteReceipt(String? path) async {
    if (path == null || path.isEmpty || kIsWeb) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting receipt at $path: $e');
    }
  }
}


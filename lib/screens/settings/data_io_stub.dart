// Web dışı platformlarda dosya kaydetme (dosya seçici ile).
import 'dart:convert';

import 'package:file_picker/file_picker.dart';

/// Metin içeriğini kullanıcının seçtiği konuma kaydeder.
Future<bool> saveTextFile(String filename, String content, String mime) async {
  try {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Dosyayı Kaydet',
      fileName: filename,
      bytes: utf8.encode(content),
      mimeType: mime,
      type: FileType.any,
    );
    return uri != null;
  } catch (_) {
    return false;
  }
}

Future<String?> pickTextFile() async {
  try {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    return bytes == null ? null : utf8.decode(bytes);
  } catch (_) {
    return null;
  }
}

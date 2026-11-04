import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../core/i18n/tr.dart';

typedef PdfPathPicker = Future<String?> Function(String suggestedName);

class PrintPdfFileSaver {
  const PrintPdfFileSaver._();

  static Future<String?> save({
    required Uint8List bytes,
    required String suggestedName,
    PdfPathPicker? pickPath,
  }) async {
    final path = await (pickPath ?? _pickPath)(suggestedName);
    if (path == null) return null;
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  static Future<String?> _pickPath(String suggestedName) => FilePicker.saveFile(
    dialogTitle: tr('حفظ PDF'),
    fileName: suggestedName,
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
}

// ملفُّ JSON للقالب — حفظُه واختيارُه من القرص.
//
// مستخرَجٌ من المصمّم القديم (‏`invoice_designer_templates.dart`) لا منسوخ:
// المصمّمُ وقماشُ الملصق يناديان الدالّتين نفسَيهما، والتنسيقُ واحد.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// يحفظ [json] منسَّقاً في ملفٍّ يختاره المستخدم. `false` حين يُلغي الحوار.
Future<bool> saveTemplateJsonFile({
  required String dialogTitle,
  required String baseName,
  required String json,
}) async {
  final pretty = const JsonEncoder.withIndent('  ').convert(jsonDecode(json));
  final result = await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: '${baseName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_')}.json',
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (result == null) return false;
  await File(result).writeAsString(pretty, flush: true);
  return true;
}

/// يختار ملفَّ JSON ويُرجع نصَّه — `null` حين يُلغي الحوار.
Future<String?> pickTemplateJsonFile({required String dialogTitle}) async {
  final result = await FilePicker.pickFiles(
    dialogTitle: dialogTitle,
    type: FileType.custom,
    allowedExtensions: ['json'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.first;
  if (file.bytes != null) return utf8.decode(file.bytes!);
  if (file.path != null) return File(file.path!).readAsString();
  throw Exception('لم يتم قراءة الملف');
}

import 'dart:async' show unawaited;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing_pkg;
import 'package:flutter/foundation.dart';
import '../../core/logging/diagnostic_logger.dart';

/// Helper to print PDF documents via the native print preview dialog.
///
/// NOTE: pdf.save() intentionally runs on the MAIN thread.
/// Running it in an Isolate causes Arabic font data and page build closures
/// to be deep-copied across isolate boundaries, which can result in
/// font data corruption → Arabic text rendered as boxes (■■■).
class PdfComputeHelper {
  /// Serialise the document and send to the native print preview dialog.
  ///
  /// Usage:
  /// ```dart
  /// final pdf = await BaseGenerator.newDocument();
  /// pdf.addPage(...);
  /// await PdfComputeHelper.layoutPdf(pdf);
  /// ```
  ///
  /// Field-report 2026-05-14: standalone build silently process-exited
  /// ~90s after a successful A4 print. The Dart future resolved cleanly
  /// (`err=null`), so the crash is in the native Windows print-preview
  /// teardown. Adding the try/catch + breadcrumbs here so the next
  /// repro lands a usable trace instead of disappearing into the void.
  /// خطّافُ تسجيلِ الطباعة — يُضبَط مرّةً عند الإقلاع في `main.dart`.
  ///
  /// ── لماذا خطّافٌ لا نداءٌ مباشر ───────────────────────────────────────
  /// هذا الملفُّ في `services/printing` ولا يعرف قاعدةً ولا مستخدماً، وحقنُ
  /// `AppDatabase` في كلّ مولّدِ PDF كان يقلب اعتماديّةَ الطبقة رأساً على
  /// عقب. والخطّافُ **فارغٌ بالبناء**، فمن لا يضبطه لا يتغيّر سلوكُه إطلاقاً.
  ///
  /// ⚠️ **ولا يُنادى إلّا بعد خروج الورقة**: بعد عودة حوار الطباعة الأصليّ
  /// بلا رمي. فمستندٌ ألغى المستخدمُ طباعتَه في الحوار يُسجَّل — وهذا حدُّ
  /// معلَنٌ لا سهو: النظامُ لا يرى ما بعد الحوار، وسطرُ «أُرسل إلى الطباعة»
  /// أصدقُ ممّا يدّعي معرفةَ ما خرج من الطابعة فعلاً.
  static Future<void> Function(String documentLabel)? onPrinted;

  /// [documentLabel] اسمُ المستند كما يُقرأ في السجلّ. `null` ⇒ لا تسجيل —
  /// وهو الوضعُ الصحيحُ للفواتير، فـ`PrintingServiceImpl` يسجّلها بنفسه
  /// بمعرِّفِ الفاتورة ومبلغِها، وتسجيلُها هنا أيضاً يكتب سطرَين لطباعةٍ
  /// واحدة.
  static Future<void> layoutPdf(pw.Document pdf, {String? documentLabel}) async {
    final Uint8List bytes = await saveToBytes(pdf);
    unawaited(DiagnosticLogger.log(
        'PDF-PRINT', 'layoutPdf invoking native dialog (bytes=${bytes.length})'));
    try {
      await printing_pkg.Printing.layoutPdf(
        onLayout: (format) async => bytes,
      );
      unawaited(DiagnosticLogger.log('PDF-PRINT', 'layoutPdf returned OK'));
      final hook = onPrinted;
      if (hook != null && documentLabel != null) {
        // إخفاقُ التسجيل لا يُسقط الطباعة — الورقةُ خرجت فعلاً.
        try {
          await hook(documentLabel);
        } catch (e) {
          unawaited(
              DiagnosticLogger.log('PDF-PRINT', 'print-audit hook failed: $e'));
        }
      }
    } catch (e, st) {
      unawaited(DiagnosticLogger.log(
          'PDF-PRINT', 'layoutPdf threw: $e\n$st'));
      rethrow;
    }
  }

  /// Save PDF to bytes on the main thread.
  /// Fonts and closures are fully accessible here — no isolate boundary issues.
  static Future<Uint8List> saveToBytes(pw.Document pdf) async {
    try {
      return await pdf.save();
    } catch (e) {
      debugPrint('[PdfComputeHelper] pdf.save() error: $e');
      rethrow;
    }
  }
}


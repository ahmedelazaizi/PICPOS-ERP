import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:pdf/pdf.dart' show PdfPageFormat;
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
  /// final printed = await PdfComputeHelper.layoutPdf(pdf);
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
  /// بـ`true`. مستندٌ ألغى المستخدمُ طباعتَه في الحوار **لا يُسجَّل** (منذ
  /// 2026-09-02 — كان يُسجَّل لأنّ القيمةَ كانت تُهمَل). وما بعد قبول
  /// الطابعة للمهمّة لا يراه النظام، فسطرُ «أُرسل إلى الطباعة» أصدقُ ممّا
  /// يدّعي معرفةَ ما خرج من الطابعة فعلاً.
  static Future<void> Function(String documentLabel)? onPrinted;

  /// بديلُ الحوار الأصليّ في الاختبارات — `null` في الإنتاج.
  ///
  /// `Printing.layoutPdf` تحتاج قناةَ منصّةٍ فلا تعمل في اختبار وحدة؛ وهذا
  /// الخطّافُ يُثبت العقدَ الوحيدَ الذي يهمّ: إلغاءُ الحوار ⇒ `false`
  /// و**لا** نداءَ لخطّاف التسجيل.
  @visibleForTesting
  static Future<bool> Function(Uint8List bytes, String? name)?
  nativeLayoutOverride;

  /// Native named-printer hand-off; injectable so routing can be verified
  /// without a Windows queue or physical printer.
  @visibleForTesting
  static Future<bool> Function(printing_pkg.Printer printer, Uint8List bytes)?
  directPrintOverride;

  /// آخرُ مقاسِ ورقٍ طُلب من الطابعة (‏`null` = افتراضُ الحزمة A4/Letter).
  ///
  /// ⚠️ على Windows تبني `printing` بنيةَ `DEVMODE` من [format] لا من صفحات
  /// الـPDF: غيابُه يطلب ورقةً قياسيّةً فيُرسم ملصقُ ٥٨×٤٠ صغيراً في ركنها
  /// (‏رُصد حيّاً 2026-11-03). يُحفظ هنا ليُثبَت في الاختبار بلا طابعة.
  @visibleForTesting
  static PdfPageFormat? lastRequestedFormat;

  /// [format] مقاسُ الورقة المطلوبُ من السائق — مرّره حين يكون المستندُ
  /// بمقاسٍ غيرِ قياسيّ (ملصق)، وإلّا بقي سلوكُ الحزمة كما كان.
  static Future<bool> directPrintBytes({
    required printing_pkg.Printer printer,
    required Uint8List bytes,
    PdfPageFormat? format,
    String? name,
  }) async {
    lastRequestedFormat = format;
    final override = directPrintOverride;
    if (override != null) return override(printer, bytes);
    return await printing_pkg.Printing.directPrintPdf(
      printer: printer,
      onLayout: (_) async => bytes,
      name: name ?? 'Document',
      format: format ?? PdfPageFormat.standard,
    );
  }

  /// [documentLabel] اسمُ المستند كما يُقرأ في السجلّ. `null` ⇒ لا تسجيل —
  /// وهو الوضعُ الصحيحُ للفواتير، فـ`PrintingServiceImpl` يسجّلها بنفسه
  /// بمعرِّفِ الفاتورة ومبلغِها، وتسجيلُها هنا أيضاً يكتب سطرَين لطباعةٍ
  /// واحدة.
  ///
  /// يرجع **ما ردّه حوارُ الطباعة**: `true` قُبلت المهمّة، و`false` ألغى
  /// المستخدمُ. كانت القيمةُ تُهمَل فيرى من ضغط «إلغاء» رسالةَ «تمّت
  /// الطباعة» على كلِّ شاشةٍ تطبع — ٤٩ موضعاً في ١٨ ملفّاً (مقيس 2026-09-02).
  static Future<bool> layoutPdf(
    pw.Document pdf, {
    String? documentLabel,
    String? name,
    PdfPageFormat? format,
  }) async {
    final Uint8List bytes = await saveToBytes(pdf);
    return layoutBytes(
      bytes,
      documentLabel: documentLabel,
      name: name,
      format: format,
    );
  }

  /// نفسُ [layoutPdf] لبايتاتٍ جاهزة — القمعُ الوحيدُ لحوار الطباعة الأصليّ.
  ///
  /// ⚠️ **كلُّ نداءٍ لـ`Printing.layoutPdf` في `lib` يمرّ من هنا** — يحرسه
  /// `print_dialog_funnel_guard_test`. نداءٌ مباشرٌ يفقد ثلاثةَ أشياء دفعةً:
  /// سجلَّ التشخيص، وخطّافَ التسجيل، وقيمةَ الإلغاء.
  static Future<bool> layoutBytes(
    Uint8List bytes, {
    String? documentLabel,
    String? name,
    PdfPageFormat? format,
  }) async {
    lastRequestedFormat = format;
    unawaited(
      DiagnosticLogger.log(
        'PDF-PRINT',
        'layoutPdf invoking native dialog (bytes=${bytes.length})',
      ),
    );
    try {
      final override = nativeLayoutOverride;
      final bool printed = override != null
          ? await override(bytes, name)
          : await printing_pkg.Printing.layoutPdf(
              onLayout: (_) async => bytes,
              name: name ?? 'Document',
              format: format ?? PdfPageFormat.standard,
            );
      if (!printed) {
        unawaited(
          DiagnosticLogger.log(
            'PDF-PRINT',
            'layoutPdf cancelled by user (no sheet, no audit)',
          ),
        );
        return false;
      }
      unawaited(DiagnosticLogger.log('PDF-PRINT', 'layoutPdf returned OK'));
      final hook = onPrinted;
      if (hook != null && documentLabel != null) {
        // إخفاقُ التسجيل لا يُسقط الطباعة — الورقةُ خرجت فعلاً.
        try {
          await hook(documentLabel);
        } catch (e) {
          unawaited(
            DiagnosticLogger.log('PDF-PRINT', 'print-audit hook failed: $e'),
          );
        }
      }
      return true;
    } catch (e, st) {
      unawaited(DiagnosticLogger.log('PDF-PRINT', 'layoutPdf threw: $e\n$st'));
      rethrow;
    }
  }

  static PdfPageFormat pageFormatForTemplate(
    double widthMm,
    String marginsJson,
  ) {
    final margins = _parseMargins(marginsJson);
    const mm = PdfPageFormat.mm;
    return PdfPageFormat(widthMm * mm, double.infinity,
        marginTop: margins['top']! * mm,
        marginRight: margins['right']! * mm,
        marginBottom: margins['bottom']! * mm,
        marginLeft: margins['left']! * mm);
  }

  static Map<String, double> _parseMargins(String json) {
    try {
      final margins = jsonDecode(json) as Map<String, dynamic>;
      return {
        'top': (margins['top'] as num?)?.toDouble() ?? 5,
        'right': (margins['right'] as num?)?.toDouble() ?? 5,
        'bottom': (margins['bottom'] as num?)?.toDouble() ?? 5,
        'left': (margins['left'] as num?)?.toDouble() ?? 5,
      };
    } catch (_) {
      return {'top': 5, 'right': 5, 'bottom': 5, 'left': 5};
    }
  }

  /// Serialize once and return the final page format used for the MediaBox.
  /// Continuous pages resolve their infinite height during layout/save.
  static Future<({Uint8List bytes, PdfPageFormat format})> saveToBytesWithMediaBox(
    pw.Document pdf,
  ) async {
    final bytes = await saveToBytes(pdf);
    final pages = pdf.document.pdfPageList.pages;
    if (pages.isEmpty) throw StateError('Cannot print a PDF without pages');
    return (bytes: bytes, format: pages.last.pageFormat);
  }

  static Future<bool> directPrintDocument({
    required printing_pkg.Printer printer,
    required pw.Document pdf,
  }) async {
    final output = await saveToBytesWithMediaBox(pdf);
    return directPrintBytes(
      printer: printer,
      bytes: output.bytes,
      format: output.format,
    );
  }

  static Future<bool> layoutPdfWithMediaBox(pw.Document pdf) async {
    final output = await saveToBytesWithMediaBox(pdf);
    return layoutBytes(output.bytes, format: output.format);
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

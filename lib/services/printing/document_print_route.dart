/// وجهةُ طباعةِ مستندٍ: أيُّ طابعةٍ، وأيُّ قالبٍ مربوطٍ بها.
///
/// ── العطبُ الذي يسدّه (الجولة الحيّة 2026-11-04) ─────────────────────────
/// زرُّ «طباعة» في قائمة فواتير البيع وتفاصيلها كان ينادي
/// `PrintingService.printReceipt` — مسارَ إيصال نقطة البيع بنوع المستند
/// `sales_receipt`. فرابطةُ `sales_invoice → طابعة A4 → «فاتورة A4»` لا
/// تُستشار أصلاً: لا رابطةَ لـ`sales_receipt`، فيسقط الحسمُ إلى الافتراضيِّ
/// بالفئة (‏`thermal/receipt` = «الفاتورة الحرارية»)، ويُرسم بعرضٍ حراريٍّ
/// (‏٧٢مم مطبوعةً) داخل صفحةِ طابعة A4.
///
/// والطابعةُ نفسُها كانت تُختار بـ`getActivePrinterByPurpose('pos_receipt')`
/// — **أوّلُ** طابعةٍ نشطةٍ بالغرض بلا ترتيب. وحين تحمل طابعتان الغرضَ نفسَه
/// (‏A4 و٨٠مم) لا يعرف المنادي أيَّهما تخرج، ورابطةُ المرتجع على طابعة ٨٠مم
/// تخسر مستواها الأوّل متى صادف أن جاءت طابعةُ A4 أوّلاً.
///
/// نقيٌّ من الواجهة: يقرأ القاعدةَ وحدَها.
library;

import '../../data/database/database.dart';
import 'paper_compatibility.dart';

/// الطابعةُ المحسومة لنوع مستند.
///
/// ١ · طابعةٌ **نشطةٌ** تسمّيها رابطةٌ لهذا النوع (‏`template_bindings.printer_id`)
///     يوافق فرعُها ولغتُها المستندَ — الأخصُّ أوّلاً (فرعٌ مسمّى ثم لغةٌ مسمّاة)
///     ثم الأولويّةُ الأعلى ثم الأقدمُ معرِّفاً، فالنتيجةُ ثابتة. و[locale]
///     غائباً لا يُرشِّح باللغة (المنادي لا يعرفها؛ الحسمُ بعده يقرّرها).
/// ٢ · وإلّا الطابعةُ الافتراضيّةُ للغرض [purpose] — سلوكُ ما قبل الإصلاح بحرفه.
Future<int?> resolveDocumentPrinterId(
  AppDatabase db, {
  required String documentType,
  String purpose = 'pos_receipt',
  int? branchId,
  String? locale,
}) async {
  try {
    final candidates = [
      for (final b in await db.getAllBindings())
        if (b.documentType == documentType &&
            b.printerId != null &&
            (b.branchId == null || b.branchId == branchId) &&
            (locale == null || b.locale == null || b.locale == locale))
          b,
    ];
    int rank(TemplateBinding b) =>
        (b.branchId != null ? 2 : 0) + (b.locale != null ? 1 : 0);
    candidates.sort((a, b) {
      final bySpecificity = rank(b).compareTo(rank(a));
      if (bySpecificity != 0) return bySpecificity;
      final byPriority = b.priority.compareTo(a.priority);
      return byPriority != 0 ? byPriority : a.id.compareTo(b.id);
    });
    for (final b in candidates) {
      final printer = await db.getPrinterById(b.printerId);
      if (printer != null && printer.isActive) return printer.id;
    }
  } catch (_) {
    // قراءةُ الرابطات المنهارة لا تمنع طباعة — يبقى الغرضُ الافتراضيّ.
  }
  return (await db.getActivePrinterByPurpose(purpose))?.id;
}

/// القالبُ الذي **ربطه المستخدمُ صراحةً** بنوع المستند على [printerId].
///
/// المستوياتُ ١..٤ من السلسلة وحدَها (رابطات). `null` حين لا رابطة — فيبقى
/// المنادي على مساره القائم؛ ولا يُستعمل هنا الافتراضيُّ بالفئة (المستوى
/// السادس) لأنّه **يغيّر** مطبوعَ من لم يربط شيئاً.
///
/// و`null` كذلك حين يكون القالبُ أعرضَ من الطابعة (‏A4 على ٨٠مم): رابطةٌ
/// عامّةٌ بلا طابعةٍ لا تُجيز قصَّ الفاتورة على طابعةٍ حراريّة.
Future<InvoiceTemplateWithData?> boundDocumentTemplate(
  AppDatabase db, {
  required String documentType,
  required String category,
  int? printerId,
  int? branchId,
  String? locale,
}) async {
  final r = await db.resolveTemplateFor(
    documentType: documentType,
    category: category,
    branchId: branchId,
    printerId: printerId,
    locale: locale,
  );
  if (r.templateId == null || r.level > 4) return null;
  final data = await db.getTemplateWithData(r.templateId!);
  if (data == null) return null;
  final printer = await db.getPrinterById(printerId);
  final fit = checkPaperFit(
    templateWidthMm: data.template.paperWidth,
    printerWidthMm: printer?.paperWidthMm,
  );
  return fit.isRejected ? null : data;
}

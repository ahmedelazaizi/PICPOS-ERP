// ═══════════════════════════════════════════════════════════════════════════
// §٤‑٣ — إخفاقُ الطباعة كان يُبلَّغ نجاحاً: قياسُ القيمة لا قراءةُ الحلقة
// ═══════════════════════════════════════════════════════════════════════════
//
// التسليمُ وصف البندَ بأنّ «حلقةَ `copies` تبتلع الفشل»، ثمّ شكّ في الوصف
// لأنّ الحلقةَ في `picpos_pos_operations` تبدو محترمةً للإخفاق:
//
//     printed = await _tryPrintReceipt(invoiceId);
//     if (!printed || !mounted) break;
//
// والحلقةُ سليمةٌ فعلاً — والابتلاعُ **طبقةً أعمق**:
//
//   `_tryPrintReceipt`   ← كان يرجع `true` لمجرّد غياب الاستثناء
//     └─ `PosController.printInvoice`      ← `Future<void>`، يبتلع النتيجة
//          └─ `PrintingServiceImpl.printReceipt`
//                جسمُها كلُّه في `try { … } catch (e, stack) { logger.error(…) }`
//                **بلا إعادةِ رمي** — فهي لا ترمي أبداً.
//
// فالنتائجُ ثلاثٌ، وكلُّها كانت واقعةً معاً:
//   ١. «تم حفظ وطباعة الفاتورة» تظهر ولا ورقةَ خرجت.
//   ٢. تحذيرُ «⚠️ فشلت الطباعة (تأكد من الورق)» كودٌ ميّتٌ لا يظهر قطّ.
//   ٣. `if (!printed) break` لا تقطع، فتُعاد المحاولةُ على طابعةٍ عاطلةٍ
//      بعددِ النسخ المضبوط.
//
// ⚠️ **ولا يُقاس هذا بقراءة الحلقة**: قراءتُها وحدَها هي التي أنتجت النفيَ
// الخاطئ في التسليم. المقيسُ هنا **القيمةُ العائدةُ من الخدمة نفسِها**.
//
// ── حدٌّ معلَنٌ يبقى ────────────────────────────────────────────────────────
// `false` تعني «لم يُرسَل إلى الطابعة». أمّا إلغاءُ المستخدم في حوار الطباعة
// فما زال يُحسَب نجاحاً: `Printing.layoutPdf` تُرجع `bool` تُهمَل في
// `PdfComputeHelper.layoutPdf` وفي كلِّ مواضع النداء. وذلك بندٌ منفصلٌ أصغرُ
// أثراً، وموصوفٌ في تعليق `IPrintingService.printReceipt`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';
import 'package:picpos_erp/services/printing_service.dart';

/// مستودعٌ لا بياناتِ طباعةٍ عنده — يحاكي فاتورةً محذوفةً أو معرِّفاً خاطئاً.
class _NoDataSalesRepo implements SalesRepository {
  bool asked = false;

  @override
  Future<SalesPrintData?> getSalesPrintData(int invoiceId) async {
    asked = true;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// مستودعٌ يرمي — يحاكي قاعدةً مقفلةً أو صفّاً تالفاً.
class _ThrowingSalesRepo implements SalesRepository {
  bool asked = false;

  @override
  Future<SalesPrintData?> getSalesPrintData(int invoiceId) async {
    asked = true;
    throw StateError('تعذّرت قراءةُ بيانات الطباعة');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  test('بياناتُ طباعةٍ غائبةٌ ⇒ الخدمةُ تُبلغ بعدمِ الطباعة', () async {
    final repo = _NoDataSalesRepo();
    final service = PrintingServiceImpl(db, repo);

    final printed = await service.printReceipt(999999);

    // مرساة: الجسمُ نُفِّذ فعلاً ووصل المستودع — وإلّا قِسنا قِصَراً لا عقداً.
    expect(repo.asked, isTrue,
        reason: 'مرساة: `getSalesPrintData` يجب أن تُنادى');
    expect(printed, isFalse,
        reason: 'لا ورقةَ خرجت — والمنادي في نقطة البيع يبني رسالتَه على هذه '
            'القيمة وحدَها، فـ`true` هنا تعني «تم حفظ وطباعة الفاتورة» كذباً');
  });

  test('إخفاقٌ مرميٌّ ⇒ الخدمةُ تبتلع الرميَ لكنّها تُبلغ بالقيمة', () async {
    final repo = _ThrowingSalesRepo();
    final service = PrintingServiceImpl(db, repo);

    // الخدمةُ **لا ترمي** — وهذا مقصودٌ وباقٍ. والقيمةُ هي القناةُ الوحيدة.
    final printed = await service.printReceipt(1);

    expect(repo.asked, isTrue, reason: 'مرساة: الرميُ وقع داخلَ الجسم');
    expect(printed, isFalse,
        reason: 'الرميُ ابتُلع، فلو رجعت `void`/`true` لما بقيت للمنادي '
            'قناةٌ يعرف بها أنّ الطباعةَ فشلت');
  });

  // ── حارسُ السلسلة ───────────────────────────────────────────────────────
  //
  // الاختباران أعلاه يحرسان الخدمةَ وحدَها. ولو عاد أيُّ حلقةٍ في السلسلة إلى
  // `Future<void>` لانقطعت القناةُ ثانيةً بلا أن يسقط شيء — وهو **عينُ** ما
  // كان واقعاً: الخدمةُ تعرف، والمنادي لا يسمع.
  group('سلسلةُ النداء تحمل النتيجةَ إلى الشاشة', () {
    /// يقرأ الملفَّ ويؤكّد أنّ الاستخراجَ يعمل قبل أن يحكم على الغياب.
    String read(String path) {
      final src = File(path).readAsStringSync();
      expect(src.length, greaterThan(500),
          reason: 'مرساة: الملفُّ $path قُرئ فعلاً');
      return src;
    }

    test('`IPrintingService.printReceipt` تُرجع `bool` لا `void`', () {
      final src = read('lib/services/printing_service.dart');
      expect(src.contains('Future<bool> printReceipt(int invoiceId);'), isTrue,
          reason: 'الواجهةُ هي العقد — و`Future<void>` تُسقط النتيجةَ صامتة');
      expect(src.contains('Future<bool> printReceipt(int invoiceId) async {'),
          isTrue,
          reason: 'والتنفيذُ مثلُها');
    });

    test('`PosController.printInvoice` تمرّر النتيجةَ لا تبتلعها', () {
      final src = read('lib/presentation/pos/providers/pos_controller.dart');
      expect(src.contains('Future<bool> printInvoice(int invoiceId)'), isTrue,
          reason: 'الحلقةُ الوسطى — `Future<void>` هنا تقطع القناة');
      // مرساة: الاستخراجُ يرى محتوى هذا الملفِّ بعينه.
      expect(src.contains('printingServiceProvider'), isTrue,
          reason: 'مرساة: الملفُّ المقروءُ هو مُتحكّمُ نقطة البيع');
    });

    test('`_tryPrintReceipt` تبني قرارَها على القيمة لا على غياب الرمي', () {
      final src = read(
          'lib/presentation/pos_picpos/screens/picpos_pos_checkout_support.dart');
      // مرساة: الدالّةُ المقصودةُ موجودةٌ في الملفّ المقروء.
      expect(src.contains('Future<bool> _tryPrintReceipt(int invoiceId)'),
          isTrue,
          reason: 'مرساة: `_tryPrintReceipt` في هذا الملفّ');
      expect(src.contains('if (!printed) warn('), isTrue,
          reason: 'القيمةُ `false` يجب أن تُنتج تحذيراً — وإلّا عاد التحذيرُ '
              'كوداً ميّتاً كما كان');
    });
  });
}

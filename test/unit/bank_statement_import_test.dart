// الاستيرادُ يُبلّغ بعددَي المُدرَج والمرفوض — والصفُّ المرفوضُ يُقال بسببه.
// ⚠️ القياسُ على **دالّةِ التجميع** لا على `_pickFile`: اختيارُ الملفّ
// إضافةٌ من نظام التشغيل لا منطق.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/services/excel_service.dart';

void main() {
  test('مرساة: صفوفٌ سليمةٌ كلُّها تُقبَل', () {
    final r = summarizeBankStatementRows([
      [DateTime(2026, 5, 1), 'A', '', 0, 100],
      [DateTime(2026, 5, 2), 'B', '', 50, 0],
    ]);

    expect(r.lines, hasLength(2));
    expect(r.errors, isEmpty);
  });

  test('🔴 الصفُّ المرفوضُ يُعَدُّ ويُقال سببُه', () {
    final r = summarizeBankStatementRows([
      [DateTime(2026, 5, 1), 'A', '', 0, 100],
      ['تاريخٌ فاسد', 'B', '', 0, 50],
      [DateTime(2026, 5, 3), 'C', '', 0, 0],
    ]);

    expect(r.lines, hasLength(1), reason: 'السليمُ وحدَه يُدرَج');
    expect(r.errors, hasLength(2), reason: 'والمرفوضان يُعَدّان لا يُطرَحان');
    expect(r.errors.first, contains('٢'), reason: 'ورقمُ الصفِّ في الرسالة');
  });

  test('صفُّ الرؤوس وسطرُ الشرح يُتخطّيان', () {
    final r = summarizeBankStatementRows([
      ['⚠️ مدين/دائن من منظور البنك', '', '', '', ''],
      ['التاريخ', 'المرجع', 'البيان', 'مدين', 'دائن'],
      [DateTime(2026, 5, 1), 'A', '', 0, 100],
    ], skipRows: 2);

    expect(r.lines, hasLength(1));
    expect(r.errors, isEmpty);
  });

  test('🔴 الصفوفُ الفارغةُ في ذيل الملفّ تُتخطّى ولا تُعَدُّ أخطاءً', () {
    final r = summarizeBankStatementRows([
      [DateTime(2026, 5, 1), 'A', '', 0, 100],
      [DateTime(2026, 5, 2), 'B', '', 50, 0],
      [],
      [null, null, null, null, null],
    ]);

    expect(r.lines, hasLength(2), reason: 'السطرانِ السليمانِ وحدَهما');
    expect(r.errors, isEmpty, reason: 'الفراغُ ليس خطأً فيُتخطّى صامتاً');
  });

  test('🔴 صفٌّ فارغٌ لا يُزحزح ترقيمَ الصفِّ الذي يليه', () {
    final r = summarizeBankStatementRows([
      [DateTime(2026, 5, 1), 'A', '', 0, 100],
      [],
      ['تاريخٌ فاسد', 'B', '', 0, 50],
    ]);

    expect(r.lines, hasLength(1));
    expect(r.errors, hasLength(1), reason: 'الفراغُ لا يُحتسَب خطأً');
    expect(r.errors.first, contains('٣'),
        reason: 'الصفُّ الفاسدُ هو الثالثُ فعليّاً رغم تخطّي الثاني الفارغ');
  });

  // ═════════════════════════════════════════════════════════════════════════
  // مراجعةٌ 2026-09-01 (مأخذ ٨) — التخطّي كان `row[0] == null`، أي فحصاً
  // للعمود الأوّل وحدَه.
  // ═════════════════════════════════════════════════════════════════════════
  test('🔴 صفٌّ بتاريخٍ فارغٍ وبياناتٍ حقيقيّةٍ يُقال عنه، لا يُبتلَع فراغاً',
      () {
    final r = summarizeBankStatementRows([
      [DateTime(2026, 5, 1), 'A', '', 0, 100],
      [null, 'B', 'إيداعٌ حقيقيٌّ بلا تاريخ', 0, 750],
    ]);

    expect(r.lines, hasLength(1), reason: 'السليمُ وحدَه يُدرَج');
    expect(r.errors, hasLength(1),
        reason: 'حركةٌ بنكيّةٌ بمبلغٍ حقيقيٍّ لا تختفي لأنّ خانةَ التاريخ '
            'فارغة — تُقال ويصلحها المحاسب');
    expect(r.errors.first, contains('التاريخ'),
        reason: 'والسببُ يُسمّى: «التاريخُ غيرُ مقروء» لا صمتٌ');
  });

  // ═════════════════════════════════════════════════════════════════════════
  // مراجعةٌ 2026-09-01 (مأخذ ٤) — القالبُ كان يحمل صفَّ **مثالٍ** ثالثاً
  // (‏`2026-05-10 · REF-1 · إيداع نقدي · 0 · 500`) و`pickAndParseBankStatement`
  // تتخطّى صفّين. فمن ملأ القالبَ دون أن يحذف المثالَ بيده أدرج سطرَ كشفٍ
  // ملفَّقاً بـ٥٠٠ دائن — قابلاً لأن تلتقطه المطابقةُ الآليّة.
  //
  // ⚠️ **ولم يكن في المستودع اختبارٌ واحدٌ يصل القالبَ بالمحلِّل** — وهو عينُ
  // الفجوة التي مرَّ منها. وهذا الاختبارُ هو تلك المرساة: يمرّر مخرَجَ
  // `bankStatementTemplateRows` (‏عينَ ما تكتبه `exportBankStatementTemplate`)
  // عبر `summarizeBankStatementRows` بعددِ التخطّي الذي يستعمله المستوردُ
  // نفسُه.
  // ═════════════════════════════════════════════════════════════════════════
  group('القالبُ ↔ المحلِّل', () {
    List<List<dynamic>> templateRows() =>
        bankStatementTemplateRows().map((r) => r.map<dynamic>((c) => c).toList()).toList();

    // ⚠️ **هذا التوكيدُ أوّلاً لأنّه هو الذي يسقط** إن عاد صفُّ المثال:
    // جرّبتُ اشتقاقَ عددِ التخطّي من طول القالب، فمرَّت المرساةُ التاليةُ
    // **خضراءَ على العطب نفسِه** (الصفُّ الثالثُ صار مُتخطّىً بحكم طوله).
    // فالعقدُ رقمٌ ثابتٌ، وطولُ القالب يُقاس عليه.
    test('🔴 القالبُ صفّان بالضبط — بقدر ما يتخطّاه المحلِّل', () {
      expect(bankStatementTemplateRows(), hasLength(bankStatementTemplateSkipRows),
          reason: 'كلُّ صفٍّ في القالب فوق عددِ التخطّي يُقرأ حركةً بنكيّةً '
              'حقيقيّة، وكلُّ صفٍّ دونه يبتلع أوّلَ سطرٍ يكتبه المحاسب');
    });

    test('🔴 والقالبُ الفارغُ لا يُنتج سطراً ولا خطأً', () {
      final r = summarizeBankStatementRows(templateRows(),
          skipRows: bankStatementTemplateSkipRows);

      expect(r.lines, isEmpty,
          reason: 'صفُّ المثال كان يُستورَد حركةً بنكيّةً حقيقيّةً بـ٥٠٠ '
              'دائن — قالبٌ فارغٌ يجب أن يُنتج صفراً من الأسطر');
      expect(r.errors, isEmpty,
          reason: 'وسطرُ الشرح والرؤوسُ يُتخطّيان — لا يُعَدّان صفوفاً '
              'فاسدة');
    });

    test('🔴 وصفٌّ واحدٌ يُملأ تحته يُقرَأ سطراً واحداً بالضبط', () {
      // ⚠️ هذا التوكيدُ هو ما يجعل الأوّلَ قادراً على السقوط بسببٍ صحيح:
      // «صفرُ أسطرٍ» وحدَه يمرّ أيضاً لو انكسر التخطّي فابتلع صفَّ البيانات.
      // فالمقيسُ هنا أنّ عددَ التخطّي يطابق ارتفاعَ رأس القالب تماماً — لا
      // أقلَّ (فيُقرأ الرأسُ حركةً) ولا أكثرَ (فتُبتلَع أوّلُ حركة).
      final rows = templateRows()
        ..add([DateTime(2026, 5, 10), 'REF-9', 'إيداع', 0, 500]);
      final r = summarizeBankStatementRows(rows,
          skipRows: bankStatementTemplateSkipRows);

      expect(r.lines, hasLength(1));
      expect(r.errors, isEmpty);
      expect(r.lines.first['credit'], 500.0);
    });
  });
}

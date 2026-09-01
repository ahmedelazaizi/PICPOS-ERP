// تحليلُ صفِّ الكشف نقيٌّ عن قصد — كـ`reportCellValue` و`reportBranchLabel`:
// موضعُ الكذب المحتمل يجب أن يُقاس بلا قاعدةٍ ولا نظامِ ملفّات.
//
// ⚠️ **«مدين/دائن» من منظور البنك**: المحرّكُ يقلبهما عند المطابقة (مدينُ
// البنك = دائنُ دفترنا). فالتحليلُ ينقل ما في العمودَين كما هو، والقالبُ
// يحمل سطرَ الشرح.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/services/bank_statement_row.dart';

void main() {
  test('مرساة: صفٌّ سليمٌ يُقبَل بحقوله', () {
    final r = parseBankStatementRow(
        [DateTime(2026, 5, 10), 'REF-1', 'إيداع نقدي', 0, 500]);

    expect(r.error, isNull, reason: 'الصفُّ السليمُ يجب أن يُقبَل');
    expect(r.line!['reference'], 'REF-1');
    expect(r.line!['credit'], 500.0);
    expect(r.line!['debit'], 0.0);
    expect(r.line!['date'], DateTime(2026, 5, 10));
  });

  test('التاريخُ نصّاً `yyyy-MM-dd` يُقبَل', () {
    final r = parseBankStatementRow(['2026-05-10', 'R', '', 0, 5]);
    expect(r.error, isNull);
    expect(r.line!['date'], DateTime(2026, 5, 10));
  });

  test('🔴 تاريخٌ فاسدٌ يُرفَض بسببه لا يُطرَح', () {
    final r = parseBankStatementRow(['العاشر من مايو', 'R', '', 0, 5]);
    expect(r.line, isNull);
    expect(r.error, contains('التاريخ'));
  });

  test('🔴 مدينٌ ودائنٌ معاً يُرفَض', () {
    final r = parseBankStatementRow([DateTime(2026, 5, 10), 'R', '', 100, 50]);
    expect(r.line, isNull);
    expect(r.error, contains('مدين'));
  });

  test('🔴 صفرٌ في الاثنين يُرفَض — سطرٌ بلا حركة', () {
    final r = parseBankStatementRow([DateTime(2026, 5, 10), 'R', '', 0, 0]);
    expect(r.line, isNull);
    expect(r.error, isNotNull);
  });

  test('صفٌّ أقصرُ من خمسةِ أعمدةٍ يُرفَض ولا يرمي', () {
    final r = parseBankStatementRow([DateTime(2026, 5, 10), 'R']);
    expect(r.line, isNull);
    expect(r.error, isNotNull);
  });

  test('المبلغُ السالبُ يُرفَض — الإشارةُ يحملها العمود', () {
    final r = parseBankStatementRow([DateTime(2026, 5, 10), 'R', '', 0, -5]);
    expect(r.line, isNull);
    expect(r.error, isNotNull);
  });

  // ═════════════════════════════════════════════════════════════════════════
  // مراجعةٌ 2026-09-01 (مأخذ ١) — مبلغُ كلِّ سطرٍ كان يُجرَّد من الفاصلة بلا
  // فحصِ موضعها: `double.tryParse(s.replaceAll(',', ''))`.
  //
  // ⚠️ **الصفُّ كان يُقبَل ويُعَدُّ في «استُورد N سطراً»** — فلا خطأَ يظهر
  // ولا سببَ يُقال، والرقمُ الخاطئُ يدخل رصيدَ الكشف والمطابقةَ الآليّة.
  // وهذا عينُ العطب الذي أُصلح طبقةً أعلى في `parseStatementBalance`
  // (الكوميت c1851304): حُرس رقمُ رصيدِ الكشف الواحد، وتُرك مبلغُ **كلِّ
  // سطرٍ** في الملفّ.
  //
  // والمقيسُ هنا هو الفرقُ بين قبولٍ صحيحٍ وقبولٍ **مئةَ ضعف** — لا مجرّدُ
  // «لم يرمِ».
  // ═════════════════════════════════════════════════════════════════════════
  group('مبلغُ السطر — الفاصلةُ تُقرأ بموضعها لا تُجرَّد', () {
    double? creditOf(dynamic cell) {
      final r = parseBankStatementRow([DateTime(2026, 5, 10), 'R', '', 0, cell]);
      return r.line?['credit'] as double?;
    }

    test('مرساة: "1,000.50" — فاصلةُ آلافٍ ونقطةٌ عشريّة ⇒ 1000.5', () {
      expect(creditOf('1,000.50'), 1000.5,
          reason: 'التدوينُ الإنجليزيُّ يجب أن يُقرأ كما هو');
    });

    test('🔴 "1500,50" — عشريّةٌ أوروبيّة ⇒ 1500.5، **لا 150050**', () {
      // ⚠️ القرارُ الموثَّق: تُقبَل ولا تُرفَض. القاعدةُ المنسوخةُ من
      // `_cellToNum` تقرأ فاصلةً واحدةً بذيلٍ غيرِ ثلاثيٍّ عشريّةً أوروبيّة،
      // وهي القراءةُ الوحيدةُ الممكنة. والمقصودُ إعدامُ «المئةِ ضعف» لا
      // إعدامُ الصفّ. والتوكيدُ الحاسمُ هو النفيُ الثاني.
      expect(creditOf('1500,50'), 1500.5);
      expect(creditOf('1500,50'), isNot(150050.0),
          reason: 'التجريدُ الأعمى للفاصلة كان يُنتج 150050 — مئةَ ضعف');
    });

    test('🔴 "1.500,00" — نقطةُ آلافٍ وفاصلةٌ عشريّة ⇒ 1500.0، **لا 1.5**',
        () {
      // كان `"1.500,00".replaceAll(',', '')` يعطي `"1.50000"` وهو يُحلَّل
      // بنجاح إلى 1.5 — فتُقبَل ألفٌ وخمسمئةٌ على أنّها جنيهٌ ونصف.
      expect(creditOf('1.500,00'), 1500.0);
      expect(creditOf('1.500,00'), isNot(1.5),
          reason: 'التجريدُ الأعمى كان يُنتج 1.5 — واحدٌ من ألف');
    });

    test('🔴 "NaN" نصّاً يُرفَض — لا يمرّ عدداً غيرَ ماليّ', () {
      // `double.tryParse("NaN")` يُرجع `NaN`، و`NaN < 0` و`NaN > 0` و
      // `NaN == 0` كلُّها `false` — فكان الصفُّ يفلت من فحوص الرفض الثلاثة
      // كلِّها ويُخزَّن، فيُعدي كلَّ جمعٍ بعده.
      final r = parseBankStatementRow([DateTime(2026, 5, 10), 'R', '', 0, 'NaN']);
      expect(r.line, isNull);
      expect(r.error, isNotNull);
    });

    test('🔴 `double.nan` **عدداً** يُرفَض — الفحصُ على مسار num أيضاً', () {
      // خليّةٌ رقميّةٌ لا تمرّ بالتحليل النصّيّ إطلاقاً، ففحصُ النصّ وحدَه
      // كان يترك هذا البابَ مفتوحاً.
      final r =
          parseBankStatementRow([DateTime(2026, 5, 10), 'R', '', 0, double.nan]);
      expect(r.line, isNull, reason: 'NaN ليست مبلغاً — ولا تُقارَن بصفر');
    });

    test('🔴 `double.infinity` عدداً يُرفَض كذلك', () {
      final r = parseBankStatementRow(
          [DateTime(2026, 5, 10), 'R', '', 0, double.infinity]);
      expect(r.line, isNull);
    });

    test('🔴 والسالبُ نصّاً يبقى مرفوضاً بعد النقل', () {
      // ⚠️ `normalizeNumericCellText` تقبل السالبَ، فالرفضُ هنا شرطُ
      // `_asAmount` نفسِه — ولو سقط لمرّت الإشارةُ في الرقم بدل العمود.
      final r =
          parseBankStatementRow([DateTime(2026, 5, 10), 'R', '', 0, '-5.00']);
      expect(r.line, isNull);
      expect(r.error, isNotNull);
    });

    test('والأرقامُ العربيّةُ تُقبَل — نفعُ النقل لا كلفتُه', () {
      expect(creditOf('٥٠٠'), 500.0);
    });
  });
}

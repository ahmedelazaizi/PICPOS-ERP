// حارسُ العقد: **دفترُ الشيكات — ترقيمٌ يُسحَب ولا يُكتَب بيد.**
//
// ═══ ما يُحرَس هنا ولماذا ═══
//
// ‏١) 🔴 **الرقمُ يُسحَب من الدفتر ويصل الورقة.** النموذجُ **يعاين** والمعاملةُ
//    **تسحب**، فلو كتب المضيفُ ما عاينه النموذجُ بقي `next_number` مكانَه
//    ولم يتقدّم الدفترُ **أبداً** — ويُصدَر الرقمُ نفسُه لكلّ مورّد. ولا
//    شيءَ يبدو معطوباً: الشيكُ يُكتَب، والسندُ يُرحَّل، والدفترُ يعرض
//    «التالي» كما هو.
//
// ‏٢) 🔴 **والسحبُ قبل أيّ كتابةٍ ماليّة**: الأرقامُ تدخل وصفَ السند وأرقامَ
//    الأوراق معاً، فسحبٌ بعدَها يترك سنداً يصف أرقاماً غيرَ التي كُتبت.
//
// ‏٣) 🔴 **وترتيبُ السحب في `pullTables`**: `commercial_papers.cheque_book_id`
//    تشير إلى `cheque_books`، و`_upsertRow` يكتب بالترتيب و
//    `PRAGMA foreign_keys = ON` في الإنتاج — **والخطأُ مبتلَعٌ بـ`debugPrint`**.
//    فشيكٌ يسبق دفترَه يُسقَط صامتاً.
//
// ‏٤) 🔴 **ولا حذفَ للدفتر** — الأوراقُ تشير إليه.
//
// ‏٥) **والتوصيلُ ستّةُ مواضع.**

import 'package:flutter_test/flutter_test.dart';
import '../helpers/api_handler_source.dart';
import '../helpers/library_source.dart';
import 'package:picpos_erp/core/enums/app_screen.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';
import 'package:picpos_erp/core/navigation/screen_registry.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';
import 'package:picpos_erp/services/id_namespace_service.dart';

String _code(String path) => [
  for (final line
      in (path == 'lib/services/api/api_handler.dart'
              ? readApiHandlerSource()
              : readLibrarySource(path))
          .split('\n'))
    if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
].join('\n');

int _count(String haystack, String needle) {
  var n = 0;
  var i = haystack.indexOf(needle);
  while (i != -1) {
    n++;
    i = haystack.indexOf(needle, i + needle.length);
  }
  return n;
}

const _payment =
    'lib/presentation/treasury_picpos/screens/payment_voucher_picpos_screen.dart';
const _dao = 'lib/data/database/daos/cheque_books_dao.dart';
const _screen =
    'lib/presentation/treasury_picpos/screens/cheque_books_picpos_screen.dart';
const _form =
    'lib/presentation/treasury_picpos/screens/voucher_form_picpos.dart';

void main() {
  test('🔴 سندُ الصرف يسحب من الدفتر ويكتب ما سُحب', () {
    final code = _code(_payment);

    expect(
      _count(code, 'allocateChequeNumbers('),
      1,
      reason:
          '🔴 بلا السحب يبقى `next_number` مكانَه ويُصدَر الرقمُ نفسُه '
          'لكلّ مورّد — والشيكُ يُكتَب والسندُ يُرحَّل فلا شيءَ يبدو معطوباً',
    );

    // 🔴 **يُعَدُّ الأثرُ لا يُنفى الاسم.** الكتابةُ **مزدوجةٌ** (الخادمُ ثمّ
    //    المحلّيُّ بنفس المعرّف)، فالرقمُ المسحوبُ يجب أن يصل **كلتيهما**.
    //    وواحدةٌ تكفي لتذهب الورقةُ إلى الخادم برقمٍ ومحلّيّاً بآخر.
    expect(
      _count(code, 'paperNumber: number'),
      2,
      reason: '🔴 كتابةٌ من الكتابتَين تستعمل رقمَ المعاينة لا المسحوب',
    );
    expect(
      code.contains('paperNumber: c.number'),
      isFalse,
      reason: '🔴 رقمُ المعاينة يصل الورقةَ — والدفترُ تقدّم إلى غيره',
    );

    // والورقةُ تحمل دفترَها، وإلّا تقدّم الدفترُ وبقي مصدرُها مجهولاً.
    expect(
      code.contains('chequeBookId: v.chequeBookId'),
      isTrue,
      reason:
          '🔴 `cheque_book_id` عمودُ v174 يبقى بلا كاتبٍ — وهي عينُ '
          'العلّة التي بُني هذا كلُّه لها',
    );
  });

  test('🔴 والسحبُ قبل أوّل كتابةٍ ماليّة', () {
    final code = _code(_payment);
    final draw = code.indexOf('await _drawNumbers(v)');
    // E-fix ١ — أوّلُ كتابةٍ ماليّةٍ صارت حمولةَ السند الكاملة إلى الخادم.
    final expense = code.indexOf('ClientVoucherInterceptor.submit(');
    expect(draw, greaterThan(-1));
    expect(expense, greaterThan(-1));
    expect(
      draw,
      lessThan(expense),
      reason:
          '🔴 السحبُ بعد كتابة السند يترك سنداً يصف أرقاماً غيرَ التي '
          'كُتبت على الأوراق',
    );
  });

  test('🔴 وما سُحب يُقال عند الفشل', () {
    final code = _code(_payment);
    // 🔴 الفشلُ بعد السحب يترك أرقاماً مستهلَكةً بلا شيكٍ يقابلها. وصمتٌ
    //    عنها يجعل المستخدمَ يعيد المحاولةَ ظانّاً أنّه يكتب نفسَ الرقم.
    expect(code.contains('_drawn'), isTrue);
    expect(
      _count(code, '_drawn = drawn'),
      1,
      reason: 'المسحوبُ لا يُسجَّل فلا تُقال الأرقامُ المحترقة',
    );
    expect(
      _count(code, '_drawn.isEmpty'),
      1,
      reason: 'رسالةُ الفشل لا تقرأ ما سُحب',
    );
  });

  group('🔴 المحرّكُ يحكم على المدى', () {
    final code = _code(_dao);

    test('والفحصُ داخلَ المعاملة لا في الشاشة', () {
      // فحصُ الشاشة سباقٌ: جهازان يفتحان دفترَين متداخلَين في نفس اللحظة
      // وكلاهما قرأ القائمةَ قبل كتابة الآخر.
      expect(
        _count(code, 'findChequeRangeOverlap('),
        1,
        reason:
            '🔴 بلا فحصِ تداخلٍ في المحرّك يُفتَح دفتران على نفس المدى '
            '— ورقمٌ مكرَّرٌ في شيكٍ صادرٍ يصل البنك',
      );
      final at = code.indexOf('_assertChequeBookSane');
      expect(at, greaterThan(-1));
      // والفحصُ يُنادى من الفتح ومن التعديل معاً.
      expect(
        _count(code, 'await _assertChequeBookSane('),
        2,
        reason: 'مسارٌ من المسارَين يكتب مدًى بلا فحص',
      );
    });

    test('و«التالي» يُكتَب في موضعَين لا أكثر — الإنشاءُ والسحب', () {
      // ⚠️ `nextNumber: Value(` في التعديل والسحب؛ والإنشاءُ يمرّره خاماً.
      //    كاتبٌ ثالثٌ يعني قاعدةً ثانيةً لتقدّم الدفتر.
      expect(
        _count(code, 'nextNumber: Value('),
        2,
        reason: 'كاتبٌ إضافيٌّ لـ`next_number` ⇒ قاعدتان لتقدّم الدفتر',
      );
      expect(
        _count(code, 'transaction(() async {'),
        4,
        reason: 'كتابةٌ خارجَ معاملةٍ ⇒ قراءةٌ ثمّ كتابةٌ يتخلّلهما غيرُهما',
      );
    });

    test('🔴 ولا حذفَ للدفتر — الأوراقُ تشير إليه', () {
      expect(
        code.contains('delete(chequeBooks)'),
        isFalse,
        reason: '🔴 حذفُ دفترٍ يُيتّم كلَّ شيكٍ صُرف منه',
      );
      expect(_code(_screen).contains('deleteChequeBook'), isFalse);
      expect(
        _count(code, 'setChequeBookCancelled'),
        1,
        reason:
            'الإلغاءُ هو البديلُ — وبلا كاتبٍ له لا سبيلَ لإيقاف دفترٍ '
            'ضاع',
      );
    });

    test('والحالةُ مشتقّةٌ لا مكتوبةٌ بيد', () {
      // `resolveChequeBookStatus` في الإنشاء والتعديل والإلغاء والسحب.
      expect(
        _count(code, 'resolveChequeBookStatus('),
        4,
        reason:
            'مسارٌ يكتب حالةً بيده ⇒ دفترٌ نفد يبقى «نشطاً» يُعرَض '
            'للسحب ولا يُسحَب منه',
      );
    });
  });

  test('⚠️ والمعاينةُ مقفولةٌ في النموذج', () {
    final code = _code(_form);
    // ⚠️ حقلٌ يُكتَب فيه رقمٌ ثمّ يُستبدَل عند الحفظ يكذب على من كتبه.
    expect(_count(code, "Key('voucher_cheque_preview_"), 1);
    expect(code.contains('_previewChequeNumber'), isTrue);
    // و«بلا دفتر» خيارٌ صريحٌ يبقى: دفاترُ قديمةٌ لم تُسجَّل، وشيكٌ مصرفيٌّ
    // من غير دفترنا.
    expect(
      code.contains('بلا دفتر'),
      isTrue,
      reason:
          'منعُ الكتابة بيدٍ يوقف الصرفَ حتى يُسجَّل كلُّ دفترٍ في '
          'الدرج',
    );
  });

  // 🔴 **طفرةٌ نجت حتى شُدَّ هذا**: حذفُ `isExpanded` من منتقي الدفتر في
  //    النموذج مرّ أخضرَ — مراسي التركيب تقيس ١١٠٠ و١٤٤٠ و١٩٢٠ وعندها
  //    البطاقةُ أوسعُ من أن تفيض، فالفيضُ لا يقع هناك أصلاً.
  //
  //    والصوابُ أنّ هذه **قاعدةُ ملفٍّ** لا احتياط: `DropdownButton` يبني
  //    صفّاً `mainAxisSize: min` بدونها، فالمحتوى يلتصق بجانبٍ ولا يملأ
  //    الحقلَ — يبدو مكسوراً بجوار بقيّة الحقول — **ويفيض** حيث يضيق العرض.
  //    وقد وقع فعلاً في لوح دفتر الشيكات (٢٨ بكسلاً).
  test('🔴 وكلُّ منسدلةٍ في الشاشتَين تملأ حقلَها', () {
    for (final f in [_form, _screen]) {
      final code = _code(f);
      final fields = _count(code, 'DropdownButtonFormField');
      expect(fields, greaterThan(0), reason: 'لا منسدلةَ في $f — نمطٌ تبدّل');
      expect(
        _count(code, 'isExpanded: true'),
        fields,
        reason:
            '🔴 منسدلةٌ لا تملأ حقلَها في $f — تفيض حيث يضيق العرض، '
            'وتبدو مكسورةً بجوار بقيّة الحقول حيث لا تفيض',
      );
    }
  });

  group('🔴 توصيلُ المزامنة — القوائمُ الخمس', () {
    test('و`cheque_books` في مساري السحب ومُشغِّلات PostgreSQL', () {
      expect(DeltaPullService.pullTables, contains('cheque_books'));
      // بلا استراتيجيّةٍ في `fullSync` ⇒ يجب أن يكون محميّاً من البذر، وإلّا
      // لم يرَ جهازٌ جديدٌ دفتراً فُتح قبل إقلاعه **أبداً** — فيفتح دفتراً
      // بنفس المدى.
      expect(DeltaPullService.deltaOnlyTables, contains('cheque_books'));
      expect(
        IdNamespaceService.namespacedTables,
        contains('cheque_books'),
        reason:
            'بلا أرضيّةِ ترقيمٍ يبدأ العميلُ من ١ فيصطدم دفترُه بدفتر '
            'الخادم، و`commercial_papers` تشير إلى معرّفٍ صار يدلّ على '
            'دفترٍ آخر',
      );
      expect(AppDatabase.syncHardenedTablesForTest, contains('cheque_books'));
      expect(
        _code('lib/services/api/api_handler.dart').contains("'cheque_books'"),
        isTrue,
        reason: 'الخادمُ لا يسلّم صفوفَه فلا يصل الدفترُ أيَّ جهازٍ آخر',
      );
    });

    test('🔴 والدفترُ يسبق أوراقَه في الترتيب', () {
      final book = DeltaPullService.pullTables.indexOf('cheque_books');
      final papers = DeltaPullService.pullTables.indexOf('commercial_papers');
      expect(book, greaterThan(-1));
      expect(papers, greaterThan(-1));
      expect(
        book,
        lessThan(papers),
        reason:
            '🔴 `commercial_papers.cheque_book_id` مفتاحٌ خارجيّ، '
            'و`_upsertRow` **يبتلع** خطأَ المفتاح بـ`debugPrint` ويمضي — '
            'فكلُّ شيكٍ من دفترٍ يُسقَط صامتاً ولا يظهر في أيّ اختبار',
      );
    });

    test('⚠️ وهو مرجعيٌّ فخارجَ قائمتَي المنع التعاملَيّتَين', () {
      // ⚠️ **قرارٌ لا سهو**: القائمتان قائمتا **منعٍ** للبيانات التعامليّة،
      //    والمرجعيُّ خارجَهما ليعمل التزويدُ قبل الدخول — كما `safes` و
      //    `accounts` و`asset_categories`. والدفترُ بلا مبالغَ ولا أطرافٍ
      //    ولا أرصدة، وحسابُه البنكيُّ يُسلَّم أصلاً ضمن `accounts`.
      expect(
        DeltaPullService.branchScopedPullTables,
        isNot(contains('cheque_books')),
      );
    });
  });

  group('والتوصيلُ ستّةُ مواضع', () {
    test('«دفتر الشيكات»', () {
      expect(ScreenId.chequeBooks.navigationIndex, 70);
      expect(AppScreen.chequeBooks.value, ScreenId.chequeBooks.navigationIndex);
      // ⚠️ `treasury_view` عن قصد: `treasury_manage` **غيرُ ممنوحةٍ لأيّ
      //    دور** في `RoleGrantMatrix.defaultGrants` — نفسُ فخِّ
      //    `treasury_receipts_create`.
      expect(screenPermissionMap[ScreenId.chequeBooks], 'treasury_view');
      expect(ScreenRegistry.unified, contains(ScreenId.chequeBooks));
      expect(
        _code(
          'lib/app_main_screen.dart',
        ).contains('appScreen: AppScreen.chequeBooks,'),
        isTrue,
      );
      final item = kAllNavItemDefs.where((n) => n.index == 70).toList();
      expect(
        item,
        hasLength(1),
        reason: 'بلا مدخلٍ هنا لا يراها المستخدمُ مهما صحّ الباقي',
      );
      expect(item.single.label, 'دفتر الشيكات');
      expect(item.single.group, 'accounting');
      expect(item.single.permission, 'treasury_view');
    });

    test('والكتابةُ على صلاحيّةٍ ممنوحةٍ فعلاً', () {
      // 🔴 `treasury_manage` ليست في `defaultGrants`، و`commercial_papers_manage`
      //    ممنوحةٌ لـ«مدير مالي» — وربطُ الأزرار بالأولى كان يُخفيها عن
      //    الجميع.
      final code = _code(_screen);
      expect(
        _count(code, 'PermissionCodes.commercialPapersManage'),
        3,
        reason: 'زرُّ كتابةٍ بلا حارسٍ أو بحارسٍ لا يصل أحداً',
      );
      expect(
        code.contains('PermissionCodes.treasuryManage'),
        isFalse,
        reason: '🔴 صلاحيّةٌ غيرُ ممنوحةٍ لأحدٍ تُخفي الأزرارَ عن الجميع',
      );
    });
  });
}

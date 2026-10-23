// حارسُ العقد: **طلبُ استبعاد أصل — مسوّدةٌ بلا أثر، واعتمادٌ يحرّك درجاً.**
//
// ═══ ما يُحرَس هنا ولماذا ═══
//
// ‏١) 🔴 **المسوّدةُ بلا أيّ أثرٍ محاسبيّ.** زرٌّ يقول «حفظ مسودة» ويُخرج
//    أصلاً من الدفاتر يجعل المستخدمَ يظنّ أنّه أجّل قراراً وقد وقع.
//
// ‏٢) 🔴 **والنقديُّ يحرّك خزنةً.** `disposeAsset` القائمةُ تقيّد مدينَ
//    نقديّةٍ على `1111` **ولا تحرّك خزنةً إطلاقاً** — فيزيد النقدُ في
//    الأستاذ ولا يزيد في أيّ درج، ويفترق رصيدُ الخزينة عن دفترها من أوّل
//    أصلٍ يُباع. ولا شيءَ يبدو معطوباً: القيدُ متّزنٌ والأصلُ خرج.
//
// ‏٣) 🔴 **والآجلُ يرفع رصيدَ الطرف.** ذمّةٌ في الأستاذ وحدَها لا تُطالِب
//    أحداً: كشوفُ الحساب وحدُّ الائتمان يقرآن `parties.balance`.
//
// ‏٤) 🔴 **وحسابا الفئة صريحان أو لا اعتماد.** `_getCategoryAssetAccount`
//    تسقط إلى `1211` (الأراضي) و`_getCategoryDepreciationAccount` إلى
//    `1218` (مجمّع إهلاك المباني) — فيُدائَن «الأراضي» بتكلفة حاسوبٍ وتبقى
//    الميزانيّةُ مُحرَّفةً بلا أثرٍ يدلّ على الخطأ.
//
// ‏٥) 🔴 **والبيعُ `sold`**: الرمزُ مقروءٌ في سبعة مواضعَ وكان بلا كاتب.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/api_handler_source.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';
import 'package:picpos_erp/services/id_namespace_service.dart';

String _code(String path) => [
      for (final line in (path == 'lib/services/api/api_handler.dart'
              ? readApiHandlerSource()
              : File(path).readAsStringSync())
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

/// مقطعٌ بين علامتين — أدقُّ من قصِّ الجسم بقوس، وقد أخطأ ذاك من قبل حين
/// طابق `\n  }) async {` في التوقيع.
/// ⚠️ **ولا `expect` هنا**: تُنادى عند إعلان المجموعات لا داخلَ اختبار،
///    و`expect` خارجَ اختبارٍ يرمي `OutsideTestException` فيسقط الملفُّ
///    كلُّه عند التحميل — ويبدو الحارسُ معطوباً لا الشيفرةُ.
String _between(String code, String from, String to) {
  final a = code.indexOf(from);
  if (a < 0) throw StateError('العلامةُ «$from» اختفت من المصدر');
  final b = code.indexOf(to, a);
  if (b <= a) throw StateError('العلامةُ «$to» اختفت من المصدر');
  return code.substring(a, b);
}

const _dao = 'lib/data/database/daos/asset_disposals_dao.dart';
const _form =
    'lib/presentation/fixed_assets_picpos/screens/asset_disposal_request_picpos.dart';
const _screen =
    'lib/presentation/fixed_assets_picpos/screens/fixed_assets_picpos_screen.dart';

void main() {
  final dao = _code(_dao);

  test('🔴 المسوّدةُ بلا أيّ أثرٍ محاسبيّ', () {
    final draft = _between(
      dao,
      'Future<int> createAssetDisposalRequest(',
      'Future<void> updateAssetDisposalRequest(',
    );
    for (final effect in const [
      'createJournalEntry',
      'createSafeTransaction',
      'adjustPartyBalance',
      'FixedAssetsCompanion',
    ]) {
      expect(draft.contains(effect), isFalse,
          reason: '🔴 «$effect» في مسار المسوّدة — والزرُّ يقول «حفظ مسودة»، '
              'فيظنّ المستخدمُ أنّه أجّل قراراً وقد وقع');
    }
  });

  group('🔴 الاعتمادُ يقع كاملاً', () {
    final approve = _between(
        dao, 'Future<void> approveAssetDisposal(', 'Future<FixedAssetData>');

    test('ويحرّك خزنةً في النقديّ', () {
      // 🔴 **يُعَدُّ الأثرُ لا يُنفى الاسم.** حركةٌ واحدةٌ لا أكثر: ثانيةٌ
      //    تضاعف النقدَ الداخل.
      expect(_count(approve, 'createSafeTransaction('), 1,
          reason: '🔴 قيدُ نقديّةٍ بلا حركةِ خزنة — يزيد النقدُ في الأستاذ '
              'ولا يزيد في أيّ درج');
      expect(approve.contains("category: 'asset_disposal'"), isTrue,
          reason: 'الحركةُ بلا تصنيفٍ يميّزها في كشف الخزينة');
    });

    test('🔴 وعلى حساب الخزنة المرتبط لا `1111` عمياء', () {
      expect(approve.contains('safe.linkedAccountId != null'), isTrue,
          reason: '🔴 قيدٌ على الصندوق الرئيسيِّ يَنسب المالَ إلى درجٍ لم '
              'يدخله — وخزائنُ الفروع لها حساباتُها');
    });

    test('ويرفع رصيدَ الطرف في الآجل', () {
      expect(_count(approve, 'adjustPartyBalance('), 1,
          reason: '🔴 ذمّةٌ في الأستاذ وحدَها لا تُطالِب أحداً');
      expect(approve.contains("collectionMethod == 'credit'"), isTrue,
          reason: 'الفرعُ الآجلُ غيرُ مقروءٍ — فيُقيَّد البيعُ نقداً دائماً');
    });

    test('🔴 وحسابا الفئة صريحان — لا سقوطَ إلى «الأراضي»', () {
      expect(_count(approve, '_disposalCategoryAccounts('), 1);
      // 🔴 الساقطتان ممنوعتان في **هذا** الملفّ كلِّه: استعمالُهما يُعيد
      //    السقوطَ إلى `1211`/`1218` من بابٍ آخر.
      expect(dao.contains('_getCategoryAssetAccount('), isFalse,
          reason: '🔴 الساقطةُ إلى «الأراضي» عادت — ويُدائَن حسابُ الأرض '
              'بتكلفة حاسوب');
      expect(dao.contains('_getCategoryDepreciationAccount('), isFalse,
          reason: '🔴 الساقطةُ إلى «مجمّع إهلاك المباني» عادت');
    });

    test('🔴 والبيعُ يُختَم `sold`', () {
      expect(_count(approve, 'assetStatusAfterDisposal('), 1,
          reason: '🔴 `sold` مقروءٌ في سبعة مواضعَ ولا كاتبَ له — فكلُّ مبيعٍ '
              'يُعرَض «إعدام» ومرشِّحُ «بيع» يعدّ صفراً');
      expect(approve.contains("status: const Value('disposed')"), isFalse,
          reason: '🔴 حالةٌ مكتوبةٌ بيدٍ تُلغي التفرقةَ بين بيعٍ وإعدام');
    });

    test('⚠️ ولا يُنادى `disposeAsset` القديمُ من هذا المسار', () {
      // ⚠️ نداؤه يقيّد القيدَ مرّتين: مرّةً بفرعه الناقص ومرّةً هنا.
      expect(dao.contains('disposeAsset('), isFalse);
    });
  });

  test('🔴 والفشلُ يرتدّ — الاعتمادُ كلُّه في معاملةٍ واحدة', () {
    final approve = _between(
        dao, 'Future<void> approveAssetDisposal(', 'Future<FixedAssetData>');
    expect(_count(approve, 'transaction(() async {'), 1,
        reason: '🔴 بلا معاملةٍ واحدةٍ يُختَم الأصلُ «مستبعَداً» ويسقط القيدُ '
            'بعده، فتبقى تكلفتُه في الأستاذ إلى الأبد');
  });

  group('⚠️ والنموذجُ يقول ما يفعل', () {
    final form = _code(_form);

    test('والاسمُ يتبع العلامةَ — لا «خسارة» ثابتة', () {
      // 🔴 التصميمُ يسمّيه «الخسارة المتوقعة» دائماً؛ والحسابُ في
      //    `domain/models` هو مَن يسمّيه.
      expect(form.contains('o.label'), isTrue);
      expect(form.contains("labelText: 'الخسارة المتوقعة'"), isFalse,
          reason: '🔴 عنوانٌ ثابتٌ يعرض ربحاً تحت «خسارة»');
    });

    test('وزرّان لكلٍّ رايتُه', () {
      expect(_count(form, '_submit(approve: false)'), 1);
      expect(_count(form, '_submit(approve: true)'), 1,
          reason: '🔴 زرٌّ يقول «اعتماد» ويحفظ مسوّدةً يترك الأصلَ في الدفاتر');
    });

    test('⚠️ والخزنةُ تمنع الاعتمادَ لا المسوّدة', () {
      expect(_count(form, 'draftBlockReason'), greaterThanOrEqualTo(2),
          reason: 'اشتراطُ الخزنة على المسوّدة يمنع تحريرَ طلبٍ يراجعه غيرُ '
              'مَن كتبه');
      expect(form.contains('safeId: 0,'), isTrue,
          reason: 'فحصُ المسوّدة لا يتخطّى الخزنةَ فعلاً');
    });

    test('ورقمُ الطلب لا يُخمَّن', () {
      expect(form.contains('kDisposalNumberPlaceholder'), isTrue);
    });

    test('وكلُّ منسدلةٍ تملأ حقلَها', () {
      final fields = _count(form, 'DropdownButtonFormField');
      expect(fields, greaterThan(0));
      expect(_count(form, 'isExpanded: true'), fields,
          reason: '🔴 منسدلةٌ لا تملأ حقلَها تفيض حيث يضيق العرض');
    });
  });

  test('⚠️ واللوحُ يُفتَح من الشاشة ولا مدخلَ جانبيَّ له', () {
    final screen = _code(_screen);
    expect(screen.contains('AssetDisposalRequestForm('), isTrue,
        reason: 'اللوحُ غيرُ مبلوغٍ من أيّ مكان');
    expect(_count(screen, '_disposalRequestsProvider'), greaterThanOrEqualTo(3),
        reason: 'جدولُ الطلبات أو إبطالُه بعد الحفظ مفقود — والمسوّدةُ تختفي '
            'بإغلاق اللوح فلا مدخلَ يعيد فتحَها');
    expect(screen.contains('ref.invalidate(_disposalRequestsProvider)'), isTrue,
        reason: '🔴 بلا إبطالٍ يبقى الجدولُ يعرض الحالةَ القديمة — طلبٌ '
            'اعتُمد يُعرَض «مسودة» فيُضغَط اعتمادُه ثانيةً');
  });

  group('🔴 توصيلُ المزامنة', () {
    test('و`asset_disposals` في القوائم الخمس', () {
      expect(DeltaPullService.pullTables, contains('asset_disposals'));
      expect(DeltaPullService.deltaOnlyTables, contains('asset_disposals'));
      expect(IdNamespaceService.namespacedTables, contains('asset_disposals'));
      expect(AppDatabase.syncHardenedTablesForTest,
          contains('asset_disposals'));
      expect(
          _code('lib/services/api/api_handler.dart')
              .contains("'asset_disposals'"),
          isTrue);
    });

    test('🔴 والطلبُ يلي أصلَه في الترتيب', () {
      final req = DeltaPullService.pullTables.indexOf('asset_disposals');
      final asset = DeltaPullService.pullTables.indexOf('fixed_assets');
      expect(asset, greaterThan(-1));
      expect(req, greaterThan(asset),
          reason: '🔴 `asset_disposals.asset_id` مفتاحٌ خارجيّ، و`_upsertRow` '
              '**يبتلع** خطأَه بـ`debugPrint` — فكلُّ طلبٍ يُسقَط صامتاً');
    });

    test('⚠️ وهو بياناتُ عملٍ فداخلَ قائمتَي المنع', () {
      // ⚠️ يحمل ثمنَ بيعٍ ومشترياً وسببَ استبعاد — بخلاف `cheque_books`
      //    المرجعيّ. فلا يُسلَّم لمستدعٍ بلا هويّةٍ متحقَّقة.
      expect(DeltaPullService.branchScopedPullTables,
          contains('asset_disposals'));
    });
  });
}

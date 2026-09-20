// جدولٌ خارجَ المزامنة **لا يجوز أن يُكتَب فيه** — وإلّا صار الدَّينُ عطباً.
//
// ═══ لماذا هذا الحارسُ موجود ═══
//
// v174 أنشأت أربعةَ جداولَ لإعادة تصميم الشاشات (بلاغُ المالك 2026-09-18)،
// وشاشاتُها في المراحل ٥–٨. فسُجّلت في `_unsyncedBaseline` بحكمِ «يجب أن
// تُزامَن»، لأنّ توصيلَ مزامنةٍ لجدولٍ فارغٍ قبل أن يُعرَف شكلُ واجهته بناءٌ
// على تخمين: نقطةُ النهاية وحقولُ السلك وحلُّ التعارض تتبع الميزةَ لا تسبقها.
//
// ⚠️ **لكنّ «سنُزامنها لاحقاً» جملةٌ لا تُنفِّذ نفسَها.** وهذا المستودعُ يحمل
// ثلاثَ سوابقَ مقيسةٍ لبنيةٍ شُحنت ولم يصلها كاتبُها أو قارئُها:
//   • رايةُ `table_bill_guest_order_enabled` — قارئٌ وطابورٌ ومحرّكٌ وبانرٌ
//     ونقطتا API وثلاثةَ عشرَ اختبارَ تكاملٍ أخضر، و**صفرُ كُتّابٍ** في `lib/`.
//   • `InvoiceCurrencySelector` — ودجتٌ كاملةٌ بلا مستعملٍ واحد.
//   • `Payments` + `PaymentAllocations` — جدولان واستراتيجيّتا مزامنةٍ
//     وإسقاطةٌ وتبويبٌ كاملٌ يقيسهما، ولا أحدَ يُنشئ صفّاً.
//
// فالحارسُ يقلب الوعدَ إلى دَينٍ يُطالِب بنفسه: **أوّلُ كاتبٍ يظهر لجدولٍ ما
// زال في خطّ الأساس يُسقط البناء**، فيُجبِر على أحد أمرَين — توصيلُ المزامنة،
// أو حذفُ الكاتب. ولا ثالثَ صامت.
//
// ⚠️ **ولا يحرس الجداولَ كلَّها.** خطُّ الأساس فيه ما هو محلّيٌّ بطبعه
// (‏أعمالُ الطابعة مثلاً) وما هو مؤجَّلٌ بقرار مالكٍ صريح — ولتلك كُتّابٌ
// مشروعون. فالقائمةُ هنا **صريحةٌ** لجداولِ v174 وحدَها.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// جداولُ v174 التي تنتظر مزامنتَها — بأسماء أصنافها.
/// ✅ **و`ChequeBooks` خرجت 2026-09-20 (المرحلة ٦ / v175)** — لا بإسقاط
/// السطر بل بأداء الدَّين: استراتيجيّتُها مسارُ الدلتا (‏`deltaOnlyTables`)
/// وهي في القوائم الثماني، ثمّ كُتب أوّلُ كاتبٍ لها. وهذا بالضبط ما وُجد
/// الحارسُ ليُجبِر عليه.
/// ✅ **و`ImportPurchaseDetails` خرجت 2026-09-20 (المرحلة ٨)** — كذلك
/// بأداء الدَّين لا بإسقاط السطر: القوائمُ الخمسُ ثمّ أوّلُ كاتب، والكاتبُ
/// يقع **داخلَ معاملة الفاتورة** لا بعدَها.
/// ✅ **و`FloorPlanItems` خرجت 2026-09-20 (قسمُ ٧)** — كذلك بأداء
/// الدَّين: القوائمُ الخمسُ ثمّ أوّلُ كاتب، وهو [saveFloorPlanLayout] يكتب
/// **مستنداً واحداً في معاملةٍ واحدة** لا سحبةً سحبة.
///
/// ⚠️ **والقائمةُ فرغت اليومَ — ولا تُحذَف الآلة.** الحارسُ وُجد
/// لدفعةِ v174، وأوّلُ جدولٍ يُشحَن غداً بلا مزامنةٍ يُسجَّل هنا
/// فتعود الحلقةُ تعمل. ومرساتاه تعملان على أيّ حال، وتحتهما
/// فحصُ الإغلاق: أربعةُ v174 لها كُتّابٌ **وهي في مسار السحب**.
const _pendingSync = <String>[];

/// جداولُ v174 الأربعة واسمُ كلٍّ منها على السلك.
const _dischargedV174 = <String, String>{
  'AssetDisposals': 'asset_disposals',
  'ChequeBooks': 'cheque_books',
  'FloorPlanItems': 'floor_plan_items',
  'ImportPurchaseDetails': 'import_purchase_details',
};

/// مساراتٌ يُسمح فيها بذكر الجدول: التعريفُ والتوليدُ والهجرةُ والمزامنةُ
/// نفسُها. الكتابةُ الممنوعةُ هي كتابةُ **منتَجٍ** خارجَ هذه.
bool _isExempt(String path) {
  final p = path.replaceAll(r'\', '/');
  return p.contains('/data/database/tables/') ||
      p.endsWith('database.g.dart') ||
      p.contains('/data/database/migrations/') ||
      p.contains('/services/sync/');
}

/// نصُّ الملفّ بلا أسطر التعليق — فشرحُ الدَّين لا يُعَدُّ كاتباً.
String _code(String raw) => [
      for (final line in raw.split('\n'))
        if (!line.trimLeft().startsWith('//')) line,
    ].join('\n');

void main() {
  late List<({String path, String code})> sources;

  setUpAll(() {
    sources = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart') && !_isExempt(f.path))
          (path: f.path, code: _code(f.readAsStringSync())),
    ];
  });

  test('مرساةٌ — شجرةُ المصدر قُرئت غيرَ فارغة', () {
    expect(sources.length, greaterThan(300),
        reason: 'قُرئ عددٌ ضئيلٌ من الملفّات — الفحوصُ تحته تقرأ لا شيء');
  });

  test('مرساةٌ — النمطُ يمسك كاتباً حقيقيّاً قائماً', () {
    // بلا هذه المرساة يمرّ الحارسُ أخضرَ لأنّ صيغةَ الكتابة تبدّلت، لا لأنّ
    // الجداولَ نظيفة. و`PurchaseReturnsCompanion` يُكتَب فعلاً في
    // `accounting_autopost_dao.dart`.
    final hits = sources.where((s) =>
        s.code.contains('PurchaseReturnsCompanion'));
    expect(hits, isNotEmpty,
        reason: 'لم أجد كاتباً معروفاً — نمطُ `<Table>Companion` تبدّل '
            'فالحارسُ كلُّه صار عمياء');
  });

  for (final table in _pendingSync) {
    test('ولا كاتبَ لـ$table قبل مزامنته', () {
      final writers = <String>[
        for (final s in sources)
          if (s.code.contains('${table}Companion'))
            s.path.replaceAll(r'\', '/'),
      ];
      expect(writers, isEmpty,
          reason: 'ظهر كاتبٌ لـ$table وهو ما زال في `_unsyncedBaseline`:\n'
              '  ${writers.join('\n  ')}\n\n'
              'فإمّا تُوصَل مزامنتُه الآن (استراتيجيّةٌ + نقطةُ نهايةٍ + '
              'إدراجُه في مساري السحب و`_syncHardenedTables`) ويُحذَف سطرُه '
              'من خطّ الأساس، وإمّا يُؤجَّل الكاتب.\n'
              'وشحنُه كما هو يعني أنّ القيدَ يصل الخادمَ ومستندُه لا — وهي '
              'بعينها الفجوةُ التي وُجد لأجلها `PurchaseReturns`.');
    });
  }

  // ═══ فحصُ الإغلاق — الدَّينُ أُدّي فعلاً لا أُسقِطَ سطرُه ═══
  //
  // خطُّ الأساس فرغ، ولو وُقِف عند هذا لصار الملفُّ أخضرَ بالفراغ:
  // حذفُ أربعةِ أسطرٍ من `pullTables` أو حذفُ كاتبٍ يمرُّ بلا صوت. ففحصُ
  // الإغلاق يقلب التوكيدَ: لكلّ جدولٍ كاتبٌ **وهو في مسار السحب**.
  for (final entry in _dischargedV174.entries) {
    test('وـ${entry.key} لها كاتبٌ بعد أداء الدَّين', () {
      final writers = <String>[
        for (final s in sources)
          if (s.code.contains('${entry.key}Companion')) s.path,
      ];
      expect(writers, isNotEmpty,
          reason: 'جدولٌ خرج من خطّ الأساس ثمّ ذهب كاتبُه — عادت البنيةُ '
              'إلى وعدٍ بلا تنفيذ، وهذا عينُ ما وُجد الحارسُ لأجله');
    });

    test('وـ${entry.value} في مسار السحب', () {
      // النصُّ بلا تعليق: ذكرٌ في شرحٍ وحده ليس إدراجاً في قائمة.
      final code = _code(
          File('lib/services/delta_pull_service.dart').readAsStringSync());
      expect(code.contains("'${entry.value}'"), isTrue,
          reason: 'اسمُ الجدول غاب عن `delta_pull_service` — الصفُّ '
              'يُكتَب محلّيّاً ولا يصل جهازاً آخر');
    });
  }
}

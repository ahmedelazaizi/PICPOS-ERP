// حارسُ العقد: **وحدةُ العمر واحدةٌ، وحركاتُ الأصل كاملةٌ، وملاحظتُه ملكُه.**
//
// ═══ ما يُحرَس هنا ولماذا ═══
//
// ‏١) 🔴 **التحويلُ بين الشهور والسنوات موضعٌ واحدٌ مسمّى.** العمودُ
//    `usefulLifeYears` بالسنوات وتصميمُ المالك `(8)`/`(9)` يعرض «٣٦ شهراً».
//    و`* 12` مكتوبةٌ بيدها في ملفِّ شاشةٍ هي أوّلُ خطوةٍ نحو رقمٍ يعود بالشهور
//    إلى حقلِ سنوات: ٣٦ = إهلاكٌ على ستٍّ وثلاثين سنةً بدل ثلاث، والقيدُ
//    **متّزنٌ على الرقم الخاطئ** فلا فحصَ اتّزانٍ يمسكه.
//
// ‏٢) 🔴 **كلُّ نوعِ قيدٍ يكتبه محرّكُ الأصول موجودٌ في قائمة الحركات.** نوعٌ
//    جديدٌ يُكتَب هناك ولا يُذكَر في `kAssetJeReferenceTypes` يعني حركةً تقع
//    على الأصل ولا تظهر في بطاقته — ولا شيءَ يبدو معطوباً: التبويبةُ تعمل
//    وتعرض ما تعرف.
//
// ‏٣) 🔴 **ولا يُكتَب على `notes` مباشرةً من المحرّك.** العمودُ حقلُ مستخدمٍ،
//    وبطاقةُ الأصل تجعله ظاهراً يُحرَّر. و`Value('…')` مباشرةً تمحو ما كتبه.
//
// ‏٤) **والبطاقةُ لا تستورد `data/database`**: حارسُ
//    `presentation_db_import_guard` يمنع أيَّ ملفِّ عرضٍ جديدٍ من ذلك
//    وقائمتُه مقفولة.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r`.
///
/// ⚠️ **والتعليقُ يُسقَط قبل العدّ**: هذا الملفُّ يعدّ أنماطاً يذكرها الشرحُ
/// فوقَ إصلاحها حرفيّاً.
String _code(String path) => [
      for (final line in File(path).readAsStringSync().split('\n'))
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

const _math = 'lib/domain/models/depreciation_math.dart';
const _types = 'lib/domain/models/asset_movement_types.dart';
const _dao = 'lib/data/database/daos/fixed_assets_dao_ext.dart';
const _repoImpl = 'lib/data/repositories/fixed_assets_repository_impl.dart';
const _repoApi = 'lib/domain/repositories/fixed_assets_repository.dart';
const _card =
    'lib/presentation/fixed_assets_picpos/screens/asset_card_picpos.dart';
const _screen =
    'lib/presentation/fixed_assets_picpos/screens/fixed_assets_picpos_screen.dart';

void main() {
  test('🔴 التحويلُ بين الشهور والسنوات في موضعٍ واحدٍ مسمّى', () {
    final math = _code(_math);
    expect(math.contains('int usefulLifeMonths('), isTrue);
    expect(math.contains('double usefulLifeYearsFromMonths('), isTrue);

    for (final f in [_card, _screen]) {
      final code = _code(f);
      expect(code.contains('usefulLifeYears * 12'), isFalse,
          reason: '🔴 حسابُ شهورٍ بيده في $f — والرقمُ يعود إلى حقل سنوات');
      expect(code.contains('usefulLifeYears / 12'), isFalse,
          reason: 'قسمةٌ بيدها في $f');
    }
    expect(_code(_card).contains('usefulLifeMonths('), isTrue,
        reason: 'البطاقةُ لا تعرض العمرَ بالشهور أصلاً — والتصميمُ يقول '
            '«٣٦ شهراً»');
  });

  test('🔴 وكلُّ نوعِ قيدٍ يكتبه محرّكُ الأصول في قائمة الحركات', () {
    final dao = _code(_dao);
    final types = _code(_types);

    // ⚠️ **القائمةُ تُقرأ من جسمها لا من نصِّ الملفّ.**
    //
    // 🔴 أوّلُ صيغةٍ لهذا الفحص بحثت عن `'asset_transfer'` في **الملفّ
    //    كلِّه**، وإسقاطُ الرمز من القائمة نجا منها: التعريفُ
    //    `const String kAssetJeTransfer = 'asset_transfer';` يبقى فوقها
    //    فتبقى السلسلةُ موجودة. والقائمةُ هي ما يقرؤه الاستعلامُ لا التعريف.
    final body = RegExp(r'kAssetJeReferenceTypes = \[(.*?)\];', dotAll: true)
        .firstMatch(types)
        ?.group(1);
    expect(body, isNotNull, reason: 'قائمةُ الأنواع اختفت أو تغيّر شكلُها');

    final constants = {
      for (final m
          in RegExp(r"const String (\w+) = '([a-z_]+)';").allMatches(types))
        m.group(1)!: m.group(2)!,
    };
    final listed = {
      for (final m in RegExp(r'(kAssetJe\w+)').allMatches(body!))
        if (constants.containsKey(m.group(1))) constants[m.group(1)]!,
    };

    final written = RegExp(r"referenceType: '([a-z_]+)'")
        .allMatches(dao)
        .map((m) => m.group(1)!)
        .toSet();

    expect(written, isNotEmpty,
        reason: 'لم يعد المحرّكُ يكتب نوعاً — النمطُ تغيّر فالفحصُ بلا معنى');
    expect(listed, isNotEmpty, reason: 'القائمةُ فُرِّغت');
    for (final t in written) {
      expect(listed.contains(t), isTrue,
          reason: '🔴 النوعُ «$t» يُكتَب في المحرّك ولا يُذكَر في '
              '`kAssetJeReferenceTypes` — فحركةٌ تقع على الأصل ولا تظهر في '
              'بطاقته، والتبويبةُ تعمل وتعرض ما تعرف');
    }
  });

  test('🔴 والمحرّكُ لا يكتب على `notes` مباشرةً', () {
    final dao = _code(_dao);
    expect(dao.contains('String _assetNoteWith('), isTrue,
        reason: 'أداةُ الإلحاق اختفت');
    expect(_count(dao, '_assetNoteWith('), 3,
        reason: '🔴 تعريفٌ ونداءان (إعادةُ التقييم والنقل). وموضعٌ يكتب '
            '`notes` بيده يمحو ما كتبه المستخدم — والسجلُّ الدائمُ هو القيدُ '
            'لا خانةُ نصٍّ حرّ');
  });

  test('وعمودُ المسؤول موصولٌ في الطبقات الثلاث', () {
    for (final f in [_dao, _repoImpl, _repoApi]) {
      expect(_code(f).contains('custodianUserId'), isTrue,
          reason: 'الطبقةُ $f لا تمرّر المسؤولَ — والعمودُ يبقى بلا كاتب');
      expect(_code(f).contains('clearCustodian'), isTrue,
          reason: 'لا سبيلَ لرفع العهدة في $f — و`null` تعني «لا تلمس»');
    }
  });

  test('🔴 و«كما في» تقرأ لقطةً وتُسقط ما لم يكن قد وُجد', () {
    final screen = _code(_screen);
    expect(screen.contains('assetOnBooksAt('), isTrue,
        reason: '🔴 جردُ تاريخٍ ماضٍ يعرض أصلاً اشتُري بعده — بتكلفته كاملةً');
    expect(screen.contains('_asOfSnapshotsProvider'), isTrue,
        reason: 'المرشِّحُ لا يصل استعلامَ اللقطات');
    expect(_code(_repoApi).contains('getAssetSnapshotsAsOf'), isTrue);
  });

  test('والبطاقةُ لا تستورد `data/database`', () {
    final card = _code(_card);
    expect(card.contains('data/database'), isFalse,
        reason: 'ملفُّ عرضٍ جديدٌ يستورد القاعدةَ — يكسر حارسَ الاستيراد');
    expect(card.contains('typedef AssetCardValue'), isTrue,
        reason: 'البطاقةُ تأخذ صفَّ drift مباشرةً بدل قيمٍ خالصة');
  });

  test('🔴 ووسمُ الترحيل على الصفّ لا على الجدول', () {
    final card = _code(_card);
    expect(card.contains("PicPosPillCell(tr('مُرحَّل')"), isTrue);
    expect(card.contains("PicPosPillCell(tr('متوقَّع')"), isTrue);
    expect(card.contains('rows[i].posted'), isTrue,
        reason: '🔴 وسمٌ واحدٌ فوق الجدول يكذب على أحد النصفين — وجدولُ أصلٍ '
            'نصفُه مُرحَّلٌ ونصفُه توقّعٌ هو الحالةُ الطبيعيّة');
  });
}

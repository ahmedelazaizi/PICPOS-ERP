// الإضافاتُ والخيارات تصل كلَّ جهاز — توصيلٌ في أربعة مواضعَ لا موضع.
//
// ═══ ما يحرسه هذا الملفّ ═══
//
// الإضافةُ ملاحظةٌ يستلمها المطبخ (زيادةُ جبنٍ أو كاتشب)، والخيارُ **مُسعَّرٌ
// يزيد قيمةَ الصنف في الفاتورة**. وبقرار المالك 2026-09-21 هي **بياناتٌ
// رئيسةٌ عامّةٌ** كالأصناف والفئات: تعريفٌ واحدٌ يصل كلَّ الأجهزة في كلّ
// الفروع.
//
// وقبلَ ذلك كانت الجداولُ الثلاثةُ خارجَ القوائم **كلِّها**، فمجموعةٌ
// يعرّفها المديرُ لا تصل الكاشيرَ أبداً وسعرُ الخيار يختلف من جهازٍ لآخرَ
// في فاتورتَين.
//
// ═══ 🔴 ولماذا حارسٌ يقرأ أربعةَ ملفّات ═══
//
// التوصيلُ ليس سطراً: كلُّ قائمةٍ تحكم مرحلةً مختلفةً، وسقوطُ واحدةٍ يُنتج
// عطباً **مختلفاً** لا غيابَ الميزة:
//
//   • `DeltaPullService.pullTables` — العميلُ لا يطلبها أصلاً؛
//   • `api_handler._syncPullTables` — الخادمُ لا يسلّمها وإن طُلبت؛
//   • `IdNamespaceService.namespacedTables` — العميلُ لا يتبنّى معرّفَ
//     الخادم، فيتصادم معرّفٌ محلّيٌّ مع آخرَ وارد؛
//   • `AppDatabase._syncHardenedTables` — على PostgreSQL يُولَد الصفُّ
//     **بختمٍ فارغ** (‏`fn_bump_row_version` وحدَه يختم عند الإدراج)، فلا
//     يصل عميلاً بعد أوّل سحب. وهذه أخبثُها: كلُّ شيءٍ يبدو موصولاً.
//
// ⚠️ **ولا يكفي وجودُ الاسم في الملفّ**: اسمٌ في تعليقٍ يُقرأ توصيلاً.
//    فتُنزَع التعليقاتُ قبل المطابقة — وهو عينُ ما يفعله
//    `sync_coverage_guard` للسبب نفسِه.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/api_handler_source.dart';

const _tables = <String>[
  'modifier_groups',
  'modifier_items',
  'product_modifier_groups',
];

/// المواضعُ الأربعةُ: المِلفُّ والرمزُ الذي يحدّد القائمةَ فيه.
const _lists = <String, (String path, String anchor)>{
  'طلبُ العميل': (
    'lib/services/delta_pull_service.dart',
    'static const List<String> pullTables',
  ),
  'تسليمُ الخادم': (
    'lib/services/api/api_handler.dart',
    'static const _syncPullTables',
  ),
  'تبنّي المعرّف': (
    'lib/services/id_namespace_service.dart',
    'namespacedTables',
  ),
  'ختمُ PostgreSQL': (
    'lib/data/database/database.dart',
    '_syncHardenedTables',
  ),
};

String _stripComments(String raw) {
  final out = StringBuffer();
  for (final line in raw.split('\n')) {
    final t = line.trimLeft();
    if (t.startsWith('//')) continue;
    out.writeln(line);
  }
  return out.toString();
}

/// جسمُ القائمةِ وحدَها — من مرساتها إلى إغلاق القوس.
///
/// ⚠️ **بالموازنة لا بأوّلِ `}`**: قائمةٌ فيها تعليقٌ أو تعشيشٌ تنتهي مبكّراً
///    بالقصّ الساذج، فيُقرأ اسمٌ خارجَها غيابًا — أو داخلَها حضوراً كاذباً.
String _listBody(String path, String anchor) {
  final src = _stripComments(path == 'lib/services/api/api_handler.dart'
      ? readApiHandlerSource()
      : File(path).readAsStringSync());
  final at = src.indexOf(anchor);
  expect(at, greaterThan(0), reason: 'لم تعد المرساةُ موجودةً: $anchor');
  final open = src.indexOf(RegExp(r'[\[{]'), at);
  expect(open, greaterThan(0), reason: 'لا قائمةَ بعد المرساة: $anchor');
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (c == '[' || c == '{') depth++;
    if (c == ']' || c == '}') {
      depth--;
      if (depth == 0) return src.substring(open, i + 1);
    }
  }
  fail('قائمةٌ غيرُ مغلقة عند $anchor');
}

void main() {
  group('حراسةُ الحارس', () {
    test('المواضعُ الأربعةُ تُقرأ فعلاً وغيرَ فارغة', () {
      _lists.forEach((label, spec) {
        final body = _listBody(spec.$1, spec.$2);
        expect(body.length, greaterThan(60),
            reason: '«$label» قُرئ فارغاً — القصُّ انكسر والحارسُ يقيس لا شيء');
      });
    });

    test('ومرساةٌ موجبة — جدولٌ معروفُ المزامنة حاضرٌ في الأربعة', () {
      // بلا هذه يمرّ كلُّ ما تحتها لو انكسر القصُّ وصارت الأجسامُ فارغة.
      _lists.forEach((label, spec) {
        expect(_listBody(spec.$1, spec.$2), contains('products'),
            reason: '«$label» لا يذكر `products` ⇒ القصُّ خاطئ');
      });
    });

    test('وذكرٌ في تعليقٍ ليس توصيلاً — على البلاغ نفسِه', () {
      const sample = "  // 'modifier_items' مذكورٌ شرحاً\n  'products',";
      expect(_stripComments(sample).contains('modifier_items'), isFalse,
          reason: 'اسمٌ في تعليقٍ يُعَدُّ توصيلاً ⇒ الحارسُ يكذب في الاتّجاه '
              'الخطر: قائمةٌ ناقصةٌ تمرّ خضراء');
      expect(_stripComments(sample).contains('products'), isTrue,
          reason: 'النزعُ ابتلع كوداً ⇒ بلاغاتٌ وهميّة');
    });
  });

  test('🔴 الجداولُ الثلاثةُ في المواضع الأربعة كلِّها', () {
    final missing = <String>[];
    _lists.forEach((label, spec) {
      final body = _listBody(spec.$1, spec.$2);
      for (final t in _tables) {
        if (!body.contains("'$t'")) missing.add('$label ← $t');
      }
    });
    expect(missing, isEmpty,
        reason: '🔴 توصيلٌ ناقص — ولكلِّ موضعٍ عطبُه المختلف (راجع رأسَ '
            'الملفّ):\n  ${missing.join('\n  ')}');
  });

  test('🔴 والحذفُ ناعمٌ — وإلّا عاد المحذوفُ بأوّل سحب', () {
    // 🔴 حذفٌ قاطعٌ محلّيّاً يترك الصفَّ على الخادم فيعود: يحذف المستخدمُ
    //    الخيارَ فيعود بعد دقائقَ بلا سبب. ويُقاس سلوكيّاً كذلك في
    //    `modifiers_sync_contract_test`؛ وهذا يمنع عودةَ `DELETE` نصّاً.
    final dao = _stripComments(
        File('lib/data/database/daos/modifiers_dao.dart').readAsStringSync());
    for (final t in _tables) {
      expect(dao.contains('DELETE FROM $t'), isFalse,
          reason: '🔴 عاد الحذفُ القاطعُ على $t');
    }
    expect(dao, contains('deleted_at = ?'),
        reason: 'لا وسمَ حذفٍ إطلاقاً ⇒ الفحصُ أعلاه يمرّ بلا معنى');
  });

  test('🔴 وفرعا اللهجة كلاهما يمنح معرّفاً عالميّاً', () {
    // 🔴 نجت طفرةٌ تُفرّغ المعرّفَ في فرع PostgreSQL (‏M1): سويّةُ الوحدة
    //    تعمل على SQLite فلا تنفّذ ذلك الفرعَ إطلاقاً — والخادمُ **هو** من
    //    يعمل على PG. فصفٌّ يُنشأ على الخادم كان سيخرج بلا معرّف، ولا
    //    يحلّه `_upsertRow` على أيّ جهاز.
    //
    // ⚠️ ويُقاس بنيويّاً لا سلوكيّاً: قياسُه سلوكيّاً يحتاج قاعدةَ PG حيّة
    //    (سويّةُ `integration_pg`)، وهذا يمنع السقوطَ قبل أن يصلها.
    final dao = _stripComments(
        File('lib/data/database/daos/modifiers_dao.dart').readAsStringSync());
    // الجملةُ كاملةً: الأعمدةُ ثمّ قائمةُ القيم.
    final inserts = RegExp(r"'INSERT (?:OR IGNORE )?INTO (modifier_groups|"
            r"modifier_items|product_modifier_groups) \(([^)]*)\) '\s*"
            r"'VALUES \(([^)]*)\)")
        .allMatches(dao)
        .toList();
    expect(inserts.length, greaterThanOrEqualTo(6),
        reason: 'عُثر على ${inserts.length} إدراجاً فقط — ثلاثةُ جداولَ '
            'بفرعَي لهجةٍ تعني ستّةً على الأقلّ، فالكشفُ انكسر');
    for (final m in inserts) {
      expect(m.group(2), contains('global_id'),
          reason: '🔴 إدراجٌ في `${m.group(1)}` بلا عمود `global_id` — وصفٌّ '
              'بلا معرّفٍ لا يحلّه `_upsertRow` فيتكرّر على الطرف الآخر');
      expect(m.group(2), contains('last_modified_at'),
          reason: '🔴 إدراجٌ بلا ختمٍ لا يلتقطه السحبُ التفاضليُّ أبداً');

      // 🔴 **والقيمةُ لا العمودُ وحدَه.** نجت طفرةٌ تُبدّل القيمةَ إلى
      //    `NULL` والعمودُ في مكانه (‏M1) — فيبدو الإدراجُ موصولاً ويكتب
      //    معرّفاً فارغاً. **وفحصُ ذكرِ `gid` لا يمسكها**: المتغيّرُ ما زال
      //    يُمرَّر في `variables`، والـSQL وحدَه هو الذي تغيّر.
      //
      //    فالمقياسُ عددُ العناصر النائبة: عمودٌ بلا `?` يقابله يعني قيمةً
      //    مكتوبةً في الجملة.
      final cols = m.group(2)!.split(',').length;
      final holders = '?'.allMatches(m.group(3)!).length;
      expect(holders, cols,
          reason: '🔴 إدراجٌ في `${m.group(1)}`: $cols عموداً و$holders '
              'عنصراً نائباً — قيمةٌ مكتوبةٌ في الجملة بدل مُمرَّرة، '
              'وعمودٌ فارغٌ أسوأُ من عمودٍ غائبٍ لأنّه يبدو موصولاً');
      expect(m.group(3), isNot(contains('NULL')),
          reason: '🔴 `NULL` مكتوبةٌ في قيم `${m.group(1)}`');
    }
  });

  test('🔴 وكلُّ قراءةٍ ترشّح المحذوف', () {
    final dao = _stripComments(
        File('lib/data/database/daos/modifiers_dao.dart').readAsStringSync());
    final selects = RegExp(r"'SELECT[^;]*?FROM (modifier_groups|modifier_items|"
            r"product_modifier_groups)")
        .allMatches(dao)
        .length;
    expect(selects, greaterThan(0), reason: 'لا قراءةَ أصلاً ⇒ فحصٌ فارغ');
    expect('deleted_at IS NULL'.allMatches(dao).length,
        greaterThanOrEqualTo(selects),
        reason: '🔴 قراءةٌ بلا ترشيحِ المحذوف ⇒ الخيارُ المحذوفُ ما زال '
            'يُعرَض ويُسعَّر — «حذفٌ» لا يحذف');
  });
}

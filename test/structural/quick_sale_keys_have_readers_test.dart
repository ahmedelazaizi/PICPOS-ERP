// حارسُ العقد: مفتاحٌ موسومٌ بالإنفاذ لا بدّ أن يبلغه المحرّكُ فعلاً.
//
// ═══ فئةُ العطب ═══
//
// «إعدادٌ يُحفَظ ولا يُقرأ = ميزةٌ ميّتةٌ صامتة» — المبدأُ الذي بُني عليه هذا
// البندُ كلُّه. والوسمُ `enforced` يصف **نيّةً**، ولا شيءَ كان يتحقّق من صدقها.
//
// ⚠️ **وقد سقط فعلاً**: الشاشةُ تكتب `pos_enabled_payment_methods` والمحرّكُ
// يقرأ `pos_payment_methods_enabled` — الكلمتان مقلوبتان، فكان للمفتاح
// المكتوبِ **قارئٌ واحدٌ في المستودع كلِّه: سطرُ تعريفه**. المديرُ يُلغي تأشيرَ
// «آجل»، والمعاينةُ الحيّةُ تُسقطه أمام عينَيه، ويحفظ — ثمّ يجده الكاشيرُ في
// حوار الدفع: مبيعاتٌ آجلةٌ من تِلٍّ ظُنَّ مغلقاً. (‏وجده تدقيقا المزامنة
// وسلامةِ القاعدة مستقلَّين 2026-08-30، ولم يمسكه أيٌّ من ١٥٠٠ اختبارٍ قائم.)
//
// ═══ لماذا لا يكفي البحثُ عن نصّ المفتاح ═══
//
// للمحرّك **ثلاثةُ طرقٍ** لبلوغ الإعداد، ولا يظهر نصُّ المفتاح إلّا في واحدة:
//
//   ١. بنصِّ المفتاح — وهو ما تفعله مجموعاتُ الاختيار.
//   ٢. بمعرّف الصفّ: `kQuickSaleRows.firstWhere((r) => r.id == 'askqty')`.
//   ٣. بمترجِمٍ مسمّى: `quickSaleMaxLineQty(policy)` — والمعرّفُ يعيش داخلَ
//      المترجِم في النموذج، فلا أثرَ له في شيفرة المحرّك إطلاقاً.
//
// ونسخةٌ أولى من هذا الحارسِ بحثت عن نصِّ المفتاح وحدَه فأبلغت عن **١٣**
// مفتاحاً ميّتاً وكلُّها حيّة. فالمقياسُ هنا **الوصولُ** بالطرق الثلاث معاً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/quick_sale_policy.dart';

const _modelPath = 'lib/domain/models/quick_sale_policy.dart';

/// ملفّاتٌ لا تُحتسَب محرّكاً: النموذجُ يعرّف، وشاشاتُ الإعدادات تكتب وتعرض.
bool _isWriterOnly(String path) {
  final p = path.replaceAll(r'\', '/');
  return p.contains(_modelPath) || p.contains('lib/presentation/settings_picpos/');
}

/// شيفرةُ المحرّك كلُّها في نصٍّ واحد.
String _engineSource() {
  final buf = StringBuffer();
  var count = 0;
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    if (_isWriterOnly(f.path)) continue;
    buf.writeln(f.readAsStringSync());
    count++;
  }
  _engineFileCount = count;
  return buf.toString();
}

int _engineFileCount = 0;

/// خريطةُ «اسمُ مترجِمٍ في النموذج ⇒ معرّفاتُ الصفوف التي يقرؤها».
///
/// تُشتقُّ من مصدر النموذج: كلُّ دالّةٍ عليا اسمُها `quickSale…` وما تذكره من
/// `_rowById('x')`. فحين يُنادى المترجِمُ في المحرّك، تُعدُّ صفوفُه مقروءة.
Map<String, Set<String>> _translatorIds(String modelSrc) {
  final out = <String, Set<String>>{};
  final fn = RegExp(r'\b(quickSale\w+)\s*\(');
  final rowId = RegExp(r"_rowById\('([a-z]+)'\)");

  // نقسّم المصدرَ عند كلِّ تعريفِ دالّةٍ عليا ونجمع ما بعدها حتّى التالية.
  final marks = <MapEntry<String, int>>[];
  for (final m in fn.allMatches(modelSrc)) {
    marks.add(MapEntry(m.group(1)!, m.start));
  }
  for (var i = 0; i < marks.length; i++) {
    final name = marks[i].key;
    final from = marks[i].value;
    final to = i + 1 < marks.length ? marks[i + 1].value : modelSrc.length;
    final body = modelSrc.substring(from, to);
    out.putIfAbsent(name, () => <String>{})
        .addAll(rowId.allMatches(body).map((m) => m.group(1)!));
  }
  return out;
}

void main() {
  late String engine;
  late Set<String> reachableIds;

  setUpAll(() {
    engine = _engineSource();
    final modelSrc = File(_modelPath).readAsStringSync();
    final translators = _translatorIds(modelSrc);

    reachableIds = <String>{};
    // (٢) معرّفٌ مذكورٌ نصّاً في المحرّك.
    for (final row in kQuickSaleRows) {
      if (engine.contains("'${row.id}'")) reachableIds.add(row.id);
    }
    // (٣) مترجِمٌ يُنادى في المحرّك ⇒ صفوفُه مقروءة.
    for (final entry in translators.entries) {
      if (engine.contains('${entry.key}(')) reachableIds.addAll(entry.value);
    }
  });

  group('مفاتيحُ سياسة البيع السريع يبلغها المحرّك', () {
    test('المرساة: المسحُ يرى الشجرةَ والاشتقاقُ ينتج وصولاً', () {
      // ⚠️ ثلاثُ مرساةٍ: بلا واحدةٍ منها يمرُّ الحارسُ أخضرَ على مسحٍ فارغ.
      expect(_engineFileCount, greaterThan(200),
          reason: 'المسحُ لا يرى شجرةَ `lib` — $_engineFileCount ملفّاً');
      expect(reachableIds.length, greaterThan(10),
          reason: 'الاشتقاقُ لم ينتج وصولاً معقولاً — '
              '${reachableIds.length} معرّفاً فقط');
      expect(reachableIds, contains('askqty'),
          reason: 'مسارٌ نعلم يقيناً أنّه موصولٌ لم يظهر — المطابقةُ معطوبة');
      expect(reachableIds, contains('maxqty'),
          reason: 'صفٌّ يُقرأ عبر مترجِمٍ لم يظهر — اشتقاقُ المترجِمات معطوب');
    });

    test('كلُّ صفٍّ موسومٍ بالإنفاذ يبلغه المحرّك', () {
      final dead = <String>[];
      for (final row in kQuickSaleRows) {
        if (!row.enforced) continue;
        // (٤) المرآة: صفٌّ يكتب مفتاحاً ثانياً يقرؤه المحرّكُ نصّاً.
        //     `negstock` مثالُه: المحرّكُ يقرأ `enable_negative_sales` ولا
        //     يقرأ `pos_negative_stock_policy` إطلاقاً. والمرآةُ مسلكٌ مقصود،
        //     لكنّها **ثنائيّةٌ** فتُسقط الخيارَ الأوسط — ولهذا يشترط الفحصُ
        //     التالي `caveat` صريحاً على كلِّ صفٍّ لا يصل إلّا بها.
        final mirror = row.mirrorKey;
        final reached = reachableIds.contains(row.id) ||
            engine.contains("'${row.settingKey}'") ||
            (mirror != null && engine.contains("'$mirror'"));
        if (!reached) dead.add('${row.id} → ${row.settingKey}');
      }
      expect(dead, isEmpty,
          reason: 'صفوفٌ موسومةٌ «منفَّذة» لا يبلغها المحرّك ⇒ المديرُ يظنّها '
              'تعمل وهي لا تفعل شيئاً:\n  ${dead.join("\n  ")}');
    });

    test('ومجموعاتُ الاختيار تُقرأ بنصِّ مفتاحها', () {
      // المجموعاتُ لا مترجِمَ لها: `pickOf` تأخذ الكائنَ، والمحرّكُ يقرأ
      // المفتاحَ نصّاً. فالفحصُ هنا مباشرٌ — وهو الذي أمسك العطبَ الحقيقيّ.
      final dead = <String>[];
      for (final pick in kQuickSalePicks) {
        if (!pick.enforced) continue;
        if (!engine.contains("'${pick.settingKey}'")) {
          dead.add('${pick.id} → ${pick.settingKey}');
        }
      }
      expect(dead, isEmpty,
          reason: 'مجموعاتُ اختيارٍ موسومةٌ «منفَّذة» بلا قارئٍ في المحرّك:\n'
              '  ${dead.join("\n  ")}');
    });

    test('وصفٌّ لا يبلغه المحرّكُ إلّا بمرآةٍ يحمل تحفّظاً صريحاً', () {
      // المرآةُ تُوصِّل المعنى وقد تفقد تفصيلَه. فحين يكون الوصولُ **عبرها
      // وحدَها**، يلزم `caveat` يقول للمدير أيَّ تفصيلٍ لا يُنفَّذ.
      for (final row in kQuickSaleRows) {
        if (!row.enforced || row.mirrorKey == null) continue;
        final direct = reachableIds.contains(row.id) ||
            engine.contains("'${row.settingKey}'");
        if (direct) continue;
        expect(row.caveat, isNotNull,
            reason: 'الصفُّ `${row.id}` يبلغ المحرّكَ بمرآته وحدَها — '
                'فالتفصيلُ الذي تفقده المرآةُ يجب أن يُذكَر في `caveat`، '
                'وإلّا قرأ المديرُ ثلاثةَ خياراتٍ والمحرّكُ يرى اثنين.');
      }
    });

    test('وما ليس منفَّذاً يحمل سببَه — الصفوفُ والمجموعاتُ سواء', () {
      for (final row in kQuickSaleRows) {
        if (row.enforced) continue;
        expect(row.notEnforcedReason, isNotNull,
            reason: 'الصفُّ `${row.id}` غيرُ منفَّذٍ بلا سبب');
      }
      for (final pick in kQuickSalePicks) {
        if (pick.enforced) continue;
        expect(pick.notEnforcedReason, isNotNull,
            reason: 'المجموعةُ `${pick.id}` غيرُ منفَّذةٍ بلا سبب — والوسمُ '
                'هو ما يُبقي المديرَ صادقَ التوقّع');
      }
    });
  });
}

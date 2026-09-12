// حارسٌ بنيويّ — كلُّ فئةِ تقاريرَ لها مجموعةٌ ووصف.
//
// ═══ لماذا ═══
//
// مركزُ التقارير صار شريطاً جانبيّاً يرسم الفئاتِ **مجمَّعةً** في خمس
// مجموعات، ولوحةَ تفصيلٍ ترسم وصفَ الفئة المختارة. والمجموعةُ والوصفُ
// يُقرآن من خريطتَين بالمعرّف — لا من حقلٍ في الفئة نفسِها.
//
// وهذا يفتح باباً صامتاً: فئةٌ جديدةٌ بلا مدخلٍ في الخريطة **تُرسَم**، لكنّها
// تسقط في آخر مجموعةٍ بلا عنوانٍ يخصّها، ووصفُها يختفي. لا خطأَ ولا تحذير —
// فقط فئةٌ في المكان الخطأ. والشاشةُ ٢٣٠٠ سطرٍ فلا تُرى بالعين.
//
// ⚠️ ولا يُفحَص بـ`contains` على الملفّ: المعرّفُ نفسُه يظهر مرّاتٍ (تعريفُ
//    الفئة · مفتاحُ المجموعة · مفتاحُ الوصف)، فالمقارنةُ **بين مجموعتَي
//    معرّفاتٍ مستخرَجتَين** لا بوجودِ نصّ.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File(
    'lib/presentation/reports_picpos/screens/reports_picpos_screen.dart',
  ).readAsStringSync();

  /// معرّفاتُ الفئات كما تُعرَّف فعلاً في `buildPicposReportCatalog`.
  ///
  /// ⚠️ `[a-z_0-9]+` لا `[a-z_]+`: معرّفاتُ هذا المستودع تحمل أرقاماً
  ///    (`bank2`)، ونمطٌ يستبعدها يُسقط فئةً ويُقرأ «لا فجوة».
  ///
  /// ⚠️ والاسمُ `PicposReportCategory` لا `_ReportCategory`: رُفع الصنفُ إلى
  ///    العلن 2026-09-12 ليقرأه الشريطُ الجانبيّ. والحارسُ أمسك نفسَه —
  ///    توكيدُ «عشرةٌ على الأقلّ» أبلغ صفراً بدل أن يُقرأ «لا فجوة».
  Set<String> categoryIds() => RegExp(
        r"PicposReportCategory\(\s*id:\s*'([a-z_0-9]+)'",
        multiLine: true,
      ).allMatches(src).map((m) => m.group(1)!).toSet();

  /// مفاتيحُ خريطةٍ ثابتةٍ بالاسم.
  Set<String> mapKeys(String name) {
    final start = src.indexOf('const Map<String, String> $name = {');
    expect(start, greaterThan(0), reason: 'الخريطةُ `$name` غيرُ موجودة.');
    final end = src.indexOf('\n};', start);
    expect(end, greaterThan(start));
    return RegExp(r"'([a-z_0-9]+)':")
        .allMatches(src.substring(start, end))
        .map((m) => m.group(1)!)
        .toSet();
  }

  test('كلُّ فئةٍ لها مجموعةٌ في الشريط الجانبيّ', () {
    final cats = categoryIds();
    expect(cats.length, greaterThanOrEqualTo(10),
        reason: 'استخراجُ معرّفات الفئات أعطى ${cats.length} — النمطُ غالباً '
            'هو المعطوب لا الشاشة.');

    final groups = mapKeys('_kCatGroup');
    expect(cats.difference(groups), isEmpty,
        reason: 'فئةٌ بلا مجموعة — تُرسَم في آخر مجموعةٍ بلا عنوانٍ يخصّها '
            'ولا خطأَ يُنبّه. أضف مدخلَها في `_kCatGroup`.');
    expect(groups.difference(cats), isEmpty,
        reason: 'مدخلٌ في `_kCatGroup` لفئةٍ لا وجودَ لها — بقيّةُ خريطةٍ '
            'من فئةٍ حُذفت.');
  });

  test('ولها وصفٌ في لوحة التفصيل', () {
    final cats = categoryIds();
    final descs = mapKeys('_kCatDesc');
    expect(cats.difference(descs), isEmpty,
        reason: 'فئةٌ بلا وصف — لوحةُ التفصيل تعرض عنواناً عارياً حيث يعرض '
            'التصميمُ سطرَ شرح.');
    expect(descs.difference(cats), isEmpty,
        reason: 'وصفٌ لفئةٍ لا وجودَ لها.');
  });

  test('ومجموعاتُ الفئات كلُّها من ترتيبٍ معرَّف', () {
    // مجموعةٌ باسمٍ خارج `_kGroupOrder` لا تُرسَم إطلاقاً: الشريطُ يمرّ على
    // الترتيب لا على قيم الخريطة.
    final start = src.indexOf('const List<String> _kGroupOrder = [');
    expect(start, greaterThan(0));
    final order = RegExp(r"'([^']+)'")
        .allMatches(src.substring(start, src.indexOf('\n];', start)))
        .map((m) => m.group(1)!)
        .toSet();

    final gStart = src.indexOf('const Map<String, String> _kCatGroup = {');
    final used = RegExp(r":\s*'([^']+)',")
        .allMatches(src.substring(gStart, src.indexOf('\n};', gStart)))
        .map((m) => m.group(1)!)
        .toSet();

    expect(used.difference(order), isEmpty,
        reason: 'فئةٌ أُسندت إلى مجموعةٍ ليست في `_kGroupOrder` — والشريطُ '
            'يرسم بالترتيب، فالفئةُ تختفي من الشاشة تماماً.');
  });
}

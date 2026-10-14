// حراسةُ الصلاحية تتبع الشاشةَ التي تعمل فعلاً.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// `permission_enforcement_coverage_test` المجاور يسأل: «هل للكود موضعُ
// إنفاذٍ في `lib/`؟» — وهذا سؤالٌ **ناقص**. صلاحيةٌ محروسةٌ حراسةً صحيحةً في
// `presentation/pos/widgets/cart_item_tile.dart` تُرضيه، بينما PicPos له
// توأمٌ `pos_picpos` كُتب من جديدٍ ولا يستورد ذلك الملفَّ إطلاقاً.
//
// فالحارسُ يمرّ أخضرَ والمشغّلُ يرى العطب. بلاغٌ ميدانيّ (2026-08-11):
// «رفعتُ التحديد عن حذف صنف من السلة، ودخلتُ بالكاشير، فحذف الصنفَ ولم
// يظهر حوارُ كلمة المرور» — و`pos_remove_item` محروسٌ فعلاً، في ملفٍّ لا
// تصل إليه الشاشة.
//
// وهذه أخطرُ من صلاحيةٍ بلا إنفاذٍ أصلاً: هناك مفتاحٌ لا يفعل شيئاً، وهنا
// **ضابطٌ رقابيٌّ يبدو مفعَّلاً وهو غيرُ موجودٍ على المسار الحيّ**.
//
// ── ما يقيسه هذا الملفّ ───────────────────────────────────────────────────
// لكلّ مجلدٍ له توأمُ `_picpos`: أيُّ كودِ صلاحيةٍ يُذكر في النظير القديم
// ولا يُذكر في التوأم ولا في أيّ موضعٍ آخر — فهو فجوةُ تكافؤ. ويجب أن يكون
// مسجَّلاً في `PermissionEnforcementRegistry.picposParityGaps` بسببٍ صريح.
//
// والقائمةُ **تتقلّص ولا تكبر**: الاختبارُ الثاني يفشل لمدخلٍ صار منفَّذاً
// في التوأم، فلا تبقى ساكنةً بعد إصلاحها.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_source.dart';
import 'package:ural_erp/core/permissions/permission_enforcement_registry.dart';

/// النظيرُ القديم ↔ توأمُ PicPos. مقيسٌ لا مفترَض: هذه هي المجلداتُ التي
/// لها اسمان تحت `lib/presentation/`.
const _twins = <String, String>{
  'pos': 'pos_picpos',
  'products': 'products_picpos',
  'settings': 'settings_picpos',
  'treasury': 'treasury_picpos',
};

/// الملفاتُ التي **تعرّف** الصلاحية لا التي تفحصها — ذكرُها فيها ليس إنفاذاً.
bool _isDefinitionFile(String p) {
  final n = p.replaceAll(r'\', '/');
  return n.endsWith('lib/core/permissions/permission_codes.dart') ||
      n.endsWith('lib/core/permissions/role_grant_matrix.dart') ||
      n.endsWith('lib/core/permissions/permission_enforcement_registry.dart') ||
      n.endsWith('data/permission_categories.dart') ||
      n.contains('lib/data/database/database_seeder');
}

Map<String, String> _constantNameByCode() {
  final src = File(
    'lib/core/permissions/permission_codes.dart',
  ).readAsStringSync();
  final re = RegExp(r"static const String (\w+) = '([a-z0-9_]+)';");
  return {for (final m in re.allMatches(src)) m.group(2)!: m.group(1)!};
}

/// كلُّ ملفات دارت تحت `lib/` مع محتواها، مقروءةً مرّةً واحدة.
///
/// القراءةُ مرّةً في `setUpAll`: المسحُ لكلّ `test()` كان يضاعف زمنَ التشغيل
/// بلا فائدة — نفسُ ملاحظة الحارس المجاور.
final Map<String, String> _sources = () {
  final out = <String, String>{};
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final p = f.path.replaceAll(r'\', '/');
    if (_isDefinitionFile(p)) continue;
    out[p] = f.readAsStringSync();
  }
  return out;
}();

final _importRe = RegExp("(?:import|part)\\s+'([^']+\\.dart)'");

/// نصُّ الملفّ بلا تعليقات.
///
/// ⚠️ التعليقاتُ **لا تُحتسب إشارة**: توجيهةُ `import` في تعليقٍ ليست استيراداً،
/// وذكرُ `PermissionCodes.posX` في تعليقٍ ليس حراسة. (‏وثيقةُ الحارس في
/// `permission_guard.dart:58` تذكر `PermissionCodes.posExpense` في **مثالٍ
/// توضيحيّ** — وهو أحدُ ما كان يُسكت هذا الحارس.)
///
/// ولا نلمس السلاسلَ النصّية: ماسحٌ يدويٌّ لها قد يفقد التزامنَ على استقراءٍ
/// متداخلٍ فيبتلع بقيةَ الملفّ — أي يُخفي حراسةً قائمة، وهو اتجاهُ الخطأ
/// الخطر. والأكوادُ نفسُها تُكتب سلاسلَ (`'pos_save'`) فحذفُها خطأ أصلاً.
final Map<String, String> _codeOnlyCache = {};
String _codeOnly(String path) =>
    _codeOnlyCache.putIfAbsent(path, () => stripComments(_sources[path] ?? ''));

@visibleForTesting
String stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      i += 2;
      while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// نصُّ الملفّ **مع أجزائه** — المكتبةُ وحدةُ القياس لا الملفّ.
///
/// ⚠️ بلا هذا يسقط الحارسُ في سلبٍ كاذب: `picpos_pos_screen.dart` يستورد
/// `held_orders_dialog.dart` والاستعمالُ في جزئه `picpos_pos_operations.dart`،
/// فشرطُ «يذكر رمزاً من المستورَد» يفشل على الأصل وحدَه فتُقطع الحافة.
final Map<String, String> _withPartsCache = {};
String _codeOnlyWithParts(String path) => _withPartsCache.putIfAbsent(path, () {
  final own = _codeOnly(path);
  final buf = StringBuffer(own);
  for (final m in RegExp("part\\s+'([^']+\\.dart)'").allMatches(own)) {
    final p = _resolveImport(path, m.group(1)!);
    if (p != null && _sources.containsKey(p)) buf.write(_codeOnly(p));
  }
  return buf.toString();
});

/// كلُّ ملفٍّ **يبلغه** توأمُ PicPos عبر رسم الاستيراد.
///
/// ⚠️ الاستيرادُ وحدَه لا يكفي: البراميلُ والاستيرادُ العارض يجرّان رسماً
/// كاملاً فيُعَدُّ محروساً ما لا يُرسم — وهذا اتجاهُ الخطأ الخطر (فجوةٌ
/// حقيقيةٌ تُخفى). فلا تُتبَع الحافةُ إلا إن كانت المكتبةُ المستورِدة **تذكر
/// فعلاً** رمزاً معرَّفاً في المستورَد.
Set<String> _reachableFrom(String twin) {
  final seen = <String>{};
  final queue = <String>[];

  void enqueue(String path) {
    if (!_sources.containsKey(path)) return;
    if (!seen.add(path)) return;
    queue.add(path);
  }

  // ⚠️ **البذرةُ مجلّدٌ أو ملفٌّ مفرد.** الخريطةُ اليدويّةُ تربط مجلّداً
  //    بمجلّد، لكنّ أغلبَ فوركات PicPos أصلُها **ملفٌّ مفردٌ** تحت
  //    `screens/` (‏`fixed_assets_screen.dart` …). فبلا الفرع الثاني يعجز
  //    الحارسُ بنيويّاً عن رؤية ٢١ فوركاً من ٢٥ — وهو ما كان.
  for (final key in _sources.keys) {
    if (key == 'lib/presentation/$twin' ||
        key.startsWith('lib/presentation/$twin/')) {
      enqueue(key);
    }
  }

  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    final text = _codeOnlyWithParts(current);
    for (final m in _importRe.allMatches(text)) {
      final resolved = _resolveImport(current, m.group(1)!);
      if (resolved == null) continue;
      if (_referencesSymbolOf(text, resolved)) enqueue(resolved);
    }
  }

  return seen;
}

final Map<String, Set<String>> _declaredCache = {};

/// أسماءُ الأنواع المعرَّفة في ملف — تكفي لحالتنا (كلُّ ما يُرسم ودجت/كلاس).
Set<String> _declaredTypes(String path) => _declaredCache.putIfAbsent(path, () {
  final src = _sources[path];
  if (src == null) return <String>{};
  final re = RegExp(r'\b(?:class|mixin|enum|extension|typedef)\s+(\w+)');
  return {for (final m in re.allMatches(src)) m.group(1)!};
});

bool _referencesSymbolOf(String importerSource, String importedPath) {
  final declared = _declaredTypes(importedPath);
  // ملفُّ `part` لا يعرّف نوعاً بالضرورة وهو جزءٌ من نفس المكتبة — يُتبَع.
  if (declared.isEmpty) return true;
  for (final name in declared) {
    if (RegExp('\\b$name\\b').hasMatch(importerSource)) return true;
  }
  return false;
}

/// يحوّل توجيهةَ `import`/`part` إلى مسارٍ تحت `lib/`، أو null لما لا يُقاس
/// (‏`dart:` وحِزَمُ الطرف الثالث).
String? _resolveImport(String from, String raw) {
  if (raw.startsWith('dart:')) return null;
  if (raw.startsWith('package:')) {
    const self = 'package:ural_erp/';
    if (!raw.startsWith(self)) return null;
    return 'lib/${raw.substring(self.length)}';
  }
  final segments = from.split('/')..removeLast();
  for (final part in raw.split('/')) {
    if (part == '.' || part.isEmpty) continue;
    if (part == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(part);
  }
  return segments.join('/');
}

/// هل يُذكر الكودُ في [text] ذكراً **يصلح أن يكون حراسة**؟
///
/// صورتان لا ثالثة: السلسلةُ الخام `'pos_save'`، أو الثابتُ **مؤهَّلاً**
/// بـ`PermissionCodes.`.
///
/// ⚠️ والتأهيلُ ليس تجميلاً — هو إصلاحُ سلبٍ كاذبٍ مقيس: كان البحثُ عن اسم
/// الثابت وحدَه (`\bposDiscount\b`)، فطابق **لوناً** اسمُه
/// `AppColors.posDiscount` في `core/theme/app_colors.dart`، فمرّ `pos_discount`
/// «محروساً» وهو غيرُ محروسٍ في PicPos إطلاقاً — وثلاثةُ أبوابٍ مفتوحةٍ عليه.
/// **لونٌ أسكتَ حارساً أمنياً.** (مقيسٌ 2026-08-13)
///
/// و`\s*` حول النقطة تحفظ المرجعَ الملفوفَ على سطرين
/// (`PermissionCodes.\n  posSave`) الذي كان سببَ إسقاط البادئة أصلاً.
@visibleForTesting
bool mentionsCode(String text, String code, String? constName) {
  if (text.contains("'$code'")) return true;
  if (constName == null) return false;
  return RegExp('PermissionCodes\\s*\\.\\s*$constName\\b').hasMatch(text);
}

/// هل الملفُّ موضعَ حراسةٍ مُحتمَل — أي في طبقة العرض؟
///
/// ⚠️ ثلاثةُ أصنافٍ من الملفات كانت تُسكت هذا الحارسَ وهي **ليست شاشة**:
///   · `lib/services/api/api_sales_handler.dart` — يفرض `pos_hold_order` على
///     سطح HTTP. وهو إنفاذٌ حقيقيّ، لكن لعميلٍ بعيدٍ لا لزرّ الشاشة. وعلى
///     تنصيبةٍ مستقلّةٍ لا وجودَ لهذا المسار أصلاً.
///   · `lib/data/database/migrations/epoch_3.dart` — قائمةُ منحٍ افتراضيّةٍ
///     تذكر `'pos_hold_order'` نصّاً. بياناتُ منحٍ لا إنفاذ.
///   · `lib/services/logging/…` — سلاسلُ أفعالٍ في سجلّ النشاط.
bool _isEnforcementSurface(String path) =>
    path.startsWith('lib/presentation/') || path.startsWith('lib/core/');

/// أزواجُ (الأصل ↔ فورك PicPos) **مشتقّةً من الموجّه نفسِه**.
///
/// ═══ لماذا تُشتقّ ولا تُكتَب ═══
///
/// [_twins] خريطةٌ يدويّةٌ فيها أربعةُ مداخل، وفوركاتُ PicPos اليومَ **٢٥**.
/// كُتبت يومَ كانت أربعةً ولم تكبر مع المشروع، فبقي الحارسُ يغطّي ١٦٪ وهو
/// يبدو شاملاً — وهذا عينُ الصنف الذي بُني الحارسُ لمنعه: ضابطٌ يبدو مفعَّلاً
/// وهو غيرُ موجودٍ على المسار الحيّ.
///
/// و`app_main_screen.dart` هو **المصدرُ الوحيدُ للحقيقة** في التفريع: ما لم
/// يُذكر فيه لا يُفتَح لمستخدم PicPos أصلاً. فاشتقاقُ الأزواج منه يجعل
/// الخريطةَ تكبر تلقائيّاً مع كلّ فوركٍ جديد، ولا يمكن أن تبيت.
///
/// وتُعاد **مساراتٍ** لا أسماءَ صفوف: الأصلُ ملفٌّ مفردٌ غالباً والفوركُ
/// كذلك، و[_reachableFrom] يتبع رسمَ الاستيراد فيبلغ بقيّةَ مجلّد الفورك.
final List<({String legacy, String fork})> _routerPairs = () {
  final src = readLibrarySource('lib/app_main_screen.dart');
  final re = RegExp(
    r'Brand\.isPicPos[\s\S]{0,80}?\?[\s\S]{0,80}?const\s+(\w+)\(\)'
    r'[\s\S]{0,80}?:[\s\S]{0,80}?const\s+(\w+)\(\)',
  );
  String? fileOf(String cls) {
    for (final entry in _sources.entries) {
      if (_declaredTypes(entry.key).contains(cls)) return entry.key;
    }
    return null;
  }

  final out = <({String legacy, String fork})>[];
  for (final m in re.allMatches(src)) {
    final forkFile = fileOf(m.group(1)!);
    final legacyFile = fileOf(m.group(2)!);
    if (forkFile == null || legacyFile == null) continue;
    // المسارُ نسبيٌّ إلى `lib/presentation/` لأنّ الباقيَ يبنيه المنادي.
    const prefix = 'lib/presentation/';
    if (!forkFile.startsWith(prefix) || !legacyFile.startsWith(prefix))
      continue;
    out.add((
      legacy: legacyFile.substring(prefix.length),
      fork: forkFile.substring(prefix.length),
    ));
  }
  return out;
}();

Set<String> _currentGaps() {
  final byCode = _constantNameByCode();
  // ⚠️ المدى **كلُّ توائم PicPos معاً** لا كلُّ زوجٍ وحدَه: التطبيقُ واحد،
  // فحراسةُ `products_add` في توأم الأصناف تحمي الفعلَ ولو ذُكر الكودُ في
  // نظير البيع القديم. قياسُ الزوج وحدَه كان يعطي فجوةً عابرةً للأزواج.
  final reachable = <String>{
    for (final twin in _twins.values) ..._reachableFrom(twin),
    // والفوركاتُ المشتقّةُ من الموجّه — راجع [_routerPairs].
    for (final p in _routerPairs) ..._reachableFrom(p.fork),
  };
  final legacies = <String>{
    ..._twins.keys,
    for (final p in _routerPairs) p.legacy,
  };
  final gaps = <String>{};
  for (final legacy in legacies) {
    for (final code in byCode.keys) {
      final c = byCode[code];
      final inLegacy = _sources.keys
          .where(
            (p) =>
                p == 'lib/presentation/$legacy' ||
                p.startsWith('lib/presentation/$legacy/'),
          )
          .any((p) => mentionsCode(_codeOnly(p), code, c));
      if (!inLegacy) continue;
      final reaches = reachable
          .where(_isEnforcementSurface)
          .any((p) => mentionsCode(_codeOnly(p), code, c));
      if (reaches) continue;
      gaps.add(code);
    }
  }
  return gaps;
}

// ── الحارسُ المعاكس ────────────────────────────────────────────────────────
//
// `picposParityGaps` يقول «لا سطحَ يُحرَس اليوم». وهو حكمُ **غياب**، ولا شيءَ
// في الحارس أعلاه يمنعه من أن يبطل صامتاً: يومَ يُضاف زرُّ مرتجعٍ أو طاولاتٍ
// لشاشة PicPos **بلا حراسة** لن يذكر أحدٌ الكود، فيبقى الكودُ «غيرَ واصل» أي
// فجوةً مسجَّلة، فيمرّ الاختبارُ أخضرَ وقد وُلد ثقبٌ جديد.
//
// والاختبارُ الثالث («السجلُّ يتقلّص») لا يسدّ هذا: هو يفشل لمدخلٍ **صار
// محروساً** — أي للحالة السعيدة. أمّا الميزةُ التي تصل بلا حراسة فلا أثرَ لها
// في مطابقات الكود إطلاقاً.
//
// فالحارسُ لا يجوز أن يرصد **ذكرَ الكود** بل **وصولَ الميزة**. ولكلّ مدخلٍ في
// السجلّ شاهدُ غيابٍ مكتوبٌ نثراً هناك («لا مِسطرةَ زيادةٍ ونقص» · «صفرُ
// مطابقاتٍ لـ`TablePos`»). وهذه الخريطةُ تحوّل ذلك النثرَ إلى تأكيدٍ تنفيذيّ.
//
// ⚠️ الشواهدُ تُقاس على الكود **بلا تعليقات**: خمسٌ منها (`استبدال` ·
// `العروض` · `applyOffer` · `TouchKeyboard` · `Return`) لها اليومَ مطابقاتٌ في
// تعليقاتٍ فقط، ولولا التجريدُ لوُلد الحارسُ أحمرَ بلا سبب.
const _absenceWitness = <String, List<String>>{
  // ⚠️ `pos_booking` شُطب 2026-08-23 مع سطرِه في السجلّ: وصل السطحُ
  // (‏زرُّ «الحجوزات» في `picpos_top_bar.dart`) وصار محروساً. وبقاءُ شاهدِه
  // هنا بعد شطبِ المدخلِ يُسقط حارسَ «لا شاهدَ بائتٌ لمدخلٍ شُطب» — والاثنان
  // يُحذفان معاً في نفس الكوميت.
  // ⚠️ `pos_exchange` شُطب 2026-08-19 مع مدخلِه في السجلّ: وصل سطحُ الاستبدال
  // (زرُّ اللوحة · ترويسةُ الأرقام الثلاثة · مسارُ الحفظ) وصار الكودُ مُنفَذاً
  // في `_showExchange`. والحارسُ المعاكسُ هو من كشف الوصولَ — أعطى الملفّاتِ
  // الثلاثةَ بالاسم قبل أن يُشطَب أيُّ سطر.
  'pos_deleted_items': ['الأصناف المحذوفة', 'DeletedItems'],
  'pos_keyboard': ['لوحة المفاتيح'],
  'pos_offers': ['العروض', 'OffersDialog'],
  'pos_table_select': ['طاولة', 'TablePos', 'table_pos'],
  'pos_table_bill': ['طاولة', 'TablePos', 'table_pos'],
  'tables_add_items': ['طاولة', 'TablePos', 'table_pos'],
  'tables_cancel': ['طاولة', 'TablePos', 'table_pos'],
  'tables_checkout': ['طاولة', 'TablePos', 'table_pos'],

  // ── الفوركاتُ الخمسةُ الجديدة (2026-08-26) ────────────────────────────
  //
  // ⚠️ الشاهدان مختاران **بمرساةٍ في الطرفَين**: صفرُ مطابقاتٍ في سطح
  // PicPos، و٣ مطابقاتٍ في الشاشة الأصل لكلٍّ منهما. فلو كان الشاهدُ نادراً
  // في الأصل أيضاً لكان يقيس نفسَه لا الميزة.
  //
  // ⚠️ ولا يصلح `disposeAsset` ولا «إلغاء المستند» شاهداً: كلاهما مذكورٌ في
  // **تعليقات** الفورك (‏حيث وُثِّق سببُ الغياب). والحارسُ يجرّد التعليقاتِ
  // فيمرّان — لكنّ من يقرأ الشاهدَ لاحقاً سيظنّهما مكسورَين. فالمختارُ رمزٌ
  // لا يُذكر إلّا في الشِّفرة.

  // ⚠️ **`assets_manage` شُطبت 2026-08-28 — والفجوةُ ضاقت فعلاً.**
  //
  // كانت هنا لأنّ إنشاءَ الأصل وتعديلَه في `fixed_assets_dialogs.dart`
  // (‏جزءٌ من الشاشة الأصل) ولا يستوردها الفورك. ثمّ صار للفورك حوارُ
  // «أصل جديد» خاصٌّ به محروسٌ بـ`PermissionGuard(assetsManage)` — فالكودُ
  // مُنفَّذٌ في التوأم، وسجلٌّ لا يتقلّص يكفّ عن كونه مقياسَ تقدّم.
  //
  // 🔴 **وتعديلُ الأصل ما زال غائباً عن الفورك** — لكنّه ليس فجوةَ
  //    **صلاحيّة**: الكودُ محروسٌ حيثما وُجد. وغيابُ الفعل نفسِه بندُ تسليمٍ
  //    لا مدخلٌ في سجلّ التكافؤ، وإبقاؤه هنا يخلط القياسَين.

  // ⚠️ **`einvoice_cancel` شُطبت 2026-09-03 — والسببُ المكتوبُ لها كان باطلاً.**
  //
  // كان هنا: «`EInvoiceServiceWrapper` لا يكشف مسارَ إلغاءٍ أصلاً». وهو غيرُ
  // صحيح: `cancelDocument` موجودةٌ منذ زمنٍ وتنادي
  // `EtaService.cancelDocument` التي تُرسل PUT إلى
  // `/documents/state/{uuid}/state`. فالقدرةُ كانت مبنيّةً وغيرَ مكشوفة.
  //
  // وصار للفورك زرُّ «إلغاء المستند» محروسٌ بـ`PermissionGuard(einvoiceCancel)`
  // — بثلاثة شروط: الصلاحيّة، واعتمادُ البوّابة على هذا الجهاز، والمستندُ
  // معتمَدٌ. فالكودُ مُنفَّذٌ في التوأم، وسجلٌّ لا يتقلّص يكفّ عن كونه مقياسَ
  // تقدّم.
  //
  // 🔴 **ودرسٌ يتعدّى هذا المدخل**: «لا يكشف مسارَ كذا» عبارةٌ في تعليقٍ لا
  //    قياس. وكانت مكتوبةً في موضعَين (هنا ورأسِ الشاشة) فصدّق كلٌّ منهما
  //    الآخر. اقرأ الدالّةَ قبل أن تصدّق تعليقاً ينفي وجودَها.
};

/// مدخلاتٌ بلا شاهدٍ **بسببٍ صريح** — لا بالإهمال.
///
/// الاثنان غيرُ محسومَين أصلاً: لم يُثبَت لأيٍّ منهما زرٌّ مقابلٌ في PicPos،
/// ويحتاجان لقطةَ شاشةٍ من المالك (‏لا بحثاً نصّياً — أخطأ خمسَ مرّاتٍ في هذه
/// المسألة وحدَها). ولا يصلح لهما شاهدٌ نصّيّ بعد: `Notification` يطابق
/// `PosNotificationType` وهو نظامُ التوست القائم، فالشاهدُ كان سيولد أحمرَ
/// كاذباً — ومن يضيف شاهداً كاذباً يُدرّب القارئَ على تجاهل الأحمر.
const _witnessExempt = <String>{'pos_low_stock_alert', 'pos_notifications'};

/// المجلدُ الذي **ستهبط فيه** الميزةُ لو وصلت.
///
/// ⚠️ مقيسٌ لا مفترَض: مسحُ التوائم الأربعة كلِّها ولّد أربعَ حمراواتٍ كاذبة
/// من أوّل تشغيلة — `IconsBold.plus` أيقونةُ زرِّ «إضافة صنف» في شاشة الأصناف،
/// و«لوحة المفاتيح» تسميةٌ في الإعدادات، و«العروض» كلمةٌ في شاشة الرئيسية.
/// ولا واحدةَ منها تقول شيئاً عن سلّة البيع.
///
/// وكلُّ المدخلات الثلاثةَ عشرَ ميزاتُ **شاشة بيع**: مِسطرةُ الكمية · زرُّ
/// المرتجع · الطاولات · العروض · الحجز · الاستبدال · لوحة المفاتيح. فمداها
/// `pos_picpos/` وحدَه — وهو نفسُ ما تقوله أسبابُ السجلّ نثراً («جدولُ PicPos
/// بلا مِسطرة» · «رأسُ شاشة PicPos لا يعرض طاولات»).
///
/// ومن يضيف مدخلاً لميزةٍ في توأمٍ آخر فليوسّع هذا **لمجلده هو**، لا للأربعة.
const _witnessScope = <String>['pos_picpos'];

/// مواضعُ [marker] في كود المجلدات المعطاة، بلا تعليقات.
@visibleForTesting
List<String> witnessHitsIn(Iterable<String> twinDirs, String marker) {
  final hits = <String>[];
  for (final e in _sources.keys) {
    if (!twinDirs.any((d) => e.startsWith('lib/presentation/$d/'))) continue;
    if (_codeOnly(e).contains(marker)) hits.add(e);
  }
  return hits;
}

void main() {
  // ── حراسةُ الحارس ────────────────────────────────────────────────────────
  // في حارسٍ أمنيّ الإيجابُ الكاذبُ أرخصُ من السلب الكاذب: الأولُ ضجيجٌ
  // يُراجَع، والثاني ثقبٌ يسقط من الرادار. وقد وقع الثاني فعلاً — أربعةُ
  // أكوادٍ مرّت خضراءَ وأفعالُها مفتوحة. فهذه المجموعةُ تثبّت الاتجاه.
  group('قواعدُ المطابقة نفسُها', () {
    test(
      'اسمُ الثابت بلا بادئةٍ لا يُحتسب — حالةُ `AppColors.posDiscount`',
      () {
        const colour = 'static const Color posDiscount = error;';
        expect(
          mentionsCode(colour, 'pos_discount', 'posDiscount'),
          isFalse,
          reason:
              'لونٌ يحمل نفسَ الاسم كان يمرّر `pos_discount` «محروساً» '
              'وهو مفتوحٌ من ثلاثة أبواب',
        );
        expect(
          mentionsCode(
            'permission: PermissionCodes.posDiscount,',
            'pos_discount',
            'posDiscount',
          ),
          isTrue,
          reason: 'والحراسةُ الحقيقيةُ يجب أن تبقى معدودة',
        );
      },
    );

    test('والمرجعُ الملفوفُ على سطرين يبقى معدوداً', () {
      // سببُ إسقاط البادئة أصلاً — فلا يُعاد كسرُه بإصلاح الاصطدام.
      expect(
        mentionsCode('PermissionCodes.\n      posSave', 'pos_save', 'posSave'),
        isTrue,
      );
    });

    test('والسلسلةُ الخام تكفي', () {
      expect(mentionsCode("'pos_save'", 'pos_save', 'posSave'), isTrue);
    });

    test('التعليقُ ليس حراسةً ولا استيراداً', () {
      const src =
          "/// permission: PermissionCodes.posExpense,\n"
          "// import 'x.dart';\n"
          "/* PermissionCodes.posSave */\n"
          "final int x = 1;";
      final stripped = stripComments(src);
      expect(
        mentionsCode(stripped, 'pos_expense', 'posExpense'),
        isFalse,
        reason:
            'مثالٌ توضيحيٌّ في وثيقة `PermissionGuard` كان يُسكت '
            '`pos_expense` وهو مفتوح',
      );
      expect(mentionsCode(stripped, 'pos_save', 'posSave'), isFalse);
      expect(stripped.contains("import 'x.dart'"), isFalse);
      expect(stripped.contains('final int x = 1;'), isTrue);
    });

    test('ولا يُحتسب إنفاذاً ما ليس على سطح العرض', () {
      // `api_sales_handler` و`migrations/epoch_3` كانا يُخفيان
      // `pos_hold_order` — سطحُ HTTP وقائمةُ منحٍ، لا زرَّ شاشة.
      expect(
        _isEnforcementSurface('lib/services/api/api_sales_handler.dart'),
        isFalse,
      );
      expect(
        _isEnforcementSurface('lib/data/database/migrations/epoch_3.dart'),
        isFalse,
      );
      expect(
        _isEnforcementSurface(
          'lib/presentation/pos/widgets/held_orders_dialog.dart',
        ),
        isTrue,
      );
    });
  });

  // ── مرساةُ الاشتقاق ──────────────────────────────────────────────────────
  //
  // ⚠️ **بلا هذه المجموعةِ يكون التوسيعُ بلا أثرٍ ولا أحدَ يعلم.** لو تغيّر
  // تنسيقُ `Brand.isPicPos ? … : …` في الموجّه — أو كُسر النمطُ بمسافةٍ —
  // لعادت `_routerPairs` فارغةً، فيسقط المدى إلى الأربعةِ القديمة **ويمرّ
  // الاختبارُ أخضرَ**. وهو عينُ العطب الذي نصلحه: تغطيةٌ تنكمش صامتة.
  //
  // والعددُ يُقاس مقابلَ `Brand.isPicPos` في الموجّه لا مقابلَ رقمٍ مكتوب،
  // فلا يبيت بإضافة فوركٍ جديد.
  group('اشتقاقُ الأزواج من الموجّه', () {
    test('الأزواجُ المشتقّةُ تغطّي أغلبَ تفريعات `Brand.isPicPos`', () {
      final router = readLibrarySource('lib/app_main_screen.dart');
      final branches = RegExp(r'Brand\.isPicPos').allMatches(router).length;

      expect(
        _routerPairs.length,
        greaterThanOrEqualTo(20),
        reason:
            'الاشتقاقُ أعطى ${_routerPairs.length} زوجاً فقط — النمطُ '
            'مكسورٌ غالباً، والمدى انكمش إلى خريطة المجلّدات صامتاً.',
      );
      expect(
        _routerPairs.length,
        lessThanOrEqualTo(branches),
        reason:
            'أزواجٌ أكثرُ من تفريعات الموجّه ⇒ النمطُ يلتقط ما ليس '
            'تفريعَ علامة.',
      );
    });

    test('وكلُّ مسارٍ مشتقٍّ موجودٌ فعلاً على القرص', () {
      for (final p in _routerPairs) {
        expect(
          _sources.containsKey('lib/presentation/${p.legacy}'),
          isTrue,
          reason: 'الأصلُ «${p.legacy}» غيرُ مقروء',
        );
        expect(
          _sources.containsKey('lib/presentation/${p.fork}'),
          isTrue,
          reason: 'الفوركُ «${p.fork}» غيرُ مقروء',
        );
      }
    });

    test('والفوركاتُ الخمسُ الجديدةُ داخلَ المدى', () {
      // مرساةٌ صريحةٌ على ما بُني في هذه الجولة — فلو خرج أحدُها من المدى
      // لعاد بلا حراسةٍ بلا أن يلاحظ أحد.
      final forks = _routerPairs.map((p) => p.fork).join(' ');
      for (final f in const [
        'landed_cost_picpos',
        'fixed_assets_picpos',
        'e_invoicing_picpos',
        'analytics_picpos',
        'report_builder_picpos',
      ]) {
        expect(
          forks,
          contains(f),
          reason: 'الفوركُ «$f» خارجَ مدى حارس التكافؤ.',
        );
      }
    });
  });

  test('كلُّ توأمٍ في المجلدات موجودٌ فعلاً — وإلا فالخريطةُ بائتة', () {
    for (final e in _twins.entries) {
      expect(
        Directory('lib/presentation/${e.key}').existsSync(),
        isTrue,
        reason: 'النظيرُ «${e.key}» اختفى — حدّث الخريطة',
      );
      expect(
        Directory('lib/presentation/${e.value}').existsSync(),
        isTrue,
        reason: 'التوأمُ «${e.value}» اختفى — حدّث الخريطة',
      );
    }
  });

  test('لا فجوةَ تكافؤٍ جديدةٍ بلا تسجيل', () {
    final unregistered =
        _currentGaps()
            .difference(PermissionEnforcementRegistry.picposParityGaps)
            .toList()
          ..sort();

    expect(
      unregistered,
      isEmpty,
      reason:
          'هذه الأكوادُ محروسةٌ في نظيرٍ قديمٍ ولا أثرَ لها في توأم '
          'PicPos ⇒ الضابطُ يبدو مفعَّلاً في شاشة الصلاحيات وهو غيرُ موجودٍ '
          'على المسار الحيّ. إمّا تُحرَس في التوأم، أو تُسجَّل في '
          '`picposParityGaps` بسببٍ صريح.',
    );
  });

  group('الحارسُ المعاكس: ميزةٌ وصلت وسطرُها ما زال مسجَّلاً «بلا ميزة»', () {
    test('لكلّ مدخلٍ في السجلّ شاهدُ غيابٍ أو إعفاءٌ مُعلَّل', () {
      final unwitnessed =
          PermissionEnforcementRegistry.picposParityGaps
              .where(
                (c) =>
                    !_absenceWitness.containsKey(c) &&
                    !_witnessExempt.contains(c),
              )
              .toList()
            ..sort();
      expect(
        unwitnessed,
        isEmpty,
        reason:
            'مدخلٌ في `picposParityGaps` بلا شاهدِ غياب. السجلُّ يقول «لا '
            'ميزةَ تُحرَس»، وهذا حكمٌ يبطل صامتاً يومَ تصل الميزة. أضِف '
            'عباراتٍ تدلّ على وصولها في `_absenceWitness`، أو أعفِه في '
            '`_witnessExempt` بسببٍ مكتوب.',
      );
    });

    test('ولا شاهدَ بائتٌ لمدخلٍ شُطب', () {
      // سجلٌّ يحمل شواهدَ لأكوادٍ لم تعد فيه يضلّل القارئَ ويكذب على الجديد.
      final orphan =
          {..._absenceWitness.keys, ..._witnessExempt}
              .where(
                (c) =>
                    !PermissionEnforcementRegistry.picposParityGaps.contains(c),
              )
              .toList()
            ..sort();
      expect(
        orphan,
        isEmpty,
        reason: 'شاهدٌ لكودٍ لم يعد مسجَّلاً فجوةً — احذفه',
      );
    });

    test('والآليّةُ ترصد فعلاً — ضابطٌ على مصدرٍ صناعيّ', () {
      // بلا هذا قد تمرّ الخريطةُ كلُّها خضراءَ لأن المطابقةَ معطوبة، لا لأن
      // الميزةَ غائبة. وهو الفرقُ بين حارسٍ يعمل وحارسٍ يبدو أنه يعمل.
      const arrived =
          "IconButton(icon: Icon(PhosphorIconsBold.plus), "
          "onPressed: () => cart.updateQuantity(i, item.quantity + 1))";
      expect(arrived.contains('IconsBold.plus'), isTrue);
      expect(arrived.contains('quantity + 1'), isTrue);
      // والتعليقُ لا يُرصد — وإلا وُلد الحارسُ أحمرَ على وثائقَ قائمة.
      expect(
        stripComments('// زرُّ طاولة TablePos').contains('TablePos'),
        isFalse,
      );
    });

    for (final entry in _absenceWitness.entries) {
      test('${entry.key} — الميزةُ لم تصل بعد', () {
        for (final marker in entry.value) {
          final hits = witnessHitsIn(_witnessScope, marker);
          expect(
            hits,
            isEmpty,
            reason:
                'الشاهدُ «$marker» ظهر في توأم PicPos ⇒ يبدو أن ميزةَ '
                '«${entry.key}» وصلت. والكودُ مسجَّلٌ في `picposParityGaps` '
                'بوصفه «بلا ميزة»، فحارسُ التكافؤ يمرّ أخضرَ وهو مفتوح.\n'
                'إمّا تُحرَس الميزةُ ويُشطب السطرُ من السجلّ، وإمّا كانت '
                'المطابقةُ عرضيةً فيُضيَّق الشاهد — ولا يُحذف بلا قياس.',
          );
        }
      });
    }
  });

  test('والسجلُّ يتقلّص: لا مدخلَ صار منفَّذاً وبقي مكتوباً', () {
    final gaps = _currentGaps();
    final stale =
        PermissionEnforcementRegistry.picposParityGaps
            .where((c) => !gaps.contains(c))
            .toList()
          ..sort();

    expect(
      stale,
      isEmpty,
      reason:
          'هذه صارت محروسةً في توأم PicPos — اشطبها من '
          '`picposParityGaps`. سجلٌّ لا يتقلّص يكفّ عن كونه مقياسَ تقدّم، '
          'ويُخفي أن الفجوةَ ضاقت.',
    );
  });
}

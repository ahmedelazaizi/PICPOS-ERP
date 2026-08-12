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

import 'package:flutter_test/flutter_test.dart';
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
  final src =
      File('lib/core/permissions/permission_codes.dart').readAsStringSync();
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

/// ملفاتُ النظير القديم التي **يستوردها** التوأمُ صراحةً.
///
/// ⚠️ بلا هذا يُحسب زوراً فجوةً كلُّ كودٍ محروسٍ في ملفٍ مُعادِ استخدامه: توأمُ
/// الخزينة يستورد `treasury/widgets/receipt_voucher_dialog.dart` بحراسته كما
/// هي، فالحراسةُ تصل إلى الشاشة فعلاً. قياسُ **المجلد** وحدَه كان سيطالب
/// بتكرار حراسةٍ قائمة — وهو ضدُّ غرض الحارس.
/// ⚠️ والبلوغُ **متعدٍّ**: قفزةٌ واحدةٌ كانت تفوّت الحراسةَ الواصلةَ عبر
/// وسيط. `pos_customer_add` مثالُه المقيس — PicPos يستورد
/// `pos/widgets/pos_customer_selection_dialog.dart`، وهو بدورِه يستورد
/// `customer_selector_v2.dart` حيث الحارسُ فعلاً. فحسبه الحارسُ فجوةً وهو
/// منفَّذٌ على المسار الحيّ منذ Task 7.
Set<String> _legacyFilesImportedBy(String twin, String legacy) {
  final root = 'lib/presentation/$legacy/';
  final seen = <String>{};
  final queue = <String>[];

  final re = RegExp("(?:import|part)\\s+'([^']+\\.dart)'");

  void enqueue(String path) {
    if (!path.startsWith(root)) return;
    if (!seen.add(path)) return;
    queue.add(path);
  }

  for (final e in _sources.entries) {
    if (!e.key.startsWith('lib/presentation/$twin/')) continue;
    for (final m in re.allMatches(e.value)) {
      final resolved = _resolveImport(e.key, m.group(1)!);
      if (resolved != null) enqueue(resolved);
    }
  }

  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    final src = _sources[current];
    if (src == null) continue;
    for (final m in re.allMatches(src)) {
      final resolved = _resolveImport(current, m.group(1)!);
      if (resolved == null) continue;
      // ⚠️ الاستيرادُ وحدَه لا يكفي بعد القفزة الأولى: البراميلُ والاستيرادُ
      // العارض يجرّان رسمَ استيرادٍ كاملاً فيُعَدُّ محروساً ما لا يُرسم —
      // وهذا اتجاهُ الخطأ الخطر (فجوةٌ حقيقيةٌ تُخفى). فلا تُتبَع الحافةُ إلا
      // إن كان الملفُّ المستورِد **يذكر فعلاً** رمزاً معرَّفاً في المستورَد.
      if (_referencesSymbolOf(src, resolved)) enqueue(resolved);
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

/// هل يُذكر الكودُ (نصّاً خاماً أو ثابتاً) في ملفٍّ تحت [dir]؟
///
/// ⚠️ المرجعُ قد يُلَفّ على سطرين (`PermissionCodes.\n  posSave`) — فالبحثُ
/// عن الثابت **بلا** بادئته، مقيَّداً بحدّ كلمة. البحثُ عن السطر الكامل كان
/// يفوّت الملفوفَ ويعطي إيجاباً كاذباً بأن الحراسةَ غائبة.
bool _mentionedIn(String dir, String code, String? constName) {
  final prefix = 'lib/presentation/$dir/';
  for (final e in _sources.entries) {
    if (!e.key.startsWith(prefix)) continue;
    if (e.value.contains("'$code'")) return true;
    if (constName != null && RegExp('\\b$constName\\b').hasMatch(e.value)) {
      return true;
    }
  }
  return false;
}

/// هل يُذكر في أيّ موضعٍ **خارج** النظير القديم وتوأمه؟
bool _mentionedElsewhere(String legacy, String twin, String code, String? c) {
  for (final e in _sources.entries) {
    if (e.key.startsWith('lib/presentation/$legacy/')) continue;
    if (e.key.startsWith('lib/presentation/$twin/')) continue;
    if (e.value.contains("'$code'")) return true;
    if (c != null && RegExp('\\b$c\\b').hasMatch(e.value)) return true;
  }
  return false;
}

Set<String> _currentGaps() {
  final byCode = _constantNameByCode();
  final gaps = <String>{};
  for (final entry in _twins.entries) {
    final legacy = entry.key, twin = entry.value;
    final reused = _legacyFilesImportedBy(twin, legacy);
    for (final code in byCode.keys) {
      final c = byCode[code];
      if (!_mentionedIn(legacy, code, c)) continue;
      if (_mentionedIn(twin, code, c)) continue;
      // ملفٌّ قديمٌ يستورده التوأمُ = حراستُه تصل إلى الشاشة.
      final viaImport = reused.any((p) {
        final src = _sources[p];
        if (src == null) return false;
        return src.contains("'$code'") ||
            (c != null && RegExp('\\b$c\\b').hasMatch(src));
      });
      if (viaImport) continue;
      if (_mentionedElsewhere(legacy, twin, code, c)) continue;
      gaps.add(code);
    }
  }
  return gaps;
}

void main() {
  test('كلُّ توأمٍ في المجلدات موجودٌ فعلاً — وإلا فالخريطةُ بائتة', () {
    for (final e in _twins.entries) {
      expect(Directory('lib/presentation/${e.key}').existsSync(), isTrue,
          reason: 'النظيرُ «${e.key}» اختفى — حدّث الخريطة');
      expect(Directory('lib/presentation/${e.value}').existsSync(), isTrue,
          reason: 'التوأمُ «${e.value}» اختفى — حدّث الخريطة');
    }
  });

  test('لا فجوةَ تكافؤٍ جديدةٍ بلا تسجيل', () {
    final unregistered = _currentGaps()
        .difference(PermissionEnforcementRegistry.picposParityGaps)
        .toList()
      ..sort();

    expect(
      unregistered,
      isEmpty,
      reason: 'هذه الأكوادُ محروسةٌ في نظيرٍ قديمٍ ولا أثرَ لها في توأم '
          'PicPos ⇒ الضابطُ يبدو مفعَّلاً في شاشة الصلاحيات وهو غيرُ موجودٍ '
          'على المسار الحيّ. إمّا تُحرَس في التوأم، أو تُسجَّل في '
          '`picposParityGaps` بسببٍ صريح.',
    );
  });

  test('والسجلُّ يتقلّص: لا مدخلَ صار منفَّذاً وبقي مكتوباً', () {
    final gaps = _currentGaps();
    final stale = PermissionEnforcementRegistry.picposParityGaps
        .where((c) => !gaps.contains(c))
        .toList()
      ..sort();

    expect(
      stale,
      isEmpty,
      reason: 'هذه صارت محروسةً في توأم PicPos — اشطبها من '
          '`picposParityGaps`. سجلٌّ لا يتقلّص يكفّ عن كونه مقياسَ تقدّم، '
          'ويُخفي أن الفجوةَ ضاقت.',
    );
  });
}

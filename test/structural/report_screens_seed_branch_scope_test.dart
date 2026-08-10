// حارسٌ بنيويّ — كلُّ شاشةِ تقريرٍ تبذر فرعاً على أوّل تحميلٍ لازم **تحلّه**
// إلى نطاق الاستعلام قبل أوّل جلبٍ للبيانات.
//
// ── فئةُ العطب (H13) ────────────────────────────────────────────────────────
// `initState` يبذر `_selectedBranchId` من `activeBranchIdProvider`
// (‏Feature 058) ثم ينادي `_loadData` مباشرةً، بينما حلَّ الفرعِ إلى
// `_branchWarehouseIds` / `_branchSafeIds` يعيش داخل `onBranchChanged` وحدَه.
//
// فعلى أوّل تحميل: **القائمةُ تُظهر اسمَ الفرع والأرقامُ لكلّ الفروع**، ولا
// شيءَ على الشاشة يكشف الفرق. المستخدمُ يقرأ رقمَ الشركة ظانّاً أنه رقمُ فرعه.
//
// و`allowedBranchIds` لا يُنقذ: سقفُ **صلاحية** لا فلترُ عرض — صاحبُ الوصول
// الكامل يأخذ `null` فلا يحدّ شيئاً.
//
// ── ليه بنيويّ ─────────────────────────────────────────────────────────────
// وقعت في **عشر** شاشاتٍ دفعةً واحدة، وكلُّ شاشةٍ جديدة تنسخ نفسَ قالب
// Feature 058. الاختبارُ السلوكيُّ يغطّي ما تذكّر أحدٌ أن يكتب له؛ وهذا يسقط
// لحظةَ إضافةِ شاشةٍ تبذر بلا أن تحلّ.
//
// ملاحظة: هذا يفرض **الاستدعاء**، لا صحّةَ النتيجة. الإنفاذُ الفعليّ محروسٌ
// سلوكياً (‏`treasury_report_branch_scope_d01_test` وأخواتُه).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// جسمُ `initState` — من ترويسته حتى أوّل `}` على مستوى الدالّة.
String _initStateBody(String source) {
  final start = source.indexOf('void initState()');
  if (start < 0) return '';
  final end = source.indexOf('\n  }', start);
  return end < 0 ? source.substring(start) : source.substring(start, end);
}

void main() {
  test('كلُّ شاشةِ تقريرٍ تبذر فرعاً تحلّه في initState', () {
    final offenders = <String>[];

    for (final entity in Directory('lib/presentation/screens/reports').listSync()) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();

      // الشاشاتُ المعنيّة: تبذر فرعاً **و** لها حقلُ نطاقٍ للاستعلام.
      final seedsBranch = src.contains('activeBranchIdProvider');
      final hasScopeField = src.contains('_branchWarehouseIds') ||
          src.contains('_branchSafeIds');
      if (!seedsBranch || !hasScopeField) continue;

      final body = _initStateBody(src);
      final resolves = body.contains('_branchWarehouseIds =') ||
          body.contains('_branchSafeIds =') ||
          body.contains('_resolveBranch');
      if (!resolves) offenders.add(entity.path);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'الشاشةُ تبذر `_selectedBranchId` وما بتحلّهوش قبل أوّل '
          '`_loadData` ⇒ العنوانُ يقول فرعاً والأرقامُ تقول شركة. حلَّ '
          'النطاقَ بعد البذر مباشرةً (‏شوف treasury_report_screen). '
          'المواضع:\n  ${offenders.join('\n  ')}',
    );
  });

  test('ضابط: الحارسُ فاحصٌ لعشر شاشاتٍ على الأقل', () {
    var considered = 0;
    for (final entity in Directory('lib/presentation/screens/reports').listSync()) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      if (src.contains('activeBranchIdProvider') &&
          (src.contains('_branchWarehouseIds') ||
              src.contains('_branchSafeIds'))) {
        considered++;
      }
    }
    expect(considered, greaterThanOrEqualTo(10),
        reason: 'لو نزل العددُ فجأةً فإما اتشالت شاشات وإما اتغيّر القالب '
            'فبقى الحارسُ يمرّ على لا شيء');
  });
}

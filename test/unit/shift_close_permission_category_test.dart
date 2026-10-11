// «إغلاقُ الوردية» خارجَ فئة البيع السريع.
//
// ── طلبُ المالك (2026-08-14) ────────────────────────────────────────────────
// «الإغلاقُ له صلاحيةٌ خارجَ إعداد صلاحيات نقطة البيع، بحيث يكون المديرُ هو
// من يجرد، فلا يقدر الكاشيرُ على الإغلاق بدونه.»
//
// وقرارُه بين ثلاثةِ خيارات: **نقلُ الفئة** لا كودٌ جديد. والسببُ مقيس:
// الكودُ نفسُه لا يتغيّر ⇒ لا بذرةَ جديدةً ولا منحاً يدوياً في القواعد
// القائمة، ولا يفقد أحدٌ صلاحيةً يملكها اليوم.
//
// ── ولماذا الفتحُ يبقى في `pos` ────────────────────────────────────────────
// الفتحُ فعلُ كاشيرٍ يوميّ (`_ensureShiftOpen` يناديه عند دخول الشاشة)،
// والإغلاقُ **جردٌ** — وهو ما طلب المالكُ فصلَه. فالتماثلُ الاسميُّ بين
// الاثنين لا يعني تماثلَ الدور.
//
// ── وثلاثةُ مواضعَ لا موضعٌ واحد ───────────────────────────────────────────
// الفئةُ مكتوبةٌ في ماستر `PermissionCodes` **وفي** بذرة SQLite **وفي** بذرة
// PostgreSQL. وشاشةُ الصلاحيات تقرأ الفئةَ من **صفّ القاعدة** لا من الماستر
// (`authRepo.getAllPermissions()`)، والبذرةُ `InsertMode.insertOrIgnore` —
// فقاعدةٌ منصَّبةٌ سلفاً تحتفظ بالفئة القديمة إلى الأبد بلا هجرة. ولذلك
// يقيس هذا الملفُّ الهجرةَ أيضاً، لا الثوابتَ وحدَها.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';

import '../helpers/epoch3_source.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  test('الماسترُ يضع «إغلاق الوردية» في الخزينة لا في البيع السريع', () {
    final entry = PermissionCodes.masterList.firstWhere(
      (p) => p['code'] == PermissionCodes.posShiftClose,
      orElse: () => <String, String>{},
    );
    expect(entry, isNotEmpty, reason: 'الكودُ نفسُه اختفى من الماستر');
    expect(entry['category'], equals('treasury'));
  });

  test('وفتحُ الوردية يبقى في البيع السريع — الفصلُ مقصودٌ لا سهو', () {
    final entry = PermissionCodes.masterList.firstWhere(
      (p) => p['code'] == PermissionCodes.posShiftOpen,
      orElse: () => <String, String>{},
    );
    expect(entry['category'], equals('pos'));
  });

  test('و«الخزينة» فئةٌ معرَّفةٌ باسمٍ عربيّ — وإلا ظهرت مجموعةٌ بلا عنوان', () {
    expect(PermissionCodes.categoryNames['treasury'], isNotNull);
  });

  group('البذرتان تطابقان الماستر', () {
    for (final path in const [
      'lib/data/database/database_seeder_permissions.dart',
      'lib/data/database/database_seeder_postgres.dart',
    ]) {
      test(path.split('/').last, () {
        final src = _stripComments(File(path).readAsStringSync());
        // كلُّ ذكرٍ للكود يقترن بفئةٍ في نفس المدخل. نلتقط المدخلَ كاملاً بين
        // قوسَي الخريطة ثم نقرأ فئتَه.
        final entries = RegExp(
          r"\{[^{}]*'pos_shift_close'[^{}]*\}",
          dotAll: true,
        ).allMatches(src);
        if (entries.isEmpty) return; // هذه البذرةُ لا تحمل فئاتٍ أصلاً
        for (final e in entries) {
          final text = e.group(0)!;
          if (!text.contains("'category'")) continue;
          expect(
            text.contains("'treasury'"),
            isTrue,
            reason: 'مدخلٌ ما زال على الفئة القديمة: $text',
          );
        }
      });
    }
  });

  test('وثمّة هجرةٌ تنقل الصفوفَ القائمة — البذرةُ لا تصلها', () {
    // `insertOrIgnore` يعني أن قاعدةَ المالك ستُبقي 'pos' للأبد بلا هذه
    // الهجرة، فتظهر الصلاحيةُ في المكان الذي طلب إخراجَها منه.
    final src = _stripComments(
      readEpoch3Source(),
    );
    final moves = RegExp(
      r"UPDATE permissions[\s\S]{0,200}?pos_shift_close",
    ).hasMatch(src);
    expect(
      moves,
      isTrue,
      reason: 'لا هجرةَ تنقل فئةَ pos_shift_close في القواعد القائمة',
    );
  });
}

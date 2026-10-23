// حارسُ العقد: كلُّ جدولٍ يُسحَب يحمل مُشغِّلَ الختم على PostgreSQL.
//
// ═══ فئةُ العطب — مقيسةٌ 2026-09-02 ═══
//
// `AppDatabase._syncHardenedTables` هي القائمةُ التي يعلّق عليها
// `_ensurePostgresSyncInfrastructure` مُشغِّلَ `fn_bump_row_version` —
// و**هو الوحيدُ** الذي يختم `last_modified_at` عند الإدراج (SQLite بلا
// مُشغِّلِ إدراجٍ أصلاً). ومسارُ السحب يرشّح بـ
// `last_modified_at IS NOT NULL AND last_modified_at > since`.
//
// فجدولٌ في `pullTables` وغائبٌ عن هذه القائمة يعمل **مرّةً واحدةً**: أوّلُ
// سحبٍ (‏`since = null`) يفرّغه كاملاً، وكلُّ صفٍّ يُدرَج بعده على خادم
// PostgreSQL يُولَد بختمٍ فارغٍ فلا يراه أيُّ عميلٍ أبداً — إلّا أن يُعدَّل.
//
// وهكذا كانت المرحلتان ٢ و٣ (اثنا عشرَ + تسعةَ عشرَ جدولاً) و`purchase_returns`:
// **اثنان وثلاثون جدولاً** في القوائم الستِّ كلِّها وغائبةٌ عن السابعة. ولا
// يمسكه اختبارُ وحدة: `forTesting()` على SQLite، وفحوصُ الهجرة تقيس الأعمدةَ
// لا الختم. فصار لذلك حارسان: هذا يثبّت **العضويّة**، و
// `pg_phase4_sync_columns_pg_test` يثبّت **الختمَ** على PostgreSQL حيّة.
//
// ═══ ما لا يفعله ═══
//
// حارسُ بنيةٍ: عضويّةُ القائمة لا تثبت أنّ المُشغِّلَ رُكِّب فعلاً ولا أنّه
// يختم. ذاك يُقاس على PostgreSQL وحدَها.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';

/// جداولُ في القائمة المصلَّبة وليست في `pullTables` — **بحكمٍ مكتوب**.
///
/// `printers` أُخرجت من السحب بقرار مالك 2026-08-31 (إعدادٌ جهازيّ)، وبقيت
/// هنا لأنّ المُشغِّلَ عليها بلا ضررٍ وأعمدتَها قائمة.
const _hardenedButNotPulled = <String>{
  'printers',
};

void main() {
  final hardened = AppDatabase.syncHardenedTablesForTest.toSet();
  final pulled = DeltaPullService.pullTables.toSet();

  group('مرساةُ الكشف — قبلَ أيِّ حكم', () {
    test('القائمتان مقروءتان وليستا فارغتَين', () {
      expect(hardened.length, greaterThan(40),
          reason: 'القائمةُ المصلَّبةُ انكمشت دون الأربعين الأصليّة');
      expect(pulled.length, greaterThan(40));
    });

    test('ومرساةٌ موجبة: `parties` في الاثنتَين', () {
      expect(hardened, contains('parties'));
      expect(pulled, contains('parties'));
    });

    test('ولا اسمَ مكرَّرٌ في القائمة المصلَّبة', () {
      // مكرَّرٌ يرفع `length` فيجعل فحصَ «المُشغِّلاتُ مركَّبةٌ سلفاً» في
      // `_ensurePostgresSyncInfrastructure` يعدّ أكثرَ ممّا يركّب.
      final list = AppDatabase.syncHardenedTablesForTest;
      expect(list.length, hardened.length,
          reason: 'أسماءٌ مكرَّرة: '
              '${list.where((t) => list.where((u) => u == t).length > 1).toSet()}');
    });
  });

  test('🔴 كلُّ جدولٍ في `pullTables` يحمل مُشغِّلَ PostgreSQL', () {
    final missing = pulled.difference(hardened).toList()..sort();

    expect(
      missing,
      isEmpty,
      reason: 'جداولُ تُسحَب وبلا مُشغِّلِ ختمٍ على PostgreSQL:\n'
          '  ${missing.join('\n  ')}\n\n'
          'كلُّ صفٍّ يُدرَج فيها على خادم PostgreSQL يُولَد بـ'
          '`last_modified_at = NULL`، ومسارُ السحب يرشّحه فلا يصل أيَّ '
          'عميلٍ بعد أوّل سحب. أضِف الاسمَ إلى '
          '`AppDatabase._syncHardenedTables`.',
    );
  });

  test('ولا اسمَ بائتٍ في القائمة المصلَّبة', () {
    final ghosts = hardened
        .difference(pulled)
        .difference(_hardenedButNotPulled)
        .toList()
      ..sort();

    expect(ghosts, isEmpty,
        reason: 'أسماءٌ مصلَّبةٌ لا تُسحَب ولا حكمَ لها في '
            '`_hardenedButNotPulled`: ${ghosts.join('، ')} — إمّا حُذف '
            'الجدولُ أو أُعيدت تسميتُه، والقائمةُ تحمي جدولاً لا يُسحَب.');
  });

  test('ومدى الحارس لم ينكمش — المرحلتان ٢ و٣ محميّتان بأسمائهما', () {
    // هذه هي الاثنان والثلاثون التي كُشف غيابُها. حذفُ أحدها من القائمة
    // المصلَّبة يُعيد العطبَ له وحدَه، وفحصُ الفرق أعلاه يمسكه — لكنّ
    // حذفَه من `pullTables` **معاً** يمرّ صامتاً، فيُسمّى هنا.
    const phases2and3 = <String>{
      'asset_categories', 'op_expense_categories', 'bill_of_materials',
      'fixed_assets', 'manufacturing_orders', 'bom_components',
      'op_expenses', 'asset_depreciations', 'mfg_order_costs',
      'landed_cost_sheets', 'landed_cost_items', 'landed_cost_allocations',
      'purchase_returns',
      'employees',
      'table_sections', 'restaurant_tables', 'table_orders',
      'table_order_items', 'table_reservations', 'table_order_payments',
      'kitchen_stations', 'category_station_mappings',
      'work_orders', 'work_order_items',
      'booking_resources', 'booking_services', 'bookings', 'booking_reminders',
      'sales_routes', 'route_visits', 'sales_rep_targets',
      'sales_rep_collections',
    };
    expect(phases2and3.length, 32);
    final gone = phases2and3.difference(hardened).toList()..sort();
    expect(gone, isEmpty,
        reason: 'خرجت من القائمة المصلَّبة: ${gone.join('، ')}');
  });
}

// حارسُ العقد: جدولٌ لا تملؤه `fullSync` لا تُبذَر علامتُه المائيّة.
//
// ═══ فئةُ العطب ═══
//
// الإقلاعُ الأوّلُ لعميلٍ بلا علاماتٍ يشغّل `SyncService.fullSync()` — وهي
// تعمل بالاستراتيجيّات لا بمسار الدلتا — ثمّ يبذر `seedWatermarks` علامةَ
// **كلِّ** جدولٍ في `pullTables` على لحظة الخادم، بحجّةِ أنّ الاستراتيجيّات
// نزّلته للتوّ.
//
// والحجّةُ تسقط لجدولٍ لا استراتيجيّةَ له: يُبذَر ولم يُملأ، فالسحبُ التالي
// يسأل عمّا تغيّر **بعد** تلك اللحظة، وكلُّ صفٍّ أقدمَ يُتخطّى ولا يُطلَب
// ثانيةً. عميلٌ ينضمّ اليومَ لا يرى ورقةَ تحميلٍ من أمس — أبداً.
//
// وهذا نفسُ «تسميم العلامة» الموصوف في `delta_pull_service.dart`، من بابٍ
// مختلف: ذاك سببُه ردٌّ مقصوصٌ من الخادم، وهذا سببُه بذرٌ بلا تنزيل.
//
// ═══ ما يفعله هذا الملفّ ═══
//
// يثبّت أنّ `deltaOnlyTables` تصف الواقعَ: كلُّ اسمٍ فيها جدولٌ يُسحَب فعلاً،
// ولا اسمَ فيها لجدولٍ **له** استراتيجيّةٌ في `fullSync` (‏وإلّا حُرم من بذرٍ
// يستحقّه فدفع تفريغاً كاملاً كلَّ إقلاع).

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/delta_pull_service.dart';

/// جداولٌ نعلم يقيناً أنّ لها استراتيجيّةً في `fullSync` — **مرساةُ الحارس**.
///
/// ⚠️ بلا هذه المرساةِ يمرّ الحارسُ أخضرَ ولو أُفرغت `deltaOnlyTables` تماماً:
/// المجموعةُ الفارغةُ تحقّق كلَّ فحصٍ فيها. فالمرساةُ تُثبت أنّ المدى قائم.
const _knownStrategyBacked = <String>{
  'parties',
  'products',
  'sales_invoices',
  'purchase_invoices',
  'journal_entries',
  'safe_transactions',
  'accounts',
  'branches',
};

void main() {
  test('كلُّ جدولٍ بلا بذرٍ جدولٌ يُسحَب فعلاً — لا اسمَ بائت', () {
    final ghosts = DeltaPullService.deltaOnlyTables
        .where((t) => !DeltaPullService.pullTables.contains(t))
        .toList()
      ..sort();

    expect(
      ghosts,
      isEmpty,
      reason: 'أسماءٌ في `deltaOnlyTables` لا تقابلها مدخلاتٌ في `pullTables` '
          '⇒ إمّا حُذفت أو أُعيدت تسميتُها. والاسمُ البائتُ لا يحمي شيئاً، '
          'ويُوهم أنّ الجدولَ محميٌّ من البذر وهو لا يُسحَب أصلاً.',
    );
  });

  test('ولا جدولَ ذا استراتيجيّةٍ محرومٌ من البذر', () {
    final wrong = DeltaPullService.deltaOnlyTables
        .intersection(_knownStrategyBacked)
        .toList()
      ..sort();

    expect(
      wrong,
      isEmpty,
      reason: 'هذه الجداولُ تملؤها `fullSync` فعلاً، فحرمانُها من البذر يجعل '
          'أوّلَ سحبِ دلتا بعد كلّ إقلاعٍ **تفريغاً كاملاً** لما نُزِّل للتوّ.',
    );
  });

  test('ومدى الحارس لم ينكمش — مستنداتُ المرحلة ٢ كلُّها محميّة', () {
    // v166 — الاثنا عشرَ الموصوفةُ في `epoch_3.dart`. حذفُ أحدها من
    // `deltaOnlyTables` يعيد فتحَ تسميم العلامة له وحدَه، وهو ما لا يظهر
    // في أيّ فحصٍ آخر: القوائمُ تبقى متكافئةً والبناءُ يمرّ.
    const phase2 = <String>{
      'landed_cost_sheets', 'landed_cost_items', 'landed_cost_allocations',
      'fixed_assets', 'asset_categories', 'asset_depreciations',
      'op_expenses', 'op_expense_categories',
      'bill_of_materials', 'manufacturing_orders', 'mfg_order_costs',
      'bom_components',
    };

    final unprotected =
        phase2.difference(DeltaPullService.deltaOnlyTables).toList()..sort();

    expect(
      unprotected,
      isEmpty,
      reason: 'مستنداتٌ محاسبيّةٌ خرجت من الحماية ⇒ عميلٌ جديدٌ سيُبذَر له '
          'watermark بلا تنزيل، فلا يرى منها صفّاً واحداً سابقاً لإقلاعه.',
    );
  });
}

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
import 'package:picpos_erp/services/delta_pull_service.dart';
import 'dart:io';

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

  // ═══════════════════════════════════════════════════════════════════════
  // الاتّجاهُ الثالث — المفقود، ومن ثقبِه انفتح البند ٦‑٤
  // ═══════════════════════════════════════════════════════════════════════
  //
  // الفحصان أعلاه أحاديّا الاتّجاه: «لا اسمَ بائت» و«لا حمايةَ زائدة».
  // والثالثُ — **«كلُّ جدولٍ بلا استراتيجيّةٍ يجب أن يكون هنا»** — لم يكن
  // مفحوصاً إطلاقاً، وهو الوحيدُ الذي يمسك الحالةَ الخطرة.
  //
  // ولهذا انفتح الثقبُ **ثلاثَ مرّات** (‏v166 · v167 · ٦‑٤): المرساةُ
  // `_knownStrategyBacked` خريطةٌ يدويّةٌ **لا تكبر مع المشروع**.
  //
  // ⚠️ **ولا يصلح `SyncStrategy.tableName` مصدراً** — مقيسٌ لا مفترَض:
  // هو وسمٌ لا اسمُ جدول. `JournalSyncStrategy` يقول `journals` والجدولُ
  // `journal_entries`؛ و`purchases` مقابلَ `purchase_invoices`؛ و
  // `fiscalYears`/`productUnits` بحالةِ سنامٍ لا شرطة. والاشتقاقُ منه
  // يُبلغ عن ثمانيةِ جداولَ سليمةٍ بوصفها مكشوفة.
  //
  // فالمصدرُ هنا **الكتابةُ الفعليّة**: `into/update/delete(db.X)` في
  // ملفّات الاستراتيجيّات. و`pullTables`/`deltaOnlyTables` ثابتان
  // يُستورَدان مباشرةً — فلا تحليلَ نصّيَّ إلّا على طرفٍ واحد.
  test('🔴 كلُّ جدولٍ بلا استراتيجيّةٍ محميٌّ من البذر — الاتّجاهُ الثالث', () {
    final dir = Directory('lib/services/sync/strategies');
    expect(dir.existsSync(), isTrue,
        reason: 'مجلّدُ الاستراتيجيّات انتقل — الحارسُ يقيس فراغاً');

    final re = RegExp(r'\b(?:into|update|delete)\(\s*(?:db|_db|localDb)\.([A-Za-z][A-Za-z0-9]*)\s*\)');
    String snake(String v) => v
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
        .toLowerCase();

    final backed = <String>{};
    for (final e in dir.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      for (final m in re.allMatches(e.readAsStringSync())) {
        backed.add(snake(m.group(1)!));
      }
    }

    // ⚠️ مرساة: لو انكسر النمطُ لعاد الحارسُ أخضرَ بمجموعةٍ فارغة — وهو
    // عينُ العطب الذي يحرسه. الرقمُ حدٌّ أدنى مقيسٌ لا سقف.
    expect(backed.length, greaterThanOrEqualTo(40),
        reason: 'استخراجُ جداولِ الاستراتيجيّات عاد شبهَ فارغ ⇒ الفحصُ '
            'أدناه لا يقيس شيئاً. راجع النمط.');
    expect(backed, contains('journal_entries'),
        reason: 'مرساةٌ ثانية: جدولٌ نعلم يقيناً أنّ له استراتيجيّة');

    final unprotected = DeltaPullService.pullTables
        .where((t) =>
            !backed.contains(t) &&
            !DeltaPullService.deltaOnlyTables.contains(t))
        .toList()
      ..sort();

    expect(
      unprotected,
      isEmpty,
      reason: 'جداولُ في `pullTables` بلا استراتيجيّةٍ تملؤها وبلا حمايةٍ من '
          'البذر ⇒ تُختَم علامتُها المائيّةُ بعد `fullSync` لم ينزّل منها '
          'صفّاً، فلا تصل الجهازَ صفوفُها السابقةُ **أبداً** — بلا خطأٍ ولا '
          'سجلّ. أضِفها إلى `deltaOnlyTables`، أو اكتب لها استراتيجيّة.',
    );
  });
}

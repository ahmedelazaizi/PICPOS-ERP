// حارسُ العقد: **«سند قيد» موصولٌ، ومرجعُه يصل القاعدة، ورقمُه لا يُخمَّن.**
//
// ═══ ما يُحرَس هنا ولماذا ═══
//
// ‏١) 🔴 **`journal_entries.reference` كان عموداً بلا كاتبٍ ولا قارئ** منذ
//    v174 — `grep` على المستودع كلِّه لم يجد إلّا تعريفَه والهجرة. وهو عينُ
//    ما وقع لـ`custodian_user_id` و`source_voucher_id`: بنيةٌ تُشحَن وتبقى
//    فارغةً إلى الأبد لأنّ أحداً لم يصلها.
//
//    **والسلسلةُ كاملةٌ تُحرَس**: الشاشةُ ← واجهةُ المستودع ← تنفيذُه ←
//    الـDAO ← `JournalEntriesCompanion`. وحلقةٌ ناقصةٌ في المنتصف تجعل
//    الحقلَ يُكتَب فيه ولا يُخزَّن، وهو أسوأُ من حقلٍ غائب.
//
// ‏٢) 🔴 **ورقمُ السند لا يُخمَّن** — Spec 066: المولّدُ داخلَ معاملة الحفظ،
//    فقبلها لا رقمَ موجود. وهي نفسُ قاعدةِ معاينةِ فاتورة المبيعات.
//
// ‏٣) **والتوصيلُ ستّةُ مواضع** — وحارسٌ يقيس خمسةً من ستّةٍ يُعطي طمأنينةً
//    كاذبة (وقع مع الحجوزات مرّتين).
//
// ‏٤) **وودجتا السطر مكتبةٌ لا `part`**: كانتا محبوستَين داخل شاشة اليومية،
//    وهو عينُ ما حبس حوارَي فئة الأصول داخل شاشة UralCash.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/config/brand.dart';
import 'package:ural_erp/core/enums/app_screen.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/navigation/screen_registry.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';

String _code(String path) => [
      for (final line in File(path).readAsStringSync().split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

const _screen =
    'lib/presentation/accounting_picpos/journal_voucher_picpos_screen.dart';
const _widgets =
    'lib/presentation/accounting_picpos/journal_entries_picpos_widgets.dart';
const _repoApi = 'lib/domain/repositories/accounting_repository.dart';
const _repoImpl = 'lib/data/repositories/drift_accounting_repository.dart';
const _dao = 'lib/data/database/daos/accounting_dao_writes.dart';
const _table = 'lib/data/database/tables/accounting_tables.dart';

void main() {
  test('🔴 «المرجع» يصل القاعدة — السلسلةُ كاملة', () {
    // العمودُ نفسُه — مرساةٌ: بلا العمود لا معنى لباقي الفحص.
    expect(_code(_table).contains('TextColumn get reference'), isTrue,
        reason: 'عمودُ المرجع اختفى من الجدول');

    expect(_code(_screen).contains('reference: _referenceCtrl.text'), isTrue,
        reason: '🔴 الشاشةُ تكتب حقلاً لا يُرسَل — وحقلٌ يُكتَب فيه ولا '
            'يُخزَّن أسوأُ من حقلٍ غائب');
    expect(_code(_repoApi).contains('String? reference,'), isTrue,
        reason: 'الواجهةُ لا تقبله، فالمنادي لا يستطيع تمريرَه');
    expect(_code(_repoImpl).contains('reference: reference,'), isTrue,
        reason: 'التنفيذُ يبتلعه قبل الـDAO');
    // 🔴 **وآخرُ حلقةٍ هي الكتابةُ نفسُها**: الـDAO قد يقبل الوسيطَ ولا
    //    يضعه في الـ`Companion` — والسلسلةُ كلُّها تبدو موصولة.
    expect(_code(_dao).contains('reference: Value(reference),'), isTrue,
        reason: '🔴 الـDAO يقبل المرجعَ ولا يكتبه — الشاشةُ والواجهةُ '
            'والتنفيذُ كلُّها خضراء والعمودُ يبقى فارغاً كما كان');
  });

  test('⚠️ و«المرجع» ليس `referenceType`', () {
    final code = _code(_screen);
    // `referenceType` مفرداتٌ مغلقةٌ يكتبها المحرّكُ ويُرشَّح بها كلُّ تقريرٍ
    // على المصدر — وكتابةُ نصِّ المستخدم فيها تُفسد الترشيحَ كلَّه.
    expect(code.contains('referenceType: _entryType'), isTrue,
        reason: 'نوعُ القيد لا يصل `referenceType` — فيسقط من كلّ ترشيحٍ '
            'على المصدر');
    expect(code.contains('referenceType: _referenceCtrl'), isFalse,
        reason: '⚠️ نصُّ المستخدم في حقل المفردات المغلقة يُفسد الترشيح');
  });

  test('🔴 ورقمُ السند لا يُخمَّن قبل الحفظ', () {
    final code = _code(_screen);
    expect(code.contains('kJournalVoucherNumberPlaceholder'), isTrue);
    expect(code.contains("'JV-"), isFalse,
        reason: '🔴 رقمٌ مخمَّنٌ يُنقَل إلى دفترٍ ورقيٍّ ثمّ يُحفَظ غيرُه — '
            'والمولّدُ داخلَ معاملة الحفظ (Spec 066)');
    expect(code.contains("entryNumber: '—'"), isTrue,
        reason: 'ورقةُ المعاينة تحمل رقماً — وهي نفسُ قاعدةِ معاينةِ فاتورة '
            'المبيعات');
  });

  test('والزرّان يمرّران `asDraft` مختلفاً', () {
    final code = _code(_screen);
    expect(code.contains('_save(asDraft: true)'), isTrue);
    expect(code.contains('_save(asDraft: false)'), isTrue,
        reason: '🔴 زرّان يفعلان الشيءَ نفسَه: مسوّدةٌ تُرحَّل تحرّك أرصدةً '
            'ظُنّ أنّها تنتظر اعتماداً');
    expect(code.contains('asDraft: asDraft,'), isTrue,
        reason: 'الرايةُ لا تصل المستودع');
  });

  test('⚠️ وودجتا السطر مكتبةٌ لا `part`', () {
    final code = _code(_widgets);
    expect(code.contains("part of 'journal_entries_picpos_screen.dart';"),
        isFalse,
        reason: '⚠️ `part` لا يبلغه شيءٌ خارجَ مكتبته — وهو عينُ ما حبس '
            'حوارَي فئة الأصول داخل شاشة UralCash');
    expect(_code(_screen).contains("import 'journal_entries_picpos_widgets.dart';"),
        isTrue,
        reason: 'الشاشةُ تنسخ المنتقيَين بدل استعمالهما — ونسختان تفترقان '
            'عند أوّل تعديل');
  });

  group('والتوصيلُ ستّةُ مواضع', () {
    test('«سند قيد»', () {
      const id = ScreenId.journalVoucher;
      // ‏١) معرِّفُ الشاشة · ‏٢) و`AppScreen` بنفس الرقم.
      expect(id.navigationIndex, 67);
      expect(AppScreen.journalVoucher.value, id.navigationIndex,
          reason: 'الرقمان مصدرُ حقيقةٍ في نظامَين — وانحرافُهما يفتح شاشةً '
              'غيرَ التي أذنت بها الصلاحية');
      // ‏٣) وصلاحيّةٌ في الخريطة.
      //
      // ⚠️ **`settings_view` عن قصدٍ لا `accounting_journal`**: الثانيةُ
      //    **ليست في `RoleGrantMatrix.defaultGrants` أصلاً**، فربطُ الشاشة
      //    بها كان يسحبها من كلِّ دورٍ قائمٍ حتى تُمنح يدويّاً. وهي تُفحَص
      //    عند **الحفظ** كما يفعل `saveManualEntry` اليوم حرفاً.
      expect(screenPermissionMap[id], 'settings_view',
          reason: 'صلاحيّةٌ غيرُ ممنوحةٍ لأحدٍ تُخفي الشاشةَ عن الجميع');
      expect(_code(_screen).contains('PermissionCodes.accountingJournal'),
          isTrue,
          reason: '🔴 الشاشةُ تُفتَح بـ`settings_view` — وترحيلٌ بلا فحصٍ '
              'يجعل كلَّ من يرى الإعدادات يرحّل قيوداً');
      // ‏٤) والنطاقُ نطاقُ «اليومية العامة» بالضبط.
      expect(ScreenRegistry.unified, contains(id));
      expect(ScreenRegistry.lite.contains(id), isFalse,
          reason: 'أصغرُ ملفٍّ لا يحمل الدورةَ المحاسبيّة أصلاً');
      // ‏٥) و`ScreenConfig` تبنيها.
      expect(
          _code('lib/app_main_screen.dart')
              .contains('appScreen: AppScreen.journalVoucher,'),
          isTrue,
          reason: 'شاشةٌ بلا بانٍ تفتح فراغاً');
      // ‏٦) ومدخلٌ في القائمة الجانبيّة — المصدرُ السادسُ المستقلّ.
      final item = kAllNavItemDefs.where((n) => n.index == 67).toList();
      expect(item, hasLength(1),
          reason: 'بلا مدخلٍ هنا لا يراها المستخدمُ مهما صحّ الباقي');
      expect(item.single.label, 'سند قيد');
      // E1 — «سند قيد» قيدٌ محاسبيٌّ لا حركةُ خزينة: تحت «إدارة الحسابات».
      // E-fix ٣ — والفصلُ لـPicPos وحدَه: UralCash على «المالية والمحاسبة».
      expect(item.single.group, Brand.isPicPos ? 'accounts' : 'accounting');
      expect(item.single.permission, screenPermissionMap[id],
          reason: 'صلاحيّةٌ في القائمة تخالف الخريطةَ تُظهر مدخلاً يفتح '
              'شاشةً ممنوعة');
    });
  });
}

// حارسُ العقد: **اللوحُ يحلّ محلَّ الحوارات — ولا تُلمَس نسخةُ UralCash**.
//
// ═══ ما يُحرَس هنا ولماذا ═══
//
// قرارُ المالك 2026-09-18: لوحُ تفاصيلَ جانبيٌّ يحلّ محلَّ حواري الإنشاء
// والتعديل **تماماً**. و«تماماً» تحتاج حارساً: نداءٌ واحدٌ باقٍ يعيد الحوارَ
// من بابٍ خلفيّ (زرُّ صفٍّ · اختصار · قائمة)، ولا يلاحظه أحدٌ لأنّ الشاشةَ
// تعمل.
//
// ⚠️ **و`coa_dialogs.dart` تبقى كما هي**: تخدم `chart_of_accounts_screen`
// (فرعُ UralCash). فالمقيسُ هو **مَن ينادي** لا وجودُ الملفّ — وحذفُه كان
// سيكسر الفرعَ الآخر.
//
// ⚠️ **واللوحُ لا يستورد `data/database`**: حارسُ
// `presentation_db_import_guard` يمنع أيَّ ملفِّ عرضٍ جديدٍ من ذلك وقائمتُه
// مقفولة — فاللوحُ يأخذ قيماً خالصةً ويعيدها.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — أغلبُ الملفّات هنا CRLF.
String _code(String path) => [
      for (final line in File(path).readAsStringSync().split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

const _screen =
    'lib/presentation/accounting_picpos/chart_of_accounts_picpos_screen.dart';
const _panel =
    'lib/presentation/accounting_picpos/chart_of_accounts_detail_panel.dart';
const _insight =
    'lib/presentation/accounting_picpos/chart_of_accounts_insight.dart';
const _overview =
    'lib/presentation/accounting_picpos/chart_of_accounts_overview.dart';
const _search =
    'lib/presentation/accounting_picpos/chart_of_accounts_search.dart';
const _legacy = 'lib/presentation/screens/chart_of_accounts_screen.dart';
const _dialogs = 'lib/presentation/screens/coa/coa_dialogs.dart';
const _daoWrites = 'lib/data/database/daos/accounting_dao_writes.dart';

void main() {
  test('🔴 شاشةُ PicPos لا تفتح حواري الإنشاء والتعديل', () {
    final code = _code(_screen);
    expect(code.contains('showAddAccountDialog('), isFalse,
        reason: 'حوارُ الإنشاء ما زال يُفتَح — واللوحُ يحلّ محلَّه **تماماً**');
    expect(code.contains('showEditAccountDialog('), isFalse,
        reason: 'حوارُ التعديل ما زال يُفتَح');
    expect(code.contains('AccountDetailPanel('), isTrue,
        reason: 'اللوحُ لا يُبنى أصلاً');
  });

  test('وأفعالُ الشجرة الثلاثةُ تصل اللوحَ', () {
    // 🔴 `sub` و`edit` ونقرةُ الصفّ (`ledger`) — ثلاثةُ أبوابٍ إلى نفس
    //    المكان. وبابٌ واحدٌ يُنسى يُعيد الحوارَ حيث لا يُتوقَّع.
    final body = _code(_screen);
    final at = body.indexOf('void _handleAccountAction(');
    expect(at, greaterThan(0), reason: 'موجّهُ أفعال الشجرة اختفى');
    final fn = body.substring(at, body.indexOf('Future<void> _toggleHideFromEntries', at));
    expect(fn.contains('_startCreate(parentId: account.id)'), isTrue,
        reason: '«إضافة فرعي» لا يفتح اللوح');
    expect('_openPanelFor(account.id)'.allMatches(fn).length, 2,
        reason: 'نقرةُ الصفّ و«تعديل» كلاهما يفتح اللوحَ — والعدُّ يمسك '
            'سقوطَ أحدهما');
  });

  test('ودفترُ الأستاذ لم يسقط مع إعادة التوجيه', () {
    // ⚠️ نقرةُ الصفّ كانت تفتحه، وصارت تختار. والفعلُ يبقى في قائمة الصفّ.
    expect(_code(_screen).contains('showAccountLedger('), isTrue,
        reason: 'دفترُ الأستاذ سقط — فعلٌ ضاع في إعادة التوجيه');
  });

  test('🔴 و`coa_dialogs` تبقى لفرع UralCash', () {
    expect(File(_dialogs).existsSync(), isTrue,
        reason: 'الحواراتُ حُذفت — وتخدم الفرعَ الآخر');
    final legacy = _code(_legacy);
    expect(legacy.contains('showAddAccountDialog('), isTrue,
        reason: 'فرعُ UralCash فقد حوارَ الإنشاء — والقرارُ يخصّ PicPos وحدَها');
  });

  test('🔴 واللوحُ لا يستورد `data/database`', () {
    final panel = _code(_panel);
    expect(panel.contains("data/database"), isFalse,
        reason: 'ملفُّ عرضٍ جديدٌ يستورد القاعدةَ — يكسر حارسَ الاستيراد');
    expect(panel.contains('class AccountPanelValue'), isTrue,
        reason: 'اللوحُ يأخذ صفَّ drift مباشرةً بدل قيمٍ خالصة');
  });

  // ═══ المرحلة G (البند ١٩): رئيسيٌّ/تفصيليٌّ ظاهران معاً ═══
  test('🔴 اللوحُ لا يختفي: حالةٌ فارغةٌ مرشدةٌ وعرضٌ قبل التحرير', () {
    final body = _code(_screen);
    final at = body.indexOf('Widget _buildDetailPanel(');
    expect(at, greaterThan(0), reason: 'بانيةُ اللوح اختفت');
    final fn = body.substring(at, body.indexOf('return AccountDetailPanel(', at));
    expect(fn.contains('return const CoaEmptyPanel()'), isTrue,
        reason: 'اللوحُ يختفي حين لا اختيار — والقرارُ أن يبقى ظاهراً مرشداً');
    expect(fn.contains('SizedBox.shrink()'), isFalse,
        reason: 'لوحٌ فارغٌ صامتٌ يُقرأ عطلاً');
    expect(fn.contains('AccountOverviewPanel('), isTrue,
        reason: 'الاختيارُ لا يعرض الحسابَ — يقفز إلى النموذج');
  });

  test('🔴 ورصيدُ اللوح يمرّ بنطاق الفروع الأمنيّ — كدفتر الأستاذ', () {
    final screen = _code(_screen);
    expect(screen.contains('branchScopeProvider.future'), isTrue,
        reason: 'اللوحُ يقرأ الحركاتِ بلا نطاق الفروع');
    final insight = _code(_insight);
    expect(insight.contains('allowedBranchIds: await allowedBranches()'), isTrue,
        reason: 'النطاقُ يُقرأ ولا يُمرَّر إلى `getAccountLedger`');
    for (final f in [_insight, _overview, _search]) {
      expect(_code(f).contains('data/database'), isFalse,
          reason: '$f ملفُّ عرضٍ جديدٌ يستورد القاعدة');
    }
  });

  test('ودفترُ الأستاذ من اللوح يُفتَح مرشَّحاً على الحساب', () {
    final screen = _code(_screen);
    expect(screen.contains('GeneralLedgerPicPosScreen('), isTrue);
    expect(screen.contains('initialAccountId: account.id'), isTrue,
        reason: 'الرابطُ يفتح الدفترَ بلا حساب — والمستخدمُ يعيد الاختيار');
  });

  test('🔴 والحقولُ المشتقّةُ تُقرأ من الوحدة الخالصة لا تُكتَب بيد', () {
    // 🔴 قاعدتان لِما هو واحد: SQL الهجرة والكاتب. وقد افترقا فعلاً —
    //    الهجرةُ تكتب `credit` للإيرادات والكاتبُ يتركها `debit`.
    final dao = _code(_daoWrites);
    expect(dao.contains('normalBalance: Value(normalBalanceFor(accountType))'),
        isTrue,
        reason: 'طبيعةُ الرصيد مكتوبةٌ بيدها أو متروكةٌ لافتراض العمود');
    expect(dao.contains('level: Value(accountLevelUnder(parentLevel))'), isTrue,
        reason: 'المستوى مكتوبٌ بيده أو متروكٌ لافتراض العمود');
    expect(_code(_panel).contains('normalBalanceFor(_type)'), isTrue,
        reason: 'اللوحُ يعرض طبيعةً محسوبةً بقاعدةٍ ثانية');
  });
}

// شاشةُ «فئات الأصول» — مدخلٌ جانبيٌّ مستقلٌّ بقرار المالك 2026-09-18.
//
// ═══ 🔴 ولماذا ليست نسخةً من التبويبة التي خرجت منها ═══
//
// تبويبةُ «الفئات» في `fixed_assets_picpos_screen.dart` كانت **جدولاً
// للقراءة وحدَه**: لا إنشاءَ ولا تعديل. وحوارا الإنشاء والتعديل موجودان —
// لكنّهما `part 'fixed_assets_dialogs.dart';` من شاشة **UralCash**
// (`fixed_assets_screen.dart`)، والفوركُ لا يبلغهما ولا يستطيع: الملفُّ
// جزءٌ من ذلك الملفِّ لا مكتبةٌ مستقلّة.
//
// ⇒ **في PicPos اليوم لا تُنشأ فئةُ أصولٍ إطلاقاً.** و`createFixedAsset`
//    تشترط `categoryId`، وحوارُ «أصل جديد» يقول «لا فئاتِ أصولٍ بعد» ثمّ
//    يقف. أي أنّ شاشةَ الأصول كلَّها **لا تُستعمَل على تنصيبةٍ جديدة** بلا
//    فئاتٍ مبذورة. فالمدخلُ الجديد ليس نقلَ جدولٍ — هو أوّلُ كاتبٍ للفئة في
//    هذا الفورك.
//
// ═══ 🔴 والحساباتُ **تفصيليّةٌ وحدَها** ═══
//
// قيدُ الاقتناء يُرحَّل على `category.accountId`، و`accounting_dao_writes`
// يرفض الترحيلَ على حسابٍ طبيعتُه `view`:
// «لا يمكن الترحيل على حساب رئيسي — يجب اختيار حساب تفصيلي».
//
// فحسابٌ رئيسيٌّ في الفئة يجعلها فئةً **لا يُسجَّل تحتها أصلٌ أبداً**،
// والرفضُ يقع في آخر نموذجِ الأصل الطويل بعد أن ملأه المستخدم — وهو عينُ
// العطب الذي بُنيت له Feature 050 (اشتراطُ الحسابَين عند إنشاء الفئة)،
// بثوبٍ آخر. فالمنتقي هنا لا يعرض إلّا التفصيليَّ النشط.
//
// ═══ ⚠️ والعمرُ بالشهور كما في بطاقة الأصل ═══
//
// العمودُ `defaultUsefulLife` بالسنوات (‏`real`)، والتحويلُ **موضعٌ واحدٌ
// مسمّى** في `domain/models/depreciation_math.dart` — لا `* 12` بيدها هنا.
// و٣٦ في حقل سنواتٍ = عمرٌ افتراضيٌّ ستٌّ وثلاثون سنةً يرثه كلُّ أصلٍ
// يُنشأ تحت الفئة.
//
// ═══ ⚠️ ولا يستوردُ هذا الملفُّ `data/database` ═══
//
// حارسُ `presentation_db_import_guard` يمنع كلَّ ملفِّ عرضٍ جديدٍ من ذلك،
// وقائمتُه مقفولة. و`AssetCategory`/`Account`/`FixedAssetData` تصل هنا عبر
// واجهتَي المستودع في `domain/repositories/`.
//
// ═══ ⚠️ ولا زرَّ حذفٍ ═══
//
// لا `deleteAssetCategory` في المستودع ولا في الـDAO، والحذفُ بلا كاتبٍ
// زرٌّ يُعرَض ولا يفعل. وهو أيضاً غيرُ بديهيّ: فئةٌ تحتها أصولٌ مُرحَّلةٌ
// حذفُها يقطع `categoryId` المرجعيَّ ويُيتّم قيودَ اقتناءٍ وإهلاكٍ في
// الأستاذ. فإن طُلب لاحقاً فهو قرارُ مالكٍ بمساره المحاسبيّ.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/depreciation_math.dart';
import '../../../domain/repositories/accounting_repository.dart';
import '../../../domain/repositories/fixed_assets_repository.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_kpi_row.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../widgets/permission_guard.dart';

const _err = Color(0xFFEF4444);
const _purple = Color(0xFF8B5CF6);
const _idle = Color(0xFF6B7280);

String _ar(Object n) =>
    '$n'.replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)]);

String _methodLabel(String method) =>
    method == 'declining_balance' ? 'قسط متناقص' : 'قسط ثابت';

final _categoriesProvider = StreamProvider.autoDispose<List<AssetCategory>>(
    (ref) => ref.watch(fixedAssetsRepositoryProvider).watchAssetCategories());

final _assetsProvider = StreamProvider.autoDispose<List<FixedAssetData>>(
    (ref) => ref.watch(fixedAssetsRepositoryProvider).watchFixedAssets());

final _accountsProvider = StreamProvider.autoDispose<List<Account>>(
    (ref) => ref.watch(accountingRepositoryProvider).watchAllAccounts());

/// خيارُ حسابٍ في المنتقي — **قيمةٌ خالصةٌ** لا صفُّ قاعدة.
typedef AccountOption = ({int id, String code, String name});

/// هل يصلح الحسابُ لقيدٍ يُرحَّل؟
///
/// 🔴 **شرطان لا واحد**: الطبيعةُ `detail` (وإلّا رفض المحرّكُ الترحيل)،
/// والحسابُ نشط (‏وحسابٌ موقوفٌ يُختار اليومَ ويُرفَض غداً).
bool isPostableAccount(String accountNature, bool isActive) =>
    accountNature != 'view' && isActive;

class AssetCategoriesPicposScreen extends ConsumerStatefulWidget {
  const AssetCategoriesPicposScreen({super.key});

  @override
  ConsumerState<AssetCategoriesPicposScreen> createState() =>
      _AssetCategoriesPicposScreenState();
}

class _AssetCategoriesPicposScreenState
    extends ConsumerState<AssetCategoriesPicposScreen> {
  /// الفئةُ المفتوحةُ في اللوح — و`_creating` تعني فئةً جديدة.
  int? _panelId;
  bool _creating = false;

  void _closePanel() => setState(() {
        _panelId = null;
        _creating = false;
      });

  void _openPanelFor(int id) => setState(() {
        _panelId = id;
        _creating = false;
      });

  void _startCreate() => setState(() {
        _panelId = null;
        _creating = true;
      });

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(_categoriesProvider).value ?? const <AssetCategory>[];
    final assets = ref.watch(_assetsProvider).value ?? const <FixedAssetData>[];
    final accounts = ref.watch(_accountsProvider).value ?? const <Account>[];

    final countByCat = <int, int>{};
    for (final a in assets) {
      countByCat[a.categoryId] = (countByCat[a.categoryId] ?? 0) + 1;
    }
    final accountById = {
      for (final a in accounts) a.id: '${a.code} · ${a.name}',
    };
    final postable = <AccountOption>[
      for (final a in accounts)
        if (isPostableAccount(a.accountNature, a.isActive))
          (id: a.id, code: a.code, name: a.name),
    ];

    // 🔴 فئةٌ ناقصةُ الربطِ لا يُسجَّل تحتها أصلٌ أبداً — وهي تبدو سليمةً
    //    في أيّ جدول. فالعدّادُ يقولها قبل أن يكتشفها المستخدمُ في آخرِ
    //    نموذجِ أصلٍ طويل.
    final unlinked = cats
        .where((c) => c.accountId == null || c.depreciationAccountId == null)
        .length;

    return PermissionGuard(
      permission: PermissionCodes.assetsView,
      child: PicPosScreenScaffold(
        title: 'فئات الأصول',
        subtitle: 'الفئة تحدد العمر الافتراضي وطريقة الإهلاك وحسابَي الأصل '
            'والإهلاك',
        icon: PhosphorIconsBold.folders,
        headerActions: [
          PermissionGuard(
            permission: PermissionCodes.assetsManage,
            child: FilledButton.icon(
              onPressed: _startCreate,
              icon: const Icon(PhosphorIconsBold.plus, size: 15),
              label: const Text('فئة جديدة'),
            ),
          ),
        ],
        subHeader: PicPosKpiRow(
          kpis: [
            PicPosKpi(
              label: 'الفئات',
              value: _ar(cats.length),
              icon: PhosphorIconsBold.folders,
              tint: AppColors.primary,
            ),
            PicPosKpi(
              label: 'ناقصةُ الربط',
              value: _ar(unlinked),
              icon: PhosphorIconsBold.warningCircle,
              tint: unlinked == 0 ? AppColors.success : _err,
            ),
            PicPosKpi(
              label: 'أصولٌ مصنَّفة',
              value: _ar(assets.length),
              icon: PhosphorIconsBold.buildings,
              tint: AppColors.info,
            ),
            PicPosKpi(
              label: 'فئاتٌ بلا أصول',
              value: _ar(cats.where((c) => (countByCat[c.id] ?? 0) == 0).length),
              icon: PhosphorIconsBold.folderOpen,
              tint: AppColors.textMuted,
            ),
          ],
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: SingleChildScrollView(
                child: _table(cats, countByCat, accountById),
              ),
            ),
            if (_creating || _panelId != null) ...[
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  child: _panel(cats, postable),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _table(
    List<AssetCategory> cats,
    Map<int, int> countByCat,
    Map<int, String> accountById,
  ) {
    return PicPosDataTable(
      title: 'فئات الأصول',
      subtitle: 'الفئة تحدد العمر الافتراضي والطريقة وحسابَي الأصل والإهلاك',
      minWidth: 980,
      emptyLabel: 'لا فئاتِ أصولٍ بعد — ولا يُسجَّل أصلٌ بلا فئة',
      columns: const [
        PicPosTableColumn('الفئة', flex: 1.7),
        PicPosTableColumn('العمر الافتراضي', flex: 1.2),
        PicPosTableColumn('طريقة الإهلاك', flex: 1.4),
        PicPosTableColumn('الأصول', align: PicPosCellAlign.end),
        PicPosTableColumn('حساب الأصل', flex: 1.5),
        PicPosTableColumn('حساب الإهلاك', flex: 1.5),
      ],
      rows: [
        for (final c in cats)
          PicPosTableRow(
            selected: _panelId == c.id,
            onTap: () => _openPanelFor(c.id),
            cells: [
              PicPosTextCell(
                c.name,
                icon: PhosphorIconsBold.folders,
                sub: (countByCat[c.id] ?? 0) == 0 ? 'بلا أصول على الدفاتر' : null,
                tint: (countByCat[c.id] ?? 0) == 0 ? _idle : AppColors.primary,
              ),
              // ⚠️ بالشهور — والتحويلُ في `depreciation_math` لا هنا.
              PicPosTextCell(
                  '${_ar(usefulLifeMonths(c.defaultUsefulLife))} شهراً'),
              PicPosPillCell(
                _methodLabel(c.defaultDepreciationMethod),
                c.defaultDepreciationMethod == 'declining_balance'
                    ? _purple
                    : AppColors.primary,
              ),
              PicPosTextCell(_ar(countByCat[c.id] ?? 0)),
              PicPosTextCell(accountById[c.accountId] ?? '— غير مربوط',
                  tint: c.accountId == null ? _err : null),
              PicPosTextCell(
                  accountById[c.depreciationAccountId] ?? '— غير مربوط',
                  tint: c.depreciationAccountId == null ? _err : null),
            ],
          ),
      ],
      totals: [
        '${_ar(cats.length)} فئات',
        '',
        '',
        _ar(countByCat.values.fold<int>(0, (s, n) => s + n)),
        '',
        '',
      ],
    );
  }

  /// اللوحُ الجانبيّ — إنشاءً وتعديلاً في مكانٍ واحد.
  ///
  /// ⚠️ **و`key` من معرّف الفئة**: بدونها يُعاد استعمالُ حالةِ اللوح عند
  /// تبديل الاختيار، فتبقى حقولُ الفئة السابقة معروضةً على الجديدة —
  /// ويُحفَظ اسمُ فئةٍ على أخرى.
  Widget _panel(List<AssetCategory> cats, List<AccountOption> accounts) {
    final current =
        _panelId == null ? null : cats.where((c) => c.id == _panelId).firstOrNull;
    // الاختيارُ يُقرأ من القائمة الحيّة: فئةٌ اختفت تترك لوحاً يعمل على ما
    // لا يُرى.
    if (!_creating && current == null) return const SizedBox.shrink();

    return AssetCategoryPanel(
      key: ValueKey('cat_panel_${_creating ? 'new' : current!.id}'),
      value: current == null
          ? null
          : (
              id: current.id,
              name: current.name,
              usefulLifeMonths: usefulLifeMonths(current.defaultUsefulLife),
              method: current.defaultDepreciationMethod,
              accountId: current.accountId,
              depreciationAccountId: current.depreciationAccountId,
            ),
      accounts: accounts,
      onClose: _closePanel,
      onSave: _save,
    );
  }

  Future<void> _save(AssetCategorySave v) async {
    final repo = ref.read(fixedAssetsRepositoryProvider);
    try {
      if (v.id == null) {
        await repo.createAssetCategory(
          name: v.name,
          // ⚠️ التحويلُ هنا لا في اللوح: اللوحُ يعرض شهوراً والقاعدةُ تخزّن
          //    سنواتٍ كسريّة — و٣٠ شهراً ٢٫٥ لا ٣.
          defaultUsefulLife: usefulLifeYearsFromMonths(v.usefulLifeMonths),
          defaultDepreciationMethod: v.method,
          accountId: v.accountId,
          depreciationAccountId: v.depreciationAccountId,
        );
        if (!mounted) return;
        AppToast.show(context, 'تمت إضافة الفئة');
        _closePanel();
      } else {
        await repo.updateAssetCategoryById(
          v.id!,
          name: v.name,
          defaultUsefulLife: usefulLifeYearsFromMonths(v.usefulLifeMonths),
          defaultDepreciationMethod: v.method,
          accountId: v.accountId,
          depreciationAccountId: v.depreciationAccountId,
        );
        if (!mounted) return;
        AppToast.show(context, 'تم تحديث الفئة');
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ: $e', type: ToastType.error);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// اللوحُ — ودجتٌ خالصةٌ تُختبَر بلا قاعدة
// ═══════════════════════════════════════════════════════════════════════════

/// قيمةُ الفئة المعروضةُ في اللوح — **بالشهور** كما تُعرَض.
typedef AssetCategoryValue = ({
  int id,
  String name,
  int usefulLifeMonths,
  String method,
  int? accountId,
  int? depreciationAccountId,
});

/// ما يخرج من اللوح عند الحفظ — و`id` الفارغُ يعني إنشاءً.
typedef AssetCategorySave = ({
  int? id,
  String name,
  int usefulLifeMonths,
  String method,
  int accountId,
  int depreciationAccountId,
});

class AssetCategoryPanel extends StatefulWidget {
  const AssetCategoryPanel({
    super.key,
    required this.value,
    required this.accounts,
    required this.onClose,
    required this.onSave,
  });

  /// `null` ⇒ فئةٌ جديدة.
  final AssetCategoryValue? value;

  /// الحساباتُ الصالحةُ للترحيل وحدَها — راجع رأسَ الملفّ.
  final List<AccountOption> accounts;

  final VoidCallback onClose;
  final Future<void> Function(AssetCategorySave) onSave;

  @override
  State<AssetCategoryPanel> createState() => _AssetCategoryPanelState();
}

class _AssetCategoryPanelState extends State<AssetCategoryPanel> {
  late final TextEditingController _name =
      TextEditingController(text: widget.value?.name ?? '');
  late final TextEditingController _months = TextEditingController(
      text: '${widget.value?.usefulLifeMonths ?? 60}');
  late String _method = widget.value?.method ?? 'straight_line';
  late int? _accountId = widget.value?.accountId;
  late int? _deprAccountId = widget.value?.depreciationAccountId;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _months.dispose();
    super.dispose();
  }

  int get _monthsValue => int.tryParse(_months.text.trim()) ?? 0;

  /// سببُ منعِ الحفظ — أو `null` إن جاز.
  ///
  /// ⚠️ **يُعرَض ولا يُبتلَع**: زرٌّ معطَّلٌ بلا سببٍ ظاهرٍ يُقرأ «معطوب».
  String? get blockReason {
    if (_name.text.trim().isEmpty) return 'اكتب اسم الفئة.';
    if (_monthsValue <= 0) return 'العمر الافتراضي بالشهور — ورقمٌ أكبر من صفر.';
    // 🔴 اشتراطُ الحسابَين هو Feature 050 نفسُها: فئةٌ بلا حسابٍ لا يُسجَّل
    //    تحتها أصلٌ، والرفضُ يقع في آخرِ نموذجٍ طويلٍ بعد أن مُلئ.
    if (_accountId == null) return 'اختر حساب الأصل — وهو حسابٌ تفصيليٌّ.';
    if (_deprAccountId == null) {
      return 'اختر حساب مجمع الإهلاك — وهو حسابٌ تفصيليٌّ.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.value == null;
    final reason = blockReason;

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isNew ? 'فئة جديدة' : 'تعديل الفئة',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'إغلاق',
                onPressed: widget.onClose,
                icon: const Icon(PhosphorIconsBold.x, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'اسم الفئة',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _months,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'العمر الافتراضي (شهراً)',
              helperText: 'يرثه كلُّ أصلٍ يُنشأ تحت الفئة · ٦٠ شهراً = ٥ سنوات',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(
              labelText: 'طريقة الإهلاك',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'straight_line', child: Text('قسط ثابت')),
              DropdownMenuItem(
                  value: 'declining_balance', child: Text('قسط متناقص')),
            ],
            onChanged: (v) => setState(() => _method = v ?? 'straight_line'),
          ),
          const SizedBox(height: 10),
          _AccountField(
            key: const Key('asset_category_account_field'),
            label: 'حساب الأصل',
            hint: 'ابحث برقم الحساب أو اسمه…',
            options: widget.accounts,
            selectedId: _accountId,
            onSelected: (id) => setState(() => _accountId = id),
          ),
          const SizedBox(height: 10),
          _AccountField(
            key: const Key('asset_category_depr_account_field'),
            label: 'حساب مجمع الإهلاك',
            hint: 'ابحث برقم الحساب أو اسمه…',
            options: widget.accounts,
            selectedId: _deprAccountId,
            onSelected: (id) => setState(() => _deprAccountId = id),
          ),
          const SizedBox(height: 10),
          // ⚠️ **يُقال دائماً لا عند الضغط**: الحساباتُ المعروضةُ تفصيليّةٌ
          //    وحدَها، وغيابُ الرئيسيِّ من القائمة بلا تفسيرٍ يُقرأ «الحساب
          //    ناقص».
          const Text(
            'الحساباتُ المعروضة تفصيليّةٌ نشطةٌ وحدَها — والمحرّك يرفض '
            'الترحيل على حسابٍ رئيسيّ.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          if (reason != null) ...[
            const SizedBox(height: 8),
            Text(reason,
                style: const TextStyle(fontSize: 11.5, color: _err)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PermissionGuard(
                  permission: PermissionCodes.assetsManage,
                  child: FilledButton.icon(
                    onPressed: (_saving || reason != null) ? null : _submit,
                    icon: const Icon(PhosphorIconsBold.floppyDisk, size: 15),
                    label: Text(isNew ? 'حفظ الفئة' : 'حفظ التعديل'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: widget.onClose,
                child: const Text('إلغاء'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await widget.onSave((
        id: widget.value?.id,
        name: _name.text.trim(),
        usefulLifeMonths: _monthsValue,
        method: _method,
        accountId: _accountId!,
        depreciationAccountId: _deprAccountId!,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// منتقي حسابٍ بالبحث — دليلُ الحسابات مئاتُ الصفوف، وقائمةٌ منسدلةٌ بلا
/// بحثٍ فيها غيرُ صالحةٍ للاستعمال.
class _AccountField extends StatelessWidget {
  const _AccountField({
    super.key,
    required this.label,
    required this.hint,
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  final String label;
  final String hint;
  final List<AccountOption> options;
  final int? selectedId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final current = options.where((a) => a.id == selectedId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Autocomplete<AccountOption>(
          optionsBuilder: (v) {
            final q = v.text.trim().toLowerCase();
            if (q.isEmpty) return options.take(20);
            return options.where(
              (a) => a.name.toLowerCase().contains(q) || a.code.contains(q),
            );
          },
          displayStringForOption: (a) => '${a.code} - ${a.name}',
          onSelected: (a) => onSelected(a.id),
          fieldViewBuilder: (ctx, ctrl, fn, _) => TextField(
            controller: ctrl,
            focusNode: fn,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (current != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('✓ ${current.code} - ${current.name}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.success)),
          ),
      ],
    );
  }
}

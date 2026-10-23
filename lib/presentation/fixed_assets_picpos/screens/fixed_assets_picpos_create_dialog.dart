import 'package:picpos_erp/core/i18n/tr.dart';
// حوارُ «أصل ثابت جديد» بهويّة PicPos — فورك `DLGS.asset` في
// `PicPos Fixed Assets.dc.html`.
//
// ═══ لماذا فوركٌ ولمَ لم يُستدعَ القائم ═══
//
// المنطقُ قائمٌ في `showCreateAssetDialog` داخلَ `fixed_assets_dialogs.dart`
// — لكنّه **امتدادٌ (`mixin`) على حالةِ الشاشة القديمة**، فلا يُنادى من فوركٍ
// آخرَ إلّا بجرّ تلك الحالة كلِّها. وواجهتُه `AlertDialog` خامّةٌ بعرض ٤٥٠،
// وشاشةُ الأصول منقولةٌ إلى الهويّة.
//
// ⚠️ **ومسارُ الحفظ سطرٌ واحد** (`repo.createFixedAsset`) بلا كتابةٍ مزدوجةٍ
// للخادم — بخلاف الأوراق التجاريّة. فلا دالّةَ مشتركةً تُستخرَج هنا: النداءُ
// نفسُه هو المشترك.
//
// ═══ وجدولُ الإهلاك في اللوحة **محسوبٌ بصيغة المحرّك** ═══
//
// `monthlyDepreciation` في `domain/models/depreciation_math.dart` — وهي عينُ
// ما يكتبه `runMonthlyDepreciation`. فما يقرؤه المستخدمُ هنا قبل الحفظ هو ما
// سيُقيَّد فعلاً، لا تقديرٌ يقاربه.
//
// ═══ وثلاثةُ مفاتيحَ في التصميم لا تُعرَض مفاتيحَ — وكلُّه مقيس ═══
//
// 🔴 **«إنشاء حساب فرعي للأصل»**: ليس خياراً بل **عقدُ الـDAO**. تعليقُ
//    الجدول صريح: «The linked account is created atomically with the asset».
//    فمفتاحٌ يُطفَأ ولا يُطفئ شيئاً يكذب — ويُعرَض حقيقةً في اللوحة.
//
// 🔴 **«ربط بفاتورة شراء»**: لا عمودَ له في `FixedAssets` إطلاقاً.
//
// 🔴 **«بدء الإهلاك من الشهر القادم»**: لا عمودَ له، **والمحرّكُ لا يقرأ
//    `purchaseDate` أصلاً** — `runMonthlyDepreciation` يختار
//    `status == 'active'` ثمّ يحسب قسطاً كاملاً. فنصُّ التصميم «الشهر الجزئي
//    لا يُهلك» **غيرُ صحيحٍ في المحرّك الحاليّ**، ويُقال ذلك في اللوحة بدل
//    مفتاحٍ يَعِد بما لا يقع.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/depreciation_math.dart';
import '../../picpos_shell/picpos_dialog.dart';

/// فئةُ أصولٍ كما يحتاجها الحوار — الاسمُ والعمرُ الافتراضيُّ وحدَهما.
typedef AssetCategoryOption = ({int id, String name, double defaultUsefulLife});

/// حسابٌ في الشجرة — للحساب المقابل (‏ما دُفع منه ثمنُ الأصل).
typedef AccountOption = ({int id, String code, String name});

/// مركزُ تكلفة.
typedef CostCenterOption = ({int id, String name});

/// حصيلةُ الحوار — تُمرَّر إلى `repo.createFixedAsset` كما هي.
class NewAssetForm {
  const NewAssetForm({
    required this.code,
    required this.name,
    required this.categoryId,
    required this.purchasePrice,
    required this.purchaseDate,
    required this.usefulLifeYears,
    required this.salvageValue,
    required this.depreciationMethod,
    this.location,
    this.notes,
    this.costCenterId,
    this.contraAccountId,
  });

  final String code;
  final String name;
  final int categoryId;
  final double purchasePrice;
  final DateTime purchaseDate;
  final double usefulLifeYears;
  final double salvageValue;
  final String depreciationMethod;
  final String? location;
  final String? notes;
  final int? costCenterId;
  final int? contraAccountId;
}

/// يفتح الحوارَ ويُرجع النموذجَ، أو `null` عند الإلغاء.
Future<NewAssetForm?> showFixedAssetPicposCreateDialog(
  BuildContext context, {
  required List<AssetCategoryOption> categories,
  required List<AccountOption> accounts,
  required List<CostCenterOption> costCenters,
}) {
  return showDialog<NewAssetForm>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CreateAssetDialog(
      categories: categories,
      accounts: accounts,
      costCenters: costCenters,
    ),
  );
}

class _CreateAssetDialog extends StatefulWidget {
  const _CreateAssetDialog({
    required this.categories,
    required this.accounts,
    required this.costCenters,
  });

  final List<AssetCategoryOption> categories;
  final List<AccountOption> accounts;
  final List<CostCenterOption> costCenters;

  @override
  State<_CreateAssetDialog> createState() => _CreateAssetDialogState();
}

class _CreateAssetDialogState extends State<_CreateAssetDialog> {
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _lifeCtrl = TextEditingController(text: '5');
  final _salvageCtrl = TextEditingController(text: '0');
  final _locationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _fmt = DateFormat('yyyy/MM/dd');
  final _money = NumberFormat('#,##0.00', 'en');

  int? _categoryId;
  int? _costCenterId;
  int? _contraAccountId;
  DateTime _purchase = DateTime.now();
  String _method = kStraightLine;

  /// هل عدّل المستخدمُ العمرَ بيده؟
  ///
  /// ⚠️ **علَمٌ لا زخرفة**: التصميمُ يقول «الفئة تُملي العمر — يمكن تجاوزها
  /// لهذا الأصل». فبدونه يُلقي تبديلُ الفئة عمراً كتبه المستخدمُ عمداً.
  bool _lifeTouched = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _lifeCtrl.dispose();
    _salvageCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double? get _price => double.tryParse(_priceCtrl.text.trim());
  double? get _life => double.tryParse(_lifeCtrl.text.trim());
  double get _salvage => double.tryParse(_salvageCtrl.text.trim()) ?? 0;

  String? get _blocker {
    if (widget.categories.isEmpty) {
      return tr('لا فئاتِ أصولٍ — أنشئ فئةً من تبويب «الفئات» أوّلاً');
    }
    if (_codeCtrl.text.trim().isEmpty) return tr('كودُ الأصل مطلوب');
    if (_nameCtrl.text.trim().isEmpty) return tr('اسمُ الأصل مطلوب');
    if (_categoryId == null) return tr('اختر الفئة');
    final p = _price;
    if (p == null || p <= 0) return tr('ثمنُ الشراء مطلوبٌ وأكبرُ من صفر');
    final l = _life;
    if (l == null || l <= 0) return tr('العمرُ الإنتاجيُّ مطلوبٌ وأكبرُ من صفر');
    // 🔴 تخريديّةٌ تساوي الثمنَ أو تتجاوزه ⇒ قابلٌ للإهلاك صفرٌ أو سالب،
    //    والمحرّكُ يتخطّى الأصلَ بـ`if (monthly <= 0) continue` — فيُنشَأ
    //    أصلٌ لا يُهلك أبداً بلا أن يقول أحدٌ لماذا.
    if (_salvage >= p) return tr('القيمةُ التخريديّة يجب أن تقلّ عن ثمن الشراء');
    return null;
  }

  void _onCategory(int? id) {
    setState(() {
      _categoryId = id;
      // العمرُ يتبع الفئةَ ما لم يُكتَب بيد — راجع [_lifeTouched].
      if (!_lifeTouched && id != null) {
        final cat = widget.categories.where((c) => c.id == id).firstOrNull;
        if (cat != null) {
          _lifeCtrl.text = cat.defaultUsefulLife
              .toStringAsFixed(cat.defaultUsefulLife % 1 == 0 ? 0 : 1);
        }
      }
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _purchase,
      firstDate: DateTime(2015),
      lastDate: DateTime(2040),
    );
    if (d == null) return;
    setState(() => _purchase = d);
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: picposDialogMuted(context),
          ),
        ),
      );

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    bool number = false,
    VoidCallback? onChanged,
  }) =>
      TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : null,
        onChanged: (_) {
          onChanged?.call();
          setState(() {});
        },
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          prefixIcon: Icon(icon, size: 16),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final blocker = _blocker;
    final price = _price ?? 0;
    final life = _life ?? 0;
    final depreciable =
        depreciableAmount(purchasePrice: price, salvageValue: _salvage);
    final monthly = monthlyDepreciation(
      purchasePrice: price,
      salvageValue: _salvage,
      usefulLifeYears: life,
      depreciationMethod: _method,
    );
    final end = life > 0
        ? endOfLife(purchaseDate: _purchase, usefulLifeYears: life)
        : null;

    return PicPosDialog(
      icon: PhosphorIconsBold.package,
      title: tr('أصل ثابت جديد'),
      subtitle: tr('الفئة تُملي العمر والطريقة — يمكن تجاوزها لهذا الأصل'),
      width: 880,
      onCancel: () => Navigator.pop(context),
      footerHint: blocker,
      primaryAction: PicPosDialogAction(
        label: tr('إنشاء الأصل'),
        icon: PhosphorIconsBold.check,
        onPressed: blocker != null
            ? null
            : () => Navigator.pop(
                  context,
                  NewAssetForm(
                    code: _codeCtrl.text.trim(),
                    name: _nameCtrl.text.trim(),
                    categoryId: _categoryId!,
                    purchasePrice: _price!,
                    purchaseDate: _purchase,
                    usefulLifeYears: _life!,
                    salvageValue: _salvage,
                    depreciationMethod: _method,
                    location: _locationCtrl.text.trim().isEmpty
                        ? null
                        : _locationCtrl.text.trim(),
                    notes: _notesCtrl.text.trim().isEmpty
                        ? null
                        : _notesCtrl.text.trim(),
                    costCenterId: _costCenterId,
                    contraAccountId: _contraAccountId,
                  ),
                ),
      ),
      body: [
        _sectionLabel(tr('بيانات الأصل')),
        PicPosDialogRow(
          children: [
            _field(_codeCtrl, tr('كود الأصل *'), PhosphorIconsBold.hash),
            _field(_nameCtrl, tr('اسم الأصل *'), PhosphorIconsBold.tag),
          ],
        ),
        PicPosDialogRow(
          children: [
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration:  InputDecoration(
                labelText: tr('الفئة *'),
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(PhosphorIconsBold.folders, size: 16),
              ),
              items: [
                for (final c in widget.categories)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: _onCategory,
            ),
            _field(_locationCtrl, tr('الموقع'), PhosphorIconsBold.mapPin),
          ],
        ),
        PicPosDialogRow(
          children: [
            DropdownButtonFormField<int>(
              initialValue: _costCenterId,
              isExpanded: true,
              decoration:  InputDecoration(
                labelText: tr('مركز التكلفة'),
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(PhosphorIconsBold.target, size: 16),
              ),
              items: [
                for (final cc in widget.costCenters)
                  DropdownMenuItem(value: cc.id, child: Text(trData(cc.name))),
              ],
              onChanged: (v) => setState(() => _costCenterId = v),
            ),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration:  InputDecoration(
                  labelText: tr('تاريخ الشراء'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: const Icon(PhosphorIconsBold.calendarBlank, size: 16),
                ),
                child: Text(
                  _fmt.format(_purchase),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        _sectionLabel(tr('التكلفة والعمر')),
        PicPosDialogRow(
          children: [
            _field(
              _priceCtrl,
              tr('ثمن الشراء *'),
              PhosphorIconsBold.currencyCircleDollar,
              number: true,
            ),
            _field(
              _lifeCtrl,
              tr('العمر الإنتاجي (سنوات) *'),
              PhosphorIconsBold.hourglass,
              number: true,
              onChanged: () => _lifeTouched = true,
            ),
            _field(
              _salvageCtrl,
              tr('القيمة التخريدية'),
              PhosphorIconsBold.recycle,
              number: true,
            ),
          ],
        ),
        _sectionLabel(tr('طريقة الإهلاك')),
        PicPosDialogRow(
          children: [
            PicPosDialogChoice(
              icon: PhosphorIconsBold.equals,
              label: tr('القسط الثابت'),
              selected: _method == kStraightLine,
              onTap: () => setState(() => _method = kStraightLine),
            ),
            PicPosDialogChoice(
              icon: PhosphorIconsBold.trendDown,
              label: tr('القسط المتناقص'),
              selected: _method == kDecliningBalance,
              onTap: () => setState(() => _method = kDecliningBalance),
            ),
          ],
        ),
        _sectionLabel(tr('الربط المحاسبي')),
        // ⚠️ الحسابُ المقابلُ هو **ما دُفع منه** ثمنُ الأصل (‏خزنةٌ أو بنكٌ أو
        //    ذمّةُ مورد). و`createFixedAsset` تمرّره `contraAccountId`، فتركُه
        //    فارغاً يدع الـDAO يختار الافتراضيّ.
        DropdownButtonFormField<int>(
          initialValue: _contraAccountId,
          isExpanded: true,
          decoration:  InputDecoration(
            labelText: tr('الحساب المقابل (ما دُفع منه)'),
            border: const OutlineInputBorder(),
            isDense: true,
            prefixIcon: const Icon(PhosphorIconsBold.bank, size: 16),
          ),
          items: [
            for (final a in widget.accounts)
              DropdownMenuItem(
                value: a.id,
                child: Text('${a.code} — ${a.name}'),
              ),
          ],
          onChanged: (v) => setState(() => _contraAccountId = v),
        ),
        _field(_notesCtrl, tr('ملاحظات'), PhosphorIconsBold.note),
        _sectionLabel(tr('جدول الإهلاك')),
        // ⚠️ محسوبٌ بصيغة المحرّك لا بتقديرٍ يقاربها — راجع تعليقَ الرأس.
        PicPosDialogSummary(
          rows: [
            (label: tr('التكلفة'), value: _money.format(price), color: null),
            (
              label: tr('التخريدية'),
              value: _money.format(_salvage),
              color: AppColors.textMuted,
            ),
            (
              label: tr('القابل للإهلاك'),
              value: _money.format(depreciable < 0 ? 0 : depreciable),
              color: AppColors.primary,
            ),
            (
              label: tr('القسط الشهري'),
              value: _money.format(monthly),
              color: AppColors.warning,
            ),
            (
              label: tr('القسط السنوي'),
              value: _money.format(monthly * 12),
              color: AppColors.warning,
            ),
            (
              label: tr('نهاية العمر'),
              value: end == null
                  ? '—'
                  : '${end.year}-${end.month.toString().padLeft(2, '0')}',
              color: AppColors.textMuted,
            ),
          ],
        ),
        // حقيقتان لا مفتاحان — راجع تعليقَ الرأس.
         PicPosDialogBanner(
          icon: PhosphorIconsBold.bank,
          text: tr('يُنشأ للأصل حسابٌ فرعيٌّ ذرّيّاً مع إنشائه. والقيودُ تبقى على حساب الفئة.'),
          color: AppColors.primary,
        ),
         PicPosDialogBanner(
          icon: PhosphorIconsBold.warningCircle,
          text: tr('الإهلاك يبدأ بأوّل ترحيلٍ بعد الإنشاء بقسطٍ كامل — المحرّك لا يجزّئ شهر الشراء.'),
          color: AppColors.warning,
        ),
      ],
    );
  }
}

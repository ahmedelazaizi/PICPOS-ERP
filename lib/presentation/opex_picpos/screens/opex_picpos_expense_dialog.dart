import 'package:picpos_erp/core/i18n/tr.dart';
// حوارُ «مصروف تشغيلي جديد» بهويّة PicPos — فورك `DLGS.expense` في
// `PicPos Operating Expenses.dc.html`.
//
// ⚠️ **والمُفرَك الواجهةُ وحدَها.** الحفظُ يمرّ بـ
// `recordAndPostOperationalExpense` — وهي **معاملةٌ واحدة** تُدرج الصفَّ
// وترحّل القيدَ معاً، بعد أن كان النداءان منفصلَين فيترك الفشلُ صفّاً بلا
// قيد (‏EXP-2 / S-FAILLOUD). ونسخُ مسارها هنا يُعيد ذلك العطبَ بابَه.
//
// ═══ ⚠️ والملاحظةُ في التصميم **غيرُ صحيحةٍ في المحرّك** ═══
//
// التصميمُ يكتب: «المسوّدة لا تُنشئ قيداً محاسبياً ولا تمسّ الخزينة. القيد
// ينشأ عند الاعتماد، وحركة الخزينة عند السداد — ثلاث خطوات متمايزة عن قصد».
//
// 🔴 **والمقيسُ خلافُه**: `recordAndPostOperationalExpense` تفعل الثلاثةَ
//    **الآن**: قيدُ يوميّةٍ متوازنٌ، وسندُ صرفٍ في `safe_transactions`،
//    وخصمٌ من رصيد الخزنة — كلُّها عند الحفظ. وعمودُ `status` يبقى `draft`
//    وهو أثرُ مراجعةٍ لا بوّابة.
//
// ⇒ فزرُّ «حفظ كمسوّدة» في التصميم يَعِد بما لا يقع. والزرُّ هنا «حفظ
//   وترحيل»، والملاحظةُ تقول ما يحدث فعلاً. وشاشةٌ تُعلّم المستخدمَ محاسبةً
//   لا تقع أسوأُ من شاشةٍ بلا ملاحظة.
//
// ═══ وبندان في التصميم بلا عمودٍ في القاعدة ═══
//
// 🔴 **«الأصل المرتبط»** — لا عمودَ يربط `OpExpenses` بـ`FixedAssets`.
// 🔴 **والدوريّةُ لا تُكرّر شيئاً**: `period` وسمُ تصنيفٍ يُقرأ في التقارير،
//    ولا جدولةَ تُنشئ مصروفَ الشهر القادم. فالنصُّ «يتكرر كل شهر» يَعِد
//    بأتمتةٍ لا وجودَ لها — والوصفُ هنا «تصنيفٌ للتقارير».
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_dialog.dart';

/// فئةُ مصروفٍ كما يحتاجها الحوار — والاسمُ ورمزُ الحساب وطريقةُ التحميل.
typedef ExpenseCategoryOption = ({
  int id,
  String name,
  String accountCode,
  String allocationMethod,
});

typedef BranchOption = ({int id, String name});
typedef CostCentreOption = ({int id, String name});

/// حصيلةُ الحوار — تُمرَّر إلى `recordAndPostOperationalExpense` كما هي.
class NewExpenseForm {
  const NewExpenseForm({
    required this.categoryId,
    required this.accountCode,
    required this.amount,
    required this.expenseDate,
    required this.description,
    required this.period,
    required this.paymentMethod,
    this.reference,
    this.notes,
    this.branchId,
    this.costCenterId,
  });

  final int categoryId;
  final String accountCode;
  final double amount;
  final DateTime expenseDate;
  final String description;

  /// `monthly` · `weekly` · `daily` · `one_time`.
  final String period;

  /// `cash` · `bank`.
  final String paymentMethod;

  final String? reference;
  final String? notes;
  final int? branchId;
  final int? costCenterId;
}

List<(String, String, IconData, String)> get _periods => <(String, String, IconData, String)>[
  ('monthly', tr('شهري'), PhosphorIconsBold.calendar, tr('تصنيفٌ للتقارير')),
  ('weekly', tr('أسبوعي'), PhosphorIconsBold.calendarDots, tr('تصنيفٌ للتقارير')),
  ('daily', tr('يومي'), PhosphorIconsBold.sun, tr('تصنيفٌ للتقارير')),
  ('one_time', tr('لمرة واحدة'), PhosphorIconsBold.dot, tr('مصروف عارض')),
];

/// يفتح الحوارَ ويُرجع النموذجَ، أو `null` عند الإلغاء.
Future<NewExpenseForm?> showOpexPicposExpenseDialog(
  BuildContext context, {
  required List<ExpenseCategoryOption> categories,
  required List<BranchOption> branches,
  required List<CostCentreOption> costCentres,
}) {
  return showDialog<NewExpenseForm>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ExpenseDialog(
      categories: categories,
      branches: branches,
      costCentres: costCentres,
    ),
  );
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({
    required this.categories,
    required this.branches,
    required this.costCentres,
  });

  final List<ExpenseCategoryOption> categories;
  final List<BranchOption> branches;
  final List<CostCentreOption> costCentres;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _fmt = DateFormat('yyyy/MM/dd');
  final _money = NumberFormat('#,##0.00', 'en');

  int? _categoryId;
  int? _branchId;
  int? _costCentreId;
  DateTime _date = DateTime.now();
  String _period = 'one_time';
  String _payment = 'cash';

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_amountCtrl.text.trim());

  ExpenseCategoryOption? get _category =>
      widget.categories.where((c) => c.id == _categoryId).firstOrNull;

  String? get _blocker {
    if (widget.categories.isEmpty) {
      return tr('لا فئاتِ مصروفاتٍ — أنشئ فئةً من تبويب «الفئات» أوّلاً');
    }
    if (_categoryId == null) return tr('اختر الفئة');
    final a = _amount;
    if (a == null || a <= 0) return tr('المبلغُ مطلوبٌ وأكبرُ من صفر');
    if (_descCtrl.text.trim().isEmpty) return tr('البيانُ مطلوب');
    return null;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (d == null) return;
    setState(() => _date = d);
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

  @override
  Widget build(BuildContext context) {
    final blocker = _blocker;
    final cat = _category;
    final amount = _amount ?? 0;

    return PicPosDialog(
      icon: PhosphorIconsBold.receiptX,
      title: tr('مصروف تشغيلي جديد'),
      subtitle: tr('الفئة تحدد الحساب وطريقة التحميل على الإنتاج'),
      width: 880,
      onCancel: () => Navigator.pop(context),
      footerHint: blocker,
      primaryAction: PicPosDialogAction(
        // ⚠️ **لا «حفظ كمسوّدة»**: الحفظُ يرحّل القيدَ ويخصم من الخزنة —
        //    راجع تعليقَ الرأس. واسمُ الزرّ يقول ما يفعل.
        label: tr('حفظ وترحيل'),
        icon: PhosphorIconsBold.check,
        onPressed: blocker != null
            ? null
            : () => Navigator.pop(
                  context,
                  NewExpenseForm(
                    categoryId: _categoryId!,
                    accountCode: cat!.accountCode,
                    amount: _amount!,
                    expenseDate: _date,
                    description: _descCtrl.text.trim(),
                    period: _period,
                    paymentMethod: _payment,
                    reference: _refCtrl.text.trim().isEmpty
                        ? null
                        : _refCtrl.text.trim(),
                    notes: _notesCtrl.text.trim().isEmpty
                        ? null
                        : _notesCtrl.text.trim(),
                    branchId: _branchId,
                    costCenterId: _costCentreId,
                  ),
                ),
      ),
      body: [
        _sectionLabel(tr('الفئة والمبلغ')),
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
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            // ⚠️ الحسابُ **مشتَقٌّ** من الفئة لا مكتوبٌ بيد: `accountCode`
            //    هو ما يُرحَّل عليه القيدُ فعلاً، وحقلٌ ثانٍ يسمح باختلافهما.
            InputDecorator(
              decoration:  InputDecoration(
                labelText: tr('الحساب'),
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(PhosphorIconsBold.bank, size: 16),
              ),
              child: Text(
                cat == null ? '—' : '${cat.accountCode} · ${cat.name}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        PicPosDialogRow(
          children: [
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration:  InputDecoration(
                labelText: tr('المبلغ *'),
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon:
                    const Icon(PhosphorIconsBold.currencyCircleDollar, size: 16),
              ),
            ),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration:  InputDecoration(
                  labelText: tr('تاريخ المصروف'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: const Icon(PhosphorIconsBold.calendarBlank, size: 16),
                ),
                child: Text(
                  _fmt.format(_date),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        TextField(
          controller: _descCtrl,
          onChanged: (_) => setState(() {}),
          decoration:  InputDecoration(
            labelText: tr('البيان *'),
            border: const OutlineInputBorder(),
            isDense: true,
            prefixIcon: const Icon(PhosphorIconsBold.textAa, size: 16),
          ),
        ),
        _sectionLabel(tr('النطاق')),
        PicPosDialogRow(
          children: [
            DropdownButtonFormField<int>(
              initialValue: _branchId,
              isExpanded: true,
              decoration:  InputDecoration(
                // ⚠️ الفراغُ **ليس نقصاً**: مصروفٌ بلا فرعٍ مصروفُ إدارةٍ
                //    مشتركٌ، وتقاريرُ الفروع تعامله كذلك عمداً.
                labelText: tr('الفرع (فارغٌ = كل الفروع)'),
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(PhosphorIconsBold.storefront, size: 16),
              ),
              items: [
                for (final b in widget.branches)
                  DropdownMenuItem(value: b.id, child: Text(b.name)),
              ],
              onChanged: (v) => setState(() => _branchId = v),
            ),
            DropdownButtonFormField<int>(
              initialValue: _costCentreId,
              isExpanded: true,
              decoration:  InputDecoration(
                labelText: tr('مركز التكلفة'),
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(PhosphorIconsBold.target, size: 16),
              ),
              items: [
                for (final cc in widget.costCentres)
                  DropdownMenuItem(value: cc.id, child: Text(trData(cc.name))),
              ],
              onChanged: (v) => setState(() => _costCentreId = v),
            ),
          ],
        ),
        PicPosDialogRow(
          children: [
            TextField(
              controller: _refCtrl,
              decoration:  InputDecoration(
                labelText: tr('رقم مرجعي'),
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(PhosphorIconsBold.hash, size: 16),
              ),
            ),
            TextField(
              controller: _notesCtrl,
              decoration:  InputDecoration(
                labelText: tr('ملاحظات'),
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(PhosphorIconsBold.note, size: 16),
              ),
            ),
          ],
        ),
        // ⚠️ «الأصل المرتبط» في التصميم بلا عمودٍ في القاعدة — راجع الرأس.
        _sectionLabel(tr('الدورية')),
        PicPosDialogRow(
          children: [
            for (final (id, label, icon, _) in _periods)
              PicPosDialogChoice(
                icon: icon,
                label: label,
                selected: _period == id,
                onTap: () => setState(() => _period = id),
              ),
          ],
        ),
        _sectionLabel(tr('الدفع')),
        PicPosDialogRow(
          children: [
            PicPosDialogChoice(
              icon: PhosphorIconsBold.money,
              label: tr('نقدي'),
              selected: _payment == 'cash',
              onTap: () => setState(() => _payment = 'cash'),
            ),
            PicPosDialogChoice(
              icon: PhosphorIconsBold.bank,
              label: tr('بنك'),
              selected: _payment == 'bank',
              onTap: () => setState(() => _payment = 'bank'),
            ),
          ],
        ),
        _sectionLabel(tr('ما سيحدث')),
        PicPosDialogSummary(
          rows: [
            (
              label: tr('{p0} مدين', {'p0': cat?.accountCode ?? '—'}),
              value: _money.format(amount),
              color: AppColors.primary,
            ),
            (
              label: _payment == 'cash' ? tr('الخزينة دائن') : tr('البنك دائن'),
              value: _money.format(amount),
              color: AppColors.success,
            ),
            (
              label: tr('حالة المصروف'),
              value: tr('مسوّدة'),
              color: AppColors.warning,
            ),
          ],
        ),
        // ⚠️ **نصٌّ يخالف التصميمَ عمداً** — التصميمُ يقول إنّ المسوّدةَ بلا
        //    قيدٍ ولا خزنة، والمحرّكُ يفعل الثلاثةَ الآن. راجع تعليقَ الرأس.
        PicPosDialogBanner(
          icon: PhosphorIconsBold.scales,
          text: _payment == 'cash'
              ? tr('الحفظ يرحّل القيدَ ويُنشئ سندَ صرفٍ ويخصم من الخزينة فوراً. و«مسوّدة» أثرُ مراجعةٍ لا بوّابةٌ قبل القيد.')
              : tr('الحفظ يرحّل القيدَ فوراً. والمصروفُ البنكيُّ لا يحرّك خزنةً بعد — القيدُ وحدَه.'),
          color: AppColors.warning,
        ),
      ],
    );
  }
}

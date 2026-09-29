import 'package:ural_erp/core/i18n/tr.dart';
// حوارُ «تحميل مصروف على أمر تصنيع» بهويّة PicPos — فورك `DLGS.allocate`
// في `PicPos Operating Expenses.dc.html`.
//
// ⚠️ **والحسابُ في `domain/models/expense_allocation.dart`** — خالصٌ يُقاس
// وحدَه، ويحمل قاعدةَ فرق التقريب: المجموعُ يساوي المبلغَ بالضبط، والفرقُ
// يُحمَّل على أكبر سطرٍ فعلاً لا في النصّ وحدَه.
//
// ═══ ⚠️ وأثرُ اللوحة يُعرَض قبل الحفظ لأنّه قرارُ محاسبةِ تكاليف ═══
//
// الأساسان ليسا تفصيلَ واجهة:
//
// • **بالمعدل** أمينٌ لمعدّل الفئة ويترك جزءاً غيرَ محمَّل — وتكلفةُ الوحدة
//   المسجَّلةُ تخرج **أقلَّ من الحقيقيّة**، فيتضخّم هامشُ الربح الظاهر.
// • **توزيع كامل المبلغ** لا يترك باقياً لكنّه يجعل أوامرَ الدفعة تحمل نصيبَ
//   أوامرَ أخرى.
//
// فالباقي والمحمَّلُ يُعرَضان بالرقم قبل الضغط.
//
// ═══ 🔴 وبندٌ في التصميم لا يُنقَل ═══
//
// `save:'تحميل على ٢ أمر'` يفترض أنّ التحميلَ لا يقيّد شيئاً. **والمقيسُ
// خلافُه**: `addMfgOrderCost` على الخادم تُرحّل قيدَ `manufacturing_overhead`
// — وتعليقُ الـDAO صريح: «صفٌّ محلّيٌّ بلا قيدِه يجعل تكلفةَ الأمر تخالف
// الأستاذ». فالتحميلُ فعلٌ محاسبيٌّ ويُقال ذلك في اللوحة.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/expense_allocation.dart';
import '../../picpos_shell/picpos_dialog.dart';

/// مصروفٌ قابلٌ للتحميل — ما يحتاجه الحوار منه.
typedef AllocatableExpense = ({
  int id,
  String label,
  double amount,
  String categoryName,
  String allocationMethod,
  double rate,
});

/// أمرُ تصنيعٍ مرشَّح.
typedef AllocatableOrder = ({int id, String orderNumber, double quantity});

/// حصيلةُ الحوار — أسطرُ التحميل جاهزةً للكتابة.
class AllocationForm {
  const AllocationForm({
    required this.expenseId,
    required this.costType,
    required this.description,
    required this.lines,
  });

  final int expenseId;

  /// `overhead` · `utility` · `depreciation`.
  final String costType;
  final String description;

  /// ‏`(orderId, amount)` — الأسطرُ **بأصفارها محذوفة**: صفٌّ بصفرٍ يملأ
  /// جدولَ التكاليف بلا أثرٍ على تكلفة الأمر.
  final List<({int orderId, double amount})> lines;
}

List<(String, String, IconData)> get _costTypes => <(String, String, IconData)>[
  ('overhead', tr('تحميل غير مباشر'), PhosphorIconsBold.lightning),
  ('utility', tr('مرافق'), PhosphorIconsBold.fire),
  ('depreciation', tr('إهلاك'), PhosphorIconsBold.arrowDownRight),
];

/// يفتح الحوارَ ويُرجع النموذجَ، أو `null` عند الإلغاء.
Future<AllocationForm?> showOpexPicposAllocateDialog(
  BuildContext context, {
  required List<AllocatableExpense> expenses,
  required List<AllocatableOrder> orders,
}) {
  return showDialog<AllocationForm>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _AllocateDialog(expenses: expenses, orders: orders),
  );
}

class _AllocateDialog extends StatefulWidget {
  const _AllocateDialog({required this.expenses, required this.orders});

  final List<AllocatableExpense> expenses;
  final List<AllocatableOrder> orders;

  @override
  State<_AllocateDialog> createState() => _AllocateDialogState();
}

class _AllocateDialogState extends State<_AllocateDialog> {
  final _money = NumberFormat('#,##0.00', 'en');

  int? _expenseId;
  final Set<int> _picked = {};
  AllocationBasis _basis = AllocationBasis.byRate;
  String _costType = 'overhead';

  AllocatableExpense? get _expense =>
      widget.expenses.where((e) => e.id == _expenseId).firstOrNull;

  Map<int, double> get _quantities => {
        for (final o in widget.orders)
          if (_picked.contains(o.id)) o.id: o.quantity,
      };

  AllocationPlan get _plan {
    final e = _expense;
    return allocateExpense(
      expenseAmount: e?.amount ?? 0,
      quantities: _quantities,
      basis: _basis,
      rate: e?.rate ?? 0,
    );
  }

  String? get _blocker {
    if (widget.expenses.isEmpty) {
      return tr('لا مصروفاتِ قابلةً للتحميل — الفئةُ يجب أن تكون مرتبطةً بالإنتاج');
    }
    if (widget.orders.isEmpty) return tr('لا أوامرَ تصنيعٍ مرشَّحة');
    if (_expenseId == null) return tr('اختر المصروف');
    if (_picked.isEmpty) return tr('اختر أمراً واحداً على الأقلّ');
    // 🔴 خطّةٌ كلُّ أسطرها أصفارٌ لا تكتب شيئاً — والزرُّ الذي «ينجح» بلا
    //    أثرٍ أسوأُ من زرٍّ معطَّلٍ يقول السبب.
    if (_plan.allocated.abs() < 0.005) {
      return _basis == AllocationBasis.byRate
          ? tr('المعدلُ أو الكمّيّاتُ صفرٌ — لا شيءَ يُحمَّل')
          : tr('الكمّيّاتُ المختارةُ صفرٌ — لا أساسَ للتوزيع');
    }
    return null;
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

  Widget _readOnly(String label, String value, IconData icon) =>
      InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          prefixIcon: Icon(icon, size: 16),
        ),
        child: Text(value, style: const TextStyle(fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) {
    final blocker = _blocker;
    final e = _expense;
    final plan = _plan;
    final n = _picked.length;
    final over = plan.unallocated < -0.005;

    return PicPosDialog(
      icon: PhosphorIconsBold.factory,
      title: tr('تحميل مصروف على أمر تصنيع'),
      subtitle: tr('يدخل المصروف في تكلفة الأمر ثم تكلفة الوحدة'),
      accent: const Color(0xFF8B5CF6),
      width: 880,
      onCancel: () => Navigator.pop(context),
      footerHint: blocker,
      primaryAction: PicPosDialogAction(
        label: n == 0 ? tr('تحميل') : tr('تحميل على {n} {p0}', {'n': n, 'p0': n == 1 ? 'أمر' : 'أوامر'}),
        icon: PhosphorIconsBold.check,
        onPressed: blocker != null
            ? null
            : () => Navigator.pop(
                  context,
                  AllocationForm(
                    expenseId: _expenseId!,
                    costType: _costType,
                    description: '${e!.categoryName} — ${e.label}',
                    lines: [
                      // ⚠️ الأصفارُ تُحذَف — راجع [AllocationForm.lines].
                      for (final l in plan.lines)
                        if (l.amount.abs() >= 0.005)
                          (orderId: l.orderId, amount: l.amount),
                    ],
                  ),
                ),
      ),
      body: [
        _sectionLabel(tr('المصروف')),
        DropdownButtonFormField<int>(
          initialValue: _expenseId,
          isExpanded: true,
          decoration:  InputDecoration(
            labelText: tr('المصروف *'),
            border: const OutlineInputBorder(),
            isDense: true,
            prefixIcon: const Icon(PhosphorIconsBold.receiptX, size: 16),
          ),
          items: [
            for (final x in widget.expenses)
              DropdownMenuItem(
                value: x.id,
                child: Text('${x.categoryName} — ${x.label}'),
              ),
          ],
          onChanged: (v) => setState(() => _expenseId = v),
        ),
        PicPosDialogRow(
          children: [
            _readOnly(
              tr('المبلغ الكلي'),
              e == null ? '—' : _money.format(e.amount),
              PhosphorIconsBold.currencyCircleDollar,
            ),
            _readOnly(
              tr('المعدل'),
              e == null || e.rate == 0 ? '—' : _money.format(e.rate),
              PhosphorIconsBold.percent,
            ),
          ],
        ),
        _sectionLabel(tr('الأوامر المستهدفة')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in widget.orders)
              FilterChip(
                selected: _picked.contains(o.id),
                onSelected: (on) => setState(
                  () => on ? _picked.add(o.id) : _picked.remove(o.id),
                ),
                avatar: Icon(
                  PhosphorIconsBold.factory,
                  size: 13,
                  color: _picked.contains(o.id)
                      ? const Color(0xFF8B5CF6)
                      : picposDialogMuted(context),
                ),
                label: Text(
                  tr('{p0} — {p1} وحدة', {'p0': o.orderNumber, 'p1': o.quantity.toStringAsFixed(0)}),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
        _sectionLabel(tr('أساس التوزيع')),
        PicPosDialogRow(
          children: [
            PicPosDialogChoice(
              icon: PhosphorIconsBold.package,
              label: tr('بالمعدل × الكمية'),
              selected: _basis == AllocationBasis.byRate,
              accent: const Color(0xFF8B5CF6),
              onTap: () => setState(() => _basis = AllocationBasis.byRate),
            ),
            PicPosDialogChoice(
              icon: PhosphorIconsBold.arrowsSplit,
              label: tr('توزيع كامل المبلغ'),
              selected: _basis == AllocationBasis.fullAmount,
              accent: const Color(0xFF8B5CF6),
              onTap: () => setState(() => _basis = AllocationBasis.fullAmount),
            ),
          ],
        ),
        _sectionLabel(tr('نوع التكلفة')),
        PicPosDialogRow(
          children: [
            for (final (id, label, icon) in _costTypes)
              PicPosDialogChoice(
                icon: icon,
                label: label,
                selected: _costType == id,
                accent: const Color(0xFF8B5CF6),
                onTap: () => setState(() => _costType = id),
              ),
          ],
        ),
        _sectionLabel(tr('أثر التحميل')),
        PicPosDialogSummary(
          rows: [
            for (final l in plan.lines)
              (
                label: widget.orders
                        .where((o) => o.id == l.orderId)
                        .firstOrNull
                        ?.orderNumber ??
                    tr('أمر #{p0}', {'p0': l.orderId}),
                value: _money.format(l.amount),
                color: const Color(0xFF8B5CF6),
              ),
            (
              label: tr('المحمَّل'),
              value: _money.format(plan.allocated),
              color: AppColors.success,
            ),
            (
              // ⚠️ **سالبٌ يعني تجاوزاً** — والتصميمُ يفترضه موجباً دائماً.
              label: over ? tr('تجاوزُ التحميل') : tr('غير محمَّل'),
              value: _money.format(plan.unallocated.abs()),
              color: plan.isExact ? AppColors.textMuted : AppColors.error,
            ),
          ],
        ),
        if (!plan.isExact && _expenseId != null)
          PicPosDialogBanner(
            icon: PhosphorIconsBold.warningCircle,
            text: over
                ? 'المعدلُ أعلى من الواقع: التحميلُ يفوق المصروفَ بـ'
                    '${_money.format(plan.unallocated.abs())} ج.م — تكلفةُ '
                    'الوحدة تخرج أعلى من الحقيقيّة.'
                : 'يبقى ${_money.format(plan.unallocated)} ج.م غيرَ محمَّل. '
                    'تكلفةُ الوحدة المسجَّلة تخرج أقلَّ من الحقيقيّة فيتضخّم '
                    'هامشُ الربح الظاهر — راجع معدلَ الفئة أو وزّع كاملَ '
                    'المبلغ.',
            color: AppColors.error,
          ),
        // ⚠️ التحميلُ **فعلٌ محاسبيّ** — راجع تعليقَ الرأس.
        const PicPosDialogBanner(
          icon: PhosphorIconsBold.scales,
          text: 'التحميل يدخل تكلفةَ الأمر ثمّ تكلفةَ الوحدة، ويُرحَّل قيدَ '
              'تحميلٍ غير مباشر على الخادم.',
          color: AppColors.warning,
        ),
      ],
    );
  }
}

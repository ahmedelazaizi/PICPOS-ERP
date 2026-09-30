import 'package:ural_erp/core/i18n/tr.dart';
// حوارُ «إيداع شيكات بالبنك» بهويّة PicPos — فورك `DLGS.deposit` في
// `PicPos Cheques.dc.html`.
//
// ═══ لماذا بناءٌ لا تنسيق ═══
//
// `DepositForCollectionDialog` القديمُ يودع **ورقةً واحدة**: يستقبل
// `paperNumber` و`amount` مفردَين. والتصميمُ يودع **دفعةً** — مجموعةُ رقاقاتٍ
// تُختار، وقسيمةُ إيداعٍ واحدةٌ، وملخّصٌ بالإجمالي. فمَن يودع خمسةَ شيكاتٍ
// بقسيمةٍ واحدةٍ في البنك كان يفتح الحوارَ خمسَ مرّاتٍ ويكتب رقمَ القسيمة
// خمساً.
//
// ⚠️ **والمُفرَك الواجهةُ وحدَها.** الحلقةُ فوق `depositForCollection` وحصيلةُ
// الفشل الجزئيّ في `depositPapersForCollection` المشتركة.
//
// ═══ ثلاثةُ فروقٍ عن التصميم — كلُّها مقيسةٌ من القاعدة ═══
//
// 🔴 **الرقاقاتُ لا تعرض المرتجعةَ رغم أنّ التصميم يعرضها.** حارسُ الـDAO
//    صريح: `if (!['pending','in_portfolio'].contains(paper.status)) throw`.
//    فورقةٌ مرتجعةٌ في هذا الحوار تُلقي دائماً. والتصميمُ محقٌّ في أنّ إعادةَ
//    الإيداع حاجةٌ قائمة — لكنّ مسارَها في الكود آخرُ: `updatePaperStatus(id,
//    'deposited')`، وهو ما يفعله زرُّ الصفّ «إعادة إيداع». فالفصلُ هنا ليس
//    إسقاطاً للتصميم بل توجيهٌ لكلّ حالةٍ إلى المسار الذي يقبلها.
//
// 🔴 **«تاريخ الإيداع» يُعرَض ولا يُدخَل.** الـDAO يختم بـ`DateTime.now()`
//    ولا عمودَ لتاريخِ إيداعٍ في `CommercialPapers`. فحقلٌ قابلٌ للتحرير يَعِد
//    بما لا يُكتَب — والتصميمُ نفسُه يكتب قيمتَه `'اليوم'`.
//
// 🔴 **مفتاحا «طباعة القسيمة» و«تنبيه عند الاستحقاق» غيرُ معروضَين.** لا
//    مسارَ طباعةٍ لقسيمة إيداعٍ ولا جدولَ تذكيراتٍ للأوراق. ومفتاحٌ يُقلَب ولا
//    يفعل شيئاً أسوأُ من غيابه.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/repositories/treasury_repository.dart' show SafeData;
import '../../picpos_shell/picpos_dialog.dart';

/// ورقةٌ مرشَّحةٌ للإيداع — القدرُ الذي يحتاجه الحوارُ من صفّ القاعدة.
///
/// ⚠️ **ليست `CommercialPaperData`** عمداً: حارسُ
/// `presentation_db_import_guard` يمنع ملفَّ عرضٍ جديداً من استيراد
/// `data/database`، والحوارُ لا يحتاج الصفَّ كلَّه.
class DepositCandidate {
  const DepositCandidate({
    required this.id,
    required this.paperNumber,
    required this.amount,
    required this.dueDate,
    required this.partyName,
  });

  final int id;
  final String paperNumber;
  final double amount;
  final DateTime dueDate;
  final String partyName;
}

/// حصيلةُ الحوار — ما اختاره المشغّلُ ليُمرَّر للدالّة المشتركة.
class DepositBatchForm {
  const DepositBatchForm({
    required this.paperIds,
    required this.bankSafeId,
    required this.voucherNumber,
  });

  final List<int> paperIds;
  final int bankSafeId;

  /// رقمُ قسيمة الإيداع — يُكتَب في `notes` على كلّ ورقةٍ في الدفعة، وهو ما
  /// يجعل تتبّعَ القسيمة ممكناً لاحقاً.
  final String voucherNumber;
}

/// يفتح الحوارَ ويُرجع النموذجَ، أو `null` عند الإلغاء.
Future<DepositBatchForm?> showChequesPicposDepositDialog(
  BuildContext context, {
  required List<DepositCandidate> candidates,
  required List<SafeData> bankSafes,
  Set<int> preselected = const {},
}) {
  return showDialog<DepositBatchForm>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DepositBatchDialog(
      candidates: candidates,
      bankSafes: bankSafes,
      preselected: preselected,
    ),
  );
}

class _DepositBatchDialog extends StatefulWidget {
  const _DepositBatchDialog({
    required this.candidates,
    required this.bankSafes,
    required this.preselected,
  });

  final List<DepositCandidate> candidates;
  final List<SafeData> bankSafes;

  /// ما يُفتَح الحوارُ وهو مُعلَّم — زرُّ الصفّ يمرّر ورقتَه وحدَها.
  final Set<int> preselected;

  @override
  State<_DepositBatchDialog> createState() => _DepositBatchDialogState();
}

class _DepositBatchDialogState extends State<_DepositBatchDialog> {
  final _voucherCtrl = TextEditingController();
  final _fmt = DateFormat('yyyy/MM/dd');

  late final Set<int> _picked = {...widget.preselected};
  int? _bankSafeId;

  @override
  void initState() {
    super.initState();
    // خزنةٌ بنكيّةٌ واحدةٌ ⇒ لا اختيارَ فيها، فتُنتقى سلفاً بدل أن يُطلَب من
    // المشغّل اختيارُ ما لا بديلَ له.
    if (widget.bankSafes.length == 1) _bankSafeId = widget.bankSafes.first.id;
  }

  @override
  void dispose() {
    _voucherCtrl.dispose();
    super.dispose();
  }

  List<DepositCandidate> get _selected =>
      widget.candidates.where((c) => _picked.contains(c.id)).toList();

  double get _total => _selected.fold<double>(0, (s, c) => s + c.amount);

  SafeData? get _bank =>
      widget.bankSafes.where((s) => s.id == _bankSafeId).firstOrNull;

  /// أقربُ استحقاقٍ بين المختارة — `null` حين لا اختيار.
  DateTime? get _nearestDue {
    if (_selected.isEmpty) return null;
    return _selected
        .map((c) => c.dueDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// ما يمنع الحفظَ — يُقال في التذييل بدل ارتدادٍ صامت.
  String? get _blocker {
    if (widget.bankSafes.isEmpty) {
      return tr('لا خزائنَ بنكيّة — أضف بنكاً من إعدادات الخزينة أوّلاً');
    }
    if (_bankSafeId == null) return tr('اختر البنك');
    if (_picked.isEmpty) return tr('اختر شيكاً واحداً على الأقلّ');
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

  @override
  Widget build(BuildContext context) {
    final blocker = _blocker;
    final n = _picked.length;
    final due = _nearestDue;

    return PicPosDialog(
      icon: PhosphorIconsBold.vault,
      title: tr('إيداع شيكات بالبنك'),
      subtitle: tr('الإيداع ينقل الورقة من الخزنة إلى «تحت التحصيل» بالبنك'),
      width: 880,
      onCancel: () => Navigator.pop(context),
      footerHint: blocker,
      primaryAction: PicPosDialogAction(
        // ‏`save:'إيداع ٣ شيكات'` في التصميم — والعددُ محسوبٌ لا مكتوب.
        label: n == 0 ? tr('إيداع') : tr('إيداع {n} {p0}', {'n': n, 'p0': n == 1 ? tr('شيك') : tr('شيكات')}),
        icon: PhosphorIconsBold.check,
        onPressed: blocker != null
            ? null
            : () => Navigator.pop(
                  context,
                  DepositBatchForm(
                    paperIds: _selected.map((c) => c.id).toList(),
                    bankSafeId: _bankSafeId!,
                    voucherNumber: _voucherCtrl.text.trim(),
                  ),
                ),
      ),
      body: [
        _sectionLabel(tr('البنك والحساب')),
        PicPosDialogRow(
          children: [
            DropdownButtonFormField<int>(
              initialValue: _bankSafeId,
              isExpanded: true,
              decoration:  InputDecoration(
                labelText: tr('البنك *'),
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(PhosphorIconsBold.bank, size: 16),
              ),
              items: [
                for (final s in widget.bankSafes)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) => setState(() => _bankSafeId = v),
            ),
            // ⚠️ الحسابُ **مشتَقٌّ** من الخزنة لا مكتوبٌ بيد: خزنةٌ بنكيّةٌ
            //    تحمل رقمَ حسابها، وكتابتُه ثانيةً تسمح باختلافهما.
            InputDecorator(
              decoration:  InputDecoration(
                labelText: tr('الحساب'),
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(PhosphorIconsBold.hash, size: 16),
              ),
              child: Text(
                _bank?.accountNumber ?? '—',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        PicPosDialogRow(
          children: [
            // ⚠️ يُعرَض ولا يُدخَل — راجع تعليقَ الرأس.
            InputDecorator(
              decoration:  InputDecoration(
                labelText: tr('تاريخ الإيداع'),
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(PhosphorIconsBold.calendarBlank, size: 16),
              ),
              child: Text(
                _fmt.format(DateTime.now()),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            TextField(
              controller: _voucherCtrl,
              decoration:  InputDecoration(
                labelText: tr('رقم قسيمة الإيداع'),
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(PhosphorIconsBold.receipt, size: 16),
              ),
            ),
          ],
        ),
        _sectionLabel(tr('الشيكات المختارة')),
        if (widget.candidates.isEmpty)
           PicPosDialogBanner(
            icon: PhosphorIconsBold.info,
            text: tr('لا أوراقَ بالخزنة قابلةً للإيداع. الإيداعُ يقبل الورقةَ المعلَّقةَ أو التي في الحافظة وحدَها.'),
            color: AppColors.textMuted,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in widget.candidates)
                FilterChip(
                  selected: _picked.contains(c.id),
                  onSelected: (on) => setState(
                    () => on ? _picked.add(c.id) : _picked.remove(c.id),
                  ),
                  avatar: Icon(
                    PhosphorIconsBold.note,
                    size: 13,
                    color: _picked.contains(c.id)
                        ? AppColors.primary
                        : picposDialogMuted(context),
                  ),
                  label: Text(
                    '${c.paperNumber} — ${c.amount.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  tooltip: tr('{p0} · يستحقّ {p1}', {'p0': c.partyName, 'p1': _fmt.format(c.dueDate)}),
                ),
            ],
          ),
        _sectionLabel(tr('ملخص الإيداع')),
        PicPosDialogSummary(
          rows: [
            (label: tr('عدد الشيكات'), value: '$n', color: null),
            (
              label: tr('إجمالي القيمة'),
              value: _total.toStringAsFixed(2),
              color: AppColors.success,
            ),
            (
              label: tr('إلى'),
              value: _bank?.name ?? '—',
              color: AppColors.primary,
            ),
            (
              label: tr('أقرب استحقاق'),
              value: due == null ? '—' : _fmt.format(due),
              color: AppColors.warning,
            ),
          ],
        ),
        // ⚠️ قاعدةُ محاسبةٍ تشرح سلوكاً يبدو خطأً — نفسُ انضباط ملاحظات
        //    التبويبات: البنكُ لا يُدان بالإيداع بل بالتحصيل، فمن يودع ثمّ
        //    ينظر إلى رصيد البنك لا يجد المبلغَ ويظنّ الإيداعَ فشل.
         PicPosDialogBanner(
          icon: PhosphorIconsBold.scales,
          text: tr('الإيداع حالةٌ وسيطة: الورقة تنتقل إلى «تحت التحصيل» ولا يُدان البنكُ إلّا عند التحصيل.'),
          color: AppColors.warning,
        ),
      ],
    );
  }
}

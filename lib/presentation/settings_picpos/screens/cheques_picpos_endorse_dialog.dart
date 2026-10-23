import 'package:picpos_erp/core/i18n/tr.dart';
// حوارُ «تجيير ورقة» بهويّة PicPos — فورك `DLGS.endorse` في
// `PicPos Cheques.dc.html`.
//
// ⚠️ **والمُفرَك الواجهةُ وحدَها.** الكتابةُ المزدوجةُ (‏خادمٌ ثمّ قاعدة) في
// `endorsePaperTo` المشتركة.
//
// ═══ ما لا يُنقَل من التصميم — وكلُّه مقيس ═══
//
// 🔴 **مجموعةُ «ما يُسدَّد بها»** (‏رقاقاتُ فواتير المورد) غيرُ معروضة:
//    `endorsePaper(id, toPartyId)` تنقل الورقةَ إلى الطرف ولا تربطها بفاتورةٍ
//    بعينها. فرقاقاتٌ تُختار ولا تُكتَب تَعِد بتخصيصٍ لا يقع.
//
// 🔴 **مفتاحُ «طباعة محضر تجيير»** — لا قالبَ محضرٍ في مولّد التقارير.
//
// 🔴 **مفتاحُ «إبقاء مسؤولية الضمان»** — لا عمودَ له في `CommercialPapers`،
//    ومفتاحٌ يُقلَب ولا يُحفَظ في ورقةٍ ماليّةٍ أسوأُ من غيابه. والتحذيرُ
//    المصاحبُ في التصميم يبقى نصّاً لأنّه **صحيحٌ دائماً** في القانون
//    المصريّ: المُجيِّر ضامنٌ ما لم يُنَصّ على خلافه.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_dialog.dart';

/// حصيلةُ الحوار.
class EndorseForm {
  const EndorseForm({required this.toPartyId, required this.notes});

  final int toPartyId;
  final String notes;
}

/// طرفٌ يصلح مُجيَّراً إليه — الاسمُ والمعرِّفُ وحدَهما.
typedef EndorseParty = ({int id, String name});

/// يفتح الحوارَ ويُرجع النموذجَ، أو `null` عند الإلغاء.
Future<EndorseForm?> showChequesPicposEndorseDialog(
  BuildContext context, {
  required String paperNumber,
  required String paperTypeLabel,
  required String fromPartyName,
  required double amount,
  required DateTime dueDate,
  required List<EndorseParty> parties,
}) {
  return showDialog<EndorseForm>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _EndorseDialog(
      paperNumber: paperNumber,
      paperTypeLabel: paperTypeLabel,
      fromPartyName: fromPartyName,
      amount: amount,
      dueDate: dueDate,
      parties: parties,
    ),
  );
}

class _EndorseDialog extends StatefulWidget {
  const _EndorseDialog({
    required this.paperNumber,
    required this.paperTypeLabel,
    required this.fromPartyName,
    required this.amount,
    required this.dueDate,
    required this.parties,
  });

  final String paperNumber;
  final String paperTypeLabel;
  final String fromPartyName;
  final double amount;
  final DateTime dueDate;
  final List<EndorseParty> parties;

  @override
  State<_EndorseDialog> createState() => _EndorseDialogState();
}

class _EndorseDialogState extends State<_EndorseDialog> {
  final _notesCtrl = TextEditingController();
  int? _toPartyId;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  String? get _blocker {
    if (widget.parties.isEmpty) return tr('لا أطرافَ مسجَّلون');
    if (_toPartyId == null) return tr('اختر المُجيَّر إليه');
    return null;
  }

  static String _d(DateTime x) =>
      '${x.year}-${x.month.toString().padLeft(2, '0')}-'
      '${x.day.toString().padLeft(2, '0')}';

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
    final to = widget.parties.where((p) => p.id == _toPartyId).firstOrNull;

    return PicPosDialog(
      icon: PhosphorIconsBold.arrowBendUpLeft,
      title: tr('تجيير ورقة'),
      subtitle: tr('نقل الورقة لطرف ثالث سداداً لمديونية'),
      accent: const Color(0xFF8B5CF6),
      width: 860,
      onCancel: () => Navigator.pop(context),
      footerHint: blocker,
      primaryAction: PicPosDialogAction(
        label: tr('تأكيد التجيير'),
        icon: PhosphorIconsBold.check,
        onPressed: blocker != null
            ? null
            : () => Navigator.pop(
                  context,
                  EndorseForm(
                    toPartyId: _toPartyId!,
                    notes: _notesCtrl.text.trim(),
                  ),
                ),
      ),
      body: [
        _sectionLabel(tr('الورقة والطرف')),
        PicPosDialogRow(
          children: [
            _readOnly(
              tr('الورقة'),
              '${widget.paperTypeLabel} ${widget.paperNumber}',
              PhosphorIconsBold.scroll,
            ),
            _readOnly(
              tr('الطرف الأصلي'),
              widget.fromPartyName,
              PhosphorIconsBold.user,
            ),
          ],
        ),
        PicPosDialogRow(
          children: [
            _readOnly(
              tr('المبلغ'),
              widget.amount.toStringAsFixed(2),
              PhosphorIconsBold.currencyCircleDollar,
            ),
            DropdownButtonFormField<int>(
              initialValue: _toPartyId,
              isExpanded: true,
              decoration:  InputDecoration(
                labelText: tr('المُجيَّر إليه *'),
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(PhosphorIconsBold.userSwitch, size: 16),
              ),
              items: [
                for (final p in widget.parties)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => _toPartyId = v),
            ),
          ],
        ),
        TextField(
          controller: _notesCtrl,
          maxLines: 2,
          decoration:  InputDecoration(
            labelText: tr('ملاحظات'),
            border: const OutlineInputBorder(),
            isDense: true,
            prefixIcon: const Icon(PhosphorIconsBold.note, size: 16),
          ),
        ),
        _sectionLabel(tr('الأثر')),
        PicPosDialogSummary(
          rows: [
            (
              label: tr('الورقة تنتقل إلى'),
              value: to?.name ?? '—',
              color: const Color(0xFF8B5CF6),
            ),
            (
              label: tr('مديونية {p0}', {'p0': to?.name ?? tr('المُجيَّر إليه')}),
              value: '-${widget.amount.toStringAsFixed(2)}',
              color: AppColors.success,
            ),
            (
              label: tr('ذمة {p0}', {'p0': widget.fromPartyName}),
              value: tr('لا تتغيّر'),
              color: AppColors.textMuted,
            ),
            (
              label: tr('استحقاق الورقة'),
              value: _d(widget.dueDate),
              color: AppColors.warning,
            ),
          ],
        ),
        // ⚠️ نصٌّ لا مفتاح: لا عمودَ لمسؤولية الضمان في القاعدة — راجع
        //    تعليقَ الرأس. والقاعدةُ نفسُها صحيحةٌ في كلّ الأحوال.
         PicPosDialogBanner(
          icon: PhosphorIconsBold.shieldWarning,
          text: tr('المُجيِّر ضامنٌ للوفاء: لو ارتجعت الورقة عاد الالتزامُ على منشأتنا لا على الطرف الأصليّ.'),
          color: AppColors.error,
        ),
      ],
    );
  }
}

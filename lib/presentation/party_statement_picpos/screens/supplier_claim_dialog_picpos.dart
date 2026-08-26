part of 'party_statement_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// «تسوية ومطالبة المورد» — كشفُ المورد، `DLGS.reconcile` في التصميم
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️ **مراسلةٌ لا قيدٌ ماليّ.** المطالبةُ تُسجَّل وتُرسَل؛ والمالُ يتحرّك حين
// يصل إشعارُ المورد الدائنُ فيُدخَل مستنداً مستقلّاً في مسارِه. وقيدُ
// المطالبة نفسِها كان سيُنتج ذمّةً وهميّةً قبل أن يوافق المورد.
//
// ⚠️ **والفروقُ كمّيّاتٌ لا مبالغ** — كما في تبويبة المطابقة: الاستعلامُ يعود
// بـ`quantity` من سطرِ الأمر وسطرِ الفاتورة، لا بقيمتهما. فحقلُ «صافي
// المطالبة» يُكتَب بيدِ المشغّل ولا يُشتقّ من الكمّيّات، والتصميمُ يعرضه
// محسوباً لأنّه صورة.
//
// ⚠️ **وثلاثةُ مفاتيحَ لم تُبنَ ولم تُرسَم**: «إرفاقُ أذون الاستلام وصور
// الميزان» (لا بنيةَ مرفقات)، و«تعليقُ سداد أمرٍ حتى التسوية» (حجزُ سدادٍ
// يُفرَض في مسار الدفع)، و«تصعيدٌ تلقائيٌّ بعد ٧ أيّام» (لا جدولةَ خلفيّة).
// وما بقي منها ممّا يُقاس صار **مهلةَ ردٍّ** تُعرَض.

/// شكلُ التسوية — بطاقاتُ «شكل التسوية» الأربع.
enum _SettlementKind { creditNote, goods, invoiceDiscount, cashRefund }

extension _SettlementMeta on _SettlementKind {
  String get code => switch (this) {
        _SettlementKind.creditNote => 'credit_note',
        _SettlementKind.goods => 'goods',
        _SettlementKind.invoiceDiscount => 'invoice_discount',
        _SettlementKind.cashRefund => 'cash_refund',
      };

  String get label => switch (this) {
        _SettlementKind.creditNote => 'إشعار دائن من المورد',
        _SettlementKind.goods => 'تعويض بضاعة',
        _SettlementKind.invoiceDiscount => 'خصم من الفاتورة القادمة',
        _SettlementKind.cashRefund => 'رد نقدي',
      };

  IconData get icon => switch (this) {
        _SettlementKind.creditNote => PhosphorIconsBold.receiptX,
        _SettlementKind.goods => PhosphorIconsBold.package,
        _SettlementKind.invoiceDiscount =>
          PhosphorIconsBold.arrowCounterClockwise,
        _SettlementKind.cashRefund => PhosphorIconsBold.money,
      };
}

/// حوارُ تسجيل مطالبةٍ على فروق المطابقة الثلاثيّة.
class _SupplierClaimDialog extends ConsumerStatefulWidget {
  const _SupplierClaimDialog({
    required this.party,
    required this.gaps,
    required this.ledgerBalance,
  });

  final Party party;

  /// أسطرُ المطابقة **التي بها فروقٌ** — تُعرَض شرائحَ تُختار.
  final List<PoMatchRow> gaps;

  /// «رصيده في دفاترنا» — لقطةٌ وقتَ المطالبة.
  final double ledgerBalance;

  @override
  ConsumerState<_SupplierClaimDialog> createState() =>
      _SupplierClaimDialogState();
}

class _SupplierClaimDialogState extends ConsumerState<_SupplierClaimDialog> {
  late final Set<int> _selected;
  _SettlementKind _kind = _SettlementKind.creditNote;
  DateTime? _replyDue;
  final _netCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // كلُّ الفروق مختارةٌ ابتداءً — وهو ما يعرضه التصميم، والمشغّلُ يستثني.
    _selected = {for (var i = 0; i < widget.gaps.length; i++) i};
    _replyDue = DateTime.now().add(const Duration(days: 7));
  }

  @override
  void dispose() {
    _netCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  List<PoMatchRow> get _chosen =>
      [for (var i = 0; i < widget.gaps.length; i++) if (_selected.contains(i)) widget.gaps[i]];

  /// وصفُ الفرق كما يُقرأ في الشريحة — كمّيّةٌ لا مبلغ.
  String _gapLabel(PoMatchRow r) {
    final qty = r.qtyGap.abs() >= 0.001 ? r.qtyGap : r.billingGap;
    return '${r.gapKind} ${r.orderNumber} — ${_qty(qty)} (${r.productName})';
  }

  Future<void> _save() async {
    final net = double.tryParse(_netCtrl.text.trim()) ?? 0;
    if (_chosen.isEmpty) {
      AppToast.show(context, 'لم يُختَر فرقٌ واحد', type: ToastType.warning);
      return;
    }
    setState(() => _saving = true);
    try {
      // الأسطرُ تُسلسَل في عمودٍ — قرارٌ موثَّقٌ في تعريف الجدول: المطالبةُ
      // مراسلةٌ لا تُرحَّل ولا يُستعلَم عبر أسطرها.
      final lines = [
        for (final r in _chosen)
          {
            'orderId': r.orderId,
            'orderNumber': r.orderNumber,
            'productName': r.productName,
            'gapKind': r.gapKind,
            'ordered': r.ordered,
            'received': r.received,
            'invoiced': r.invoiced,
          }
      ];
      await ref.read(partiesRepositoryProvider).insertSupplierClaim(
            supplierId: widget.party.id,
            claimDate: DateTime.now(),
            settlementKind: _kind.code,
            ledgerBalance: widget.ledgerBalance,
            netAmount: net,
            linesJson: jsonEncode(lines),
            lineCount: lines.length,
            replyDueAt: _replyDue,
            notes:
                _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context, true);
      AppToast.show(context, 'سُجّلت المطالبة كمسوّدة',
          type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, 'تعذّر حفظ المطالبة: $e', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy/MM/dd');
    return PicPosDialog(
      icon: PhosphorIconsBold.scales,
      title: 'تسوية ومطالبة المورد',
      subtitle: 'الفروق المطالَب بها والمقابل المتفق عليه',
      width: 760,
      accent: AppColors.warning,
      onCancel: _saving ? null : () => Navigator.pop(context),
      primaryAction: PicPosDialogAction(
        label: 'حفظ المطالبة',
        icon: PhosphorIconsBold.check,
        busy: _saving,
        onPressed: _saving ? null : _save,
      ),
      footerHint: 'المطالبة مراسلة لا قيد — الرصيد لا يتحرك حتى يصل '
          'إشعار المورد الدائن',
      body: [
        PicPosPanelGroup(
          label: 'المورد والرصيد',
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _readOnly('المورد', widget.party.name, PhosphorIconsBold.truck),
              _readOnly('رصيده في دفاترنا', _money(widget.ledgerBalance),
                  PhosphorIconsBold.book),
              _readOnly('تاريخ المطابقة', df.format(DateTime.now()),
                  PhosphorIconsBold.calendarBlank),
              _readOnly('عدد الفروق', '${widget.gaps.length}',
                  PhosphorIconsBold.gitDiff),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PicPosPanelGroup(
          label: 'الفروق المطالَب بها',
          hint: 'كميات من المطابقة الثلاثية — لا مبالغ',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.gaps.length; i++)
                CheckboxListTile(
                  dense: true,
                  value: _selected.contains(i),
                  onChanged: (v) => setState(() {
                    if (v ?? false) {
                      _selected.add(i);
                    } else {
                      _selected.remove(i);
                    }
                  }),
                  title: Text(
                    _gapLabel(widget.gaps[i]),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PicPosPanelGroup(
          label: 'شكل التسوية',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final k in _SettlementKind.values)
                SizedBox(
                  width: 340,
                  child: PicPosDialogChoice(
                    icon: k.icon,
                    label: k.label,
                    accent: AppColors.primary,
                    selected: _kind == k,
                    onTap: () => setState(() => _kind = k),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PicPosPanelGroup(
          label: 'الصافي ومهلة الرد',
          // ⚠️ الصافي يُكتَب بيد: الفروقُ كمّيّاتٌ والاستعلامُ لا يحمل أسعارَ
          //    الأسطر، فاشتقاقُه كان سيُنتج رقماً يبدو محسوباً وهو مخترَع.
          hint: 'الصافي يُكتب بيدك — الفروق كميات ولا سعر لسطرها في الاستعلام',
          child: Column(
            children: [
              PicPosDialogField(
                label: 'صافي المطالبة (موجب = لنا على المورد)',
                child: TextField(
                  controller: _netCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    suffixText: AppConstants.currencySymbolEn,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              PicPosDialogField(
                label: 'مهلة الرد',
                child: InkWell(
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _replyDue ?? now,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 180)),
                    );
                    if (picked != null) setState(() => _replyDue = picked);
                  },
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(_replyDue == null
                        ? 'اختر تاريخاً'
                        : df.format(_replyDue!)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              PicPosDialogField(
                label: 'ملاحظات',
                height: 76,
                child: TextField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _readOnly(String label, String value, IconData icon) => SizedBox(
        width: 330,
        child: PicPosDialogField(
          label: label,
          child: Row(
            children: [
              Icon(icon, size: 15, color: context.picposMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      );
}

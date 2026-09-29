part of 'party_statement_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// «متابعة تحصيل» — كشفُ العميل، `DLGS.followup` في التصميم
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️ **سجلُّ تواصلٍ لا قيدٌ ماليّ.** لا خزنةَ ولا ذمّةَ ولا قيد. والمالُ
// يتحرّك بسند القبض — وهو زرُّ «تحصيل» في نفس الصفّ.
//
// ⚠️ **وثلاثةُ مفاتيحَ في التصميم لم تُبنَ ولم تُرسَم**: «مهمّةُ تحصيلٍ في
// زيارة الأربعاء» تربط المتابعةَ بمسارات التوزيع، و«تعليقُ البيع الآجل حتى
// الوعد» حجزُ ائتمانٍ يُفرَض عند إنشاء الفاتورة، و«تصعيدٌ تلقائيٌّ بعد ٣
// أيّام» يحتاج جدولةً خلفيّة. ولا واحدٌ منها مبنيّ، فمفتاحٌ يُحفَظ ولا
// يُنفَّذ أسوأُ من مفتاحٍ غائب.
//
// ⚠️ **و«موعدُ الإجراء التالي» تاريخٌ يُعرَض لا تنبيهٌ يُطلَق** — مكتوبٌ في
// تذييل الحوار كي لا ينتظر المشغّلُ صوتاً لا يأتي.

/// نتيجةُ الاتّصال — بطاقاتُ «نتيجة الاتصال» الأربع.
enum _FollowUpOutcome { promise, noAnswer, disputed, refused }

extension _OutcomeMeta on _FollowUpOutcome {
  String get code => switch (this) {
        _FollowUpOutcome.promise => 'promise',
        _FollowUpOutcome.noAnswer => 'no_answer',
        _FollowUpOutcome.disputed => 'disputed',
        _FollowUpOutcome.refused => 'refused',
      };

  String get label => switch (this) {
        _FollowUpOutcome.promise => tr('وعد بالسداد'),
        _FollowUpOutcome.noAnswer => tr('لم يُرد'),
        _FollowUpOutcome.disputed => tr('اعتراض على المبلغ'),
        _FollowUpOutcome.refused => tr('رفض السداد'),
      };

  IconData get icon => switch (this) {
        _FollowUpOutcome.promise => PhosphorIconsBold.handshake,
        _FollowUpOutcome.noAnswer => PhosphorIconsBold.phoneSlash,
        _FollowUpOutcome.disputed => PhosphorIconsBold.chatCircleDots,
        _FollowUpOutcome.refused => PhosphorIconsBold.prohibit,
      };

  Color get tint => switch (this) {
        _FollowUpOutcome.promise => AppColors.success,
        _FollowUpOutcome.noAnswer => AppColors.warning,
        _FollowUpOutcome.disputed => AppColors.warning,
        _FollowUpOutcome.refused => AppColors.error,
      };

  /// موعدُ الإجراء التالي المشتقُّ من النتيجة. الوعدُ يأخذ تاريخَه، والباقي
  /// مهلٌ ثابتةٌ من التصميم («يُعاد الاتصال بعد يومين»).
  DateTime? nextAction(DateTime now, DateTime? promised) => switch (this) {
        _FollowUpOutcome.promise => promised,
        _FollowUpOutcome.noAnswer => now.add(const Duration(days: 2)),
        _FollowUpOutcome.disputed => now.add(const Duration(days: 3)),
        _FollowUpOutcome.refused => now.add(const Duration(days: 1)),
      };
}

/// حوارُ تسجيل محاولةِ تحصيل.
///
/// يعود بـ`true` إن حُفظت متابعةٌ — فتُعيد الشاشةُ التحميلَ لتظهر في العدّاد.
class _FollowUpDialog extends ConsumerStatefulWidget {
  const _FollowUpDialog({
    required this.party,
    required this.invoice,
    required this.priorAttempts,
  });

  final Party party;

  /// الفاتورةُ موضوعُ المتابعة — «موضوع المتابعة» في التصميم.
  final PartyOpenInvoiceRow invoice;

  /// «محاولاتٌ سابقة» — **عدٌّ مقيسٌ** من الجدول لا رقمٌ مكتوب.
  final int priorAttempts;

  @override
  ConsumerState<_FollowUpDialog> createState() => _FollowUpDialogState();
}

class _FollowUpDialogState extends ConsumerState<_FollowUpDialog> {
  _FollowUpOutcome _outcome = _FollowUpOutcome.promise;
  DateTime? _promisedDate;
  final _amountCtrl = TextEditingController();
  final _personCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // الافتراضُ: يَعِد بكامل المتبقّي بعد أسبوع — يُعدَّل، ولا يُخترَع رقمٌ
    // غيرُ المتبقّي المقيس.
    _promisedDate = DateTime.now().add(const Duration(days: 7));
    _amountCtrl.text =
        widget.invoice.remaining.toStringAsFixed(AppConstants.decimalPlaces);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _personCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _isPromise => _outcome == _FollowUpOutcome.promise;

  Future<void> _save() async {
    final promisedAmount = double.tryParse(_amountCtrl.text.trim());
    if (_isPromise && (promisedAmount == null || promisedAmount <= 0)) {
      AppToast.show(context, tr('المبلغ الموعود غير صالح'), type: ToastType.error);
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      await ref.read(partiesRepositoryProvider).insertPartyFollowUp(
            partyId: widget.party.id,
            contactedAt: now,
            outcome: _outcome.code,
            invoiceId: widget.invoice.invoiceId,
            invoiceNumber: widget.invoice.invoiceNumber,
            // لقطةُ المتبقّي **وقتَ المتابعة** — لا يُعاد حسابُها لاحقاً.
            amountDue: widget.invoice.remaining,
            promisedDate: _isPromise ? _promisedDate : null,
            promisedAmount: _isPromise ? promisedAmount : null,
            contactPerson: _personCtrl.text.trim().isEmpty
                ? null
                : _personCtrl.text.trim(),
            nextActionAt: _outcome.nextAction(now, _promisedDate),
            notes:
                _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context, true);
      AppToast.show(context, tr('سُجّلت المتابعة'), type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, tr('تعذّر حفظ المتابعة: {e}', {'e': e}), type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final df = DateFormat('yyyy/MM/dd');
    return PicPosDialog(
      icon: PhosphorIconsBold.phone,
      title: tr('متابعة تحصيل'),
      subtitle: tr('تسجيل محاولة تحصيل وتحديد الخطوة التالية'),
      width: 720,
      accent: AppColors.primary,
      onCancel: _saving ? null : () => Navigator.pop(context),
      primaryAction: PicPosDialogAction(
        label: tr('حفظ المتابعة'),
        icon: PhosphorIconsBold.check,
        busy: _saving,
        onPressed: _saving ? null : _save,
      ),
      footerHint: 'موعد الإجراء التالي تاريخٌ يُعرض في المتابعات — '
          'لا تنبيه تلقائي',
      body: [
        PicPosPanelGroup(
          label: tr('موضوع المتابعة'),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _readOnly(tr('الفاتورة'), inv.invoiceNumber,
                  PhosphorIconsBold.receipt),
              _readOnly(tr('المتبقي'), _money(inv.remaining),
                  PhosphorIconsBold.money),
              _readOnly(
                inv.overdue ? tr('عمر التأخر') : tr('يستحق بعد'),
                _count(inv.daysLate.abs(), tr('يوماً')),
                PhosphorIconsBold.hourglass,
              ),
              // **عدٌّ مقيسٌ** لا رقمٌ مكتوبٌ كما في التصميم.
              _readOnly(tr('محاولات سابقة'), '${widget.priorAttempts}',
                  PhosphorIconsBold.phoneCall),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PicPosPanelGroup(
          label: tr('نتيجة الاتصال'),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final o in _FollowUpOutcome.values)
                SizedBox(
                  width: 320,
                  child: PicPosDialogChoice(
                    icon: o.icon,
                    label: o.label,
                    accent: o.tint,
                    selected: _outcome == o,
                    onTap: () => setState(() => _outcome = o),
                  ),
                ),
            ],
          ),
        ),
        if (_isPromise) ...[
          const SizedBox(height: 14),
          PicPosPanelGroup(
            label: tr('تفاصيل الوعد'),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 320,
                  child: PicPosDialogField(
                    label: tr('تاريخ السداد الموعود'),
                    child: InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _promisedDate ?? now,
                          firstDate: now.subtract(const Duration(days: 1)),
                          lastDate: now.add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() => _promisedDate = picked);
                        }
                      },
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          _promisedDate == null
                              ? tr('اختر تاريخاً')
                              : df.format(_promisedDate!),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: PicPosDialogField(
                    label: tr('المبلغ الموعود'),
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        suffixText: AppConstants.currencySymbolEn,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        PicPosPanelGroup(
          label: tr('من تُكلِّم وملاحظات'),
          child: Column(
            children: [
              PicPosDialogField(
                label: tr('من تكلّم معه'),
                child: TextField(
                  controller: _personCtrl,
                  decoration:  InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: tr('اسم المسؤول عند العميل'),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              PicPosDialogField(
                label: tr('ملاحظات'),
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
        width: 320,
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

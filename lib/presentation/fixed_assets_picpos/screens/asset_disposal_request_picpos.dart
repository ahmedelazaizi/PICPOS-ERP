import 'package:picpos_erp/core/i18n/tr.dart';
// «طلب استبعاد أصل» — تصميمُ المالك `(6)`.
//
// ═══ ⚠️ لوحٌ كاملُ العرض لا شاشةٌ سادسة ═══
//
// مسارُه في التصميم «الأصول الثابتة / طلب استبعاد أصل»، ويُفتَح من تبويب
// «الاستبعاد والبيع». وشاشةٌ مستقلّةٌ كانت تعني ستّةَ مواضعِ توصيلٍ
// وصلاحيّةً أخرى لشيءٍ لا يُبلَغ إلّا من هناك — وهو عينُ حكمِ بطاقة الأصل.
//
// ═══ 🔴 و«الخسارة المتوقَّعة» تتبع العلامة ═══
//
// التصميمُ يسمّي الحقلَ «الخسارة المتوقعة» دائماً. وبيعٌ بأكثرَ من القيمة
// الدفتريّة **ربحٌ**، فعرضُه تحت عنوان «خسارة» — أو عرضُ سالبٍ تحته — يقلب
// إشارةَ رقمٍ يدخل قائمةَ الدخل. فالاسمُ محسوبٌ في
// `domain/models/asset_disposal_plan.dart` لا مكتوبٌ هنا.
//
// ═══ ⚠️ و«طريقة التحصيل» قسمٌ ظاهرٌ لا مطويّ ═══
//
// التصميمُ يطويها مع «المرفقات» في شريطٍ واحد. والمرفقاتُ **بُنيت في
// v176 (§٨)** وصارت لوحاً مستقلّاً أسفلَ هذا القسم لا مطويّاً معه، فيبقى
// في الشريط حقلٌ واحد — وهو الحقلُ الذي **يقرّر القيد**:
// نقديٌّ يُمدَن حسابَ الخزنة ويحرّك درجَها، وآجلٌ يُمدَن حسابَ العميل ويرفع
// ذمّتَه. وطيُّ ما يغيّر القيدَ خلفَ سهمٍ أسوأُ من تغييرِ تخطيط.
//
// ═══ ⚠️ والخزنةُ حقلٌ ليس في التصميم ═══
//
// `disposeAsset` القائمةُ تقيّد مدينَ نقديّةٍ على `1111` **ولا تحرّك خزنةً**،
// فيزيد النقدُ في الأستاذ ولا يزيد في أيّ درج. فالبيعُ النقديُّ هنا يشترط
// خزنةً — ومَن يعتمد هو مَن يعرف أيَّ درجٍ استلم.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/asset_disposal_plan.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_form_action_bar.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../widgets/compact_date_picker.dart';
import '../../picpos_shell/picpos_attachments_panel.dart';

final _money = NumberFormat('#,##0.00');
final _dateFmt = DateFormat('dd-MM-yyyy');

const _err = Color(0xFFEF4444);
const _warn = Color(0xFFF59E0B);

/// رقمُ الطلب قبل الحفظ — **لا يُخمَّن** (‏مواصفة ٠٦٦: المولّدُ داخلَ
/// معاملةِ الحفظ).
String get kDisposalNumberPlaceholder => tr('يُولَّد عند الحفظ');

/// الأصلُ كما يراه النموذج — **قيمةٌ خالصةٌ** لا صفُّ قاعدة.
typedef DisposalAssetSummary = ({
  int id,
  String code,
  String name,
  double originalCost,
  double accumulatedDepreciation,
  String status,
});

typedef DisposalPartyOption = ({int id, String name});
typedef DisposalSafeOption = ({int id, String name});
typedef DisposalCostCenterOption = ({int id, String name});

/// قيمةُ طلبٍ قائمٍ يُفتَح للتعديل.
typedef DisposalRequestValue = ({
  int id,
  String number,
  String status,
  DateTime disposalDate,
  String method,
  double disposalValue,
  String collectionMethod,
  int? buyerPartyId,
  int? costCenterId,
  String reason,
});

/// ما يخرج من النموذج.
typedef DisposalSubmission = ({
  int? requestId,
  int assetId,
  DateTime disposalDate,
  String method,
  double disposalValue,
  String collectionMethod,
  int? buyerPartyId,
  int? safeId,
  int? costCenterId,
  String reason,

  /// 🔴 **الفرقُ بين الزرَّين**: المسوّدةُ بلا أثرٍ محاسبيّ، والاعتمادُ يُخرج
  ///    الأصلَ من الدفاتر ويقيّد الربحَ أو الخسارة.
  bool approve,
});

class AssetDisposalRequestForm extends StatefulWidget {
  const AssetDisposalRequestForm({
    super.key,
    required this.asset,
    required this.parties,
    required this.safes,
    required this.costCenters,
    required this.onSubmit,
    this.value,
    this.onBack,
    this.busy = false,
  });

  final DisposalAssetSummary asset;

  /// `null` ⇒ طلبٌ جديد.
  final DisposalRequestValue? value;

  final List<DisposalPartyOption> parties;
  final List<DisposalSafeOption> safes;
  final List<DisposalCostCenterOption> costCenters;

  final Future<void> Function(DisposalSubmission) onSubmit;
  final VoidCallback? onBack;
  final bool busy;

  @override
  State<AssetDisposalRequestForm> createState() =>
      AssetDisposalRequestFormState();
}

class AssetDisposalRequestFormState extends State<AssetDisposalRequestForm> {
  late DateTime _date = widget.value?.disposalDate ?? DateTime.now();
  late String _method = widget.value?.method ?? 'sale';
  late String _collection = widget.value?.collectionMethod ?? 'cash';
  late int? _buyerId = widget.value?.buyerPartyId;
  late int? _costCenterId = widget.value?.costCenterId;
  int? _safeId;

  late final _valueCtrl = TextEditingController(
      text: (widget.value?.disposalValue ?? 0) == 0
          ? ''
          : '${widget.value!.disposalValue}');
  late final _reasonCtrl =
      TextEditingController(text: widget.value?.reason ?? '');

  @override
  void initState() {
    super.initState();
    if (widget.safes.length == 1) _safeId = widget.safes.single.id;
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  /// 🔴 **المُعتمَدُ والملغى كلاهما مقفول.** الملغى كان يُفتَح بأزرارٍ حيّةٍ
  ///    لأنّ أصلَه ما زال نشطاً، فيُعتمَد مستندٌ أُلغي — ويخرج الأصلُ بقيدٍ
  ///    لا مستندَ ساريَ له.
  bool get _isApproved =>
      widget.value?.status == 'approved' || widget.value?.status == 'cancelled';
  bool get _carriesProceeds => disposalCarriesProceeds(_method);
  double get _value => double.tryParse(_valueCtrl.text.trim()) ?? 0;

  DisposalOutcome get _outcome => computeDisposalOutcome(
        originalCost: widget.asset.originalCost,
        accumulatedDepreciation: widget.asset.accumulatedDepreciation,
        disposalValue: _carriesProceeds ? _value : 0,
      );

  /// سببُ منعِ الاعتماد — أو `null`.
  ///
  /// ⚠️ **يُعرَض ولا يُبتلَع**: زرٌّ معطَّلٌ بلا سببٍ ظاهرٍ يُقرأ «معطوب».
  String? get blockReason => validateAssetDisposal(
        method: _method,
        disposalValue: _carriesProceeds ? _value : 0,
        collectionMethod: _collection,
        buyerPartyId: _buyerId,
        safeId: _safeId,
        reason: _reasonCtrl.text,
        assetStatus: widget.asset.status,
      );

  /// سببُ منعِ **حفظِ المسوّدة** — والخزنةُ ليست منه.
  ///
  /// ⚠️ الخزنةُ قرارُ لحظةِ الاعتماد؛ واشتراطُها على المسوّدة كان يمنع
  ///    تحريرَ طلبٍ يراجعه غيرُ مَن كتبه.
  String? get draftBlockReason => validateAssetDisposal(
        method: _method,
        disposalValue: _carriesProceeds ? _value : 0,
        collectionMethod: _collection,
        buyerPartyId: _buyerId,
        safeId: 0,
        reason: _reasonCtrl.text,
        assetStatus: widget.asset.status,
      );

  @override
  Widget build(BuildContext context) {
    final approveReason = blockReason;
    final draftReason = draftBlockReason;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _assetCard(),
                const SizedBox(height: 10),
                _financialsCard(),
                const SizedBox(height: 10),
                _disposalCard(),
                const SizedBox(height: 10),
                _collectionCard(),
                const SizedBox(height: 10),
                // v176 / §٨ — عرضُ البيعِ وتقريرُ اللجنة.
                //
                // 🔴 **والاعتمادُ لا يُقفل الورقة.** الطلبُ المُعتمَدُ
                //    تُقفَل حقولُه — الأصلُ خرج من الدفاتر وقيدُه رُحِّل.
                //    أمّا عقدُ البيع وتقريرُ اللجنة فيصلان **بعد**
                //    الاعتماد بطبيعتهما، فقفلُهما معه يمنع أهمَّ ورقةٍ
                //    في الملفّ.
                PicPosAttachmentsPanel(
                  entityType: 'asset_disposal',
                  entityId: widget.value?.id,
                ),
                if (approveReason != null) ...[
                  const SizedBox(height: 8),
                  Text(approveReason,
                      key: const Key('disposal_block_reason'),
                      style: const TextStyle(fontSize: 12, color: _err)),
                ],
              ],
            ),
          ),
        ),
        PicPosFormActionBar(
          onBack: widget.onBack,
          busy: widget.busy,
          hint: _isApproved
              ? tr('طلبٌ مُعتمَدٌ — الأصلُ خرج من الدفاتر ولا يُعدَّل')
              : tr('المسوّدةُ بلا أثرٍ محاسبيّ · والاعتمادُ يُخرج الأصلَ ويقيّد الفرق'),
          draft: PicPosFormAction(
            label: tr('حفظ مسودة'),
            icon: PhosphorIconsBold.floppyDisk,
            onPressed: (_isApproved || draftReason != null)
                ? null
                : () => _submit(approve: false),
          ),
          primary: PicPosFormAction(
            label: tr('مراجعة واعتماد'),
            icon: PhosphorIconsBold.check,
            onPressed: (_isApproved || approveReason != null)
                ? null
                : () => _submit(approve: true),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // معلوماتُ الأصل — تُعرَض ولا تُحرَّر
  // ═══════════════════════════════════════════════════════════════════════

  Widget _assetCard() => PicPosContentCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                 Expanded(
                  child: PicPosSectionHeader(
                    icon: PhosphorIconsBold.identificationCard,
                    title: tr('معلومات الأصل'),
                  ),
                ),
                _statusPill(),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _readOnly(tr('رقم الأصل'), widget.asset.code)),
                const SizedBox(width: 10),
                Expanded(child: _readOnly(tr('اسم الأصل'), widget.asset.name)),
                const SizedBox(width: 10),
                Expanded(
                  child: _readOnly(
                      tr('رقم الطلب'),
                      widget.value?.number ?? kDisposalNumberPlaceholder),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _statusPill() {
    final status = widget.value?.status ?? 'draft';
    final (label, tint) = switch (status) {
      'approved' => (tr('معتمد'), AppColors.success),
      'cancelled' => (tr('ملغى'), AppColors.textMuted),
      _ => (tr('مسودة'), _warn),
    };
    return Container(
      key: const Key('disposal_status_pill'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tint)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // البياناتُ الماليّة — للقراءة فقط
  // ═══════════════════════════════════════════════════════════════════════

  Widget _financialsCard() => PicPosContentCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
             PicPosSectionHeader(
              icon: PhosphorIconsBold.scales,
              title: tr('البيانات المالية للأصل (للقراءة فقط)'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _readOnly(tr('التكلفة الأصلية'),
                        _money.format(widget.asset.originalCost))),
                const SizedBox(width: 10),
                Expanded(
                    child: _readOnly(tr('مجموع الإهلاك المتراكم'),
                        _money.format(widget.asset.accumulatedDepreciation))),
                const SizedBox(width: 10),
                Expanded(
                  child: _readOnly(
                    tr('القيمة الدفترية الحالية'),
                    _money.format(_outcome.bookValue),
                    key: const Key('disposal_book_value'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  // ═══════════════════════════════════════════════════════════════════════
  // بياناتُ الاستبعاد
  // ═══════════════════════════════════════════════════════════════════════

  Widget _disposalCard() => PicPosContentCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
             PicPosSectionHeader(
              icon: PhosphorIconsBold.trash,
              title: tr('بيانات الاستبعاد'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _dateField()),
                const SizedBox(width: 10),
                Expanded(child: _methodField()),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _valueField()),
                const SizedBox(width: 10),
                Expanded(child: _buyerField()),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _reasonField()),
                const SizedBox(width: 10),
                Expanded(child: _outcomeField()),
              ],
            ),
          ],
        ),
      );

  Widget _dateField() => InkWell(
        key: const Key('disposal_date'),
        onTap: _isApproved
            ? null
            : () async {
                final picked = await CompactDatePicker.showCompact(
                  context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (picked != null) setState(() => _date = picked);
              },
        child: InputDecorator(
          decoration:  InputDecoration(
            labelText: tr('تاريخ الاستبعاد'),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          child: Text(_dateFmt.format(_date)),
        ),
      );

  Widget _methodField() => DropdownButtonFormField<String>(
        key: const Key('disposal_method'),
        initialValue: _method,
        isExpanded: true,
        decoration:  InputDecoration(
          labelText: tr('طريقة الاستبعاد'),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final m in kDisposalMethods)
            DropdownMenuItem(value: m, child: Text(disposalMethodLabel(m))),
        ],
        onChanged: _isApproved
            ? null
            : (v) => setState(() {
                  _method = v ?? 'sale';
                  // 🔴 تبديلُ الطريقة إلى ما لا ثمنَ له **يمسح الثمنَ**، فلا
                  //    يبقى رقمٌ مكتوبٌ يُرفَض عند الحفظ بلا أن يُفهَم سببُه.
                  if (!disposalCarriesProceeds(_method)) _valueCtrl.clear();
                }),
      );

  Widget _valueField() => TextField(
        key: const Key('disposal_value'),
        controller: _valueCtrl,
        enabled: !_isApproved && _carriesProceeds,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: tr('قيمة البيع المتوقعة'),
          helperText: _carriesProceeds
              ? null
              : tr('{p0} بلا ثمن', {'p0': disposalMethodLabel(_method)}),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _buyerField() => DropdownButtonFormField<int?>(
        key: const Key('disposal_buyer'),
        initialValue: _buyerId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: _carriesProceeds ? tr('المشتري') : tr('المستلِم'),
          helperText: _collection == 'credit'
              // ⚠️ نصٌّ حرٌّ لا يكفي في الآجل: القيدُ يحتاج حساباً والذمّةُ
              //    تحتاج طرفاً يُطالَب.
              ? tr('الآجل يحتاج طرفاً مسجَّلاً')
              : null,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
           DropdownMenuItem<int?>(value: null, child: Text(tr('— بلا طرف'))),
          for (final p in widget.parties)
            DropdownMenuItem<int?>(value: p.id, child: Text(p.name)),
        ],
        onChanged: _isApproved ? null : (v) => setState(() => _buyerId = v),
      );

  Widget _reasonField() => TextField(
        key: const Key('disposal_reason'),
        controller: _reasonCtrl,
        enabled: !_isApproved,
        maxLines: 2,
        onChanged: (_) => setState(() {}),
        decoration:  InputDecoration(
          labelText: tr('سبب الاستبعاد'),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  /// 🔴 **الاسمُ يتبع العلامة** — راجع رأسَ الملفّ.
  Widget _outcomeField() {
    final o = _outcome;
    final tint = o.gainLoss > 0
        ? AppColors.success
        : o.gainLoss < 0
            ? _err
            : AppColors.textMuted;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: o.label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      child: Text(
        _money.format(o.gainLoss.abs()),
        key: const Key('disposal_outcome'),
        style: TextStyle(fontWeight: FontWeight.w800, color: tint),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // طريقةُ التحصيل — قسمٌ ظاهرٌ لا مطويّ (راجع رأسَ الملفّ)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _collectionCard() => PicPosContentCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
             PicPosSectionHeader(
              icon: PhosphorIconsBold.wallet,
              title: tr('طريقة التحصيل'),
            ),
            const SizedBox(height: 6),
            if (!_carriesProceeds)
              Text(
                tr('{p0} بلا تحصيل — ولا قيدَ نقديّةٍ ولا ذمّة.', {'p0': disposalMethodLabel(_method)}),
                key: const Key('disposal_no_collection'),
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              )
            else ...[
              Row(
                children: [
                  for (final m in kDisposalCollectionMethods) ...[
                    Expanded(child: _collectionChip(m)),
                    if (m != kDisposalCollectionMethods.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _collection == 'cash'
                        ? _safeField()
                        : const _CreditNote(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _costCenterField()),
                ],
              ),
            ],
          ],
        ),
      );

  Widget _collectionChip(String m) {
    final selected = _collection == m;
    return InkWell(
      key: Key('disposal_collection_$m'),
      onTap: _isApproved ? null : () => setState(() => _collection = m),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.10)
              : context.picposField,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : context.picposHairline,
          ),
        ),
        child: Text(
          disposalCollectionLabel(m),
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? AppColors.primary : null,
          ),
        ),
      ),
    );
  }

  Widget _safeField() => DropdownButtonFormField<int?>(
        key: const Key('disposal_safe'),
        initialValue: _safeId,
        isExpanded: true,
        decoration:  InputDecoration(
          labelText: tr('الخزينة'),
          helperText: tr('يُقيَّد على حسابها المرتبط وتزيد أرصدتُها بالمبلغ'),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final s in widget.safes)
            DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
        ],
        onChanged: _isApproved ? null : (v) => setState(() => _safeId = v),
      );

  Widget _costCenterField() => DropdownButtonFormField<int?>(
        key: const Key('disposal_cost_center'),
        initialValue: _costCenterId,
        isExpanded: true,
        decoration:  InputDecoration(
          labelText: tr('مركز التكلفة'),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
           DropdownMenuItem<int?>(value: null, child: Text(tr('— عام'))),
          for (final c in widget.costCenters)
            DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
        ],
        onChanged: _isApproved ? null : (v) => setState(() => _costCenterId = v),
      );

  Widget _readOnly(String label, String value, {Key? key}) => InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: context.picposField,
        ),
        child: Text(value, key: key),
      );

  Future<void> _submit({required bool approve}) async {
    await widget.onSubmit((
      requestId: widget.value?.id,
      assetId: widget.asset.id,
      disposalDate: _date,
      method: _method,
      disposalValue: _carriesProceeds ? _value : 0,
      collectionMethod: _collection,
      buyerPartyId: _buyerId,
      // الآجلُ لا يدخل درجاً — والمحرّكُ يُطبّع، وهذا يوافقه هنا كي لا
      // يُرسَل حقلٌ يناقض طريقتَه.
      safeId: _collection == 'cash' ? _safeId : null,
      costCenterId: _costCenterId,
      reason: _reasonCtrl.text.trim(),
      approve: approve,
    ));
  }
}

class _CreditNote extends StatelessWidget {
  const _CreditNote();

  @override
  Widget build(BuildContext context) =>  InputDecorator(
        decoration: InputDecoration(
          labelText: tr('الخزينة'),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        child: Text(
          tr('لا خزينة — الآجل يُحمَّل على ذمّة الطرف'),
          key: const Key('disposal_credit_note'),
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      );
}

// شاشةُ «سند قيد» — تصميمُ المالك `(14)`، مدخلٌ جانبيٌّ ثالثٌ بجوار سندَي
// القبض والصرف.
//
// ═══ ⚠️ ولماذا شاشةٌ لا حوار ═══
//
// القيدُ اليدويُّ اليومَ حوارٌ داخلَ «اليومية العامة» (‏`showCreateEntryDialog`
// — `part` من تلك الشاشة، فلا يبلغه شيءٌ من خارجها). والتصميمُ يعطيه صفحةً
// كاملةً بمسارٍ خاصّ: «المالية والمحاسبة / القيود المحاسبية / سند قيد جديد».
//
// **والحوارُ الأصلُ يبقى** — هو مسارُ «قيدٌ من قالب» ومسارُ العكس، وحذفُه
// تغييرٌ في شاشةٍ أخرى لم يطلبه أحد.
//
// ═══ 🔴 ورقمُ السند لا يُخمَّن ═══
//
// التصميمُ يعرض `JV-0031` وشارةَ «مسودة» في الترويسة. ورقمُ القيد يُولَّده
// `_generateEntryNumber` **داخلَ معاملة الحفظ** (‏Spec 066) — فقبلها لا رقمَ
// موجود. ورقمٌ مخمَّنٌ على ورقةٍ أو شاشةٍ يجعل المستخدمَ يسجّله في دفترٍ
// ورقيٍّ أو يبلّغه، ثمّ يُحفَظ غيرُه.
//
// ⇒ الخانةُ تقول **«يُولَّد عند الحفظ»**، والشارةُ لا تُرسَم قبل أن يوجد
//   مستندٌ توصفه.
//
// ═══ 🔴 و«المرجع» عمودٌ كان مشحوناً بلا كاتب ═══
//
// `journal_entries.reference` مزروعٌ منذ v174، و`grep` على المستودع كلِّه لا
// يجد إلّا تعريفَه والهجرة: **لا كاتبَ ولا قارئ**. وهو عينُ ما وقع لـ
// `custodian_user_id` و`source_voucher_id`. وهذه الشاشةُ أوّلُ مَن يكتبه.
//
// ⚠️ **وليس `referenceType`**: ذاك مفرداتٌ مغلقةٌ يكتبها المحرّك
// (`sale` · `purchase` · `daily`…) ويُرشَّح بها كلُّ تقريرٍ على المصدر، وهذا
// نصٌّ حرٌّ يقرؤه إنسان (رقمُ عقدٍ · إشعارُ بنكٍ · مستندٌ ورقيّ).
//
// ═══ ⚠️ ومركزُ التكلفة **على السطر** — وقد تحقّقتُ أنّ التقارير تقرؤه ═══
//
// الخطّةُ وسمت هذا «للتحقّق وقتَ التنفيذ»: هل تربط تقاريرُ مراكز التكلفة على
// `journal_entries.cost_center_id` (مستوى القيد) بينما تلتقط الواجهةُ مركزاً
// لكلّ سطر؟ والقياسُ في `accounting_reports_dao.dart`:
//
//     AND (lines.cost_center_id IN (…)
//          OR (lines.cost_center_id IS NULL AND entry.cost_center_id IN (…)))
//
// أي أنّ السطرَ **هو الأصل** والقيدُ احتياطٌ للقيود القديمة. فالتقاطُ مركزٍ
// لكلّ سطرٍ صحيحٌ ومقروء.
//
// ═══ ⚠️ وما أُسقط من التصميم ═══
//
// • **«ملاحظات»** — قرارُ المالك في الخطّة: تُسقَط. والبيانُ حقلٌ قائمٌ
//   يُحفَظ ويُعرَض في كلّ تقرير، وحقلٌ ثانٍ لا عمودَ له يبتلع ما يُكتَب فيه.
// • **«مستند مؤيد»** — مرفقاتٌ مؤجَّلةٌ بقرار مالكٍ مستقلّ (ح‑٤).
//
// ═══ ⚠️ والصلاحيّة `settings_view` للشاشة و`accounting_journal` للحفظ ═══
//
// وهو **عينُ** ما يحرس القيدَ اليدويَّ اليوم: شاشةُ اليومية على
// `settings_view`، و`saveManualEntry` تفحص `accounting_journal` عند الضغط.
// وربطُ الشاشة بـ`accounting_journal` كان يسحبها من كلّ دورٍ قائم — فالكودُ
// **ليس في `RoleGrantMatrix.defaultGrants` أصلاً**، ولا يملكه إلّا من مُنح
// يدويّاً أو مديرُ النظام بتجاوزه.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/permissions/permission_codes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/providers.dart';
import '../../domain/models/journal_balance.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../services/printing/report_pdf_generator.dart';
import '../picpos_shell/picpos_content_card.dart';
import '../picpos_shell/picpos_form_action_bar.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import '../picpos_shell/picpos_section_header.dart';
import '../picpos_shell/picpos_surface.dart';
import '../picpos_shell/picpos_totals_bar.dart';
import '../widgets/compact_date_picker.dart';
import 'journal_entries_picpos_widgets.dart';

final _voucherMoney =
    NumberFormat('#,##0.${'0' * AppConstants.decimalPlaces}');

final _dateFmt = DateFormat('dd-MM-yyyy');

/// رقمُ السند قبل الحفظ — **لا يُخمَّن**. راجع رأسَ الملفّ (‏Spec 066).
const String kJournalVoucherNumberPlaceholder = 'يُولَّد عند الحفظ';

/// أنواعُ القيد كما يقبلها `referenceType` في المحرّك.
const _entryTypes = <({String value, String label})>[
  (value: 'daily', label: 'يومية'),
  (value: 'adjustment', label: 'تسوية'),
  (value: 'salary', label: 'رواتب'),
];

class JournalVoucherPicposScreen extends ConsumerStatefulWidget {
  const JournalVoucherPicposScreen({super.key});

  @override
  ConsumerState<JournalVoucherPicposScreen> createState() =>
      _JournalVoucherPicposScreenState();
}

class _JournalVoucherPicposScreenState
    extends ConsumerState<JournalVoucherPicposScreen> {
  final _descCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  String _entryType = 'daily';
  int? _branchId;

  /// سطرُ القيد الواحد — **سطران على الأقلّ**: قيدٌ بسطرٍ واحدٍ لا يتّزن أبداً.
  final List<JournalLineInput> _lines = [
    JournalLineInput(),
    JournalLineInput(),
  ];

  bool _saving = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    _referenceCtrl.dispose();
    super.dispose();
  }

  JournalBalance get _balance => JournalBalance(
        debit: _lines.fold(0.0, (s, l) => s + l.debit),
        credit: _lines.fold(0.0, (s, l) => s + l.credit),
      );

  /// سببُ منعِ الحفظ — أو `null` إن جاز.
  ///
  /// ⚠️ **يُعرَض ولا يُبتلَع**: زرٌّ معطَّلٌ بلا سببٍ ظاهرٍ يُقرأ «معطوب»،
  /// فيُعاد الضغطُ عليه ويُبلَّغ عن عطبٍ لا وجودَ له.
  String? get blockReason {
    if (_descCtrl.text.trim().isEmpty) return 'اكتب بيان القيد.';
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      if (l.account == null) return 'السطر ${i + 1}: اختر الحساب.';
      if (l.debit <= 0 && l.credit <= 0) {
        return 'السطر ${i + 1}: أدخل مديناً أو دائناً.';
      }
      // 🔴 سطرٌ يحمل الطرفَين معاً يتّزن بنفسه ولا يعني شيئاً — وهو نفسُ
      //    حارس BUG-U13 في المسار القديم.
      if (l.debit > 0 && l.credit > 0) {
        return 'السطر ${i + 1}: مدينٌ ودائنٌ معاً في سطرٍ واحد.';
      }
    }
    if (!_balance.isPostable) {
      return 'القيد غير متوازن — الفرق ${_voucherMoney.format(_balance.difference)}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final reason = blockReason;
    final balance = _balance;
    final balanced = balance.isPostable;

    return PicPosScreenScaffold(
      title: 'سند قيد',
      // 🔴 لا رقمَ ولا شارةَ «مسودة» قبل أن يوجد مستند — راجع رأسَ الملفّ.
      subtitle: 'رقم السند: $kJournalVoucherNumberPlaceholder',
      icon: PhosphorIconsBold.notebook,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _infoCard(),
                  const SizedBox(height: 12),
                  _linesCard(),
                  const SizedBox(height: 12),
                  PicPosTotalsBar(items: [
                    PicPosTotal(
                      label: 'إجمالي المدين',
                      value: _voucherMoney.format(balance.debit),
                    ),
                    PicPosTotal(
                      label: 'إجمالي الدائن',
                      value: _voucherMoney.format(balance.credit),
                    ),
                    PicPosTotal(
                      label: 'الفرق',
                      // ⚠️ **بإشارته**: «٥٠» لا يقول أيَّ الطرفَين ناقص.
                      value: _voucherMoney.format(balance.difference),
                      tone: balanced ? AppColors.success : AppColors.error,
                    ),
                    PicPosTotal(
                      label: 'حالة القيد',
                      value: balanced ? 'متوازن' : 'غير متوازن',
                      emphasis: true,
                      tone: balanced ? AppColors.success : AppColors.error,
                    ),
                  ]),
                ],
              ),
            ),
          ),
          PicPosFormActionBar(
            onBack: _saving ? null : () => Navigator.maybePop(context),
            backLabel: 'إلغاء',
            busy: _saving,
            hint: reason ?? 'يتطلّب الترحيلُ تساويَ المدين والدائن',
            extras: [
              OutlinedButton.icon(
                onPressed: _saving ? null : _preview,
                icon: const Icon(PhosphorIconsBold.eye, size: 15),
                label: const Text('معاينة'),
              ),
            ],
            draft: PicPosFormAction(
              label: 'حفظ مسودة',
              icon: PhosphorIconsBold.floppyDisk,
              onPressed: (_saving || reason != null)
                  ? null
                  : () => _save(asDraft: true),
            ),
            primary: PicPosFormAction(
              label: 'مراجعة وترحيل',
              icon: PhosphorIconsBold.paperPlaneTilt,
              onPressed: (_saving || reason != null)
                  ? null
                  : () => _save(asDraft: false),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // معلومات القيد
  // ═══════════════════════════════════════════════════════════════════════

  Widget _infoCard() {
    final branches =
        ref.watch(allBranchesProvider).asData?.value ?? const <Branche>[];

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PicPosSectionHeader(
            icon: PhosphorIconsBold.info,
            title: 'معلومات القيد',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(width: 200, child: _dateField()),
              SizedBox(width: 200, child: _branchField(branches)),
              SizedBox(width: 180, child: _typeField()),
              SizedBox(width: 220, child: _referenceField()),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('journal_voucher_description'),
            controller: _descCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'البيان',
              hintText: 'مثال: إثبات مصروف إيجار',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateField() => InkWell(
        onTap: () async {
          final picked = await CompactDatePicker.showCompact(
            context,
            initialDate: _date,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 30)),
          );
          if (picked != null) setState(() => _date = picked);
        },
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'تاريخ القيد',
            isDense: true,
            border: OutlineInputBorder(),
            prefixIcon: Icon(PhosphorIconsBold.calendar, size: 15),
          ),
          child: Text(_dateFmt.format(_date)),
        ),
      );

  /// الفرعُ **يُختار هنا فعلاً** — خلافاً لحقل الفاتورة المقفول.
  ///
  /// ⚠️ والفرقُ ليس ذوقاً: `createSalesInvoice` تشتقّ الفرعَ من المخزن فلا
  /// معنى لمنتقٍ، و`createJournalEntry` **تقبل `branchId`** وتمرّره إلى
  /// حمولة المزامنة. و`null` يعني «يُحسَم عند الحفظ» — فالمستودع يشتقّ فرعَ
  /// الجهاز في وضع العميل، وتركُ الحقل فارغاً ليس إهمالاً.
  Widget _branchField(List<Branche> branches) =>
      DropdownButtonFormField<int?>(
        key: const Key('journal_voucher_branch'),
        initialValue: _branchId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'الفرع',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem<int?>(
            value: null,
            child: Text('فرع الجهاز'),
          ),
          for (final b in branches)
            DropdownMenuItem<int?>(value: b.id, child: Text(b.name)),
        ],
        onChanged: (v) => setState(() => _branchId = v),
      );

  Widget _typeField() => DropdownButtonFormField<String>(
        key: const Key('journal_voucher_type'),
        initialValue: _entryType,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'نوع القيد',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: [
          for (final t in _entryTypes)
            DropdownMenuItem(value: t.value, child: Text(t.label)),
        ],
        onChanged: (v) => setState(() => _entryType = v ?? 'daily'),
      );

  Widget _referenceField() => TextField(
        key: const Key('journal_voucher_reference'),
        controller: _referenceCtrl,
        decoration: const InputDecoration(
          labelText: 'المرجع',
          hintText: 'اختياري — رقم عقد أو إشعار',
          isDense: true,
          border: OutlineInputBorder(),
        ),
      );

  // ═══════════════════════════════════════════════════════════════════════
  // تفاصيل القيد
  // ═══════════════════════════════════════════════════════════════════════

  Widget _linesCard() {
    final repo = ref.read(accountingRepositoryProvider);
    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: PicPosSectionHeader(
                  icon: PhosphorIconsBold.listBullets,
                  title: 'تفاصيل القيد',
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _lines.add(JournalLineInput())),
                icon: const Icon(PhosphorIconsBold.plus, size: 14),
                label: const Text('إضافة سطر'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _lines.length; i++) _lineRow(repo, i),
        ],
      ),
    );
  }

  Widget _lineRow(IAccountingRepository repo, int i) {
    final line = _lines[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('سطر ${i + 1}',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700)),
              const Spacer(),
              // «نسخ السطر» — قيدُ الرواتب عشرةُ سطورٍ تختلف في رقمٍ واحد.
              IconButton(
                tooltip: 'نسخ السطر',
                onPressed: () => _duplicateLine(i),
                icon: const Icon(PhosphorIconsBold.copy, size: 14),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
              // ⚠️ **سطران لا ينقصان**: قيدٌ بسطرٍ واحدٍ لا يتّزن أبداً،
              //    وزرٌّ يحذف آخرَ سطرَين يترك نموذجاً لا يُحفَظ.
              IconButton(
                tooltip: _lines.length > 2 ? 'حذف السطر' : 'لا يقلّ القيد عن سطرين',
                onPressed: _lines.length > 2
                    ? () => setState(() => _lines.removeAt(i))
                    : null,
                icon: const Icon(PhosphorIconsBold.trash,
                    size: 14, color: AppColors.error),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 6),
          AccountAutocompleteField(
            repo: repo,
            selectedAccount: line.account,
            onSelected: (a) => setState(() => line.account = a),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: line.descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'البيان',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: CostCenterPicker(
                  repo: repo,
                  selectedId: line.costCenterId,
                  onChanged: (id) => setState(() => line.costCenterId = id),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: line.debitCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'مدين',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: line.creditCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'دائن',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ينسخ السطرَ بحسابه وبيانه ومركزه — **وبلا مبالغه**.
  ///
  /// 🔴 **والمبالغُ لا تُنسَخ عمداً.** نسخةٌ تحمل نفسَ المدين تُبقي القيدَ
  /// متوازناً بالمصادفة حين يُعدَّل أحدُهما وتُنسى الأخرى، وتضاعف مبلغاً
  /// ماليّاً بنقرةٍ واحدة. والغرضُ من النسخ تكرارُ **بنيةِ** السطر: قيدُ
  /// الرواتب عشرةُ سطورٍ بنفس الحساب ومركز التكلفة وبمبالغَ مختلفة.
  void _duplicateLine(int i) {
    final src = _lines[i];
    final copy = JournalLineInput()
      ..account = src.account
      ..costCenterId = src.costCenterId;
    copy.descCtrl.text = src.descCtrl.text;
    setState(() => _lines.insert(i + 1, copy));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // المعاينة والحفظ
  // ═══════════════════════════════════════════════════════════════════════

  /// ورقةُ معاينةٍ **بلا رقمِ مستند** — نفسُ قاعدة فاتورة المبيعات.
  ///
  /// 🔴 رقمُ القيد يُولَّد داخلَ معاملة الحفظ، وورقةٌ برقمٍ مخمَّنٍ تُقرأ
  /// مستنداً صدر. والخانةُ شرطةٌ والنوعُ يقول «غير محفوظ».
  Future<void> _preview() async {
    final reason = blockReason;
    if (reason != null) {
      AppToast.show(context, reason, type: ToastType.info);
      return;
    }
    await ReportPdfGenerator.printJournalEntry(
      entryNumber: '—',
      entryDate: _date,
      description: '${_descCtrl.text.trim()} — معاينة غير محفوظة',
      referenceType: _entryType,
      isAutoPosted: false,
      lines: [
        for (final l in _lines)
          {
            'account_code': l.account?.code ?? '',
            'account_name': l.account?.name ?? '',
            'description': l.descCtrl.text,
            'debit': l.debit,
            'credit': l.credit,
          },
      ],
    );
  }

  Future<void> _save({required bool asDraft}) async {
    if (blockReason != null) return;
    setState(() => _saving = true);
    try {
      // ⚠️ **الصلاحيةُ تُفحَص عند الضغط لا عند فتح الشاشة**: هو عينُ عقدِ
      //    `saveManualEntry` — الشاشةُ تُفتَح بـ`settings_view` والترحيلُ
      //    يحتاج `accounting_journal`.
      final userId = ref.read(authProvider).user?.id;
      if (userId == null) {
        _toast('يجب تسجيل الدخول لتنفيذ هذا الإجراء', ToastType.error);
        return;
      }
      final allowed = await ref
          .read(authRepositoryProvider)
          .userHasPermission(userId, PermissionCodes.accountingJournal);
      if (!allowed) {
        _toast('لا تملك صلاحية إنشاء قيود يومية', ToastType.error);
        return;
      }

      final repo = ref.read(accountingRepositoryProvider);
      await repo.createJournalEntry(
        description: _descCtrl.text.trim(),
        date: _date,
        lines: [
          for (final l in _lines)
            JournalLine(
              accountId: l.account!.id,
              debit: l.debit,
              credit: l.credit,
              description:
                  l.descCtrl.text.isNotEmpty ? l.descCtrl.text : null,
              costCenterId: l.costCenterId,
            ),
        ],
        referenceType: _entryType,
        branchId: _branchId,
        isAutoPosted: false,
        asDraft: asDraft,
        createdBy: userId,
        // 🔴 أوّلُ كاتبٍ للعمود منذ v174.
        reference: _referenceCtrl.text.trim().isEmpty
            ? null
            : _referenceCtrl.text.trim(),
      );

      if (!mounted) return;
      _toast(
        asDraft
            ? 'حُفظت المسودّة — لا تؤثّر على الأرصدة حتى تُعتمَد'
            : 'رُحِّل القيد',
        ToastType.success,
      );
      _resetForm();
    } catch (e) {
      _toast('خطأ: $e', ToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message, ToastType type) {
    if (!mounted) return;
    AppToast.show(context, message, type: type);
  }

  /// نموذجٌ نظيفٌ بعد الحفظ — **وإلّا رُحِّل القيدُ نفسُه مرّتين.**
  ///
  /// شاشةٌ تبقى ممتلئةً بعد الترحيل تُغري بضغطةٍ ثانيةٍ على «مراجعة وترحيل»،
  /// ولا شيءَ في المحرّك يمنع قيداً ثانياً مطابقاً — فهو قيدٌ مشروعٌ تماماً
  /// من وجهة نظره.
  void _resetForm() {
    setState(() {
      _descCtrl.clear();
      _referenceCtrl.clear();
      _lines
        ..clear()
        ..addAll([JournalLineInput(), JournalLineInput()]);
    });
  }
}

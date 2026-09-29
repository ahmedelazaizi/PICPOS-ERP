import 'package:ural_erp/core/i18n/tr.dart';
// شاشةُ «دفتر الشيكات» — تصميمُ المالك `(11)`: «حسابٌ بنكيّ · رقمُ الدفتر ·
// بادئة · من ← إلى · التالي · المتبقّي».
//
// ═══ 🔴 ولماذا جدولٌ أصلاً ═══
//
// تفرُّدُ الشيك **الصادر** في `commercial_papers_dao.dart` مبنيٌّ على
// `(paperNumber, type, bankName)` — أي على أنّه «من دفترنا» **بلا دفترٍ
// يضبطه**. فاليومَ: لا رقمَ تاليَ يُعرَف، ولا منعَ لقفزةٍ أو تكرار، ولا
// معرفةَ بما تبقّى. والمستخدمُ يكتب رقمَ الشيك بيده في سند الصرف.
//
// **ورقمٌ مكرَّرٌ في شيكٍ صادرٍ خطأٌ يصل البنك.** والحارسُ الوحيدُ اليومَ
// يعمل **بعد** الكتابة، ولا يعمل إطلاقاً إن اختلف اسمُ البنك حرفاً («مصر»
// مقابل «بنك مصر») — لأنّه يقارن `bankName` نصّاً حرّاً.
//
// ⇒ فالدفترُ يمنع التكرارَ **قبل وقوعه**: مدًى محجوزٌ على حسابٍ بنكيٍّ
//   بعينه، ورقمٌ يُسحَب آليّاً لا يُكتَب بيد.
//
// ═══ ⚠️ والبنكُ **خزنةٌ بنكيّةٌ لها حسابٌ مرتبط** ═══
//
// لا رايةَ «هذا حسابُ بنك» في دليل الحسابات، والطريقةُ المستقرّةُ في هذا
// المستودع هي خزنةُ `safeType == 'bank'` بـ`linkedAccountId` — وهي عينُ ما
// تفعله `bank_reconciliation_picpos_screen.dart`. فالمنتقي يعرضها، و
// `cheque_books.bank_account_id` يخزّن `linkedAccountId` (‏العمودُ يشير إلى
// `Accounts`).
//
// ⚠️ **والخزنةُ البنكيّةُ بلا حسابٍ مرتبطٍ تُقصى مع سطرِ شرحٍ يُقال** — لا
//    صمتٍ يجعلها تبدو مفقودةً من النظام.
//
// ═══ ⚠️ والرقمُ يُعايَن هنا ويُسحَب عند الحفظ ═══
//
// اللوحُ يعرض «التالي» ليعرف المستخدمُ أيَّ ورقةٍ يسحب من الدرج. لكنّ السحبَ
// الفعليَّ (`allocateChequeNumbers`) يقع في **معاملة سند الصرف** — كما
// يولَّد رقمُ المستند في مواصفة ٠٦٦. وسحبٌ عند العرض كان يحرق أرقاماً لم
// تُكتَب على ورقةٍ لو أُغلق النموذجُ، والدفترُ الورقيُّ لا يُعاد ترقيمُه.
//
// ═══ ⚠️ ولا زرَّ حذف ═══
//
// `commercial_papers.cheque_book_id` تشير إلى الدفتر، وحذفُه يُيتّم كلَّ
// شيكٍ صُرف منه. فالإلغاءُ حالةٌ (`cancelled`) تُوقف السحبَ وتُبقي التاريخ.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/cheque_book_plan.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_kpi_row.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../widgets/permission_guard.dart';

const _err = Color(0xFFEF4444);
const _warn = Color(0xFFF59E0B);
const _idle = Color(0xFF6B7280);

/// دفترٌ يوشك — العتبةُ عشرةُ شيكات.
///
/// ⚠️ **ورقمٌ مسمّى لا `10` مبعثرة**: العتبةُ تُقرأ في مؤشّرٍ وفي وسمِ صفٍّ
///    وفي اختبار، وثلاثةُ أرقامٍ تفترق عند أوّل تعديل.
const int kChequeBookLowThreshold = 10;

String _ar(Object n) =>
    '$n'.replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)]);

String chequeBookStatusLabel(String status) => switch (status) {
      'cancelled' => tr('ملغى'),
      'exhausted' => tr('انتهى'),
      _ => tr('نشط'),
    };

Color chequeBookStatusTint(String status) => switch (status) {
      'cancelled' => _idle,
      'exhausted' => _warn,
      _ => AppColors.success,
    };

/// خزنةٌ بنكيّةٌ صالحةٌ لفتح دفترٍ عليها — **قيمةٌ خالصة**.
typedef BankAccountOption = ({int accountId, String label});

/// 🔴 الترشيحُ حرفيٌّ لا اجتهاديّ: `bank` **و**نشطة **و**لها حسابٌ مرتبط.
///
/// والثلاثةُ معاً: خزنةٌ موقوفةٌ تُختار اليومَ ويُرفَض قيدُها غداً، وخزنةٌ
/// بلا حسابٍ مرتبطٍ لا حسابَ للدفتر أصلاً.
List<BankAccountOption> bankAccountOptions(List<SafeData> safes) {
  final out = <BankAccountOption>[];
  final seen = <int>{};
  for (final s in safes) {
    if (s.safeType != 'bank' || !s.isActive) continue;
    final acc = s.linkedAccountId;
    if (acc == null) continue;
    // حسابٌ واحدٌ قد تشير إليه خزنتان — والدفترُ على الحساب لا على الخزنة.
    if (!seen.add(acc)) continue;
    final bank = (s.bankName ?? '').trim();
    out.add((accountId: acc, label: bank.isEmpty ? s.name : '${s.name} · $bank'));
  }
  return out;
}

/// **عامٌّ عمداً**: سندُ الصرف يستهلكه ليعرض الدفاترَ السارية ويسحب منها —
/// ومزوّدان على نفس التدفّق يفترقان عند أوّل ترشيح.
final chequeBooksListProvider =
    StreamProvider.autoDispose<List<ChequeBookData>>(
        (ref) => ref.watch(chequeBooksRepositoryProvider).watchChequeBooks());

final _safesProvider = StreamProvider.autoDispose<List<SafeData>>(
    (ref) => ref.watch(treasuryRepositoryProvider).watchSafes());

class ChequeBooksPicposScreen extends ConsumerStatefulWidget {
  const ChequeBooksPicposScreen({super.key});

  @override
  ConsumerState<ChequeBooksPicposScreen> createState() =>
      _ChequeBooksPicposScreenState();
}

class _ChequeBooksPicposScreenState
    extends ConsumerState<ChequeBooksPicposScreen> {
  int? _panelId;
  bool _creating = false;

  void _closePanel() => setState(() {
        _panelId = null;
        _creating = false;
      });

  @override
  Widget build(BuildContext context) {
    final books =
        ref.watch(chequeBooksListProvider).value ?? const <ChequeBookData>[];
    final safes = ref.watch(_safesProvider).value ?? const <SafeData>[];
    final banks = bankAccountOptions(safes);
    final bankLabel = {for (final b in banks) b.accountId: b.label};

    final live = books.where((b) => b.status != 'cancelled');
    final remaining = live.fold<int>(
        0,
        (s, b) =>
            s + chequesRemaining(nextNumber: b.nextNumber, toNumber: b.toNumber));
    final low = live
        .where((b) =>
            b.status == 'active' &&
            chequesRemaining(nextNumber: b.nextNumber, toNumber: b.toNumber) <=
                kChequeBookLowThreshold)
        .length;

    return PermissionGuard(
      // ⚠️ `treasury_view` للعرض كما في سندَي القبض والصرف؛ والكتابةُ على
      //    `commercial_papers_manage` — وهي **ممنوحةٌ فعلاً** (مدير مالي،
      //    ومديرُ النظام يملك ما ليس «عمليّةً ماليّةً حرجة»). و
      //    `treasury_manage` غيرُ ممنوحةٍ لأيّ دورٍ فكانت ستُخفي الأزرار
      //    عن الجميع.
      permission: PermissionCodes.treasuryView,
      child: PicPosScreenScaffold(
        title: tr('دفتر الشيكات'),
        subtitle: tr('مدًى محجوزٌ على حسابٍ بنكيّ — ورقمٌ يُسحَب آليّاً لا يُكتَب بيد'),
        icon: PhosphorIconsBold.checkSquareOffset,
        headerActions: [
          PermissionGuard(
            permission: PermissionCodes.commercialPapersManage,
            child: FilledButton.icon(
              key: const Key('cheque_book_new'),
              onPressed: banks.isEmpty
                  ? null
                  : () => setState(() {
                        _panelId = null;
                        _creating = true;
                      }),
              icon: const Icon(PhosphorIconsBold.plus, size: 15),
              label:  Text(tr('دفتر جديد')),
            ),
          ),
        ],
        subHeader: PicPosKpiRow(
          kpis: [
            PicPosKpi(
              label: tr('دفاترُ سارية'),
              value: _ar(live.where((b) => b.status == 'active').length),
              icon: PhosphorIconsBold.books,
              tint: AppColors.primary,
            ),
            PicPosKpi(
              label: tr('شيكاتٌ متبقّية'),
              value: _ar(remaining),
              icon: PhosphorIconsBold.checkSquareOffset,
              tint: AppColors.info,
            ),
            PicPosKpi(
              label: tr('دفاترُ توشك'),
              value: _ar(low),
              icon: PhosphorIconsBold.warningCircle,
              tint: low == 0 ? AppColors.success : _warn,
            ),
            PicPosKpi(
              label: tr('انتهت أو أُلغيت'),
              value: _ar(books.where((b) => b.status != 'active').length),
              icon: PhosphorIconsBold.archive,
              tint: AppColors.textMuted,
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ⚠️ **يُقال ولا يُبتلَع**: بلا خزنةٍ بنكيّةٍ مربوطةٍ يبقى زرُّ
            //    «دفتر جديد» معطَّلاً بلا سبب — وزرٌّ معطَّلٌ بلا سببٍ ظاهرٍ
            //    يُقرأ «معطوب».
            if (banks.isEmpty)
               Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  tr('لا خزنةَ بنكيّةً نشطةً لها حسابٌ مرتبطٌ في دليل الحسابات — والدفتر يُفتَح على حسابٍ بنكيّ. اربط الخزنةَ من شاشة الخزينة أوّلاً.'),
                  key: const Key('cheque_book_no_bank_notice'),
                  style: const TextStyle(fontSize: 12, color: _err),
                ),
              ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: SingleChildScrollView(
                      child: _table(books, bankLabel),
                    ),
                  ),
                  if (_creating || _panelId != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SingleChildScrollView(
                        child: _panel(books, banks),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table(List<ChequeBookData> books, Map<int, String> bankLabel) {
    return PicPosDataTable(
      title: tr('الدفاتر'),
      subtitle: tr('المدى محجوزٌ على الحساب — ولا يتداخل دفتران عليه'),
      minWidth: 980,
      emptyLabel: tr('لا دفاترَ بعد — ورقمُ الشيك الصادر يُكتَب بيدٍ بلا ضابط'),
      columns:  [
        PicPosTableColumn(tr('الحساب البنكي'), flex: 1.7),
        PicPosTableColumn(tr('رقم الدفتر'), flex: 1.1),
        PicPosTableColumn(tr('المدى'), flex: 1.4),
        PicPosTableColumn(tr('التالي'), flex: 1.1),
        PicPosTableColumn(tr('المتبقّي'), align: PicPosCellAlign.end),
        PicPosTableColumn(tr('الحالة'), flex: 1.0),
      ],
      rows: [
        for (final b in books)
          PicPosTableRow(
            selected: _panelId == b.id,
            onTap: () => setState(() {
              _panelId = b.id;
              _creating = false;
            }),
            cells: [
              PicPosTextCell(
                bankLabel[b.bankAccountId] ?? tr('— حسابٌ غيرُ مربوطٍ بخزنة'),
                icon: PhosphorIconsBold.bank,
                tint: bankLabel.containsKey(b.bankAccountId) ? null : _err,
              ),
              PicPosTextCell(b.bookNumber,
                  sub: (b.prefix ?? '').isEmpty ? null : tr('بادئة {p0}', {'p0': b.prefix})),
              PicPosTextCell(
                '${formatChequeNumber(prefix: b.prefix, number: b.fromNumber, toNumber: b.toNumber)}'
                ' ← '
                '${formatChequeNumber(prefix: b.prefix, number: b.toNumber, toNumber: b.toNumber)}',
              ),
              PicPosTextCell(
                _nextLabel(b),
                tint: b.status == 'active' ? AppColors.primary : _idle,
              ),
              PicPosTextCell(_ar(
                  chequesRemaining(nextNumber: b.nextNumber, toNumber: b.toNumber))),
              PicPosPillCell(
                chequeBookStatusLabel(b.status),
                chequeBookStatusTint(b.status),
              ),
            ],
          ),
      ],
    );
  }

  /// «التالي» على دفترٍ لا يُسحَب منه **وعدٌ كاذب** — فيُقال بدله سببُه.
  String _nextLabel(ChequeBookData b) {
    if (b.status == 'cancelled') return tr('— ملغى');
    if (chequesRemaining(nextNumber: b.nextNumber, toNumber: b.toNumber) == 0) {
      return tr('— انتهى');
    }
    return formatChequeNumber(
        prefix: b.prefix, number: b.nextNumber, toNumber: b.toNumber);
  }

  Widget _panel(List<ChequeBookData> books, List<BankAccountOption> banks) {
    final current =
        _panelId == null ? null : books.where((b) => b.id == _panelId).firstOrNull;
    if (!_creating && current == null) return const SizedBox.shrink();

    return ChequeBookPanel(
      key: ValueKey('cheque_book_panel_${_creating ? 'new' : current!.id}'),
      value: current == null
          ? null
          : (
              id: current.id,
              bankAccountId: current.bankAccountId,
              bookNumber: current.bookNumber,
              prefix: current.prefix ?? '',
              fromNumber: current.fromNumber,
              toNumber: current.toNumber,
              nextNumber: current.nextNumber,
              status: current.status,
              notes: current.notes ?? '',
            ),
      banks: banks,
      others: [
        for (final b in books)
          (
            id: b.id,
            bankAccountId: b.bankAccountId,
            fromNumber: b.fromNumber,
            toNumber: b.toNumber,
            nextNumber: b.nextNumber,
            status: b.status,
          ),
      ],
      onClose: _closePanel,
      onSave: _save,
      onToggleCancelled: _toggleCancelled,
    );
  }

  Future<void> _save(ChequeBookSave v) async {
    final repo = ref.read(chequeBooksRepositoryProvider);
    try {
      if (v.id == null) {
        await repo.createChequeBook(
          bankAccountId: v.bankAccountId,
          bookNumber: v.bookNumber,
          fromNumber: v.fromNumber,
          toNumber: v.toNumber,
          prefix: v.prefix,
          nextNumber: v.nextNumber,
          notes: v.notes,
        );
        if (!mounted) return;
        AppToast.show(context, tr('تم فتح الدفتر'));
      } else {
        await repo.updateChequeBook(
          id: v.id!,
          bankAccountId: v.bankAccountId,
          bookNumber: v.bookNumber,
          fromNumber: v.fromNumber,
          toNumber: v.toNumber,
          nextNumber: v.nextNumber,
          prefix: v.prefix,
          notes: v.notes,
        );
        if (!mounted) return;
        AppToast.show(context, tr('تم حفظ التعديل'));
      }
      _closePanel();
    } catch (e) {
      // 🔴 **ورسالةُ المحرّك تُعرَض كما هي**: فحصُ التداخل يقع داخلَ
      //    المعاملة، وهي وحدَها تعرف أيَّ دفترٍ اصطدم به المدى.
      if (!mounted) return;
      AppToast.show(context, '$e', type: ToastType.error);
    }
  }

  Future<void> _toggleCancelled(int id, bool cancelled) async {
    try {
      await ref
          .read(chequeBooksRepositoryProvider)
          .setChequeBookCancelled(id, cancelled);
      if (!mounted) return;
      AppToast.show(context, cancelled ? tr('أُلغي الدفتر') : tr('أُعيد الدفتر'));
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '$e', type: ToastType.error);
    }
  }
}

/// قيمةُ لوحِ التحرير.
typedef ChequeBookValue = ({
  int id,
  int bankAccountId,
  String bookNumber,
  String prefix,
  int fromNumber,
  int toNumber,
  int nextNumber,
  String status,
  String notes,
});

typedef ChequeBookSave = ({
  int? id,
  int bankAccountId,
  String bookNumber,
  String prefix,
  int fromNumber,
  int toNumber,
  int nextNumber,
  String notes,
});

/// لوحُ الدفتر — إنشاءً وتعديلاً في مكانٍ واحد. مكشوفٌ للاختبار.
class ChequeBookPanel extends StatefulWidget {
  const ChequeBookPanel({
    super.key,
    required this.value,
    required this.banks,
    required this.others,
    required this.onClose,
    required this.onSave,
    required this.onToggleCancelled,
  });

  /// `null` ⇒ دفترٌ جديد.
  final ChequeBookValue? value;
  final List<BankAccountOption> banks;

  /// الدفاترُ القائمةُ كلُّها — لمعاينةِ التداخل **قبل** أن يردّه المحرّك.
  final List<ChequeBookRow> others;

  final VoidCallback onClose;
  final Future<void> Function(ChequeBookSave) onSave;
  final Future<void> Function(int id, bool cancelled) onToggleCancelled;

  @override
  State<ChequeBookPanel> createState() => _ChequeBookPanelState();
}

class _ChequeBookPanelState extends State<ChequeBookPanel> {
  late int? _bankAccountId =
      widget.value?.bankAccountId ?? widget.banks.firstOrNull?.accountId;
  late final _bookNumber =
      TextEditingController(text: widget.value?.bookNumber ?? '');
  late final _prefix = TextEditingController(text: widget.value?.prefix ?? '');
  late final _from =
      TextEditingController(text: '${widget.value?.fromNumber ?? ''}');
  late final _to = TextEditingController(text: '${widget.value?.toNumber ?? ''}');
  late final _next =
      TextEditingController(text: '${widget.value?.nextNumber ?? ''}');
  late final _notes = TextEditingController(text: widget.value?.notes ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _bookNumber.dispose();
    _prefix.dispose();
    _from.dispose();
    _to.dispose();
    _next.dispose();
    _notes.dispose();
    super.dispose();
  }

  int get _fromValue => int.tryParse(_from.text.trim()) ?? 0;
  int get _toValue => int.tryParse(_to.text.trim()) ?? 0;

  /// دفترٌ جديدٌ يبدأ من أوّله ما لم يُكتَب غيرُه.
  int get _nextValue {
    final typed = int.tryParse(_next.text.trim());
    if (typed != null) return typed;
    return _fromValue;
  }

  /// سببُ منعِ الحفظ — أو `null`.
  ///
  /// ⚠️ **معاينةٌ لا حكم**: الحكمُ النافذُ في `ChequeBooksDao` داخلَ
  ///    المعاملة، لأنّ جهازَين قد يفتحان دفترَين متداخلَين في نفس اللحظة
  ///    وكلاهما قرأ القائمةَ قبل كتابة الآخر.
  String? get blockReason {
    if (_bankAccountId == null) return tr('اختر الحساب البنكي.');
    if (_bookNumber.text.trim().isEmpty) return tr('اكتب رقم الدفتر.');
    if (_fromValue <= 0 || _toValue <= 0) {
      return tr('اكتب مدى الأرقام — من وإلى.');
    }
    final range = validateChequeBookRange(
      fromNumber: _fromValue,
      toNumber: _toValue,
      nextNumber: _nextValue,
    );
    if (range != null) return range;
    final clash = findChequeRangeOverlap(
      existing: widget.others,
      bankAccountId: _bankAccountId!,
      fromNumber: _fromValue,
      toNumber: _toValue,
      editingId: widget.value?.id,
    );
    if (clash != null) {
      return tr('المدى يتداخل مع دفترٍ قائمٍ على نفس الحساب ({p0} – {p1}) — ورقمٌ مكرَّرٌ في شيكٍ صادرٍ يصل البنك.', {'p0': clash.fromNumber, 'p1': clash.toNumber});
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.value == null;
    final reason = blockReason;
    final left =
        chequesRemaining(nextNumber: _nextValue, toNumber: _toValue);

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isNew ? tr('دفتر جديد') : tr('تعديل الدفتر'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: tr('إغلاق'),
                onPressed: widget.onClose,
                icon: const Icon(PhosphorIconsBold.x, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: const Key('cheque_book_bank'),
            initialValue: _bankAccountId,
            // ⚠️ **`isExpanded` إلزاميّ**: `DropdownButton` يبني صفّاً
            //    `mainAxisSize: min` بدونها، فاسمُ بنكٍ طويلٌ يفيض على
            //    اللوح — وهو عطبُ تخطيطٍ لا يظهر إلّا في عرضٍ بعينه.
            isExpanded: true,
            decoration:  InputDecoration(
              labelText: tr('الحساب البنكي'),
              helperText: tr('خزائنُ بنكيّةٌ نشطةٌ لها حسابٌ مرتبط وحدَها'),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final b in widget.banks)
                DropdownMenuItem(value: b.accountId, child: Text(b.label)),
            ],
            onChanged: (v) => setState(() => _bankAccountId = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  key: const Key('cheque_book_number'),
                  controller: _bookNumber,
                  onChanged: (_) => setState(() {}),
                  decoration:  InputDecoration(
                    labelText: tr('رقم الدفتر'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('cheque_book_prefix'),
                  controller: _prefix,
                  onChanged: (_) => setState(() {}),
                  decoration:  InputDecoration(
                    labelText: tr('بادئة'),
                    hintText: 'CHK-',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _numberField('cheque_book_from', _from, tr('من'))),
              const SizedBox(width: 8),
              Expanded(child: _numberField('cheque_book_to', _to, tr('إلى'))),
              const SizedBox(width: 8),
              Expanded(child: _numberField('cheque_book_next', _next, tr('التالي'))),
            ],
          ),
          const SizedBox(height: 6),
          // ⚠️ **ولماذا «التالي» محرَّرٌ أصلاً**: دفترٌ وصل والنظامُ لم يُفتَح
          //    إلّا بعد أن صُرفت منه أوراقٌ ورقيّاً — فبدايتُه الفعليّةُ ليست
          //    «من». وهو الطريقُ الوحيدُ لتصحيح ذلك بلا حذفٍ وإعادةِ فتح.
          Text(
            isNew
                ? tr('اترك «التالي» فارغاً ليبدأ من أوّل الدفتر — أو اكتبه إن كانت أوراقٌ منه قد صُرفت قبل تسجيله.')
                : tr('المتبقّي {p0} شيكاً.', {'p0': _ar(left)}),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('cheque_book_notes'),
            controller: _notes,
            maxLines: 2,
            decoration:  InputDecoration(
              labelText: tr('ملاحظات'),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          if (reason != null) ...[
            const SizedBox(height: 8),
            Text(reason,
                key: const Key('cheque_book_block_reason'),
                style: const TextStyle(fontSize: 11.5, color: _err)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PermissionGuard(
                  permission: PermissionCodes.commercialPapersManage,
                  child: FilledButton.icon(
                    key: const Key('cheque_book_save'),
                    onPressed: (_saving || reason != null) ? null : _submit,
                    icon: const Icon(PhosphorIconsBold.floppyDisk, size: 15),
                    label: Text(isNew ? tr('فتح الدفتر') : tr('حفظ التعديل')),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: widget.onClose,
                child:  Text(tr('إلغاء')),
              ),
            ],
          ),
          if (!isNew) ...[
            const SizedBox(height: 10),
            // ⚠️ **إلغاءٌ لا حذف** — راجع رأسَ الملفّ.
            PermissionGuard(
              permission: PermissionCodes.commercialPapersManage,
              child: OutlinedButton.icon(
                key: const Key('cheque_book_toggle_cancelled'),
                onPressed: _saving
                    ? null
                    : () => widget.onToggleCancelled(
                          widget.value!.id,
                          widget.value!.status != 'cancelled',
                        ),
                icon: Icon(
                  widget.value!.status == 'cancelled'
                      ? PhosphorIconsBold.arrowCounterClockwise
                      : PhosphorIconsBold.prohibit,
                  size: 15,
                ),
                label: Text(widget.value!.status == 'cancelled'
                    ? tr('إعادة الدفتر')
                    : tr('إلغاء الدفتر (ضاع أو سُحب من البنك)')),
              ),
            ),
            const SizedBox(height: 4),
             Text(
              tr('ولا حذفَ: الشيكات المصروفة منه تشير إليه، وحذفُه يُيتّمها.'),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _numberField(String key, TextEditingController c, String label) {
    return TextField(
      key: Key(key),
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await widget.onSave((
        id: widget.value?.id,
        bankAccountId: _bankAccountId!,
        bookNumber: _bookNumber.text.trim(),
        prefix: _prefix.text.trim(),
        fromNumber: _fromValue,
        toNumber: _toValue,
        nextNumber: _nextValue,
        notes: _notes.text.trim(),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

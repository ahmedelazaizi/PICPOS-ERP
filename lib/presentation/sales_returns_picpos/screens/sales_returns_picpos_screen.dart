import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/data/providers/financial_figures_providers.dart';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:ural_erp/core/utils/app_error_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/navigation/screen_id.dart';
import '../../../core/permissions/financial_figures_access.dart';
import '../../../core/theme/app_colors.dart';

import '../../../data/providers/providers.dart';
import '../../../services/invoice_generator.dart';

import '../../providers/sales_return_provider.dart';
import '../../../domain/entities/product_entity.dart';
import '../../widgets/permission_guard.dart'; // B5: Manager approval
// دفعة ٩ — حرّاس sales_return_delete و sales_return_print في ملف الـlogic.
import '../../../core/permissions/permission_codes.dart';
import '../../widgets/common/common.dart';

import '../../shared_widgets/open_shift_prompt.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_returns_panel.dart';
import '../../picpos_shell/picpos_return_form_kit.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../picpos_shell/picpos_totals_bar.dart';
import '../../../data/providers/manufacturing_providers.dart'
    show warehouseNameMapProvider;
import '../../../domain/models/picpos_return_view.dart';
import '../../../domain/models/sales_return_refund_split.dart';
import '../../../domain/models/return_draft.dart';
import '../../../data/providers/return_records_providers.dart';
import '../../shared_widgets/return_draft_support.dart';

// ── Part files (منسوخة حرفياً من lib/presentation/screens/sales_returns/ —
// الشاشة الأصل `part of _SalesReturnsScreenState` خاصة فما ينفعش تتعمل import،
// فبتنتقل بنسخ حرفي هنا؛ راجع تعليق مصيدة النسخ في رأس كل ملف). ──────────────
part 'sales_returns_picpos_logic.dart';
// الاستمارةُ المعاد تصميمُها (C2) — حلّت محلَّ لوح التفاصيل المنسوخ.
part 'sales_returns_picpos_form.dart';
// J2 — دورةُ المسوّدة، وأفعالُ صفوف السجلّ (طباعةٌ وإلغاء) بنفس المعالجات.
part 'sales_returns_picpos_drafts.dart';
part 'sales_returns_picpos_record_actions.dart';

/// شاشة مرتجع المبيعات بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). تعيد استخدام نفس `salesReturnProvider` (وتوابعه
/// `SalesReturnState`/`SalesReturnNotifier`) و`ThermalReceiptGenerator` و
/// `SyncPendingBanner` من UralCash — فقط طبقة العرض تبدّلت لـ `picpos_shell`.
///
/// القائمة (`_buildInvoiceList`) inline كما في الأصل، ولوحة التفاصيل تأتي من
/// mixin منسوخ (`buildReturnDetailsPanel`). الشكل العام «قائمة + تفاصيل»
/// (Row بعمودين) محفوظ من الأصل بلا تغيير، وكذلك كل الإجراءات: حوار «سجل
/// المرتجعات» (`showReturnsHistoryDialog`)، تدفّق تأكيد الإرجاع/الطباعة،
/// وضع الاستبدال، وضع الإتلاف، تصنيف سبب الإرجاع، والموافقة الإدارية على
/// المرتجعات عالية القيمة.
///
/// راجع lib/presentation/screens/sales_returns_screen.dart (الأصل).
///
/// ⚠️ **المرحلة C2 (البند ٣):** الشكلُ صار استمارةً واحدةً على تصميم المالك
/// (`sales_returns_picpos_form.dart`)، وقائمةُ الفواتير بترشيحها وعدّاداتها
/// انتقلت إلى منتقي «رقم الفاتورة الأصليّة». والإجراءاتُ أعلاه كما هي.
///
/// ⚠️ **J2 (قرارُ المالك):** المدخلُ الجانبيُّ صار سجلَّ المرتجعات
/// (`SalesReturnRecordsPicPosScreen`)، وهذه الاستمارةُ تُدفَع منه صفحةً:
/// «جديد» بلا مسوّدة، و«تعديل»/«اعتماد» بـ[draftId]. وفيها «حفظ مسودة».
class SalesReturnsPicposScreen extends ConsumerStatefulWidget {
  final SalesInvoiceData? initialInvoice;

  /// J2 — مسوّدةٌ محفوظةٌ تُفتَح للتعديل.
  final int? draftId;

  /// J2 — بعد فتح [draftId] يبدأ «مراجعة واعتماد» مباشرةً (فعلُ صفّ السجلّ).
  final bool approveOnOpen;

  /// J2 — بعد الاعتماد تُغلَق الصفحةُ عائدةً إلى السجلّ بالصفّ الجديد.
  final bool popOnDone;

  const SalesReturnsPicposScreen({
    super.key,
    this.initialInvoice,
    this.draftId,
    this.approveOnOpen = false,
    this.popOnDone = false,
  });

  @override
  ConsumerState<SalesReturnsPicposScreen> createState() =>
      _SalesReturnsPicposScreenState();
}

class _SalesReturnsPicposScreenState
    extends ConsumerState<SalesReturnsPicposScreen>
    with
        _SalesReturnsPicposLogic<SalesReturnsPicposScreen>,
        _SalesReturnsPicposForm,
        _SalesReturnsPicposDrafts {
  final _invoiceSearchController = TextEditingController();
  final _returnReasonController = TextEditingController();
  String _selectedReasonCategory = ''; // B4: Return reason categorization

  @override
  TextEditingController get returnReasonController => _returnReasonController;

  @override
  String get selectedReasonCategory => _selectedReasonCategory;

  @override
  set selectedReasonCategory(String value) => _selectedReasonCategory = value;

  @override
  void initState() {
    super.initState();
    if (widget.draftId != null) {
      Future.microtask(() async {
        await ref.read(salesReturnProvider.notifier).loadInvoices();
        await openDraftOnStart();
      });
    } else if (widget.initialInvoice != null) {
      Future.microtask(
        () => ref
            .read(salesReturnProvider.notifier)
            .selectInvoice(widget.initialInvoice!),
      );
    } else {
      Future.microtask(
        () => ref.read(salesReturnProvider.notifier).loadInvoices(),
      );
    }
  }

  @override
  void dispose() {
    _invoiceSearchController.dispose();
    _returnReasonController.dispose();
    super.dispose();
  }

  Future<void> _selectFromDate() async {
    final state = ref.read(salesReturnProvider);
    final date = await showDatePicker(
      context: context,
      initialDate: state.fromDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      ref.read(salesReturnProvider.notifier).setFromDate(date);
    }
  }

  Future<void> _selectToDate() async {
    final state = ref.read(salesReturnProvider);
    final date = await showDatePicker(
      context: context,
      initialDate: state.toDate,
      firstDate: state.fromDate,
      lastDate: DateTime.now(),
    );
    if (date != null) {
      ref.read(salesReturnProvider.notifier).setToDate(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(salesReturnProvider);
    final notifier = ref.read(salesReturnProvider.notifier);

    ref.listen(salesReturnProvider.select((s) => s.error), (previous, next) {
      if (next != null) {
        AppToast.show(context, next.toString(), type: ToastType.error);
        notifier.clearError();
      }
    });

    // J2 — هذه استمارةُ الإنشاء/التعديل تُدفَع من سجلّ المرتجعات، فلا زرَّ
    // «سجل المرتجعات» فيها ولا عنوانَ يقول «تسجيل ومتابعة» (عينُ التباس
    // توأم المشتريات في بلاغ 2026-09-22). والسجلُّ نفسُه بابُ الطباعة
    // والإلغاء بأفعال صفوفه.
    return PicPosScreenScaffold(
      title: _draftId != null
          ? tr('مسودة مرتجع مبيعات')
          : tr('مرتجع مبيعات جديد'),
      subtitle: tr('اختر فاتورةَ البيع ثمّ حدّد ما يُردُّ منها'),
      icon: PhosphorIconsBold.arrowUUpLeft,
      body: _buildBody(state, notifier),
    );
  }

  /// تحويلُ صفِّ الفاتورة إلى صورةِ العرض المحايدة.
  ///
  /// اسمُ العميل يأتي من `state.customerNames` المحمَّلةِ مسبقاً — لا استعلامَ
  /// لكلّ صفّ. وغيابُه يعني «عميل نقدي» كما كانت الشاشةُ تعرضه بالضبط.
  PicPosReturnInvoiceRow _toRow(SalesInvoiceData inv, SalesReturnState state) =>
      PicPosReturnInvoiceRow(
        id: inv.id,
        number: '# ${inv.invoiceNumber}',
        date: inv.invoiceDate,
        total: inv.total,
        status: PicPosReturnStatus.fromCode(inv.status),
        partyName: state.customerNames[inv.customerId] ?? tr('عميل نقدي'),
      );

  Widget _buildBody(SalesReturnState state, SalesReturnNotifier notifier) {
    // القائمةُ وعدّاداتُها (من فواتير المدى كلِّها) ترشيحُها بالبحث صارا
    // داخلَ منتقي الفاتورة الأصليّة — `_openInvoicePicker` في الاستمارة.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
         SyncPendingBanner(
          tableName: 'sales_returns',
          label: tr('مرتجع مبيعات'),
        ),
        Expanded(child: buildReturnForm(state, notifier)),
      ],
    );
  }

  /// شريطُ ترشيح القائمة — مدىً وبحث. يُبنى هنا لا في اللوح المشترك، لأن
  /// شاشةَ المشتريات ترشّح في SQL ولها منتقي مورّدٍ إضافيّ.
  ///
  /// [onSearchChanged] يعيد رسمَ حوار المنتقي: البحثُ هنا في الذاكرة، و
  /// `setState` الشاشة لا يصل الحوار.
  Widget _buildListFilters(
    SalesReturnState state, {
    VoidCallback? onSearchChanged,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _dateField(
                label: tr('من {p0}/{p1}', {'p0': state.fromDate.day, 'p1': state.fromDate.month}),
                onTap: _selectFromDate,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dateField(
                label: tr('إلى {p0}/{p1}', {'p0': state.toDate.day, 'p1': state.toDate.month}),
                onTap: _selectToDate,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: TextField(
            controller: _invoiceSearchController,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              hintText: tr('البحث برقم الفاتورة...'),
              hintStyle: TextStyle(
                fontSize: 12,
                color: picposReturnsMuted(context),
              ),
              prefixIcon: Icon(
                PhosphorIconsBold.magnifyingGlass,
                size: 14,
                color: picposReturnsMuted(context),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 34, minHeight: 34),
              filled: true,
              fillColor: Theme.of(context).scaffoldBackgroundColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) {
              setState(() {});
              onSearchChanged?.call();
            },
          ),
        ),
      ],
    );
  }

  Widget _dateField({required String label, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsBold.calendar,
                  size: 13, color: picposReturnsMuted(context)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

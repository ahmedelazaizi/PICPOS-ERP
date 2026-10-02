import 'package:ural_erp/core/i18n/tr.dart';
// ═══ ⚠️ والمرفقاتُ ليست هنا — بسببٍ بنيويٍّ لا تأجيل ═══
//
// بُنيت المرفقاتُ في v176 (§٨)، و`purchase_return` من الأنواع التسعة
// المُعرَّفة في `kAttachmentEntities`.
//
// 🔴 **لكنّ هذه الشاشةَ لا تعرض مردوداً — تُنشئه.** لوحُها يختار **فاتورةَ
// مشترياتٍ** ثمّ يُحدَّد منها ما يُردّ. فالمردودُ لا يوجد قبل الضغط على
// «تنفيذ الارتجاع»، ولا شاشةَ في المستودع تفتح مردوداً محفوظاً للمطالعة.
//
// ⚠️ **وإرفاقُ ورقةٍ بالفاتورة الأصل ليس بديلاً**: إشعارُ الخصم ورقةُ
// **المردود** لا ورقةُ الفاتورة، ووضعُها على الأمّ يخلط مستندَين في
// ملفٍّ واحد. ويومَ تُبنى شاشةُ عرضٍ للمردود، التركيبُ سطران.

import 'package:flutter/material.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/permissions/permission_codes.dart';

import '../../../data/providers/providers.dart';
import '../../../domain/repositories/purchases_repository.dart' show PurchaseReturnItem;
import '../../../services/invoice_generator.dart';

import '../../providers/purchase_return_provider.dart';
import '../../shared_widgets/purchase_return_save.dart';
import '../../widgets/permission_guard.dart'; // B5: Manager approval
import '../../widgets/common/common.dart';

import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_return_form_kit.dart';
import '../../picpos_shell/picpos_totals_bar.dart';
import '../../picpos_shell/picpos_returns_panel.dart';
import '../../../data/providers/manufacturing_providers.dart'
    show warehouseNameMapProvider;
import '../../../domain/models/picpos_return_view.dart';

// ── Part files (منسوخة حرفياً من lib/presentation/screens/purchase_returns/ —
// الشاشة الأصل `part of` خاص فما ينفعش تتعمل import، فبتنتقل بنسخ حرفي هنا؛
// راجع تعليق مصيدة النسخ في رأس كل ملف). ──────────────────────────────────
part 'purchase_returns_picpos_logic.dart';
// الاستمارةُ المعاد تصميمُها (C2) — حلّت محلَّ لوح التفاصيل المنسوخ.
part 'purchase_returns_picpos_form.dart';

/// شاشة مرتجع المشتريات بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). تعيد استخدام نفس `purchaseReturnProvider` (وتوابعه
/// `PurchaseReturnState`/`PurchaseReturnNotifier`) و`InvoiceGenerator` و
/// `SyncPendingBanner` من UralCash — فقط طبقة العرض تبدّلت لـ `picpos_shell`.
///
/// الفلاتر (`_buildSupplierFilter`/`_buildProductFilter`) والقائمة
/// (`_buildInvoiceList`) inline كما في الأصل، ولوحة التفاصيل تأتي من mixin
/// منسوخ (`buildReturnDetailsPanel`). الشكل العام «قائمة + تفاصيل» (Row
/// بعمودين) محفوظ من الأصل بلا تغيير، وكذلك كل الإجراءات: حوار «سجل
/// المرتجعات» (`showReturnsHistoryDialog`)، تدفّق تأكيد الإرجاع/الطباعة A4،
/// تصنيف سبب الإرجاع (B4)، الموافقة الإدارية على المرتجعات عالية القيمة (B5)،
/// وتعديل مرتجع مُرحّل (Feature 015، محكوم بصلاحية `purchases_return_edit`).
///
/// راجع lib/presentation/screens/purchase_returns_screen.dart (الأصل).
///
/// ⚠️ **المرحلة C2 (البند ٣):** الشكلُ صار استمارةً واحدةً على تصميم المالك
/// (`purchase_returns_picpos_form.dart`)، وقائمةُ الفواتير بفلاترها
/// وعدّاداتها انتقلت إلى منتقي «رقم الفاتورة الأصليّة». والإجراءاتُ أعلاه
/// كما هي.
class PurchaseReturnsPicposScreen extends ConsumerStatefulWidget {
  const PurchaseReturnsPicposScreen({super.key});

  @override
  ConsumerState<PurchaseReturnsPicposScreen> createState() =>
      _PurchaseReturnsPicposScreenState();
}

class _PurchaseReturnsPicposScreenState
    extends ConsumerState<PurchaseReturnsPicposScreen>
    with _PurchaseReturnsPicposLogic, _PurchaseReturnsPicposForm {
  final _searchController = TextEditingController();
  // حقلا السبب المحلّيّان حُذفا: السببُ يعيش في `PurchaseReturnState`
  // ويصل صفَّ المستند. حالةٌ محلّيّةٌ لا تغادر الودجت هي ما جعل
  // `PurchaseReturns.reason` عموداً بلا كاتب.

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(purchaseReturnProvider.notifier).loadInvoices(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _selectFromDate() async {
    final state = ref.read(purchaseReturnProvider);
    final date = await showDatePicker(
      context: context,
      initialDate: state.fromDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      ref.read(purchaseReturnProvider.notifier).setFromDate(date);
    }
  }

  Future<void> _selectToDate() async {
    final state = ref.read(purchaseReturnProvider);
    final date = await showDatePicker(
      context: context,
      initialDate: state.toDate,
      firstDate: state.fromDate,
      lastDate: DateTime.now(),
    );
    if (date != null) {
      ref.read(purchaseReturnProvider.notifier).setToDate(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(purchaseReturnProvider);
    final notifier = ref.read(purchaseReturnProvider.notifier);

    // أخطاءُ التحميل واختيار الفاتورة كانت تُكتب في `error` ولا يقرؤها أحد —
    // نظيرُ مستمع توأم المبيعات. وخطأُ الحفظ يعرضه حوارُه (`_savingReturn`).
    ref.listen(purchaseReturnProvider.select((s) => s.error), (_, next) {
      if (next == null || _savingReturn) return;
      AppToast.show(context, next, type: ToastType.error);
      notifier.clearError();
    });

    // ═══ 🔴 بلاغٌ ميدانيٌّ 2026-09-22 ═══
    //
    // «زرُّ جديد… بيفتح شاشة مرتجع المشتريات السابقة». وهو صحيح: بعد خ‑٩
    // صار المدخلُ الجانبيُّ **سجلَّ** المردودات، وهذه الشاشةُ تُدفَع منه
    // بزرّ «جديد» — فكانت تحمل **نفسَ العنوان** وسطراً يقول «تسجيل
    // ومتابعة» وزرّاً اسمُه «سجل المرتجعات». ثلاثُ إشاراتٍ تقول «هذا سجلٌّ
    // ثانٍ» بينما هي استمارةُ الإنشاء.
    //
    // ⚠️ **والعلاجُ تسميةٌ لا حذف** (خ‑٩٫٧: لا يُمَسُّ منطقُ استمارةٍ قائمة).
    //    وزرُّ السجلّ **لا يُسحَب**: حوارُه يحمل ثلاثةَ مساراتٍ حيّةٍ لا
    //    يوجد لها بابٌ آخر — إعادةُ الطباعة (`purchases_return_print`) وعرضُ
    //    الأصناف المرتجعة و**تعديلُ مرتجعٍ مُرحَّل** (ميزة ٠١٥،
    //    `purchases_return_edit`). فسحبُه يُسقطها، وإبقاؤه باسمه القديم
    //    يُبقي الالتباس. فسُمّي بما يفعله.
    return PicPosScreenScaffold(
      title: tr('مرتجع مشتريات جديد'),
      subtitle: tr('اختر فاتورةَ الشراء ثمّ حدّد ما يُردُّ منها'),
      icon: PhosphorIconsBold.arrowUUpLeft,
      headerActions: [
        OutlinedButton.icon(
          onPressed: showReturnsHistoryDialog,
          icon: const Icon(PhosphorIconsBold.printer, size: 16),
          label:  Text(tr('طباعة أو تعديل مرتجعٍ سابق')),
        ),
      ],
      body: _buildBody(state, notifier),
    );
  }

  /// تحويلُ صفِّ فاتورة المشتريات إلى صورةِ العرض المحايدة.
  ///
  /// ⚠️ **بلا اسمِ مورّد**: `PurchaseReturnState` لا تحمل خريطةَ أسماءٍ نظيرةً
  /// لـ`customerNames` في المبيعات، والشاشةُ اليوم تعرض التاريخَ وحدَه.
  /// فاشتقاقُ الاسم كان سيعني استعلاماً لكلّ صفّ (N+1) أو اختلاقاً — وكلاهما
  /// أسوأُ من سطرٍ أقصر. يُرفَع حين تحمل الحالةُ الأسماءَ كما في التوأم.
  PicPosReturnInvoiceRow _toRow(PurchaseInvoiceData inv) =>
      PicPosReturnInvoiceRow(
        id: inv.id,
        number: '# ${inv.invoiceNumber}',
        date: inv.invoiceDate,
        total: inv.total,
        status: PicPosReturnStatus.fromCode(inv.status),
      );

  Widget _buildBody(
    PurchaseReturnState state,
    PurchaseReturnNotifier notifier,
  ) {
    // ‏لا ترشيحَ في الذاكرة: كلُّ الفلاتر (المدى · الرقم · المورد · الصنف)
    // نُفِّذت في SQL، فما يصل منتقي الفاتورة الأصليّة (`_openInvoicePicker`
    // في الاستمارة) هو النتيجةُ الكاملةُ لا شريحةٌ مبتورةٌ منها. فالعدّاداتُ
    // والقائمةُ هناك يقرآن نفسَ القائمة — بخلاف توأم المبيعات الذي يرشّح
    // بالبحث في الذاكرة فيفترقان.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
         SyncPendingBanner(
          tableName: 'purchase_returns',
          label: tr('مرتجع مشتريات'),
        ),
        Expanded(child: buildReturnForm(state, notifier)),
      ],
    );
  }

  /// شريطُ ترشيح القائمة — مدىً وبحثٌ ومنتقيا المورد والصنف.
  ///
  /// [r] مرجعُ الحوار الذي يُرسَم فيه الشريط: `ref.watch` الشاشة لا يصلح
  /// خارجَ بنائها.
  Widget _buildListFilters(PurchaseReturnState state, WidgetRef r) {
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
        // البحثُ يذهب إلى SQL — سابقاً كان `contains()` في الذاكرة فوق أحدث
        // ‏٥٠٠ فاتورة، فيفشل صامتاً على أيّ فاتورةٍ أقدم.
        SizedBox(
          height: 36,
          child: TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              hintText: tr('البحث برقم الفاتورة (رقمنا أو رقم المورد)...'),
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
            onChanged: (v) =>
                ref.read(purchaseReturnProvider.notifier).setInvoiceQuery(v),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildSupplierFilter(state.supplierId)),
            const SizedBox(width: 8),
            Expanded(child: _buildProductFilter(state.productId, r)),
          ],
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

  /// البند 7 — فلتر المورد. القائمة تُبنى من الموردين المعرَّفين فعلاً، عبر
  /// نفس المسار الذي تستعمله شاشة فاتورة المشتريات (`getSuppliers`) بدل
  /// استحداث مزوّد جديد.
  Widget _buildSupplierFilter(int? selected) {
    return FutureBuilder(
      future: ref.read(productRepositoryProvider).getSuppliers(),
      builder: (context, snapshot) {
        final suppliers = snapshot.data ?? const [];
        return DropdownButtonFormField<int?>(
          initialValue: selected,
          isExpanded: true,
          isDense: true,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: tr('المورد'),
            prefixIcon: const Icon(PhosphorIconsBold.truck, size: 16),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: [
             DropdownMenuItem<int?>(
              value: null,
              child: Text(tr('كل الموردين'), style: const TextStyle(fontSize: 13)),
            ),
            for (final s in suppliers)
              DropdownMenuItem<int?>(
                value: s.id,
                child: Text(s.name,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) =>
              ref.read(purchaseReturnProvider.notifier).setSupplierFilter(v),
        );
      },
    );
  }

  /// البند 7 — فلتر الصنف: «الصنف الموجود في جميع الفواتير».
  Widget _buildProductFilter(int? selected, WidgetRef r) {
    final productsAsync = r.watch(allProductsProvider);
    return productsAsync.when(
      loading: () => const SizedBox(height: 40),
      error: (_, _) => const SizedBox(height: 40),
      data: (products) => DropdownButtonFormField<int?>(
        initialValue: selected,
        isExpanded: true,
        isDense: true,
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: tr('الصنف'),
          prefixIcon: const Icon(PhosphorIconsBold.package, size: 16),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        items: [
           DropdownMenuItem<int?>(
            value: null,
            child: Text(tr('كل الأصناف'), style: const TextStyle(fontSize: 13)),
          ),
          for (final p in products)
            DropdownMenuItem<int?>(
              value: p.id,
              child: Text(p.name,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) =>
            ref.read(purchaseReturnProvider.notifier).setProductFilter(v),
      ),
    );
  }

  // ignore: unused_element
  double _calculateReturnTotal() {
    final state = ref.read(purchaseReturnProvider);
    if (state.invoiceItems.isEmpty) return 0;
    double total = 0;
    for (final item in state.invoiceItems) {
      final qty = state.returnQuantities[item.item.id] ?? 0;
      total += qty * item.item.unitCost;
    }
    return total;
  }
}

import 'package:ural_erp/core/i18n/tr.dart';
// ═══════════════════════════════════════════════════════════════════════════
// PICPOS — لوحة المجاميع والدفع
// ═══════════════════════════════════════════════════════════════════════════
//
// نسخة مستقلة عن `cart/cart_totals_panel.dart` و`cart/cart_payment_selector.dart`
// بتاعت UralCash، بقرار صريح من صاحب المشروع: «استنسخه من ural واشتغل عليه
// لشغل picpos».
//
// ── ليه نسخة وليس إعادة استخدام؟ ──────────────────────────────────────────
// `CartTotalsPanel` مش مكوّن مستقل: بياخد `buildTaxToggle` و`buildDiscountButton`
// **كدوال بناء** من جوّه `cart_view.dart`، فاستخدامه من برّه معناه تفكيك
// `cart_view.dart` — أخطر ملف في شاشة UralCash، ومفيش اختبارات widget تغطيه.
//
// ── إيه اللي **مش** منسوخ ─────────────────────────────────────────────────
// المنطق. كل قرار مالي هنا بيروح لنفس الكائنات: `cart_controller` للطرق
// والصناديق والخصم والضريبة، و`checkout_controller` للترحيل، و`PaymentSheet`
// للدفع المتعدد. الملف ده تخطيط وشكل وقراءة إعدادات — مفيش حساب فلوس فيه.
//
// ── إعدادات البيع السريع ────────────────────────────────────────────────────
// اللوحة بتحترم إعدادات الإظهار والمقاسات اللي في «إعدادات البيع السريع»:
//   الأزرار:  ضريبة · خصم · درج · مصاريف · حفظ-فقط · إجمالي فرعي
//   العميل:   إضافة عميل · عميل عابر · نوع الطلب
//   المقاسات: posBottomPanelScale · posButtonHeight · posButtonFontSize ·
//             paymentButtonHeight
// كل واحد بياخد نفس الافتراضي اللي شاشة UralCash بتاخده، فتركيب بينقل بين
// المنتجين مش بيلاقي سلوك مختلف من غير ما يغيّر إعداد.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import '../../pos/providers/cart_controller.dart';
import '../providers/pos_exchange_mode_provider.dart';
import '../providers/pos_return_mode_provider.dart';
import 'picpos_cart_permissions.dart';
import 'picpos_pos_text.dart';

/// `--field` من التصميم تابعاً للوضع.
///
/// ⚠️ القيمةُ الفاتحةُ **هي هي** (`#F4F7FC`) لا `AppColors.surface`: اللوحةُ
/// رُسمت على رمز التصميم، و`context.picposField` تعطي `#F8FAFC` — فرقٌ لا
/// يُرى لكنّه يبدّل الفاتحَ، والعقدُ أن يبقى الفاتحُ كما هو بايتاً ببايت.
///
/// وكان الخمسةُ مكتوبين بالرقم مباشرةً، فبقيت أرضيّاتُ اللوحة بيضاءَ في
/// الوضع الغامق — أحدُ مواضعِ بلاغ المالك 2026-08-24 عن «البيع السريع».
Color _fieldOf(BuildContext context) => context.picposIsDark
    ? const Color(0xFF18243A)
    : const Color(0xFFF4F7FC);

class PicPosPaymentPanel extends ConsumerWidget {
  final VoidCallback onCheckout;
  final VoidCallback onSave;

  /// «الفاتورة السابقة» — خد خانة زرار «طباعة F3» القديم (طلبين ١ و ٩):
  /// الطباعة بقت جوه `دفع`، فالخانة اتفرّغت لعرض/إعادة طباعة آخر فاتورة.
  final VoidCallback onLastInvoice;
  final VoidCallback onEditDiscount;
  final VoidCallback onPickCustomer;
  final VoidCallback onPreviousInvoices;
  final VoidCallback onOpenDrawer;
  final VoidCallback onExpense;
  final VoidCallback onHold;
  final VoidCallback onHeldOrders;

  /// «مرتجع سريع» — يفتح مُحدِّدَ فاتورةٍ ثم يضبط `posReturnModeProvider`
  /// (المهمّة ٧). القرارُ عيشُ السلكِ في الشاشة لا هنا: هذه اللوحةُ لا تعرف
  /// شيئاً عن `PosReturnMode` أو المستودعات — نفسُ نمط بقيّة أزرار اللوحة.
  final VoidCallback onQuickReturn;

  /// «استبدال» — يفتح نفسَ مُحدِّد الفاتورة ثم يضبط `posExchangeModeProvider`.
  /// وبخلاف المرتجع، السلّةُ تبقى مفتوحةً للتعديل: هي سلّةُ البديل.
  final VoidCallback onExchange;

  const PicPosPaymentPanel({
    super.key,
    required this.onCheckout,
    required this.onSave,
    required this.onLastInvoice,
    required this.onEditDiscount,
    required this.onPickCustomer,
    required this.onPreviousInvoices,
    required this.onOpenDrawer,
    required this.onExpense,
    required this.onHold,
    required this.onHeldOrders,
    required this.onQuickReturn,
    required this.onExchange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    final controller = ref.read(cartControllerProvider.notifier);
    final totals = cart.totals;

    // المفاتيح هي نفس مفاتيح UralCash. الافتراضيات لما الإعداد مش مضبوط
    // **أصغر** عن قصد: عمود الفاتورة هنا ضيّق (٤٠٪) مش نص الشاشة زي سلة
    // UralCash، وأول تنفيذ بافتراضيات UralCash خلّى اللوحة تاكل العمود
    // والجدول ينسحق لصفر — بلاغ ميداني: «الأزرار ضخمة ومغطية على السلة».
    // أي قيمة مضبوطة في الإعدادات بتكسب على الافتراضي ده.
    final scale = ref.watch(posBottomPanelScaleProvider).value ?? 1.0;
    final btnHeight = ref.watch(posButtonHeightProvider).value ?? 32.0;
    final btnFont = ref.watch(posButtonFontSizeProvider).value ?? 12.0;

    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: EdgeInsets.all(7 * scale),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // العميل ونوع الطلب على صف واحد — كانوا صفّين وكل واحد بارتفاع
          // كامل، وهما أقل حاجة الكاشير بيلمسها في اللوحة.
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _CustomerRow(
                    onPickCustomer: onPickCustomer, scale: scale),
              ),
              _OrderTypeRow(cart: cart, controller: controller, scale: scale),
            ],
          ),
          _TotalsBlock(
            cart: cart,
            controller: controller,
            totals: totals,
            scale: scale,
            onEditDiscount: onEditDiscount,
          ),
          SizedBox(height: 5 * scale),
          _SafeChipRow(cart: cart, scale: scale),
          SizedBox(height: 5 * scale),
          _ActionButtons(
            scale: scale,
            btnHeight: btnHeight,
            btnFont: btnFont,
            onCheckout: onCheckout,
            onSave: onSave,
            onLastInvoice: onLastInvoice,
            onPreviousInvoices: onPreviousInvoices,
            onOpenDrawer: onOpenDrawer,
            onExpense: onExpense,
            onHold: onHold,
            onHeldOrders: onHeldOrders,
            onQuickReturn: onQuickReturn,
            onExchange: onExchange,
          ),
        ],
      ),
    );
  }
}

// ── العميل ─────────────────────────────────────────────────────────────────

class _CustomerRow extends ConsumerWidget {
  final VoidCallback onPickCustomer;
  final double scale;

  const _CustomerRow({required this.onPickCustomer, required this.scale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(showAddCustomerInPOSProvider).value ?? true)) {
      return const SizedBox.shrink();
    }
    final cart = ref.watch(cartControllerProvider);
    final name = cart.selectedCustomerName ?? cart.adhocCustomerName;
    final isSet = name != null && name.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: 8 * scale),
      child: InkWell(
        onTap: onPickCustomer,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9 * scale),
          decoration: BoxDecoration(
            color: isSet
                ? AppColors.primary.withValues(alpha: 0.07)
                : _fieldOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSet ? AppColors.primary : context.picposHairline,
            ),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsBold.user,
                  size: 15, color: isSet ? AppColors.primary : AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSet ? name : tr('عميل نقدي — اضغط للاختيار'),
                  overflow: TextOverflow.ellipsis,
                  style: isSet
                      ? PicPosText.v(context, 13 * scale, color: AppColors.primary)
                      : PicPosText.l(context, 13 * scale),
                ),
              ),
              const Icon(PhosphorIconsBold.caretLeft,
                  size: 13, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ── نوع الطلب ──────────────────────────────────────────────────────────────

class _OrderTypeRow extends ConsumerWidget {
  final CartState cart;
  final CartController controller;
  final double scale;

  const _OrderTypeRow({
    required this.cart,
    required this.controller,
    required this.scale,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(showOrderTypeInPOSProvider).value ?? true)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * scale),
      child: Row(
        children: [
          Expanded(
            child: _TypeChip(
              label: tr('داخلي'),
              icon: PhosphorIconsBold.storefront,
              selected: cart.orderType == 'internal',
              onTap: () => controller.setOrderType('internal'),
              scale: scale,
            ),
          ),
          SizedBox(width: 6 * scale),
          Expanded(
            child: _TypeChip(
              label: tr('توصيل'),
              icon: PhosphorIconsBold.moped,
              selected: cart.orderType == 'delivery',
              // ── `pos_delivery` — قرارُ المالك 2026-08-13 ─────────────────
              // هذه الشريحةُ **هي** ميزةُ التوصيل في PicPos. وكانت الكودُ
              // محروساً في `pos/widgets/pos_header.dart:247` وحدَه (زرُّ لوح
              // طلبات التوصيل) — شاشةُ UralCash التي لا تبلغها PicPos.
              // وأخفاه الحارسُ البنيويُّ لأن `FeatureKey.posDelivery` في
              // `core/config/feature_key.dart` يحمل نفسَ الاسم — تعدادُ
              // رايات، لا حراسة.
              //
              // ⚠️ و«داخلي» بلا حراسةٍ عن قصد: الرجوعُ للوضع الافتراضيّ
              // ليس فعلاً يُراقَب، وحراستُه كانت ستحبس الكاشيرَ في «توصيل»
              // بعد لمسةٍ خاطئة.
              onTap: () async {
                if (!await ensureDeliveryPermission(ref, context)) return;
                controller.setOrderType('delivery');
              },
              scale: scale,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final double scale;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 7 * scale),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : _fieldOf(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : context.picposHairline,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 14,
                color: selected ? Colors.white : PicPosText.labelOf(context)),
            const SizedBox(width: 5),
            Text(
              label,
              style: selected
                  ? PicPosText.v(context, 12 * scale, color: Colors.white)
                  : PicPosText.l(context, 12 * scale),
            ),
          ],
        ),
      ),
    );
  }
}

// ── المجاميع ───────────────────────────────────────────────────────────────

class _TotalsBlock extends ConsumerWidget {
  final CartState cart;
  final CartController controller;
  final InvoiceTotals totals;
  final double scale;
  final VoidCallback onEditDiscount;

  const _TotalsBlock({
    required this.cart,
    required this.controller,
    required this.totals,
    required this.scale,
    required this.onEditDiscount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showSubtotal = ref.watch(showSubtotalInPOSProvider).value ?? true;
    final showTax = ref.watch(showTaxButtonInPOSProvider).value ?? true;
    final showDiscount =
        ref.watch(showDiscountButtonInPOSProvider).value ?? true;

    return Column(
      children: [
        if (showTax || showDiscount)
          Padding(
            padding: EdgeInsets.only(bottom: 8 * scale),
            child: Row(
              children: [
                if (showTax)
                  Expanded(
                    child: _ToggleTile(
                      label: tr('ضريبة'),
                      icon: PhosphorIconsBold.receipt,
                      active: cart.taxEnabled,
                      // نفس الاستدعاء اللي شاشة UralCash بتعمله — الحساب كله
                      // جوّه `CartState.totals`، مفيش نسبة محسوبة هنا.
                      //
                      // ومحروسٌ بـ`pos_tax_toggle`: يغيّر ما يدفعه العميلُ وما
                      // يُرحَّل ضريبةً في الدفاتر. كان محروساً في
                      // `pos/widgets/cart/cart_totals_panel.dart` وحدَه —
                      // وهي شاشةٌ لا يصل إليها PicPos.
                      onTap: () async {
                        if (!await ensureTaxTogglePermission(ref, context)) {
                          return;
                        }
                        controller.toggleTax(!cart.taxEnabled);
                      },
                      scale: scale,
                    ),
                  ),
                if (showTax && showDiscount) SizedBox(width: 6 * scale),
                if (showDiscount)
                  Expanded(
                    child: _ToggleTile(
                      label: cart.discountPercent > 0
                          ? tr('خصم {p0}', {'p0': NumberUtils.formatPercent(cart.discountPercent)})
                          : tr('خصم'),
                      icon: PhosphorIconsBold.percent,
                      active: cart.discountPercent > 0,
                      onTap: onEditDiscount,
                      scale: scale,
                    ),
                  ),
              ],
            ),
          ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8 * scale),
          decoration: BoxDecoration(
            color: _fieldOf(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              if (showSubtotal)
                _Line(
                  label: tr('المجموع الفرعي'),
                  value: totals.subtotal,
                  scale: scale,
                ),
              if (totals.totalDiscount > 0)
                _Line(
                  label: tr('الخصم'),
                  value: totals.totalDiscount,
                  scale: scale,
                  color: AppColors.error,
                  negative: true,
                ),
              if (showTax && cart.taxEnabled)
                _Line(
                  label: tr('ضريبة القيمة المضافة'),
                  value: totals.taxAmount,
                  scale: scale,
                ),
              if (cart.deliveryFee > 0)
                _Line(
                  label: tr('رسوم التوصيل'),
                  value: cart.deliveryFee,
                  scale: scale,
                ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 5 * scale),
                child: const Divider(height: 1),
              ),
              Row(
                children: [
                  Text(
                    tr('الإجمالي النهائي'),
                    style: PicPosText.l(context, 
                      13 * scale,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    NumberUtils.formatCurrency(cart.total),
                    // اللون دلالي (أحمر لو سالب) فبيغلب أسود القيم.
                    style: PicPosText.v(context, 
                      24 * scale,
                      color: cart.isNegative
                          ? AppColors.error
                          : AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final double value;
  final double scale;
  final Color? color;
  final bool negative;

  const _Line({
    required this.label,
    required this.value,
    required this.scale,
    this.color,
    this.negative = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2 * scale),
      child: Row(
        children: [
          Text(label, style: PicPosText.l(context, 12 * scale)),
          const Spacer(),
          Text(
            '${negative ? '− ' : ''}${NumberUtils.formatCurrency(value)}',
            style: PicPosText.v(context, 
              13 * scale,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final double scale;

  const _ToggleTile({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 8 * scale),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.10)
              : _fieldOf(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.primary : context.picposHairline,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 14,
                color: active ? AppColors.primary : PicPosText.labelOf(context)),
            const SizedBox(width: 5),
            Text(
              label,
              style: active
                  ? PicPosText.v(context, 12 * scale, color: AppColors.primary)
                  : PicPosText.l(context, 12 * scale),
            ),
          ],
        ),
      ),
    );
  }
}

// ── شيب الصندوق / البنك ────────────────────────────────────────────────────

/// عرض **للقراءة** لطريقة الدفع الحالية والخزنة اللي الفاتورة هتترحّل عليها،
/// + منتقي البنك لما يكون فيه أكتر من حساب.
///
/// ── ليه مفيش أزرار طرق دفع هنا (طلب ٢) ────────────────────────────────────
/// أزرار نقدي/بطاقة/كليك/آجل/متعدد كانت هنا **و** في ديالوج «إتمام الدفع» —
/// نفس الاختيار في مكانين، والكاشير مش عارف مين اللي بيكسب. القرار كان إن
/// الديالوج هو المكان الوحيد. الأكواد اللي كانت بتُنفَّذ بـ `PermissionGuard`
/// حوالين كل زرار بقت بتتنفَّذ في `_allowedPaymentMethods()` وقت فتح الديالوج،
/// وقيد شركات التوصيل (آجل إجباري) بقى في `_processPaymentAndSave` —
/// **الاتنين على مسار الكتابة**، فمش ممكن يتفوّتوا بالطريقة اللي زرار مخفي
/// كان بيسمح بها.
///
/// الصف ده بيفضل **بارتفاع سطر واحد دايماً** عشان ارتفاع اللوحة ما ينططش بين
/// فاتورة وفاتورة — طول متغيّر كان بيزقّ جدول الأصناف لفوق ولتحت مع كل بيعة.
class _SafeChipRow extends ConsumerWidget {
  final CartState cart;
  final double scale;

  const _SafeChipRow({required this.cart, required this.scale});

  static bool _isBankMethod(String m) =>
      m == 'card' || m == 'click' || m == 'mixed';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bankSafes = ref.watch(branchBankSafesProvider).value ?? const <Safe>[];
    final cashSafes = ref.watch(branchCashSafesProvider).value ?? const <Safe>[];
    final method = cart.paymentMethod;

    if (_isBankMethod(method)) {
      return _SafeChip(
        icon: PhosphorIconsBold.bank,
        color: AppColors.info,
        label: _bankName(bankSafes) ?? tr('لا يوجد حساب بنكي'),
        scale: scale,
        onTap: bankSafes.length > 1
            ? () => _pickBank(context, ref, bankSafes)
            : null,
      );
    }
    if (method == 'credit') {
      return _SafeChip(
        icon: PhosphorIconsBold.timer,
        color: AppColors.warning,
        label: tr('آجل — {p0}', {'p0': cart.selectedCustomerName ?? 'بدون عميل'}),
        scale: scale,
      );
    }
    return _SafeChip(
      icon: PhosphorIconsBold.vault,
      color: AppColors.success,
      label: cashSafes.isEmpty
          ? tr('نقدي')
          : tr('الصندوق: {p0}', {'p0': cashSafes.first.name}),
      scale: scale,
    );
  }

  void _pickBank(BuildContext context, WidgetRef ref, List<Safe> bankSafes) {
    final box = context.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlayBox),
        box.localToGlobal(box.size.bottomRight(Offset.zero),
            ancestor: overlayBox),
      ),
      Offset.zero & overlayBox.size,
    );
    showMenu<int>(
      context: context,
      position: position,
      items: [
        for (final safe in bankSafes)
          PopupMenuItem<int>(
            value: safe.id,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                children: [
                  Icon(PhosphorIconsBold.bank,
                      size: 15,
                      color: cart.bankSafeId == safe.id
                          ? AppColors.primary
                          : AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(safe.name)),
                  if (cart.bankSafeId == safe.id)
                    const Icon(PhosphorIconsBold.check,
                        size: 15, color: AppColors.primary),
                ],
              ),
            ),
          ),
      ],
    ).then((id) {
      if (id != null) {
        ref.read(cartControllerProvider.notifier).setBankSafe(id);
      }
    });
  }

  String? _bankName(List<Safe> bankSafes) {
    if (bankSafes.isEmpty) return null;
    if (cart.bankSafeId != null) {
      final m = bankSafes.where((s) => s.id == cart.bankSafeId);
      if (m.isNotEmpty) return m.first.name;
    }
    return bankSafes.length == 1 ? bankSafes.first.name : tr('اختر البنك');
  }
}

class _SafeChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final double scale;
  final VoidCallback? onTap;

  const _SafeChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.scale,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: PicPosText.v(context, 
                  11 * scale,
                  color: color,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(PhosphorIconsBold.caretDown, size: 10, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── أزرار الأفعال ──────────────────────────────────────────────────────────

class _ActionButtons extends ConsumerWidget {
  final double scale;
  final double btnHeight;
  final double btnFont;
  final VoidCallback onCheckout;
  final VoidCallback onSave;
  final VoidCallback onLastInvoice;
  final VoidCallback onPreviousInvoices;
  final VoidCallback onOpenDrawer;
  final VoidCallback onExpense;
  final VoidCallback onHold;
  final VoidCallback onHeldOrders;
  final VoidCallback onQuickReturn;
  final VoidCallback onExchange;

  const _ActionButtons({
    required this.scale,
    required this.btnHeight,
    required this.btnFont,
    required this.onCheckout,
    required this.onSave,
    required this.onLastInvoice,
    required this.onPreviousInvoices,
    required this.onOpenDrawer,
    required this.onExpense,
    required this.onHold,
    required this.onHeldOrders,
    required this.onQuickReturn,
    required this.onExchange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showDrawer = ref.watch(showDrawerButtonInPOSProvider).value ?? true;
    final showExpense = ref.watch(showExpenseButtonInPOSProvider).value ?? true;
    final showSaveOnly = ref.watch(showSaveOnlyInPOSProvider).value ?? true;
    final showHold = ref.watch(showHoldButtonInPOSProvider).value ?? true;
    final cartIsEmpty =
        ref.watch(cartControllerProvider.select((s) => s.items.isEmpty));
    // وضعُ المرتجع (المهمّة ٧، جولةُ إصلاح ١ — C1): «دفع»/«حفظ» كانا
    // معطَّلين **دوماً** أثناء المرتجع لأنهما يقيسان فراغَ سلّة البيع، وسلّةُ
    // المرتجع لا تكتب على `cartController` عمداً (محرِّرُ الأسطر منفصلٌ
    // ومخصَّص). فالتفعيلُ هنا: سلّةُ بيعٍ عامرة، **أو** وضعُ مرتجعٍ فيه
    // كميةٌ واحدةٌ مطلوبةٌ فأكثر — ومعطَّلٌ صراحةً حين تكون كلُّ كميّاتِ
    // المرتجع أصفاراً (لا يُفترَض وصولُه فعلياً: محرِّرُ الأسطر يمنع التأكيدَ
    // بلا كميةٍ، لكنها حمايةٌ دفاعيّةٌ لهذا الزرّ بالذات).
    final returnMode = ref.watch(posReturnModeProvider);
    final returnHasQty =
        returnMode?.requestedQty.values.any((q) => q > 0) ?? false;

    // وضعُ الاستبدال: الشرطُ **مركَّبٌ** لا مفرد — مرتجَعٌ مختارٌ **و**سلّةُ
    // بديلٍ عامرة. فأحدُهما وحدَه ليس استبدالاً: مرتجَعٌ بلا بديلٍ مردودٌ
    // عاديّ، وبديلٌ بلا مرتجَعٍ بيعٌ عاديّ — ولكلٍّ منهما زرُّه.
    //
    // وهنا بالذات يقع الخطأُ المقيسُ في الخطة الأولى: `isEmpty` يُشتقّ من
    // سلّة البيع وحدَها، فيموت «دفع/حفظ» في كلِّ وضعٍ لا يملؤها.
    final exchangeMode = ref.watch(posExchangeModeProvider);
    final isEmpty = exchangeMode != null
        ? !(exchangeMode.hasReturnSelection && !cartIsEmpty)
        : (returnMode != null ? !returnHasQty : cartIsEmpty);

    return Column(
      children: [
        // صف واحد: الدفع بارز وبياخد ضعف عرض جاره، والحفظ والفاتورة السابقة
        // جانبه. كانوا تلات صفوف منفصلة، وده كان بياكل ~١٤٠ بكسل من الجدول.
        Row(
          children: [
            Expanded(
              flex: showSaveOnly ? 2 : 1,
              child: SizedBox(
                height: btnHeight + 6,
                child: ElevatedButton(
                  onPressed: isEmpty ? null : onCheckout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: context.picposHairline,
                    padding: EdgeInsets.zero,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(PhosphorIconsBold.money, size: btnFont + 4),
                      const SizedBox(width: 5),
                      // «دفع» بقى بيحفظ **ويطبع ويفتح الدرج** (طلب ١)، فما
                      // بقاش فيه زرار طباعة منفصل يتلغبط معاه.
                      Text(tr('دفع F4'),
                          style: TextStyle(
                              fontSize: btnFont + 1,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
            if (showSaveOnly) ...[
              SizedBox(width: 5 * scale),
              Expanded(
                child: _Action(
                  label: tr('حفظ F2'),
                  icon: PhosphorIconsBold.floppyDisk,
                  onTap: isEmpty ? null : onSave,
                  height: btnHeight + 6,
                  font: btnFont,
                ),
              ),
            ],
            // ── **خارج** بوابة `showSaveOnly` عن قصد ────────────────────────
            // الزرار ده ورث خانة «طباعة F3» اللي كانت جوه البوابة، لكن دلالته
            // اختلفت: هو مش فعل حفظ، هو مراجعة/إعادة طباعة. مدير قافل «إظهار
            // زر الحفظ» مش قصده يخفي وصول الكاشير لآخر فاتورة.
            //
            // ومش معطّل على السلة الفاضية كمان — السلة الفاضية هي بالظبط وقت
            // استخدامه: البيعة خلصت والعميل رجع يطلب الإيصال.
            SizedBox(width: 5 * scale),
            Expanded(
              child: _Action(
                label: tr('الفاتورة السابقة'),
                icon: PhosphorIconsBold.receipt,
                onTap: onLastInvoice,
                height: btnHeight + 6,
                font: btnFont,
              ),
            ),
            // «مرتجع سريع» (المهمّة ٧) — بجوار «الفاتورة السابقة» بنفس نمط
            // `_Action`. غيرُ معطَّلٍ على سلّةٍ فارغة عمداً: اختيارُ الفاتورة
            // للإرجاع لا يحتاج سلّةَ بيعٍ أصلاً، بعكس «دفع»/«حفظ».
            //
            // ومعطَّلٌ حين وضعُ المرتجع فعّالٌ بالفعل (جولةُ إصلاح ٢، ملاحظةٌ
            // صغيرة): بلا هذا كان يمكن الضغطُ عليه ثانيةً فيستبدل الاختيارَ
            // الحاليّ (فاتورةً وكمياتٍ ضُبطت بعنايةٍ في المحرِّر) بآخرَ صامتاً
            // بلا تأكيد.
            SizedBox(width: 5 * scale),
            Expanded(
              child: _Action(
                label: tr('مرتجع سريع'),
                icon: PhosphorIconsBold.arrowUUpLeft,
                onTap: (returnMode != null || exchangeMode != null)
                    ? null
                    : onQuickReturn,
                height: btnHeight + 6,
                font: btnFont,
              ),
            ),
            // «استبدال» — نفسُ منطق «مرتجع سريع»، وكلُّ وضعٍ يعطّل الآخرَ
            // والنفسَ: الوضعان يقرآن فاتورةً أصليّةً واحدة، وفتحُ الثاني فوق
            // الأوّل كان يستبدل اختياراً ضُبط بعناية بلا تأكيد.
            SizedBox(width: 5 * scale),
            Expanded(
              child: _Action(
                label: tr('استبدال'),
                icon: PhosphorIconsBold.arrowsLeftRight,
                onTap: (returnMode != null || exchangeMode != null)
                    ? null
                    : onExchange,
                height: btnHeight + 6,
                font: btnFont,
              ),
            ),
          ],
        ),
        SizedBox(height: 5 * scale),
        // الأفعال الثانوية: أيقونة + تسمية صغيرة. كل واحد خلف إعداد إظهاره.
        Row(
          children: [
            Expanded(
              child: _MiniAction(
                label: tr('فواتير'),
                icon: PhosphorIconsBold.receipt,
                onTap: onPreviousInvoices,
                height: btnHeight,
                font: btnFont - 1,
              ),
            ),
            if (showHold) ...[
              SizedBox(width: 4 * scale),
              Expanded(
                child: _MiniAction(
                  label: tr('تعليق'),
                  icon: PhosphorIconsBold.pauseCircle,
                  onTap: isEmpty ? null : onHold,
                  height: btnHeight,
                  font: btnFont - 1,
                ),
              ),
              SizedBox(width: 4 * scale),
              Expanded(
                child: _MiniAction(
                  label: tr('معلقة'),
                  icon: PhosphorIconsBold.listChecks,
                  // وضعُ المرتجع (جولةُ إصلاح ٢ — مانعٌ ١): استرجاعُ فاتورةٍ
                  // معلَّقة يحذفها من القاعدة فوراً (`hold_order_usecase.
                  // executeRetrieve`)، وحفظُ المرتجع بعدها يمحو السلّةَ
                  // (`clearCart` في `_processQuickReturnSave`) فيضيع الطلبُ
                  // المعلَّق نهائياً بلا بيعٍ ولا رسالة. `_showHeldOrders`
                  // نفسُها محروسةٌ أيضاً (خطُّ دفاعٍ ثانٍ)، والتعطيلُ هنا
                  // يمنع الكاشيرَ من الدخول أصلاً.
                  onTap: returnMode != null ? null : onHeldOrders,
                  height: btnHeight,
                  font: btnFont - 1,
                ),
              ),
            ],
            if (showDrawer) ...[
              SizedBox(width: 4 * scale),
              Expanded(
                child: _MiniAction(
                  label: tr('الدرج'),
                  icon: PhosphorIconsBold.money,
                  onTap: onOpenDrawer,
                  height: btnHeight,
                  font: btnFont - 1,
                ),
              ),
            ],
            if (showExpense) ...[
              SizedBox(width: 4 * scale),
              Expanded(
                child: _MiniAction(
                  label: tr('مصاريف'),
                  icon: PhosphorIconsBold.coins,
                  onTap: onExpense,
                  height: btnHeight,
                  font: btnFont - 1,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// زرار ثانوي مضغوط — أيقونة فوق تسمية، بلا إطار ثقيل.
class _MiniAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final double height;
  final double font;

  const _MiniAction({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.height,
    required this.font,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: _fieldOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.picposHairline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: font + 2, color: AppColors.primaryDark),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: PicPosText.v(context, 
                  font,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final double height;
  final double font;

  const _Action({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.height,
    required this.font,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          side: BorderSide(color: context.picposHairline),
          foregroundColor: AppColors.primaryDark,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: PicPosText.v(context, font),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

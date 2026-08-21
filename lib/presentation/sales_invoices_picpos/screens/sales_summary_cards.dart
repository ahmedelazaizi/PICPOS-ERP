// ignore_for_file: library_private_types_in_public_api
// نسخةُ PicPos من صفِّ الإجماليات. المنطقُ (المصادر، الحجب، معادلةُ الصافي)
// يبقى مطابقاً لتوأمِ UralCash في
// `screens/widgets/sales_invoices/sales_summary_cards.dart` — وأيُّ إصلاحٍ
// منطقيٍّ يتصلّح في المصدر أوّلاً ثمّ patch (مصيدة النسخ §٥.٨).
//
// ⚠️ **والشكلُ وحدَه هو الذي تباعد** (تصميمُ PicPos 2026-08-21): بطاقةٌ
// رئيسيّةٌ داكنةٌ تحمل المعادلةَ كاملةً، وأربعُ بطاقاتٍ ثانويّة بدل ستٍّ
// متساوية. ولا يُقاس على هذا التباعدِ منطق: `buildMaskedAmountKpiCard`
// تحتفظ بتوقيعها وبعقدها الثلاثيّ — `PermissionGuard(salesAmountsView)`،
// والقيمةُ تختفي، والعنوانُ يبقى — لأن
// `task_9_sales_documents_permission_gates_test` يستدعيها من **الفوركين**
// معاً ويؤكّد الثلاثة.
part of 'sales_invoices_picpos_screen.dart';

/// لونُ خلفيّةِ البطاقة الرئيسيّة — `--hero` في التصميم.
Color _heroBg(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF10305F)
        : AppColors.primaryDark;

/// لونُ النصِّ الخافت — `--muted` في الوضعين.
Color _mutedOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF94A3B8)
        : AppColors.textMuted;

/// كارت مبلغ محجوب بـ`sales_amounts_view`.
///
/// الشكلُ صار بطاقةَ التصميم الثانويّة، والعقدُ لم يتغيّر: الحجبُ بنفس الكود،
/// والعنوانُ يبقى ظاهراً كي يعرف المستخدمُ أن ثمّةَ بياناتٍ لا أن القيمةَ صفر.
@visibleForTesting
Widget buildMaskedAmountKpiCard({
  required IconData icon,
  required String label,
  required String value,
  required Color color,
}) {
  Widget tile(String v) => _SalesKpiTile(
        icon: icon,
        label: label,
        value: v,
        dot: color,
      );
  return PermissionGuard(
    permission: PermissionCodes.salesAmountsView,
    fallback: tile(kMaskedValuePlaceholder),
    child: tile(value),
  );
}

/// البطاقةُ الرئيسيّة للاختبار — نفسُ نمطِ [buildMaskedAmountKpiCard]:
/// النوعُ خاصٌّ بالمكتبة، فالمَخرجُ دالّةٌ كي يبلغه الاختبارُ بلا كشفِ النوع.
@visibleForTesting
Widget buildSalesTotalsHero({
  required double total,
  required double returns,
  required double collected,
}) =>
    _SalesHeroCard(total: total, returns: returns, collected: collected);

/// بطاقةٌ ثانويّة: نقطةٌ ملوّنة · عنوان · أيقونة، ثمّ القيمة.
class _SalesKpiTile extends StatelessWidget {
  const _SalesKpiTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.dot,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _mutedOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon, size: 14, color: muted.withValues(alpha: .55)),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: -.4,
                color: theme.textTheme.bodyLarge?.color,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// البطاقةُ الرئيسيّة: الإجمالي كبيراً، ثمّ شريطُ المعادلة
/// (الإجمالي − المرتجعات = الصافي · والمحصَّلُ نسبةً)، ثمّ شريطُ نِسَبٍ سفليّ.
///
/// المبالغُ كلُّها محجوبةٌ بـ`sales_amounts_view`. والنسبةُ تُحجَب معها: هي
/// مشتقّةٌ من المبالغ فتُفشي مقدارَها لمن لا يحقّ له.
class _SalesHeroCard extends StatelessWidget {
  const _SalesHeroCard({
    required this.total,
    required this.returns,
    required this.collected,
  });

  final double total;
  final double returns;
  final double collected;

  static const _amber = Color(0xFFFCD34D);
  static const _sky = Color(0xFF7FB0FF);

  String _fmt(double v) => v.toStringAsFixed(AppConstants.decimalPlaces);

  double _pct(double part) =>
      total <= 0 ? 0 : (part / total * 100).clamp(0, 100).toDouble();

  @override
  Widget build(BuildContext context) {
    final net = total - returns;
    return PermissionGuard(
      permission: PermissionCodes.salesAmountsView,
      fallback: _body(context, masked: true, paidPct: 0, retPct: 0, net: net),
      child: _body(
        context,
        masked: false,
        paidPct: _pct(collected),
        retPct: _pct(returns),
        net: net,
      ),
    );
  }

  Widget _body(
    BuildContext context, {
    required bool masked,
    required double paidPct,
    required double retPct,
    required double net,
  }) {
    String amount(double v) => masked ? kMaskedValuePlaceholder : _fmt(v);
    final pctLabel = masked ? kMaskedValuePlaceholder : '${paidPct.round()}%';

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: _heroBg(context),
        child: Stack(
          children: [
            // الدائرةُ الزخرفيّة — خارجةٌ عن الحدّ فيقصّها `ClipRRect`.
            PositionedDirectional(
              start: -40,
              top: -40,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryLight.withValues(alpha: .18),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 14, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _headline(amount(total)),
                  _equation(
                    amount(total),
                    amount(returns),
                    amount(net),
                    pctLabel,
                  ),
                ],
              ),
            ),
            // شريطُ النِّسَب السفليّ: المحصَّلُ ثم المرتجعُ ثم الباقي.
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: 0,
              child: SizedBox(
                height: 5,
                child: Row(
                  children: [
                    Expanded(
                      flex: (paidPct * 10).round().clamp(0, 1000),
                      child: const ColoredBox(color: AppColors.primaryLight),
                    ),
                    Expanded(
                      flex: (retPct * 10).round().clamp(0, 1000),
                      child: const ColoredBox(color: AppColors.warning),
                    ),
                    Expanded(
                      // الباقي — وأدنى وزنٍ ١ كي لا ينهار `Row` حين تبلغ
                      // النسبتان ١٠٠٪ فتصير الأوزانُ الثلاثةُ أصفاراً.
                      flex: ((100 - paidPct - retPct) * 10).round().clamp(1, 1000),
                      child: ColoredBox(
                        color: Colors.white.withValues(alpha: .14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headline(String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(
            PhosphorIconsBold.shoppingCart,
            size: 16,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'إجمالي المبيعات (شامل الضريبة)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: .72),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -.5,
                        color: Colors.white,
                        fontFeatures: [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      AppConstants.currencySymbolEn,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: .6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _equation(String total, String returns, String net, String pct) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 100,
            child: _term('الإجمالي', total, Colors.white, FontWeight.w700),
          ),
          _op('−'),
          Expanded(
            flex: 100,
            child: _term('المرتجعات', returns, _amber, FontWeight.w700),
          ),
          _op('='),
          Expanded(
            flex: 115,
            child: _term('صافي المبيعات', net, Colors.white, FontWeight.w800),
          ),
          Container(
            width: 1,
            height: 26,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.white.withValues(alpha: .16),
          ),
          _term('المحصّل', pct, _sky, FontWeight.w800, center: true),
        ],
      ),
    );
  }

  Widget _op(String s) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          s,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: .45),
          ),
        ),
      );

  Widget _term(
    String label,
    String value,
    Color color,
    FontWeight weight, {
    bool center = false,
  }) {
    return Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: .6),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 14,
              fontWeight: weight,
              color: color,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// صفُّ الإجماليات: بطاقةٌ رئيسيّةٌ + أربعُ بطاقاتٍ ثانويّة.
///
/// ⚠️ ولا شارةَ اتّجاهٍ («مقابل الفترة السابقة») رغم وجودها في التصميم:
/// `SalesInvoicesState` لا تحمل بياناتِ فترةٍ سابقةٍ إطلاقاً، واختراعُ نسبةٍ
/// في شاشةٍ ماليّةٍ أسوأُ من غيابها. تُضاف حين يُحسَب الفارقُ فعلاً.
class SalesSummaryRow extends ConsumerWidget {
  const SalesSummaryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalAmount = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.totalAmount));
    final totalPaid =
        ref.watch(salesInvoicesControllerProvider.select((s) => s.totalPaid));
    // Issue 10 — receipt vouchers in the same filter set, summed in.
    final receiptVouchersTotal = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.receiptVouchersTotal));
    final totalRemaining = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.totalRemaining));
    final totalReturns = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.totalReturns));
    final invoiceCount = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.invoiceCount));

    // المحصّل = مدفوعات الفواتير + سندات القبض (Issue 10).
    final collected = totalPaid + receiptVouchersTotal;
    final hasReceiptVouchers = receiptVouchersTotal > 0;

    String money(double v) =>
        '${v.toStringAsFixed(AppConstants.decimalPlaces)} '
        '${AppConstants.currencySymbolEn}';

    final hero = _SalesHeroCard(
      total: totalAmount,
      returns: totalReturns,
      collected: collected,
    );

    final tiles = <Widget>[
      Tooltip(
        // الـtooltip بيفصّل مدفوعات الفواتير وسندات القبض — نفس المبالغ،
        // فبيتحجب مع الكارت لا قبله.
        message: hasReceiptVouchers
            ? 'مدفوعات الفواتير: '
                '${totalPaid.toStringAsFixed(AppConstants.decimalPlaces)}\n'
                'سندات القبض: '
                '${receiptVouchersTotal.toStringAsFixed(AppConstants.decimalPlaces)}'
            : 'مدفوعات الفواتير',
        child: buildMaskedAmountKpiCard(
          icon: PhosphorIconsBold.wallet,
          label: 'المحصّل',
          value: money(collected),
          color: AppColors.success,
        ),
      ),
      buildMaskedAmountKpiCard(
        icon: PhosphorIconsBold.clock,
        label: 'المتبقي',
        value: money(totalRemaining),
        color: AppColors.warning,
      ),
      buildMaskedAmountKpiCard(
        icon: PhosphorIconsBold.arrowUUpLeft,
        label: 'إجمالي المرتجعات',
        value: money(totalReturns),
        color: AppColors.error,
      ),
      // العددُ لا يُحجَب: `sales_amounts_view` تحرس المبالغَ لا وجودَ العمل.
      _SalesKpiTile(
        icon: PhosphorIconsBold.receipt,
        label: 'عدد الفواتير',
        value: '$invoiceCount',
        dot: AppColors.info,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          // ‏٤٣٦ للبطاقة الرئيسيّة كما في التصميم، وأربعُ بطاقاتٍ بجانبها
          // تحتاج ~٦٤٠ كي لا تنضغط أرقامُها. ودون ذلك ينكسر الصفُّ رأسيّاً.
          final wide = constraints.maxWidth >= 1100;
          if (wide) {
            return SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 436, child: hero),
                  const SizedBox(width: gap),
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    Expanded(child: tiles[i]),
                  ],
                ],
              ),
            );
          }
          final perRow = constraints.maxWidth >= 700 ? 4 : 2;
          final tileWidth =
              (constraints.maxWidth - (perRow - 1) * gap) / perRow;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 150, child: hero),
              const SizedBox(height: gap),
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: tiles
                    .map((t) =>
                        SizedBox(width: tileWidth, height: 72, child: t))
                    .toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

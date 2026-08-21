// ignore_for_file: library_private_types_in_public_api
// نسخةُ PicPos من صفِّ إجماليات المشتريات — **مرآةُ شكلٍ** لتوأمِ المبيعات
// في `sales_invoices_picpos/screens/sales_summary_cards.dart`: بطاقةٌ
// رئيسيّةٌ داكنةٌ تحمل المعادلةَ كاملةً، وأربعُ بطاقاتٍ ثانويّة.
//
// ⚠️ **وثلاثةُ فروقٍ مقيسةٍ لا منسوخة** — قِيست في 2026-08-21 قبل كتابةِ سطر:
//
// ‏١) **لا `PermissionGuard` على المبالغ.** لا وجودَ لكودِ
//    `purchases_amounts_view` في `permission_codes.dart` أصلاً (الموجودُ
//    عشرةٌ: view/create/edit/delete/print وخمسةٌ للمرتجع). فمبالغُ المشتريات
//    غيرُ محجوبةٍ بالتصميم لا سهواً — ولفُّها بـ`salesAmountsView` كان سيحجب
//    فاتورةَ مورِّدٍ عن مشترٍ يملك صلاحيتَه كاملةً، بحجّة صلاحيةٍ في وحدةٍ
//    أخرى.
//
// ‏٢) **«المسدَّد» لا «المحصَّل»**، وبلا سنداتِ صرفٍ مضمومة:
//    `PurchaseInvoicesScreenState` لا تحمل `receiptVouchersTotal` ولا نظيرَه،
//    فضمُّ سنداتٍ غيرِ مقيسةٍ كان اختراعَ رقمٍ في شاشةٍ ماليّة.
//
// ‏٣) **المورد لا العميل** في كلّ نصٍّ ومصدرِ اسم.
part of 'purchases_picpos_screen.dart';

/// لونُ خلفيّةِ البطاقة الرئيسيّة — `--hero` في التصميم.
Color _purHeroBg(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF10305F)
        : AppColors.primaryDark;

/// لونُ النصِّ الخافت — `--muted` في الوضعين.
Color _purMuted(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF94A3B8)
        : AppColors.textMuted;

/// نسبةُ التغيّر بين [current] و[previous].
///
/// ‏`null` حين لا تُحسَب: لا فترةَ سابقة، أو كانت صفراً — والقسمةُ على صفرٍ
/// في Dart تعطي `Infinity` لا استثناءً، فـ«‏+Infinity%» كانت ستُطبَع بلا
/// هذا الحارس.
@visibleForTesting
double? purchasesDeltaPct(double current, double? previous) {
  if (previous == null || previous == 0) return null;
  return (current - previous) / previous * 100;
}

/// شارةُ الاتّجاه — سهمٌ ونسبةٌ ملوّنةٌ بمعناها.
///
/// ⚠️ ودلالةُ اللون **معكوسةٌ عن المبيعات عمداً**: ارتفاعُ المشترياتِ ليس
/// خبراً ساراً بذاته كارتفاعِ المبيعات. فالمعنى يُمرَّر صراحةً بـ[goodWhenUp]
/// ولا يُستنتَج من الإشارة.
class _PurTrendBadge extends StatelessWidget {
  const _PurTrendBadge({
    required this.pct,
    this.compact = false,
    this.goodWhenUp = false,
  });

  final double pct;
  final bool compact;
  final bool goodWhenUp;

  @override
  Widget build(BuildContext context) {
    final up = pct >= 0;
    final good = up == goodWhenUp;
    final color = good ? const Color(0xFF5EE49A) : AppColors.error;
    final text = '${up ? '+' : ''}${pct.toStringAsFixed(0)}%';
    final icon = up ? PhosphorIconsBold.trendUp : PhosphorIconsBold.trendDown;

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .18),
        border: Border.all(color: color.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقةٌ ثانويّة: نقطةٌ ملوّنة · عنوان · أيقونة، ثمّ القيمة.
class _PurKpiTile extends StatelessWidget {
  const _PurKpiTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.dot,
    this.deltaPct,
    this.goodWhenUp = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color dot;

  /// `null` ⇒ لا صفَّ اتّجاهٍ إطلاقاً — لا صفرٌ ولا شرطة.
  final double? deltaPct;
  final bool goodWhenUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _purMuted(context);
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
          if (deltaPct != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                _PurTrendBadge(
                  pct: deltaPct!,
                  compact: true,
                  goodWhenUp: goodWhenUp,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'مقابل الفترة السابقة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// البطاقةُ الرئيسيّة للاختبار — النوعُ خاصٌّ بالمكتبة، فالمَخرجُ دالّةٌ كي
/// يبلغه الاختبارُ بلا كشفِ النوع.
@visibleForTesting
Widget buildPurchasesTotalsHero({
  required double total,
  required double returns,
  required double paid,
}) =>
    _PurHeroCard(total: total, returns: returns, paid: paid);

/// البطاقةُ الرئيسيّة: الإجمالي كبيراً، ثمّ شريطُ المعادلة
/// (الإجمالي − المرتجعات = الصافي · والمسدَّدُ نسبةً)، ثمّ شريطُ نِسَبٍ سفليّ.
class _PurHeroCard extends StatelessWidget {
  const _PurHeroCard({
    required this.total,
    required this.returns,
    required this.paid,
    this.deltaPct,
  });

  final double total;
  final double returns;
  final double paid;

  /// تغيّرُ الإجماليّ عن الفترة السابقة — `null` ⇒ لا شارة.
  final double? deltaPct;

  static const _amber = Color(0xFFFCD34D);
  static const _sky = Color(0xFF7FB0FF);

  String _fmt(double v) => v.toStringAsFixed(AppConstants.decimalPlaces);

  double _pct(double part) =>
      total <= 0 ? 0 : (part / total * 100).clamp(0, 100).toDouble();

  @override
  Widget build(BuildContext context) {
    final net = total - returns;
    final paidPct = _pct(paid);
    final retPct = _pct(returns);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: _purHeroBg(context),
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
                  _headline(_fmt(total), deltaPct),
                  _equation(
                    _fmt(total),
                    _fmt(returns),
                    _fmt(net),
                    '${paidPct.round()}%',
                  ),
                ],
              ),
            ),
            // شريطُ النِّسَب السفليّ: المسدَّدُ ثم المرتجعُ ثم الباقي.
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: 0,
              child: SizedBox(
                height: 5,
                // ⚠️ عرضٌ محسوبٌ صراحةً لا `Expanded(flex:)`: الوزنُ صفراً
                // **لا يُلغي** القطعة — `Flexible` يمنح عديمَ الوزن قياسَه
                // الطبيعيّ لا عدماً. نفسُ درسِ بطاقةِ المبيعات.
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    final paidW = (w * paidPct / 100).clamp(0.0, w);
                    final retW = (w * retPct / 100).clamp(0.0, w - paidW);
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.white.withValues(alpha: .14),
                          ),
                        ),
                        PositionedDirectional(
                          start: 0,
                          width: paidW,
                          top: 0,
                          bottom: 0,
                          child: const ColoredBox(
                            color: AppColors.primaryLight,
                          ),
                        ),
                        PositionedDirectional(
                          start: paidW,
                          width: retW,
                          top: 0,
                          bottom: 0,
                          child: const ColoredBox(color: AppColors.warning),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headline(String value, double? trend) {
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
                'إجمالي المشتريات (شامل الضريبة)',
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
        if (trend != null) ...[
          const SizedBox(width: 8),
          _PurTrendBadge(pct: trend),
        ],
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
            child: _term('صافي المشتريات', net, Colors.white, FontWeight.w800),
          ),
          Container(
            width: 1,
            height: 26,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.white.withValues(alpha: .16),
          ),
          _term('المسدَّد', pct, _sky, FontWeight.w800, center: true),
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

/// صفُّ إجماليات المشتريات: بطاقةٌ رئيسيّةٌ + أربعُ بطاقاتٍ ثانويّة.
class PurchasesSummaryRow extends ConsumerWidget {
  const PurchasesSummaryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalAmount = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.totalAmount));
    final totalPaid = ref
        .watch(purchaseInvoicesControllerProvider.select((s) => s.totalPaid));
    final totalRemaining = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.totalRemaining));
    final totalReturns = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.totalReturns));
    final invoiceCount = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.invoiceCount));
    final prev = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.previousPeriod));

    String money(double v) =>
        '${v.toStringAsFixed(AppConstants.decimalPlaces)} '
        '${AppConstants.currencySymbolEn}';

    final hero = _PurHeroCard(
      total: totalAmount,
      returns: totalReturns,
      paid: totalPaid,
      deltaPct: purchasesDeltaPct(totalAmount, prev?.totalAmount),
    );

    final tiles = <Widget>[
      _PurKpiTile(
        icon: PhosphorIconsBold.wallet,
        label: 'المسدَّد',
        value: money(totalPaid),
        dot: AppColors.success,
        deltaPct: purchasesDeltaPct(totalPaid, prev?.totalPaid),
        // سدادُ الموردين ارتفاعُه التزامٌ أُوفي به لا عبئاً — فالأخضرُ صعوداً.
        goodWhenUp: true,
      ),
      _PurKpiTile(
        icon: PhosphorIconsBold.clock,
        label: 'المتبقي',
        value: money(totalRemaining),
        dot: AppColors.warning,
        deltaPct: purchasesDeltaPct(totalRemaining, prev?.totalRemaining),
      ),
      _PurKpiTile(
        icon: PhosphorIconsBold.arrowUUpLeft,
        label: 'إجمالي المرتجعات',
        value: money(totalReturns),
        dot: AppColors.error,
        deltaPct: purchasesDeltaPct(totalReturns, prev?.totalReturns),
      ),
      _PurKpiTile(
        icon: PhosphorIconsBold.receipt,
        label: 'عدد الفواتير',
        value: '$invoiceCount',
        dot: AppColors.info,
        deltaPct: purchasesDeltaPct(
          invoiceCount.toDouble(),
          prev?.invoiceCount.toDouble(),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          // ‏٤٣٦ للبطاقة الرئيسيّة كما في التصميم، وأربعُ بطاقاتٍ بجانبها
          // تحتاج ~٦٤٠ كي لا تنضغط أرقامُها.
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../data/providers/providers.dart';
import '../../../../domain/repositories/restaurant_repository.dart';
import '../providers/tables_state_provider.dart';
import 'table_status_info.dart';

class TableCard extends ConsumerWidget {
  final RestaurantTable table;
  final IRestaurantRepository restaurantRepo;
  final Function(RestaurantTable) onInteraction;

  const TableCard({
    super.key,
    required this.table,
    required this.restaurantRepo,
    required this.onInteraction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiState = ref.watch(tablesUIProvider);
    final statusInfo = tableStatusInfo(table.status);
    // البطاقةُ تعيش على سطحِ الشاشة، فألوانُها تُشتقُّ من الثيم. الأبيضُ
    // المثبَّتُ كان يعمل ما دامت الشاشةُ داكنةً وحدَها؛ وفي الوضع الفاتح
    // يذوب في السطح فيختفي اسمُ الطاولة وسعتُها.
    final cs = Theme.of(context).colorScheme;
    final isSelected = uiState.selectedTableId == table.id;
    final isActive = table.status != 'available' && table.status != 'reserved' && table.status != 'cleaning';

    // Calculate elapsed time
    final elapsed = DateTime.now().difference(table.lastStatusAt);
    final elapsedStr = elapsed.inMinutes > 0
        ? '${elapsed.inHours > 0 ? '${elapsed.inHours}س ' : ''}${elapsed.inMinutes % 60}د'
        : 'الآن';

    final isRound = table.capacity <= 4;

    return GestureDetector(
      onTap: () => onInteraction(table),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSelected
                ? [
                    statusInfo.color.withValues(alpha: 0.15),
                    statusInfo.color.withValues(alpha: 0.05)
                  ]
                : [
                    cs.onSurfaceVariant.withValues(alpha: 0.04),
                    cs.onSurfaceVariant.withValues(alpha: 0.01)
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(isRound ? 80 : 18),
          border: Border.all(
            color: isSelected
                ? statusInfo.color
                : statusInfo.color.withValues(alpha: 0.25),
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: [
            if (isSelected || isActive)
              BoxShadow(
                color: statusInfo.color.withValues(alpha: isSelected ? 0.25 : 0.1),
                blurRadius: isSelected ? 20 : 12,
                spreadRadius: isSelected ? 2 : 0,
              ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── Main content ──
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusInfo.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: statusInfo.color.withValues(alpha: 0.6),
                          blurRadius: 8,
                          spreadRadius: 1),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(table.name,
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      // لونُ الحالة — وهو نفسُ ما تفعله بطاقةُ وضع التصميم
                      // في `floor_plan_designer`، فتتوحّد لغةُ العرضين.
                      // وخلفيّةُ البطاقة تدرُّجٌ بشفافيّة 0.15 فأدنى، فيبقى
                      // الاسمُ مقروءاً محدَّداً كان أو غيرَ محدَّد.
                      color: statusInfo.color,
                    ),
                    textAlign: TextAlign.center),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // نصٌّ ثانويّ — `onSurfaceVariant` هو دورُه في الثيم.
                    // وكان `white @ 0.25`: باهتاً في الداكن، معدوماً في الفاتح.
                    Icon(PhosphorIconsBold.users,
                        size: 10,
                        color: cs.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text('${table.capacity}',
                        style: GoogleFonts.cairo(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600)),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      Icon(PhosphorIconsBold.clock,
                          size: 10, color: statusInfo.color),
                      const SizedBox(width: 2),
                      Text(elapsedStr,
                          style: GoogleFonts.cairo(
                              fontSize: 10,
                              color: statusInfo.color,
                              fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      statusInfo.color.withValues(alpha: 0.2),
                      statusInfo.color.withValues(alpha: 0.08),
                    ]),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: statusInfo.color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusInfo.icon,
                          size: 10, color: statusInfo.color),
                      const SizedBox(width: 4),
                      Text(statusInfo.label,
                          style: GoogleFonts.cairo(
                              fontSize: 9,
                              color: statusInfo.color,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                // «دُفع X من Y» — دفعةٌ جزئيةٌ فقط تبقي الطاولة 🔵 (المدفوعةُ
                // بالكامل تصير 🟠 من تلقائها)، فهذا العرضُ محصورٌ بحالة
                // `occupied` كي لا يظهر على طاولةٍ فارغة.
                if (table.status == 'occupied')
                  FutureBuilder<_PaidProgress?>(
                    future: _paidProgress(ref, restaurantRepo, table.id),
                    builder: (context, snap) {
                      final progress = snap.data;
                      if (progress == null) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'دُفع ${progress.paid.toStringAsFixed(AppConstants.decimalPlaces)} من ${progress.effective.toStringAsFixed(AppConstants.decimalPlaces)}',
                          style: GoogleFonts.cairo(
                              fontSize: 8,
                              color: const Color(0xFFF97316),
                              fontWeight: FontWeight.w700),
                        ),
                      );
                    },
                  ),
              ],
            ),

            if (isActive)
              Positioned(
                top: 8,
                left: 8,
                child: FutureBuilder<TableOrder?>(
                  future: restaurantRepo.getActiveOrderForTable(table.id),
                  builder: (context, snap) {
                    final order = snap.data;
                    if (order == null || order.total <= 0) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        order.total.toStringAsFixed(0),
                        style: GoogleFonts.cairo(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF10B981)),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ما دُفع وما هو مستحقٌّ على الطاولة — لسطر «دُفع س من ص».
class _PaidProgress {
  const _PaidProgress(this.paid, this.effective);
  final double paid;
  final double effective;
}

/// كانت هنا نسخةٌ من قاعدة الخصم تحسب بـ`double` عارية — واحدةٌ من أربع
/// نسخٍ متطابقة. وبدخول الضريبة صار الحسابُ يحتاج **بنودَ** الطلب لا صفَّه
/// وحدَه (لكلّ بندٍ نسبتُه)، فما عاد يُنسَخ في ودجت أصلاً. الحسابُ الآن في
/// `TableSessionService.effectiveTotal` وحدَها، ومن ورائها `TableOrderTotals`.
Future<_PaidProgress?> _paidProgress(
  WidgetRef ref,
  IRestaurantRepository repo,
  int tableId,
) async {
  final order = await repo.getActiveOrderForTable(tableId);
  if (order == null || order.paidAmount <= 0) return null;
  final effective =
      await ref.read(tableSessionServiceProvider).effectiveTotal(order.id);
  return _PaidProgress(order.paidAmount, effective);
}

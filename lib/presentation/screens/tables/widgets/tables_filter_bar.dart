import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/tables_state_provider.dart';
import 'table_status_info.dart';

class TablesFilterBar extends ConsumerWidget {
  const TablesFilterBar({super.key});

  /// ثلاثُ حالاتٍ من خمسٍ عمداً — الترشيحُ لا يعرض `paid` ولا
  /// `out_of_service`. هذا اختيارُ شاشةٍ قديمة، والمصدرُ الموحَّدُ في
  /// `table_status_info.dart` لا يغيّره؛ يُقرأ منه الاسمُ واللونُ والأيقونةُ
  /// فقط لهذه الحالات الثلاث.
  static const List<String> _filterStatuses = [
    'available',
    'reserved',
    'occupied',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiState = ref.watch(tablesUIProvider);
    final uiNotifier = ref.read(tablesUIProvider.notifier);

    final filters = [
       MapEntry(
          'all', TableStatusInfo(tr('الكل'), const Color(0xFF94A3B8), PhosphorIconsBold.stack)),
      for (final status in _filterStatuses)
        MapEntry(status, tableStatusInfo(status)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemCount: filters.length,
                itemBuilder: (context, index) {
                  final entry = filters[index];
                  final isSelected = uiState.statusFilter == entry.key;
                  final info = entry.value;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => uiNotifier.setStatusFilter(entry.key),
                      borderRadius: BorderRadius.circular(8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? LinearGradient(colors: [
                                  info.color.withValues(alpha: 0.2),
                                  info.color.withValues(alpha: 0.08),
                                ])
                              : null,
                          color: isSelected
                              ? null
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? info.color.withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.06),
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                      color: info.color.withValues(alpha: 0.15),
                                      blurRadius: 8)
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(info.icon,
                                size: 12,
                                color: isSelected
                                    ? info.color
                                    : Colors.white.withValues(alpha: 0.3)),
                            const SizedBox(width: 5),
                            Text(info.label,
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? info.color
                                      : Colors.white.withValues(alpha: 0.4),
                                )),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildZoomButton(PhosphorIconsBold.minus, () {
            uiNotifier.setCardSize(uiState.tableCardSize - 40);
          }),
          const SizedBox(width: 4),
          _buildZoomButton(PhosphorIconsBold.plus, () {
            uiNotifier.setCardSize(uiState.tableCardSize + 40);
          }),
        ],
      ),
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

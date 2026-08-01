import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../data/database/database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/permissions/permission_codes.dart';
import '../../../../data/providers/repository_providers.dart';
import '../../../widgets/permission_guard.dart';
import '../providers/tables_state_provider.dart';

/// شكل زرار الإجراءات في الشريط العلوي — مستخرج top-level عشان تقدر
/// `buildTablesManageAddTableButton` تستخدمه من غير الاعتماد على instance
/// method في `TablesTopBar`.
Widget _tablesActionButtonChip(IconData icon, String label, VoidCallback onTap,
    {bool highlight = false}) {
  return Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: highlight
                ? AppColors.primary.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlight
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: highlight
                      ? AppColors.primary
                      : Colors.white.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: highlight
                          ? AppColors.primary
                          : Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    ),
  );
}

// ── دالة بناء مستخرجة (Task 6b) ─────────────────────────────────────────
// زرار «طاولة» (إضافة طاولة) كان محمي بكود عرض خشن بس (فحص الملاحية عبر
// `screenPermissionMap`)، مفيش فحص على الإنشاء نفسه (`tables_manage`).
// مستخرج كدالة top-level عشان يتبنى في اختبار widget خفيف من غير شاشة/قاعدة
// بيانات حقيقية.
@visibleForTesting
Widget buildTablesManageAddTableButton({required VoidCallback onPressed}) {
  return PermissionGuard(
    permission: PermissionCodes.tablesManage,
    allowManagerOverride: true,
    actionName: 'إضافة طاولة',
    onGranted: onPressed,
    child: _tablesActionButtonChip(
      PhosphorIconsBold.plus,
      'طاولة',
      onPressed,
      highlight: true,
    ),
  );
}

class TablesTopBar extends ConsumerWidget {
  final VoidCallback onAddTable;
  final VoidCallback onManageSections;

  const TablesTopBar({
    super.key,
    required this.onAddTable,
    required this.onManageSections,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurantRepo = ref.watch(restaurantRepositoryProvider);
    final uiState = ref.watch(tablesUIProvider);
    final uiNotifier = ref.read(tablesUIProvider.notifier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
          bottom: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo/Title area
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.2),
                  AppColors.primary.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: const Icon(PhosphorIconsBold.table,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('إدارة الطاولات',
                  style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('نشط',
                      style: GoogleFonts.cairo(
                          fontSize: 10,
                          color: const Color(0xFF10B981),
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const Spacer(),

          // Live stats
          FutureBuilder<List<RestaurantTable>>(
            future: restaurantRepo.getAllTables(),
            builder: (context, snap) {
              final tables = snap.data ?? [];
              final available =
                  tables.where((t) => t.status == 'available').length;
              final occupied = tables
                  .where((t) =>
                      t.status != 'available' && t.status != 'reserved')
                  .length;
              final reserved =
                  tables.where((t) => t.status == 'reserved').length;
              return Row(
                children: [
                  _statBadge('$available', 'متاحة', const Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  _statBadge('$occupied', 'مشغولة', const Color(0xFF3B82F6)),
                  const SizedBox(width: 8),
                  _statBadge('$reserved', 'محجوزة', const Color(0xFFF59E0B)),
                  const SizedBox(width: 8),
                  _statBadge(
                      '${tables.length}', 'إجمالي', const Color(0xFF94A3B8)),
                ],
              );
            },
          ),

          const SizedBox(width: 20),

          // Action buttons
          _actionBtn(
            uiState.isVisualView ? PhosphorIconsBold.gridFour : PhosphorIconsBold.squaresFour,
            uiState.isVisualView ? 'شبكي' : 'مخطط',
            () => uiNotifier.toggleView(),
          ),
          if (uiState.isVisualView)
            _actionBtn(
              uiState.isDesignerMode
                  ? PhosphorIconsBold.check
                  : PhosphorIconsBold.pencilLine,
              uiState.isDesignerMode ? 'حفظ' : 'تصميم',
              () => uiNotifier.toggleDesignerMode(),
              highlight: uiState.isDesignerMode,
            ),
          _actionBtn(PhosphorIconsBold.layout, 'أقسام', onManageSections),
          buildTablesManageAddTableButton(onPressed: onAddTable),
        ],
      ),
    );
  }

  Widget _statBadge(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: color.withValues(alpha: 0.5), blurRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(value,
              style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.cairo(
                  fontSize: 9,
                  color: color.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap,
          {bool highlight = false}) =>
      _tablesActionButtonChip(icon, label, onTap, highlight: highlight);
}

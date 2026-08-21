import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/brand.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/permission_guard.dart';

/// Top strip: logo · clock/date · user · POS name · held invoices · close shift.
class PicPosTopBar extends ConsumerWidget {
  /// `null` يعطّل الزرَّ بصرياً (باهتٌ بلا `onTap`) — المهمّة ٧، جولةُ إصلاح
  /// ٢: استرجاعُ فاتورةٍ معلَّقةٍ أثناء وضع المرتجع يحذفها نهائياً من القاعدة
  /// ثم تُمحى مع السلّة عند حفظ المرتجع، فلا سبيلَ لاستعادتها. المستدعي
  /// (‏`picpos_pos_screen.dart`) يمرّر `null` طالما `posReturnModeProvider`
  /// فعّال.
  final VoidCallback? onHeldOrders;
  final VoidCallback onBack;
  final bool showBackButton;

  /// إغلاق الوردية — Task 10B: يسدّ فجوة إن كاشير PicPos ما كان عندوش أي طريقة
  /// يقفل الوردية من البيع السريع. المُستدعي (`picpos_pos_screen.dart`) يمرّر
  /// الفعل مباشرة (`PosCashierClosingDialog.show(context)`) بلا لف — نفس أسلوب
  /// `onCashierClosing` في `pos_main_screen.dart` → `pos_header.dart`. حارس
  /// الصلاحية (`PermissionCodes.posShiftClose` + `allowManagerOverride`) يعيش
  /// هنا داخل الزر نفسه، مطابقاً لـ `_buildShiftCloseButton` في
  /// `pos_header.dart:384-387`.
  final VoidCallback onCloseShift;

  /// تحويل الوردية لكاشير تاني من غير خروج من التطبيق. الشريحة اللي بتعرض
  /// اسم المستخدم كانت `Container` جامد بلا `onTap` — والطريقة الوحيدة
  /// لتغيير الكاشير كانت خروج كامل ورجوع لشاشة الدخول.
  final VoidCallback onSwitchUser;

  const PicPosTopBar({
    super.key,
    required this.onHeldOrders,
    required this.onBack,
    required this.onCloseShift,
    required this.onSwitchUser,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).effectiveUser;
    final heldCount = ref.watch(heldOrdersProvider).value?.length ?? 0;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
      ),
      child: Row(
        children: [
          if (showBackButton)
            IconButton(
              onPressed: onBack,
              icon: const Icon(PhosphorIconsBold.arrowRight,
                  color: Colors.white),
              tooltip: 'رجوع',
            ),
          // Logo comes from Brand so this bar never hard-codes a product.
          Image.asset(
            Brand.logoAsset,
            height: 36,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
          const SizedBox(width: 16),
          const _ClockBlock(),
          const Spacer(),
          // شريحة المستخدم بقت زرار «تحويل المستخدم». مبنية كدالة بترجع
          // widgets قياسية مباشرة (زي `_closeShiftChip`) مش كلاس خاص —
          // نفس السبب الموضّح تحت عند `PermissionGuard`.
          _switchUserChip(
            label: user?.displayName ?? 'مستخدم',
            onPressed: onSwitchUser,
          ),
          const SizedBox(width: 8),
          const _InfoChip(
            icon: PhosphorIconsBold.storefront,
            label: 'البيع السريع',
          ),
          const SizedBox(width: 8),
          _HeldOrdersButton(count: heldCount, onPressed: onHeldOrders),
          const SizedBox(width: 8),
          // ملحوظة تصميم: الحارس هنا يبني الـ InkWell/Container مباشرة (بدل
          // كلاس خاص زي `_HeldOrdersButton`) لأن `PermissionGuard` مع
          // `allowManagerOverride` بيدوّر جوه شجرة الـ widget عن onTap/onPressed
          // (`_ManagerOverrideWrapper._extractOnPressed`) ليعترضه بعد نجاح
          // تصريح المدير — وهو بيتعرف بس على عناصر Flutter القياسية
          // (InkWell/TextButton/Container/إلخ)، مش على كلاس خاص. لف الفعل في
          // كلاس زي `_HeldOrdersButton` كان هيخلي التصريح الناجح ينفّذ لا شيء
          // بصمت. نفس بنية `_buildShiftCloseButton` في pos_header.dart.
          PermissionGuard(
            permission: PermissionCodes.posShiftClose,
            allowManagerOverride: true,
            actionName: 'إغلاق الوردية',
            child: _closeShiftChip(onCloseShift),
          ),
        ],
      ),
    );
  }
}

/// Live clock. Ticks on its own timer rather than rebuilding the whole bar —
/// a POS screen sits open all day, so a per-second rebuild of the header (and
/// everything it watches) is not free.
class _ClockBlock extends StatefulWidget {
  const _ClockBlock();

  @override
  State<_ClockBlock> createState() => _ClockBlockState();
}

class _ClockBlockState extends State<_ClockBlock> {
  late DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final time = '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}';
    final date = '${_now.year}/${_two(_now.month)}/${_two(_now.day)}';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          time,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            // Tabular figures stop the clock from jittering as digits change.
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          date,
          // كان `white70` — باهت على شريط داكن تحت إضاءة المحل. أبيض كامل
          // وبولد زي باقي نصوص البيع السريع (طلب ١٠).
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeldOrdersButton extends StatelessWidget {
  final int count;
  final VoidCallback? onPressed;

  const _HeldOrdersButton({required this.count, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: enabled && count > 0
                ? AppColors.warning
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(PhosphorIconsBold.pauseCircle,
                  size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                'فواتير معلقة ($count)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريحة المستخدم الحالي — دوس عليها يفتح «تحويل المستخدم». مبنية كدالة
/// ترجع widgets قياسية للسبب الموضّح عند `_closeShiftChip`.
Widget _switchUserChip({
  required String label,
  required VoidCallback onPressed,
}) {
  return InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsBold.user, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          // إشارة إن الشريحة قابلة للضغط — من غيرها بتبان زي باقي شرائح
          // العرض الجامدة جنبها.
          const Icon(PhosphorIconsBold.arrowsLeftRight,
              size: 12, color: Colors.white70),
        ],
      ),
    ),
  );
}

/// شريحة «إغلاق الوردية» — نفس أسلوب `_HeldOrdersButton` بصرياً (لون تحذير،
/// نفس المقاسات). مبنية كدالة ترجع widgets قياسية مباشرة (مش كلاس خاص) —
/// السبب موضّح عند نقطة الاستخدام في `PicPosTopBar.build`.
Widget _closeShiftChip(VoidCallback onPressed) {
  return InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsBold.signOut, size: 16, color: Colors.white),
          SizedBox(width: 6),
          Text(
            'إغلاق الوردية',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}

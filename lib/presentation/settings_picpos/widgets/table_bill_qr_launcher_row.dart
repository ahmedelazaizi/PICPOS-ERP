import 'package:ural_erp/core/i18n/tr.dart';
// صفُّ «طباعة أكواد الحساب» في الإعدادات — نُقل من رأس شاشة الطاولات.
//
// ═══ 🔴 لماذا نُقل (قرارُ الخطّة ٢، قسمُ ٧) ═══
//
// بلاغُ المالك 2026-09-18: «قارئُ QR مكانُه مش شاشة الطاولات». والورقةُ
// تُطبَع **مرّةً** عند التجهيز ثمّ تُلصَق، فموضعُها في رأسِ شاشةٍ يفتحها
// النادلُ كلَّ دقيقة يزاحم أفعالَه اليوميّة بفعلٍ لا يفعله.
//
// ⚠️ **والحراسةُ تنتقل بحرفها**: `tables_manage` مع تجاوزِ المدير. الورقةُ
//    تحمل رموزاً موقَّعةً يقرأ بها حاملُها حساباتِ الطاولات، فنقلُ المكان
//    ليس تخفيفَ حراسة.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../tables_picpos/widgets/table_bill_qr_dialog.dart';
import '../../widgets/permission_guard.dart';
import 'settings_blocks.dart';

class TableBillQrLauncherRow extends ConsumerStatefulWidget {
  const TableBillQrLauncherRow({super.key});

  @override
  ConsumerState<TableBillQrLauncherRow> createState() =>
      _TableBillQrLauncherRowState();
}

class _TableBillQrLauncherRowState
    extends ConsumerState<TableBillQrLauncherRow> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final tables =
          await ref.read(restaurantRepositoryProvider).getAllTables();
      if (!mounted) return;
      final active = [
        for (final t in tables)
          if (t.isActive) t,
      ];
      if (active.isEmpty) {
        AppToast.show(context, tr('لا طاولاتٍ بعد — أنشئها من شاشة الطاولات'),
            type: ToastType.warning);
        return;
      }
      TableBillQrDialog.show(context, active);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('تعذّر تحميلُ الطاولات: {e}', {'e': e}),
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGuard(
      permission: PermissionCodes.tablesManage,
      allowManagerOverride: true,
      actionName: tr('طباعة أكواد حساب الطاولات'),
      onGranted: _open,
      child: SettingsRowsBody(
        children: [
          SettingsValueRow(
            key: const Key('settings_table_bill_qr'),
            first: true,
            icon: PhosphorIconsBold.qrCode,
            title: tr('طباعة أكواد الحساب'),
            sub: tr('ورقةٌ برموزِ الطاولات تُلصَق على كلِّ طاولة'),
            tint: AppColors.info,
            onTap: _open,
          ),
        ],
      ),
    );
  }
}

import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_body_handle.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../screens/delivery_management_screen.dart'
    show DeliveryManagementBody;
import '../../widgets/permission_guard.dart';

/// التوصيلُ بترويسة PicPos الموحّدة (`HEADS.delivery`).
///
/// **قشرةٌ لا نسخة**: المنطقُ كلُّه في `DeliveryManagementBody`، وتركبه قشرةُ
/// UralCash في ملفّها كما هي.
///
/// ⚠️ **وحارسُ الصلاحيّة منقولٌ حرفاً بحرف**: زرُّ «سائق جديد» ملفوفٌ بـ
/// `PermissionGuard(PermissionCodes.deliveryCourierManage)` تماماً كما كان
/// الـ`FAB` في قشرة UralCash. وظهورُه مربوطٌ بتبويب المناديب عبر
/// `isReady` — الجسمُ يسجّل الإجراءَ في التبويب الثاني وحدَه.
class DeliveryManagementPicposScreen extends StatefulWidget {
  const DeliveryManagementPicposScreen({super.key});

  @override
  State<DeliveryManagementPicposScreen> createState() =>
      _DeliveryManagementPicposScreenState();
}

class _DeliveryManagementPicposScreenState
    extends State<DeliveryManagementPicposScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _addCourierHandle = PicPosBodyHandle();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _addCourierHandle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PicPosScreenScaffold(
      title: tr('التوصيل'),
      subtitle: tr('الإعدادات ← التكاملات والخدمات'),
      icon: PhosphorIconsBold.moped,
      headerActions: [
        ValueListenableBuilder<bool>(
          valueListenable: _addCourierHandle.isReady,
          builder: (_, ready, _) => ready
              ? PermissionGuard(
                  permission: PermissionCodes.deliveryCourierManage,
                  child: ElevatedButton.icon(
                    onPressed: _addCourierHandle.invoke,
                    icon: const Icon(PhosphorIconsBold.plus, size: 15),
                    label:  Text(tr('سائق جديد')),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
      subHeader: Container(
        color: context.picposCard,
        child: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs:  [
            Tab(
              icon: const Icon(PhosphorIconsBold.buildings),
              text: tr('شركات التوصيل'),
            ),
            Tab(icon: const Icon(PhosphorIconsBold.moped), text: tr('المناديب')),
          ],
        ),
      ),
      bodyPadding: EdgeInsets.zero,
      body: DeliveryManagementBody(
        tabController: _tabController,
        addCourierHandle: _addCourierHandle,
      ),
    );
  }
}

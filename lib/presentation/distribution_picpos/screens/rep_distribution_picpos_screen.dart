// «إدارة المناديب والتوزيع» — المرحلة و (بندا المالك ١٢ و١٨).
//
// القاعدةُ الملزمة: منطقةُ توزيعٍ ← مسارٌ بمندوبٍ واحدٍ وأيّامِ زيارة ←
// عملاءُ مرتَّبون يدويّاً، والعميلُ على مسارٍ واحدٍ في كلّ لحظة. والمندوبُ
// له مخزنُ سيارةٍ (تحميل/تفريغ = تحويلُ مخزون) وخزنةُ عهدةٍ (تسليمٌ =
// تحويلٌ بين الخزائن) ودفاترُ سندات (المرحلة هـ).
//
// التبويبات: المناطق · المسارات · المناديب · الأهداف والتحصيلات.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'dm_areas_tab.dart';
import 'dm_reps_tab.dart';
import 'dm_routes_tab.dart';
import 'dm_targets_tab.dart';

class RepDistributionPicPosScreen extends ConsumerStatefulWidget {
  const RepDistributionPicPosScreen({super.key, this.initialTab = 0});

  /// 0 المناطق · 1 المسارات · 2 المناديب · 3 الأهداف والتحصيلات.
  final int initialTab;

  @override
  ConsumerState<RepDistributionPicPosScreen> createState() =>
      _RepDistributionPicPosScreenState();
}

class _RepDistributionPicPosScreenState
    extends ConsumerState<RepDistributionPicPosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
      length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PicPosScreenScaffold(
      title: tr('إدارة المناديب والتوزيع'),
      subtitle: tr('المناطق والمسارات وعملاؤها ومناديبها وعهدتهم'),
      icon: PhosphorIconsBold.truck,
      subHeader: Container(
        decoration: BoxDecoration(
          color: context.picposCard,
          border: Border(bottom: BorderSide(color: context.picposHairline)),
        ),
        child: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: context.picposMuted,
          tabs: [
            Tab(
              key: const Key('dm_tab_areas'),
              icon: const Icon(PhosphorIconsBold.mapTrifold, size: 18),
              text: tr('المناطق'),
            ),
            Tab(
              key: const Key('dm_tab_routes'),
              icon: const Icon(PhosphorIconsBold.path, size: 18),
              text: tr('المسارات'),
            ),
            Tab(
              key: const Key('dm_tab_reps'),
              icon: const Icon(PhosphorIconsBold.userCircle, size: 18),
              text: tr('المناديب'),
            ),
            Tab(
              key: const Key('dm_tab_targets'),
              icon: const Icon(PhosphorIconsBold.target, size: 18),
              text: tr('الأهداف والتحصيلات'),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          DmAreasTab(),
          DmRoutesTab(),
          DmRepsTab(),
          DmTargetsTab(),
        ],
      ),
    );
  }
}

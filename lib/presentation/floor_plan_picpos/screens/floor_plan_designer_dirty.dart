// تسجيلُ مصمّم القاعة في سجلّ الشاشات المتّسخة (E-1) — في ملفٍّ مستقلٍّ لأنّ
// `floor_plan_designer_picpos_screen.dart` على سقف `file_size_ratchet`.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/dirty_screens_registry.dart';
import '../../../core/navigation/screen_id.dart';
import 'floor_plan_designer_navigation.dart';

/// يسجّل الشاشةَ في [DirtyScreensRegistry] عند الإنشاء ويُلغي التسجيلَ عند
/// التخلّص، فإغلاقُ التاب أو النافذة يسأل قبل إسقاط المسوّدة.
mixin FloorPlanDirtyRegistration<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// مسوّدةُ القسم **أو** مواضعُ الأقسام المعدَّلةُ لم تُحفَظ.
  bool get hasUnsavedFloorPlan;

  late final DirtyScreensRegistry _dirtyRegistry;

  @override
  void initState() {
    super.initState();
    _dirtyRegistry = ref.read(dirtyScreensRegistryProvider);
    _dirtyRegistry.register(
      this,
      screenIndex: ScreenId.floorPlanDesigner.navigationIndex,
      isDirty: () => hasUnsavedFloorPlan,
      confirmDiscard: () async {
        if (!mounted) return true;
        return showFloorPlanDiscardDialog(context, leavingDesigner: true);
      },
    );
  }

  @override
  void dispose() {
    _dirtyRegistry.unregister(this);
    super.dispose();
  }
}
import 'package:ural_erp/core/i18n/tr.dart';
// شاشةُ «مصمّم القاعة» — بلاغُ المالك 2026-09-18 وقسمُ ٧ من خطّة إعادة
// تصميم الشاشات.
//
// ═══ 🔴 لماذا شاشةٌ مستقلّةٌ لا بطاقةٌ داخلَ شاشة الطاولات ═══
//
// شاشةٌ واحدةٌ كانت تخدم **ثلاثةَ** مستخدمين: النادلُ يفتحها كلَّ دقيقة،
// والمديرُ كلَّ شهور، والمُعِدُّ مرّةً واحدة. والمحرّرُ مضغوطٌ في بطاقةٍ
// داخلَ شاشةِ تشغيل، فالسحبُ حيٌّ تحت يدِ من يريد أن **ينقر** طاولةً لا أن
// يحرّكها. وهذا نصُّ البلاغ: «التصميمُ والخريطةُ فيهما مشاكلُ ومش مريح».
//
// ═══ 🔴 والمخطَّطُ **مسوّدةٌ في الذاكرة** حتّى يُحفَظ ═══
//
// المصمّمُ القديم كان يكتب في القاعدة عند نهاية كلّ سحبة، ويترتّب عليه:
// لا تراجعَ ممكن (وهو أوّلُ ما طلبته الخطّةُ من أدوات)، ولا ذرّيّةَ لنصف
// ترتيبٍ انقطع، ولا مستندَ يعبر السلك. فصار التحريرُ هنا على نسخةٍ، والحفظُ
// [saveFloorPlanLayout] — **معاملةٌ واحدة**.
//
// ═══ ⚠️ ولا استيرادَ لـ`data/database` هنا ═══
//
// حارسُ `presentation_db_import_guard` يمنع كلَّ ملفِّ عرضٍ **جديد** من
// استيرادها وقائمتُه البيضاءُ مقفولة. والأنواعُ تصل عبر
// `data/providers/providers.dart` — وهو استيرادٌ غيرُ مباشرٍ لا يخالفه.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/uuid_v7.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/floor_plan_layout.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../widgets/permission_guard.dart';
import '../widgets/floor_plan_canvas_picpos.dart';
import 'floor_plan_designer_dirty.dart';
import 'floor_plan_designer_navigation.dart';

/// المقاسُ الابتدائيُّ لكلّ نوعِ معلَم — جدارٌ شريطٌ طويلٌ نحيف، وعمودٌ
/// مربّعٌ صغير. ولو وُلِد الكلُّ بمقاسٍ واحدٍ لوجب على المستخدم تحجيمُ كلّ
/// جدارٍ يضعه.
const Map<String, ({double width, double height})> kFloorPlanKindSize = {
  'wall': (width: 240, height: 16),
  'door': (width: 80, height: 16),
  'bar': (width: 200, height: 60),
  'kitchen': (width: 200, height: 160),
  'pillar': (width: 40, height: 40),
  'text': (width: 120, height: 32),
};

/// أقسامُ الطاولات — **بثٌّ لا لقطة**.
///
/// ═══ 🔴 بلاغٌ ميدانيٌّ 2026-09-21 ═══
///
/// كانت لقطةً (`getAllSections` في `FutureProvider`)، فقسمٌ يُنشأ في شاشة
/// «الطاولات» **لا يصل المصمّمَ أبداً**: يقول «لا أقسامَ بعد» وقد أُنشئ
/// القسمُ فعلاً وظهر في الشاشة المجاورة.
///
/// ⚠️ **و`autoDispose` لا ينقذ**: الشاشتان تابان في `IndexedStack`، و«كلُّ
///    تابٍ مفتوحٍ شجرةٌ حيّةٌ بمؤقّتاتها ومراقباتها» (راجع
///    `_openScreensStack`). فالمراقبُ قائمٌ والمزوّدُ لا يتخلّص ولا يُعيد
///    القراءة — ولا مخرجَ للمستخدم إلّا إغلاقُ التاب أو البرنامج.
///
/// وشاشةُ الطاولات كانت تقرأ `watchAllSections` والشرطُ في الـDAO **مطابقٌ
/// حرفاً** (`is_active = 1`) — فالفرقُ كان في شكل القراءة وحدَه.
final floorPlanSectionsProvider =
    StreamProvider.autoDispose<List<TableSection>>((ref) {
  return ref.watch(restaurantRepositoryProvider).watchAllSections();
});

/// كلُّ الطاولات — منها تُقرأ الأسماءُ والسعاتُ والحالات. **بثٌّ** كذلك:
/// طاولةٌ تُنشأ والمصمّمُ مفتوحٌ كانت تغيب عنه لنفس السبب، فيرى المستخدمُ
/// صالةً فارغةً وطاولتُه في الشاشة المجاورة.
final floorPlanTablesProvider =
    StreamProvider.autoDispose<List<RestaurantTable>>((ref) {
  return ref.watch(restaurantRepositoryProvider).watchAllTables();
});

/// صناديقُ الأقسام على أرضيّة المحلّ — لنظرةِ المحلّ كلِّه.
///
/// ⚠️ **وتتبع الأقسامَ**: الصناديقُ مشتقّةٌ منها، فقسمٌ جديدٌ يعني صندوقاً
///    جديداً. وبلا هذا التعلُّق تبقى نظرةُ المحلّ لقطةً قديمةً بينما
///    محرّرُ القسم تحدَّث — وهو نصفُ العطب لا كلُّه.
final floorPlanShopBoxesProvider =
    FutureProvider.autoDispose<List<FloorPlanSectionBox>>((ref) async {
  await ref.watch(floorPlanSectionsProvider.future);
  return ref.watch(restaurantRepositoryProvider).getFloorPlanSectionBoxes();
});

/// مخطَّطُ كلِّ قسمٍ — لرسم محتوى الأقسام في نظرة المحلّ.
///
/// ⚠️ **ويُقرأ مرّةً لا مرّةً لكلّ إطار**: نظرةُ المحلّ تُعيد البناءَ مع كلِّ
///    سحبةِ قسمٍ، وقراءةُ القاعدة في `build` كانت تعني استعلاماً لكلّ إطار.
final floorPlanShopLayoutsProvider = FutureProvider.autoDispose<
    Map<int, FloorPlanSectionLayout>>((ref) async {
  final repo = ref.watch(restaurantRepositoryProvider);
  final boxes = await ref.watch(floorPlanShopBoxesProvider.future);
  final out = <int, FloorPlanSectionLayout>{};
  for (final b in boxes) {
    final l = await repo.getFloorPlanLayout(b.sectionId);
    if (l != null) out[b.sectionId] = l;
  }
  return out;
});

class FloorPlanDesignerPicposScreen extends ConsumerStatefulWidget {
  const FloorPlanDesignerPicposScreen({super.key});

  @override
  ConsumerState<FloorPlanDesignerPicposScreen> createState() =>
      _FloorPlanDesignerPicposScreenState();
}

class _FloorPlanDesignerPicposScreenState
    extends ConsumerState<FloorPlanDesignerPicposScreen>
    with FloorPlanDirtyRegistration {
  int? _sectionId;
  FloorPlanUndoStack<FloorPlanSectionLayout>? _stack;
  FloorPlanSectionLayout? _saved;
  Set<String> _selection = <String>{};

  double _gridStep = 40;
  bool _showGrid = true;
  bool _shopView = false;
  bool _busy = false;

  /// يُرفَع مع كلّ نقرةِ «ملاءمةِ الشاشة» — راجع `fitToken`.
  int _fitToken = 0;

  /// مواضعُ الأقسام المعدَّلةُ في نظرة المحلّ — تُحفَظ بزرّها.
  final Map<int, Offset> _shopOrigins = <int, Offset>{};

  FloorPlanSectionLayout? get _draft => _stack?.current;

  @override
  bool get hasUnsavedFloorPlan => _dirty || _shopOrigins.isNotEmpty;

  bool get _dirty {
    final d = _draft;
    final s = _saved;
    if (d == null || s == null) return false;
    return floorPlanLayoutToJson(d).toString() !=
        floorPlanLayoutToJson(s).toString();
  }

  // ───────────────────────────────────────────────────────────────────────
  // تحميل
  // ───────────────────────────────────────────────────────────────────────

  /// 🔴 **طاولةٌ تُنشأ والمصمّمُ مفتوحٌ تصله** — بلاغٌ ميدانيٌّ 2026-09-21.
  ///
  /// اللوحةُ ترسم [_draft] (هندسةَ المخطَّط المحفوظ) و[floorPlanTablesProvider]
  /// يعطي الأسماءَ والسعاتِ وحدَها. فطاولةٌ جديدةٌ ليست في المسوّدة، ولا
  /// تظهر حتى يُعاد تحميلُ القسم — والمستخدمُ يرى صالةً فارغةً وطاولتُه في
  /// الشاشة المجاورة.
  ///
  /// ⚠️ **ولا يُعاد التحميلُ على مسوّدةٍ متّسخة**: إعادةُ التحميل تبني
  ///    `FloorPlanUndoStack` جديدةً، فكلُّ سحبةٍ لم تُحفَظ تضيع — وضياعُ
  ///    عملِ المستخدم أسوأُ من طاولةٍ تتأخّر حتى الحفظ. فالمتّسخةُ تُترَك،
  ///    والعنوانُ يقول «تغييراتٌ لم تُحفَظ» فالحالُ مرئيّةٌ لا صامتة.
  void _watchForNewTables() {
    ref.listen<AsyncValue<List<RestaurantTable>>>(floorPlanTablesProvider,
        (prev, next) {
      final sid = _sectionId;
      final before = prev?.asData?.value;
      final after = next.asData?.value;
      if (sid == null || before == null || after == null) return;

      Set<int> idsIn(List<RestaurantTable> list) =>
          {for (final t in list) if (t.sectionId == sid) t.id};

      final was = idsIn(before);
      final now = idsIn(after);
      if (was.length == now.length && was.containsAll(now)) return;
      if (_dirty) return;
      _loadSection(sid);
    });
  }

  Future<void> _loadSection(int sectionId) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(restaurantRepositoryProvider);
      final layout = await repo.getFloorPlanLayout(sectionId);
      if (!mounted) return;
      setState(() {
        _sectionId = sectionId;
        _saved = layout;
        _stack = layout == null
            ? null
            : FloorPlanUndoStack<FloorPlanSectionLayout>(layout);
        _selection = <String>{};
      });
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('تعذّر فتحُ المخطَّط: {e}', {'e': e}), type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _push(FloorPlanSectionLayout next) {
    final stack = _stack;
    if (stack == null) return;
    setState(() => stack.push(next));
  }

  // ───────────────────────────────────────────────────────────────────────
  // أدوات
  // ───────────────────────────────────────────────────────────────────────

  void _addItem(String kind) {
    final d = _draft;
    if (d == null) return;
    final size = kFloorPlanKindSize[kind] ?? (width: 60.0, height: 60.0);

    // في وسط الصالة: معلَمٌ يُولَد في الزاوية قد يقع تحت آخرَ فلا يُرى،
    // فيظنّ المستخدمُ أنّ الزرَّ لا يعمل ويضغطه مراراً.
    final x = snapToStep((d.canvasWidth - size.width) / 2, _gridStep);
    final y = snapToStep((d.canvasHeight - size.height) / 2, _gridStep);
    final gid = UuidV7.generate();

    _push((
      sectionId: d.sectionId,
      sectionGlobalId: d.sectionGlobalId,
      canvasWidth: d.canvasWidth,
      canvasHeight: d.canvasHeight,
      originX: d.originX,
      originY: d.originY,
      tables: d.tables,
      items: <FloorPlanItemInput>[
        ...d.items,
        (
          id: null,
          globalId: gid,
          kind: kind,
          x: x,
          y: y,
          width: size.width,
          height: size.height,
          rotation: 0,
          // معلَمُ النصّ **يُرفَض بلا نصّ** في التحقّق، فيُولَد بنصٍّ
          // ابتدائيٍّ بدل أن يمنع الحفظَ برسالةٍ لا يعرف المستخدمُ سببَها.
          label: kind == 'text' ? tr('نصّ') : null,
        ),
      ],
    ));
    setState(() => _selection = <String>{itemSelectionKey(gid)});
  }

  void _deleteSelection() {
    final d = _draft;
    if (d == null || _selection.isEmpty) return;
    final items = <FloorPlanItemInput>[
      for (final it in d.items)
        if (it.globalId == null ||
            !_selection.contains(itemSelectionKey(it.globalId!)))
          it,
    ];
    if (items.length == d.items.length) {
      // ⚠️ **الطاولاتُ لا تُحذَف من هنا.** حذفُها يمسّ سجلَّ طلباتٍ وفواتيرَ
      //    (`deleteTable` يفحص ذلك)، والمصمّمُ يرتّب لا يُصفّي.
      AppToast.show(context, tr('الطاولاتُ تُحذَف من شاشة الطاولات لا من المصمّم'),
          type: ToastType.warning);
      return;
    }
    _push(_replaceItems(d, items));
    setState(() => _selection = <String>{});
  }

  void _rotateSelection() {
    final d = _draft;
    if (d == null || _selection.isEmpty) return;

    final items = <FloorPlanItemInput>[
      for (final it in d.items)
        (it.globalId != null &&
                _selection.contains(itemSelectionKey(it.globalId!)))
            ? (
                id: it.id,
                globalId: it.globalId,
                kind: it.kind,
                x: it.x,
                y: it.y,
                width: it.width,
                height: it.height,
                rotation: (it.rotation + 90) % 360,
                label: it.label,
              )
            : it,
    ];
    final tables = <FloorPlanTableGeometry>[
      for (final t in d.tables)
        _selection.contains(tableSelectionKey(t.id))
            ? (
                id: t.id,
                globalId: t.globalId,
                x: t.x,
                y: t.y,
                width: t.width,
                height: t.height,
                rotation: (t.rotation + 90) % 360,
                shape: t.shape,
              )
            : t,
    ];
    _push((
      sectionId: d.sectionId,
      sectionGlobalId: d.sectionGlobalId,
      canvasWidth: d.canvasWidth,
      canvasHeight: d.canvasHeight,
      originX: d.originX,
      originY: d.originY,
      tables: tables,
      items: items,
    ));
  }

  /// يطبّق دالّةَ ترتيبٍ على **المحدَّد وحدَه**.
  ///
  /// 🔴 وهذا هو الفرقُ عن المصمّم القديم: كان يحاذي ويوزّع على
  ///    `tables` كاملةً مهما اختار المستخدم، **ويكتب فوراً في القاعدة**
  ///    بلا تراجع — فمن أراد صفَّ ثلاثِ طاولاتٍ خسر ترتيبَ القاعة.
  void _arrange(
    List<FloorPlanBox> Function(List<FloorPlanBox>) fn,
  ) {
    final d = _draft;
    if (d == null || _selection.length < 2) return;

    final boxes = <FloorPlanBox>[
      for (final t in d.tables)
        if (_selection.contains(tableSelectionKey(t.id)))
          (key: tableSelectionKey(t.id), x: t.x, y: t.y),
      for (final it in d.items)
        if (it.globalId != null &&
            _selection.contains(itemSelectionKey(it.globalId!)))
          (key: itemSelectionKey(it.globalId!), x: it.x, y: it.y),
    ];
    final moved = <String, FloorPlanBox>{
      for (final b in fn(boxes)) b.key: b,
    };
    if (moved.isEmpty) return;

    final next = (
      sectionId: d.sectionId,
      sectionGlobalId: d.sectionGlobalId,
      canvasWidth: d.canvasWidth,
      canvasHeight: d.canvasHeight,
      originX: d.originX,
      originY: d.originY,
      tables: <FloorPlanTableGeometry>[
        for (final t in d.tables)
          () {
            final b = moved[tableSelectionKey(t.id)];
            if (b == null) return t;
            return (
              id: t.id,
              globalId: t.globalId,
              x: b.x,
              y: b.y,
              width: t.width,
              height: t.height,
              rotation: t.rotation,
              shape: t.shape,
            );
          }(),
      ],
      items: <FloorPlanItemInput>[
        for (final it in d.items)
          () {
            final gid = it.globalId;
            final b = gid == null ? null : moved[itemSelectionKey(gid)];
            if (b == null) return it;
            return (
              id: it.id,
              globalId: gid,
              kind: it.kind,
              x: b.x,
              y: b.y,
              width: it.width,
              height: it.height,
              rotation: it.rotation,
              label: it.label,
            );
          }(),
      ],
    );

    // والحصرُ بعدَها: متوسّطٌ قد يقع خارجَ اللوحة حين يُمال إليه
    // صندوقٌ عريض، فيخرج عن المرئيّ بلا أن يلمسه أحد.
    _push(clampLayoutToCanvas(
      next,
      capacityOf: _capacityOf,
    ));
  }

  /// سعةُ طاولةٍ — **وأربعةٌ لمن لم تُقرأ بعد**.
  ///
  /// ⚠️ ورمٌ عند الغياب كان يُسقِط **الترتيبَ كلَّه** لأنّ مزوّدَ
  ///    الطاولات لم يصل بعد، والسعةُ تخدم **الرسمَ وحدَه**.
  int _capacityOf(int id) {
    final tables = ref.read(floorPlanTablesProvider).asData?.value ??
        const <RestaurantTable>[];
    for (final t in tables) {
      if (t.id == id) return t.capacity;
    }
    return 4;
  }

  FloorPlanSectionLayout _replaceItems(
    FloorPlanSectionLayout d,
    List<FloorPlanItemInput> items,
  ) =>
      (
        sectionId: d.sectionId,
        sectionGlobalId: d.sectionGlobalId,
        canvasWidth: d.canvasWidth,
        canvasHeight: d.canvasHeight,
        originX: d.originX,
        originY: d.originY,
        tables: d.tables,
        items: items,
      );

  // ───────────────────────────────────────────────────────────────────────
  // حفظ
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final d = _draft;
    if (d == null) return;

    final bad = validateFloorPlanLayout(d);
    if (bad != null) {
      AppToast.show(context, bad, type: ToastType.error);
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(restaurantRepositoryProvider).saveFloorPlanLayout(d);
      if (!mounted) return;
      // ⚠️ **يُعاد التحميلُ من القاعدة لا يُنسَخ المسوّدة.** الحفظُ يُولّد
      //    معرّفاتٍ ويحذف معالمَ غائبةً، فنسخُ المسوّدة كان يُبقي الشاشةَ
      //    تعرض حالةً لا تطابق ما في القاعدة حتّى إعادةِ الفتح.
      await _loadSection(d.sectionId);
      ref.invalidate(floorPlanShopBoxesProvider);
      ref.invalidate(floorPlanTablesProvider);
      if (mounted) {
        AppToast.show(context, tr('حُفظ مخطَّطُ القاعة'), type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('فشل الحفظ: {e}', {'e': e}), type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // الحوارُ والمغادرةُ في `floor_plan_designer_navigation.dart` (سقفُ الحجم).
  Future<bool> _confirmDiscard() async =>
      !_dirty || await showFloorPlanDiscardDialog(context);

  /// يُسقط المسوّدةَ ويعيد قراءةَ المحفوظ.
  Future<void> _discardDraft() async {
    if (mounted) setState(_shopOrigins.clear);
    final id = _sectionId;
    if (id != null) await _loadSection(id);
  }

  // ───────────────────────────────────────────────────────────────────────
  // نظرةُ المحلّ
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _saveShopOrigins() async {
    if (_shopOrigins.isEmpty) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(restaurantRepositoryProvider);
      for (final entry in _shopOrigins.entries) {
        final layout = await repo.getFloorPlanLayout(entry.key);
        if (layout == null) continue;
        await repo.saveFloorPlanLayout((
          sectionId: layout.sectionId,
          sectionGlobalId: layout.sectionGlobalId,
          canvasWidth: layout.canvasWidth,
          canvasHeight: layout.canvasHeight,
          originX: entry.value.dx,
          originY: entry.value.dy,
          tables: layout.tables,
          items: layout.items,
        ));
      }
      if (!mounted) return;
      setState(_shopOrigins.clear);
      ref.invalidate(floorPlanShopBoxesProvider);
      AppToast.show(context, tr('حُفظت مواضعُ الأقسام'),
          type: ToastType.success);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('فشل الحفظ: {e}', {'e': e}), type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // البناء
  // ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _watchForNewTables();

    final sections =
        ref.watch(floorPlanSectionsProvider).asData?.value ??
            const <TableSection>[];

    return FloorPlanLeaveGuard(
      dirty: hasUnsavedFloorPlan,
      discardDraft: _discardDraft,
      child: PicPosScreenScaffold(
      onBack: () => leaveFloorPlanDesigner(context, ref,
          dirty: hasUnsavedFloorPlan, discardDraft: _discardDraft),
      title: tr('مصمم القاعة'),
      subtitle: _shopView
          ? tr('نظرةُ المحلّ كلِّه — اسحب القسمَ لتضعه على الأرضيّة')
          : (_dirty ? tr('تغييراتٌ لم تُحفَظ') : tr('ارسم الصالةَ كما هي على الأرض')),
      icon: PhosphorIconsBold.squaresFour,
      headerActions: [
        SegmentedButton<bool>(
          key: const Key('floor_plan_shop_view'),
          segments:  [
            ButtonSegment(value: false, label: Text(tr('قسم'))),
            ButtonSegment(value: true, label: Text(tr('المحلّ كلّه'))),
          ],
          selected: {_shopView},
          showSelectedIcon: false,
          onSelectionChanged: (v) async {
            final next = v.first;
            if (next && !await _confirmDiscard()) return;
            if (mounted) setState(() => _shopView = next);
          },
        ),
      ],
      toolbar: _shopView ? _shopToolbar() : _editorToolbar(sections),
      body: _shopView ? _shopBody() : _editorBody(sections),
    ));
  }

  // ─── شريطُ المحرّر ─────────────────────────────────────────────────────
  Widget _editorToolbar(List<TableSection> sections) {
    final stack = _stack;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<int>(
                key: const Key('floor_plan_section_picker'),
                initialValue: _sectionId,
                isDense: true,
                decoration:  InputDecoration(
                  labelText: tr('القسم'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final s in sections)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) async {
                  if (v == null || v == _sectionId) return;
                  if (!await _confirmDiscard()) return;
                  await _loadSection(v);
                },
              ),
            ),
            const SizedBox(width: 12),
            _btn('floor_plan_undo', PhosphorIconsBold.arrowUUpLeft, tr('تراجع'),
                (stack?.canUndo ?? false) ? () => setState(stack!.undo) : null),
            _btn('floor_plan_redo', PhosphorIconsBold.arrowUUpRight, tr('إعادة'),
                (stack?.canRedo ?? false) ? () => setState(stack!.redo) : null),
            _divider(),
            for (final kind in kFloorPlanItemKinds)
              _btn(
                'floor_plan_add_$kind',
                floorPlanKindIcon(kind),
                tr('أضف {p0}', {'p0': floorPlanKindLabel(kind)}),
                _draft == null ? null : () => _addItem(kind),
              ),
            _divider(),
            _btn('floor_plan_rotate', PhosphorIconsBold.arrowClockwise,
                tr('تدوير ٩٠°'), _selection.isEmpty ? null : _rotateSelection),
            _btn('floor_plan_delete', PhosphorIconsBold.trash, tr('حذف المحدَّد'),
                _selection.isEmpty ? null : _deleteSelection),
            _divider(),
            // المحاذاةُ والتوزيعُ على **المحدَّد** — ومعطّلان دونَ اثنين.
            _btn(
              'floor_plan_align_h',
              PhosphorIconsBold.alignCenterHorizontal,
              tr('محاذاة أفقية'),
              _selection.length < 2
                  ? null
                  : () => _arrange((b) => alignBoxes(b, horizontal: true)),
            ),
            _btn(
              'floor_plan_align_v',
              PhosphorIconsBold.alignCenterVertical,
              tr('محاذاة رأسية'),
              _selection.length < 2
                  ? null
                  : () => _arrange((b) => alignBoxes(b, horizontal: false)),
            ),
            _btn(
              'floor_plan_distribute_h',
              PhosphorIconsBold.columns,
              tr('توزيع أفقي'),
              _selection.length < 3
                  ? null
                  : () =>
                      _arrange((b) => distributeBoxes(b, horizontal: true)),
            ),
            _btn(
              'floor_plan_distribute_v',
              PhosphorIconsBold.rows,
              tr('توزيع رأسي'),
              _selection.length < 3
                  ? null
                  : () =>
                      _arrange((b) => distributeBoxes(b, horizontal: false)),
            ),
            _divider(),
            _btn(
              'floor_plan_fit',
              PhosphorIconsBold.cornersOut,
              tr('ملاءمة الشاشة'),
              _draft == null ? null : () => setState(() => _fitToken++),
            ),
            _btn(
              'floor_plan_grid_toggle',
              _showGrid ? PhosphorIconsBold.gridFour : PhosphorIconsBold.square,
              _showGrid ? tr('إخفاء الشبكة') : tr('إظهار الشبكة'),
              () => setState(() => _showGrid = !_showGrid),
            ),
            SizedBox(
              width: 96,
              child: DropdownButtonFormField<double>(
                key: const Key('floor_plan_grid_step'),
                initialValue: _gridStep,
                isDense: true,
                decoration:  InputDecoration(
                  labelText: tr('الشبكة'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final step in kFloorPlanGridSteps)
                    DropdownMenuItem(
                        value: step, child: Text(step.toInt().toString())),
                ],
                onChanged: (v) => setState(() => _gridStep = v ?? 40),
              ),
            ),
            const SizedBox(width: 12),
            PermissionGuard(
              permission: PermissionCodes.tablesManage,
              allowManagerOverride: true,
              actionName: tr('حفظ مخطط القاعة'),
              onGranted: _save,
              child: FilledButton.icon(
                key: const Key('floor_plan_save'),
                onPressed: (_busy || _draft == null) ? null : _save,
                icon: const Icon(PhosphorIconsBold.floppyDisk, size: 18),
                label: Text(_dirty ? tr('حفظ *') : tr('حفظ')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shopToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
           Expanded(
            child: Text(
              tr('الأقسامُ تُرى معاً على أرضيّةٍ واحدة — اسحب القسمَ ليجاور موضعَه الحقيقيَّ في المحلّ.'),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          FilledButton.icon(
            key: const Key('floor_plan_shop_save'),
            onPressed:
                (_busy || _shopOrigins.isEmpty) ? null : _saveShopOrigins,
            icon: const Icon(PhosphorIconsBold.floppyDisk, size: 18),
            label:  Text(tr('حفظ المواضع')),
          ),
        ],
      ),
    );
  }

  Widget _btn(String key, IconData icon, String tip, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        key: Key(key),
        tooltip: tip,
        icon: Icon(icon, size: 18),
        onPressed: onTap,
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: AppColors.border.withValues(alpha: 0.4),
      );

  // ─── جسمُ المحرّر ──────────────────────────────────────────────────────
  Widget _editorBody(List<TableSection> sections) {
    if (sections.isEmpty) {
      return  PicPosContentCard(
        child: PicPosEmptyState(
          key: const Key('floor_plan_no_sections'),
          icon: PhosphorIconsBold.mapPinArea,
          title: tr('لا أقسامَ بعد'),
          hint: tr('أنشئ قسماً من شاشة الطاولات ثمّ ارسم صالتَه هنا'),
        ),
      );
    }

    // أوّلُ قسمٍ يُفتَح تلقائيّاً: شاشةٌ فارغةٌ بمنسدلةٍ مملوءةٍ تُقرأ عطلاً.
    if (_sectionId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sectionId == null) _loadSection(sections.first.id);
      });
      return const Center(child: CircularProgressIndicator());
    }

    final draft = _draft;
    if (draft == null) {
      return Center(
        child: _busy
            ? const CircularProgressIndicator()
            :  Text(tr('تعذّر تحميلُ مخطَّط هذا القسم')),
      );
    }

    final tables = ref.watch(floorPlanTablesProvider).asData?.value ??
        const <RestaurantTable>[];
    final meta = <int, FloorPlanTableMeta>{
      for (final t in tables)
        t.id: (name: t.name, capacity: t.capacity, status: t.status),
    };

    return PicPosContentCard(
      padding: const EdgeInsets.all(8),
      child: FloorPlanEditorCanvas(
        key: ValueKey(draft.sectionId),
        layout: draft,
        tableMeta: meta,
        selection: _selection,
        gridStep: _gridStep,
        showGrid: _showGrid,
        fitToken: _fitToken,
        onChanged: _push,
        onSelectionChanged: (s) => setState(() => _selection = s),
      ),
    );
  }

  // ─── نظرةُ المحلّ ──────────────────────────────────────────────────────

  /// محتوى قسمٍ مصغَّراً على أرضيّة المحلّ — طاولاتٌ ومعالمُ بلا نصّ.
  ///
  /// والأسماءُ تُحذَف عمداً: عند مقياسٍ يصغّر الصالةَ إلى خُمسها يصير كلُّ
  /// نصٍّ بقعةً، والشكلُ وحدَه هو ما يُتعرَّف به على القاعة.
  List<Widget> _shopContents(FloorPlanSectionBox box, double scale) {
    final layouts = ref.watch(floorPlanShopLayoutsProvider).asData?.value;
    final layout = layouts?[box.sectionId];
    if (layout == null) return const <Widget>[];

    final tables = ref.watch(floorPlanTablesProvider).asData?.value ??
        const <RestaurantTable>[];
    final capacityOf = <int, int>{for (final t in tables) t.id: t.capacity};

    return <Widget>[
      for (final it in layout.items)
        Positioned(
          left: it.x * scale,
          top: it.y * scale,
          width: it.width * scale,
          height: it.height * scale,
          child: Container(
            color: AppColors.textMuted.withValues(alpha: 0.35),
          ),
        ),
      for (final t in layout.tables)
        () {
          final size = resolveTableSize(
            width: t.width,
            height: t.height,
            capacity: capacityOf[t.id] ?? 4,
          );
          return Positioned(
            key: Key('floor_plan_shop_table_${t.id}'),
            left: t.x * scale,
            top: t.y * scale,
            width: size.width * scale,
            height: size.height * scale,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.25),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.6),
                ),
                borderRadius: BorderRadius.circular(
                  t.shape == 'circle' ? 999 : 3,
                ),
              ),
            ),
          );
        }(),
    ];
  }

  Widget _shopBody() {
    final boxesAsync = ref.watch(floorPlanShopBoxesProvider);
    final sections = ref.watch(floorPlanSectionsProvider).asData?.value ??
        const <TableSection>[];
    final boxes = boxesAsync.asData?.value ?? const <FloorPlanSectionBox>[];

    if (boxes.isEmpty) {
      return  PicPosContentCard(
        child: PicPosEmptyState(
          key: const Key('floor_plan_shop_empty'),
          icon: PhosphorIconsBold.buildings,
          title: tr('لا أقسامَ تُرسَم'),
          hint: tr('أنشئ قسماً أوّلاً'),
        ),
      );
    }

    final nameById = <int, String>{for (final s in sections) s.id: s.name};
    final placed = <FloorPlanSectionBox>[
      for (final b in boxes)
        _shopOrigins.containsKey(b.sectionId)
            ? (
                sectionId: b.sectionId,
                originX: _shopOrigins[b.sectionId]!.dx,
                originY: _shopOrigins[b.sectionId]!.dy,
                width: b.width,
                height: b.height,
              )
            : b,
    ];
    final extent = shopExtent(placed);

    return PicPosContentCard(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, c) {
          final scale = fitScale(
            contentWidth: extent.width,
            contentHeight: extent.height,
            viewWidth: c.maxWidth - 16,
            viewHeight: c.maxHeight - 16,
          );
          return Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.expand(
              child: Stack(
                children: [
                  for (final b in placed)
                    Positioned(
                      left: b.originX * scale,
                      top: b.originY * scale,
                      width: b.width * scale,
                      height: b.height * scale,
                      child: GestureDetector(
                        key: Key('floor_plan_shop_section_${b.sectionId}'),
                        onPanUpdate: (d) => setState(() {
                          final cur = _shopOrigins[b.sectionId] ??
                              Offset(b.originX, b.originY);
                          _shopOrigins[b.sectionId] = Offset(
                            (cur.dx + d.delta.dx / scale)
                                .clamp(0.0, kMaxCanvasSide),
                            (cur.dy + d.delta.dy / scale)
                                .clamp(0.0, kMaxCanvasSide),
                          );
                        }),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.06),
                              border: Border.all(
                                color:
                                    AppColors.primary.withValues(alpha: 0.5),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Stack(
                              children: [
                                // ⚠️ **ومحتوى القسم يُرسَم داخلَه.** «نظرةُ
                                //    المحلّ كلِّه» بمستطيلاتٍ مسمّاةٍ وحدَها
                                //    ليست مخطَّطَ محلّ: المديرُ يضع التراسَ
                                //    خلفَ الصالة ليرى **أين تقع الطاولاتُ
                                //    بعضُها من بعض**، لا ليرى صندوقَين.
                                ..._shopContents(b, scale),
                                Positioned(
                                  left: 4,
                                  top: 4,
                                  child: Text(
                                    nameById[b.sectionId] ??
                                        '#${b.sectionId}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

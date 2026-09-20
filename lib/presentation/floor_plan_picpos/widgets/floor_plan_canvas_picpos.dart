// لوحةُ مصمّم القاعة — نسخةٌ مستقلّةٌ عن `screens/tables/floor_plan_designer.dart`.
//
// ═══ ⚠️ نسخةٌ لا مشاركة (ح‑٣) ═══
//
// الأصلُ يبقى كما هو لفورك UralCash ولشاشة الطاولات القديمة. وهذه النسخةُ
// تختلف عنه في **النموذج** لا في الشكل:
//
//   • الأصلُ يكتب في القاعدة عند نهاية كلّ سحبة، وهذه تُعدّل **مسوّدةً في
//     الذاكرة** وتُبلّغ المضيفَ — وهو ما يجعل «تراجع» ممكناً أصلاً.
//   • الأصلُ يعرف الطاولاتِ وحدَها، وهذه ترسم **معالمَ القاعة** معها.
//   • الأصلُ يشتقّ المقاسَ من السعة حصراً، وهذه تقرأ المحفوظَ أوّلاً
//     (`resolveTableSize`) — فطاولتا اثنَين وثلاثةٍ لم تعودا متطابقتَين.
//
// ═══ ⚠️ ولا استيرادَ لـ`data/database` هنا ═══
//
// حارسُ `presentation_db_import_guard` يمنع كلَّ ملفِّ عرضٍ **جديد** من
// استيرادها. والحسابُ كلُّه في `domain/models/floor_plan_layout.dart`.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/floor_plan_layout.dart';

/// ما تعرفه اللوحةُ عن الطاولة **غيرَ هندستها** — اسمٌ وسعةٌ وحالة.
///
/// ⚠️ **ولا تُحفَظ.** الحالةُ تتغيّر كلَّ دقيقةٍ بيد النادل، والمصمّمُ يحفظ
///    مواضعَ — فلو حملها المخطَّطُ لأعاد حالةً قديمةً إلى طاولةٍ عليها طلب.
typedef FloorPlanTableMeta = ({String name, int capacity, String status});

/// مفتاحُ التحديد — `t:<id>` لطاولة، `i:<globalId>` لمعلَم.
String tableSelectionKey(int id) => 't:$id';
String itemSelectionKey(String globalId) => 'i:$globalId';

class FloorPlanEditorCanvas extends StatefulWidget {
  const FloorPlanEditorCanvas({
    super.key,
    required this.layout,
    required this.tableMeta,
    required this.selection,
    required this.onChanged,
    required this.onSelectionChanged,
    this.gridStep = 40,
    this.showGrid = true,
    this.enabled = true,
    this.fitToken = 0,
  });

  final FloorPlanSectionLayout layout;
  final Map<int, FloorPlanTableMeta> tableMeta;
  final Set<String> selection;
  final double gridStep;
  final bool showGrid;
  final bool enabled;

  /// عدّادٌ يرفعُه المضيفُ ليطلب «ملاءمةَ الشاشة».
  ///
  /// ⚠️ **وعدّادٌ لا راية**: الرايةُ تُضبَط ثمّ تُطفَأ في إطارٍ
  ///    ثانٍ، ونقرتان متتاليتان على نفس القيمة لا تُنتج تغيّراً
  ///    يراه `didUpdateWidget` — فيبدو الزرُّ ميّتاً في المرّة الثانية.
  final int fitToken;

  /// يُنادى عند **انتهاء** الإيماءة لا أثناءها.
  ///
  /// 🔴 وهذا هو ما يجعل «تراجع» صالحاً للاستعمال: بثُّ كلّ إطارٍ كان يدفع
  ///    مئةَ خطوةٍ في المكدّس للسحبة الواحدة، فيصير الزرُّ بلا معنى.
  final ValueChanged<FloorPlanSectionLayout> onChanged;
  final ValueChanged<Set<String>> onSelectionChanged;

  @override
  State<FloorPlanEditorCanvas> createState() => _FloorPlanEditorCanvasState();
}

class _FloorPlanEditorCanvasState extends State<FloorPlanEditorCanvas> {
  final TransformationController _transform = TransformationController();

  /// مواضعُ حيّةٌ أثناء السحب — تُمحى عند انتهائه.
  final Map<String, Offset> _live = <String, Offset>{};
  final Map<String, Size> _liveSize = <String, Size>{};
  Size? _liveCanvas;

  double? _guideX;
  double? _guideY;

  /// مقاسُ النافذة كما قاسه `LayoutBuilder` — لملاءمة الشاشة.
  Size _viewport = Size.zero;

  @override
  void didUpdateWidget(covariant FloorPlanEditorCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fitToken != oldWidget.fitToken) _fitToScreen();
  }

  /// يضبط التحويلَ ليُرى المخطَّطُ كلُّه.
  void _fitToScreen() {
    final s = fitScale(
      contentWidth: _w + 40,
      contentHeight: _h + 40,
      viewWidth: _viewport.width,
      viewHeight: _viewport.height,
    );
    _transform.value = Matrix4.identity()..scaleByDouble(s, s, 1, 1);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  double get _w => _liveCanvas?.width ?? widget.layout.canvasWidth;
  double get _h => _liveCanvas?.height ?? widget.layout.canvasHeight;

  double _snap(double v) => snapToStep(v, widget.gridStep);

  double _scale() => _transform.value.getMaxScaleOnAxis();

  // ───────────────────────────────────────────────────────────────────────
  // أدلّةُ المحاذاة
  // ───────────────────────────────────────────────────────────────────────

  void _updateGuides(String movingKey, Offset pos) {
    const threshold = 8.0;
    double? gx;
    double? gy;
    for (final e in _allBoxes()) {
      if (e.key == movingKey) continue;
      if ((pos.dx - e.x).abs() < threshold) gx = e.x;
      if ((pos.dy - e.y).abs() < threshold) gy = e.y;
    }
    if (gx != _guideX || gy != _guideY) {
      setState(() {
        _guideX = gx;
        _guideY = gy;
      });
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // صناديقُ الرسم
  // ───────────────────────────────────────────────────────────────────────

  List<({String key, double x, double y, double w, double h})> _allBoxes() {
    final out = <({String key, double x, double y, double w, double h})>[];
    for (final t in widget.layout.tables) {
      final key = tableSelectionKey(t.id);
      final meta = widget.tableMeta[t.id];
      final size = resolveTableSize(
        width: t.width,
        height: t.height,
        capacity: meta?.capacity ?? 4,
      );
      final p = _live[key] ?? Offset(t.x, t.y);
      out.add((key: key, x: p.dx, y: p.dy, w: size.width, h: size.height));
    }
    for (final it in widget.layout.items) {
      final gid = it.globalId;
      if (gid == null) continue;
      final key = itemSelectionKey(gid);
      final p = _live[key] ?? Offset(it.x, it.y);
      final s = _liveSize[key] ?? Size(it.width, it.height);
      out.add((key: key, x: p.dx, y: p.dy, w: s.width, h: s.height));
    }
    return out;
  }

  // ───────────────────────────────────────────────────────────────────────
  // الالتقاطُ والتحديد
  // ───────────────────────────────────────────────────────────────────────

  void _toggleSelection(String key, {required bool additive}) {
    final next = <String>{...widget.selection};
    if (additive) {
      if (!next.remove(key)) next.add(key);
    } else {
      next
        ..clear()
        ..add(key);
    }
    widget.onSelectionChanged(next);
  }

  /// مفاتيحُ ما سيتحرّك مع هذه السحبة.
  ///
  /// ⚠️ سحبُ عنصرٍ **خارجَ** التحديد يعني «انسَ التحديدَ واسحب هذا» — لا
  ///    «حرّك ما اخترتَه قبل دقيقةٍ ونسيتَه».
  Set<String> _dragGroup(String key) =>
      widget.selection.contains(key) && widget.selection.length > 1
          ? <String>{...widget.selection}
          : <String>{key};

  // ───────────────────────────────────────────────────────────────────────
  // الإفلات
  // ───────────────────────────────────────────────────────────────────────

  void _commitDrag() {
    if (_live.isEmpty) return;

    final tables = <FloorPlanTableGeometry>[
      for (final t in widget.layout.tables)
        () {
          final p = _live[tableSelectionKey(t.id)];
          if (p == null) return t;
          return (
            id: t.id,
            globalId: t.globalId,
            x: _snapWithGuide(p.dx, _guideX),
            y: _snapWithGuide(p.dy, _guideY),
            width: t.width,
            height: t.height,
            rotation: t.rotation,
            shape: t.shape,
          );
        }(),
    ];

    final items = <FloorPlanItemInput>[
      for (final it in widget.layout.items)
        () {
          final gid = it.globalId;
          if (gid == null) return it;
          final p = _live[itemSelectionKey(gid)];
          if (p == null) return it;
          return (
            id: it.id,
            globalId: gid,
            kind: it.kind,
            x: _snapWithGuide(p.dx, _guideX),
            y: _snapWithGuide(p.dy, _guideY),
            width: it.width,
            height: it.height,
            rotation: it.rotation,
            label: it.label,
          );
        }(),
    ];

    setState(() {
      _live.clear();
      _guideX = null;
      _guideY = null;
    });

    widget.onChanged(_withGeometry(tables: tables, items: items));
  }

  double _snapWithGuide(double v, double? guide) =>
      (guide != null && (v - guide).abs() < 12) ? guide : _snap(v);

  void _commitResize(String key) {
    final size = _liveSize[key];
    if (size == null) return;
    final items = <FloorPlanItemInput>[
      for (final it in widget.layout.items)
        (it.globalId != null && itemSelectionKey(it.globalId!) == key)
            ? (
                id: it.id,
                globalId: it.globalId,
                kind: it.kind,
                x: it.x,
                y: it.y,
                width: _snap(size.width).clamp(kMinItemSide, _w),
                height: _snap(size.height).clamp(kMinItemSide, _h),
                rotation: it.rotation,
                label: it.label,
              )
            : it,
    ];
    setState(() => _liveSize.remove(key));
    widget.onChanged(_withGeometry(items: items));
  }

  void _commitCanvas() {
    final size = _liveCanvas;
    if (size == null) return;
    setState(() => _liveCanvas = null);

    final next = (
      sectionId: widget.layout.sectionId,
      sectionGlobalId: widget.layout.sectionGlobalId,
      canvasWidth: _snap(size.width).clamp(kMinCanvasSide, kMaxCanvasSide),
      canvasHeight: _snap(size.height).clamp(kMinCanvasSide, kMaxCanvasSide),
      originX: widget.layout.originX,
      originY: widget.layout.originY,
      tables: widget.layout.tables,
      items: widget.layout.items,
    );

    // 🔴 والحصرُ **مع** تغيير المقاس لا بعده بخطوة: ما وراء الحافّة الجديدة
    //    لا يُرسَم ولا يُلتقَط بالماوس ولا يُحذَف — صفٌّ في القاعدة لا وجودَ
    //    له على الشاشة.
    widget.onChanged(clampLayoutToCanvas(
      next,
      capacityOf: (id) => widget.tableMeta[id]?.capacity ?? 4,
    ));
  }

  FloorPlanSectionLayout _withGeometry({
    List<FloorPlanTableGeometry>? tables,
    List<FloorPlanItemInput>? items,
  }) =>
      (
        sectionId: widget.layout.sectionId,
        sectionGlobalId: widget.layout.sectionGlobalId,
        canvasWidth: widget.layout.canvasWidth,
        canvasHeight: widget.layout.canvasHeight,
        originX: widget.layout.originX,
        originY: widget.layout.originY,
        tables: tables ?? widget.layout.tables,
        items: items ?? widget.layout.items,
      );

  // ───────────────────────────────────────────────────────────────────────
  // البناء
  // ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // ⚠️ **اللوحةُ `ltr` عمداً وإن كان التطبيقُ كلُّه `rtl`.** إحداثيّاتُ
    //    `Positioned.left` فيزيائيّةٌ لا منطقيّة، فخلطُ الاتّجاه يجعل ما
    //    يُحفَظ في القاعدة مختلفاً عمّا يراه من رسمه — وتقرأ القاعةُ
    //    معكوسةً على أيّ جهازٍ آخر.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          // المقاسُ يُقاس هنا لا يُفترَض: «ملاءمةُ الشاشة» تحتاج مقاسَ
          // النافذة الفعليَّ، و`MediaQuery` يعطي الشاشةَ كلَّها لا اللوحة.
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewport = Size(constraints.maxWidth, constraints.maxHeight);
              return InteractiveViewer(
            transformationController: _transform,
            boundaryMargin: const EdgeInsets.all(240),
            minScale: 0.2,
            maxScale: 3.0,
            constrained: false,
            child: SizedBox(
              width: _w + 40,
              height: _h + 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // أرضيّةُ الصالة — النقرُ عليها يمسح التحديد.
                  Positioned(
                    left: 0,
                    top: 0,
                    width: _w,
                    height: _h,
                    child: GestureDetector(
                      key: const Key('floor_plan_canvas_surface'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onSelectionChanged(<String>{}),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.02),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                        ),
                        child: widget.showGrid
                            ? CustomPaint(
                                painter: FloorPlanGridPainter(
                                  gridSize: widget.gridStep,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),

                  if (_guideX != null)
                    Positioned(
                      left: _guideX,
                      top: 0,
                      child: Container(
                        width: 1,
                        height: _h,
                        color: AppColors.primary.withValues(alpha: 0.6),
                      ),
                    ),
                  if (_guideY != null)
                    Positioned(
                      left: 0,
                      top: _guideY,
                      child: Container(
                        width: _w,
                        height: 1,
                        color: AppColors.primary.withValues(alpha: 0.6),
                      ),
                    ),

                  // المعالمُ تحتَ الطاولات: الجدارُ خلفيّةٌ لا يحجب طاولة.
                  for (final it in widget.layout.items)
                    if (it.globalId != null) _buildItem(it, it.globalId!),

                  for (final t in widget.layout.tables) _buildTable(t),

                  if (widget.enabled) _buildCanvasHandle(),
                ],
              ),
            ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ─── مقبضُ مقاس الصالة ───────────────────────────────────────────────
  Widget _buildCanvasHandle() {
    return Positioned(
      left: _w - 8,
      top: _h - 8,
      child: GestureDetector(
        key: const Key('floor_plan_canvas_handle'),
        onPanUpdate: (d) {
          final scale = _scale();
          final cur = _liveCanvas ?? Size(_w, _h);
          setState(() {
            _liveCanvas = Size(
              (cur.width + d.delta.dx / scale)
                  .clamp(kMinCanvasSide, kMaxCanvasSide),
              (cur.height + d.delta.dy / scale)
                  .clamp(kMinCanvasSide, kMaxCanvasSide),
            );
          });
        },
        onPanEnd: (_) => _commitCanvas(),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeDownRight,
          child: Tooltip(
            message: 'اسحب لتغيير مقاس الصالة',
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(PhosphorIconsBold.arrowsOutSimple,
                  size: 13, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  // ─── معلَم ────────────────────────────────────────────────────────────
  Widget _buildItem(FloorPlanItemInput it, String gid) {
    final key = itemSelectionKey(gid);
    final pos = _live[key] ?? Offset(it.x, it.y);
    final size = _liveSize[key] ?? Size(it.width, it.height);
    final selected = widget.selection.contains(key);
    final style = _itemStyle(it.kind);

    Widget body = Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: BorderRadius.circular(it.kind == 'pillar' ? 999 : 4),
        border: Border.all(
          color: selected ? AppColors.primary : style.stroke,
          width: selected ? 2.5 : 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: (it.label != null && it.label!.trim().isNotEmpty)
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                it.label!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: style.stroke,
                ),
              ),
            )
          : Icon(style.icon, size: 16, color: style.stroke),
    );

    if (it.rotation != 0) {
      body = Transform.rotate(angle: it.rotation * 3.1415926535 / 180, child: body);
    }

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            key: Key('floor_plan_item_$gid'),
            onTap: () => _toggleSelection(key, additive: false),
            onLongPress: () => _toggleSelection(key, additive: true),
            onPanUpdate: widget.enabled ? (d) => _drag(key, d.delta) : null,
            onPanEnd: widget.enabled ? (_) => _commitDrag() : null,
            child: MouseRegion(
              cursor: widget.enabled
                  ? SystemMouseCursors.grab
                  : SystemMouseCursors.basic,
              child: body,
            ),
          ),
          if (selected && widget.enabled)
            Positioned(
              left: size.width - 7,
              top: size.height - 7,
              child: GestureDetector(
                key: Key('floor_plan_item_resize_$gid'),
                onPanUpdate: (d) {
                  final scale = _scale();
                  final cur = _liveSize[key] ?? Size(it.width, it.height);
                  setState(() {
                    _liveSize[key] = Size(
                      (cur.width + d.delta.dx / scale)
                          .clamp(kMinItemSide, _w),
                      (cur.height + d.delta.dy / scale)
                          .clamp(kMinItemSide, _h),
                    );
                  });
                },
                onPanEnd: (_) => _commitResize(key),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _drag(String key, Offset delta) {
    final scale = _scale();
    final group = _dragGroup(key);
    final boxes = {for (final b in _allBoxes()) b.key: b};
    setState(() {
      for (final k in group) {
        final b = boxes[k];
        if (b == null) continue;
        final cur = _live[k] ?? Offset(b.x, b.y);
        _live[k] = Offset(
          (cur.dx + delta.dx / scale).clamp(0.0, (_w - b.w).clamp(0.0, _w)),
          (cur.dy + delta.dy / scale).clamp(0.0, (_h - b.h).clamp(0.0, _h)),
        );
      }
    });
    final moved = _live[key];
    if (moved != null && group.length == 1) _updateGuides(key, moved);
  }

  // ─── طاولة ────────────────────────────────────────────────────────────
  Widget _buildTable(FloorPlanTableGeometry t) {
    final key = tableSelectionKey(t.id);
    final meta = widget.tableMeta[t.id];
    final size = resolveTableSize(
      width: t.width,
      height: t.height,
      capacity: meta?.capacity ?? 4,
    );
    final pos = _live[key] ?? Offset(t.x, t.y);
    final selected = widget.selection.contains(key);
    final color = floorPlanStatusColor(meta?.status ?? 'available');
    final isCircle = t.shape == 'circle';

    Widget body = Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.16),
            color.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: isCircle
            ? BorderRadius.circular(999)
            : BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.primary : color.withValues(alpha: 0.7),
          width: selected ? 3 : 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            meta?.name ?? '#${t.id}',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
              fontSize: size.width > 100 ? 15 : 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            '${meta?.capacity ?? 4}',
            style: GoogleFonts.cairo(
              fontSize: 10,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );

    if (t.rotation != 0) {
      body = Transform.rotate(angle: t.rotation * 3.1415926535 / 180, child: body);
    }

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        key: Key('floor_plan_table_${t.id}'),
        onTap: () => _toggleSelection(key, additive: false),
        onLongPress: () => _toggleSelection(key, additive: true),
        onPanUpdate: widget.enabled ? (d) => _drag(key, d.delta) : null,
        onPanEnd: widget.enabled ? (_) => _commitDrag() : null,
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.grab
              : SystemMouseCursors.basic,
          child: body,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// أنماطُ المعالم والحالات
// ═══════════════════════════════════════════════════════════════════════

typedef FloorPlanItemStyle = ({Color fill, Color stroke, IconData icon});

FloorPlanItemStyle _itemStyle(String kind) => switch (kind) {
      'wall' => (
          fill: const Color(0xFF6B7280).withValues(alpha: 0.35),
          stroke: const Color(0xFF4B5563),
          icon: PhosphorIconsBold.minus,
        ),
      'door' => (
          fill: const Color(0xFF10B981).withValues(alpha: 0.14),
          stroke: const Color(0xFF059669),
          icon: PhosphorIconsBold.doorOpen,
        ),
      'bar' => (
          fill: const Color(0xFFF59E0B).withValues(alpha: 0.14),
          stroke: const Color(0xFFD97706),
          icon: PhosphorIconsBold.wine,
        ),
      'kitchen' => (
          fill: const Color(0xFFEF4444).withValues(alpha: 0.12),
          stroke: const Color(0xFFDC2626),
          icon: PhosphorIconsBold.cookingPot,
        ),
      'pillar' => (
          fill: const Color(0xFF6B7280).withValues(alpha: 0.45),
          stroke: const Color(0xFF374151),
          icon: PhosphorIconsBold.circle,
        ),
      _ => (
          fill: Colors.transparent,
          stroke: const Color(0xFF3B82F6),
          icon: PhosphorIconsBold.textT,
        ),
    };

/// لونُ حالة الطاولة — **نفسُ ألوان المصمّم الأصليّ** بحرفها، فلا تنقسم
/// لغةُ الألوان بين شاشةِ النادل وشاشةِ المُعِدّ.
Color floorPlanStatusColor(String status) => switch (status) {
      'available' => const Color(0xFF10B981),
      'reserved' => const Color(0xFFFF9800),
      'occupied' || 'seated' => const Color(0xFF14B8A6),
      'ordered' => const Color(0xFF3B82F6),
      'eating' => const Color(0xFF6366F1),
      'billing' => const Color(0xFFF59E0B),
      'cleaning' => const Color(0xFF6B7280),
      _ => const Color(0xFF9CA3AF),
    };

/// اسمُ نوعِ المعلَم بالعربيّة.
String floorPlanKindLabel(String kind) => switch (kind) {
      'wall' => 'جدار',
      'door' => 'باب',
      'bar' => 'بار',
      'kitchen' => 'مطبخ',
      'pillar' => 'عمود',
      'text' => 'نصّ',
      _ => kind,
    };

/// أيقونةُ نوعِ المعلَم — للشريط.
IconData floorPlanKindIcon(String kind) => _itemStyle(kind).icon;

// ═══════════════════════════════════════════════════════════════════════
// رسّامُ الشبكة
// ═══════════════════════════════════════════════════════════════════════

class FloorPlanGridPainter extends CustomPainter {
  FloorPlanGridPainter({required this.gridSize, required this.color});

  final double gridSize;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 🔴 **الحلقتان أدناه تزيدان `x += gridSize`** — فبقيمةٍ صفرٍ أو سالبةٍ
    //    أو `NaN` تدوران إلى الأبد **على خيط الواجهة**: الإطارُ لا يكتمل
    //    فتسودّ الشاشةُ بلا استثناءٍ يُرمى، أي بلا سطرٍ واحدٍ في اللوج.
    //    وهو نفسُ الحارس المكتوب في المصمّم الأصليّ.
    if (!(gridSize > 0) || !gridSize.isFinite) return;

    final dot = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..strokeWidth = 1
      ..style = PaintingStyle.fill;

    for (double x = 0; x <= size.width; x += gridSize) {
      for (double y = 0; y <= size.height; y += gridSize) {
        canvas.drawCircle(Offset(x, y), 1, dot);
      }
    }

    final major = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += gridSize * 4) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), major);
    }
    for (double y = 0; y <= size.height; y += gridSize * 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), major);
    }
  }

  @override
  bool shouldRepaint(covariant FloorPlanGridPainter old) =>
      old.gridSize != gridSize || old.color != color;
}

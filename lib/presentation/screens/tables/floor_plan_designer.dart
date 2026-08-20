import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/repository_providers.dart';
import '../../../domain/repositories/restaurant_repository.dart';
import '../../../data/database/database.dart';

/// Professional Floor Plan Designer V2
/// Modern drag-and-drop with visual grid, snap-to-grid, alignment guides,
/// toolbar with auto-layout, and zoom controls.
class FloorPlanDesigner extends ConsumerStatefulWidget {
  final int sectionId;
  final bool isEditMode;
  final Function(RestaurantTable) onTap;

  /// حصرُ المرسوم بحالةٍ واحدة — `null` تعني «الكلّ».
  ///
  /// **اختياريٌّ لا يغيّر السلوكَ الافتراضيّ:** `TablesScreen` القديمة لا
  /// تمرّره فتبقى كما هي. أُضيف لأن عمودَ الحالات في شاشة PicPos كان يُرشِّح
  /// فرعَ الشبكة وحدَه، فالمستخدمُ يهبط على الخريطة (`isVisualView` افتراضُها
  /// `true`) وينقر «متاحة» فلا يتغيّر شيء.
  ///
  /// ويُلغى في وضع التصميم: ترتيبُ خريطةٍ ناقصةٍ يخدع العين، وأدواتُ المحاذاة
  /// والتوزيع تعمل على القائمة كاملةً على أيّ حال.
  final String? statusFilter;

  const FloorPlanDesigner({
    super.key,
    required this.sectionId,
    required this.onTap,
    this.isEditMode = false,
    this.statusFilter,
  });

  @override
  ConsumerState<FloorPlanDesigner> createState() => _FloorPlanDesignerState();
}

class _FloorPlanDesignerState extends ConsumerState<FloorPlanDesigner> {
  final TransformationController _transformController =
      TransformationController();

  // Grid & canvas settings
  double _gridSize = 40.0;
  bool _showGrid = true;
  static const double _canvasW = 1200;
  static const double _canvasH = 900;

  // Drag state
  int? _draggingTableId;
  final Map<int, Offset> _livePositions = {}; // live positions during drag

  // Alignment guides
  double? _guideX;
  double? _guideY;

  // ─── المجرى مُخبَّأٌ بهُويّةٍ ثابتة ────────────────────────────────────
  //
  // كان `stream:` يُستدعى **داخل `build`**، وهو بعينه عطبُ شاشة المطبخ الذي
  // أُصلح في 3970bde9: كلُّ إعادةِ بناءٍ تخلق كائنَ Stream جديداً ⇒ يفسخ
  // `StreamBuilder` اشتراكَه ويشترك من جديد ⇒ استعلامُ قاعدةٍ جديدٌ ومرورٌ
  // بـ`ConnectionState.waiting`. وهذه الشاشةُ تُعيد البناءَ مع كلِّ سحبةِ
  // طاولةٍ وكلِّ تحريكٍ للأدلّة (`setState` في `_checkGuides` لكلِّ إطار).
  //
  // ولم يظهر الأثرُ لأن الودجتَ كانت بلا مستدعٍ؛ توصيلُ `TablesPicposScreen`
  // إيّاها يُحييه — فيُرفَع المجرى إلى الحالة قبل التوصيل لا بعده.
  late final IRestaurantRepository _repo;
  late Stream<List<RestaurantTable>> _tablesStream;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(restaurantRepositoryProvider);
    _tablesStream = _repo.watchTablesInSection(widget.sectionId);
  }

  @override
  void didUpdateWidget(covariant FloorPlanDesigner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // القسمُ وحدَه يبدّل المجرى. بدون هذا يبقى المضيفُ عالقاً على طاولات
    // القسم الأوّل عند تبديل التبويب — ثمنُ التخبئة إن نُسي.
    if (oldWidget.sectionId != widget.sectionId) {
      _tablesStream = _repo.watchTablesInSection(widget.sectionId);
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  // ─── Snap to grid ──────────────────────────────────────────────────
  double _snap(double v) => (_gridSize > 0)
      ? (v / _gridSize).roundToDouble() * _gridSize
      : v;

  // ─── Auto-layout: arrange tables in a neat grid ────────────────────
  Future<void> _autoLayout(List<RestaurantTable> tables) async {
    if (tables.isEmpty) return;
    final repo = ref.read(restaurantRepositoryProvider);
    final cols = (sqrt(tables.length)).ceil().clamp(2, 8);
    const padding = 60.0;
    const spacing = 160.0;

    for (int i = 0; i < tables.length; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      final x = padding + col * spacing;
      final y = padding + row * spacing;
      await repo.updateTablePosition(tables[i].id, x, y);
    }
    setState(() => _livePositions.clear());
  }

  // ─── Align all tables horizontally or vertically ───────────────────
  Future<void> _alignTables(List<RestaurantTable> tables, bool horizontal) async {
    if (tables.length < 2) return;
    final repo = ref.read(restaurantRepositoryProvider);

    if (horizontal) {
      // Align all to the average Y
      final avgY = tables.map((t) => t.y).reduce((a, b) => a + b) / tables.length;
      final snappedY = _snap(avgY);
      for (final t in tables) {
        await repo.updateTablePosition(t.id, t.x, snappedY);
      }
    } else {
      // Align all to the average X
      final avgX = tables.map((t) => t.x).reduce((a, b) => a + b) / tables.length;
      final snappedX = _snap(avgX);
      for (final t in tables) {
        await repo.updateTablePosition(t.id, snappedX, t.y);
      }
    }
    setState(() => _livePositions.clear());
  }

  // ─── Distribute tables evenly ──────────────────────────────────────
  Future<void> _distributeTables(List<RestaurantTable> tables, bool horizontal) async {
    if (tables.length < 3) return;
    final repo = ref.read(restaurantRepositoryProvider);

    final sorted = [...tables];
    if (horizontal) {
      sorted.sort((a, b) => a.x.compareTo(b.x));
      final minX = sorted.first.x;
      final maxX = sorted.last.x;
      final step = (maxX - minX) / (sorted.length - 1);
      for (int i = 0; i < sorted.length; i++) {
        await repo.updateTablePosition(sorted[i].id, _snap(minX + i * step), sorted[i].y);
      }
    } else {
      sorted.sort((a, b) => a.y.compareTo(b.y));
      final minY = sorted.first.y;
      final maxY = sorted.last.y;
      final step = (maxY - minY) / (sorted.length - 1);
      for (int i = 0; i < sorted.length; i++) {
        await repo.updateTablePosition(sorted[i].id, sorted[i].x, _snap(minY + i * step));
      }
    }
    setState(() => _livePositions.clear());
  }

  // Removed _savePosition as it is replaced by repository updateTablePosition

  // ─── Check alignment guides against other tables ───────────────────
  void _checkGuides(Offset pos, List<RestaurantTable> tables, int excludeId) {
    const threshold = 8.0;
    double? gx, gy;

    for (final t in tables) {
      if (t.id == excludeId) continue;
      final tx = _livePositions[t.id]?.dx ?? t.x;
      final ty = _livePositions[t.id]?.dy ?? t.y;

      // Center alignment
      if ((pos.dx - tx).abs() < threshold) gx = tx;
      if ((pos.dy - ty).abs() < threshold) gy = ty;
      // Center-to-center with 60px offset (side by side)
      if ((pos.dx - tx - 160).abs() < threshold) gx = tx + 160;
      if ((pos.dy - ty - 160).abs() < threshold) gy = ty + 160;
    }

    setState(() {
      _guideX = gx;
      _guideY = gy;
    });
  }

  // ─── Zoom controls ────────────────────────────────────────────────
  void _zoomIn() {
    final current = _transformController.value.clone();
    final scale = Matrix4.identity()..setEntry(0, 0, 1.2)..setEntry(1, 1, 1.2)..setEntry(2, 2, 1.0);
    _transformController.value = current.multiplied(scale);
  }

  void _zoomOut() {
    final current = _transformController.value.clone();
    final scale = Matrix4.identity()..setEntry(0, 0, 0.83)..setEntry(1, 1, 0.83)..setEntry(2, 2, 1.0);
    _transformController.value = current.multiplied(scale);
  }

  void _zoomReset() {
    _transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo;

    return StreamBuilder<List<RestaurantTable>>(
      stream: _tablesStream,
      builder: (context, snapshot) {
        final tables = snapshot.data ?? [];
        // المرسومُ وحدَه يُرشَّح. أدواتُ الشريط (`_autoLayout` والمحاذاةُ
        // والتوزيع) ورفاقُ الالتقاط في `_buildDraggableTable` تبقى على
        // [tables] كاملةً — وإلّا رتّب زرُّ «تنظيم تلقائي» جزءاً من القسم
        // فوق جزءٍ مخفيٍّ منه.
        final visible = (widget.statusFilter == null || widget.isEditMode)
            ? tables
            : [
                for (final t in tables)
                  if (t.status == widget.statusFilter) t,
              ];

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              // ── Toolbar (edit mode only) ──
              if (widget.isEditMode) _buildToolbar(tables),

              // ── Canvas ──
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      boundaryMargin: const EdgeInsets.all(200),
                      minScale: 0.3,
                      maxScale: 3.0,
                      constrained: false,
                      child: SizedBox(
                        width: _canvasW,
                        height: _canvasH,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Grid background
                            if (_showGrid)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _GridPainter(gridSize: _gridSize),
                                ),
                              ),

                            // Alignment guides
                            if (_guideX != null)
                              Positioned(
                                left: _guideX,
                                top: 0,
                                child: Container(
                                  width: 1,
                                  height: _canvasH,
                                  color: AppColors.primary.withValues(alpha: 0.5),
                                ),
                              ),
                            if (_guideY != null)
                              Positioned(
                                left: 0,
                                top: _guideY,
                                child: Container(
                                  width: _canvasW,
                                  height: 1,
                                  color: AppColors.primary.withValues(alpha: 0.5),
                                ),
                              ),

                            // Tables
                            ...visible.map((table) => _buildDraggableTable(
                                  repo, table, tables)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Toolbar ────────────────────────────────────────────────────────
  Widget _buildToolbar(List<RestaurantTable> tables) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          _toolBtn(
            icon: PhosphorIconsBold.gridFour,
            label: 'تنظيم تلقائي',
            color: AppColors.primary,
            onTap: () => _autoLayout(tables),
          ),
          _divider(),
          _toolBtn(
            icon: PhosphorIconsBold.alignCenterHorizontal,
            label: 'محاذاة أفقي',
            onTap: () => _alignTables(tables, true),
          ),
          _toolBtn(
            icon: PhosphorIconsBold.alignCenterVertical,
            label: 'محاذاة عمودي',
            onTap: () => _alignTables(tables, false),
          ),
          _divider(),
          _toolBtn(
            icon: PhosphorIconsBold.arrowsOutLineHorizontal,
            label: 'توزيع أفقي',
            onTap: () => _distributeTables(tables, true),
          ),
          _toolBtn(
            icon: PhosphorIconsBold.arrowsOutLineVertical,
            label: 'توزيع عمودي',
            onTap: () => _distributeTables(tables, false),
          ),
          _divider(),
          _toolBtn(
            icon: PhosphorIconsBold.magnifyingGlassPlus,
            label: '+',
            onTap: _zoomIn,
          ),
          _toolBtn(
            icon: PhosphorIconsBold.magnifyingGlassMinus,
            label: '-',
            onTap: _zoomOut,
          ),
          _toolBtn(
            icon: PhosphorIconsBold.arrowsOut,
            label: 'إعادة',
            onTap: _zoomReset,
          ),
          _divider(),
          _toolBtn(
            icon: _showGrid
                ? PhosphorIconsBold.gridFour
                : PhosphorIconsBold.squaresFour,
            label: _showGrid ? 'إخفاء الشبكة' : 'إظهار الشبكة',
            onTap: () => setState(() => _showGrid = !_showGrid),
          ),
          // Grid size selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<double>(
              value: _gridSize,
              dropdownColor: const Color(0xFF1E293B),
              underline: const SizedBox(),
              isDense: true,
              style: GoogleFonts.cairo(fontSize: 11, color: Colors.white70),
              items: const [
                DropdownMenuItem(value: 20, child: Text('20px')),
                DropdownMenuItem(value: 40, child: Text('40px')),
                DropdownMenuItem(value: 60, child: Text('60px')),
              ],
              onChanged: (v) => setState(() => _gridSize = v ?? 40),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolBtn({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (color ?? Colors.white).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (color ?? Colors.white).withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color ?? Colors.white70),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: color ?? Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        color: Colors.white.withValues(alpha: 0.08),
      );

  // ─── Draggable Table Widget ────────────────────────────────────────
  Widget _buildDraggableTable(
    IRestaurantRepository repo,
    RestaurantTable table,
    List<RestaurantTable> allTables,
  ) {
    final pos = _livePositions[table.id] ?? Offset(table.x, table.y);
    final isDragging = _draggingTableId == table.id;
    final color = _getStatusColor(table.status);
    final isCircle = table.shape == 'circle';
    // Size based on capacity
    final size = (60.0 + (table.capacity * 8.0)).clamp(80.0, 140.0);

    Widget tableWidget = AnimatedContainer(
      duration: isDragging
          ? Duration.zero
          : const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: isDragging ? 0.25 : 0.12),
            color.withValues(alpha: isDragging ? 0.15 : 0.04),
          ],
        ),
        borderRadius: isCircle
            ? BorderRadius.circular(size / 2)
            : BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: isDragging ? 1 : 0.6),
          width: isDragging ? 2.5 : 1.5,
        ),
        boxShadow: [
          if (isDragging)
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 24,
              spreadRadius: 4,
            )
          else
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 8,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.isEditMode ? null : () => widget.onTap(table),
          borderRadius: isCircle
              ? BorderRadius.circular(size / 2)
              : BorderRadius.circular(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Table name
              Text(
                table.name,
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontSize: size > 100 ? 16 : 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // Capacity
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsBold.users, size: 10, color: color.withValues(alpha: 0.6)),
                  const SizedBox(width: 3),
                  Text(
                    '${table.capacity}',
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: color.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              // Status badge
              if (table.status != 'available')
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _statusLabel(table.status),
                    style: GoogleFonts.cairo(
                      fontSize: 8,
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              // Edit mode indicator
              if (widget.isEditMode)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    PhosphorIconsBold.arrowsOutCardinal,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // In view mode → just position
    if (!widget.isEditMode) {
      return Positioned(left: pos.dx, top: pos.dy, child: tableWidget);
    }

    // In edit mode → GestureDetector for drag
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _draggingTableId = table.id;
            _livePositions[table.id] = pos;
          });
        },
        onPanUpdate: (details) {
          if (_draggingTableId != table.id) return;

          // Get the current scale from the transformation matrix
          final scale = _transformController.value.getMaxScaleOnAxis();
          final scaledDelta = details.delta / scale;

          final current = _livePositions[table.id] ?? pos;
          final newPos = Offset(
            (current.dx + scaledDelta.dx).clamp(0, _canvasW - size),
            (current.dy + scaledDelta.dy).clamp(0, _canvasH - size),
          );

          _checkGuides(newPos, allTables, table.id);

          setState(() {
            _livePositions[table.id] = newPos;
          });
        },
        onPanEnd: (details) async {
          if (_draggingTableId != table.id) return;
          final current = _livePositions[table.id] ?? pos;
          // Snap to guide if close, otherwise snap to grid
          final snapX = _guideX != null && (current.dx - _guideX!).abs() < 12
              ? _guideX!
              : _snap(current.dx);
          final snapY = _guideY != null && (current.dy - _guideY!).abs() < 12
              ? _guideY!
              : _snap(current.dy);

          await repo.updateTablePosition(table.id, snapX, snapY);

          setState(() {
            _draggingTableId = null;
            _guideX = null;
            _guideY = null;
            _livePositions.remove(table.id);
          });
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: tableWidget,
        ),
      ),
    );
  }

  // ─── Status helpers ────────────────────────────────────────────────
  Color _getStatusColor(String status) {
    switch (status) {
      case 'available':
        return const Color(0xFF10B981);
      case 'reserved':
        return Colors.orange;
      case 'occupied':
      case 'seated':
        return const Color(0xFF14B8A6);
      case 'ordered':
        return const Color(0xFF3B82F6);
      case 'eating':
        return const Color(0xFF6366F1);
      case 'billing':
        return const Color(0xFFF59E0B);
      case 'cleaning':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'reserved':
        return 'محجوزة';
      case 'occupied':
      case 'seated':
        return 'مشغولة';
      case 'ordered':
        return 'طلب';
      case 'eating':
        return 'تناول';
      case 'billing':
        return 'حساب';
      case 'cleaning':
        return 'تنظيف';
      default:
        return status;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Grid Painter — draws dotted grid on canvas
// ═══════════════════════════════════════════════════════════════════════
class _GridPainter extends CustomPainter {
  final double gridSize;

  _GridPainter({required this.gridSize});

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;

    // Draw dots at grid intersections
    for (double x = 0; x <= size.width; x += gridSize) {
      for (double y = 0; y <= size.height; y += gridSize) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }

    // Draw subtle axis lines at every 4th grid line
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 0.5;

    for (double x = 0; x <= size.width; x += gridSize * 4) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y <= size.height; y += gridSize * 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.gridSize != gridSize;
}

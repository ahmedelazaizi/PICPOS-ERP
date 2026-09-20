// ═══════════════════════════════════════════════════════════════════════════
// FLOOR PLAN LAYOUT — حسابُ مخطَّط القاعة الخالص (قسمُ ٧)
// ═══════════════════════════════════════════════════════════════════════════
//
// ملفٌّ **بلا قاعدةٍ ولا ودجت**: يستورد `dart:math` وحدَه. وموضعُه
// `domain/models` لأنّ `presentation_db_import_guard` يمنع ملفَّ عرضٍ جديداً
// من استيراد `data/database` — والحسابُ هنا يخدم المصمّمَ وخريطةَ النادل
// معاً، فلو عاش في أحدهما لانقسم عند أوّل تعديل.

import 'dart:math' as math;

// ─────────────────────────────────────────────────────────────────────────
// ثوابتُ الحدود
// ─────────────────────────────────────────────────────────────────────────

/// أنواعُ معالم القاعة — **مجموعةٌ مغلقة**.
///
/// ⚠️ ونوعٌ خارجَها ليس خطأً مرئيّاً: الرسّامُ لا يعرف كيف يرسمه فيسقط
///    المعلَمُ من اللوحة صامتاً — جدارٌ حُفظ ولا يُرى. فالتحقّقُ عند الكتابة
///    لا عند الرسم.
const Set<String> kFloorPlanItemKinds = <String>{
  'wall',
  'door',
  'bar',
  'kitchen',
  'pillar',
  'text',
};

/// لوحةُ القسم حين لا مقاسَ محفوظ — **نفسُ ثابتَي المصمّم القديم**
/// (`_canvasW`/`_canvasH`)، فالأقسامُ القائمةُ لا تتبدّل تحت المستخدم.
const double kDefaultCanvasWidth = 1200;
const double kDefaultCanvasHeight = 900;

const double kMinCanvasSide = 400;
const double kMaxCanvasSide = 6000;

/// أصغرُ ضلعٍ لمعلَم — أقلُّ منه نقطةٌ لا تُلتقَط بالماوس فلا تُحذَف.
const double kMinItemSide = 8;

/// يطابق `withLength(max: 60)` على `FloorPlanItems.label`.
const int kFloorPlanLabelMax = 60;

/// خطواتُ الشبكة المتاحة — و**الصفرُ ليس منها**: `_GridPainter.paint` يدور
/// `x += gridSize` فيتجمّد الإطار. يحرسها [snapToStep] أيضاً.
const List<double> kFloorPlanGridSteps = <double>[20, 40, 60];

/// الفجوةُ بين قسمَين في الرصف التلقائيّ لأرضيّة المحلّ.
const double kSectionGap = 80;

// ─────────────────────────────────────────────────────────────────────────
// الأنواع
// ─────────────────────────────────────────────────────────────────────────

/// معلَمُ قاعةٍ كما يراه المصمّم — `id`/`globalId` فارغان لمعلَمٍ لم يُحفظ.
typedef FloorPlanItemInput = ({
  int? id,
  String? globalId,
  String kind,
  double x,
  double y,
  double width,
  double height,
  double rotation,
  String? label,
});

/// هندسةُ الطاولة وحدَها — لا اسمَ ولا حالةَ ولا سعة.
///
/// ⚠️ **والحالةُ غائبةٌ عمداً**: المصمّمُ يحفظ مواضعَ، وطاولةٌ تُسحَب بينما
///    عليها طلبٌ يجب ألّا تعود «متاحةً» لأنّ الحمولةَ حملت حالةً قديمة.
typedef FloorPlanTableGeometry = ({
  int id,
  String? globalId,
  double x,
  double y,
  double? width,
  double? height,
  double rotation,
  String shape,
});

/// مخطَّطُ قسمٍ كاملاً — **وحدةُ الحفظ**.
///
/// المخطَّطُ يُحرَّر كلاًّ ويُحفَظ مرّةً: هذا ما يجعل «تراجع» ممكناً أصلاً
/// (المصمّمُ القديم كان يكتب في القاعدة عند نهاية كلّ سحبة، فلا شيءَ
/// يُتراجَع عنه)، وهو ما يجعل الحفظَ يعبر السلكَ **مستنداً واحداً** كسائر
/// الكتابة في هذا المستودع.
typedef FloorPlanSectionLayout = ({
  int sectionId,
  String? sectionGlobalId,
  double canvasWidth,
  double canvasHeight,
  double originX,
  double originY,
  List<FloorPlanTableGeometry> tables,
  List<FloorPlanItemInput> items,
});

/// صندوقُ قسمٍ على أرضيّة المحلّ — لنظرةِ المحلّ كلِّه.
typedef FloorPlanSectionBox = ({
  int sectionId,
  double originX,
  double originY,
  double width,
  double height,
});

// ─────────────────────────────────────────────────────────────────────────
// مقاسُ الطاولة
// ─────────────────────────────────────────────────────────────────────────

/// المقاسُ المشتقُّ من السعة — سلوكُ ما قبل v174 بحرفه.
///
/// 🔴 **وهو عينُ ما اشتكى منه المالك — والقياسُ يصحّح تشخيصَ الخطّة.**
///    كتبت الخطّةُ «فطاولتا ٢ و٣ متطابقتان»، وليس كذلك: ٢ تُعطي ٧٦ فتُقَصّ
///    إلى ٨٠، و٣ تُعطي ٨٤ فتمرّ كما هي.
///    **والانطباقُ الحقيقيُّ عند الطرفَين**: السعتان ١ و٢ تُقصّان إلى ٨٠
///    معاً، **وكلُّ سعةٍ من عشرةٍ فصاعداً تُعطي ١٤٠** — فطاولةُ عشرةٍ
///    وطاولةُ عشرين واحدةٌ على الخريطة، وهو الطرفُ الأوجع.
///    ولا سبيلَ فيه لطاولةٍ مستطيلةٍ طويلةٍ أصلاً (الضلعان سواء).
///    يبقى **احتياطاً** لا أصلاً: الصفوفُ القائمةُ بلا عرضٍ محفوظ.
double legacyTableSide(int capacity) =>
    (60.0 + capacity * 8.0).clamp(80.0, 140.0);

/// مقاسُ الطاولة للرسم — المحفوظُ إن وُجد، وإلّا الاشتقاق.
///
/// والعرضُ والارتفاعُ **مستقلّان**: طاولةٌ حُفظ عرضُها ولم يُحفظ ارتفاعُها
/// تأخذ الاشتقاقَ للارتفاع وحدَه.
({double width, double height}) resolveTableSize({
  required double? width,
  required double? height,
  required int capacity,
}) {
  final side = legacyTableSide(capacity);
  final w = (width != null && width > 0) ? width : side;
  final h = (height != null && height > 0) ? height : side;
  return (width: w, height: h);
}

// ─────────────────────────────────────────────────────────────────────────
// الالتقاطُ بالشبكة
// ─────────────────────────────────────────────────────────────────────────

/// تقريبٌ إلى أقرب خطوةٍ — **ويعيد القيمةَ كما هي** إن كانت الخطوةُ غيرَ
/// صالحة.
///
/// ⚠️ الحارسُ `isFinite` ليس تزيُّداً: خطوةٌ `NaN` تجعل القسمةَ `NaN`
///    فيصير الموضعُ `NaN`، و`Positioned` بموضعٍ `NaN` يرمي في الرسم.
double snapToStep(double value, double step) {
  if (!(step > 0) || !step.isFinite) return value;
  if (!value.isFinite) return value;
  return (value / step).roundToDouble() * step;
}

// ─────────────────────────────────────────────────────────────────────────
// التحقّق
// ─────────────────────────────────────────────────────────────────────────

/// تحقّقُ مقاس اللوحة — يعيد رسالةً عربيّةً أو `null`.
String? validateCanvasSize({required double width, required double height}) {
  if (!width.isFinite || !height.isFinite) {
    return 'مقاسُ الصالة غيرُ صالح';
  }
  if (width < kMinCanvasSide || height < kMinCanvasSide) {
    return 'أصغرُ مقاسٍ للصالة ${kMinCanvasSide.toInt()} × '
        '${kMinCanvasSide.toInt()}';
  }
  if (width > kMaxCanvasSide || height > kMaxCanvasSide) {
    return 'أكبرُ مقاسٍ للصالة ${kMaxCanvasSide.toInt()} × '
        '${kMaxCanvasSide.toInt()}';
  }
  return null;
}

/// تحقّقُ معلَمٍ واحد.
String? validateFloorPlanItem(FloorPlanItemInput item) {
  if (!kFloorPlanItemKinds.contains(item.kind)) {
    return 'نوعُ معلَمٍ غيرُ معروف: ${item.kind}';
  }
  if (!item.x.isFinite ||
      !item.y.isFinite ||
      !item.width.isFinite ||
      !item.height.isFinite ||
      !item.rotation.isFinite) {
    return 'إحداثيّاتُ المعلَم غيرُ صالحة';
  }
  if (item.width < kMinItemSide || item.height < kMinItemSide) {
    return 'أصغرُ مقاسٍ للمعلَم ${kMinItemSide.toInt()}';
  }
  final label = item.label;
  if (item.kind == 'text' && (label == null || label.trim().isEmpty)) {
    return 'معلَمُ النصّ بلا نصّ — اكتبه أو احذفه';
  }
  if (label != null && label.length > kFloorPlanLabelMax) {
    return 'نصُّ المعلَم أطولُ من $kFloorPlanLabelMax حرفاً';
  }
  return null;
}

/// تحقّقُ المخطَّط كلِّه — اللوحةُ ثمّ كلُّ معلَم.
///
/// ⚠️ **ولا يتحقّق من وقوع المعلَم داخلَ اللوحة**: [clampLayoutToCanvas] هو
///    الذي يُدخله، ورفضُ الحفظ لأنّ جداراً خرج بعشرة بكسلاتٍ بعد تصغير
///    الصالة يُضيّع عملَ المستخدم كلَّه بدل أن يُصلحه.
String? validateFloorPlanLayout(FloorPlanSectionLayout layout) {
  final bad = validateCanvasSize(
    width: layout.canvasWidth,
    height: layout.canvasHeight,
  );
  if (bad != null) return bad;
  for (final item in layout.items) {
    final e = validateFloorPlanItem(item);
    if (e != null) return e;
  }
  if (!layout.originX.isFinite || !layout.originY.isFinite) {
    return 'موضعُ القسم على أرضيّة المحلّ غيرُ صالح';
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────
// الحصرُ داخلَ اللوحة
// ─────────────────────────────────────────────────────────────────────────

double _clampIn(double v, double lo, double hi) =>
    hi <= lo ? lo : v.clamp(lo, hi);

/// يُدخل كلَّ معلَمٍ وكلَّ طاولةٍ داخلَ اللوحة.
///
/// 🔴 **وهذا ليس تجميلاً.** تصغيرُ الصالة بسحب حافّتها يترك ما وراء الحافّة
///    **خارجَ اللوحة**: لا يُرسَم، ولا يُلتقَط بالماوس، ولا يُحذَف — طاولةٌ
///    في القاعدة لا وجودَ لها على الشاشة. فالحصرُ يقع مع كلّ تغييرِ مقاس.
FloorPlanSectionLayout clampLayoutToCanvas(
  FloorPlanSectionLayout layout, {
  required int Function(int tableId) capacityOf,
}) {
  final w = layout.canvasWidth;
  final h = layout.canvasHeight;

  final tables = <FloorPlanTableGeometry>[
    for (final t in layout.tables)
      () {
        final size = resolveTableSize(
          width: t.width,
          height: t.height,
          capacity: capacityOf(t.id),
        );
        return (
          id: t.id,
          globalId: t.globalId,
          x: _clampIn(t.x, 0, w - size.width),
          y: _clampIn(t.y, 0, h - size.height),
          width: t.width,
          height: t.height,
          rotation: t.rotation,
          shape: t.shape,
        );
      }(),
  ];

  final items = <FloorPlanItemInput>[
    for (final it in layout.items)
      () {
        final iw = math.min(it.width, w);
        final ih = math.min(it.height, h);
        return (
          id: it.id,
          globalId: it.globalId,
          kind: it.kind,
          x: _clampIn(it.x, 0, w - iw),
          y: _clampIn(it.y, 0, h - ih),
          width: iw,
          height: ih,
          rotation: it.rotation,
          label: it.label,
        );
      }(),
  ];

  return (
    sectionId: layout.sectionId,
    sectionGlobalId: layout.sectionGlobalId,
    canvasWidth: w,
    canvasHeight: h,
    originX: layout.originX,
    originY: layout.originY,
    tables: tables,
    items: items,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// نظرةُ المحلّ كلِّه
// ─────────────────────────────────────────────────────────────────────────

/// مواضعُ افتراضيّةٌ للأقسام التي لا موضعَ محفوظاً لها.
///
/// 🔴 **بلا هذا تُرصَّ كلُّ الأقسام عند `(0, 0)`** — أي تنطبق تماماً الواحدةُ
///    فوق الأخرى، فتبدو نظرةُ المحلّ قسماً واحداً وتُقرأ على أنّها عطبُ
///    عرضٍ لا نقصُ بيانات. فالأقسامُ بلا موضعٍ تُرصَف **صفّاً أفقيّاً**
///    بفجوةٍ ثابتة، ويبقى للمستخدم أن يسحبها.
List<FloorPlanSectionBox> resolveSectionOrigins(
  List<
          ({
            int sectionId,
            double? originX,
            double? originY,
            double width,
            double height
          })>
      sections,
) {
  final out = <FloorPlanSectionBox>[];
  var cursor = 0.0;
  for (final s in sections) {
    final ox = s.originX;
    final oy = s.originY;
    final hasOrigin =
        ox != null && oy != null && ox.isFinite && oy.isFinite;
    final x = hasOrigin ? ox : cursor;
    final y = hasOrigin ? oy : 0.0;
    if (!hasOrigin) cursor += s.width + kSectionGap;
    out.add((
      sectionId: s.sectionId,
      originX: x,
      originY: y,
      width: s.width,
      height: s.height,
    ));
  }
  return out;
}

/// امتدادُ أرضيّة المحلّ — يشمل الأقسامَ كلَّها.
({double width, double height}) shopExtent(List<FloorPlanSectionBox> boxes) {
  if (boxes.isEmpty) {
    return (width: kDefaultCanvasWidth, height: kDefaultCanvasHeight);
  }
  var maxX = 0.0;
  var maxY = 0.0;
  for (final b in boxes) {
    maxX = math.max(maxX, b.originX + b.width);
    maxY = math.max(maxY, b.originY + b.height);
  }
  return (width: math.max(maxX, 1), height: math.max(maxY, 1));
}

/// معاملُ «ملاءمةِ الشاشة».
///
/// ⚠️ **ولا يكبّر فوق `max`**: قاعةٌ صغيرةٌ في شاشةٍ كبيرةٍ كانت تُنفَخ إلى
///    ثلاثة أضعافٍ فتبدو الطاولاتُ عملاقةً — «الملاءمة» تعني أن يُرى الكلُّ
///    لا أن يُملأ الفراغ.
double fitScale({
  required double contentWidth,
  required double contentHeight,
  required double viewWidth,
  required double viewHeight,
  double max = 1.0,
}) {
  if (!(contentWidth > 0) || !(contentHeight > 0)) return max;
  if (!(viewWidth > 0) || !(viewHeight > 0)) return max;
  final s = math.min(viewWidth / contentWidth, viewHeight / contentHeight);
  if (!s.isFinite || s <= 0) return max;
  return math.min(s, max);
}

// ─────────────────────────────────────────────────────────────────────────
// المحاذاةُ والتوزيع
// ─────────────────────────────────────────────────────────────────────────

/// صندوقٌ محدَّدٌ بمفتاحه — لا يعرف أطاولةٌ هو أم معلَم.
typedef FloorPlanBox = ({String key, double x, double y});

/// يحاذي المحدَّد إلى **متوسّطه**.
///
/// 🔴 **وعلى المحدَّد وحدَه لا على الكلّ.** المصمّمُ القديم كان يحاذي كلَّ
///    طاولات القسم مهما اختير المستخدم — فمن أراد صفَّ ثلاثِ طاولاتٍ على
///    الجدار وجد القاعةَ كلَّها قد انسحبت معها، **ولا تراجعَ يُعيدها**.
///    وهو بعينه سببُ «تحديدٍ متعدّد» في قائمة أدوات الخطّة.
List<FloorPlanBox> alignBoxes(
  List<FloorPlanBox> boxes, {
  required bool horizontal,
}) {
  if (boxes.length < 2) return boxes;
  if (horizontal) {
    final avg = boxes.map((b) => b.y).reduce((a, b) => a + b) / boxes.length;
    return [for (final b in boxes) (key: b.key, x: b.x, y: avg)];
  }
  final avg = boxes.map((b) => b.x).reduce((a, b) => a + b) / boxes.length;
  return [for (final b in boxes) (key: b.key, x: avg, y: b.y)];
}

/// يوزّع المحدَّد بتباعدٍ متساوٍ بين طرفَيه.
///
/// ⚠️ **والطرفان يبقيان مكانَهما**: التوزيعُ يملأ ما بينهما، ولو تحرّكا
///    لانزلق الصفُّ كلُّه عن الجدار الذي حوذي عليه قبل سطرٍ واحد.
List<FloorPlanBox> distributeBoxes(
  List<FloorPlanBox> boxes, {
  required bool horizontal,
}) {
  if (boxes.length < 3) return boxes;
  final sorted = [...boxes]
    ..sort((a, b) => horizontal ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  final first = horizontal ? sorted.first.x : sorted.first.y;
  final last = horizontal ? sorted.last.x : sorted.last.y;
  final step = (last - first) / (sorted.length - 1);
  return [
    for (var i = 0; i < sorted.length; i++)
      horizontal
          ? (key: sorted[i].key, x: first + i * step, y: sorted[i].y)
          : (key: sorted[i].key, x: sorted[i].x, y: first + i * step),
  ];
}

// ─────────────────────────────────────────────────────────────────────────
// مكدّسُ التراجع
// ─────────────────────────────────────────────────────────────────────────

/// مكدّسُ تراجعٍ/إعادةٍ عامّ — **أهمُّ أداةٍ في المصمّم** بنصِّ الخطّة:
/// بلاها كلُّ سحبةٍ خطأٌ دائم.
///
/// وهو خالصٌ بلا ودجت ليُختبَر بلا شجرة.
class FloorPlanUndoStack<T> {
  FloorPlanUndoStack(T initial, {this.limit = 50}) : _current = initial;

  final int limit;
  final List<T> _past = <T>[];
  final List<T> _future = <T>[];
  T _current;

  T get current => _current;
  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;
  int get depth => _past.length;

  /// خطوةٌ جديدة — **وتمحو ما بعدها**.
  ///
  /// ⚠️ بلا محو `_future` يصير «إعادة» بعد تعديلٍ جديدٍ قفزةً إلى فرعٍ
  ///    مهجور: المستخدمُ يتراجع، يرسم شيئاً آخر، ثمّ «يُعيد» فيجد رسماً لم
  ///    يرسمه قطّ في هذا المسار.
  void push(T next) {
    _past.add(_current);
    if (_past.length > limit) _past.removeAt(0);
    _current = next;
    _future.clear();
  }

  T undo() {
    if (_past.isEmpty) return _current;
    _future.add(_current);
    _current = _past.removeLast();
    return _current;
  }

  T redo() {
    if (_future.isEmpty) return _current;
    _past.add(_current);
    _current = _future.removeLast();
    return _current;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// السلك
// ─────────────────────────────────────────────────────────────────────────

double _num(Object? v, [double fallback = 0]) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : fallback;
  }
  if (v is String) {
    final p = double.tryParse(v);
    if (p != null && p.isFinite) return p;
  }
  return fallback;
}

/// يمنح كلَّ معلَمٍ بلا معرِّفٍ عالميٍّ معرِّفاً — **قبل أيّ كتابة**.
///
/// 🔴 **والترتيبُ هو كلُّ الفائدة.** المخطَّطُ يُكتَب مرّتَين في وضع العميل:
///    نسخةٌ محلّيّةٌ ليرى المستخدمُ أثرَه فوراً، وحمولةٌ تمضي إلى الخادم.
///    فلو وُلِّد المعرِّفُ في كلٍّ منهما على حدة لحمل الصفّان **هويّتَين
///    مختلفتَين لمعلَمٍ واحد** — فيعود المعلَمُ مضاعَفاً عند أوّل سحبِ دلتا،
///    وهو عينُ عطبِ سطور المشتريات الذي أُصلح في الميزة ٠٤٣.
FloorPlanSectionLayout stampMissingGlobalIds(
  FloorPlanSectionLayout layout,
  String Function() newGlobalId,
) {
  return (
    sectionId: layout.sectionId,
    sectionGlobalId: layout.sectionGlobalId,
    canvasWidth: layout.canvasWidth,
    canvasHeight: layout.canvasHeight,
    originX: layout.originX,
    originY: layout.originY,
    tables: layout.tables,
    items: <FloorPlanItemInput>[
      for (final it in layout.items)
        (
          id: it.id,
          globalId: (it.globalId == null || it.globalId!.isEmpty)
              ? newGlobalId()
              : it.globalId,
          kind: it.kind,
          x: it.x,
          y: it.y,
          width: it.width,
          height: it.height,
          rotation: it.rotation,
          label: it.label,
        ),
    ],
  );
}

/// هل تصلح هذه الحمولةُ للعبور إلى الخادم؟
///
/// 🔴 **القسمُ والطاولاتُ تعبر بمعرِّفها العالميّ لا برقمها المحلّيّ** —
///    ورقمُ صفٍّ محلّيٌّ قد يخصّ قسماً آخرَ تماماً على الخادم. فصفٌّ بلا
///    معرِّفٍ عالميٍّ **لا يُرسَل صامتاً**: الإرسالُ حينها إمّا يُهمَل
///    فيظنّ المستخدمُ أنّه حفظ، أو يُصيب قسماً غيرَ قسمه.
///
/// ويُنادى في وضع العميل وحدَه: في التشغيل المنفرد لا سلكَ ولا حاجةَ
/// لمعرِّفٍ عالميّ.
String? validateFloorPlanWireIdentity(FloorPlanSectionLayout layout) {
  final sg = layout.sectionGlobalId;
  if (sg == null || sg.isEmpty) {
    return 'القسمُ بلا معرِّفٍ عالميّ — لم يصل هذا الجهازَ من الخادم بعد، '
        'فالمخطَّطُ يُحفَظ على الخادم أو بعد أوّل مزامنة';
  }
  for (final t in layout.tables) {
    final g = t.globalId;
    if (g == null || g.isEmpty) {
      return 'طاولةٌ بلا معرِّفٍ عالميّ — أنشئت على هذا الجهاز ولم تُزامَن بعد';
    }
  }
  return null;
}

/// حمولةُ حفظِ المخطَّط — **بلا `id` محلّيٍّ لمعلَمٍ أو طاولة**.
///
/// 🔴 رقمُ الصفّ المحلّيُّ لا يعبر الأجهزة: هو عينُ الدرس الذي دفعته
///    المرحلةُ الثامنةُ في وكيل التخليص. فالمعرِّفُ العالميُّ وحدَه يسافر،
///    ومعلَمٌ بلا معرِّفٍ عالميٍّ **جديدٌ** على الطرف الآخر.
Map<String, dynamic> floorPlanLayoutToJson(FloorPlanSectionLayout layout) {
  return <String, dynamic>{
    'sectionGlobalId': layout.sectionGlobalId,
    'canvasWidth': layout.canvasWidth,
    'canvasHeight': layout.canvasHeight,
    'originX': layout.originX,
    'originY': layout.originY,
    'tables': <Map<String, dynamic>>[
      for (final t in layout.tables)
        <String, dynamic>{
          'globalId': t.globalId,
          'x': t.x,
          'y': t.y,
          'width': t.width,
          'height': t.height,
          'rotation': t.rotation,
          'shape': t.shape,
        },
    ],
    'items': <Map<String, dynamic>>[
      for (final it in layout.items)
        <String, dynamic>{
          'globalId': it.globalId,
          'kind': it.kind,
          'x': it.x,
          'y': it.y,
          'width': it.width,
          'height': it.height,
          'rotation': it.rotation,
          'label': it.label,
        },
    ],
  };
}

/// قراءةُ الحمولة على الطرف الآخر — `sectionId` و`tableId` يُحلّان هناك
/// بالمعرِّف العالميّ، فيُمرَّران إلى هنا محلولَين.
///
/// ⚠️ **وطاولةٌ لم يُحلَّ معرِّفُها تُسقَط**: `resolveTableId` يعيد `null`
///    فتُطرَح من القائمة. وكتابةُ هندسةٍ على `id = 0` كانت ستُحرّك طاولةً
///    أخرى أو تفشل صامتةً.
FloorPlanSectionLayout floorPlanLayoutFromJson(
  Map<String, dynamic> json, {
  required int sectionId,
  required int? Function(String? globalId) resolveTableId,
}) {
  final rawTables = json['tables'];
  final rawItems = json['items'];

  final tables = <FloorPlanTableGeometry>[];
  if (rawTables is List) {
    for (final raw in rawTables) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final gid = m['globalId'] as String?;
      final id = resolveTableId(gid);
      if (id == null) continue;
      tables.add((
        id: id,
        globalId: gid,
        x: _num(m['x']),
        y: _num(m['y']),
        width: m['width'] == null ? null : _num(m['width']),
        height: m['height'] == null ? null : _num(m['height']),
        rotation: _num(m['rotation']),
        shape: (m['shape'] as String?) ?? 'rect',
      ));
    }
  }

  final items = <FloorPlanItemInput>[];
  if (rawItems is List) {
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      items.add((
        id: null,
        globalId: m['globalId'] as String?,
        kind: (m['kind'] as String?) ?? '',
        x: _num(m['x']),
        y: _num(m['y']),
        width: _num(m['width'], kMinItemSide),
        height: _num(m['height'], kMinItemSide),
        rotation: _num(m['rotation']),
        label: m['label'] as String?,
      ));
    }
  }

  return (
    sectionId: sectionId,
    sectionGlobalId: json['sectionGlobalId'] as String?,
    canvasWidth: _num(json['canvasWidth'], kDefaultCanvasWidth),
    canvasHeight: _num(json['canvasHeight'], kDefaultCanvasHeight),
    originX: _num(json['originX']),
    originY: _num(json['originY']),
    tables: tables,
    items: items,
  );
}

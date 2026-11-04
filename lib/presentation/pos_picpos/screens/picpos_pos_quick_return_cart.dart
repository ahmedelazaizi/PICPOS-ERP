part of 'picpos_pos_screen.dart';

/// «سلّة المرتجع» بعد تأكيد محرِّر الأسطر — العرضُ في عمود الفاتورة، والإضافةُ
/// من الشبكة/حقل المسح الرئيسيّ، وتعديلُ الكميّات (2026-11-04).
///
/// ── العيبُ الذي تُغلقه ───────────────────────────────────────────────────
/// بعد «تأكيد المرتجع» كان العمودُ يعرض جدولَ **سلّة البيع** (فارغةً دوماً في
/// وضع المرتجع، لأنّ المرتجعَ لا يكتب عليها عمداً)، والشبكةُ وحقلُ المسح
/// يرفضان كلَّ صنفٍ بتوستٍ عابر («أنهِ الحفظَ أو الإلغاء»). فالكاشيرُ يرى
/// ترويسةً حمراءَ فوق سلّةٍ فارغة، ولا يستطيع رؤيةَ ما اختاره ولا تعديلَه ولا
/// مسحَ الصنف المرتجَع — بلاغُ التحقّق الحيّ (`SINV-7`، باركود `20004`).
///
/// الآن: كلُّ مدخلٍ يكتب على [PosReturnMode] (نسخةٍ جديدةٍ في المزوِّد) لا على
/// سلّة البيع، ويمرّ بالأقفال نفسِها: الصنفُ من أصناف الفاتورة فقط
/// (‏`canAcceptProduct`)، والكميةُ مسقوفةٌ بالمتاح (‏`setQty`)، وكلُّ رفضٍ
/// برسالةٍ ظاهرة.

/// كميّاتُ الحفظ: ما فوق الصفر فقط — `processSalesReturn` يعتبر السطرَ غيرَ
/// المذكور «لا إرجاعَ له». منقولةٌ من `_processQuickReturnSave`.
@visibleForTesting
Map<int, double> quickReturnQuantitiesOf(PosReturnMode mode) => <int, double>{
      for (final entry in mode.requestedQty.entries)
        if (entry.value > 0) entry.key: entry.value,
    };

/// نتيجةُ محاولة إضافة صنفٍ لوضع المرتجع من الشبكة أو المسح.
enum QuickReturnAddOutcome {
  /// زادت كميّةُ سطرٍ مطابق — `mode` في النتيجة هي النسخةُ الجديدة.
  added,

  /// الصنفُ لم يُبَع في هذه الفاتورة — لا مرتجعَ لصنفٍ لم يُبَع منها.
  notInInvoice,

  /// الصنفُ في الفاتورة لكنّ كلَّ متاحه للإرجاع مطلوبٌ سلفاً.
  exhausted,
}

/// يزيد سطرَ [productId] في [mode] خطوةَ [step] (مقصوصةً على المتاح) **على
/// نسخة**، ولا يمسّ [mode] نفسَه. خالصةٌ لتُختبر بلا شجرة ودجت.
@visibleForTesting
({QuickReturnAddOutcome outcome, PosReturnMode mode, ReturnableLine? line})
    addProductToQuickReturn(PosReturnMode mode, int productId,
        {double step = 1}) {
  if (!mode.canAcceptProduct(productId)) {
    return (outcome: QuickReturnAddOutcome.notInInvoice, mode: mode, line: null);
  }
  final line = findReturnableLineForProduct(mode, productId);
  final target = line == null
      ? null
      : nextIncrementedQty(line, mode.requestedQty[line.invoiceItemId] ?? 0,
          step: step);
  if (line == null || target == null) {
    return (outcome: QuickReturnAddOutcome.exhausted, mode: mode, line: line);
  }
  final next = mode.copy();
  if (!next.setQty(line.invoiceItemId, target)) {
    return (outcome: QuickReturnAddOutcome.exhausted, mode: mode, line: line);
  }
  return (outcome: QuickReturnAddOutcome.added, mode: next, line: line);
}

/// يضبط كميّةَ سطرٍ على نسخةٍ من [mode] — `qty <= 0` يستبعد السطر. يرجع
/// `null` حين ترفض `setQty` الكميةَ (تتجاوز المتاح)، فيبقى [mode] كما هو.
@visibleForTesting
PosReturnMode? setQuickReturnLineQty(
    PosReturnMode mode, int invoiceItemId, double qty) {
  final next = mode.copy();
  if (qty <= 0) {
    next.clearQty(invoiceItemId);
    return next;
  }
  return next.setQty(invoiceItemId, qty) ? next : null;
}

extension _PicPosQuickReturnCartOps on _PicPosOperations {
  /// اللوحةُ التي تحلّ محلَّ جدول سلّة البيع ما دام وضعُ المرتجع فعّالاً.
  Widget _buildQuickReturnTable(PosReturnMode mode) =>
      PicPosQuickReturnLinesTable(
        mode: mode,
        onIncrement: (line) async {
          if (!await ensureIncrementReturnLinePermission(ref, context)) return;
          final m = ref.read(posReturnModeProvider);
          if (m == null) return;
          // هذا السطرُ بعينه، لا «أوّلُ سطرٍ للصنف» — فاتورةٌ قد تحمل الصنفَ
          // على سطرين.
          final target = nextIncrementedQty(
              line, m.requestedQty[line.invoiceItemId] ?? 0);
          if (target != null) _applyQuickReturnQty(line, target);
        },
        onDecrement: (line) async {
          if (!await ensureDecrementReturnLinePermission(ref, context)) return;
          final m = ref.read(posReturnModeProvider);
          if (m == null) return;
          _applyQuickReturnQty(
              line, (m.requestedQty[line.invoiceItemId] ?? 0) - 1);
        },
        onEditQty: _editQuickReturnQty,
        onRemove: (line) => _applyQuickReturnQty(line, 0),
      );

  /// يضيف [productId] لوضع المرتجع ويُظهر رسالةً عند كلّ رفض — لا صمت.
  void _addProductToQuickReturn(PosReturnMode mode, int productId,
      {double step = 1, String? productName}) {
    final r = addProductToQuickReturn(mode, productId, step: step);
    final name = r.line?.productName ?? productName ?? '#$productId';
    switch (r.outcome) {
      case QuickReturnAddOutcome.added:
        ref.read(posReturnModeProvider.notifier).state = r.mode;
      case QuickReturnAddOutcome.notInInvoice:
        showPosToast(context, ref,
            tr('«{p0}» ليس ضمن أصناف هذه الفاتورة', {'p0': name}),
            type: PosNotificationType.warning);
      case QuickReturnAddOutcome.exhausted:
        showPosToast(context, ref,
            tr('كلُّ كمية «{p0}» المتاحة للإرجاع طُلِبت بالفعل', {'p0': name}),
            type: PosNotificationType.warning);
    }
    _refocusScanner();
  }

  /// مسحُ باركودٍ في الحقل الرئيسيّ أثناء وضع المرتجع: الباركودُ ثم الكود ثم
  /// ملصقُ الميزان (‏وزنُه هو الخطوة) — نفسُ ترتيب `_blockedProductForBarcode`.
  Future<void> _addBarcodeToQuickReturn(String barcode) async {
    final code = barcode.trim();
    barcodeController.clear();
    ProductEntity? product;
    double step = 1;
    try {
      final repo = ref.read(productRepositoryProvider);
      product = await repo.getProductByBarcode(code);
      product ??= await repo.getProductByCode(code);
      if (product == null) {
        final scale =
            await ScaleBarcodeHandler.tryParse(RepositoryBarcodeAdapter(ref), code);
        product = scale?.product;
        if (scale != null && scale.quantity > 0) step = scale.quantity;
      }
    } catch (e) {
      debugPrint('[PicPos-QuickReturn] تعذّر البحث عن الباركود: $e');
      product = null;
    }
    if (!mounted) return;
    final mode = ref.read(posReturnModeProvider);
    if (mode == null) return;
    if (product == null) {
      showPosToast(context, ref, tr('لم يُعثر على صنفٍ بهذا الباركود/الكود'),
          type: PosNotificationType.warning);
      _refocusScanner();
      return;
    }
    _addProductToQuickReturn(mode, product.id,
        step: step, productName: product.name);
  }

  void _applyQuickReturnQty(ReturnableLine line, double qty) {
    final mode = ref.read(posReturnModeProvider);
    if (mode == null) return;
    final next = setQuickReturnLineQty(mode, line.invoiceItemId, qty);
    if (next == null) {
      showPosToast(
        context,
        ref,
        tr('الكميةُ مرفوضة — أقصى متاحٍ لـ«{p0}» {p1}', {
          'p0': line.productName,
          'p1': line.availableQty.toStringAsFixed(2),
        }),
        type: PosNotificationType.error,
      );
      return;
    }
    ref.read(posReturnModeProvider.notifier).state = next;
  }

  Future<void> _editQuickReturnQty(ReturnableLine line) async {
    final current =
        ref.read(posReturnModeProvider)?.requestedQty[line.invoiceItemId] ?? 0;
    final result = await PicPosNumericKeypadDialog.show(
      context,
      title: tr('كميةُ إرجاع «{p0}»', {'p0': line.productName}),
      initialValue: current,
      decimals: 3,
      min: 0,
      max: line.availableQty,
    );
    if (result == null || !mounted) return;
    _applyQuickReturnQty(line, result);
    _refocusScanner();
  }
}

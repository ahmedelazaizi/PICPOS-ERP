part of 'picpos_pos_screen.dart';

/// سطحُ اختيار أسطر المرتجع — يظهر بعد اختيار الفاتورة في `_showQuickReturn`
/// (المهمّة ٧، جولةُ إصلاح ١: يُغلق ما رفضه المراجعُ في C1–C3). الكاشيرُ لم
/// يكن يرى ما سيُرجَع ولا يتحكّم فيه، وسلّةُ البيع كانت دوماً فارغةً فأزرارُ
/// الدفع/الحفظ معطَّلة — راجع تعليقَ `_showQuickReturn`.
///
/// عمداً **لا** يكتب على `cartController` — قرارُ المراجع الصريح: «سلّةُ
/// البيع تقود الإجماليّاتِ والدفعَ والمخزون، وحشوُها بأسطرِ مرتجعٍ يخلط
/// مسارَين. واللوحةُ المخصَّصةُ أسلم». كلُّ الحالة هنا محليّةٌ لهذا الحوار
/// وحدَه، فوق [PosReturnMode] المُمرَّر (كائنٌ متغيّرٌ داخلياً — نفسُ
/// المرجع، لا نسخة).
///
/// يحقّق المطلوبَ السبعة في المراجعة:
///  ١. كلُّ سطرٍ يعرض الاسمَ والمباعَ والمرتجعَ سابقاً و**المتاح** والسعر.
///  ٢. الكميّاتُ تبدأ صفراً وتُضبط بعنصرِ تحكّم (‏+/- أو كيبوردٌ رقميّ لمسيّ).
///  ٣. كلُّ تعديلٍ يمرّ بـ`PosReturnMode.setQty`/`clearQty` — لا كتابةَ
///     مباشرةً في `requestedQty`.
///  ٤. السعرُ من `unitPriceOf`، لا من أيّ مصدرٍ آخر.
///  ٥. حقلُ البحث/الباركود يمرّ بـ`findReturnableLineForProduct` (خالصةٌ،
///     تستعمل `canAcceptProduct` داخلياً) ويرفض غيرَ المطابق برسالةٍ ظاهرة.
///  ٦. مبلغُ الاسترداد (`_refundTotal`) ظاهرٌ ويُعاد حسابُه مع كلّ تعديل.
///  ٧. «تأكيد المرتجع» يعمل بالماوس/اللمس دوماً، ومعطَّلٌ فقط حين تكون كلُّ
///     الكميّات أصفاراً (‏`_hasAnyQty`).
class _QuickReturnLinesEditorDialog extends ConsumerStatefulWidget {
  final PosReturnMode mode;
  final String invoiceNumber;

  const _QuickReturnLinesEditorDialog({
    required this.mode,
    required this.invoiceNumber,
  });

  @override
  ConsumerState<_QuickReturnLinesEditorDialog> createState() =>
      _QuickReturnLinesEditorDialogState();
}

class _QuickReturnLinesEditorDialogState
    extends ConsumerState<_QuickReturnLinesEditorDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  PosReturnMode get _mode => widget.mode;

  /// ٦: مبلغُ الاسترداد المعروض — يفوّض لـ`PosReturnMode.refundTotal`
  /// (‏نفسُ صيغة `ReturnsRepositoryImpl._calculateReturnTotal` بالحرف عبر
  /// `calculateReturnRefundTotal` المشتركة)، **لا** `Σ qty × unitPrice`.
  /// العطبُ المقيسُ في مراجعة 2026-08-16: `unitPrice` سعرُ البيع قبل
  /// الضريبة وقبل خصم السطر، بينما المصروفُ فعلياً من الدرج مبنيٌّ على
  /// `item.total` (شاملَ الضريبة وصافياً من الخصم) — فاتورةٌ بضريبة ١٤٪
  /// كانت تعرض أقلَّ ممّا يخرج من الدرج فعلياً بمقدار الضريبة تماماً.
  /// `unitPriceOf` **يبقى بلا تغيير** لعرض سعر السطر في `_buildLineRow` —
  /// هذا التغييرُ في مجموع الاسترداد وحدَه.
  double get _refundTotal => _mode.refundTotal;

  bool get _hasAnyQty => _mode.requestedQty.values.any((q) => q > 0);

  /// حقلُ البحث/الباركود — ٥: يمرّ بـ`findReturnableLineForProduct`
  /// (‏`canAcceptProduct` داخلياً) ويرفض غيرَ المطابق برسالةٍ ظاهرة، لا
  /// بإهمالٍ صامت.
  Future<void> _resolveSearch(String input) async {
    final code = input.trim();
    if (code.isEmpty) return;

    ProductEntity? product;
    try {
      product =
          await ref.read(productRepositoryProvider).getProductByBarcode(code);
      product ??=
          await ref.read(productRepositoryProvider).getProductByCode(code);
    } catch (_) {
      product = null;
    }

    _searchController.clear();
    if (!mounted) return;

    if (product == null) {
      showPosToast(context, ref, tr('لم يُعثر على صنفٍ بهذا الباركود/الكود'),
          type: PosNotificationType.warning);
      return;
    }

    final line = findReturnableLineForProduct(_mode, product.id);
    if (line == null) {
      final inInvoice = _mode.canAcceptProduct(product.id);
      showPosToast(
        context,
        ref,
        inInvoice
            ? tr('كلُّ كمية «{p0}» المتاحة للإرجاع طُلِبت بالفعل', {'p0': product.name})
            : tr('«{p0}» ليس ضمن أصناف هذه الفاتورة', {'p0': product.name}),
        type: PosNotificationType.warning,
      );
      return;
    }

    _increment(line);
  }

  /// ٣: نقطةُ الكتابة الوحيدة على `requestedQty` — دوماً عبر `setQty` أو
  /// `clearQty`، أبداً بكتابةٍ مباشرةٍ في الخريطة.
  ///
  /// ⚠️ المتطلَّبُ ٥ (جولةُ إصلاح ٢): **كلُّ** رفضٍ من `setQty` يُظهر توستاً
  /// يذكر المتاحَ — لا إهمالٌ صامت، حتى من نقطة استدعاءٍ تظنّ القيمةَ
  /// صالحةً سلفاً (‏دفاعٌ في العمق: `_increment` تحسب هدفاً محدوداً
  /// فلا يُفترَض بلوغُ هذا الفرع منه، والكيبورد يحصر القيمةَ بـ`min`/`max`
  /// بنفسه — لكن كلاهما يبقى مغطّى هنا احتياطاً).
  void _setQty(ReturnableLine line, double qty) {
    if (qty <= 0) {
      setState(() => _mode.clearQty(line.invoiceItemId));
      return;
    }
    final ok = _mode.setQty(line.invoiceItemId, qty);
    if (!ok) {
      showPosToast(
        context,
        ref,
        tr('الكميةُ مرفوضة — أقصى متاحٍ لـ«{p0}» {p1}', {'p0': line.productName, 'p1': line.availableQty.toStringAsFixed(2)}),
        type: PosNotificationType.error,
      );
      return;
    }
    setState(() {});
  }

  /// يزيد كميّةَ [line] خطوةً واحدة عبر [nextIncrementedQty] (‏القصُّ على
  /// المتاح خالصٌ ومُختبَرٌ هناك). أسلمُ تطبيقٍ للمتطلَّب ٥ هو ألّا يقعَ
  /// الرفضُ إطلاقاً حين يكون العنصرُ تحت تحكّم البرنامج (زرّ «+» أو مسحةُ
  /// باركود)، لا اختيارَ الكاشير حرفياً — فيُظهر توستاً بدل الرفض الصامت
  /// حين لا مجالَ للزيادة.
  void _increment(ReturnableLine line) {
    final current = _mode.requestedQty[line.invoiceItemId] ?? 0;
    final target = nextIncrementedQty(line, current);
    if (target == null) {
      showPosToast(
        context,
        ref,
        tr('بلغتَ الحدَّ الأقصى المتاح لـ«{p0}» ({p1})', {'p0': line.productName, 'p1': line.availableQty.toStringAsFixed(2)}),
        type: PosNotificationType.warning,
      );
      return;
    }
    _setQty(line, target);
  }

  Future<void> _editQtyViaKeypad(ReturnableLine line) async {
    final current = _mode.requestedQty[line.invoiceItemId] ?? 0;
    final result = await PicPosNumericKeypadDialog.show(
      context,
      title: tr('كميةُ إرجاع «{p0}»', {'p0': line.productName}),
      initialValue: current,
      decimals: 3,
      min: 0,
      max: line.availableQty,
    );
    if (result == null || !mounted) return;
    _setQty(line, result);
  }

  /// اختصارٌ اختياريّ — ليس بديلاً عن التحكّم سطراً سطراً، بل نقطةَ بدءٍ
  /// سريعة تبقى قابلةً للتعديل بعدها (تمرّ بـ`setQty` مثل أيّ تعديلٍ آخر).
  void _selectAllFull() {
    setState(() {
      for (final line in _mode.linesByItemId.values) {
        _mode.setQty(line.invoiceItemId, line.availableQty);
      }
    });
  }

  void _clearAll() {
    setState(() {
      for (final line in _mode.linesByItemId.values) {
        _mode.clearQty(line.invoiceItemId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = _mode.linesByItemId.values.toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.arrowUUpLeft, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('أصنافُ الإرجاع — فاتورة #{p0}', {'p0': widget.invoiceNumber}),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                decoration:  InputDecoration(
                  hintText: tr('باركود أو كود الصنف — يزيد الكميةَ سطراً بسطر'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(PhosphorIconsBold.barcode, size: 18),
                ),
                onSubmitted: _resolveSearch,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _selectAllFull,
                    icon: const Icon(PhosphorIconsBold.checkCircle, size: 16),
                    label:  Text(tr('تحديد الكلّ (مرتجعٌ كامل)')),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _hasAnyQty ? _clearAll : null,
                    icon: const Icon(PhosphorIconsBold.xCircle, size: 16),
                    label:  Text(tr('تصفيرُ الكلّ')),
                  ),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: lines.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _buildLineRow(lines[i]),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                     Text(tr('مبلغُ الاسترداد'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(
                      _refundTotal.toStringAsFixed(2),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:  Text(tr('إلغاء')),
          ),
          // ٧: يعمل بالماوس/اللمس دوماً — لا يعتمد على سلّة البيع إطلاقاً،
          // ومعطَّلٌ فقط حين تكون كلُّ الكميّات أصفاراً.
          ElevatedButton.icon(
            onPressed: _hasAnyQty ? () => Navigator.pop(context, true) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(PhosphorIconsBold.check, size: 18),
            label:  Text(tr('تأكيد المرتجع')),
          ),
        ],
      ),
    );
  }

  Widget _buildLineRow(ReturnableLine line) {
    final qty = _mode.requestedQty[line.invoiceItemId] ?? 0;
    final atMax = qty >= line.availableQty - 0.0005;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.productName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                // ١: المباع، المرتجعُ سابقاً، المتاح، السعر — الأربعةُ معاً.
                Text(
                  tr('مباع {p0} · مرتجعٌ سابقاً {p1} · متاح {p2} · السعر {p3}', {'p0': line.soldQty.toStringAsFixed(2), 'p1': line.alreadyReturnedQty.toStringAsFixed(2), 'p2': line.availableQty.toStringAsFixed(2), 'p3': _mode.unitPriceOf(line.invoiceItemId).toStringAsFixed(2)}),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsBold.minusCircle, size: 20),
            // `pos_item_minus` — كان محروساً في النظير القديم وحدَه
            // (`pos/widgets/cart_item_tile.dart:302`) على زرِّ «−» لكمية
            // صنفٍ في سلّة البيع. جدولُ PicPos أُعيدت كتابتُه بلا مِسطرةِ
            // خطوةٍ لتلك السلّة، فهذا أوّلُ سطحٍ حيٍّ للكود في PicPos.
            onPressed: qty > 0
                ? () async {
                    if (!await ensureDecrementReturnLinePermission(
                        ref, context)) {
                      return;
                    }
                    _setQty(line, qty - 1);
                  }
                : null,
          ),
          InkWell(
            onTap:
                line.availableQty > 0 ? () => _editQtyViaKeypad(line) : null,
            child: Container(
              width: 48,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: context.picposHairline),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                qty == qty.truncateToDouble()
                    ? qty.toStringAsFixed(0)
                    : qty.toStringAsFixed(2),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsBold.plusCircle, size: 20),
            // `pos_item_plus` — نفسُ قصّة `pos_item_minus` فوق، على زرِّ «+»
            // (`cart_item_tile.dart:381`).
            onPressed: !atMax
                ? () async {
                    if (!await ensureIncrementReturnLinePermission(
                        ref, context)) {
                      return;
                    }
                    _increment(line);
                  }
                : null,
          ),
          if (qty > 0)
            IconButton(
              icon: const Icon(PhosphorIconsBold.x,
                  size: 16, color: AppColors.error),
              tooltip: tr('استبعادُ الصنف من المرتجع'),
              onPressed: () => _setQty(line, 0),
            ),
        ],
      ),
    );
  }
}

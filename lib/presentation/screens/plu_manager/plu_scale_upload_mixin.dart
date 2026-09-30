part of '../plu_manager_screen.dart';

mixin _PluScaleUploadMixin on ConsumerState<PluManagerScreen> {
  // Abstract members satisfied by _PluManagerScreenState
  PluManagerController get _controller;
  // ignore: unused_element
  bool get _isUploading;
  set _isUploading(bool v);
  // ignore: unused_element
  String get _uploadStatus;
  set _uploadStatus(String v);
  // ignore: unused_element
  int get _uploadProgress;
  set _uploadProgress(int v);
  // ignore: unused_element
  int get _uploadTotal;
  set _uploadTotal(int v);

  // ═══════════════════════════════════════════════════════════════════
  // Direct Scale Upload — uses scales registered in "ميزان التسعير"
  // ═══════════════════════════════════════════════════════════════════

  IScaleRepository get _scaleRepo => ref.read(scaleRepositoryProvider);

  /// Generate scale barcode: prefix + PLU padded to [codeLen] digits.
  /// e.g., PLU=123, weightPrefix="21", codeLen=5 → "2100123"
  String _generateScaleBarcode(int plu, bool isByWeight, {String weightPrefix = '21', String pricePrefix = '20', int codeLen = 5}) {
    final prefix = isByWeight ? weightPrefix : pricePrefix;
    return '$prefix${plu.toString().padLeft(codeLen, '0')}';
  }

  Future<void> _uploadDirectToScale() async {
    final scaleProducts = await _controller.getScaleProducts();
    if (scaleProducts.isEmpty) {
      if (mounted) AppToast.show(context, tr('لا توجد أصناف بأرقام PLU للترحيل'), type: ToastType.warning);
      return;
    }

    final scales = await _scaleRepo.getAllScales();
    if (!mounted) return;

    if (scales.isEmpty) {
      if (mounted) AppToast.show(context, tr('لا توجد موازين مسجّلة — أضف موازين من شاشة "ميزان التسعير"'), type: ToastType.warning);
      return;
    }

    final selectedScale = await _showScalePickerDialog(scales, scaleProducts.length);
    if (selectedScale == null || !mounted) return;

    final settingsRepo = ref.read(settingsRepositoryProvider);
    final weightPrefix = await settingsRepo.getSetting('scale_weight_prefix') ?? '21';
    final pricePrefix = await settingsRepo.getSetting('scale_price_prefix') ?? '20';
    final pluCodeLenStr = await settingsRepo.getSetting('scale_weight_item_code_len') ?? '5';
    final pluCodeLen = int.tryParse(pluCodeLenStr) ?? 5;

    final pluItems = scaleProducts.map((p) {
      final plu = (p.scalePluNumber != null && p.scalePluNumber! > 0) ? p.scalePluNumber! : p.id;
      final isByWeight = scaleItemIsSoldByWeight(
        scaleType: p.scaleType,
        isSoldByWeight: p.isSoldByWeight,
      );
      return ScalePLUItem(
        pluNumber: plu,
        name: p.name,
        unitPrice: p.pricePerUnit ?? p.salePrice,
        isByWeight: isByWeight,
        department: isByWeight ? int.tryParse(weightPrefix) ?? 21 : int.tryParse(pricePrefix) ?? 20,
        barcode: _generateScaleBarcode(plu, isByWeight, weightPrefix: weightPrefix, pricePrefix: pricePrefix, codeLen: pluCodeLen),
        productCode: p.code,
      );
    }).toList();

    final conn = LabelScaleService.connectionFromString(selectedScale.connectionType);
    if (conn == LabelScaleConnection.file) {
      try {
        final brand = LabelScaleService.brandFromString(selectedScale.brand);
        final csvContent = LabelScaleService.instance.generatePLUCsv(pluItems, brand: brand);
        final desktopPath = '${Platform.environment['USERPROFILE']}\\Desktop';
        final fileName = 'PLU_${DateTime.now().millisecondsSinceEpoch}.csv';
        final filePath = '$desktopPath\\$fileName';
        // Write as UTF-16 LE — matches PLU Manager's native TSV format (2.xls)
        await File(filePath).writeAsBytes(ScaleTransport().encodeUtf16LE(csvContent));
        if (mounted) {
          AppToast.show(context, tr('تم تصدير {p0} صنف إلى سطح المكتب: {fileName}', {'p0': pluItems.length, 'fileName': fileName}), type: ToastType.success);
          Process.run('explorer.exe', ['/select,', filePath]);
        }
      } catch (e) {
        if (mounted) AppToast.show(context, tr('فشل التصدير: {e}', {'e': e}), type: ToastType.error);
      }
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = tr('جاري الترحيل إلى {p0}...', {'p0': selectedScale.name});
      _uploadProgress = 0;
      _uploadTotal = pluItems.length;
    });

    try {
      final result = await _scaleRepo.syncToScale(selectedScale, pluItems);
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = result.success;
        });
        if (result.isFullSuccess) {
          AppToast.show(context, tr('تم ترحيل {p0} صنف بنجاح إلى "{p1}"', {'p0': result.success, 'p1': selectedScale.name}), type: ToastType.success);
        } else if (result.success > 0) {
          AppToast.show(context, tr('"{p0}": {p1} نجاح، {p2} فشل', {'p0': selectedScale.name, 'p1': result.success, 'p2': result.failed}), type: ToastType.warning);
        } else {
  // ignore: dead_code
          _showUploadErrorDialog(result, selectedScale.name ?? tr('الميزان'));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        AppToast.show(context, tr('خطأ في الاتصال بـ "{p0}": {e}', {'p0': selectedScale.name, 'e': e}), type: ToastType.error);
      }
    }
  }

  Future<LabelScale?> _showScalePickerDialog(List<LabelScale> scales, int itemCount) async {
    LabelScale? selected = scales.where((s) => s.isActive).firstOrNull;

    return showDialog<LabelScale>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title: Row(children: [
              const Icon(PhosphorIconsBold.scales, color: Colors.teal, size: 24),
              const SizedBox(width: 8),
               Expanded(child: Text(tr('اختر الميزان للترحيل'))),
              Text(tr('{itemCount} صنف', {'itemCount': itemCount}), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: scales.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (_, i) {
                        final scale = scales[i];
                        final isSelected = selected?.id == scale.id;
                        final brand = LabelScaleService.brandFromString(scale.brand);
                        final conn = scale.connectionType == 'tcp'
                            ? '${scale.ipAddress ?? "—"}:${scale.port}'
                            : scale.comPort ?? '—';

                        return InkWell(
                          onTap: scale.isActive ? () => setDialogState(() => selected = scale) : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.teal.withValues(alpha: 0.1) : null,
                              border: Border.all(
                                color: isSelected ? Colors.teal : AppColors.border.withValues(alpha: 0.3),
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(children: [
                              Radio<int>(
                                value: scale.id,
                                groupValue: selected?.id,
                                activeColor: Colors.teal,
                                onChanged: scale.isActive ? (_) => setDialogState(() => selected = scale) : null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
  // ignore: dead_code
                                      Text(scale.name ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          LabelScaleService.brandNames[brand] ?? brand.name,
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ),
                                      if (!scale.isActive) ...[
                                        const SizedBox(width: 8),
                                         Text(tr('(غير نشط)'), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                      ],
                                    ]),
                                    Text(conn, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: AppTypography.mono)),
                                  ],
                                ),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child:  Text(tr('إلغاء'))),
              FilledButton.icon(
                onPressed: selected != null ? () => Navigator.pop(ctx, selected) : null,
                icon: const Icon(PhosphorIconsBold.upload, size: 16),
                label: Text(tr('ترحيل {p0}', {'p0': selected != null ? tr('إلى "{p0}"', {'p0': selected!.name}) : ""})),
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUploadErrorDialog(PLUUploadResult result, String scaleName) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Row(children: [
            const Icon(PhosphorIconsBold.warningCircle, color: AppColors.error, size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('فشل الترحيل إلى "{scaleName}"', {'scaleName': scaleName}))),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('إجمالي: {p0} | نجاح: {p1} | فشل: {p2}', {'p0': result.total, 'p1': result.success, 'p2': result.failed})),
              if (result.errors.isNotEmpty) ...[
                const Divider(),
                SizedBox(
                  height: 100,
                  child: SingleChildScrollView(
                    child: Text(result.errors.take(10).join('\n'), style: const TextStyle(fontSize: 11, fontFamily: AppTypography.mono)),
                  ),
                ),
              ],
              const Divider(),
               Text(tr('تأكد من: الميزان مشغّل — IP/COM صحيح — الماركة مطابقة'), style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child:  Text(tr('إغلاق')))],
        ),
      ),
    );
  }
}

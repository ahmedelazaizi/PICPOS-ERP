part of '../plu_manager_screen.dart';

mixin _PluCsvMixin on ConsumerState<PluManagerScreen> {
  // Abstract members satisfied by _PluManagerScreenState and other mixins
  PluManagerController get _controller;
  Future<void> _loadData();
  String _generateScaleBarcode(int plu, bool isByWeight, {String weightPrefix, String pricePrefix, int codeLen});

  // ═══════════════════════════════════════════════════════════════════
  // CSV IMPORT / EXPORT
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _importPluFromCsv() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
      dialogTitle: 'اختر ملف PLU (CSV)',
    );
    if (result == null || result.files.isEmpty) return;

    try {
      final file = File(result.files.first.path!);

      List<String> lines;
      try {
        lines = await file.readAsLines(encoding: utf8);
      } catch (_) {
        final bytes = await file.readAsBytes();
        lines = latin1.decode(bytes).split('\n');
      }

      int imported = 0;
      int skipped = 0;
      final errors = <String>[];

      final isCasFormat = lines.isNotEmpty &&
          (lines[0].contains('Hotkey') || lines[0].contains('LFCode') ||
           lines[0].split(RegExp(r'[,;\t]')).length >= 10);

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final lower = line.toLowerCase();
        if (lower.startsWith('plu') || lower.startsWith('num') ||
            lower.contains('hotkey') || lower.contains('lfcode') ||
            lower.contains('barcode type')) continue;

        final parts = line.split(RegExp(r'[,;\t]'));
        if (parts.length < 2) {
          errors.add('سطر ${i + 1}: تنسيق خاطئ');
          continue;
        }

        int? pluNum;
        String productIdentifier;

        if (isCasFormat && parts.length >= 5) {
          pluNum = int.tryParse(parts[1].trim());
          productIdentifier = parts[4].trim();
          if (productIdentifier == parts[1].trim() && parts.length > 2) {
            productIdentifier = parts[2].trim().replaceAll('"', '');
          }
        } else {
          pluNum = int.tryParse(parts[0].trim());
          productIdentifier = parts[1].trim().replaceAll('"', '');
        }

        if (pluNum == null) {
          errors.add('سطر ${i + 1}: PLU غير صالح "${isCasFormat ? parts[1] : parts[0]}"');
          continue;
        }

        var product = await _controller.getProductByCode(productIdentifier);
        product ??= await _controller.getProductByBarcode(productIdentifier);
        if (product == null) {
          final results = await _controller.searchProducts(productIdentifier);
          if (results.length == 1) product = results.first;
        }
        if (product == null) {
          final id = int.tryParse(productIdentifier);
          if (id != null) product = await _controller.getProductById(id);
        }

        if (product == null) {
          errors.add('سطر ${i + 1}: منتج "$productIdentifier" غير موجود');
          skipped++;
          continue;
        }

        await _controller.updateProductScalePlu(product.id, pluNumber: pluNum);
        imported++;
      }

      await _loadData();
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title: const Text('نتيجة الاستيراد'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('✅ تم استيراد: $imported', style: const TextStyle(color: AppColors.success)),
                if (skipped > 0) Text('⚠️ تم تخطي: $skipped', style: const TextStyle(color: AppColors.warning)),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('أخطاء:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...errors.take(10).map((e) => Text(e, style: const TextStyle(fontSize: 11, color: AppColors.error))),
                  if (errors.length > 10) Text('... و${errors.length - 10} أخطاء أخرى'),
                ],
              ],
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('موافق'))],
          ),
        ),
      );
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ في قراءة الملف: $e', type: ToastType.error);
    }
  }

  Future<void> _exportPluToCsv() async {
    final scaleProducts = await _controller.getScaleProducts();
    if (scaleProducts.isEmpty) {
      if (!mounted) return;
      AppToast.show(context, 'لا توجد أصناف بأرقام PLU', type: ToastType.error);
      return;
    }

    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'اختر مجلد التصدير');
    if (dir == null) return;

    try {
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

      final csvContent = LabelScaleService.instance.generatePLUCsv(pluItems, weightPrefix: weightPrefix, pluCodeLen: pluCodeLen);
      final file = File('$dir/plu_export_${DateTime.now().millisecondsSinceEpoch}.csv');
      // Write as UTF-16 LE — matches PLU Manager's native TSV format (2.xls)
      await file.writeAsBytes(ScaleTransport().encodeUtf16LE(csvContent));

      if (mounted) AppToast.show(context, 'تم تصدير ${scaleProducts.length} صنف PLU إلى ${file.path}', type: ToastType.success);
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ في التصدير: $e', type: ToastType.error);
    }
  }
}

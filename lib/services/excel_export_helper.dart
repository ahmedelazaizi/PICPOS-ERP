// ═══════════════════════════════════════════════════════════════════════════
// U-12: Excel Export Consistency Utility
// Reusable mixin and helper for standardized Excel export on all list screens
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:excel/excel.dart' as xl;
import 'dart:io';
import '../core/config/data_dir.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';

/// Standardized Excel export utility for consistent exports across all screens.
///
/// Usage:
/// ```dart
/// await ExcelExportHelper.export(
///   context: context,
///   title: 'تقرير المبيعات',
///   headers: ['التاريخ', 'الفاتورة', 'المبلغ'],
///   rows: data.map((r) => [r.date, r.invoiceNo, r.total]).toList(),
/// );
/// ```
class ExcelExportHelper {
  /// حوّل خليةً واحدة لقيمةِ Excel.
  ///
  /// الأرقامُ **تُدوَّر لخانات العملة** (`AppConstants.decimalPlaces`) قبل
  /// الكتابة. كان يُكتب `cell.toDouble()` خاماً، فالشاشةُ تعرض 12.346
  /// والملفُّ يحمل 12.345678900000001 — ومجموعُ عمودٍ في Excel يفترق عن
  /// مجموع الشاشة في الكسور، فيقول المراجعُ إن التقريرَ لا يطابق النظام.
  /// والعطبُ صامت: الملفُّ يُفتح ويبدو سليماً، والفرقُ يظهر عند الجمع.
  ///
  /// معزولةٌ عن [export] كي تُقاس بلا `BuildContext` ولا نظامِ ملفات.
  static xl.CellValue toCellValue(dynamic cell) {
    if (cell == null) return xl.TextCellValue('');
    if (cell is num) {
      return xl.DoubleCellValue(
        double.parse(cell.toDouble().toStringAsFixed(
              AppConstants.decimalPlaces,
            )),
      );
    }
    if (cell is DateTime) {
      return xl.TextCellValue(DateFormat('yyyy/MM/dd').format(cell));
    }
    return xl.TextCellValue(cell.toString());
  }

  /// Export data to Excel with standardized formatting
  static Future<void> export({
    required BuildContext context,
    required String title,
    required List<String> headers,
    required List<List<dynamic>> rows,
    String? sheetName,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final excel = xl.Excel.createExcel();
      final sheet = sheetName ?? 'تقرير';
      final s = excel[sheet];
      // Remove default sheet
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      // Title row
      s.appendRow([xl.TextCellValue(title)]);

      // Date range row if provided
      if (fromDate != null && toDate != null) {
        final fmt = DateFormat('yyyy/MM/dd');
        s.appendRow([xl.TextCellValue('الفترة: ${fmt.format(fromDate)} - ${fmt.format(toDate)}')]);
      }

      // Empty row
      s.appendRow([]);

      // Header row
      s.appendRow(headers.map((h) => xl.TextCellValue(h)).toList());

      // Data rows
      for (final row in rows) {
        s.appendRow(row.map(toCellValue).toList());
      }

      // Save file
      final dir = await DataDir.documents();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = '${title.replaceAll(' ', '_')}_$timestamp.xlsx';
      final filePath = '${dir.path}/$fileName';
      final bytes = excel.encode();
      if (bytes != null) {
        await File(filePath).writeAsBytes(bytes);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم التصدير: $fileName'),
            backgroundColor: AppColors.success,
            action: SnackBarAction(
              label: 'فتح المجلد',
              textColor: Colors.white,
              onPressed: () => Process.run('explorer.exe', [dir.path]),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تصدير Excel: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

/// Standard export button widget for consistent placement across screens
class ExcelExportButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool compact;

  const ExcelExportButton({
    super.key,
    required this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        icon: const Icon(PhosphorIconsBold.fileXls, size: 20),
        onPressed: onPressed,
        tooltip: 'تصدير Excel',
        color: AppColors.success,
      );
    }

    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(PhosphorIconsBold.fileXls, size: 16, color: AppColors.success),
      label: Text('تصدير Excel', style: GoogleFonts.cairo(fontSize: 11, color: AppColors.success)),
    );
  }
}

/// Standard PDF export button
class PdfExportButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool compact;

  const PdfExportButton({
    super.key,
    required this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        icon: const Icon(PhosphorIconsBold.filePdf, size: 20),
        onPressed: onPressed,
        tooltip: 'تصدير PDF',
        color: Colors.red,
      );
    }

    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(PhosphorIconsBold.filePdf, size: 16, color: Colors.red),
      label: Text('تصدير PDF', style: GoogleFonts.cairo(fontSize: 11, color: Colors.red)),
    );
  }
}

import 'dart:async' show unawaited;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing_pkg;
import 'package:flutter/foundation.dart';
import '../../core/logging/diagnostic_logger.dart';

/// Helper to print PDF documents via the native print preview dialog.
///
/// NOTE: pdf.save() intentionally runs on the MAIN thread.
/// Running it in an Isolate causes Arabic font data and page build closures
/// to be deep-copied across isolate boundaries, which can result in
/// font data corruption → Arabic text rendered as boxes (■■■).
class PdfComputeHelper {
  /// Serialise the document and send to the native print preview dialog.
  ///
  /// Usage:
  /// ```dart
  /// final pdf = pw.Document();
  /// pdf.addPage(...);
  /// await PdfComputeHelper.layoutPdf(pdf);
  /// ```
  ///
  /// Field-report 2026-05-14: standalone build silently process-exited
  /// ~90s after a successful A4 print. The Dart future resolved cleanly
  /// (`err=null`), so the crash is in the native Windows print-preview
  /// teardown. Adding the try/catch + breadcrumbs here so the next
  /// repro lands a usable trace instead of disappearing into the void.
  static Future<void> layoutPdf(pw.Document pdf) async {
    final Uint8List bytes = await saveToBytes(pdf);
    unawaited(DiagnosticLogger.log(
        'PDF-PRINT', 'layoutPdf invoking native dialog (bytes=${bytes.length})'));
    try {
      await printing_pkg.Printing.layoutPdf(
        onLayout: (format) async => bytes,
      );
      unawaited(DiagnosticLogger.log('PDF-PRINT', 'layoutPdf returned OK'));
    } catch (e, st) {
      unawaited(DiagnosticLogger.log(
          'PDF-PRINT', 'layoutPdf threw: $e\n$st'));
      rethrow;
    }
  }

  /// Save PDF to bytes on the main thread.
  /// Fonts and closures are fully accessible here — no isolate boundary issues.
  static Future<Uint8List> saveToBytes(pw.Document pdf) async {
    try {
      return await pdf.save();
    } catch (e) {
      debugPrint('[PdfComputeHelper] pdf.save() error: $e');
      rethrow;
    }
  }
}


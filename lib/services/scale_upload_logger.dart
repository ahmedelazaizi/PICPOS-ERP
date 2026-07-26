// ═══════════════════════════════════════════════════════════════════════════
// SCALE UPLOAD LOGGER — Detailed logging for scale PLU upload operations
// ═══════════════════════════════════════════════════════════════════════════
//
// Writes a human-readable log file to Desktop showing every step of the
// upload process: connection, protocol selection, data sent, responses,
// errors, and final status. Opens the log file after upload completes.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'label_scale_service.dart';
import '../core/config/brand.dart';

/// Logger for scale upload operations — writes to a file on Desktop
class ScaleUploadLogger {
  final StringBuffer _buffer = StringBuffer();
  final String _scaleName;
  final String _brand;
  final String _connection;
  final String _address;
  final DateTime _startTime;

  ScaleUploadLogger({
    required String scaleName,
    required String brand,
    required String connection,
    required String address,
  })  : _scaleName = scaleName,
        _brand = brand,
        _connection = connection,
        _address = address,
        _startTime = DateTime.now() {
    _writeHeader();
  }

  void _writeHeader() {
    _buffer.writeln('╔══════════════════════════════════════════════════════════════╗');
    _buffer.writeln('║          سجل ترحيل أصناف الميزان — ${Brand.name} ERP           ║');
    _buffer.writeln('╚══════════════════════════════════════════════════════════════╝');
    _buffer.writeln();
    _buffer.writeln('التاريخ: ${_startTime.toString().split('.').first}');
    _buffer.writeln('الميزان: $_scaleName');
    _buffer.writeln('العلامة: $_brand');
    _buffer.writeln('الاتصال: $_connection');
    _buffer.writeln('العنوان: $_address');
    _buffer.writeln();
    _buffer.writeln('═' * 64);
  }

  /// Log a section header
  void section(String title) {
    _buffer.writeln();
    _buffer.writeln('── $title ──');
  }

  /// Log an info message
  void info(String message) {
    final time = DateTime.now().toString().split('.').first.split(' ').last;
    _buffer.writeln('[$time] ℹ $message');
    debugPrint('[ScaleLog] $message');
  }

  /// Log a success message
  void success(String message) {
    final time = DateTime.now().toString().split('.').first.split(' ').last;
    _buffer.writeln('[$time] ✓ $message');
    debugPrint('[ScaleLog] ✓ $message');
  }

  /// Log an error message
  void error(String message) {
    final time = DateTime.now().toString().split('.').first.split(' ').last;
    _buffer.writeln('[$time] ✗ $message');
    debugPrint('[ScaleLog] ✗ $message');
  }

  /// Log a warning message
  void warning(String message) {
    final time = DateTime.now().toString().split('.').first.split(' ').last;
    _buffer.writeln('[$time] ⚠ $message');
    debugPrint('[ScaleLog] ⚠ $message');
  }

  /// Log raw bytes sent (hex dump)
  void sentBytes(String label, Uint8List data) {
    _buffer.writeln('  ⮕ أرسل [$label]: ${data.length} بايت');
    if (data.length <= 120) {
      _buffer.writeln('    HEX: ${_hexDump(data)}');
    } else {
      _buffer.writeln('    HEX (أول 60): ${_hexDump(data.sublist(0, 60))}');
      _buffer.writeln('    HEX (آخر 60): ${_hexDump(data.sublist(data.length - 60))}');
    }
  }

  /// Log raw bytes received
  void receivedBytes(String label, Uint8List data) {
    _buffer.writeln('  ⮘ استقبل [$label]: ${data.length} بايت');
    if (data.isNotEmpty) {
      _buffer.writeln('    HEX: ${_hexDump(data)}');
      // Try to interpret as ASCII
      final ascii = String.fromCharCodes(data.where((b) => b >= 32 && b < 127));
      if (ascii.isNotEmpty) {
        _buffer.writeln('    ASCII: $ascii');
      }
    }
  }

  /// Log a PLU item being processed
  void pluItem(int index, int total, int plu, String name, double price, bool byWeight, String barcode) {
    _buffer.writeln('  [$index/$total] PLU=$plu | ${byWeight ? "وزن" : "عدد"} | $name | ${price.toStringAsFixed(2)} | باركود=$barcode');
  }

  /// Log the PLU data table for preview
  void pluTable(List<ScalePLUItem> items) {
    section('جدول الأصناف المرحَّلة (${items.length} صنف)');
    _buffer.writeln();
    _buffer.writeln('─' * 100);
    _buffer.writeln('│ ${"#".padRight(4)} │ ${"PLU".padRight(6)} │ ${"اسم الصنف".padRight(30)} │ ${"السعر".padRight(10)} │ ${"النوع".padRight(6)} │ ${"القسم".padRight(4)} │ ${"الباركود".padRight(10)} │');
    _buffer.writeln('─' * 100);
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final type = item.isByWeight ? 'وزن' : 'عدد';
      _buffer.writeln(
        '│ ${(i + 1).toString().padRight(4)} '
        '│ ${item.pluNumber.toString().padRight(6)} '
        '│ ${item.name.padRight(30).substring(0, 30)} '
        '│ ${item.unitPrice.toStringAsFixed(2).padRight(10)} '
        '│ ${type.padRight(6)} '
        '│ ${item.department.toString().padRight(4)} '
        '│ ${(item.barcode ?? "").padRight(10)} │',
      );
    }
    _buffer.writeln('─' * 100);
  }

  /// Log final result
  void result(int total, int success, int failed, List<String> errors) {
    section('النتيجة النهائية');
    _buffer.writeln();
    final duration = DateTime.now().difference(_startTime);
    _buffer.writeln('المدة: ${duration.inSeconds} ثانية');
    _buffer.writeln('الإجمالي: $total صنف');
    _buffer.writeln('��جاح: $success');
    _buffer.writeln('فشل: $failed');
    if (errors.isNotEmpty) {
      _buffer.writeln();
      _buffer.writeln('الأخطاء:');
      for (final err in errors) {
        _buffer.writeln('  • $err');
      }
    }
    _buffer.writeln();
    if (failed == 0 && success > 0) {
      _buffer.writeln('═══ تم الترحيل بنجاح ✓ ═══');
    } else if (success == 0) {
      _buffer.writeln('═══ فشل الترحيل بالكامل ✗ ═══');
      _buffer.writeln();
      _buffer.writeln('اقتراحات:');
      _buffer.writeln('  1. تأكد أن الميزان متصل ومشغّل');
      _buffer.writeln('  2. تأكد من عنوان IP والمنفذ الصحيح');
      _buffer.writeln('  3. جرّب طريقة "تصدير ملف CSV" واستيراده عبر برنامج PLU Manager');
      _buffer.writeln('  4. لميزان Rongta: جرّب FTP بدلاً من TCP');
    } else {
      _buffer.writeln('═══ ترحيل جزئي — $success من $total ═══');
    }
  }

  /// Save log to a temp file (NOT Desktop) and return the file path.
  /// The file is meant to be shown once and then deleted.
  Future<String> save() async {
    final tempDir = Directory.systemTemp;
    final timestamp = _startTime.toIso8601String().replaceAll(':', '-').split('.').first;
    final fileName = 'scale_upload_$timestamp.log';
    final filePath = '${tempDir.path}\\$fileName';

    await File(filePath).writeAsString(_buffer.toString(), encoding: utf8);
    debugPrint('[ScaleLog] Log saved to temp: $filePath');
    return filePath;
  }

  /// Save to temp, open in notepad, then delete after notepad closes.
  /// The log is displayed once for review and leaves no permanent file.
  Future<String> saveAndOpen({bool autoOpen = true}) async {
    final path = await save();
    if (autoOpen) {
      // notepad.exe blocks until user closes it — then we delete the file
      await Process.run('notepad.exe', [path]);
      try { await File(path).delete(); } catch (_) {}
    }
    return path;
  }

  /// Get the full log content
  String get content => _buffer.toString();

  String _hexDump(Uint8List data) {
    return data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }
}

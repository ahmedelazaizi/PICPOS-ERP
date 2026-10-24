// فحصُ مكان بيانات هذه النسخة للإعداد الأول (B14 — **للقراءة فقط**).
//
// القاعدةُ مفتوحةٌ ومشفَّرةٌ قبل المعالج، فلا يُقترَح نقلُها (‏خطرُ فقد بيانات).
// الفحصُ: مسارُ ملف القاعدة، وهل المجلدُ قابلٌ للكتابة، وهل توجد بياناتٌ سابقة
// (‏فواتير) — ما يستحقّ تنبيهاً قبل المتابعة.
//
// ⚠️ فحصُ المساحة الحرّة غير منفَّذ: لا واجهةَ عبر المنصّات بلا حزمةٍ جديدة.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/database/connection.dart' show getDatabaseFileName;

class StorageProbeResult {
  const StorageProbeResult({
    required this.path,
    required this.writable,
    this.hasPriorData = false,
    this.error,
  });

  /// مسارُ ملف القاعدة.
  final String path;
  final bool writable;
  final bool hasPriorData;
  final String? error;
}

class FirstRunStorageProbe {
  FirstRunStorageProbe({
    Future<Directory> Function()? documentsDir,
    Future<int> Function()? countInvoices,
  })  : _documentsDir = documentsDir ?? getApplicationDocumentsDirectory,
        _countInvoices = countInvoices;

  final Future<Directory> Function() _documentsDir;
  final Future<int> Function()? _countInvoices;

  Future<StorageProbeResult> probe() async {
    String path = '';
    try {
      final dir = await _documentsDir();
      path = p.join(dir.path, getDatabaseFileName());
      final marker = File(p.join(dir.path, '.picpos_write_probe'));
      await marker.writeAsString('ok', flush: true);
      await marker.delete();
      var prior = false;
      try {
        prior = ((await _countInvoices?.call()) ?? 0) > 0;
      } catch (_) {}
      return StorageProbeResult(path: path, writable: true, hasPriorData: prior);
    } catch (e) {
      return StorageProbeResult(path: path, writable: false, error: '$e');
    }
  }
}

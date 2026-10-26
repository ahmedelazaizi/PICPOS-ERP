// تحويل إضافات Flutter (SharedPreferences + التخزين الآمن) إلى مجلد
// `PICPOS_DATA_DIR` — هذه الإضافات على Windows تكتب في `%APPDATA%\<company>\
// <product>` بمسار مثبَّت في الكود الأصلي ولا يمكن تحويله بغير استبدال
// المنصّة. بدون المتغير: لا يحدث شيء (السلوك الافتراضي كما هو).
//
// تحذير: ملف التخزين الآمن هنا **نص عادي** — للمعمل فقط، لا للإنتاج.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'data_dir.dart';

/// يُستدعى مرة في بداية `main()` قبل أي استخدام للإضافات.
void installDataDirPluginRedirects() {
  final prefs = DataDir.prefsFilePath;
  final secure = DataDir.secureFilePath;
  if (prefs == null || secure == null) return;
  SharedPreferencesStorePlatform.instance = FileSharedPreferencesStore(prefs);
  FlutterSecureStoragePlatform.instance = FileSecureStoragePlatform(secure);
}

Map<String, Object?> _readJson(File f) {
  try {
    if (!f.existsSync()) return {};
    final d = jsonDecode(f.readAsStringSync());
    return d is Map ? Map<String, Object?>.from(d) : {};
  } catch (_) {
    return {};
  }
}

void _writeJson(File f, Map<String, Object?> data) {
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(jsonEncode(data), flush: true);
}

class FileSharedPreferencesStore extends SharedPreferencesStorePlatform {
  FileSharedPreferencesStore(String path) : _file = File(path);
  final File _file;
  static const _prefix = 'flutter.';

  Map<String, Object?> _load() => _readJson(_file);

  @override
  Future<bool> clear() async {
    final m = _load()..removeWhere((k, _) => k.startsWith(_prefix));
    _writeJson(_file, m);
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    final out = <String, Object>{};
    _load().forEach((k, v) {
      if (v == null) return;
      out[k] = v is List ? v.map((e) => e.toString()).toList() : v;
    });
    return out;
  }

  @override
  Future<bool> remove(String key) async {
    final m = _load()..remove(key);
    _writeJson(_file, m);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final m = _load()..[key] = value;
    _writeJson(_file, m);
    return true;
  }
}

class FileSecureStoragePlatform extends FlutterSecureStoragePlatform {
  FileSecureStoragePlatform(String path) : _file = File(path);
  final File _file;

  Map<String, String> _load() =>
      _readJson(_file).map((k, v) => MapEntry(k, '$v'));

  @override
  Future<bool> containsKey(
          {required String key, required Map<String, String> options}) async =>
      _load().containsKey(key);

  @override
  Future<void> delete(
      {required String key, required Map<String, String> options}) async {
    final m = _load()..remove(key);
    _writeJson(_file, m);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      _writeJson(_file, {});

  @override
  Future<String?> read(
          {required String key, required Map<String, String> options}) async =>
      _load()[key];

  @override
  Future<Map<String, String>> readAll(
          {required Map<String, String> options}) async =>
      _load();

  @override
  Future<void> write(
      {required String key,
      required String value,
      required Map<String, String> options}) async {
    final m = _load()..[key] = value;
    _writeJson(_file, m);
  }
}

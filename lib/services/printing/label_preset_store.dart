// حفظ مقاسات الملصقات المخصصة والمقاس النشط في SharedPreferences
// (بلا أي تغيير على مخطط قاعدة البيانات).
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'barcode_label_spec.dart';

abstract final class LabelPresetStore {
  static const customKey = 'barcode_label.custom_presets';
  static const activeKey = 'barcode_label.active_preset_id';

  /// المقاسات المخصصة المحفوظة (التالف يُتجاهل).
  static Future<List<LabelSpec>> loadCustom() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(customKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          ?LabelSpec.fromJson(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// الجاهزة ثم المخصصة.
  static Future<List<LabelSpec>> loadAll() async =>
      [...LabelSpec.presets, ...await loadCustom()];

  /// يحفظ (أو يستبدل بنفس المعرّف) مقاساً مخصصاً. يرمي [ArgumentError] لو غير صالح.
  static Future<void> saveCustom(LabelSpec spec) async {
    final error = spec.validate();
    if (error != null) throw ArgumentError('invalid label spec: $error');
    final list = (await loadCustom()).where((s) => s.id != spec.id).toList()
      ..add(spec);
    await _writeCustom(list);
  }

  static Future<void> deleteCustom(String id) async {
    final list = (await loadCustom()).where((s) => s.id != id).toList();
    await _writeCustom(list);
    if (await activeId() == id) await setActiveId(LabelSpec.defaultSpec.id);
  }

  static Future<void> _writeCustom(List<LabelSpec> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        customKey, jsonEncode([for (final s in list) s.toJson()]));
  }

  static Future<String?> activeId() async =>
      (await SharedPreferences.getInstance()).getString(activeKey);

  static Future<void> setActiveId(String id) async =>
      (await SharedPreferences.getInstance()).setString(activeKey, id);

  /// المقاس النشط؛ يرجع الافتراضي (50×25) إن لم يوجد أو حُذف.
  static Future<LabelSpec> activeSpec() async {
    final id = await activeId();
    if (id == null) return LabelSpec.defaultSpec;
    for (final s in await loadAll()) {
      if (s.id == id) return s;
    }
    return LabelSpec.defaultSpec;
  }
}

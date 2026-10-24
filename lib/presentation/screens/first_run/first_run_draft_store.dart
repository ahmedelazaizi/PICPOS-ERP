// حفظُ مسودّة الإعداد الأول — إعدادٌ واحدٌ خاصٌّ بالجهاز (`setup_draft_v2`).
//
// • الحفظ مؤجَّلٌ 500ms (debounce) كي لا تُكتَب القاعدةُ مع كلّ ضغطة مفتاح.
// • المسودّةُ لا تحوي أسراراً (‏بنيويّاً: `FirstRunDraft.toJson`)؛ والقراءةُ تتجاهل
//   التالفَ والإصدارَ المجهول ⇒ `null` (‏مسودّةٌ فارغة).
// • `setup_progress_v2` يسجّل أنّ التشغيل بدأ (`committing`) ليُعرَض بانرُ
//   «إعداد غير مكتمل» إن أُغلق التطبيقُ في منتصفه (‏C.3).
// • الوصولُ عبر دالّتَي قراءةٍ وكتابةٍ مُحقَنتَين — لا قاعدةَ هنا (حارس
//   presentation_db_import).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/utils/uuid_v7.dart';
import '../../../domain/models/first_run/first_run_draft.dart';

typedef SettingReader = Future<String?> Function(String key);
typedef SettingWriter = Future<void> Function(String key, String value);

class FirstRunDraftStore {
  FirstRunDraftStore({
    required SettingReader read,
    required SettingWriter write,
    this.debounce = const Duration(milliseconds: 500),
    String Function()? newId,
  })  : _read = read,
        _write = write,
        _newId = newId ?? UuidV7.generate;

  static const String draftKey = 'setup_draft_v2';
  static const String progressKey = 'setup_progress_v2';
  static const String committingMarker = 'committing';

  final SettingReader _read;
  final SettingWriter _write;
  final String Function() _newId;
  final Duration debounce;

  Timer? _timer;
  FirstRunDraft? _pending;

  /// مسودّةٌ جديدةٌ بمعرّفٍ جديد.
  FirstRunDraft fresh() => FirstRunDraft(
        draftId: _newId(),
        fiscalYear: DateTime.now().year,
      );

  /// المسودّةُ المحفوظة، أو `null` (‏لا شيء/تالف/إصدار آخر).
  Future<FirstRunDraft?> load() async {
    try {
      final raw = await _read(draftKey);
      if (raw == null || raw.trim().isEmpty) return null;
      return FirstRunDraft.fromJson(jsonDecode(raw), fallbackId: _newId());
    } catch (e) {
      debugPrint('[FirstRunDraftStore] ignoring unreadable draft: $e');
      return null;
    }
  }

  /// يؤجّل الحفظ؛ آخرُ نداءٍ في النافذة هو الذي يُكتَب.
  void scheduleSave(FirstRunDraft draft) {
    _pending = draft;
    _timer?.cancel();
    _timer = Timer(debounce, flush);
  }

  /// يكتب فوراً ما بقي معلَّقاً.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final d = _pending;
    _pending = null;
    if (d == null) return;
    try {
      await _write(draftKey, jsonEncode(d.toJson()));
    } catch (e) {
      debugPrint('[FirstRunDraftStore] save failed: $e');
    }
  }

  /// قراءةُ إعدادٍ آخر (‏لاشتقاق الحقائق) عبر نفس القارئ.
  Future<String?> readSetting(String key) => _read(key);

  Future<bool> wasCommitting() async {
    try {
      return (await _read(progressKey))?.contains(committingMarker) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markCommitting() async {
    await flush();
    await _write(progressKey, jsonEncode({'stage': committingMarker}));
  }

  /// بعد نجاح الإنهاء: تُمسح المسودّةُ وسجلُّ المراحل.
  Future<void> clear() async {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    await _write(draftKey, '');
    await _write(progressKey, '');
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

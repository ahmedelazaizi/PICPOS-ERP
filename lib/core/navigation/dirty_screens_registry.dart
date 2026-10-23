// سجلُّ «الشاشات المتّسخة» — شاشاتٌ فيها عملٌ لم يُحفَظ (E-1 في مراجعة الجودة).
//
// ═══ لماذا ═══
//
// الشاشاتُ تابات في `IndexedStack`، فحارسُ الرجوع/`PopScope` لا يغطّي إغلاقَ
// التاب ولا إغلاقَ النافذة: تضيع المسوّدةُ بصمت. فتُسجِّل الشاشةُ المتّسخةُ
// نفسَها هنا، ويستشير السجلَّ كلٌّ من إغلاقِ التاب (`_closeTab`) وإغلاقِ
// النافذة/البرنامج (`handleWindowClose`/زرّ «إغلاق البرنامج»).
//
// السجلُّ لا يعرف شيئاً عن الحوار: كلُّ شاشةٍ تعطيه [confirmDiscard] الذي
// يسأل بلغتها، ويرجع `true` إن وافق المستخدمُ على إسقاط ما لم يُحفَظ.
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DirtyScreenEntry {
  const DirtyScreenEntry({
    required this.screenIndex,
    required this.isDirty,
    required this.confirmDiscard,
  });

  /// فهرسُ التاب (`ScreenId.navigationIndex`)؛ `null` لشاشةٍ ليست تاباً.
  final int? screenIndex;
  final bool Function() isDirty;
  final Future<bool> Function() confirmDiscard;
}

class DirtyScreensRegistry {
  final Map<Object, DirtyScreenEntry> _entries = <Object, DirtyScreenEntry>{};

  void register(
    Object owner, {
    required int? screenIndex,
    required bool Function() isDirty,
    required Future<bool> Function() confirmDiscard,
  }) {
    _entries[owner] = DirtyScreenEntry(
      screenIndex: screenIndex,
      isDirty: isDirty,
      confirmDiscard: confirmDiscard,
    );
  }

  void unregister(Object owner) => _entries.remove(owner);

  /// هل في السجلِّ شاشةٌ متّسخة (للتاب [screenIndex] إن حُدّد)؟
  bool hasDirty({int? screenIndex}) => _entries.values.any((e) =>
      e.isDirty() && (screenIndex == null || e.screenIndex == screenIndex));

  /// يسأل عن كلّ شاشةٍ متّسخةٍ في التاب [screenIndex]؛ `false` ⇒ ابقَ.
  Future<bool> confirmCloseScreen(int screenIndex) =>
      _confirm(_entries.values.where((e) => e.screenIndex == screenIndex));

  /// يسأل عن كلّ الشاشات المتّسخة قبل إغلاق النافذة/البرنامج؛ `false` ⇒ ابقَ.
  Future<bool> confirmCloseAll() => _confirm(_entries.values);

  Future<bool> _confirm(Iterable<DirtyScreenEntry> candidates) async {
    // نسخةٌ: الحوارُ async وقد يتغيّر السجلُّ أثناءه.
    for (final e in candidates.toList()) {
      if (!e.isDirty()) continue;
      if (!await e.confirmDiscard()) return false;
    }
    return true;
  }
}

final dirtyScreensRegistryProvider =
    Provider<DirtyScreensRegistry>((ref) => DirtyScreensRegistry());
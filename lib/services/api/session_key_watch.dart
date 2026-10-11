/// يراقب `sessionKeyId` المُعلَن في `/api/health` من جهة العميل/المرآة.
///
/// تدويرُ/تغيّرُ مفتاح الجلسات يُبطل كلَّ رمز، وقراءاتُ GET المقيّدةُ بالفرع
/// تفشل مغلقةً (فارغة، لا 401) فيبقى العميلُ «أعمى» حتى 12 ساعة. فعند تغيّر
/// المعرّف في دورة الفحص نُبطل الرموزَ المخزّنة (الإثباتات تبقى) ليُعاد السكّ.
class SessionKeyWatch {
  String? _lastId;

  String? get lastId => _lastId;

  /// يسجّل [id] القادم من الخادم. يعيد `true` (ويستدعي [onChanged]) فقط إذا
  /// كان معرّفٌ سابقٌ معروفاً وتغيّر. الغيابُ (خادمٌ أقدم) لا يغيّر شيئاً.
  bool observe(Object? id, void Function() onChanged) {
    if (id is! String || id.isEmpty) return false;
    final previous = _lastId;
    _lastId = id;
    if (previous != null && previous != id) {
      onChanged();
      return true;
    }
    return false;
  }

  void reset() => _lastId = null;
}

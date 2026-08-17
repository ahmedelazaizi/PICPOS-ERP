/// حالاتُ الطاولة الخمس.
///
/// المخطّطُ كان يذكر ثمانيَ حالاتٍ في تعليق (`seated, ordered, eating,
/// billing, cleaning`) أكثرُها غيرُ مستعمَل. و`billing` تحديداً صفةٌ للطلب
/// (`TableOrders.status = 'bill_requested'`) لا للطاولة.
abstract final class TableStatus {
  /// 🟢 لا طلبَ عليها.
  static const available = 'available';

  /// 🔵 طلبٌ مفتوح — ولو دُفع منه جزء.
  static const occupied = 'occupied';

  /// 🟠 سُدِّد كاملاً ولم يُغلَق بعد.
  static const paid = 'paid';

  /// 🔴 حجزٌ مسبق.
  static const reserved = 'reserved';

  /// ⚪ خارج الخدمة.
  static const outOfService = 'out_of_service';

  static const all = [available, occupied, paid, reserved, outOfService];
}

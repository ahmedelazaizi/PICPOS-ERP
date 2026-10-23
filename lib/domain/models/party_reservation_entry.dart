/// سطرٌ في «حجوزات العميل» — يجمع حجوزاتِ الخدمات (`bookings`) وحجوزاتِ
/// الطاولات (`table_reservations`) في قائمةٍ واحدة (ملفُّ العميل + بطاقةُ المنتقي).
class PartyReservationEntry {
  const PartyReservationEntry({
    required this.kind,
    required this.id,
    required this.at,
    required this.status,
    required this.place,
    this.partySize,
    this.amount = 0,
    this.invoiceNumber,
    this.customerName = '',
  });

  /// `booking` أو `table`.
  final String kind;
  final int id;
  final DateTime at;
  final String status;

  /// اسمُ الخدمة (حجز) أو اسمُ الطاولة (حجز طاولة).
  final String place;
  final int? partySize;

  /// العربونُ المحجوز (حجوزات الخدمات فقط).
  final double amount;
  final String? invoiceNumber;

  /// لقطةُ الاسم وقتَ الحجز (التاريخ).
  final String customerName;

  bool get isTable => kind == 'table';
}

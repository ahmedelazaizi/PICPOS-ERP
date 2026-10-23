/// قيمةُ `CustomerPickerField`: عميلٌ مسجَّلٌ (`partyId` غيرُ معدوم) أو ضيفٌ
/// (اسمٌ وهاتفٌ نصّاً فقط). الاسمُ والهاتفُ دائماً **لقطةٌ** تُحفَظ مع الحجز
/// حتى لو تغيّر الطرفُ لاحقاً.
class CustomerPickerValue {
  const CustomerPickerValue({this.partyId, this.name = '', this.phone = ''});

  static const CustomerPickerValue empty = CustomerPickerValue();

  final int? partyId;
  final String name;
  final String phone;

  bool get isGuest => partyId == null;
  bool get isEmpty =>
      partyId == null && name.trim().isEmpty && phone.trim().isEmpty;

  /// الهاتفُ للكتابة (`null` إن كان فارغاً).
  String? get phoneOrNull => phone.trim().isEmpty ? null : phone.trim();

  @override
  bool operator ==(Object other) =>
      other is CustomerPickerValue &&
      other.partyId == partyId &&
      other.name == name &&
      other.phone == phone;

  @override
  int get hashCode => Object.hash(partyId, name, phone);

  @override
  String toString() => 'CustomerPickerValue($partyId, $name, $phone)';
}

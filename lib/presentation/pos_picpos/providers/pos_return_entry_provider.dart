// `StateProvider` في `legacy.dart` منذ Riverpod 3 — كما في `pos_return_mode_provider`.
import 'package:flutter_riverpod/legacy.dart';

/// «وضع إدخال: مرتجع» (بند ٤ — المرتجع السريع بلا فاتورة).
///
/// `true` ⇒ كلُّ صنفٍ يُمسَح أو يُضغَط في الشبكة يُضاف **سطرَ مرتجعٍ** بكميّة ١
/// بدل سطر بيع. مفتاحٌ يدويٌّ يُطفئه الكاشير، ويُطفأ آلياً بعد كل حفظٍ ناجح
/// وبعد إلغاء الفاتورة — فلا يبقى مشتعلاً على زبونٍ تالٍ فيُسجَّل بيعُه مرتجعاً.
///
/// مستقلٌّ عن [posReturnModeProvider] (المرتجع المرتبط بفاتورة): الوضعان
/// حصريّان، فتفعيلُ أحدهما يرفضه الآخر (انظر `picpos_pos_no_invoice_return.dart`).
final posReturnEntryModeProvider = StateProvider<bool>((ref) => false);

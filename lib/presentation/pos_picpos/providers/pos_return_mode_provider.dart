// `StateProvider` انتقل إلى `legacy.dart` في Riverpod 3.x (نُقل من الحزمة
// الرئيسيّة تشجيعاً على `Notifier`)، لكنه يبقى الأنسبَ هنا: [PosReturnMode]
// خالصةٌ ومتغيّرةٌ داخلياً بالفعل (‏`setQty`/`clearQty`)، فكلُّ ما يحتاجه
// هذا المزوّد تبديلٌ كاملٌ للمرجع — لا منطقَ تحديثٍ يستحقّ `Notifier` مخصَّص.
import 'package:flutter_riverpod/legacy.dart';

import '../state/pos_return_mode.dart';

/// حالةُ وضع المرتجع الحاليّة في شاشة نقطة بيع PicPos — `null` يعني وضعَ
/// البيع العاديّ، وأيُّ [PosReturnMode] غيرِ `null` يعني أن السلّة الحاليّة
/// أصبحت مردوداً مربوطاً بفاتورته (المهمّة ٧).
///
/// `StateProvider` لا `Notifier`: [PosReturnMode] خالصةٌ ومتغيّرة داخلياً
/// (‏`setQty`/`clearQty` تُحدِّث خرائطَها الداخليّة)، فكلُّ ما يحتاجه هذا
/// المزوّد هو تبديلٌ كاملٌ للمرجع — بناءُ وضعٍ جديدٍ عند اختيار فاتورةٍ
/// للمرتجع، وإرجاعٌ لـ`null` عند الحفظ أو الإلغاء.
///
/// عمداً في ملفٍّ منفصل عن `state/pos_return_mode.dart`: ذاك الملفُّ خالصٌ
/// بلا Riverpod ليُختبر بلا `ProviderContainer` — راجع تعليقَ رأسِه ووثيقةَ
/// تقرير المهمّة ٦. إدخالُ `flutter_riverpod` هناك كان سيكسر ذلك بلا داعٍ.
final posReturnModeProvider = StateProvider<PosReturnMode?>((ref) => null);

import 'package:picpos_erp/core/i18n/tr.dart';
import '../../../core/constants/app_constants.dart';
import '../widgets/modifier_selection_dialog.dart';

// منقولٌ حرفياً من cart_controller.dart (سقف الحجم)؛ يُعاد تصديره من هناك.

/// بادئة سطر العرض **التلقائي** — كل جولة تطبيق بتصفّره وتعيد حسابه.
String get kAutoOfferNotePrefix => tr('عرض:');

/// بادئة سطر العرض **اليدوي** — إنسان طبّقه، فما بيتلمسش.
///
/// ⚠️ `'عرض (يدوي):'` **ما بيبدأش** بـ`'عرض:'` — بعد «عرض» بييجي « (» مش «:».
/// اللي بيسأل «هل ده سطر عرض؟» بـ`startsWith(kAutoOfferNotePrefix)` لوحدها
/// بيرجّع false للسطر اليدوي فيعامله كسطر أساس عادي. ده كان مصدر عطل ٣-٣.
String get kManualOfferNotePrefix => tr('عرض (يدوي):');

/// هل السطر ده سطر عرض بأي شكل — تلقائي أو يدوي؟
///
/// ده السؤال اللي كل حلقات التطبيق عايزة تسأله: «هل السطر ده متسعّر بعرض
/// خلاص فما ينفعش أعيد تسعيره / أعدّه ككمية أساس؟». ستة مواضع كانت بتسأله
/// بفلتر أضيق (التلقائي بس)، فسطر الخصم اليدوي كان بيتكتب فوقه، وملاحظته
/// بتتحوّل لـ`عرض:` فالجولة اللي بعدها بتصفّره لسعر الأساس ⇒ الخصم اليدوي
/// يتدمّر نهائياً والعميل يتحمّل زيادة.
bool isOfferLineNote(String? note) =>
    note != null &&
    (note.startsWith(kAutoOfferNotePrefix) ||
        note.startsWith(kManualOfferNotePrefix));

/// يبني نص `CartItemEntity.note` المركّب من المعدِّلات + الملاحظة اليدوية.
///
/// ── ليه دالة واحدة ─────────────────────────────────────────────────────────
/// نفس التركيب كان مكرَّر حرفياً في `updateItemModifiers` و`updateItemNote`.
/// أي مسار تالت بيكتب `note` مباشرة (زي ما كان بيحصل في شاشة خدمة الطاولات)
/// بيمسح المعدِّلات من النص من غير ما يمسحها من `item.modifiers` — فالفاتورة
/// المطبوعة بتخسر الإضافات والمطبخ بيحضّر الطلب غلط. الحقل `itemNote` هو
/// **مصدر الملاحظة اليدوية الوحيد**، و`note` مخرج مشتق بيتبني هنا بس.
///
/// النص الناتج بيتقرا كمان في `templated_invoice_service.dart` اللي بيحوّل
/// `📝 ` لـ«ملاحظة: » و` | ` لسطر جديد — فالبادئة جزء من العقد مش تزيين.
String? composeCartItemNote(
  List<SelectedModifier> modifiers,
  String? itemNote,
) {
  final parts = <String>[];
  for (final m in modifiers) {
    if (m.isOption) {
      // Include quantity level label (قليل/بدون/كثير) when set
      final levelLabel = m.quantityLevel.label;
      final optionText =
          levelLabel.isNotEmpty ? '$levelLabel ${m.itemName}' : m.itemName;
      parts.add('(${m.groupName}: $optionText)');
    } else {
      parts.add('+${m.itemName}${m.extraPrice > 0 ? ' ${m.extraPrice.toStringAsFixed(0)} ${AppConstants.currencySymbolEn}' : ''}');
    }
  }
  if (itemNote != null && itemNote.isNotEmpty) {
    parts.add('📝 $itemNote');
  }
  return parts.isNotEmpty ? parts.join(' | ') : null;
}

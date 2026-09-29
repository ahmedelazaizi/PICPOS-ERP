part of 'pos_table_service_screen.dart';

/// فحص صريح قبل فتح ديالوج ملاحظة الصنف في شاشة خدمة الطاولات — مسار كتابة
/// مستقل تماماً عن `updateItemNote` (اللي بيحمي حقل الملاحظة في
/// `cart_item_modifier_panel.dart`): `_showNoteDialog` تحت بيكتب
/// `item.copyWith(note: ...)` مباشرة على حالة السلة، متجاوز `updateItemNote`
/// خالص. اتكشف في مراجعة Task 7 — التريَّاج الأول عدّ فورك ين للبيع (UralCash
/// وPicPos) وفاته إن `TablePosScreen` (خدمة الطاولات) فورك تالت بمساره
/// الخاص بالكامل، بما فيه مسار ملاحظة منفصل.
@visibleForTesting
bool canAddPosNote(List<String> permissions) {
  final isAdmin =
      permissions.contains('system_admin') || permissions.contains('*');
  return isAdmin || permissions.contains(PermissionCodes.posNoteAdd);
}

/// نسخة أعلى مستوى بتقرا الصلاحيات من `ref` وتعرض توست الرفض — سطر واحد في
/// نقطة الاستدعاء (زي بواقي الأكواد في هذه الدفعة).
@visibleForTesting
Future<bool> ensurePosNoteAddPermission(
  WidgetRef ref,
  BuildContext context,
) async {
  final permissions =
      ref.read(currentUserPermissionsProvider).asData?.value ??
          const <String>[];
  if (canAddPosNote(permissions)) return true;
  if (context.mounted) {
    showPosToast(
      context,
      ref,
      tr('ليس لديك صلاحية إضافة ملاحظة للصنف'),
      type: PosNotificationType.error,
    );
  }
  return false;
}

/// يكتب ملاحظة المطبخ على صنف في سلة شاشة خدمة الطاولات.
///
/// ── ليه مش `copyWith(note: ...)` زي الأول ───────────────────────────────────
/// `note` حقل **مشتق** من `modifiers` + `itemNote`، والكتابة المباشرة عليه
/// كانت بتخلّي المشتق يخالف مصدره: `item.modifiers` فيها «الحجم: كبير» والنص
/// المطبوع مفيهوش، فالمطبخ بيحضّر الطلب من غير الإضافات. وطبقتَي الطباعة
/// بتفكّكا النص بـ` | ` و`📝 ` — الشكل المركّب عقد مش تزيين.
///
/// نص فاضي = «امسح الملاحظة» (زرار «حذف الملاحظة» بيرجّع `''`).
@visibleForTesting
void applyTablePosItemNote(CartController cart, int index, String note) {
  cart.updateItemNote(index, note.isEmpty ? null : note);
}

mixin _TablePosDialogsMixin on ConsumerState<TablePosScreen> {
  /// Show note dialog for an item (kitchen instructions)
  Future<void> _showNoteDialog(int index, CartItemEntity item) async {
    // `itemNote` مش `note`: التاني فيه نص المعدِّلات كمان، ولو اتعرض في خانة
    // الملاحظة الجرسون هيحفظه كملاحظة يدوية فيتضاعف عند أول إعادة تركيب.
    final controller = TextEditingController(text: item.itemNote ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.notepad,
                  color: Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 8),
              Text(tr('ملاحظات المطبخ'),
                  style: GoogleFonts.cairo(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.productName,
                  style: GoogleFonts.cairo(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                style: GoogleFonts.cairo(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: tr('مثال: بدون بصل، سكر زيادة، نص سوى...'),
                  hintStyle: GoogleFonts.cairo(
                      color: Colors.white.withValues(alpha: 0.2),
                      fontSize: 12),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Quick-add common notes
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _quickNote(tr('بدون بصل'), controller),
                  _quickNote(tr('سكر زيادة'), controller),
                  _quickNote(tr('بدون ملح'), controller),
                  _quickNote(tr('حار'), controller),
                  _quickNote(tr('بدون ثلج'), controller),
                  _quickNote(tr('نص سوى'), controller),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('إلغاء'),
                  style: GoogleFonts.cairo(
                      color: Colors.white.withValues(alpha: 0.5))),
            ),
            if (item.itemNote != null && item.itemNote!.isNotEmpty)
              TextButton(
                onPressed: () {
                  controller.clear();
                  Navigator.pop(ctx, '');
                },
                child: Text(tr('حذف الملاحظة'),
                    style: GoogleFonts.cairo(color: const Color(0xFFEF4444))),
              ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(tr('حفظ'), style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );

    if (note != null && mounted) {
      applyTablePosItemNote(
        ref.read(cartControllerProvider.notifier),
        index,
        note,
      );
    }
  }

  Widget _quickNote(String text, TextEditingController controller) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (controller.text.isNotEmpty) {
            controller.text = tr('{p0}، {text}', {'p0': controller.text, 'text': text});
          } else {
            controller.text = text;
          }
          controller.selection =
              TextSelection.collapsed(offset: controller.text.length);
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Text(text,
              style: GoogleFonts.cairo(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.5))),
        ),
      ),
    );
  }
}

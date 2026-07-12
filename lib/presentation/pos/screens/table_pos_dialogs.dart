part of 'pos_table_service_screen.dart';

mixin _TablePosDialogsMixin on ConsumerState<TablePosScreen> {
  /// Show note dialog for an item (kitchen instructions)
  Future<void> _showNoteDialog(int index, CartItemEntity item) async {
    final controller = TextEditingController(text: item.note ?? '');
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
              Text('ملاحظات المطبخ',
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
                  hintText: 'مثال: بدون بصل، سكر زيادة، نص سوى...',
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
                  _quickNote('بدون بصل', controller),
                  _quickNote('سكر زيادة', controller),
                  _quickNote('بدون ملح', controller),
                  _quickNote('حار', controller),
                  _quickNote('بدون ثلج', controller),
                  _quickNote('نص سوى', controller),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: GoogleFonts.cairo(
                      color: Colors.white.withValues(alpha: 0.5))),
            ),
            if (item.note != null && item.note!.isNotEmpty)
              TextButton(
                onPressed: () {
                  controller.clear();
                  Navigator.pop(ctx, '');
                },
                child: Text('حذف الملاحظة',
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
              child: Text('حفظ', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );

    if (note != null && mounted) {
      // Update the cart item note
      final items =
          List<CartItemEntity>.from(ref.read(cartControllerProvider).items);
      items[index] = item.copyWith(note: note.isEmpty ? null : note);
      ref.read(cartControllerProvider.notifier).state =
          ref.read(cartControllerProvider).copyWith(items: items);
    }
  }

  Widget _quickNote(String text, TextEditingController controller) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (controller.text.isNotEmpty) {
            controller.text = '${controller.text}، $text';
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

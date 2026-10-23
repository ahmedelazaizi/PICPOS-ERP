part of '../tables_screen.dart';

// حوارُ حجزِ طاولة — نُقل من `table_operations.dart` (الملفُّ ratcheted) مع
// استبدال حقلَي الاسم/الهاتف بـ`CustomerPickerField` (P3): الحجزُ يحفظ
// `partyId` إن اختير عميلٌ مسجَّل، والاسمُ/الهاتفُ لقطةٌ دائماً. ضيفٌ بلا
// تسجيل ممكنٌ (partyId = null).

/// يفتح حوارَ حجز [table]. الحفظُ عبر `TableSessionService.reserveTable`
/// (يكتب الصفَّ ويترك أثراً في سجلّ العمليات).
void showTableReservationDialog(
  BuildContext context,
  WidgetRef ref,
  RestaurantTable table,
) {
  final notesController = TextEditingController();
  var customer = CustomerPickerValue.empty;
  int partySize = table.capacity;
  DateTime reservationTime = DateTime.now().add(const Duration(hours: 1));
  bool saving = false;

  showDialog(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (ctx, setDialogState) => PopScope(
          canPop: !saving,
          child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.calendarPlus, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(tr('حجز {p0}', {'p0': table.name})),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomerPickerField(
                    label: tr('اسم العميل *'),
                    value: customer,
                    onChanged: (v) => setDialogState(() => customer = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: ctx,
                              initialDate: reservationTime,
                              firstDate: DateTime.now(),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 30)),
                            );
                            if (date != null) {
                              setDialogState(() {
                                reservationTime = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  reservationTime.hour,
                                  reservationTime.minute,
                                );
                              });
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: tr('التاريخ'),
                              prefixIcon: const Icon(PhosphorIconsBold.calendar),
                            ),
                            child: Text(
                              '${reservationTime.day}/${reservationTime.month}/${reservationTime.year}',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final time = await showTimePicker(
                              context: ctx,
                              initialTime:
                                  TimeOfDay.fromDateTime(reservationTime),
                            );
                            if (time != null) {
                              setDialogState(() {
                                reservationTime = DateTime(
                                  reservationTime.year,
                                  reservationTime.month,
                                  reservationTime.day,
                                  time.hour,
                                  time.minute,
                                );
                              });
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: tr('الوقت'),
                              prefixIcon: const Icon(PhosphorIconsBold.clock),
                            ),
                            child: Text(
                              '${reservationTime.hour.toString().padLeft(2, '0')}:${reservationTime.minute.toString().padLeft(2, '0')}',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(tr('عدد الأشخاص: ')),
                      IconButton(
                        onPressed: partySize > 1
                            ? () => setDialogState(() => partySize--)
                            : null,
                        icon: const Icon(PhosphorIconsBold.minus),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$partySize',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setDialogState(() => partySize++),
                        icon: const Icon(PhosphorIconsBold.plus),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: tr('ملاحظات'),
                      prefixIcon: const Icon(PhosphorIconsBold.notepad),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text(tr('إلغاء')),
            ),
            ElevatedButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      // علَمٌ متزامنٌ: نقرتان قبل إعادة بناء الزرّ تُنفّذان
                      // الحفظَ مرّتين (E-3).
                      if (saving) return;
                      if (customer.name.trim().isEmpty) {
                        AppToast.show(
                          ctx,
                          tr('يرجى إدخال اسم العميل'),
                          type: ToastType.warning,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        // نداءُ الخدمة لا المستودعِ: `reserveTable` تكتب صفَّ
                        // الحجز **وتترك أثراً** في `ActivityLogs`.
                        final user = ref.read(authProvider).user;
                        await ref.read(tableSessionServiceProvider).reserveTable(
                              tableId: table.id,
                              customerName: customer.name.trim(),
                              customerPhone: customer.phoneOrNull,
                              partyId: customer.partyId,
                              reservationTime: reservationTime,
                              partySize: partySize,
                              notes: notesController.text.trim().isNotEmpty
                                  ? notesController.text.trim()
                                  : null,
                              userId: user?.id,
                              userName: user?.displayName ?? tr('مجهول'),
                            );

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          AppToast.show(
                            context,
                            tr('تم حجز {p0} بنجاح', {'p0': table.name}),
                            type: ToastType.success,
                          );
                        }
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setDialogState(() => saving = false);
                        if (ctx.mounted) {
                          AppToast.show(ctx, tr('خطأ: {e}', {'e': e}),
                              type: ToastType.error);
                        }
                      }
                    },
              icon: const Icon(PhosphorIconsBold.calendarCheck, size: 18),
              label: Text(tr('تأكيد الحجز')),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            ),
          ],
        ),
        ),
      ),
    ),
  );
}

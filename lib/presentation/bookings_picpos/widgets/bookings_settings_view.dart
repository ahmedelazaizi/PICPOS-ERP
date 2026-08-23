// إعداداتُ الحجوزات.
//
// ═══ ⚠️ إعدادٌ واحدٌ يعمل خيرٌ من ستّةٍ تُرسم ولا تفعل ═══
//
// التصميمُ يرسم صفَّ مفاتيحَ وقيم. وبناؤها جميعاً «شكلاً» يعني مفاتيحَ
// تُقلَب ولا يتبدّل بها سلوكٌ — وهو أسوأُ من غيابها: المستخدمُ يظنّ أنه
// ضبط شيئاً. فهنا **مهلةُ التذكير** وحدَها لأنها تُحفَظ وتُقرأ فعلاً،
// ومعها حقائقُ قابلةٌ للتصرّف تُقرأ من القاعدة لا تُخترَع.
//
// ⚠️ والقراءةُ **غيرُ متزامنة** عن قصد: القراءةُ المتزامنة
// (`SettingsRepositoryCached.get`) ترجع `null` عند إخفاق الكاش بنفس ما
// ترجعه عند غياب المفتاح، فتموت الميزةُ صامتةً ما لم يُسجَّل المفتاحُ في
// `preloadKeys` بـ`main.dart`. والقراءةُ هنا عبر المستودع مباشرةً فلا تحتاج
// ذلك التسجيل.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';

// ⚠️ `bookingReminderOffsetKey` و`bookingReminderOffsetDefault` انتقلا إلى
// `data/database/tables/booking_tables.dart` — يحتاجهما مولِّدُ التذكيرات في
// الـDAO، ولا يجوز أن تستوردَ طبقةُ البيانات من طبقة العرض. وهما يصلان هنا
// عبر `providers.dart` المستوردةِ أصلاً.

final bookingReminderOffsetProvider = FutureProvider<int>((ref) async {
  final raw =
      await ref.watch(databaseProvider).getSettingValue(bookingReminderOffsetKey);
  return int.tryParse(raw ?? '') ?? bookingReminderOffsetDefault;
});

class BookingsSettingsView extends ConsumerWidget {
  const BookingsSettingsView({super.key});

  static const _choices = [15, 30, 60, 120, 180];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final offset = ref.watch(bookingReminderOffsetProvider).value ??
        bookingReminderOffsetDefault;
    final services = ref.watch(bookingServicesProvider).value ?? const [];
    final resources = ref.watch(bookingResourcesProvider).value ?? const [];
    final unlinked = services.where((s) => s.productId == null).toList();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _section('التذكيرات'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.bellRinging,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('مهلة التذكير الافتراضية',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    Text(
                      'كم دقيقة قبل الموعد يُجدوَل التذكير للحجوزات الجديدة.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              DropdownButton<int>(
                value: _choices.contains(offset) ? offset : _choices.last,
                underline: const SizedBox.shrink(),
                items: [
                  for (final m in _choices)
                    DropdownMenuItem(
                      value: m,
                      child: Text(
                        m < 60 ? '$m دقيقة' : 'قبل ${m ~/ 60} ساعة',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  await ref
                      .read(databaseProvider)
                      .setSetting(bookingReminderOffsetKey, '$v');
                  ref.invalidate(bookingReminderOffsetProvider);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _section('حالة التجهيز'),
        _fact(
          context,
          icon: PhosphorIconsBold.scissors,
          label: 'الخدمات النشِطة',
          value: '${services.length}',
        ),
        _fact(
          context,
          icon: PhosphorIconsBold.users,
          label: 'الموارد (موظَّفون وأجهزة)',
          value: '${resources.length}',
        ),
        // ⚠️ حقيقةٌ قابلةٌ للتصرّف لا زينة: خدمةٌ بلا صنفٍ مربوطٍ **لا
        // تُفوتَر** — يرفضها `assertBookingInvoiceable`. فتُسمَّى هنا بالاسم
        // قبل أن يصطدم بها الكاشيرُ لحظةَ التحويل.
        _fact(
          context,
          icon: PhosphorIconsBold.linkBreak,
          label: 'خدمات غير مربوطة بصنف — لا يمكن تفويتر حجوزها',
          value: '${unlinked.length}',
          tone: unlinked.isEmpty ? AppColors.success : AppColors.warning,
          detail: unlinked.isEmpty
              ? null
              : unlinked.map((s) => s.name).join(' · '),
        ),
      ],
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      );

  Widget _fact(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color tone = AppColors.info,
    String? detail,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                if (detail != null)
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}

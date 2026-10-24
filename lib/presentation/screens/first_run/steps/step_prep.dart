// الخطوة ٥ (مستقل/مقرّ) — تجهيز النشاط: اسمُ الصندوق، وللمطاعم طريقةُ الخدمة
// وعددُ الطاولات، ونمطُ اللمس لهذا الجهاز. الطابعةُ تُجهَّز بعد البدء (B16).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../domain/models/first_run/first_run_packs.dart';
import '../../../picpos_shell/picpos_surface.dart';
import '../first_run_controller.dart';
import '../widgets/first_run_callout.dart';
import '../widgets/first_run_choice_card.dart';
import '../widgets/first_run_field.dart';

String _serviceTitle(FirstRunServiceType t) => switch (t) {
      FirstRunServiceType.all => tr('طاولات + سفري + توصيل'),
      FirstRunServiceType.takeawayDelivery => tr('سفري وتوصيل فقط'),
      FirstRunServiceType.tablesOnly => tr('طاولات فقط'),
    };

class StepPrep extends ConsumerWidget {
  const StepPrep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(firstRunControllerProvider.select((s) => s.draft));
    final ctl = ref.read(firstRunControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FirstRunField(
          key: const Key('first_run_cashbox_name'),
          label: tr('اسم الصندوق الرئيسي (اختياري)'),
          value: d.cashBoxName,
          hint: tr('يُترك كما هو إن لم تكتب شيئًا'),
          onChanged: (v) => ctl.update((x) => x.copyWith(cashBoxName: v)),
        ),
        if (d.pack.hasTables) ...[
          const SizedBox(height: 18),
          Text(
            tr('طريقة خدمة المطعم'),
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: context.picposText,
            ),
          ),
          const SizedBox(height: 8),
          for (final t in FirstRunServiceType.values) ...[
            FirstRunChoiceCard(
              key: Key('first_run_service_${t.name}'),
              icon: t.tables ? Icons.table_restaurant_outlined : Icons.delivery_dining_outlined,
              title: _serviceTitle(t),
              subtitle: '',
              selected: d.serviceType == t,
              onTap: () => ctl.update((x) => x.copyWith(serviceType: t)),
            ),
            const SizedBox(height: 8),
          ],
          if (d.serviceType.tables)
            SizedBox(
              width: 240,
              child: FirstRunField(
                key: const Key('first_run_tables_count'),
                label: tr('عدد الطاولات المبدئي'),
                value: d.tablesCount,
                ltr: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                onChanged: (v) => ctl.update((x) => x.copyWith(tablesCount: v)),
              ),
            ),
        ],
        const SizedBox(height: 14),
        SwitchListTile(
          key: const Key('first_run_touch_mode'),
          contentPadding: EdgeInsets.zero,
          title: Text(tr('وضع اللمس (لوحة مفاتيح على الشاشة)')),
          subtitle: Text(tr('لهذا الجهاز فقط، ويمكن تغييره لاحقًا.')),
          value: d.touchMode,
          onChanged: (v) => ctl.update((x) => x.copyWith(touchMode: v)),
        ),
        const SizedBox(height: 10),
        FirstRunCallout(
          title: tr('الطابعة والمطبخ يُجهَّزان بعد البدء.'),
          body: tr('من الإعدادات › الطابعات. لا حاجة لهما لإكمال الإعداد.'),
          icon: Icons.print_outlined,
        ),
      ],
    );
  }
}

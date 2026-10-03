// J4 — تبويبُ «السجل»: أحداثُ الموظف (تعيينٌ ونقلٌ وترقيةٌ وتعديلُ راتبٍ
// وإنهاءُ خدمةٍ وربطُ مستخدم…) تُسجَّل آليّاً عند الحفظ، الأحدثُ أوّلاً.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_labels.dart';
import '../hr_picpos_providers.dart';
import '../widgets/hr_form_kit.dart';

class EfHistoryTab extends ConsumerWidget {
  const EfHistoryTab({super.key, required this.employeeId});
  final int? employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = employeeId;
    final events = id == null
        ? const <EmployeeHistoryEvent>[]
        : ref.watch(hrHistoryProvider(id)).value ??
            const <EmployeeHistoryEvent>[];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        HrSection(
          title: tr('سجل الموظف'),
          icon: PhosphorIconsBold.clockCounterClockwise,
          child: events.isEmpty
              ? PicPosEmptyState(
                  icon: PhosphorIconsBold.clockCounterClockwise,
                  title: tr('لا أحداث بعد'),
                  hint: tr('يُسجَّل التعيين والنقل والترقية وإنهاء الخدمة تلقائياً عند الحفظ'),
                )
              : Column(children: [
                  for (final e in events)
                    Container(
                      key: Key('ef_event_${e.id}'),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: context.picposField,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Row(children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(hrEventIcon(e.eventType),
                              size: 17, color: context.picposBrandInk),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(hrEventLabel(e.eventType),
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: context.picposText)),
                              if (e.fromValue != null || e.toValue != null)
                                Text(
                                  '${hrEventValue(e.eventType, e.fromValue)}  '
                                  '${Directionality.of(context) == TextDirection.rtl ? '←' : '→'}  '
                                  '${hrEventValue(e.eventType, e.toValue)}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12, color: context.picposMuted),
                                ),
                              if (e.notes != null)
                                Text(e.notes!,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: context.picposMuted)),
                            ],
                          ),
                        ),
                        Text(hrDate(e.eventDate),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: context.picposMuted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ]),
                    ),
                ]),
        ),
      ],
    );
  }
}

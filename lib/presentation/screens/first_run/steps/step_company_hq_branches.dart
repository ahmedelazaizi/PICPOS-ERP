// جدولُ «الفروع التابعة» لمسار المقرّ — رمزٌ (LTR، ≤ 10) واسمٌ لكلّ فرع، «+ إضافة
// فرع» يولّد رمزاً `BR-NN` غير مستعمل. حذفُ فرعٍ ينقل مستخدميه إلى `HQ`
// (‏قاعدة النموذج §0.5)، وتعديلُ رمزه ينقل إليه مستخدميه.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../domain/models/first_run/first_run_draft.dart';
import '../../../picpos_shell/picpos_surface.dart';
import '../first_run_controller.dart';
import '../widgets/first_run_callout.dart';
import '../widgets/first_run_field.dart';

String _nextBranchCode(List<FirstRunBranchRow> rows) {
  final used = {for (final r in rows) r.code.trim().toUpperCase()};
  for (var n = 1; n < 1000; n++) {
    final code = 'BR-${n.toString().padLeft(2, '0')}';
    if (!used.contains(code)) return code;
  }
  return 'BR-${rows.length + 1}';
}

class HqBranchesSection extends ConsumerWidget {
  const HqBranchesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(firstRunControllerProvider.select((s) => s.draft));
    final ctl = ref.read(firstRunControllerProvider.notifier);

    void setRows(List<FirstRunBranchRow> rows, {List<FirstRunUserRow>? users}) =>
        ctl.update((x) => x.copyWith(branches: rows, hqUsers: users));

    void rename(int i, String code) {
      final old = d.branches[i].code.trim().toUpperCase();
      final rows = [...d.branches];
      rows[i] = FirstRunBranchRow(code: code, name: rows[i].name);
      final next = code.trim().toUpperCase();
      setRows(rows, users: [
        for (final u in d.hqUsers)
          old.isNotEmpty && u.scope.trim().toUpperCase() == old
              ? u.copyWith(scope: next.isEmpty ? 'HQ' : next)
              : u,
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Text(
          tr('الفروع التابعة'),
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: context.picposText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tr('الفرع الرئيسي أعلاه يُنشأ دائمًا. أضف هنا الفروع الأخرى.'),
          style: TextStyle(fontSize: 12, color: context.picposMuted),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < d.branches.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 130,
                  child: FirstRunField(
                    key: Key('first_run_hq_branch_code_$i'),
                    label: tr('رمز الفرع'),
                    value: d.branches[i].code,
                    ltr: true,
                    maxLength: 10,
                    onChanged: (v) => rename(i, v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FirstRunField(
                    key: Key('first_run_hq_branch_name_$i'),
                    label: tr('اسم الفرع'),
                    value: d.branches[i].name,
                    onChanged: (v) {
                      final rows = [...d.branches];
                      rows[i] = FirstRunBranchRow(code: rows[i].code, name: v);
                      setRows(rows);
                    },
                  ),
                ),
                IconButton(
                  key: Key('first_run_hq_branch_delete_$i'),
                  tooltip: tr('حذف'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    final gone = d.branches[i].code.trim().toUpperCase();
                    final rows = [...d.branches]..removeAt(i);
                    setRows(rows, users: [
                      for (final u in d.hqUsers)
                        u.scope.trim().toUpperCase() == gone
                            ? u.copyWith(scope: 'HQ')
                            : u,
                    ]);
                  },
                ),
              ],
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const Key('first_run_hq_branch_add'),
            onPressed: () => setRows([
              ...d.branches,
              FirstRunBranchRow(code: _nextBranchCode(d.branches), name: ''),
            ]),
            icon: const Icon(Icons.add, size: 18),
            label: Text(tr('إضافة فرع')),
          ),
        ),
        const SizedBox(height: 10),
        FirstRunCallout(
          title: tr('يمكن إضافة الفروع لاحقًا من الإعدادات.'),
          body: tr('رموز ربط أجهزة كل فرع تُصدر من السيرفر الرئيسي بعد الإعداد.'),
        ),
      ],
    );
  }
}

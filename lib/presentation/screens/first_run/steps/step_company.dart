// الخطوة ٢ (مستقل/مقرّ) — الشركة والنشاط: باقةُ النشاط (= ملفّ النشاط فقط، لا
// ترخيص) ثم بياناتُ المنشأة والفرع والمخزن. العملةُ والضريبةُ والسنة في
// `step_company_finance.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../domain/models/first_run/first_run_packs.dart';
import '../../../../domain/models/first_run/first_run_path.dart';
import '../../../picpos_shell/picpos_surface.dart';
import '../first_run_controller.dart';
import '../widgets/first_run_callout.dart';
import '../widgets/first_run_choice_card.dart';
import '../widgets/first_run_field.dart';
import 'step_company_finance.dart';
import 'step_company_hq_branches.dart';

String _packTitle(FirstRunPack p) => switch (p) {
      FirstRunPack.pos => tr('نقطة بيع فقط'),
      FirstRunPack.restaurant => tr('مطاعم فقط'),
      FirstRunPack.business => tr('نقطة بيع + محاسبة + مستودعات'),
      FirstRunPack.full => tr('النظام الكامل'),
    };

String _packSubtitle(FirstRunPack p) => switch (p) {
      FirstRunPack.pos => tr('البيع والصناديق والتقارير الأساسية.'),
      FirstRunPack.restaurant => tr('الطاولات والمطبخ والتوصيل مع نقطة البيع.'),
      FirstRunPack.business => tr('بيع ومحاسبة ومستودعات لمتجر متكامل.'),
      FirstRunPack.full => tr('كل الأقسام المتاحة في النظام.'),
    };

const _packIcons = {
  FirstRunPack.pos: Icons.point_of_sale_outlined,
  FirstRunPack.restaurant: Icons.restaurant_outlined,
  FirstRunPack.business: Icons.inventory_2_outlined,
  FirstRunPack.full: Icons.apps_outlined,
};

class StepCompany extends ConsumerWidget {
  const StepCompany({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(firstRunControllerProvider.select((s) => s.draft));
    final ctl = ref.read(firstRunControllerProvider.notifier);
    Widget gap() => const SizedBox(height: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, tr('باقة النشاط')),
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth >= 640 ? (c.maxWidth - 10) / 2 : c.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final p in FirstRunPack.values)
                  SizedBox(
                    width: w,
                    child: FirstRunChoiceCard(
                      key: Key('first_run_pack_${p.name}'),
                      icon: _packIcons[p]!,
                      title: _packTitle(p),
                      subtitle: _packSubtitle(p),
                      selected: d.pack == p,
                      onTap: () => ctl.update((x) => x.copyWith(pack: p)),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        FirstRunCallout(
          title: tr('الباقة تضبط الأقسام الظاهرة، ويمكن تعديلها لاحقًا من الإعدادات.'),
        ),
        const SizedBox(height: 20),
        _title(context, tr('بيانات المنشأة')),
        FirstRunField(
          key: const Key('first_run_company_name'),
          label: tr('اسم المنشأة / الشركة'),
          value: d.companyName,
          onChanged: (v) => ctl.update((x) => x.copyWith(companyName: v)),
        ),
        gap(),
        Row(children: [
          Expanded(
            child: FirstRunField(
              key: const Key('first_run_company_name_en'),
              label: tr('اسم الشركة بالإنجليزية (اختياري)'),
              value: d.companyNameEn,
              ltr: true,
              onChanged: (v) => ctl.update((x) => x.copyWith(companyNameEn: v)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FirstRunField(
              label: tr('الهاتف'),
              value: d.companyPhone,
              ltr: true,
              keyboardType: TextInputType.phone,
              onChanged: (v) => ctl.update((x) => x.copyWith(companyPhone: v)),
            ),
          ),
        ]),
        gap(),
        FirstRunField(
          label: tr('العنوان'),
          value: d.companyAddress,
          onChanged: (v) => ctl.update((x) => x.copyWith(companyAddress: v)),
        ),
        gap(),
        Row(children: [
          Expanded(
            child: FirstRunField(
              label: tr('الرقم الضريبي (اختياري)'),
              value: d.taxNumber,
              ltr: true,
              onChanged: (v) => ctl.update((x) => x.copyWith(taxNumber: v)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FirstRunField(
              label: tr('السجل التجاري (اختياري)'),
              value: d.commercialRegister,
              ltr: true,
              onChanged: (v) =>
                  ctl.update((x) => x.copyWith(commercialRegister: v)),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        _title(context, tr('الفرع الرئيسي والمخزن')),
        Row(children: [
          Expanded(
            flex: 3,
            child: FirstRunField(
              key: const Key('first_run_branch_name'),
              label: tr('اسم الفرع الرئيسي'),
              value: d.branchName,
              onChanged: (v) => ctl.update((x) => x.copyWith(branchName: v)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FirstRunField(
              key: const Key('first_run_branch_code'),
              label: tr('رمز الفرع (اختياري)'),
              value: d.branchCode,
              ltr: true,
              maxLength: 10,
              onChanged: (v) => ctl.update((x) => x.copyWith(branchCode: v)),
            ),
          ),
        ]),
        gap(),
        FirstRunField(
          key: const Key('first_run_warehouse_name'),
          label: tr('اسم المخزن الرئيسي'),
          value: d.warehouseName,
          onChanged: (v) => ctl.update((x) => x.copyWith(warehouseName: v)),
        ),
        const SizedBox(height: 20),
        const StepCompanyFinance(),
        if (d.path == FirstRunPath.hq) const HqBranchesSection(),
        const SizedBox(height: 12),
        Text(
          tr('يمكن تعديل هذا لاحقًا من الإعدادات › معلومات الشركة.'),
          style: TextStyle(fontSize: 12, color: context.picposMuted),
        ),
      ],
    );
  }
}

Widget _title(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
          color: context.picposText,
        ),
      ),
    );

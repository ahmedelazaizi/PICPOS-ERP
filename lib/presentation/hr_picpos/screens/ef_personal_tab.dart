// J4 — تبويبُ «البيانات الشخصية» في ملفّ الموظف.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../widgets/hr_form_kit.dart';
import 'employee_file_form.dart';

class EfPersonalTab extends StatelessWidget {
  const EfPersonalTab({super.key, required this.form});
  final EmployeeFileForm form;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: form,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          HrSection(
            title: tr('الهوية'),
            icon: PhosphorIconsBold.identificationCard,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PhotoBox(path: form.photoPath.text),
                const SizedBox(width: 16),
                Expanded(
                  child: HrFieldGrid(children: [
                    HrTextField(
                      fieldKey: const Key('ef_name'),
                      label: tr('الاسم بالعربية'),
                      controller: form.name,
                      required: true,
                    ),
                    HrTextField(
                      fieldKey: const Key('ef_name_en'),
                      label: tr('الاسم بالإنجليزية'),
                      controller: form.nameEn,
                      textDirection: TextDirection.ltr,
                    ),
                    HrTextField(
                      fieldKey: const Key('ef_national_id'),
                      label: tr('الرقم القومي / الهوية'),
                      controller: form.nationalId,
                      textDirection: TextDirection.ltr,
                    ),
                    HrDateField(
                      label: tr('تاريخ الميلاد'),
                      value: form.birthDate,
                      onChanged: (v) => form.set(() => form.birthDate = v),
                    ),
                    HrDropdown<String>(
                      label: tr('النوع'),
                      value: form.gender,
                      emptyLabel: tr('غير محدد'),
                      items: {
                        EmployeeGender.male: tr('ذكر'),
                        EmployeeGender.female: tr('أنثى'),
                      },
                      onChanged: (v) => form.set(() => form.gender = v),
                    ),
                    HrTextField(
                      label: tr('الجنسية'),
                      controller: form.nationality,
                    ),
                  ]),
                ),
              ],
            ),
          ),
          HrSection(
            title: tr('التواصل'),
            icon: PhosphorIconsBold.phone,
            child: HrFieldGrid(wide: const {4}, children: [
              HrTextField(
                fieldKey: const Key('ef_phone'),
                label: tr('الهاتف'),
                controller: form.phone,
                textDirection: TextDirection.ltr,
              ),
              HrTextField(
                label: tr('هاتف آخر'),
                controller: form.phone2,
                textDirection: TextDirection.ltr,
              ),
              HrTextField(
                label: tr('البريد الإلكتروني'),
                controller: form.email,
                textDirection: TextDirection.ltr,
              ),
              HrTextField(
                label: tr('مسار الصورة'),
                controller: form.photoPath,
                hint: tr('مسار ملف صورة على الجهاز'),
                textDirection: TextDirection.ltr,
                onChanged: (_) => form.set(() {}),
              ),
              HrTextField(
                label: tr('العنوان'),
                controller: form.address,
                maxLines: 2,
              ),
            ]),
          ),
          HrSection(
            title: tr('جهة اتصال للطوارئ'),
            icon: PhosphorIconsBold.firstAid,
            child: HrFieldGrid(children: [
              HrTextField(
                label: tr('الاسم وصلة القرابة'),
                controller: form.emergencyName,
              ),
              HrTextField(
                label: tr('هاتف الطوارئ'),
                controller: form.emergencyPhone,
                textDirection: TextDirection.ltr,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// صورةُ الموظف من مسارٍ على الجهاز — أو أيقونةٌ حين لا صورة.
class _PhotoBox extends StatelessWidget {
  const _PhotoBox({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final file = path.trim().isEmpty ? null : File(path.trim());
    final exists = file != null && file.existsSync();
    return Container(
      width: 96,
      height: 112,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: exists
          ? Image.file(file, fit: BoxFit.cover)
          : Icon(PhosphorIconsBold.userCircle,
              size: 44, color: context.picposMuted),
    );
  }
}

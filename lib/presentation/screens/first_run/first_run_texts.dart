// نصوصُ الإعداد الأول المترجَمة: رسائلُ التحقّق وعناوينُ الخطوات.
//
// ⚠️ `switch` تعبيريّ (‏لا `case` تقليديّ) كي لا يحسب حارسُ
// `i18n_runtime_safety_test` النداءَ `tr()` بياناتٍ غيرَ واجهة. والنصوصُ حرفيّةٌ
// ليلتقطها مستخرجُ الفهرس.
library;

import '../../../core/i18n/tr.dart';
import '../../../domain/models/first_run/first_run_path.dart';
import '../../../domain/models/first_run/first_run_steps.dart';
import '../../../domain/models/first_run/first_run_validation.dart';

String firstRunIssueText(FirstRunIssue issue) => switch (issue) {
      FirstRunIssue.companyNameRequired => tr('أدخل اسم الشركة.'),
      FirstRunIssue.currencyRequired =>
        tr('اختر العملة الأساسية — لا يمكن تغييرها بعد أول فاتورة.'),
      FirstRunIssue.currencyUnsupported => tr('هذه العملة غير مدعومة.'),
      FirstRunIssue.fiscalYearInvalid => tr('أدخل سنة مالية صحيحة.'),
      FirstRunIssue.branchNameRequired => tr('أدخل اسم الفرع الرئيسي.'),
      FirstRunIssue.warehouseRequired => tr('أدخل اسم المخزن الرئيسي.'),
      FirstRunIssue.branchCodeTooLong =>
        tr('رمز الفرع يجب ألا يتجاوز 10 أحرف.'),
      FirstRunIssue.branchRowsIncomplete => tr('أكمل رمز واسم كل فرع.'),
      FirstRunIssue.branchCodesDuplicate => tr('رموز الفروع يجب أن تكون مختلفة.'),
      FirstRunIssue.adminPasswordShort =>
        tr('كلمة مرور المسؤول يجب أن تكون 8 أحرف على الأقل.'),
      FirstRunIssue.adminPasswordMismatch => tr('كلمتا المرور غير متطابقتين.'),
      FirstRunIssue.developerPasswordShort =>
        tr('كلمة مرور المطوّر يجب أن تكون 4 أحرف على الأقل.'),
      FirstRunIssue.developerPasswordMismatch =>
        tr('كلمتا مرور المطوّر غير متطابقتين.'),
      FirstRunIssue.userRowsIncomplete =>
        tr('أكمل بيانات المستخدمين أو احذف السطر غير المطلوب.'),
      FirstRunIssue.usernamesDuplicate =>
        tr('اسم الدخول يجب أن يكون فريدًا لكل مستخدم.'),
      FirstRunIssue.userScopeInvalid => tr('راجع الفرع المخصص لكل مستخدم.'),
      FirstRunIssue.tablesCountInvalid =>
        tr('أدخل عدد طاولات صحيحًا بين 0 و1000.'),
      FirstRunIssue.endpointRequired => tr('أدخل عنوان الاتصال بالسيرفر الرئيسي.'),
      FirstRunIssue.portInvalid => tr('أدخل منفذًا صحيحًا بين 1 و65535.'),
      FirstRunIssue.deviceNameRequired => tr('أدخل اسم هذا الجهاز.'),
      FirstRunIssue.linkNotVerified => tr('تحقق من الربط بالرئيسي أولًا.'),
      FirstRunIssue.storageNotChecked =>
        tr('تعذّر التحقق من مجلد البيانات. أعد الفحص.'),
      FirstRunIssue.serverNotProvisioned => tr('جهّز قاعدة بيانات الخادم أولًا.'),
      FirstRunIssue.firstSyncPending =>
        tr('أكمل المزامنة الأولى قبل بدء التشغيل.'),
      FirstRunIssue.accountNotVerified =>
        tr('تحقق من حساب الفرع المعتمد أولًا.'),
    };

String firstRunStepTitle(FirstRunStep step) => switch (step) {
      FirstRunStep.mode => tr('طريقة التشغيل'),
      FirstRunStep.company => tr('الشركة والنشاط'),
      FirstRunStep.link => tr('الربط بالرئيسي'),
      FirstRunStep.storage => tr('حفظ البيانات'),
      FirstRunStep.users => tr('المسؤول والأمان'),
      FirstRunStep.firstSync => tr('المزامنة الأولى'),
      FirstRunStep.prep => tr('تجهيز النشاط'),
      FirstRunStep.account => tr('حساب الفرع'),
      FirstRunStep.review => tr('مراجعة وبدء التشغيل'),
      FirstRunStep.success => tr('النسخة جاهزة للبدء'),
    };

String firstRunStepSubtitle(FirstRunStep step) => switch (step) {
      FirstRunStep.mode =>
        tr('اختر دور هذا الجهاز. الباقة والعملة تُحدَّدان في الخطوة التالية.'),
      FirstRunStep.company =>
        tr('عرّف المنشأة واختر باقة النشاط والعملة والضريبة.'),
      FirstRunStep.link => tr('اربط هذا الفرع بالسيرفر الرئيسي.'),
      FirstRunStep.storage => tr('أين تُحفظ بيانات هذه النسخة؟'),
      FirstRunStep.users => tr('أنشئ حساب المسؤول الأول وكلمة مرور المطوّر.'),
      FirstRunStep.firstSync => tr('المزامنة الأولى إلزامية قبل التشغيل.'),
      FirstRunStep.prep => tr('جهّز الصندوق والخدمة وتفضيلات هذا الجهاز.'),
      FirstRunStep.account => tr('تحقق من الحساب المعتمد لهذا الفرع.'),
      FirstRunStep.review => tr('راجع الإعداد قبل البدء.'),
      FirstRunStep.success => tr('تم حفظ الإعداد بنجاح.'),
    };

String firstRunPathTitle(FirstRunPath p) => switch (p) {
      FirstRunPath.standalone => tr('نسخة مستقلة على جهاز واحد'),
      FirstRunPath.hq => tr('سيرفر رئيسي لشركة وفروع'),
      FirstRunPath.branch => tr('فرع تابع للسيرفر الرئيسي'),
    };

String firstRunPathSubtitle(FirstRunPath p) => switch (p) {
      FirstRunPath.standalone =>
        tr('كل العمل وحفظ البيانات على هذا الجهاز فقط، بدون مزامنة مع جهاز آخر.'),
      FirstRunPath.hq =>
        tr('إدارة الشركة والفروع والمستخدمين واستقبال المزامنة من الفروع.'),
      FirstRunPath.branch =>
        tr('يحفظ بياناته محليًا، ويعمل أونلاين وأوفلاين، ثم يزامن مع الرئيسي.'),
    };

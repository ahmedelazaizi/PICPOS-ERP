import 'package:flutter/widgets.dart';
import 'package:picpos_ui/picpos_ui.dart';

/// Arabic (default) + English strings of PicPos إدارة.
abstract final class S {
  static const table = L10nTable({
    'appTitle': ('PicPos إدارة', 'PicPos Admin'),
    'navDashboard': ('الرئيسية', 'Dashboard'),
    'navApprovals': ('الموافقات', 'Approvals'),
    'navReports': ('التقارير', 'Reports'),
    'navOperations': ('العمليات', 'Operations'),
    'navNotifications': ('الإشعارات', 'Notifications'),
    'navSettings': ('الإعدادات', 'Settings'),
    'dashboardSub': ('مؤشرات اليوم والشهر', "Today's and this month's KPIs"),
    'approvalsSub': (
      'المرتجعات والإجازات والرواتب والتجاوزات',
      'Returns, leave, payroll and overrides',
    ),
    'reportsSub': (
      'القوائم المالية وكشوف الحسابات',
      'Financial statements and ledgers',
    ),
    'operationsSub': (
      'سندات القبض والصرف والقيود والشيكات',
      'Receipts, payments, journals and cheques',
    ),
    'notificationsSub': (
      'تنبيهات فورية من جهاز المكتب',
      'Instant alerts from the desktop',
    ),
    'settingsSub': ('اللغة والمظهر والربط', 'Language, theme and pairing'),
    'kpiNetSales': ('صافي المبيعات', 'Net sales'),
    'kpiInvoices': ('عدد الفواتير', 'Invoices'),
    'kpiGrossProfit': ('مجمل الربح', 'Gross profit'),
    'kpiReturns': ('المرتجعات', 'Returns'),
    'kpiAfterPairing': ('يظهر بعد الربط', 'Shown after pairing'),
    'cashBanks': ('النقدية والبنوك', 'Cash & banks'),
    'cashBanksSub': (
      'أرصدة الحسابات في دفتر الأستاذ',
      'General-ledger balances',
    ),
    'notPaired': ('الجهاز غير مربوط بعد', 'This device is not paired yet'),
    'notPairedMsg': (
      'اربط الجوال بجهاز المكتب لعرض البيانات.',
      'Pair this phone with the desktop to see data.',
    ),
    'noVerifiedData': (
      'لا توجد بيانات موثّقة بعد — يتم تحديثها من جهاز المكتب عند المزامنة',
      'No verified data yet — the office computer updates it on sync',
    ),
    'comingTitle': ('قيد الإنشاء', 'Coming soon'),
    'approvalsComing': (
      'صندوق الموافقات يصل في المرحلة M-1 (عرض) و M-3 (تنفيذ).',
      'The approvals inbox arrives in M-1 (view) and M-3 (actions).',
    ),
    'reportsComing': (
      'التقارير المالية وتصديرها PDF/Excel تصل في المرحلة M-2.',
      'Financial reports with PDF/Excel export arrive in M-2.',
    ),
    'operationsComing': (
      'السندات والقيود وحالات الشيكات تصل في المرحلة M-3.',
      'Vouchers, journals and cheque actions arrive in M-3.',
    ),
    'notificationsComing': (
      'الإشعارات الفورية تصل في المرحلة M-4.',
      'Instant notifications arrive in M-4.',
    ),
    'pairing': ('الربط', 'Pairing'),
    'openPairing': ('فتح شاشة الربط', 'Open pairing screen'),
    'accountDevice': ('الحساب والجهاز', 'Account & device'),
    'boundUser': ('المستخدم', 'User'),
    'boundToUser': (
      'هذا الجوال مربوط بالمستخدم {user}',
      'This phone is paired to {user}',
    ),
    'unknownUser': ('مستخدم غير معروف', 'Unknown user'),
    'pairedStatus': ('الجهاز مربوط', 'Device paired'),
    'logout': ('تسجيل الخروج', 'Sign out'),
    'logoutWarning': (
      'سيتم تسجيل خروجك مع بقاء الجهاز مربوطاً بهذا المستخدم.',
      'You will be signed out; this phone will remain paired to this user.',
    ),
    'switchUserUnpair': (
      'تبديل المستخدم / فك ربط الجهاز',
      'Switch user / unpair device',
    ),
    'unpairDevice': ('فك ربط الجهاز', 'Unpair device'),
    'unpairWarning': (
      'سيُحذف الربط من هذا الجوال. للدخول بمستخدم آخر، ستحتاج رمز ربط جديداً من جهاز المكتب: ربط التطبيقات والأجهزة ← تطبيق الإدارة ← ربط جوال.',
      'Pairing will be removed from this phone. To use another account, get a new pairing code on the office computer: Link apps & devices → Admin app → Pair phone.',
    ),
    'revokeOnDesktop': (
      'تعذّر إلغاء الربط على الخادم. ألغِ الجهاز من جهاز المكتب عند عودة الاتصال.',
      'Could not revoke on the server. Revoke this device from the office computer when connected.',
    ),
    'cancel': ('إلغاء', 'Cancel'),
    'keyFingerprintTitle': ('تأكيد مفتاح التوقيع', 'Confirm the signing key'),
    'keyFingerprintBody': (
      'قارن هذه البصمة بالبصمة المعروضة في برنامج المكتب (ربط التطبيقات والأجهزة). إن اختلفت فلا تتابع.',
      'Compare this fingerprint with the one shown in the office program (Link apps & devices). If they differ, do not continue.',
    ),
    'keyFingerprintMatches': ('البصمة مطابقة', 'It matches'),
    'signing_key_not_confirmed': (
      'لم يُؤكَّد مفتاح التوقيع — أُلغي الربط',
      'Signing key not confirmed — pairing cancelled',
    ),
    'about': ('حول التطبيق', 'About'),
    'version': ('الإصدار {v}', 'Version {v}'),
    'pairTitle': ('ربط هذا الجوال', 'Pair this phone'),
    'pairSub': (
      'بالسحابة وبشبكة المحل معاً',
      'With the cloud and the shop network',
    ),
    'pairStep1': (
      'على جهاز المكتب: المستخدمون ← «ربط جوال» للمستخدم.',
      'On the desktop: Users → “Pair phone” for the user.',
    ),
    'pairStep2': (
      'امسح رمز QR الظاهر على الشاشة.',
      'Scan the QR code shown on the screen.',
    ),
    'pairStep3': (
      'سجّل الدخول بكلمة مرور الجوال ثم اضبط رمز القفل.',
      'Sign in with your mobile password, then set an app PIN.',
    ),
    'scanQr': ('مسح رمز QR', 'Scan QR code'),
    'manualEntry': ('أو أدخل الرمز يدوياً', 'Or enter the code manually'),
    'serverUrl': ('عنوان الخادم', 'Server address'),
    'pairingCode': ('رمز الربط', 'Pairing code'),
    'pair': ('ربط', 'Pair'),
    'previewOnly': (
      'معاينة — الربط يُفعَّل في المرحلة M-1',
      'Preview — pairing is enabled in M-1',
    ),
    'previewApp': ('معاينة التطبيق', 'Preview the app'),
    'pasteOffer': (
      'الصق بيانات الربط JSON (اختياري)',
      'Paste pairing JSON (optional)',
    ),
    'signIn': ('تسجيل الدخول', 'Sign in'),
    'username': ('اسم المستخدم', 'Username'),
    'mobilePassword': ('كلمة مرور الجوال', 'Mobile password'),
    'totpOptional': ('رمز التحقق (اختياري)', 'Authenticator code (optional)'),
    'appPinSetupTitle': ('إعداد رمز قفل التطبيق', 'Set an app lock PIN'),
    'appPinSetupBody': (
      'أنشئ رمزاً محلياً من 4 إلى 6 أرقام لحماية التطبيق. لا يُحفظ إلا مُتحقّق الرمز في التخزين الآمن',
      'Create a local 4–6 digit PIN to protect the app. Only its verifier is stored in secure storage.',
    ),
    'appPinLockedTitle': ('التطبيق مقفل', 'App locked'),
    'appPinLockedBody': (
      'أدخل رمز قفل التطبيق للمتابعة.',
      'Enter your app lock PIN to continue.',
    ),
    'appPin': ('رمز قفل التطبيق', 'App PIN'),
    'confirmAppPin': ('تأكيد رمز القفل', 'Confirm PIN'),
    'saveAppPin': ('حفظ رمز القفل', 'Save PIN'),
    'unlockApp': ('فتح التطبيق', 'Unlock app'),
    'app_pin_mismatch': ('رمزا القفل غير متطابقين', 'PINs do not match'),
    'incorrect_app_pin': ('رمز قفل التطبيق غير صحيح', 'Incorrect app PIN'),
    'invalid_app_pin': (
      'رمز القفل يجب أن يكون من 4 إلى 6 أرقام',
      'PIN must contain 4–6 digits',
    ),
    'invalid_totp': (
      'رمز التحقق يجب أن يكون 6 أرقام',
      'Authenticator code must contain 6 digits',
    ),
    'requestFailed': ('تعذّر إكمال الطلب', 'Request failed'),
    'invalid_credentials': (
      'اسم المستخدم أو كلمة مرور الجوال غير صحيحة',
      'Wrong username or mobile password',
    ),
    'user_locked': (
      'الحساب مقفل مؤقتاً بعد محاولات خاطئة — انتظر ثم أعد المحاولة',
      'Account temporarily locked after failed attempts — wait and try again',
    ),
    'mobile_access_denied': (
      'هذا المستخدم غير مفعّل لتطبيق الإدارة',
      'This user is not enabled for the admin app',
    ),
    'invalid_code': ('رمز الربط غير صحيح', 'Invalid pairing code'),
    'code_expired': ('انتهت صلاحية رمز الربط', 'Pairing code expired'),
    'too_many_attempts': (
      'محاولات كثيرة — انتظر ثم أعد المحاولة',
      'Too many attempts — wait and try again',
    ),
    'retrySeconds': (
      'انتظر {seconds} ثانية ثم أعد المحاولة',
      'Wait {seconds} seconds and try again',
    ),
    'refresh': ('تحديث', 'Refresh'),
    'asOf': ('آخر تحديث', 'As of'),
    'staleSnapshot': ('بيانات قديمة', 'Stale data'),
    'unverifiedSnapshots': (
      'تعذّر التحقق من بعض البيانات',
      'Some data could not be verified',
    ),
    'viewOnly': ('للعرض فقط', 'View only'),
    'noPendingApprovals': ('لا توجد موافقات معلّقة', 'No pending approvals'),
  });

  static Tr of(BuildContext context) => Tr.of(context, table);

  static String errorText(
    BuildContext context,
    String code, {
    Duration? retryAfter,
  }) {
    final t = of(context);
    final message = switch (code) {
      'invalid_credentials' ||
      'user_locked' ||
      'mobile_access_denied' ||
      'invalid_code' ||
      'code_expired' ||
      'too_many_attempts' ||
      'signing_key_not_confirmed' ||
      'invalid_totp' ||
      'app_pin_mismatch' ||
      'incorrect_app_pin' ||
      'invalid_app_pin' => t(code),
      _ => code,
    };
    if (retryAfter == null ||
        (code != 'user_locked' && code != 'too_many_attempts')) {
      return message;
    }
    return '$message — ${t('retrySeconds', {'seconds': retryAfter.inSeconds})}';
  }
}

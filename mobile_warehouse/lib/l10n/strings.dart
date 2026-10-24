import 'package:flutter/widgets.dart';
import 'package:picpos_ui/picpos_ui.dart';

/// Arabic (default) + English strings of PicPos مخازن.
abstract final class S {
  static const table = L10nTable({
    'appTitle': ('PicPos مخازن', 'PicPos Warehouse'),
    'navHome': ('الرئيسية', 'Home'),
    'navLookup': ('بحث صنف', 'Item lookup'),
    'navDocuments': ('المستندات', 'Documents'),
    'navOutbox': ('قائمة الإرسال', 'Outbox'),
    'navSettings': ('الإعدادات', 'Settings'),
    'homeSub': ('مهامك وصلاحياتك على هذا الهاتف', 'Your tasks and permissions on this phone'),
    'lookupSub': ('امسح باركود أو ابحث بالاسم', 'Scan a barcode or search by name'),
    'documentsSub': ('الاستلام والتحويل والجرد والسندات', 'Receiving, transfers, counts and vouchers'),
    'outboxSub': ('العمليات المحفوظة بانتظار الإرسال', 'Operations saved and waiting to be sent'),
    'settingsSub': ('اللغة والمظهر والربط', 'Language, theme and pairing'),
    'notAvailable': ('غير متاح بعد', 'Not available yet'),
    'documentsNone': (
      'استلام أوامر الشراء والتحويلات والجرد والسندات لم تُنفَّذ بعد في هذا الإصدار.',
      'Purchase receiving, transfers, counts and vouchers are not implemented in this version yet.'
    ),
    'outboxEmpty': ('لا توجد عمليات بانتظار الإرسال.', 'Nothing is waiting to be sent.'),
    'outboxNote': (
      'الإرسال إلى المكتب لم يُفعَّل بعد؛ ستظهر هنا العمليات حين تتوفر المستندات.',
      'Sending to the office is not enabled yet; operations will appear here once documents exist.'
    ),
    'roleClerk': ('موظف مخزن / مسؤول مخزن', 'Warehouse clerk / keeper'),
    'roleSupervisor': ('مشرف / مدير مخزون', 'Supervisor / stock manager'),
    'hello': ('مرحباً {name}', 'Hello {name}'),
    'branch': ('الفرع: {name}', 'Branch: {name}'),
    'warehouses': ('المخازن المتاحة لك', 'Your warehouses'),
    'noWarehouses': (
      'لا توجد مخازن متاحة لحسابك في فرع هذا الهاتف. اطلب من المدير منحك الوصول.',
      'No warehouse is available to your account in this phone\'s branch. Ask the manager for access.'
    ),
    'capabilities': ('ما يتاح لك', 'What you can do'),
    'capLookup': ('بحث صنف ورصيده', 'Look up an item and its stock'),
    'capReceive': ('استلام أمر شراء', 'Receive a purchase order'),
    'capCount': ('جرد', 'Stock count'),
    'capTransfer': ('تحويل بين المخازن', 'Transfer between warehouses'),
    'capApprove': ('اعتماد الجرد والفروقات', 'Approve counts and variances'),
    'refresh': ('تحديث', 'Refresh'),
    'sessionUnknown': ('تعذّر التحقق من حسابك الآن.', 'Your account could not be verified right now.'),
    'scanOrType': ('امسح الباركود أو اكتبه', 'Scan or type the barcode'),
    'search': ('بحث', 'Search'),
    'scanCamera': ('مسح بالكاميرا', 'Scan with camera'),
    'lookupHint': ('ابدأ بمسح صنف.', 'Start by scanning an item.'),
    'lookupNone': ('لا يوجد صنف بهذا الباركود أو الاسم.', 'No item matches this barcode or name.'),
    'stockIn': ('الرصيد في {wh}', 'Stock in {wh}'),
    'reserved': ('محجوز {q}', 'Reserved {q}'),
    'noStockInScope': ('لا رصيد مسجّل في مخازنك.', 'No stock recorded in your warehouses.'),
    'pairTitle': ('ربط هذا الهاتف', 'Pair this phone'),
    'pairSub': ('بجهاز المكتب الرئيسي عبر شبكة المحل', 'With the main desktop over the shop network'),
    'pairStep1': (
      'اطلب من المدير المسؤول عن ربط الأجهزة: الإعدادات › ربط التطبيقات › PicPos مخازن › إقران هاتف.',
      'Ask the manager who pairs devices: Settings › Linked apps › PicPos Warehouse › Pair a phone.'
    ),
    'pairStep2': ('امسح رمز QR الظاهر على شاشة المكتب.', 'Scan the QR code shown on the office screen.'),
    'pairStep3': ('ثم سجّل الدخول بحسابك.', 'Then sign in with your own account.'),
    'scanQr': ('مسح رمز QR', 'Scan QR code'),
    'manualEntry': ('أو أدخل البيانات يدوياً', 'Or enter the details manually'),
    'serverAddress': ('عنوان المكتب (مثال 192.168.1.10:8080)', 'Office address (e.g. 192.168.1.10:8080)'),
    'pairingCode': ('رمز الإقران', 'Pairing code'),
    'fingerprint': ('بصمة الشهادة (SHA-256)', 'Certificate fingerprint (SHA-256)'),
    'pair': ('ربط', 'Pair'),
    'cancel': ('إلغاء', 'Cancel'),
    'pairingBusy': ('جارٍ الربط…', 'Pairing…'),
    'pasteHint': (
      'يمكنك لصق نص رمز QR كاملاً في خانة العنوان.',
      'You can paste the whole QR text into the address field.'
    ),
    'loginTitle': ('تسجيل الدخول', 'Sign in'),
    'loginSub': ('بحسابك في PicPos', 'With your PicPos account'),
    'username': ('اسم المستخدم', 'Username'),
    'password': ('كلمة المرور', 'Password'),
    'signIn': ('دخول', 'Sign in'),
    'signingIn': ('جارٍ الدخول…', 'Signing in…'),
    'pairedTo': ('مرتبط بالفرع {name}', 'Paired to branch {name}'),
    'unpair': ('فك الربط ومسح البيانات', 'Unpair and wipe data'),
    'unpairBody': (
      'سيُمسح كل ما على هذا الهاتف ويلزم إقرانه من جديد. العمليات غير المرسلة ستضيع.',
      'Everything on this phone is wiped and it must be paired again. Unsent operations are lost.'
    ),
    'confirm': ('تأكيد', 'Confirm'),
    'signOut': ('تسجيل الخروج', 'Sign out'),
    'account': ('الحساب', 'Account'),
    'pairing': ('الربط', 'Pairing'),
    'about': ('حول التطبيق', 'About'),
    'version': ('الإصدار {v}', 'Version {v}'),
    'appPinSetupTitle': ('أنشئ رمز قفل التطبيق', 'Create an app lock PIN'),
    'appPinSetupBody': (
      'رمز من 4 إلى 6 أرقام يحمي هذا الهاتف عند تركه أو فقده.',
      'A 4-6 digit PIN protects this phone when it is left or lost.'
    ),
    'appPin': ('رمز القفل', 'App PIN'),
    'confirmAppPin': ('أعد كتابة الرمز', 'Repeat the PIN'),
    'saveAppPin': ('حفظ الرمز', 'Save PIN'),
    'appPinLockedTitle': ('التطبيق مقفل', 'App locked'),
    'appPinLockedBody': ('أدخل رمز القفل للمتابعة.', 'Enter the PIN to continue.'),
    'unlockApp': ('فتح', 'Unlock'),
    'err_invalid_app_pin': ('الرمز يجب أن يكون 4 إلى 6 أرقام.', 'The PIN must be 4-6 digits.'),
    'err_app_pin_mismatch': ('الرمزان غير متطابقين.', 'The PINs do not match.'),
    'err_incorrect_app_pin': ('الرمز غير صحيح.', 'Incorrect PIN.'),
    'err_not_json': ('النص ليس رمز إقران صالحاً.', 'The text is not a valid pairing code.'),
    'err_not_object': ('النص ليس رمز إقران صالحاً.', 'The text is not a valid pairing code.'),
    'err_incomplete': ('بيانات الإقران ناقصة.', 'The pairing details are incomplete.'),
    'err_bad_kind': ('هذا الرمز لجهاز من نوع آخر.', 'This code is for another kind of device.'),
    'err_wrong_kind': ('هذا الرمز ليس لتطبيق المخازن.', 'This code is not for the Warehouse app.'),
    'err_no_fingerprint': (
      'الخادم لا يستعمل اتصالاً مشفّراً (TLS) فرُفض الربط.',
      'The server does not use TLS, so pairing was refused.'
    ),
    'err_not_https': ('الرمز لا يحمل عنواناً مشفّراً (https).', 'The code has no https address.'),
    'err_no_tls': ('الخادم لا يستعمل اتصالاً مشفّراً.', 'The server is not using an encrypted connection.'),
    'err_expired': ('انتهت صلاحية الرمز؛ اطلب رمزاً جديداً.', 'The code has expired; ask for a new one.'),
    'err_network': (
      'تعذّر الاتصال بالمكتب أو لم تتطابق بصمة الشهادة.',
      'Could not reach the office, or the certificate fingerprint does not match.'
    ),
    'err_unauthorized': ('اسم المستخدم أو كلمة المرور غير صحيحة، أو انتهت الجلسة.', 'Wrong username or password, or the session ended.'),
    'err_permission_denied': ('حسابك لا يملك صلاحية تطبيق المخازن.', 'Your account does not have Warehouse app access.'),
    'err_device_scope': ('هذا الهاتف غير مقترن كجهاز مخازن.', 'This phone is not paired as a warehouse device.'),
    'err_device_revoked': ('أُلغي ربط هذا الهاتف؛ أُعيد إلى شاشة الربط.', 'This phone was unpaired; returning to pairing.'),
    'err_rate_limited': ('محاولات كثيرة؛ انتظر قليلاً.', 'Too many attempts; wait a moment.'),
    'err_unavailable': ('المكتب غير متاح الآن.', 'The office is not available right now.'),
    'err_rejected': ('الطلب مرفوض.', 'The request was rejected.'),
    'err_unknown': ('حدث خطأ غير متوقع.', 'Something went wrong.'),
  });

  static Tr of(BuildContext context) => Tr.of(context, table);

  /// A user-facing message for an error [code] (see `errorCode` in wh_session).
  static String errorText(BuildContext context, String code) {
    final t = of(context);
    final key = 'err_$code';
    return t(table.entries.containsKey(key) ? key : 'err_unknown');
  }
}

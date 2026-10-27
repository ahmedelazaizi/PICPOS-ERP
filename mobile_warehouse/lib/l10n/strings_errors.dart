/// Messages for the refusals the office host can answer on /api/m1/wh/* that
/// are not part of the older document set (kept apart: strings.dart has a 30 KB
/// ceiling). Keys are `err_<code>`; see `kDomainCodes` in wh_session.dart.
const Map<String, (String, String)> kHostErrorStrings = {
    // WH-014: overlapping count tasks (refused at approval).
    'err_overlapping_count_task': (
      'لا يمكن اعتماد هذا الجرد الآن: يوجد جرد أقدم لنفس المخزن ونفس الصنف ما زال قيد التنفيذ. اعتمد الجرد الأقدم أولاً (أو أغلقه) ثم أعد المحاولة.',
      'This count cannot be approved yet: an older count of the same warehouse and item is still in progress. Approve (or close) the older count first, then try again.'
    ),
    'err_stale_overlap_count': (
      'تغيّر رصيد صنف في هذا الجرد منذ عدّه: اعتُمد جرد آخر لنفس المخزن والصنف بعد إرسال هذا العدّ. يلزم إعادة العدّ؛ اطلب من المسؤول إرجاع الجرد للعدّ من جديد.',
      'An item in this count changed since it was counted: another count of the same warehouse and item was approved after this one was submitted. A recount is needed; ask for the count to be sent back for another pass.'
    ),
    'err_idempotency_key_required': ('الطلب بلا معرّف تكرار صالح؛ حدّث التطبيق وأعد المحاولة.', 'The request has no valid retry id; update the app and try again.'),
    'err_bad_request': ('بيانات الطلب غير مكتملة أو غير صالحة.', 'The request data is incomplete or invalid.'),
    'err_internal': ('تعذّر على المكتب تنفيذ الطلب؛ ستُعاد المحاولة.', 'The office could not process the request; it will be retried.'),
    'err_not_ready': ('خدمة الاعتماد غير جاهزة في المكتب؛ حاول بعد قليل.', 'Approvals are not ready at the office; try again shortly.'),
    'err_locked_out': ('الحساب مقفل مؤقتاً بسبب محاولات خاطئة كثيرة؛ انتظر ثم أعد المحاولة.', 'The account is temporarily locked after too many wrong attempts; wait and try again.'),
    'err_password_change_required': ('يجب تغيير كلمة المرور من المكتب قبل المتابعة.', 'The password must be changed at the office before you continue.'),
    'err_query_too_short': ('اكتب حرفين على الأقل للبحث.', 'Type at least 2 characters to search.'),
    'err_host_unreachable': ('تعذّر على المكتب الوصول إلى خادمه الرئيسي.', 'The office could not reach its main server.'),
    'err_mirror_console_denied': ('هذا الإجراء غير متاح من نسخة المرآة.', 'This action is not available from a mirror console.'),
    'err_warehouse_scope': ('هذا المخزن خارج نطاق صلاحياتك.', 'This warehouse is outside your scope.'),
    'err_branch_access_denied': ('هذا الفرع خارج نطاق صلاحياتك.', 'This branch is outside your access.'),
};

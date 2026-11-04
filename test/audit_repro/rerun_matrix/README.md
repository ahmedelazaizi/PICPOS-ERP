# مصفوفة إعادة تشغيل اختبارات الاستنساخ السابقة — 2026-11-01

كل تشغيل أدناه استعمل `--run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos`. اعتُبر النجاح/الفشل بعدد الاختبارات التي انتهت بنجاح/إخفاق، لا باعتبار «اختبار عيب متوقع» نجاحاً.

| الملف/المجموعة | النتيجة الحالية | المعلن في التقرير السابق | المقارنة |
|---|---:|---:|---|
| `test/audit_repro/shift_close/shift_close_audit_matrix_test.dart` | 13 نجاح / 7 إخفاق | 13 / 7 | مطابق؛ F04 وF07 من الإخفاقات، وخرجت الأرقام الفعلية كما بالتقرير. |
| `test/audit_repro/financial_statements` (يشمل `fs_04_pg_parity_pg_test.dart`) | 19 / 15 | 19 / 15 | مطابق؛ اختبار PG1 اكتمل على الحاوية الخاصة. |
| `test/audit_repro/sales_purchases/a_negative_stock_policy_audit_test.dart` (a) | 5 / 4 | 5 / 4 | مطابق. |
| `test/audit_repro/sales_purchases/b_sales_posting_matrix_audit_test.dart` (b) | 20 / 11 | 20 / 11 | مطابق. |
| `test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart` (c) | 11 / 13 | 11 / 13 | مطابق. |
| `test/audit_repro/sales_purchases/d_purchases_cost_audit_test.dart` (d) | 7 / 6 | 7 / 6 | مطابق. |
| `test/audit_repro/sales_purchases/e_pg_parity_audit_test.dart` (e) | 3 / 4 | 3 / 4 | مطابق؛ تشغيل PostgreSQL فعلي على منفذ التدقيق. |

## أوامر التشغيل

```powershell
flutter test test/audit_repro/shift_close --run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos -r expanded
$env:PG_TEST_DSN='postgres://postgres:auditpw@127.0.0.1:56010/postgres'
flutter test test/audit_repro/financial_statements --run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos -r expanded
flutter test test/audit_repro/sales_purchases/a_negative_stock_policy_audit_test.dart --run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos -r expanded
flutter test test/audit_repro/sales_purchases/b_sales_posting_matrix_audit_test.dart --run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos -r expanded
flutter test test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart --run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos -r expanded
flutter test test/audit_repro/sales_purchases/d_purchases_cost_audit_test.dart --run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos -r expanded
flutter test test/audit_repro/sales_purchases/e_pg_parity_audit_test.dart --run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos -r expanded
```

استخدم التشغيل الفعلي أعلاه جميع هذه الأوامر؛ الخمسة الأخيرة شُغّلت منفردة بالتتابع داخل PowerShell مع `PG_TEST_DSN` متاحاً. ظهرت رسائل `Binding has not yet been initialized` في اختبارات SQLite، لكنها لم توقفها. لم يظهر `PathExistsException`، لذلك لم تُحذف أي DLL ولم تُعَد محاولة غير لازمة. لم تُشغّل واجهة رسومية ولم تُقتل عمليات.

## دليل رقمي ملحوظ

- ورديات F04: المتوقع على الشاشة `0`، المتوقع المخزَّن `-100`، الفرق المخزَّن `+100`، حركة الدرج بعد الإفراغ `0`.
- ورديات F07: بيع `100` + قبض `100` ضمن الثانية نفسها يعطي المتوقع `200` رغم حركة الدرج `100`.
- القوائم المالية Y1: الرصيد المحسوب `70`، مصروفات قائمة الدخل `0`، والرصيد المخزَّن `70` عند محاكاة حذف ناعم. Y2: الأصول `380`، الخصوم `0`، حقوق الملكية `300`، `balanced=false`.
- PG1: الربح `120`، الإيراد `300`، VAT `42`، `bs=true`، والترحيل إلى 313 يساوي `120`؛ فحص `is_posted=1` لم يرجع خطأ.
- اختبارات PG للمبيعات: `PG-RACE-01` و`PG-ACC-01` نجحا، بينما `PG-NEG-02` و`PG-DUP-01` و`PG-RET-02` و`PG-RET-08` أخفقت كاستنساخات عيوب.

لا تعني مطابقة الأعداد أن كل تقرير سابق أعيد التحقق من كل استنتاجاته؛ تفاصيل ما لم يُشغّل واردة في `docs/plans/2026-11-01-audit-server-client-fx-bom-bank.md`.

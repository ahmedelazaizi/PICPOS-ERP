# النسخ الاحتياطي واستعادة PostgreSQL (دليل المشغّل)

**BKP-004.** في وضع خادم PostgreSQL لا يوجد نسخ احتياطي داخل التطبيق: زر النسخ والنسخ التلقائي عند الإقلاع يغطيان ملف SQLite/SQLCipher المحلي فقط. نسخ خادم PostgreSQL مسؤولية المشغّل، وهذه هي الطريقة المعتمدة. The operator is responsible for keeping a copy off the server and performing the restore drill below.

## ⚠️ تحذير أمني
* النسخ **غير مشفّرة** (ملف `.dump` يحوي كل بيانات الشركة بنص واضح).
* تُحفظ افتراضياً **على القرص نفسه** في `D:\PICPOS-ERP\backups\postgres`. نسخة على نفس القرص ليست نسخة احتياطية حقيقية: **انسخ المجلد دورياً خارج الجهاز** (قرص خارجي/NAS/سحابة مشفّرة).
* احمِ المجلد بصلاحيات NTFS أو شفّر القرص (BitLocker). الملفات مُستثناة من git عبر `.gitignore`.
* كلمة المرور لا تُمرَّر أبداً في سطر الأوامر ولا تُكتب في السجل.

## الاستخدام
السكربت المعتمد هو `scripts/backup_postgres.ps1` (مساره النسبي في أوامر Windows يظهر بشرطة مائلة عكسية). كلمة المرور من متغير البيئة `PGPASSWORD` **أو** من الملف `%APPDATA%\postgresql\pgpass.conf` (سطر: `host:port:db:user:password`).

```powershell
$env:PGPASSWORD = '<password>'
powershell -File scripts\backup_postgres.ps1 -Database picpos -DbHost localhost -Port 5432 -User postgres
```

| معامل | الافتراضي | الوصف |
|---|---|---|
| `-Database` / `-DbHost` / `-Port` / `-User` | `picpos` / `localhost` / `5432` / `postgres` | الاتصال |
| `-OutDir` | `backups\postgres` | مجلد الحفظ |
| `-KeepDaily` (`-KeepDays` اسم قديم) / `-KeepWeekly` | `14` / `8` | سياسة الاحتفاظ |
| `-PgBin` | (اكتشاف تلقائي) | مجلد أدوات PostgreSQL |
| `-PruneOnly` | — | تطبيق الاحتفاظ فقط دون أخذ نسخة (للاختبار) |

* يبحث عن `pg_dump` في `-PgBin` ثم أحدث إصدار تحت `C:\Program Files\PostgreSQL\<ver>\bin` ثم `PATH`.
* الصيغة custom مضغوطة (`-Fc`)، والملف: `backups\postgres\<db>_yyyyMMdd_HHmmss.dump` + ملف `.sha256`.
* يُكتب أولاً كـ `.partial` ثم يُتحقق منه (غير فارغ + نجاح `pg_restore --list`) قبل إعادة تسميته.
* السجل: `backups\postgres\backup.log` (بلا أسرار).
* رموز الخروج: `0` نجاح · `1` معاملات خاطئة · `2` الأدوات غير موجودة · `3` فشل `pg_dump` · `4` فشل التحقق · `5` فشل الاحتفاظ (النسخة نفسها سليمة).

> **توافق الإصدارات:** استعمل أدوات بإصدار ≥ إصدار الخادم. `pg_dump` 18 يأخذ نسخة من خادم 16 بنجاح، لكن `pg_restore` 18 **يفشل** عند الاستعادة إلى خادم 16 (`unrecognized configuration parameter "transaction_timeout"`). استعد دائماً إلى خادم بنفس إصدار الأدوات أو أحدث.

## الجدولة
```powershell
.\scripts\register_postgres_backup_task.ps1 -WhatIf          # معاينة دون تسجيل
.\scripts\register_postgres_backup_task.ps1                  # يومياً 02:30
.\scripts\register_postgres_backup_task.ps1 -At 03:15 -Database picpos -Port 5432
.\scripts\register_postgres_backup_task.ps1 -Unregister
```
المهمة `PicPos PostgreSQL Backup` تعمل بحساب المستخدم الحالي (Interactive، لا تُخزَّن كلمة مرور ويجب أن يكون المستخدم مسجّلاً دخوله). اضبط لذلك المستخدم `PGPASSWORD` كمتغير بيئة للمستخدم أو `pgpass.conf`. راقب رمز الخروج غير الصفري / `backup.log`.

## الاستعادة
تستعيد إلى قاعدة **جديدة** فقط:
```powershell
powershell -File scripts\restore_postgres.ps1 -DumpFile backups\postgres\picpos_20260101_023000.dump -TargetDatabase picpos_restored
```
* ترفض الكتابة فوق قاعدة موجودة (خروج `3`). `-Force` يحذف ويعيد إنشاء القاعدة بعد أن تكتب اسمها يدوياً للتأكيد (تفاعلي).
* ترفض `postgres` و`template0/1`، وتتحقق من `.sha256` إن وُجد (خروج `6` عند عدم التطابق).
* رموز الخروج: `0` · `1` معاملات/إلغاء · `2` أدوات · `3` القاعدة موجودة · `4` فشل إنشاء/حذف · `5` فشل `pg_restore` · `6` بصمة غير مطابقة.

## الاحتفاظ
يُحتفظ بأحدث نسخة من كل يوم لآخر `KeepDaily` يوماً فيها نسخ، إضافة إلى أحدث نسخة من كل أسبوع (اثنين–أحد) لآخر `KeepWeekly` أسبوعاً. الباقي (مع `.sha256`) يُحذف، وبعد نجاح التحقق من النسخة الجديدة فقط. يُطبَّق على قاعدة البيانات المحددة فقط. احتفظ بنسخة قبل كل ترقية للتطبيق خارج المجلد.

## Restore drill — اختبار الاستعادة الدوري (كل ربع سنة)
1. استعد أحدث نسخة إلى `picpos_restore_test` على خادم تجريبي.
2. شغّل نسخة **اختبارية** من التطبيق عليها وتحقق: ميزان المراجعة متوازن، أرصدة الأطراف تطابق الدفتر، وآخر فاتورة موجودة.
3. احذف قاعدة الاختبار. نسخة لم تُستعَد أبداً غير مثبتة.

## اختبار السكربتات
`powershell -NoProfile -File scripts\test_postgres_backup_scripts.ps1` — بلا PostgreSQL: صياغة السكربتات ومنطق الاحتفاظ على مجلد مؤقت و`-WhatIf` للمهمة.


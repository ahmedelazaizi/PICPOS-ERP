# تقرير أداء ERP/POS — 2026-09

## الملخص العربي

أُجري القياس على قاعدة SQLite ملفّية فعلية في مجلد مؤقت، مع تفعيل WAL و`busy_timeout`. استُخدم profile `full` المطلوب: 20,000 منتج، 5,000 طرف، 150,000 فاتورة مبيعات (أربع أسطر في المتوسط)، و10,000 فاتورة مشتريات. استغرق الـseed `10.96s`، أي أقل كثيراً من حد 25 دقيقة.

النتيجة العامة: مسارات البحث والبيع والتقارير والإقلاع اجتازت الحدود المحددة. اختبار 20 cashier حقق 341 sales/min مع صفر أخطاء، وأرقام الفواتير فريدة، ودفتر الأستاذ متوازن، وكميات المخزون متسقة. لكن p95 للكتابة المتزامنة بلغ `4035.68ms`؛ هذا bottleneck في تسلسل معاملات SQLite تحت الكتابة المتزامنة، وليس فشل integrity.

لم يتغير أي production code، لذلك لا توجد migration أو before/after fix numbers. لا يوجد FAIL ضمن thresholds المعلنة يستوجب index/N+1 fix. خطط الاستعلام سُجلت أدناه؛ مسح المنتجات في contains وinventory valuation متوقعان من طبيعة الاستعلام، ومع ذلك بقيت المقاييس تحت الحدود.

## البيئة والبيانات

| البند | القيمة |
|---|---:|
| CPU | Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz |
| Cores / logical processors | 8 / 16 |
| RAM | 31.7 GB |
| Disk | NVMe Samsung SSD 990 (PowerShell `Get-CimInstance Win32_DiskDrive`) |
| Profile | `full` |
| Products | 20,000 |
| Parties | 5,000 |
| Sales invoices | 150,000 |
| Sales lines | 600,000 (4/invoice) |
| Purchase invoices | 10,000 |
| Seed time | 10.96s — PASS (<25 min) |
| Database | File-backed SQLite in temp directory; WAL, `synchronous=NORMAL`, `busy_timeout=60000` |

التنفيذ استخدم bulk SQL داخل schema الحقيقي للـhistorical rows، مع JEs متوازنة: أربعة أسطر لكل sale (cash, revenue, COGS, inventory) وسطران لكل purchase. المسارات المقاسة للـcash sale والvoucher والreturn/void استدعت DAOs الحقيقية. هذا قرار مقصود حتى يبقى seed أقل من الميزانية؛ ليس كل 150,000 invoice مرّ عبر posting path الكامل.

ملاحظة harness: `AppDatabase.forTesting()` في الكود الحالي يفتح `NativeDatabase.memory()` فقط، لذلك استُخدم `AppDatabase.withExecutor(NativeDatabase(file))` للحفاظ على نفس `AppDatabase`/migrations/DatabaseStartup مع disk I/O حقيقي، بدلاً من تعديل production constructor بلا defect مثبت.

## المقاييس

الأزمنة بالميلي ثانية، و`p50/p95/max` من 20 عينة في profile `full`، ما عدا cold open (عينة واحدة). حدود التقارير هي `<3s`، وحد cash sale هو `<300ms`، وحد shift هو `<5s`.

| المسار | p50 | p95 | max | الحالة |
|---|---:|---:|---:|---|
| Product search — name contains | 7.28 | 8.77 | 9.98 | PASS |
| Product search — barcode prefix | 2.96 | 4.11 | 4.34 | PASS |
| Add-to-cart price lookup | 0.27 | 0.56 | 3.96 | PASS |
| Cash sale end-to-end | 178.97 | 219.28 | 413.59 | PASS (<300 p95) |
| Cash sale — 30 lines | 256.67 | 298.15 | 315.70 | PASS (<300 p95) |
| Sales return/void path | 325.59 | 417.35 | 466.44 | PASS (no stated return limit; <3s report budget) |
| Receipt voucher | 10.48 | 16.31 | 31.00 | PASS |
| Sales invoice list page 1 | 62.82 | 115.51 | 116.00 | PASS |
| Customer statement — 12 months | 61.42 | 74.41 | 78.64 | PASS (<3s) |
| Trial balance — year | 1.96 | 3.51 | 4.31 | PASS (<3s) |
| General ledger — cash/month | 0.56 | 3.73 | 3.94 | PASS (<3s) |
| Inventory valuation | 701.55 | 788.51 | 818.36 | PASS (<3s) |
| Shift-close aggregate — 500 invoices | 36.20 | 43.92 | 46.13 | PASS (<5s) |
| Cold open to first query | 869.49 | 869.49 | 869.49 | PASS (observed) |

`shift-close aggregate` يقيس الجزء التجميعي الفعلي على shift يحتوي 500 invoice، وليس destructive finalization call المتكرر؛ إغلاق shift الكامل يغيّر حالة البيانات، لذلك لم يُكرّر 20 مرة داخل نفس fixture.

## التزامن والسلامة

| البند | النتيجة | الحالة |
|---|---:|---|
| Cashiers | 20 لمدة 60s | PASS — requested load |
| Throughput | 341 sales/min | PASS — observed |
| API handler p95 | 4035.68ms | FAIL* — SQLite write serialization bottleneck |
| API errors | 0 | PASS |
| Duplicate invoice numbers | 0 | PASS |
| Journal debit-credit difference | 0.0000 | PASS |
| Stock mismatches | 0 | PASS |

التزامن استدعى `ApiSalesHandler.postSale` في-process مع request context/auth identity لكل simulated cashier. لم تُفتح socket LAN حقيقية؛ middleware/session transport يحتاج fixture credentials غير متاح في الاختبارات الحالية. هذا يقيس handler + DB transaction، وليس network latency. *FAIL هنا توصيف latency تحذيري بلا threshold p95 معلن؛ شرط concurrency المعلن (20 cashier، صفر أخطاء، ledger balanced) PASS، وخطة الاستعلام لا تشخّص lock serialization.

## EXPLAIN QUERY PLAN

الخطط المقيسة على نفس قاعدة full:

| الاستعلام | الخطة |
|---|---|
| Product contains | `SCAN products` + `USE TEMP B-TREE FOR ORDER BY` |
| Invoice list page | `SCAN sales_invoices` + `USE TEMP B-TREE FOR ORDER BY` |
| Customer statement | `SEARCH sales_invoices USING INDEX idx_sales_invoices_customer (customer_id=?)` + `USE TEMP B-TREE FOR ORDER BY` |
| Inventory valuation | `SCAN products` |

لم تُجرَ production index changes: مسح contains/valuation متسق مع semantics الحالية، والمقاييس أقل بكثير من الحدود. Bottleneck التزامن هو write serialization/transaction contention وليس N+1 أو missing read index مثبتاً بهذه القياسات.

## التحقق والأوامر

الأمر الكامل:

```powershell
$env:PERF_PROFILE='full'; & 'D:\Cash\develop\flutter\bin\flutter.bat' test --tags perf test/perf/erp_load_bench_test.dart
```

الناتج النهائي:

```text
01:49 +1: All tests passed!
```

تحليل benchmark/runner:

```text
D:\Cash\develop\flutter\bin\cache\dart-sdk\bin\dart.exe analyze test/perf tool/perf
No issues found!
```

يوجد في test harness تحذير متكرر من `path_provider` لأن plugin غير مربوط في Flutter test (`MissingPluginException` أثناء deferred backup/logging). لم يسبب فشل test، ولم يدخل في `PERF_ERRORS`، وسُجّل هنا حتى لا تُفهم رسائل الـlog على أنها قياس صامت ناجح.

## الملفات والنطاق

- `test/perf/erp_load_bench_test.dart`: benchmark وseed والتحقق.
- `tool/perf/run_perf.dart`: runner؛ بدون `--full` يشغل smoke profile، ومع `--full` يشغل dataset المطلوب.

لم تُلمس ملفات الطباعة أو folders untracked أو production code. بقيت تغييرات workers المتزامنة كما وُجدت في الشجرة.

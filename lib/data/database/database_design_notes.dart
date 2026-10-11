part of 'database.dart';

// Design notes for `AppDatabase` (database.dart). Comment-only part: the blocks
// below were moved verbatim from the doc comments of the members named.

// ── AppDatabase.isInTransaction ──
  //
  // Read caches must not be populated or served while this is true. A read
  // taken mid-transaction sees state that may never be committed, and the
  // product cache is process-global and has no notion of rollback — so one
  // such read outlives the transaction and is handed to every later reader.
  // That is not merely a stale display: `updateProductWAC` computes the
  // weighted average from a cached `currentStock`/`costPrice` pair and WRITES
  // the result, turning a poisoned read into stored cost.
  //
  // Bypassing reads as well as writes is deliberate — inside a transaction a
  // caller must see its OWN uncommitted writes, which a pre-transaction
  // cache entry would hide.
  //
  // ⚠️ **Deliberately over-conservative.** drift runs a transaction body in
  // its own zone, so `resolvedEngine is Transaction` is scoped to the code
  // actually inside it. This counter is a plain instance field, so it reads
  // true for EVERY caller on this database while any transaction is open —
  // a POS barcode lookup during invoice posting bypasses the cache too, and
  // (because the write side is skipped as well) stays cold.
  //
  // That is safe but not free: correctness is unaffected — a database read is
  // always at least as correct as a memoised one — while cache hit rate drops
  // for the duration of any transaction. The zone-scoped alternative is
  // `resolvedEngine`, which is `@internal` and cannot be used without
  // breaking `flutter analyze`. **The performance cost is UNMEASURED**;
  // measuring barcode-scan latency on weak hardware is a tracked follow-up.

// ── AppDatabase.forWebRemote ──
  // عميل الويب (م3-6): قاعدةٌ فوق اتصال drift remote إلى مضيف الديسكتوب
  // (قراءةٌ فقط، lib/web/web_remote_connection.dart).
  //
  // **تتخطّى الترحيلات وكلَّ ما يعمل عند الفتح** (onCreate/onUpgrade/
  // eforeOpen بما فيها PRAGMA وبذرة البيانات): المضيف هو صاحب المخطّط،
  // واعتراضُ سياسة القراءة يرفض أصلاً كلَّ PRAGMA/كتابة، فتشغيلُها على
  // العميل إمّا يفشل وإمّا — لو وصل — يعبث بقاعدة المضيف. [isPostgres]
  // يُضبط من استجابة الخادم عند الدخول ليتّفق توليدُ SQL مع محرّك المضيف.
  // ليست singleton.

part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// المرفقات — v176 · §٨ من خطّة إعادة تصميم الشاشات (ح‑٤)
// ═══════════════════════════════════════════════════════════════════════════
//
// 🔴 **جدولان لا جدول، والفصلُ بينهما هو كلُّ الفكرة.**
//
// الوصفُ (`attachments`) نصٌّ صغيرٌ **يُزامَن** في القوائم الثماني.
// والبايتاتُ (`attachment_blobs`) **خارجَ كلِّ قائمةِ سحبٍ عمداً**.
//
// ولماذا لا عمودُ BLOB واحدٌ على جدولٍ مُزامَن؟ **لأنّه لا يعبر السلكَ
// أصلاً**: مُسلسِلُ `_getSyncPull` في `api_handler` يُسقط كلَّ
// `List<int>` بـ`continue`. فبايتاتٌ في جدولٍ مسحوبٍ تعني صفّاً يصل
// بلا محتواه — ثمّ **تنتفخ حمولةُ السحب الدوريّ** بلا أن يصل شيء.
//
// وبالفصل:
//   • النسخُ الاحتياطيُّ يعمل بلا سطرٍ واحد — البايتاتُ داخلَ `.sqlite`
//     (و`BackupService.performBackup` نسخةُ ملفٍّ واحدٍ لا أكثر).
//   • ولا مسارَ ملفٍّ في قاعدةٍ إطلاقاً — فلا رابطَ معلَّقٌ بعد استعادة.
//   • والبايتاتُ تُجلَب عند الطلب: `GET /api/attachments/<globalId>`.

/// وصفُ المرفق — **يُزامَن**.
@DataClassName('AttachmentData')
@TableIndex(name: 'idx_attachment_entity', columns: {#entityType, #entityId})
@TableIndex(
    name: 'idx_attachment_entity_gid', columns: {#entityType, #entityGlobalId})
@TableIndex(name: 'idx_attachment_sha', columns: {#shaHex})
class Attachments extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// نوعُ المستند المُرفَقِ به — من `kAttachmentEntityTypes`.
  TextColumn get entityType => text().withLength(min: 1, max: 40)();

  /// 🔴 **الهُويّةُ العالميّةُ للمستند هي الرابطُ عبر الأجهزة.**
  ///
  /// رقمُ المستند المحلّيُّ لا يعبر جهازَين: الرقمُ ٧ على هذا الجهاز
  /// قد يكون فاتورةً أخرى تماماً على الخادم. وهو عينُ الدرس الذي
  /// دفعته المرحلةُ الثامنة في وكيل التخليص.
  TextColumn get entityGlobalId => text().nullable()();

  /// رقمٌ محلّيٌّ **للقراءة السريعة وحدَها** — لا يُعوَّل عليه عبر السلك.
  IntColumn get entityId => integer().nullable()();

  TextColumn get fileName => text().withLength(min: 1, max: 255)();
  TextColumn get mimeType => text().withLength(min: 1, max: 100)();
  IntColumn get byteSize => integer()();

  /// بصمةُ المحتوى ستّاً وستّين محرفاً ستّ عشريّاً.
  ///
  /// ⚠️ **وليست زينةً**: بها تُكشَف بايتاتٌ وصلت ناقصةً، وبها يُعرَف أنّ
  /// ملفاً واحداً أُرفق بمستندَين فلا يُخزَّن مرّتَين.
  ///
  /// والاسمُ `shaHex` لا `sha256` عمداً: `sha256` رمزٌ عامٌّ في حزمة
  /// `crypto` تستورده هذه المكتبةُ نفسُها.
  TextColumn get shaHex => text().withLength(min: 64, max: 64)();

  /// تصنيفُ الورقة — من `AttachmentDocType`.
  TextColumn get docType => text()
      .withLength(min: 1, max: 40)
      .withDefault(const Constant('other'))();

  IntColumn get attachedByUserId =>
      integer().nullable().references(Users, #id)();
  DateTimeColumn get attachedAt =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get notes => text().nullable()();

  // === v176 — أعمدةُ المزامنة ===
  TextColumn get globalId => text().nullable().unique()();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// البايتات — 🚫 **خارجَ كلِّ قائمةِ سحبٍ عمداً**.
///
/// ⚠️ **ولا أعمدةَ مزامنةٍ لها عمداً أيضاً**: جدولٌ بلا `global_id` ولا
/// `last_modified_at` لا يُقبَل في `pullTables` أصلاً، فالبنيةُ نفسُها
/// تقاوم الإضافةَ الساهية — ويشدُّها حارسٌ بنيويٌّ فوق ذلك
/// (`attachment_blobs_stay_off_the_wire_test.dart`).
///
/// وهي **خبيئةٌ لا مصدرُ حقيقة**: محوُها يُفقد العرضَ السريعَ لا المرفقَ
/// نفسَه — يُعاد جلبُه من الخادم بـ`GET /api/attachments/<globalId>`.
/// وعلى الخادم هي المصدر.
@DataClassName('AttachmentBlobData')
class AttachmentBlobs extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// الهُويّةُ العالميّةُ لصفِّ `attachments` — لا رقمُه المحلّيّ.
  TextColumn get attachmentGlobalId => text().unique()();

  BlobColumn get bytes => blob()();

  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();
}

// تجاوزُ مستودع المرفقات لاختبارات الودجت — **ضرورةٌ لا راحة**.
//
// ═══ 🔴 ما يقع بدونه ═══
//
// `PicPosAttachmentsPanel` يقرأ `attachmentAnchorProvider` ⇐
// `attachmentsRepositoryProvider` ⇐ `databaseProvider` — وذاك يبني
// `AppDatabase()` **حقيقيّةً** تفتح ملفّاً على القرص. وداخلَ منطقةِ الزمن
// الوهميّةِ في `testWidgets` لا تكتمل مؤقّتاتُ drift أبداً، فـ
// `pumpAndSettle` **لا يستقرّ** ويسقط الاختبارُ بـ«pumpAndSettle timed out»
// — رسالةٌ **لا تذكر المرفقاتِ بكلمة**، فتُقرأ عطباً في الشاشة المختبَرة.
//
// وقد وقع فعلاً عند تركيب اللوح (2026-09-20): **٢٢ اختبارَ ودجتٍ سقطت
// دفعةً واحدة** في أربعة ملفّات لا علاقةَ لأيٍّ منها بالمرفقات.
//
// ⚠️ **ولذلك يُسمّى الملفُّ ويُشارك**: كلُّ اختبارٍ يرسم واحدةً من الشاشات
// الستِّ الحاملةِ للّوح يمرّر [attachmentsTestOverrides]، ويشدُّ ذلك حارسٌ
// بنيويٌّ في `attachments_mounted_where_documents_live_test.dart` — فمن
// ينسى يرى **بلاغاً يسمّي السبب** لا انتظاراً صامتاً.

import 'dart:typed_data';

import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/models/attachment_policy.dart';
import 'package:picpos_erp/domain/repositories/attachments_repository.dart';

/// مستودعُ مرفقاتٍ بلا قاعدة — يردّ فراغاً ويسجّل ما طُلب منه.
class FakeAttachmentsRepository implements IAttachmentsRepository {
  FakeAttachmentsRepository({
    this.anchor = 'doc-test',
    List<AttachmentData>? rows,
  }) : rows = rows ?? <AttachmentData>[];

  /// هُويّةُ المستند التي يردّها. `null` ⇒ «لم يَنَلها بعد».
  final String? anchor;
  final List<AttachmentData> rows;

  final adds = <String>[];
  final deletes = <String>[];

  @override
  Future<String?> entityGlobalId({
    required String entityType,
    required int entityId,
  }) async =>
      anchor;

  @override
  Stream<List<AttachmentData>> watchAttachments({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
  }) =>
      Stream<List<AttachmentData>>.value(rows);

  @override
  Future<List<AttachmentData>> getAttachments({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
  }) async =>
      rows;

  @override
  Future<AttachmentResult> addAttachment({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
    AttachmentDocType docType = AttachmentDocType.other,
    int? attachedByUserId,
    String? notes,
  }) async {
    adds.add(fileName);
    return (error: null, attachment: null);
  }

  @override
  Future<String?> deleteAttachment(String globalId) async {
    deletes.add(globalId);
    return null;
  }

  @override
  Future<Uint8List?> attachmentBytes(AttachmentData attachment) async => null;

  @override
  Future<bool> hasLocalBytes(String globalId) async => false;
}

/// يُوضَع في `overrides:` هكذا:
///
/// ```dart
/// overrides: [
///   attachmentsRepositoryProvider.overrideWithValue(fakeAttachmentsRepo()),
/// ],
/// ```
///
/// ⚠️ **ولماذا دالّةٌ تردّ المستودعَ لا قائمةَ تجاوزات؟** لأنّ الصنفَ
/// `Override` **غيرُ مُصدَّرٍ من `flutter_riverpod`** (الإصدار ٣)، فدالّةٌ
/// تُرجِع `List<Override>` لا تُترجَم — واستيرادُ `package:riverpod`
/// مباشرةً اعتمادٌ على حزمةٍ انتقاليّة.
FakeAttachmentsRepository fakeAttachmentsRepo({
  String? anchor = 'doc-test',
  List<AttachmentData> rows = const [],
}) =>
    FakeAttachmentsRepository(anchor: anchor, rows: rows);

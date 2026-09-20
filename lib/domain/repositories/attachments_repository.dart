import 'dart:typed_data';

import '../../data/database/database.dart' as db;
import '../models/attachment_policy.dart';

/// نتيجةُ إرفاقٍ — **رسالةٌ عربيّةٌ أو صفٌّ**، لا استثناءٌ يُلتقَط في الودجت.
///
/// ⚠️ ولماذا لا استثناء؟ لأنّ رفضَ السياسة (ملفٌّ كبيرٌ، نوعٌ غيرُ مسموح،
/// سقفُ العدد) **حالةٌ متوقَّعةٌ يراها المستخدمُ كلَّ يوم** لا عطبٌ
/// برمجيّ. والاستثناءُ في مسارٍ متوقَّعٍ يُغري بـ`catch` عامٍّ يبتلع
/// العطبَ الحقيقيَّ معه.
typedef AttachmentResult = ({String? error, db.AttachmentData? attachment});

/// مرفقاتُ المستندات — §٨.
abstract class IAttachmentsRepository {
  Stream<List<db.AttachmentData>> watchAttachments({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
  });

  Future<List<db.AttachmentData>> getAttachments({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
  });

  /// إرفاقُ ملفّ — يحسب البصمةَ ويطبّق [validateAttachment] **ثمّ** يختم
  /// الهُويّةَ العالميّةَ قبل الكتابتَين (المحلّيّةِ والخادم).
  Future<AttachmentResult> addAttachment({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
    AttachmentDocType docType,
    int? attachedByUserId,
    String? notes,
  });

  /// حذفٌ ناعمٌ للوصف ومحوٌ للبايتات.
  Future<String?> deleteAttachment(String globalId);

  /// هُويّةُ المستند العالميّةُ من رقمِه المحلّيّ.
  ///
  /// `null` تعني **«لم يَنَلها بعد»** لا «لا وجودَ له» — والفرقُ
  /// يُعرَض للمستخدم رسالةً لا خطأً.
  Future<String?> entityGlobalId({
    required String entityType,
    required int entityId,
  });

  /// بايتاتُ مرفقٍ — من الخبيئة المحلّيّة، وإلّا **جُلبت من الخادم**
  /// وتُحقَّق بصمتُها قبل أن تُخزَّن.
  ///
  /// `null` تعني «تعذّر»، لا «لا وجودَ له».
  Future<Uint8List?> attachmentBytes(db.AttachmentData attachment);

  /// هل بايتاتُه عند هذا الجهاز الآن؟ — لعرض «يُجلَب…» بلا محاولة.
  Future<bool> hasLocalBytes(String globalId);
}

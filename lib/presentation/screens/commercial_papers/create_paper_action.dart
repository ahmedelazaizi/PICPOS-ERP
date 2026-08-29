// إنشاءُ ورقةٍ تجاريّة — **مسارٌ واحدٌ تستدعيه الشاشتان**.
//
// ═══ لماذا دالّةٌ مستقلّة ═══
//
// الإنشاءُ يكتب **مرّتَين** على العميل: دفعةٌ للخادم عبر
// [ClientWriteInterceptor] ثمّ كتابةٌ محلّيّةٌ عبر المستودع. والـ`globalId`
// يُسَكّ **مرّةً واحدةً** ويُمرَّر لكليهما.
//
// 🔴 وقع فعلاً (‏Cluster 030 / Bug D): لمّا سُكَّ في كلّ طرفٍ على حدة، انتهى
// الخادمُ والمرآةُ بهويّتَين مختلفتَين لنفس الورقة — فكلُّ تحديثِ حالةٍ
// لاحقٍ من المرآة يفشل بـ«Commercial paper not found».
//
// ⇒ فحين صارت شاشةُ PicPos تُنشئ ورقةً أيضاً، كان **نسخُ** الكتلة يعني
//   نسختَين من مسارٍ ماليٍّ تنحرفان بأوّل تعديل. والواجهةُ تُفرَك، أمّا
//   المالُ فيُشارَك.
import '../../../core/utils/uuid_v7.dart';
import '../../../domain/repositories/commercial_papers_repository.dart';
import '../../../services/client_write_interceptor.dart';

/// `''` من حقلٍ لم يكتب فيه المستخدمُ شيئاً ⇒ `null`.
///
/// ⚠️ وليسا سواءً في التقارير: الفارغُ يُطبَع سطراً خالياً بينما الغائبُ
/// يُطوى.
String? _orNull(Object? v) {
  final s = v as String?;
  return (s == null || s.isEmpty) ? null : s;
}

/// يُنشئ الورقةَ على الخادم (‏في وضع العميل) وفي القاعدة المحلّيّة بهويّةٍ
/// واحدة، ويُرجع معرِّفَها المحلّيّ.
///
/// [form] هي خريطةُ حوار الإنشاء كما يُرجعها — نفسُها للشاشتَين.
///
/// ⚠️ و[direction] قد تصل `portfolio` وهي **تبويبةُ عرضٍ لا اتّجاهُ ورقة**.
/// تمريرُها كما هي يكتب في العمود قيمةً لا يعرفها أيُّ مرشِّحٍ لاحق، فتختفي
/// الورقةُ من «الواردة» و«الصادرة» معاً.
Future<int> createCommercialPaper({
  required ICommercialPapersRepository repo,
  required String direction,
  required Map<String, dynamic> form,
}) async {
  final resolvedDirection = direction == 'portfolio' ? 'received' : direction;
  final globalId = UuidV7.generate();

  final type = form['type'] as String;
  final paperNumber = form['number'] as String;
  final amount = form['amount'] as double;
  final partyId = form['partyId'] as int;
  final issueDate = form['issueDate'] as DateTime;
  final dueDate = form['dueDate'] as DateTime;
  final bankName = _orNull(form['bankName']);
  final accountNumber = _orNull(form['accountNumber']);
  final notes = _orNull(form['notes']);

  // ── وضعُ العميل: دفعةٌ للخادم أوّلاً ──
  await ClientWriteInterceptor.createCommercialPaper(
    type: type,
    paperNumber: paperNumber,
    direction: resolvedDirection,
    amount: amount,
    issueDate: issueDate,
    dueDate: dueDate,
    partyId: partyId,
    bankName: bankName,
    accountNumber: accountNumber,
    notes: notes,
    globalId: globalId,
  );

  return repo.createPaper(
    type: type,
    paperNumber: paperNumber,
    direction: resolvedDirection,
    amount: amount,
    issueDate: issueDate,
    dueDate: dueDate,
    partyId: partyId,
    bankName: bankName,
    accountNumber: accountNumber,
    notes: notes,
    globalId: globalId,
  );
}

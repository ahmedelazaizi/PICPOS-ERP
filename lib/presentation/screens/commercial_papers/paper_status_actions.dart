// انتقالاتُ حالة الورقة التجاريّة — **مسارٌ واحدٌ تستدعيه الشاشتان**.
//
// ═══ لماذا ملفٌّ مستقلّ ═══
//
// كلُّ انتقالٍ يكتب **مرّتَين** على العميل: دفعةٌ للخادم عبر
// [ClientWriteInterceptor] ثمّ كتابةٌ محلّيّةٌ عبر المستودع. وهذه الكتلةُ
// مكرّرةٌ سبعَ مرّاتٍ في `commercial_papers_dialogs.dart` — فنسخُها ثامنةً
// لشاشة PicPos يعني ثمانيَ نسخٍ من مسارٍ ماليٍّ تنحرف بأوّل تعديل. وعطبُ
// Cluster 030 / Bug D كان بالضبط انحرافَ نسختَين.
//
// ⇒ الواجهةُ تُفرَك، والمالُ يُشارَك.
//
// ═══ لماذا دوالُّ مسمّاةٌ لا `changeStatus(id, status)` ═══
//
// السلاسلُ الحرّةُ تُخفي قواعدَ الانتقال. مقيسٌ في `commercial_papers_dao.dart`
// أنّ الحالاتِ ليست متكافئة:
//
// • `depositForCollection` يقبل `pending`/`in_portfolio` **وحدَهما** ويكتب
//   `deposited_for_collection`.
// • و«إعادةُ إيداعِ» ورقةٍ مرتجعةٍ لا تمرّ به إطلاقاً — مسارُها
//   `updatePaperStatus(id,'deposited')`، وهو ما تفعله الشاشةُ القديمة.
//
// فدالّةٌ باسمِ الغرض تحمل هذا في توقيعها، وسلسلةٌ حرّةٌ تتركه في رأس مَن
// كتب النداء.
import '../../../domain/repositories/commercial_papers_repository.dart';
import '../../../services/client_write_interceptor.dart';

/// يُعيد إيداعَ ورقةٍ **مرتجعة**.
///
/// 🔴 **لا يمرّ بـ`depositForCollection`**: حارسُه
/// `if (!['pending','in_portfolio'].contains(paper.status)) throw` يرفض
/// المرتجعةَ دائماً. والمسارُ الصحيحُ — وهو ما تستعمله الشاشةُ القديمة —
/// `updatePaperStatus(id,'deposited')`.
Future<void> redepositBouncedPaper({
  required ICommercialPapersRepository repo,
  required int paperId,
  int? changedBy,
  String? notes,
}) =>
    _transition(
      repo: repo,
      paperId: paperId,
      status: 'deposited',
      changedBy: changedBy,
      notes: notes ?? 'إعادة إيداع بعد ارتجاع',
    );

/// يسجّل تحصيلَ ورقةٍ واردةٍ — أو خصمَ ورقةٍ صادرةٍ من البنك.
///
/// ⚠️ **الحالةُ واحدةٌ للاتّجاهَين** (`cashed`) والمعنى مختلف: الواردةُ
/// تُحصَّل فيُدان البنك، والصادرةُ تُخصَم فيُدان الالتزام. والـDAO يفرّق
/// بينهما بـ`paper.direction` لا بحالةٍ ثانية — فتوحيدُ الاسم هنا يطابقه.
Future<void> markPaperCashed({
  required ICommercialPapersRepository repo,
  required int paperId,
  int? changedBy,
  String? notes,
  int? counterAccountId,
}) =>
    _transition(
      repo: repo,
      paperId: paperId,
      status: 'cashed',
      changedBy: changedBy,
      notes: notes,
      counterAccountId: counterAccountId,
    );

/// يُجيّر الورقةَ إلى [toPartyId] سداداً لمديونيّةٍ عليه.
///
/// ⚠️ نداءٌ مستقلٌّ لا انتقالُ حالةٍ عامّ: `endorsePaper` تحتاج **الطرفَ
/// المُجيَّرَ إليه**، ولا موضعَ له في `updatePaperStatus`.
Future<void> endorsePaperTo({
  required ICommercialPapersRepository repo,
  required int paperId,
  required int toPartyId,
  int? changedBy,
  String? notes,
}) async {
  await ClientWriteInterceptor.endorseCommercialPaper(
    paperId,
    toPartyId,
    changedBy: changedBy,
    notes: notes,
  );
  await repo.endorsePaper(
    paperId,
    toPartyId,
    changedBy: changedBy,
    notes: notes,
  );
}

/// الكتلةُ المشتركةُ: الخادمُ أوّلاً ثمّ القاعدةُ المحلّيّة — بنفس الترتيب
/// الذي تستعمله الشاشةُ القديمة.
Future<void> _transition({
  required ICommercialPapersRepository repo,
  required int paperId,
  required String status,
  int? changedBy,
  String? notes,
  int? counterAccountId,
}) async {
  await ClientWriteInterceptor.updateCommercialPaperStatus(
    paperId,
    status,
    changedBy: changedBy,
    notes: notes,
    // Feature 048 (v130) — الحسابُ المقابلُ يُمرَّر للخادم أيضاً وإلّا نشأ
    // قيدُ الخادم على حسابٍ غيرِ الذي نشأ عليه قيدُ المرآة.
    counterAccountId: counterAccountId,
  );
  await repo.updatePaperStatus(
    paperId,
    status,
    changedBy: changedBy,
    notes: notes,
    counterAccountId: counterAccountId,
  );
}

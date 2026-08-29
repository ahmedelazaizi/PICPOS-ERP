// إيداعُ أوراقٍ برسم التحصيل — **مسارٌ واحدٌ تستدعيه الشاشتان**.
//
// ═══ لماذا دالّةٌ مستقلّة ═══
//
// الإيداعُ يكتب **مرّتَين** على العميل: دفعةٌ للخادم عبر
// [ClientWriteInterceptor] ثمّ كتابةٌ محلّيّةٌ عبر المستودع — نفسُ شكل
// [createCommercialPaper]. ونسختان من مسارٍ ماليٍّ تنحرفان بأوّل تعديل،
// وعطبُ Cluster 030 / Bug D كان بالضبط ذلك.
//
// ═══ ولماذا دفعةٌ لا ورقة ═══
//
// `DLGS.deposit` في `PicPos Cheques.dc.html` يودع **دفعةً**: رقاقاتُ شيكاتٍ
// تُختار من الخزنة، وقسيمةُ إيداعٍ واحدةٌ، وملخّصٌ بالإجمالي. والحوارُ القديم
// `DepositForCollectionDialog` يودع ورقةً واحدة — فالمشغّلُ الذي يودع خمسةَ
// شيكاتٍ بقسيمةٍ واحدةٍ في البنك يفتح الحوارَ خمسَ مرّات.
//
// و`repo.depositForCollection` تأخذ **معرِّفاً واحداً**، فالدفعةُ حلقةٌ فوقها
// لا استدعاءٌ جديدٌ في طبقة البيانات.
//
// 🔴 **والفشلُ الجزئيُّ ليس نظريّاً**: خمسةُ شيكاتٍ قد ينجح ثلاثةٌ منها ويفشل
// اثنان (‏ورقةٌ غيّر غيرُك حالتَها بين الفتح والحفظ). فابتلاعُ الاستثناء يترك
// المشغّلَ يظنّ أنّ القسيمةَ كاملةٌ وهي ناقصة، وإيقافُ الحلقة عند أوّل فشلٍ
// يترك الدفعةَ نصفَ مودعةٍ بلا بيان. ⇒ تُكمَل الحلقةُ ويُرجَع **مَن نجح ومَن
// فشل** ليقرأهما النداءُ ويقولهما للمستخدم.
import '../../../domain/repositories/commercial_papers_repository.dart';
import '../../../services/client_write_interceptor.dart';

/// حصيلةُ إيداعِ دفعة — تفصّل الناجحَ من الفاشل بدل «تمّ» أو استثناء.
class DepositBatchResult {
  const DepositBatchResult({required this.deposited, required this.failed});

  /// معرِّفاتُ الأوراق التي أُودعت فعلاً.
  final List<int> deposited;

  /// ما فشل، ومعه سببُه كما جاء — مفتاحُه معرِّفُ الورقة.
  final Map<int, Object> failed;

  bool get allSucceeded => failed.isEmpty;
  int get count => deposited.length;
}

/// يودع [paperIds] في الخزنة البنكيّة [bankSafeId] برسم التحصيل.
///
/// ⚠️ **لا تُلقي عند فشلِ ورقة.** تُكمِل البقيّةَ وتُرجع الحصيلةَ مفصَّلةً —
/// راجع تعليقَ الرأس.
///
/// و[notes] تُكتَب على كلّ ورقةٍ في الدفعة: رقمُ قسيمة الإيداع يخصّ الدفعةَ
/// كلَّها، وكتابتُه على كلّ ورقةٍ هي ما يجعل تتبّعَ القسيمة ممكناً لاحقاً.
Future<DepositBatchResult> depositPapersForCollection({
  required ICommercialPapersRepository repo,
  required List<int> paperIds,
  required int bankSafeId,
  int? changedBy,
  String? notes,
}) async {
  final deposited = <int>[];
  final failed = <int, Object>{};

  for (final id in paperIds) {
    try {
      // ── وضعُ العميل: دفعةٌ للخادم أوّلاً ──
      await ClientWriteInterceptor.depositPaperForCollection(
        id,
        bankSafeId,
        changedBy: changedBy,
        notes: notes,
      );
      await repo.depositForCollection(
        id,
        bankSafeId,
        changedBy: changedBy,
        notes: notes,
      );
      deposited.add(id);
    } catch (e) {
      failed[id] = e;
    }
  }

  return DepositBatchResult(deposited: deposited, failed: failed);
}

// «التوزيع والمواقع» — حسابٌ خالصٌ لتجميع الأصول على مواقعها وإعادةِ تسميتها.
//
// ═══ 🔴 لماذا يلزم علاجٌ أصلاً ═══
//
// `FixedAssets.location` **نصٌّ حرٌّ** (`text().nullable().withLength(max:
// 100)`) يكتبه حوارُ الإنشاء بيد المستخدم. فـ«الفرع الرئيسي» و«الفرع
// الرئيسى» و«الفرع الرئيسي » ثلاثةُ مواقعَ في كلّ تجميع — والشاشةُ تعرض
// ثلاثةَ صفوفٍ وثلاثَ قيمٍ دفتريّةٍ لمكانٍ واحد، فيقرأ المديرُ توزيعاً لم
// يقع. ولا شيءَ يبدو معطوباً: الجدولُ صحيحٌ حرفاً بحرف.
//
// والعلاجُ الوحيدُ الممكنُ بلا جدولٍ جديد هو **إعادةُ تسميةٍ تكتب كلَّ
// أصلٍ** يحمل الاسمَ القديم. وهي لذلك كتابةٌ على صفوفٍ متعدّدة، فتُخطَّط
// هنا — خالصةً ومقيسةً — قبل أن تُنفَّذ.
//
// ⚠️ **والتشذيبُ وحدَه لا يوحِّد**: «الرئيسي» و«الرئيسى» يختلفان بحرفٍ
// (ي/ى) لا بمسافة. فالدمجُ **قرارُ مستخدمٍ صريح** لا تطبيعٌ آليّ: النظامُ
// لا يعرف أنّ الاسمَين مكانٌ واحد، وتوحيدُهما بالتخمين يدمج مكانَين
// مختلفَين فعلاً («مخزن ١» و«مخزن ٢» ليسا كذلك، لكنّ أيَّ قاعدةِ تشابهٍ
// كانت ستجرّبهما).

/// وسمُ الأصول التي لا موقعَ لها — **يُعرَض ولا يُخزَّن**.
///
/// ⚠️ والعمودُ يبقى `null` لها: كتابةُ النصّ نفسِه في القاعدة تجعل «بلا
/// موقع» موقعاً حقيقيّاً يُرشَّح به ويُصدَّر، وتُفقد القدرةَ على تمييز ما
/// لم يُملأ ممّا مُلئ بهذا اللفظ.
const String kUnassignedAssetLocation = 'بلا موقع';

/// الموقعُ كما يُخزَّن — مشذَّبٌ، والفارغُ `null`.
String? normalizeAssetLocation(String? raw) {
  final t = (raw ?? '').trim();
  return t.isEmpty ? null : t;
}

/// الموقعُ كما يُعرَض ويُجمَّع عليه.
String assetLocationLabel(String? raw) =>
    normalizeAssetLocation(raw) ?? kUnassignedAssetLocation;

/// صفُّ أصلٍ بقدر ما يلزم التخطيطَ — لا أكثر.
typedef AssetLocationRow = ({int id, String? location});

/// خطّةُ إعادةِ تسميةٍ — ما سيُكتَب، وهل هو دمجٌ، ولماذا يُمنَع.
class AssetLocationRenamePlan {
  const AssetLocationRenamePlan({
    required this.assetIds,
    required this.target,
    required this.mergesInto,
    this.error,
  });

  /// أرقامُ الأصول التي ستُكتَب — وهي **كلُّ** ما سيتغيّر.
  final List<int> assetIds;

  /// الاسمُ بعد التشذيب، أو `null` إن مُنعت الخطّة.
  final String? target;

  /// عددُ الأصول القائمةِ **سلفاً** على الاسم الجديد.
  ///
  /// أكبرُ من صفرٍ ⇒ العمليّةُ **دمج** لا تسمية: الموقعان يصيران واحداً
  /// ولا سبيلَ لفكِّهما بعدها إلّا بإعادة تسميةِ كلِّ أصلٍ على حدة. فيُقال
  /// للمستخدم قبل التنفيذ.
  final int mergesInto;

  bool get isMerge => mergesInto > 0;
  bool get isAllowed => error == null;

  /// سببُ المنع — نصٌّ يُعرَض كما هو.
  final String? error;
}

/// يخطّط نقلَ كلِّ أصلٍ على [from] إلى [to].
///
/// ⚠️ **و[to] الفارغُ ممنوعٌ لا مُفسَّرٌ «امسح الموقع»**: حقلٌ تُرك فارغاً
/// بالسهو كان سيُجرّد عشراتِ الأصول من مواقعها بضغطةٍ واحدة، والتراجعُ
/// مستحيلٌ لأنّ الاسمَ القديم لم يعد مكتوباً في أيّ صفّ. وتجريدُ الموقع
/// فعلٌ آخرُ يُطلَب صراحةً على أصلٍ بعينه من بطاقته.
AssetLocationRenamePlan planAssetLocationRename({
  required String from,
  required String to,
  required List<AssetLocationRow> rows,
}) {
  final target = normalizeAssetLocation(to);
  if (target == null) {
    return const AssetLocationRenamePlan(
      assetIds: [],
      target: null,
      mergesInto: 0,
      error: 'اكتب اسم الموقع الجديد — والحقلُ الفارغ لا يعني «بلا موقع».',
    );
  }
  if (target.length > 100) {
    // العمودُ `withLength(max: 100)` — والقصُّ الصامتُ يكتب اسماً آخرَ غيرَ
    // الذي رآه المستخدم، فيصير موقعاً ثالثاً بدل أن يوحِّد اثنين.
    return const AssetLocationRenamePlan(
      assetIds: [],
      target: null,
      mergesInto: 0,
      error: 'اسمُ الموقع لا يتجاوز ١٠٠ حرف.',
    );
  }

  final fromLabel = assetLocationLabel(from);
  if (fromLabel == target) {
    return AssetLocationRenamePlan(
      assetIds: const [],
      target: target,
      mergesInto: 0,
      error: 'الاسمُ نفسُه — لا شيءَ يتغيّر.',
    );
  }

  final assetIds = <int>[];
  var mergesInto = 0;
  for (final r in rows) {
    final label = assetLocationLabel(r.location);
    if (label == fromLabel) {
      assetIds.add(r.id);
    } else if (label == target) {
      mergesInto++;
    }
  }

  if (assetIds.isEmpty) {
    return AssetLocationRenamePlan(
      assetIds: const [],
      target: target,
      mergesInto: mergesInto,
      error: 'لا أصولَ على «$fromLabel» — لا شيءَ يُنقَل.',
    );
  }

  return AssetLocationRenamePlan(
    assetIds: assetIds,
    target: target,
    mergesInto: mergesInto,
  );
}

import '../config/brand.dart';
import '../config/business_profile.dart';
import '../config/feature_policy.dart';
import 'screen_id.dart';

/// Central place for profile → screen visibility mapping.
class ScreenRegistry {
  static const List<ScreenId> restaurant = [
    ScreenId.dashboard,
    ScreenId.pos,
    ScreenId.tables,
    // مصمّمُ القاعة — حيث كانت الطاولاتُ كان مصمّمُها: الخريطةُ لا
    // تُرسَم مرّةً ثمّ تُنسى — تُنقَل الطاولاتُ ويُضاف قسمٌ.
    ScreenId.floorPlanDesigner,
    ScreenId.products,
    ScreenId.categories,
    ScreenId.parties,
    ScreenId.inventory,
    ScreenId.purchases,
    ScreenId.treasury,
    ScreenId.reports,
    ScreenId.settings,
    ScreenId.kitchen,
    ScreenId.analytics,
    ScreenId.salesInvoices,
    ScreenId.activityLog,
    ScreenId.eInvoice,
    ScreenId.inventoryBonds,
    ScreenId.stockTransfer,
    ScreenId.fieldAudit,
    ScreenId.users,
    ScreenId.rolesAndPermissions,
    ScreenId.auditTrail,
    ScreenId.shiftClose,
    ScreenId.taxReports,
    ScreenId.salesReturns,
    ScreenId.purchaseReturns,
    // الحجوزات: المطعمُ والمقهى والصالونُ هي التي تحجز مواعيد. ولا يكفي
    // إدراجُها في `screenPermissionMap` — الحلقةُ ترشِّح بنطاق الملفّ
    // **قبل** فحص الصلاحية، وهو ما أسقط إغلاقَ الورديّة من `unified`.
    ScreenId.bookings,
    // شاشةُ حسم القوالب: **كلُّ** نطاقٍ يطبع، وهي الموضعُ الوحيدُ الذي يقول
    // أيُّ قالبٍ يخرج مع أيِّ مستند. وحصرُها في نطاقٍ يترك البقيّةَ بلا
    // جوابٍ لسؤالٍ يقع فيها جميعاً.
    ScreenId.templateResolution,
  ];

  static const List<ScreenId> cafe = restaurant;

  static const List<ScreenId> supermarket = [
    ScreenId.dashboard,
    ScreenId.pos,
    ScreenId.offers,
    ScreenId.products,
    ScreenId.categories,
    ScreenId.parties,
    ScreenId.inventory,
    ScreenId.purchases,
    ScreenId.treasury,
    ScreenId.reports,
    ScreenId.settings,
    ScreenId.analytics,
    ScreenId.salesInvoices,
    ScreenId.activityLog,
    // NOTE: eInvoice intentionally excluded from the base supermarket flavor.
    // Pro/Plus retain it. Do not re-add without product-owner approval.
    ScreenId.inventoryBonds,
    ScreenId.stockTransfer,
    ScreenId.scalePlu,
    ScreenId.fieldAudit,
    ScreenId.users,
    ScreenId.rolesAndPermissions,
    ScreenId.auditTrail,
    ScreenId.shiftClose,
    ScreenId.taxReports,
    ScreenId.fiscalYear,
    ScreenId.salesReturns,
    ScreenId.purchaseReturns,
    // شاشةُ حسم القوالب: **كلُّ** نطاقٍ يطبع، وهي الموضعُ الوحيدُ الذي يقول
    // أيُّ قالبٍ يخرج مع أيِّ مستند. وحصرُها في نطاقٍ يترك البقيّةَ بلا
    // جوابٍ لسؤالٍ يقع فيها جميعاً.
    ScreenId.templateResolution,
  ];

  /// Supermarket + HR module (no tables/kitchen)
  static const List<ScreenId> supermarketPro = [
    ScreenId.dashboard,
    ScreenId.pos,
    ScreenId.offers,
    ScreenId.products,
    ScreenId.categories,
    ScreenId.parties,
    ScreenId.inventory,
    ScreenId.purchases,
    ScreenId.treasury,
    ScreenId.reports,
    ScreenId.settings,
    ScreenId.analytics,
    ScreenId.hr,
    ScreenId.salesInvoices,
    ScreenId.activityLog,
    ScreenId.eInvoice,
    ScreenId.inventoryBonds,
    ScreenId.loyalty,
    ScreenId.stockTransfer,
    ScreenId.scalePlu,
    ScreenId.fieldAudit,
    ScreenId.users,
    ScreenId.rolesAndPermissions,
    ScreenId.auditTrail,
    ScreenId.shiftClose,
    ScreenId.taxReports,
    ScreenId.fiscalYear,
    ScreenId.salesReturns,
    ScreenId.purchaseReturns,
    // شاشةُ حسم القوالب: **كلُّ** نطاقٍ يطبع، وهي الموضعُ الوحيدُ الذي يقول
    // أيُّ قالبٍ يخرج مع أيِّ مستند. وحصرُها في نطاقٍ يترك البقيّةَ بلا
    // جوابٍ لسؤالٍ يقع فيها جميعاً.
    ScreenId.templateResolution,
  ];

  /// Supermarket + Restaurant features (tables, kitchen, delivery) + HR
  static const List<ScreenId> supermarketPlus = [
    ScreenId.dashboard,
    ScreenId.pos,
    ScreenId.offers,
    ScreenId.tables,
    // مصمّمُ القاعة — حيث كانت الطاولاتُ كان مصمّمُها: الخريطةُ لا
    // تُرسَم مرّةً ثمّ تُنسى — تُنقَل الطاولاتُ ويُضاف قسمٌ.
    ScreenId.floorPlanDesigner,
    ScreenId.products,
    ScreenId.categories,
    ScreenId.parties,
    ScreenId.inventory,
    ScreenId.purchases,
    ScreenId.treasury,
    ScreenId.reports,
    ScreenId.settings,
    ScreenId.kitchen,
    ScreenId.analytics,
    ScreenId.hr,
    ScreenId.salesInvoices,
    ScreenId.activityLog,
    ScreenId.eInvoice,
    ScreenId.inventoryBonds,
    ScreenId.loyalty,
    ScreenId.stockTransfer,
    ScreenId.scalePlu,
    ScreenId.fieldAudit,
    ScreenId.users,
    ScreenId.rolesAndPermissions,
    ScreenId.auditTrail,
    ScreenId.shiftClose,
    ScreenId.taxReports,
    ScreenId.fiscalYear,
    ScreenId.salesReturns,
    ScreenId.purchaseReturns,
    // شاشةُ حسم القوالب: **كلُّ** نطاقٍ يطبع، وهي الموضعُ الوحيدُ الذي يقول
    // أيُّ قالبٍ يخرج مع أيِّ مستند. وحصرُها في نطاقٍ يترك البقيّةَ بلا
    // جوابٍ لسؤالٍ يقع فيها جميعاً.
    ScreenId.templateResolution,
  ];

  static const List<ScreenId> commercial = [
    ScreenId.dashboard,
    ScreenId.salesInvoices,
    ScreenId.products,
    ScreenId.categories,
    ScreenId.parties,
    ScreenId.inventory,
    ScreenId.purchases,
    ScreenId.treasury,
    ScreenId.reports,
    ScreenId.settings,
    ScreenId.branches,
    ScreenId.regions,
    ScreenId.analytics,
    ScreenId.hr,
    ScreenId.activityLog,
    ScreenId.eInvoice,
    ScreenId.inventoryBonds,
    ScreenId.stockTransfer,
    ScreenId.scalePlu,
    ScreenId.distribution,
    ScreenId.manufacturing,
    ScreenId.fieldAudit,
    ScreenId.users,
    ScreenId.rolesAndPermissions,
    ScreenId.auditTrail,
    ScreenId.pricingRules,
    ScreenId.shiftClose,
    ScreenId.taxReports,
    ScreenId.salesReturns,
    ScreenId.purchaseReturns,
    // شاشةُ حسم القوالب: **كلُّ** نطاقٍ يطبع، وهي الموضعُ الوحيدُ الذي يقول
    // أيُّ قالبٍ يخرج مع أيِّ مستند. وحصرُها في نطاقٍ يترك البقيّةَ بلا
    // جوابٍ لسؤالٍ يقع فيها جميعاً.
    ScreenId.templateResolution,
  ];

  static const List<ScreenId> unified = [
    ScreenId.dashboard,
    ScreenId.pos,
    ScreenId.offers,
    ScreenId.tables,
    // مصمّمُ القاعة — حيث كانت الطاولاتُ كان مصمّمُها: الخريطةُ لا
    // تُرسَم مرّةً ثمّ تُنسى — تُنقَل الطاولاتُ ويُضاف قسمٌ.
    ScreenId.floorPlanDesigner,
    ScreenId.products,
    ScreenId.categories,
    ScreenId.parties,
    ScreenId.inventory,
    ScreenId.purchases,
    ScreenId.treasury,
    ScreenId.reports,
    ScreenId.settings,
    ScreenId.branches,
    ScreenId.regions,
    ScreenId.kitchen,
    ScreenId.analytics,
    ScreenId.hr,
    ScreenId.salesInvoices,
    ScreenId.activityLog,
    ScreenId.eInvoice,
    ScreenId.inventoryBonds,
    ScreenId.loyalty,
    ScreenId.stockTransfer,
    ScreenId.scalePlu,
    ScreenId.distribution,
    ScreenId.manufacturing,
    ScreenId.operationalExpenses,
    ScreenId.chartOfAccounts,
    ScreenId.fiscalYear,
    ScreenId.stockMovements,
    ScreenId.purchaseOrders,
    ScreenId.accountMapping,
    ScreenId.journalEntries,
    ScreenId.costCenters,
    ScreenId.commercialPapers,
    ScreenId.fixedAssets,
    // ⚠️ **نطاقُهما نطاقُ [ScreenId.fixedAssets] بالضبط** — وهو `unified`
    //    وحدَه. وهما تفصيلان فيها خرجا إلى مدخلَين، فنطاقٌ أوسعُ كان يُظهر
    //    «فئات الأصول» في ملفٍّ لا شاشةَ أصولٍ فيه: مدخلٌ يُنشئ فئةً لا
    //    يستعملها أحد. والحلقةُ ترشّح بالنطاق **قبل** الصلاحية، فالنقصانُ
    //    يُسقطهما حتى عن مدير النظام.
    ScreenId.assetCategories,
    ScreenId.assetLocations,
    // «سند قيد» — نطاقُ أختِها `journalEntries` بالضبط: `unified` وحدَه.
    ScreenId.journalVoucher,
    // سندا القبض والصرف — نطاقُ `commercialPapers` و`treasury` معاً.
    ScreenId.receiptVoucher,
    ScreenId.paymentVoucher,
    // دفترُ الشيكات — نفسُ نطاقِ سندِ الصرف الذي يسحب منه.
    ScreenId.chequeBooks,
    // المشتريات الخارجيّة — نطاقُ `purchaseOrders` بالضبط: `unified`
    // وحدَه. الاستيرادُ مستندٌ مؤسّسيٌّ لا يقع في مطعمٍ ولا سوبرماركت.
    ScreenId.importPurchases,
    ScreenId.generalLedger,
    ScreenId.bankReconciliation,
    ScreenId.salesOrders,
    ScreenId.stockRequisitions,
    ScreenId.branchPerformance,
    ScreenId.helpCenter,
    ScreenId.landedCost,
    ScreenId.cycleCounting,
    ScreenId.reportBuilder,
    ScreenId.salesReturns,
    ScreenId.purchaseReturns,
    // ⚠️ **كانت ساقطةً من `unified` وحدَها** — بلاغُ المالك 2026-08-22:
    // «شاشةُ إغلاق الوردية لا تظهر في القائمة الجانبية».
    //
    // والسجلُّ أثبته بلا تخمين: `allowedIndices=[0…45, 60]` — الرقمُ **٦٠**
    // (`regions`) حاضرٌ و**٥٦** (`shiftClose`) غائب. وهما جارَان في هذه
    // القائمة بالضبط.
    //
    // وحضورُها في الستّ الأخرى (`restaurant` · `supermarket` · `…Pro` ·
    // `…Plus` · `commercial` · `lite`) يُثبت أن الغيابَ سهوٌ لا سياسة —
    // و`unified` **أوسعُ** النطاقات، فلا يُعقل أن تنقصها شاشةٌ تحملها
    // `lite`. وإغلاقُ الورديّة وظيفةُ نقطةِ بيعٍ جوهريّة، لا زينة.
    //
    // ولا يكفي وجودُها في `screenPermissionMap`: الحلقةُ في
    // `userAllowedScreensProvider` تُرشِّح بـ`flavorAllowedScreenIds` **قبل**
    // فحصِ الصلاحية، فما ليس في نطاق الملفّ يسقط حتى مع تجاوزِ مدير النظام.
    ScreenId.shiftClose,
    // و`unified` أوسعُ النطاقات، فما تحمله `restaurant` تحمله هي.
    ScreenId.bookings,
    // ⚠️ في `unified` وحدَها كأخواتها المحاسبيّة (‏دليلُ الحسابات ودفترُ
    //    الأستاذ ومراكزُ التكلفة كلُّها هنا فقط). والملفّاتُ الأصغر لا
    //    تحمل الدورةَ المحاسبيّة أصلاً.
    ScreenId.financialStatements,
    // حاويةُ التبويبات — نطاقُها نطاقُ ما تحويه، وكلُّه هنا وحدَه.
    ScreenId.accountingHub,
    // شاشةُ حسم القوالب: **كلُّ** نطاقٍ يطبع، وهي الموضعُ الوحيدُ الذي يقول
    // أيُّ قالبٍ يخرج مع أيِّ مستند. وحصرُها في نطاقٍ يترك البقيّةَ بلا
    // جوابٍ لسؤالٍ يقع فيها جميعاً.
    ScreenId.templateResolution,
  ];

  /// أصغر نطاق نشحنه: نقطة بيع + مخازن + صناديق + تقارير.
  ///
  /// ١٩ شاشة مقابل ٢٧ لأصغر بروفايل قبله (`supermarket`) — فمفيش قايمة
  /// قريبة كانت تتنسخ.
  ///
  /// قرارات الاستبعاد اللي محتاجة تفسير:
  /// - **المشتريات داخلة** رغم إن اسم النطاق مش ذاكرها: بدونها المخزون
  ///   يزيد بسند إدخال يدوي بس، والمورد ملوش رصيد. محل بيع لازم يشتري.
  ///   أوامر الشراء والتكاليف المحملة برّه — دول تدفّق جملة.
  /// - **العملاء والموردين داخلة** لأن تصميم POS فيه «العميل» و«رصيد
  ///   العميل»؛ بدونها الحقلين ميّتين.
  /// - **المستخدمين داخلة** لأن الدخول للنظام نفسه محتاجها.
  /// - **التحليلات برّه** — `reports` بتغطي احتياج التجزئة.
  /// - كل شاشات المحاسبة الموسّعة (دليل الحسابات، اليومية، الأستاذ، مراكز
  ///   التكلفة، الأصول، الشيكات، السنوات المالية، التقارير الضريبية) برّه:
  ///   المحرك المحاسبي شغّال تحت زي أي بروفايل، بس الواجهة مش معروضة.
  static const List<ScreenId> lite = [
    ScreenId.dashboard,
    // بيع
    ScreenId.pos,
    ScreenId.salesInvoices,
    ScreenId.salesReturns,
    // مشتريات
    ScreenId.purchases,
    ScreenId.purchaseReturns,
    // مخازن
    ScreenId.products,
    ScreenId.categories,
    ScreenId.inventory,
    ScreenId.inventoryBonds,
    ScreenId.stockTransfer,
    ScreenId.fieldAudit,
    // صناديق
    ScreenId.treasury,
    ScreenId.shiftClose,
    // تقارير
    ScreenId.reports,
    ScreenId.activityLog,
    // لازمة للتشغيل
    ScreenId.parties,
    ScreenId.settings,
    ScreenId.users,
    // شاشةُ حسم القوالب: **كلُّ** نطاقٍ يطبع، وهي الموضعُ الوحيدُ الذي يقول
    // أيُّ قالبٍ يخرج مع أيِّ مستند. وحصرُها في نطاقٍ يترك البقيّةَ بلا
    // جوابٍ لسؤالٍ يقع فيها جميعاً.
    ScreenId.templateResolution,
  ];

  /// PicPos-only widening of `lite`: adds the PLU scale-export screen.
  ///
  /// UralCash's `lite` (above) MUST stay byte-unchanged — this is a
  /// brand-gated ADDITION, not a replacement. See `forProfile` below.
  static const List<ScreenId> litePicpos = [...lite, ScreenId.scalePlu];

  /// PicPos-only widening of `restaurant` (و`cafe` لأنه اسمٌ آخرُ له).
  ///
  /// ═══ العطبُ الميدانيُّ الذي أوجبها (بلاغُ المالك 2026-08-22) ═══
  ///
  /// «شاشةُ ميزان التسعير PLU لا تظهر في النظام، وبالتالي مديرُ PLU كذلك».
  ///
  /// والقياسُ على التنصيبة الحيّة: `settings.business_profile = restaurant`،
  /// و**`restaurant` هي التشكيلةُ الوحيدةُ التي لا تحمل [ScreenId.scalePlu]**
  /// من بين السبع (supermarket · supermarketPro · supermarketPlus ·
  /// commercial · unified · litePicpos كلُّها تحملها).
  ///
  /// وكلُّ ما عداها كان سليماً وقد فُحص واحداً واحداً قبل هذا التعديل:
  ///  • صفُّ الصلاحية موجودٌ (`permissions.code='settings_scale'`, id=133)
  ///  • ودورُ «مدير النظام» يملكها فعلاً (‏٢٣١ صلاحيةً من ٢٣٧)
  ///  • ومدخلُ التنقّل موجودٌ (`kAllNavItemDefs`، `index: 21`)
  ///  • وباني الشاشة موصولٌ (`app_main_screen.dart` ⇒ `ScalePluPicposScreen`)
  ///  • ودليلُ الفهارس متطابقٌ (`AppScreen.scalePlu(21)` = `ScreenId(21)`)
  ///
  /// ⇒ فالسببُ تشكيلةُ الشاشات وحدَها، لا صلاحيةٌ ولا توصيلة.
  ///
  /// ومطاعمُ كثيرةٌ تزن (السلطات · المشويّات · الحلويات بالوزن)، فحضورُ
  /// الميزان فيها ليس ترفاً.
  ///
  /// ⚠️ **و`restaurant` أعلاه تبقى بلا حرفٍ لـUralCash** — إضافةٌ محكومةٌ
  /// بالعلامة لا استبدال، وهو نفسُ عقدِ [litePicpos] وقرارِ المالك
  /// 2026-08-22 بألّا تُشارَك تعديلاتُ PicPos مع UralCash.
  static const List<ScreenId> restaurantPicpos = [
    ...restaurant,
    ScreenId.scalePlu,
  ];

  /// `litePicpos` بعد تطبيق «وضع المطاعم».
  ///
  /// طلبُ المالك 2026-08-14: «شاشةُ الطاولات وأوامرُ المطاعم والمطبخ يجب أن
  /// تظهر»، وقرارُه أن تكون **خلف رايةٍ** مطفأةٍ افتراضياً لا مفتوحةً دائماً.
  ///
  /// ── ⚠️ الشاشتان على `tablesEnabled` وحدَها ────────────────────────────
  /// `litePicpos.kitchenEnabled` **صحيحٌ سلفاً** منذ قرار المالك 2026-08-12،
  /// ومعناه هناك «الإضافاتُ والملاحظاتُ تعمل» (`ModifierSelectionDialog`) لا
  /// «شاشةُ KDS معروضة». فتعليقُ [ScreenId.kitchen] على `kitchenEnabled` كان
  /// سيُظهر شاشةَ المطبخ لكلّ تنصيبةِ PicPos اليومَ بلا أن يطلبها أحد.
  /// فالرايةُ الحاكمةُ للشاشتَين واحدة — وهي «وضعُ المطاعم» نفسُه.
  ///
  /// ── ولماذا ثابتٌ مُسمّى يُنادى مباشرة ────────────────────────────────
  /// `Brand.isPicPos` ثابتُ ترجمةٍ افتراضُه `uralcash`، فالبوابةُ كلُّها
  /// تشتغل على فرع UralCash ولن تقيس فرعَ PicPos أصلاً. نفسُ علاج
  /// [litePicpos] و`FeaturePolicy.litePicpos`.
  static List<ScreenId> litePicposWith(FeaturePolicy features) {
    if (!features.tablesEnabled) return litePicpos;
    return [
      ...litePicpos,
      ScreenId.tables,
      ScreenId.floorPlanDesigner,
      ScreenId.kitchen,
    ];
  }

  /// الشاشاتُ التي أسقطها المالكُ من PicPos 2026-09-12.
  ///
  /// ⚠️ ولا يكفي إخفاءُ مدخلِ القائمة (`kPicPosRetiredNavIndexes`): الشاشةُ
  /// تُبلَغ بالفهرس المباشر من كلّ اختصارٍ ومن `onNavigate`، والنطاقُ هو
  /// البوّابةُ التي تسبق الصلاحيةَ نفسَها. فالموضعان معاً أو لا شيء.
  /// ⚠️ **و«التكاليف المحمّلة» خرجت من هنا 2026-09-20 (المرحلة ٨)** بقرار
  /// المالك: «تُفعَّل وتعيش داخلها وحدَها — لا مدخلَ جانبيَّ لها». فهي
  /// الحالةُ الوحيدةُ التي **يُفترَق فيها الموضعان عمداً**:
  ///   • خرجت من هنا ⇒ يبلغها `ScreenId.importPurchases` بالفهرس.
  ///   • وبقي فهرسُها `41` في [kPicPosRetiredNavIndexes] ⇒ **لا مدخلَ
  ///     جانبيَّ لها**.
  ///
  /// 🔴 ولا تُعَدْ إلى هنا «توحيداً»: النطاقُ يسبق الصلاحية، فإعادتُها
  ///    تجعل زرَّ «التكاليف المحمّلة» داخلَ شاشة الاستيراد يفتح لا شيء.
  static const picposRetired = <ScreenId>{
    ScreenId.stockRequisitions, // طلبات الصرف
    ScreenId.cycleCounting, // الجرد الدوري
  };

  /// [src] بعد إسقاط [picposRetired].
  ///
  /// ⚠️ **المقارنةُ بالفهرس لا بقيمة `ScreenId`**: `cycleCounting` و
  /// `fieldAudit` قيمتان مختلفتان لفهرسٍ **واحدٍ** (42)، فـ`Set.contains`
  /// على القيمة يُبقي الشاشةَ حيّةً باسمها الآخر — وهي مدرجةٌ في خمسة
  /// نطاقاتٍ باسم `fieldAudit` وفي `unified` وحدَها باسم `cycleCounting`.
  static List<ScreenId> withoutPicposRetired(List<ScreenId> src) {
    final retired = {for (final s in picposRetired) s.navigationIndex};
    return [
      for (final s in src)
        if (!retired.contains(s.navigationIndex)) s,
    ];
  }

  /// [features] اختياريٌّ عن قصد: تركُه `null` يعطي **بالضبط** ما كان
  /// يعطيه التوقيعُ القديم، فلا يتغيّر سلوكُ أيّ منادٍ لم يُحدَّث.
  static List<ScreenId> forProfile(
    BusinessProfile profile, {
    FeaturePolicy? features,
  }) {
    final base = _baseForProfile(profile, features: features);
    return Brand.isPicPos ? withoutPicposRetired(base) : base;
  }

  static List<ScreenId> _baseForProfile(
    BusinessProfile profile, {
    FeaturePolicy? features,
  }) {
    switch (profile) {
      // المطعمُ والمقهى: PicPos يضيف شاشةَ الميزان — راجع [restaurantPicpos]
      // للقياس الذي أوجبها. و`cafe` اسمٌ آخرُ لـ`restaurant` فيتبعها.
      case BusinessProfile.restaurant:
      case BusinessProfile.cafe:
        return Brand.isPicPos ? restaurantPicpos : restaurant;
      case BusinessProfile.supermarket:
        return supermarket;
      case BusinessProfile.supermarketPro:
        return supermarketPro;
      case BusinessProfile.supermarketPlus:
        return supermarketPlus;
      case BusinessProfile.commercial:
        return commercial;
      case BusinessProfile.lite:
        // UralCash-lite stays 19 verbatim; PicPos-lite adds the scale screen،
        // ثم «وضعَ المطاعم» إن أُشعلت رايتُه. والفرعُ محصورٌ بـPicPos فيبقى
        // `lite` بلا حرف — وهو عقدٌ مكتوبٌ فوق [litePicpos].
        if (!Brand.isPicPos) return lite;
        return features == null ? litePicpos : litePicposWith(features);
      case BusinessProfile.unified:
        return unified;
    }
  }
}

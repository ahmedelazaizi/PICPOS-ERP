part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TEMPLATE BINDINGS DAO - رابطاتُ القوالب
// ═══════════════════════════════════════════════════════════════════════════
//
// ثلاثةُ أعطابٍ يمنعها هذا الملفّ، وكلُّها من «ما لا يُنفَّذ كزينة» في عقد
// الأزرار:
//
// ١ · **الإلغاءُ الصامت.** تفعيلُ قالبٍ يُلغي المتعارضَ معه. وإلغاؤه بلا
//     إخبارٍ يجعل المستخدمَ يظنّ قالبين مفعّلَين، فيطبع من أحدهما ويجد
//     الآخر. لذلك [activateBinding] **تُرجع** ما ألغته.
//
// ٢ · **حذفُ قالبٍ مربوط.** بدونه تُطبع مستنداتٌ بلا قالبٍ بعد أسابيعَ بلا
//     سببٍ ظاهر، والرابطةُ تشير إلى صفٍّ لم يعد موجوداً.
//
// ٣ · **ربطُ قالبٍ أعرضَ من طابعته.** يُقصّ المطبوعُ صامتاً اليوم، وعمودُ
//     الإجمالي أوّلُ ما يضيع.

/// رفضُ حذفِ قالبٍ تشير إليه رابطةٌ واحدةٌ على الأقلّ.
class TemplateBoundException implements Exception {
  final int templateId;
  final int bindingCount;

  const TemplateBoundException(this.templateId, this.bindingCount);

  @override
  String toString() =>
      'لا يمكن حذفُ القالب #$templateId: مربوطٌ بـ$bindingCount مستند. '
      'فُكَّ الرابطةَ أوّلاً.';
}

/// رفضُ ربطِ قالبٍ لا يسعه عرضُ الطابعة.
class PaperMismatchException implements Exception {
  final String reason;
  const PaperMismatchException(this.reason);

  @override
  String toString() => reason;
}

extension TemplateBindingDao on AppDatabase {
  /// كلُّ الرابطات — تقرؤها شاشةُ الحسم.
  Future<List<TemplateBinding>> getAllBindings() =>
      select(templateBindings).get();

  /// رابطاتُ قالبٍ بعينه — يقرؤها زرُّ الحذف قبل أن يرفض.
  Future<List<TemplateBinding>> getBindingsForTemplate(int templateId) =>
      (select(templateBindings)
            ..where((b) => b.templateId.equals(templateId)))
          .get();

  /// يُفعِّل قالباً لمفتاحٍ رباعيّ، ويُرجع **الرابطاتِ التي أُلغيت**.
  ///
  /// [printerWidthMm] حين يُمرَّر يُفحَص ضدّ عرض القالب. تجاوزُه يعني «لا
  /// أعرف عرضَ هذه الطابعة» — وهو ليس عدمَ توافق.
  ///
  /// يرمي [PaperMismatchException] إن كان القالبُ أعرضَ، **قبل** أيِّ كتابة.
  Future<List<TemplateBinding>> activateBinding({
    required String documentType,
    required int templateId,
    int? branchId,
    int? printerId,
    String? locale,
    int copies = 1,
    bool directPrint = false,
    int priority = 0,
    double? printerWidthMm,
  }) async {
    // الفحصُ قبل المعاملة — فالرفضُ لا يترك رابطةً نصفَ مكتوبة.
    if (printerWidthMm != null) {
      final tpl = await getTemplateById(templateId);
      if (tpl != null) {
        final verdict = checkPaperFit(
          templateWidthMm: tpl.paperWidth,
          printerWidthMm: printerWidthMm,
        );
        if (verdict.isRejected) throw PaperMismatchException(verdict.reason);
      }
    }

    return transaction(() async {
      // المتعارضُ: نفسُ المفتاح الرباعيِّ بالضبط. و`null` تعني «أيّاً كان»
      // فلا تُطابَق بـ`equals` — لذلك يُفصَّل الشرطُ لكلِّ حقلٍ على حدة.
      final conflicts = await (select(templateBindings)
            ..where((b) {
              var w = b.documentType.equals(documentType);
              w = w &
                  (branchId == null
                      ? b.branchId.isNull()
                      : b.branchId.equals(branchId));
              w = w &
                  (printerId == null
                      ? b.printerId.isNull()
                      : b.printerId.equals(printerId));
              w = w &
                  (locale == null
                      ? b.locale.isNull()
                      : b.locale.equals(locale));
              return w;
            }))
          .get();

      final cancelled = conflicts
          .where((b) => b.templateId != templateId)
          .toList(growable: false);

      for (final c in conflicts) {
        await (delete(templateBindings)..where((b) => b.id.equals(c.id))).go();
      }

      await into(templateBindings).insert(
        TemplateBindingsCompanion.insert(
          documentType: documentType,
          templateId: templateId,
          branchId: Value(branchId),
          printerId: Value(printerId),
          locale: Value(locale),
          copies: Value(copies),
          directPrint: Value(directPrint),
          priority: Value(priority),
        ),
      );

      return cancelled;
    });
  }

  /// يفكّ رابطةَ مفتاحٍ ويُرجع عددَ الصفوف المحذوفة (صفرٌ إن لم تكن موجودة).
  Future<int> deactivateBinding({
    required String documentType,
    int? branchId,
    int? printerId,
    String? locale,
  }) =>
      (delete(templateBindings)
            ..where((b) {
              var w = b.documentType.equals(documentType);
              w = w &
                  (branchId == null
                      ? b.branchId.isNull()
                      : b.branchId.equals(branchId));
              w = w &
                  (printerId == null
                      ? b.printerId.isNull()
                      : b.printerId.equals(printerId));
              w = w &
                  (locale == null
                      ? b.locale.isNull()
                      : b.locale.equals(locale));
              return w;
            }))
          .go();

  /// يحسم القالبَ بالسلسلة السداسيّة.
  ///
  /// [paperType] لازمٌ للمستوى الخامس وحدَه (‏`isDefault` القائم يُفهرَس
  /// بالنوع + الفئة). وغيابُه يعني تخطّي ذلك المستوى لا فشلَ الحسم.
  Future<TemplateResolution> resolveTemplateFor({
    required String documentType,
    required String category,
    int? branchId,
    int? printerId,
    String? locale,
    String? paperType,
  }) async {
    final rows = await getAllBindings();

    final bindings = [
      for (final r in rows)
        BindingRule(
          templateId: r.templateId,
          documentType: r.documentType,
          branchId: r.branchId,
          printerId: r.printerId,
          locale: r.locale,
          copies: r.copies,
          directPrint: r.directPrint,
          priority: r.priority,
        ),
    ];

    int? categoryDefault;
    if (paperType != null) {
      // ⚠️ `getDefaultTemplateByCategory` تستعمل `getSingleOrNull`، فترمي
      //    «Too many elements» لو حملت قاعدةٌ افتراضيَّين لنفس النوع والفئة.
      //    والثابتُ يحفظه `setDefaultTemplate`، لكنّ الكتابةَ المباشرةَ على
      //    العمود تكسره — ومقيسٌ أنّها تقع.
      //
      //    وحسمُ القالب في مسار الطباعة: انهيارُه يعني فاتورةً لا تُطبع
      //    أصلاً. فالثابتُ المكسورُ يُسقِط **مستوىً واحداً** من السلسلة ولا
      //    يُسقِط الطباعة، ويبقى المدمجُ آخرَ ملاذ.
      try {
        final tpl = await getDefaultTemplateByCategory(paperType, category);
        categoryDefault = tpl?.id;
      } catch (_) {
        categoryDefault = null;
      }
    }

    return TemplateResolver.resolve(
      documentType: documentType,
      category: category,
      bindings: bindings,
      branchId: branchId,
      printerId: printerId,
      locale: locale,
      categoryDefaultTemplateId: categoryDefault,
    );
  }

  /// يحذف قالباً **ما لم يكن مربوطاً**.
  ///
  /// يرمي [TemplateBoundException] بعدد الرابطات، فيُعرَض للمستخدم سببُ
  /// الرفض لا رفضٌ مجرَّد.
  Future<void> deleteTemplateGuarded(int templateId) async {
    final bound = await getBindingsForTemplate(templateId);
    if (bound.isNotEmpty) {
      throw TemplateBoundException(templateId, bound.length);
    }
    await deleteTemplate(templateId);
  }
}

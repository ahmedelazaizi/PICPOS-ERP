// =======================================================================
// INVOICE TEMPLATE SEEDER DAO
// Extracted from invoice_template_dao.dart - Sprint 12 God File Splitting
// =======================================================================

part of '../database.dart';

/// Extension for Invoice Template seeding operations
extension InvoiceTemplateSeederDao on AppDatabase {
  /// #13: Seed default templates if none exist
  /// Creates Thermal, A4, Kitchen, Sales Return, Purchase, and Purchase Return templates
  Future<void> seedDefaultTemplates() async {
    // Migrate old-format elements first
    await _migrateOldFormatElements();
    // تصحيحُ فئات القوالب القديمة قبل فحص الموجود — وإلا رأى الفحصُ حالاً
    // بائتةً فبذر نظيراً لقالبٍ قائم.
    await repairTemplateCategories();
    final existing = await getAllTemplates();
    final existingTypes = existing.map((t) => t.type).toSet();
    // ⚠️ الحارسُ بالفئة لا بالنوع لما ينفرد بفئته: قالبا A4 والمشتريات
    // نوعُهما `a4` كلاهما (‏المصمّمُ لا يعرف نوعاً اسمُه `purchase`)، فحارسٌ
    // بالنوع كان يمنع بذرَ الثاني أو يزدوج به.
    final existingCategories =
        existing.map((t) => t.templateCategory).toSet();

    // Create Thermal receipt template (if not exists)
    if (!existingTypes.contains('thermal')) {
      final thermalId = await into(invoiceTemplates).insert(
        InvoiceTemplatesCompanion.insert(
          name: 'إيصال حراري',
          type: const Value('thermal'),
          paperSize: const Value('80mm'),
          paperWidth: const Value(80),
          isDefault: const Value(true),
        ),
      );
      await _seedDefaultElements(thermalId, 'thermal');
    }

    // Create A4 invoice template (if not exists)
    // الفئةُ `invoice` صراحةً: `invoice_generator.dart:164` يسأل `('a4',
    // 'invoice')`، وبلا فئةٍ كانت تأخذ الافتراضَ `'receipt'` فلا يجدها —
    // وتُطبع كلُّ فاتورة A4 بالمولّد المكتوب في الكود، وتصميمُ المالك لا
    // يصل الورقةَ أبداً بلا استثناءٍ ولا سطرِ سجلّ.
    if (!existingCategories.contains('invoice')) {
      final a4Id = await into(invoiceTemplates).insert(
        InvoiceTemplatesCompanion.insert(
          name: 'فاتورة A4',
          type: const Value('a4'),
          templateCategory: const Value('invoice'),
          paperSize: const Value('A4'),
          paperWidth: const Value(210),
          paperHeight: const Value(297),
          isDefault: const Value(true),
        ),
      );
      await _seedDefaultElements(a4Id, 'a4');
    }

    // Create Kitchen ticket template (if not exists)
    // والفئةُ `kitchen` كذلك: محرّرُ الأقسام يتفرّع عليها لا على النوع
    // (`invoice_section_editor.dart:252`)، فكان يفتح تذكرةَ المطبخ بأقسام
    // الإيصال.
    if (!existingTypes.contains('kitchen')) {
      final kitchenId = await into(invoiceTemplates).insert(
        InvoiceTemplatesCompanion.insert(
          name: 'طلب المطبخ',
          type: const Value('kitchen'),
          templateCategory: const Value('kitchen'),
          paperSize: const Value('80mm'),
          paperWidth: const Value(80),
          isDefault: const Value(true),
        ),
      );
      await _seedKitchenElements(kitchenId);
    }

    // Create Sales Return template (if not exists)
    // ورقُه حراريٌّ ٨٠mm كما يطبعه `ThermalReceiptGenerator` اليوم — فتوصيلُ
    // القالب لا يقلب مقاسَ الإيصال.
    if (!existingCategories.contains('sales_return')) {
      final salesReturnId = await into(invoiceTemplates).insert(
        InvoiceTemplatesCompanion.insert(
          name: 'إيصال مرتجع مبيعات',
          type: const Value('thermal'),
          templateCategory: const Value('sales_return'),
          paperSize: const Value('80mm'),
          paperWidth: const Value(80),
          isDefault: const Value(true),
        ),
      );
      await _seedSalesReturnElements(salesReturnId);
    }

    // Create Purchase Invoice template (if not exists)
    // كان خاطئاً في المحورَين: `type: 'purchase'` نوعٌ لا يعرضه المصمّم أصلاً
    // (ثلاثةٌ لا غير: thermal · a4 · kitchen)، والفئةُ افتراضيةٌ `'receipt'`.
    // و`invoice_generator.dart:239` يسأل `('a4','purchase')` فلا يجد طرفاً.
    if (!existingCategories.contains('purchase')) {
      final purchaseId = await into(invoiceTemplates).insert(
        InvoiceTemplatesCompanion.insert(
          name: 'فاتورة مشتريات',
          type: const Value('a4'),
          templateCategory: const Value('purchase'),
          paperSize: const Value('A4'),
          paperWidth: const Value(210),
          paperHeight: const Value(297),
          isDefault: const Value(true),
        ),
      );
      await _seedPurchaseElements(purchaseId);
    }

    // Create Purchase Return template (if not exists)
    // ورقُه A4 لا ٨٠mm: `ReportPdfGenerator` يطبعه A4 اليوم، وتوصيلُ قالبٍ
    // حراريٍّ كان سيقلب مرتجعَ المشتريات إلى شريطٍ ضيّقٍ بلا أن يطلبه أحد.
    if (!existingCategories.contains('purchase_return')) {
      final purchaseReturnId = await into(invoiceTemplates).insert(
        InvoiceTemplatesCompanion.insert(
          name: 'إيصال مرتجع مشتريات',
          type: const Value('a4'),
          templateCategory: const Value('purchase_return'),
          paperSize: const Value('A4'),
          paperWidth: const Value(210),
          paperHeight: const Value(297),
          isDefault: const Value(true),
        ),
      );
      await _seedPurchaseReturnElements(purchaseReturnId);
    }

    // Create Barcode label templates (if not exists)
    final hasBarcode = existing.any((t) => t.templateCategory == 'barcode');
    if (!hasBarcode) {
      await _seedBarcodeTemplates();
    }

    // Create Shift Closing report template (if not exists)
    if (!existingTypes.contains('shift_closing')) {
      final shiftClosingId = await into(invoiceTemplates).insert(
        InvoiceTemplatesCompanion.insert(
          name: 'تقرير إغلاق الوردية',
          type: const Value('shift_closing'),
          templateCategory: const Value('shift_closing'),
          paperSize: const Value('80mm'),
          paperWidth: const Value(80),
          isDefault: const Value(true),
        ),
      );
      await _seedShiftClosingElements(shiftClosingId);
    }

    // Seed elements for existing templates that have no elements
    await _seedMissingElements();
  }

  /// Migrate old-format elements in DB to new format
  /// Old: elementType='company_name' → New: elementType='variable', content='company_name'
  Future<void> _migrateOldFormatElements() async {
    const validTypes = {'variable', 'text', 'line', 'image', 'rectangle'};
    // Map old elementType → {newType, content}
    const migrations = <String, Map<String, String>>{
      'company_name': {'type': 'variable', 'content': 'company_name'},
      'company_address': {'type': 'variable', 'content': 'company_address'},
      'company_phone': {'type': 'variable', 'content': 'company_phone'},
      'company_tax_id': {'type': 'variable', 'content': 'company_tax_number'},
      'company_tax_number': {'type': 'variable', 'content': 'company_tax_number'},
      'invoice_number': {'type': 'variable', 'content': 'invoice_number'},
      'invoice_title': {'type': 'text', 'content': 'فاتورة مبيعات'},
      'invoice_type_label': {'type': 'variable', 'content': 'invoice_type_label'},
      'order_number': {'type': 'variable', 'content': 'order_number'},
      'date': {'type': 'variable', 'content': 'date'},
      'time': {'type': 'variable', 'content': 'time'},
      'customer': {'type': 'variable', 'content': 'customer_name'},
      'customer_name': {'type': 'variable', 'content': 'customer_name'},
      'customer_phone': {'type': 'variable', 'content': 'customer_phone'},
      'customer_address': {'type': 'variable', 'content': 'customer_address'},
      'adhoc_customer_name': {'type': 'variable', 'content': 'adhoc_customer_name'},
      'adhoc_customer_phone': {'type': 'variable', 'content': 'adhoc_customer_phone'},
      'supplier_name': {'type': 'variable', 'content': 'supplier_name'},
      'cashier_name': {'type': 'variable', 'content': 'cashier_name'},
      'payment_method': {'type': 'variable', 'content': 'payment_method'},
      'sale_type': {'type': 'variable', 'content': 'sale_type'},
      'subtotal': {'type': 'variable', 'content': 'subtotal'},
      'discount': {'type': 'variable', 'content': 'discount'},
      'tax': {'type': 'variable', 'content': 'tax_amount'},
      'tax_amount': {'type': 'variable', 'content': 'tax_amount'},
      'total': {'type': 'variable', 'content': 'total_amount'},
      'total_amount': {'type': 'variable', 'content': 'total_amount'},
      'grand_total': {'type': 'variable', 'content': 'total_amount'},
      'paid': {'type': 'variable', 'content': 'paid'},
      'paid_amount': {'type': 'variable', 'content': 'paid'},
      'remaining': {'type': 'variable', 'content': 'remaining'},
      'change': {'type': 'variable', 'content': 'remaining'},
      'cash_amount': {'type': 'variable', 'content': 'cash_amount'},
      'bank_amount': {'type': 'variable', 'content': 'bank_amount'},
      'click_amount': {'type': 'variable', 'content': 'click_amount'},
      'delivery_fee': {'type': 'variable', 'content': 'delivery_fee'},
      'delivery_type': {'type': 'variable', 'content': 'delivery_type'},
      'delivery_address': {'type': 'variable', 'content': 'delivery_address'},
      'courier_name': {'type': 'variable', 'content': 'courier_name'},
      'notes': {'type': 'variable', 'content': 'notes'},
      'table_number': {'type': 'variable', 'content': 'table_number'},
      'waiter_name': {'type': 'variable', 'content': 'waiter_name'},
      'kitchen_notes': {'type': 'variable', 'content': 'kitchen_notes'},
      'warehouse_name': {'type': 'variable', 'content': 'warehouse_name'},
      'branch_name': {'type': 'variable', 'content': 'branch_name'},
      'tax_registration': {'type': 'variable', 'content': 'tax_registration'},
      'qr_code': {'type': 'variable', 'content': 'qr_code'},
      'footer': {'type': 'text', 'content': 'شكراً لتعاملكم معنا'},
      'footer_text': {'type': 'text', 'content': 'شكراً لتعاملكم معنا'},
      'divider': {'type': 'line', 'content': ''},
      'spacer': {'type': 'line', 'content': ''},
      'logo': {'type': 'image', 'content': 'logo'},
    };

    final allElements = await select(invoiceTemplateElements).get();
    for (final el in allElements) {
      if (validTypes.contains(el.elementType)) continue;
      // جدولُ الأصناف كان يُحذف هنا بحجّة أن المُصيِّرَ يُقحمه تلقائياً.
      // وبعد الخيار (ب) صار موضعُه من القالب، فيُحوَّل إلى الصيغة الجديدة
      // ويبقى حيث وضعه المصمّم بدل أن يُمحى ثم يعود استدلالاً في غير مكانه.
      if (el.elementType == 'items_table') {
        await (update(invoiceTemplateElements)..where((e) => e.id.equals(el.id)))
            .write(const InvoiceTemplateElementsCompanion(
          elementType: Value('variable'),
          content: Value('items_table'),
        ));
        continue;
      }
      final migration = migrations[el.elementType];
      if (migration != null) {
        await (update(invoiceTemplateElements)..where((e) => e.id.equals(el.id))).write(
          InvoiceTemplateElementsCompanion(
            elementType: Value(migration['type']!),
            content: Value(el.content ?? migration['content']),
          ),
        );
      }
    }

    // Phase 2: Migrate old content keys within valid-typed elements
    // e.g. content='total' → 'total_amount', content='tax' → 'tax_amount'
    const contentMigrations = <String, String>{
      'total': 'total_amount',
      'grand_total': 'total_amount',
      'tax': 'tax_amount',
    };
    final validElements = await select(invoiceTemplateElements).get();
    for (final el in validElements) {
      if (el.content != null && contentMigrations.containsKey(el.content!)) {
        await (update(invoiceTemplateElements)..where((e) => e.id.equals(el.id))).write(
          InvoiceTemplateElementsCompanion(
            content: Value(contentMigrations[el.content!]!),
          ),
        );
      }
    }
  }

  /// قنواتُ تسوية الوردية المتوقَّعة في قالب `shift_closing`، كلٌّ بعنوانها.
  ///
  /// نفسُ المفاتيح التي يحلّها `TemplatedInvoiceService.resolveShiftValue`.
  /// ⚠️ الاسمُ داخل `labelAr` لا في عنصرِ عنوانٍ منفصل.
  ///
  /// المُصيِّر يرتّب بـ`_contentSectionPriority` أوّلاً، وكلُّ مفاتيح
  /// `shift_*` تقع في «٨ — غيرُ معروف، بعد الإجماليات» فترتيبُها بـ
  /// `sortOrder` وحدَه. فعنصرُ عنوانٍ مستقلٌّ يفارق صفوفَه بأدنى اختلافٍ في
  /// الترتيب، ويسقط كذلك في إزالة التكرار لو تكرّر نصُّه. والسطرُ الذي
  /// يسمّي قناتَه بنفسه لا يُفارَق ولا يُلبَس.
  ///
  /// بلاغُ المالك 2026-08-12: «المسمّيات كما تظهر في التقرير يجب أن تظهر في
  /// الطباعة» — الشاشةُ تعرض عموداً باسم القناة، والورقةُ كانت تعرض «رصيد
  /// النظام» ثلاثَ مرّاتٍ بلا اسمٍ يميّزها.
  /// عناوينُ كتل القنوات — **مصدرٌ واحدٌ** للبذرة ولضبط الترتيب.
  ///
  /// ⚠️ كانا نصَّين منفصلَين فافترقا: البذرةُ تكتب «بطاقة / تحويل» وضبطُ
  /// الترتيب يبحث عن «البطاقة»، فلم يعرفه عنوانَ قناةٍ فتركه خارج الكتلة —
  /// وطار فوقها على الورق (رُصد 2026-08-12). نصٌّ مكرَّرٌ في موضعَين يفترق.
  static const _shiftChannelHeadings = <String, String>{
    'cash': 'النقد (كاش)',
    'card': 'بطاقة / تحويل',
    'click': 'كليك',
  };

  static const _shiftChannelRows = <(String, String)>[
    ('shift_system_cash', 'النقد — رصيد النظام'),
    ('shift_actual_cash', 'النقد — المبلغ الفعلي'),
    ('shift_cash_variance', 'النقد — الفارق'),
    ('shift_system_card', 'البطاقة — رصيد النظام'),
    ('shift_actual_card', 'البطاقة — المبلغ الفعلي'),
    ('shift_card_variance', 'البطاقة — الفارق'),
    ('shift_system_click', 'كليك — رصيد النظام'),
    ('shift_actual_click', 'كليك — المبلغ الفعلي'),
    ('shift_click_variance', 'كليك — الفارق'),
  ];

  /// يُلحق بقوالب `shift_closing` القائمة أيَّ قناةِ تسويةٍ تنقصها.
  ///
  /// ── لماذا إصلاحٌ لا بذرة ────────────────────────────────────────────────
  /// [seedDefaultTemplates] تزرع القالبَ الكامل، لكن بشرط
  /// `!existingTypes.contains('shift_closing')`. فقاعدةٌ أُنشئت قبل §٥-٢
  /// فيها قالبٌ بالاسم نفسِه ولا يعرف «كليك» — والبذرةُ تتخطّاه إلى الأبد،
  /// و[_seedMissingElements] لا تنقذه لأنها تعالج القوالبَ **الفارغة** وحدَها.
  ///
  /// والعطبُ صامتٌ وخبيث: المطبوعُ يعرض قناتَين ويطبع `shift_total_system`
  /// الذي **يجمع الثلاث**. فالقارئُ يجمع ما يراه فلا يطابق الإجماليَّ،
  /// فيتّهم الحسابَ وهو سليم (‏رُصد ميدانياً 2026-08-12: ١٠ + ٣٠ معروضة
  /// وإجمالي ٥٥، وكليك ١٥ غائبة).
  ///
  /// **إلحاقٌ لا إعادةُ بناء** (قرارُ المالك 2026-08-12): من صمّم قالبَه لا
  /// يُهدم عليه. تُضاف القناةُ الناقصةُ تحت آخر عنصرٍ بعنوانها فوق صفوفها.
  ///
  /// متعادلة: ما وُجد يُترك، فالتشغيلُ كلَّ إقلاعٍ آمن.
  /// الصيغةُ القديمةُ في خرائط البذر → الصيغةُ التي يرسمها المُصيِّر.
  ///
  /// ثلاثُ بذورٍ (المشتريات والمرتجعان) تكتب **اسمَ الحقل في خانة النوع**:
  /// `elementType: 'company_name'` و`'total'` و`'items_table'`. ومرشّحُ
  /// المُصيِّر لا يعرف إلا `{variable, text, line, image, rectangle}`، فيرمي
  /// ما عداها **بلا رسالةٍ ولا سجلّ** — فتخرج الورقةُ شبهَ فارغة، ولا يبقى
  /// منها إلا عناصرُ `text`.
  ///
  /// وكان نائماً لأن تلك القوالبَ لم تكن تُعثَر أصلاً؛ استيقظ يومَ صارت
  /// تُعثَر. والتطبيعُ هنا عند البذر لا في هجرةٍ تالية: هجرةُ
  /// `_migrateOldFormatElements` تعمل **قبل** البذر في نفس الاستدعاء،
  /// فما يُبذر الآن يبقى قديماً حتى زيارةِ المصمّم التالية.
  ///
  /// ⚠️ ولا تمرّ بها عناصرُ الباركود (`product_name` · `barcode_image` …) —
  /// تُدرَج مباشرةً خارج هذه الحلقات، ومُصيِّرُها يفرز على النوع الخام.
  static (String, String?) _normalizeSeedElement(String type, String? content) {
    const renderable = {'variable', 'text', 'line', 'image', 'rectangle'};
    if (renderable.contains(type)) return (type, content);
    if (type == 'divider' || type == 'spacer') return ('line', content);
    if (type == 'logo') return ('image', content ?? 'logo');
    // ما عدا ذلك اسمُ متغيّر. والتسمياتُ الموحَّدةُ نفسُها التي تعتمدها
    // `_migrateOldFormatElements` كي لا يفترق المسارَان.
    const renames = <String, String>{
      'total': 'total_amount',
      'grand_total': 'total_amount',
      'tax': 'tax_amount',
    };
    return ('variable', renames[type] ?? type);
  }

  /// تصحيحُ فئةِ القوالب القديمة كي يجدها منادي الطباعة.
  ///
  /// `getDefaultTemplateByCategory` يشترط تطابقَ `type` **و**`templateCategory`
  /// معاً. والبذورُ القديمةُ لم تكتب فئةً قطّ فأخذت الافتراضَ `'receipt'`،
  /// بينما `invoice_generator` يسأل `'invoice'` للمبيعات و`'purchase'`
  /// للمشتريات — فلا يجد شيئاً، ويسقط صامتاً إلى المولّد المكتوب في الكود.
  /// فتصميمُ المالك لا يصل الورقةَ أبداً، بلا استثناءٍ ولا سطرِ سجلّ.
  ///
  /// ولا تدهس اختياراً: ما فئتُه غيرُ الافتراضيّ فصاحبُه اختارها.
  ///
  /// متعادلة: ما صحّ يُترك، فالتشغيلُ كلَّ إقلاعٍ آمن.
  Future<int> repairTemplateCategories() async {
    // النوعُ المبذور → فئتُه الصحيحة. والمصمّمُ لا يعرض إلا ثلاثةَ أنواع
    // (`invoice_designer_ui.dart:338-342`)، فما عداها نوعٌ بائتٌ يُصحَّح معه.
    const byType = <String, (String type, String category)>{
      'a4': ('a4', 'invoice'),
      'purchase': ('a4', 'purchase'),
      'kitchen': ('kitchen', 'kitchen'),
      'sales_return': ('thermal', 'sales_return'),
      'purchase_return': ('a4', 'purchase_return'),
    };

    var changed = 0;
    for (final t in await getAllTemplates()) {
      // فئةٌ غيرُ الافتراضيّ = اختيارٌ صريحٌ من المالك. لا تُدهَس.
      if (t.templateCategory != 'receipt') continue;
      final fix = byType[t.type];
      if (fix == null) continue;
      if (t.type == fix.$1 && t.templateCategory == fix.$2) continue;

      // مرتجعُ المشتريات يُطبع A4 اليومَ عبر `ReportPdfGenerator`، وقالبُه
      // المبذورُ ٨٠mm — وهو قالبٌ **لم يبلغه مسارُ طباعةٍ قطّ** فلا تصميمَ
      // فيه يُحفَظ. فيُسوّى ورقُه كي لا ينقلب المطبوعُ يومَ توصيله.
      final isPurchaseReturn = fix.$2 == 'purchase_return';
      await (update(invoiceTemplates)..where((x) => x.id.equals(t.id)))
          .write(InvoiceTemplatesCompanion(
        type: Value(fix.$1),
        templateCategory: Value(fix.$2),
        paperSize: isPurchaseReturn ? const Value('A4') : const Value.absent(),
        paperWidth: isPurchaseReturn ? const Value(210) : const Value.absent(),
        paperHeight: isPurchaseReturn ? const Value(297) : const Value.absent(),
      ));
      changed++;
    }
    return changed;
  }

  /// إلحاقُ عنصرِ «جدول الأصناف» بالقوالب التي تخلو منه.
  ///
  /// الخيارُ (ب) 2026-08-12: المطبوعُ يحترم تخطيطَ القالب. وجدولُ الأصناف
  /// كان الوحيدَ الذي لا موضعَ له فيه — يُقحمه المُصيِّرُ استدلالاً قبل أوّل
  /// عنصرِ إجمالياتٍ يصادفه. فالمالكُ يحرّكه في المصمّم ولا شيءَ يُحفَظ.
  ///
  /// ولا ينقلب مطبوعٌ قائم: العنصرُ يُولد **حيث كان الاستدلالُ يُقحمه
  /// بالضبط**، فالورقةُ لا تتغيّر بحرفٍ يومَ الترقية، ثم يصير الموضعُ
  /// مملوكاً للقالب.
  ///
  /// متعادلة: قالبٌ فيه جدولٌ يُترك، فالتشغيلُ كلَّ إقلاعٍ آمن.
  Future<int> backfillItemsTableElements() async {
    var changed = 0;
    final templates = await getAllTemplates();

    for (final template in templates) {
      // ما لا يُطبع أصنافاً لا جدولَ له: تقريرُ الوردية يمرّ بقائمةٍ فارغة،
      // وقوالبُ الباركود والملصقات مسارٌ آخرُ بالكامل.
      if (template.type == 'shift_closing') continue;
      if (const {'shift_closing', 'barcode', 'label'}
          .contains(template.templateCategory)) continue;

      final elements = await getTemplateElements(template.id);
      // قالبٌ فارغٌ تماماً شأنُ [_seedMissingElements] لا شأنُ الإلحاق.
      if (elements.isEmpty) continue;
      // متعادلة — ولوحةُ العناصر تُنشئه `variable`، والصيغةُ القديمة نوعاً.
      if (elements.any((e) =>
          e.content == 'items_table' || e.elementType == 'items_table')) {
        continue;
      }

      // موضعُ الإلحاق = موضعُ الاستدلال القديم بعينه: قبل أوّل عنصرٍ **مرئيّ**
      // من الإجماليات. فمن رقّى نسختَه لا يرى في ورقته فرقاً.
      final pivot = elements
          .where((e) =>
              e.isVisible &&
              const {'variable', 'text', 'line', 'image', 'rectangle'}
                  .contains(e.elementType) &&
              _precedesItemsTable(e.content))
          .firstOrNull;

      final int insertSort;
      final double insertY;
      if (pivot != null) {
        insertSort = pivot.sortOrder;
        insertY = pivot.yPosition;
        // إفساحُ مكانٍ — ما عند الموضع فما بعده يُزاح واحداً.
        for (final e in elements.where((e) => e.sortOrder >= pivot.sortOrder)) {
          await (update(invoiceTemplateElements)
                ..where((t) => t.id.equals(e.id)))
              .write(InvoiceTemplateElementsCompanion(
                  sortOrder: Value(e.sortOrder + 1)));
        }
      } else {
        // بلا إجماليات — المطبخُ مثلاً — فالذيلُ موضعُه، وهو ما يفعله
        // المُصيِّرُ حين لا يجد محفّزاً.
        insertSort =
            elements.map((e) => e.sortOrder).fold<int>(0, (a, b) => a > b ? a : b) +
                1;
        insertY = elements
                .map((e) => e.yPosition + e.height)
                .fold<double>(10, (a, b) => a > b ? a : b) +
            3;
      }

      await into(invoiceTemplateElements).insert(
        InvoiceTemplateElementsCompanion.insert(
          templateId: template.id,
          elementType: 'variable',
          sortOrder: Value(insertSort),
          xPosition: const Value(10),
          yPosition: Value(insertY),
          width: const Value(200),
          height: const Value(100),
          textAlign: const Value('right'),
          fontSize: const Value(9),
          fontColor: const Value('#000000'),
          content: const Value('items_table'),
          labelAr: const Value('جدول الأصناف'),
          section: const Value('details'),
        ),
      );
      changed++;
    }
    return changed;
  }

  /// العناصرُ التي يسبقها جدولُ الأصناف — نظيرُ `_precedesItemsTable` في
  /// `TemplatedInvoiceService`، بالمفاتيح **الخام** كما تُخزَّن في القاعدة
  /// (‏هناك تمرّ بـ`_resolveType` أوّلاً: `total_amount`→`total` وأخواتُها).
  static bool _precedesItemsTable(String? content) => const {
        'subtotal', 'discount', 'tax', 'tax_amount',
        'total', 'total_amount', 'grand_total',
        'paid', 'paid_amount', 'remaining', 'change',
        'notes', 'footer', 'footer_text', 'qr_code',
      }.contains(content);

  Future<int> backfillShiftClosingChannelElements() async {
    var changed = 0;
    final templates = await getAllTemplates();

    for (final template in templates.where((t) => t.type == 'shift_closing')) {
      final elements = await getTemplateElements(template.id);
      // قالبٌ فارغٌ تماماً شأنُ [_seedMissingElements] لا شأنُ الإلحاق —
      // إلحاقُ القنوات وحدَها كان سيُنتج تقريراً بلا ترويسةٍ ولا إجماليات.
      if (elements.isEmpty) continue;

      // ── ١) تسميةُ الصفوف القائمة ──
      // «رصيد النظام» ثلاثَ مرّاتٍ بلا اسمِ قناةٍ لا تُقرأ. تُصحَّح في
      // مكانها بلا تحريك — لا حذفَ ولا إعادةَ ترتيب.
      for (final el in elements) {
        if (el.elementType != 'variable') continue;
        final row = _shiftChannelRows
            .where((r) => r.$1 == el.content)
            .firstOrNull;
        if (row == null || el.labelAr == row.$2) continue;
        await (update(invoiceTemplateElements)
              ..where((t) => t.id.equals(el.id)))
            .write(InvoiceTemplateElementsCompanion(labelAr: Value(row.$2)));
        changed++;
      }

      // ── ٢) إلحاقُ الصفوف الغائبة **قبل الإجماليات** ──
      // الذيلُ لا يصلح: المُصيِّر يرتّب مفاتيحَ `shift_*` بـ`sortOrder`، فصفٌّ
      // مُلحَقٌ في الآخر يظهر بعد «إجمالي النظام» و«الحالة» — فيقرأ المستخدمُ
      // إجمالياً ثم رقماً شارداً بعده.
      final present = elements
          .where((e) => e.elementType == 'variable')
          .map((e) => e.content)
          .toSet();
      final missing =
          _shiftChannelRows.where((r) => !present.contains(r.$1)).toList();
      if (missing.isEmpty) continue;

      const rowHeight = 20.0;
      var nextSort = elements
              .map((e) => e.sortOrder)
              .fold<int>(0, (a, b) => a > b ? a : b) +
          1;
      var nextY = elements
              .map((e) => e.yPosition + e.height)
              .fold<double>(10, (a, b) => a > b ? a : b) +
          3;

      for (final (key, label) in missing) {
        await into(invoiceTemplateElements).insert(
          InvoiceTemplateElementsCompanion.insert(
            templateId: template.id,
            elementType: 'variable',
            sortOrder: Value(nextSort++),
            xPosition: const Value(10),
            yPosition: Value(nextY),
            width: const Value(200),
            height: const Value(rowHeight),
            textAlign: const Value('right'),
            fontSize: const Value(9),
            isBold: Value(key.endsWith('_variance')),
            fontColor: const Value('#000000'),
            content: Value(key),
            labelAr: Value(label),
          ),
        );
        nextY += rowHeight + 3;
        changed++;
      }
    }

    // ── ٣) ضبطُ الترتيب ──
    // منفصلٌ عن الإلحاق عمداً: قالبٌ صفوفُه **موجودةٌ** لكن في الذيل لا
    // يراه الإلحاقُ ناقصاً فيتركه مقلوباً. وهذا يقع فعلاً — نسخةٌ أولى من
    // هذا الإصلاح ألحقت في الذيل، فالقوالبُ التي مرّت بها تحتاج ضبطاً لا
    // إلحاقاً.
    changed += await _reorderShiftClosingChannels();
    return changed;
  }

  /// مفتاحُ مراجعةِ قالب الوردية. تغييرُ القيمة يُعيد بناءَ عناصر القالب
  /// **مرّةً واحدة** عند الإقلاع التالي.
  static const _shiftTemplateRevKey = 'shift_closing_template_rev';
  static const _shiftTemplateRev = '2026-08-12-headings';

  /// يُعيد بناءَ عناصر قالب `shift_closing` بالترتيب المبذور — مرّةً واحدة.
  ///
  /// ⚠️ **يمحو أيَّ تصميمٍ أدخله المستخدم على هذا القالب.** ولهذا هو
  /// مشروطٌ بمراجعةٍ مخزَّنة، لا يعمل كلَّ إقلاع: تشغيلٌ دوريٌّ كان سيهدم
  /// عملَ المستخدم في كلّ مرّة، وهو أسوأُ من العطب الذي يعالجه.
  ///
  /// طُلب صراحةً (المالك 2026-08-12) بعد أن تراكمت على قالبه رقعتان من
  /// إصلاحَين متتاليَين: صفوفٌ مُلحَقةٌ في الذيل وعنصرُ عنوانٍ استُغني عنه.
  /// الترتيبُ المبذور أنظفُ من أيّ ترقيعٍ فوقهما.
  ///
  /// رفعُ [_shiftTemplateRev] لاحقاً يدفع تغييرَ البذرة لكلّ التجهيزات —
  /// وهو قرارٌ يُتَّخذ بوعي: كلُّ رفعٍ يهدم تصميماتِ المستخدمين مرّةً أخرى.
  Future<bool> resetShiftClosingTemplateToSeed({bool force = false}) async {
    if (!force && await getSettingValue(_shiftTemplateRevKey) ==
        _shiftTemplateRev) {
      return false;
    }

    var rebuilt = false;
    for (final template
        in (await getAllTemplates()).where((t) => t.type == 'shift_closing')) {
      await (delete(invoiceTemplateElements)
            ..where((e) => e.templateId.equals(template.id)))
          .go();
      await _seedShiftClosingElements(template.id);
      rebuilt = true;
    }

    await setSetting(_shiftTemplateRevKey, _shiftTemplateRev);
    return rebuilt;
  }

  /// يضع صفوفَ القنوات الثلاث (ومعها عناوينُها النصّية إن وُجدت) قبل
  /// الإجمالياتِ مباشرةً، ويعيد ترقيمَ `sortOrder`/`yPosition` تدفّقاً.
  ///
  /// المُصيِّرُ يرتّب مفاتيحَ `shift_*` بـ`sortOrder` وحدَه — كلُّها تقع في
  /// «أولوية ٨: غيرُ معروف» عنده. فصفٌّ بعد «إجمالي النظام» يُقرأ رقماً
  /// شارداً بعد الخلاصة (رُصد على ورقٍ حقيقيّ 2026-08-12).
  ///
  /// متعادلة: قالبٌ مرتَّبٌ سلفاً لا يُكتب فيه شيء.
  Future<int> _reorderShiftClosingChannels() async {
    final channelHeadings = _shiftChannelHeadings.values.toSet();
    var changed = 0;

    for (final template
        in (await getAllTemplates()).where((t) => t.type == 'shift_closing')) {
      final elements = await getTemplateElements(template.id)
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      if (elements.isEmpty) continue;

      bool isChannel(InvoiceTemplateElement e) =>
          (e.elementType == 'variable' &&
              _shiftChannelRows.any((r) => r.$1 == e.content)) ||
          (e.elementType == 'text' && channelHeadings.contains(e.content));

      final channel = elements.where(isChannel).toList();
      if (channel.isEmpty) continue;
      final rest = elements.where((e) => !isChannel(e)).toList();

      // ⚠️ `startsWith('shift_total')` يمسك `shift_total_sales` أيضاً — وهو
      // بندُ **حركةٍ** لا تسوية. فكانت الكتلةُ تُدسّ قبل «إجمالي المبيعات»
      // فينقلب ترتيبُ الورقة عن الشاشة (رُصد على ورقٍ حقيقيّ 2026-08-12).
      // المقصودُ إجمالياتُ التسوية وحدَها.
      const reconTotals = {
        'shift_total_system',
        'shift_total_actual',
        'shift_total_variance',
        'shift_status',
      };
      final totalsIdx =
          rest.indexWhere((e) => reconTotals.contains(e.content));
      final at = totalsIdx < 0 ? rest.length : totalsIdx;

      // الترتيبُ القانونيّ داخل الكتلة: كلُّ قناةٍ بعنوانها ثم صفوفها.
      final ordered = <InvoiceTemplateElement>[];
      for (final channelName in _shiftChannelHeadings.keys) {
        final heading = _shiftChannelHeadings[channelName];
        ordered.addAll(channel.where((e) => e.content == heading));
        for (final (key, _) in _shiftChannelRows.where(
          (r) => r.$1.endsWith(channelName) || r.$1.contains('_${channelName}_'),
        )) {
          ordered.addAll(channel.where((e) => e.content == key));
        }
      }
      // أيُّ عنصرِ قناةٍ لم يلتقطه التصنيفُ يبقى في مكانه من الكتلة.
      ordered.addAll(channel.where((e) => !ordered.contains(e)));

      final finalOrder = [...rest.take(at), ...ordered, ...rest.skip(at)];
      if (finalOrder.map((e) => e.id).join(',') ==
          elements.map((e) => e.id).join(',')) {
        continue; // مرتَّبٌ سلفاً
      }

      var y = 10.0;
      for (var i = 0; i < finalOrder.length; i++) {
        final el = finalOrder[i];
        await (update(invoiceTemplateElements)
              ..where((t) => t.id.equals(el.id)))
            .write(InvoiceTemplateElementsCompanion(
          sortOrder: Value(i),
          yPosition: Value(y),
        ));
        y += el.height + 3;
      }
      changed++;
    }
    return changed;
  }

  /// مِقبضٌ للاختبار: يزرع عناصرَ قالب الوردية الكاملة على قالبٍ قائم.
  @visibleForTesting
  Future<void> seedShiftClosingElementsForTest(int templateId) =>
      _seedShiftClosingElements(templateId);

  /// Seed missing elements for existing templates that have no elements
  Future<void> _seedMissingElements() async {
    final templates = await getAllTemplates();

    for (final template in templates) {
      final elements = await getTemplateElements(template.id);

      // If template has no elements, add default ones based on category
      // ⚠️ الفرزُ على **الفئة** لا النوع: بعد تصحيح المسارات صار نوعُ قوالب
      // المشتريات والمرتجعَين `a4`/`thermal`، فحالاتُ النوع القديمةُ لم تعُد
      // تُبلَغ — وقالبٌ فارغٌ كان يبقى فارغاً إلى الأبد.
      if (elements.isEmpty) {
        switch (template.templateCategory) {
          case 'receipt':
            await _seedDefaultElements(template.id, template.type);
            break;
          case 'invoice':
            await _seedDefaultElements(template.id, 'a4');
            break;
          case 'kitchen':
            await _seedKitchenElements(template.id);
            break;
          case 'sales_return':
            await _seedSalesReturnElements(template.id);
            break;
          case 'purchase':
            await _seedPurchaseElements(template.id);
            break;
          case 'purchase_return':
            await _seedPurchaseReturnElements(template.id);
            break;
          // كان غائباً عن الشبكة: قالبُ ورديةٍ فارغٌ يبقى فارغاً إلى الأبد
          // لأن البذرةَ تتخطّاه (النوعُ موجود) وهذه لا تعرفه.
          case 'shift_closing':
            await _seedShiftClosingElements(template.id);
            break;
        }
      }
    }
  }

  /// Seed kitchen-specific elements
  Future<void> _seedKitchenElements(int templateId) async {
    final elements = [
      {'type': 'variable', 'content': 'order_number', 'alignment': 'center', 'fontSize': 20.0, 'fontWeight': 'bold', 'labelAr': 'طلب رقم'},
      {'type': 'variable', 'content': 'table_number', 'alignment': 'center', 'fontSize': 18.0, 'fontWeight': 'bold', 'labelAr': 'طاولة'},
      {'type': 'line'},
      {'type': 'variable', 'content': 'date', 'alignment': 'right', 'fontSize': 12.0, 'labelAr': 'الوقت'},
      {'type': 'line'},
      {'type': 'variable', 'content': 'items_table', 'labelAr': 'جدول الأصناف'},
      {'type': 'variable', 'content': 'notes', 'alignment': 'center', 'fontSize': 14.0, 'fontWeight': 'bold', 'labelAr': 'ملاحظات'},
    ];

    double currentY = 10;
    const double elementHeight = 25;
    const double spacing = 5;
    const double paperWidth = 220.0;

    for (int i = 0; i < elements.length; i++) {
      final el = elements[i];
      double width = paperWidth - 20;
      double height = el['type'] == 'line' ? 5 : elementHeight;

      final (elType, elContent) = _normalizeSeedElement(
          el['type'] as String, el['content'] as String?);

      await into(invoiceTemplateElements).insert(
        InvoiceTemplateElementsCompanion.insert(
          templateId: templateId,
          elementType: elType,
          sortOrder: Value(i),
          xPosition: const Value(10),
          yPosition: Value(currentY),
          width: Value(width),
          height: Value(height),
          textAlign: Value(el['alignment'] as String? ?? 'center'),
          fontSize: Value(el['fontSize'] as double? ?? 12.0),
          isBold: Value(el['fontWeight'] == 'bold'),
          fontColor: const Value('#000000'),
          labelAr: Value(el['labelAr'] as String?),
          content: Value(elContent),
        ),
      );

      currentY += height + spacing;
    }

    await into(invoiceTableSettings).insert(
      InvoiceTableSettingsCompanion.insert(
        templateId: templateId,
        xPosition: const Value(10),
        yPosition: Value(currentY),
        width: const Value(200),
      ),
    );
  }

  /// Seed shift closing report elements
  Future<void> _seedShiftClosingElements(int templateId) async {
    final elements = [
      {
        'type': 'variable',
        'content': 'company_name',
        'alignment': 'center',
        'fontSize': 14.0,
        'fontWeight': 'bold',
        'labelAr': 'اسم الشركة',
      },
      {'type': 'line'},
      {
        'type': 'text',
        'content': 'تقرير إغلاق الوردية',
        'alignment': 'center',
        'fontSize': 12.0,
        'fontWeight': 'bold',
      },
      {
        'type': 'variable',
        'content': 'date',
        'alignment': 'center',
        'fontSize': 8.0,
        'labelAr': 'التاريخ',
      },
      {
        'type': 'variable',
        'content': 'cashier_name',
        'alignment': 'center',
        'fontSize': 8.0,
        'labelAr': 'الكاشير',
      },
      {'type': 'line'},
      // Sales summary
      {
        'type': 'variable',
        'content': 'shift_invoice_count',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'عدد الفواتير',
      },
      // ترتيبُ «الحركة» هنا يطابق شاشةَ `picpos_past_shifts_panel` بنداً
      // ببند — المشغّلُ يقارن الورقةَ بالشاشة، واختلافُ الترتيب وحدَه يجعله
      // يبحث عن بندٍ يظنّه غائباً.
      {
        'type': 'variable',
        'content': 'shift_opening_balance',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'الرصيد الافتتاحي',
      },
      {
        'type': 'variable',
        'content': 'shift_total_sales',
        'alignment': 'right',
        'fontSize': 9.0,
        'fontWeight': 'bold',
        'labelAr': 'إجمالي المبيعات (شامل الآجل)',
      },
      // الآجلُ **تحت الإجمالي مباشرةً** لا في ذيل القسم: هو تفصيلٌ منه،
      // و«منها» تربطه به. بعيداً عنه كان يُقرأ بنداً مستقلاً فيجمعه القارئُ
      // مرّةً ثانية (بلاغ المالك 2026-08-12).
      //
      // وهو للتوضيح لا للتسوية: مبيعاتٌ لم تُقبَض ولا خزنةَ تحملها، فضمُّه
      // إلى `shift_total_system` يخلق عجزاً وهمياً بقيمته.
      {
        'type': 'variable',
        'content': 'shift_credit_sales',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'منها آجل (خارج التسوية)',
      },
      {
        'type': 'variable',
        'content': 'shift_credit_count',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'عدد الفواتير الآجلة',
      },
      {
        'type': 'variable',
        'content': 'shift_cash_income',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'دخل النقد',
      },
      {
        'type': 'variable',
        'content': 'shift_total_expenses',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'مصروفات الوردية',
      },
      {
        'type': 'variable',
        'content': 'shift_cash_refunds',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'مرتجعات نقدية',
      },
      {'type': 'line'},
      // Cash reconciliation
      {
        'type': 'text',
        'content': _shiftChannelHeadings['cash'],
        'alignment': 'center',
        'fontSize': 9.0,
        'fontWeight': 'bold',
      },
      {
        'type': 'variable',
        'content': 'shift_system_cash',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'النقد — رصيد النظام',
      },
      {
        'type': 'variable',
        'content': 'shift_actual_cash',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'النقد — المبلغ الفعلي',
      },
      {
        'type': 'variable',
        'content': 'shift_cash_variance',
        'alignment': 'right',
        'fontSize': 9.0,
        'fontWeight': 'bold',
        'labelAr': 'النقد — الفارق',
      },
      {'type': 'line'},
      // Card reconciliation
      {
        'type': 'text',
        'content': _shiftChannelHeadings['card'],
        'alignment': 'center',
        'fontSize': 9.0,
        'fontWeight': 'bold',
      },
      {
        'type': 'variable',
        'content': 'shift_system_card',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'البطاقة — رصيد النظام',
      },
      {
        'type': 'variable',
        'content': 'shift_actual_card',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'البطاقة — المبلغ الفعلي',
      },
      {
        'type': 'variable',
        'content': 'shift_card_variance',
        'alignment': 'right',
        'fontSize': 9.0,
        'fontWeight': 'bold',
        'labelAr': 'البطاقة — الفارق',
      },
      {'type': 'line'},
      // §٥-٢ — Click reconciliation. كانت غائبةً عن القالب المبذور بينما
      // `shift_total_system` و`shift_total_actual` تحت **يجمعانها**، فالمطبوعُ
      // يعرض النقدَ والبطاقةَ ويطبع إجمالياً أكبرَ من مجموعهما بلا تفسير:
      // المرصود ميدانياً `240,000 + 120,000` بإجمالي `560,000`.
      {
        'type': 'text',
        'content': _shiftChannelHeadings['click'],
        'alignment': 'center',
        'fontSize': 9.0,
        'fontWeight': 'bold',
      },
      {
        'type': 'variable',
        'content': 'shift_system_click',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'كليك — رصيد النظام',
      },
      {
        'type': 'variable',
        'content': 'shift_actual_click',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'كليك — المبلغ الفعلي',
      },
      {
        'type': 'variable',
        'content': 'shift_click_variance',
        'alignment': 'right',
        'fontSize': 9.0,
        'fontWeight': 'bold',
        'labelAr': 'كليك — الفارق',
      },
      {'type': 'line'},
      // Totals
      {
        'type': 'variable',
        'content': 'shift_total_system',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'إجمالي النظام',
      },
      {
        'type': 'variable',
        'content': 'shift_total_actual',
        'alignment': 'right',
        'fontSize': 9.0,
        'labelAr': 'إجمالي الفعلي',
      },
      {
        'type': 'variable',
        'content': 'shift_total_variance',
        'alignment': 'right',
        'fontSize': 10.0,
        'fontWeight': 'bold',
        'labelAr': 'الفارق الكلي',
      },
      {
        'type': 'variable',
        'content': 'shift_status',
        'alignment': 'center',
        'fontSize': 10.0,
        'fontWeight': 'bold',
        'labelAr': 'الحالة',
      },
      {'type': 'line'},
      // Signatures
      {
        'type': 'text',
        'content': 'توقيع المدير/المدقق: ..................',
        'alignment': 'right',
        'fontSize': 8.0,
      },
      {
        'type': 'text',
        'content': 'توقيع الكاشير: ..................',
        'alignment': 'right',
        'fontSize': 8.0,
      },
    ];

    double currentY = 10;
    const double elementHeight = 20;
    const double spacing = 3;
    const double paperWidth = 220.0;

    for (int i = 0; i < elements.length; i++) {
      final el = elements[i];
      double width = paperWidth - 20;
      double height = el['type'] == 'line' ? 5 : elementHeight;

      final (elType, elContent) = _normalizeSeedElement(
          el['type'] as String, el['content'] as String?);

      await into(invoiceTemplateElements).insert(
        InvoiceTemplateElementsCompanion.insert(
          templateId: templateId,
          elementType: elType,
          sortOrder: Value(i),
          xPosition: const Value(10),
          yPosition: Value(currentY),
          width: Value(width),
          height: Value(height),
          textAlign: Value(el['alignment'] as String? ?? 'center'),
          fontSize: Value(el['fontSize'] as double? ?? 9.0),
          isBold: Value(el['fontWeight'] == 'bold'),
          fontColor: const Value('#000000'),
          content: Value(elContent),
          labelAr: Value(el['labelAr'] as String?),
        ),
      );

      currentY += height + spacing;
    }
  }

  /// Seed sales return elements
  Future<void> _seedSalesReturnElements(int templateId) async {
    final elements = [
      {
        'type': 'company_name',
        'alignment': 'center',
        'fontSize': 16.0,
        'fontWeight': 'bold',
      },
      {'type': 'divider'},
      {
        'type': 'text',
        'alignment': 'center',
        'fontSize': 14.0,
        'fontWeight': 'bold',
        'content': '*** مرتجع مبيعات ***',
      },
      {'type': 'divider'},
      // سندُ المرتجع SRET-N هو رقمُ **هذا** المستند، والفاتورةُ الأصليةُ
      // تُحمل في `order_number` — والتسميةُ من القالب فلا تُقرأ «رقم الطلب».
      {
        'type': 'invoice_number',
        'alignment': 'right',
        'fontSize': 12.0,
        'labelAr': 'رقم سند المرتجع',
      },
      {
        'type': 'order_number',
        'alignment': 'right',
        'fontSize': 12.0,
        'labelAr': 'رقم الفاتورة الأصلية',
      },
      {
        'type': 'date',
        'alignment': 'right',
        'fontSize': 12.0,
        'labelAr': 'تاريخ المرتجع',
      },
      {
        'type': 'customer_name',
        'alignment': 'right',
        'fontSize': 12.0,
        'labelAr': 'العميل',
      },
      {
        'type': 'cashier_name',
        'alignment': 'right',
        'fontSize': 12.0,
        'labelAr': 'الكاشير',
      },
      {'type': 'divider'},
      {'type': 'items_table', 'fontSize': 12.0},
      {'type': 'divider'},
      {
        'type': 'total',
        'alignment': 'left',
        'fontSize': 14.0,
        'fontWeight': 'bold',
        'labelAr': 'إجمالي المرتجع',
      },
      // تفصيلُ الاسترداد — مرتجعٌ نصفُه نقدٌ ونصفُه بنكيٌّ يُقرأ على الورقة.
      {
        'type': 'cash_amount',
        'alignment': 'left',
        'fontSize': 12.0,
        'labelAr': 'استرداد نقدي',
      },
      {
        'type': 'bank_amount',
        'alignment': 'left',
        'fontSize': 12.0,
        'labelAr': 'استرداد بنكي',
      },
      {
        'type': 'payment_method',
        'alignment': 'right',
        'fontSize': 11.0,
        'labelAr': 'طريقة الاسترداد',
      },
      {
        'type': 'notes',
        'alignment': 'right',
        'fontSize': 11.0,
        'labelAr': 'سبب المرتجع',
      },
      {'type': 'divider'},
      {
        'type': 'text',
        'alignment': 'center',
        'fontSize': 10.0,
        'content': 'شكراً لتعاملكم معنا',
      },
    ];

    double currentY = 10;
    const double elementHeight = 25;
    const double spacing = 5;
    const double paperWidth = 220.0;

    for (int i = 0; i < elements.length; i++) {
      final el = elements[i];
      double width = paperWidth - 20;
      double height = el['type'] == 'divider' ? 5 : elementHeight;

      final (elType, elContent) = _normalizeSeedElement(
          el['type'] as String, el['content'] as String?);

      await into(invoiceTemplateElements).insert(
        InvoiceTemplateElementsCompanion.insert(
          templateId: templateId,
          elementType: elType,
          sortOrder: Value(i),
          xPosition: const Value(10),
          yPosition: Value(currentY),
          width: Value(width),
          height: Value(height),
          textAlign: Value(el['alignment'] as String? ?? 'center'),
          fontSize: Value(el['fontSize'] as double? ?? 12.0),
          isBold: Value(el['fontWeight'] == 'bold'),
          fontColor: const Value('#000000'),
          labelAr: Value(el['labelAr'] as String?),
          content: Value(elContent),
        ),
      );

      currentY += height + spacing;
    }

    await into(invoiceTableSettings).insert(
      InvoiceTableSettingsCompanion.insert(
        templateId: templateId,
        xPosition: const Value(10),
        yPosition: Value(currentY),
        width: const Value(200),
      ),
    );
  }

  /// Seed purchase invoice elements
  Future<void> _seedPurchaseElements(int templateId) async {
    final elements = [
      {
        'type': 'company_name',
        'alignment': 'center',
        'fontSize': 18.0,
        'fontWeight': 'bold',
      },
      {'type': 'company_address', 'alignment': 'center', 'fontSize': 10.0},
      {'type': 'company_phone', 'alignment': 'center', 'fontSize': 10.0},
      {'type': 'divider'},
      {
        'type': 'text',
        'alignment': 'center',
        'fontSize': 16.0,
        'fontWeight': 'bold',
        'content': 'فاتورة مشتريات',
      },
      {'type': 'divider'},
      {
        'type': 'invoice_number',
        'alignment': 'right',
        'fontSize': 12.0,
        'labelAr': 'رقم الفاتورة',
      },
      {
        'type': 'date',
        'alignment': 'right',
        'fontSize': 12.0,
        'labelAr': 'التاريخ',
      },
      {
        'type': 'supplier_name',
        'alignment': 'right',
        'fontSize': 12.0,
        'labelAr': 'المورد',
      },
      {'type': 'divider'},
      {'type': 'items_table', 'fontSize': 12.0},
      {'type': 'divider'},
      {
        'type': 'subtotal',
        'alignment': 'left',
        'fontSize': 12.0,
        'labelAr': 'الإجمالي الفرعي',
      },
      {
        'type': 'tax',
        'alignment': 'left',
        'fontSize': 12.0,
        'labelAr': 'الضريبة',
      },
      {
        'type': 'total',
        'alignment': 'left',
        'fontSize': 14.0,
        'fontWeight': 'bold',
        'labelAr': 'الإجمالي',
      },
      {'type': 'divider'},
      {
        'type': 'notes',
        'alignment': 'right',
        'fontSize': 10.0,
        'labelAr': 'ملاحظات',
      },
    ];

    double currentY = 10;
    const double elementHeight = 25;
    const double spacing = 5;
    const double paperWidth = 220.0;

    for (int i = 0; i < elements.length; i++) {
      final el = elements[i];
      double width = paperWidth - 20;
      double height = el['type'] == 'divider' ? 5 : elementHeight;

      final (elType, elContent) = _normalizeSeedElement(
          el['type'] as String, el['content'] as String?);

      await into(invoiceTemplateElements).insert(
        InvoiceTemplateElementsCompanion.insert(
          templateId: templateId,
          elementType: elType,
          sortOrder: Value(i),
          xPosition: const Value(10),
          yPosition: Value(currentY),
          width: Value(width),
          height: Value(height),
          textAlign: Value(el['alignment'] as String? ?? 'center'),
          fontSize: Value(el['fontSize'] as double? ?? 12.0),
          isBold: Value(el['fontWeight'] == 'bold'),
          fontColor: const Value('#000000'),
          labelAr: Value(el['labelAr'] as String?),
          content: Value(elContent),
        ),
      );

      currentY += height + spacing;
    }

    await into(invoiceTableSettings).insert(
      InvoiceTableSettingsCompanion.insert(
        templateId: templateId,
        xPosition: const Value(10),
        yPosition: Value(currentY),
        width: const Value(200),
      ),
    );
  }

  /// Seed purchase return elements
  Future<void> _seedPurchaseReturnElements(int templateId) async {
    final elements = [
      {
        'type': 'company_name',
        'alignment': 'center',
        'fontSize': 16.0,
        'fontWeight': 'bold',
      },
      {'type': 'divider'},
      {
        'type': 'text',
        'alignment': 'center',
        'fontSize': 14.0,
        'fontWeight': 'bold',
        'content': '*** إيصال مرتجع مشتريات ***',
      },
      {'type': 'divider'},
      {
        'type': 'invoice_number',
        'alignment': 'right',
        'fontSize': 12.0,
        'labelAr': 'رقم فاتورة الأصلية',
      },
      {
        'type': 'date',
        'alignment': 'right',
        'fontSize': 12.0,
        'labelAr': 'تاريخ المرتجع',
      },
      {
        'type': 'supplier_name',
        'alignment': 'right',
        'fontSize': 12.0,
        'labelAr': 'المورد',
      },
      {'type': 'divider'},
      {'type': 'items_table', 'fontSize': 12.0},
      {'type': 'divider'},
      {
        'type': 'total',
        'alignment': 'left',
        'fontSize': 14.0,
        'fontWeight': 'bold',
        'labelAr': 'إجمالي المرتجع',
      },
      {'type': 'divider'},
      {
        'type': 'notes',
        'alignment': 'center',
        'fontSize': 10.0,
        'labelAr': 'ملاحظات',
      },
    ];

    double currentY = 10;
    const double elementHeight = 25;
    const double spacing = 5;
    const double paperWidth = 220.0;

    for (int i = 0; i < elements.length; i++) {
      final el = elements[i];
      double width = paperWidth - 20;
      double height = el['type'] == 'divider' ? 5 : elementHeight;

      final (elType, elContent) = _normalizeSeedElement(
          el['type'] as String, el['content'] as String?);

      await into(invoiceTemplateElements).insert(
        InvoiceTemplateElementsCompanion.insert(
          templateId: templateId,
          elementType: elType,
          sortOrder: Value(i),
          xPosition: const Value(10),
          yPosition: Value(currentY),
          width: Value(width),
          height: Value(height),
          textAlign: Value(el['alignment'] as String? ?? 'center'),
          fontSize: Value(el['fontSize'] as double? ?? 12.0),
          isBold: Value(el['fontWeight'] == 'bold'),
          fontColor: const Value('#000000'),
          labelAr: Value(el['labelAr'] as String?),
          content: Value(elContent),
        ),
      );

      currentY += height + spacing;
    }

    await into(invoiceTableSettings).insert(
      InvoiceTableSettingsCompanion.insert(
        templateId: templateId,
        xPosition: const Value(10),
        yPosition: Value(currentY),
        width: const Value(200),
      ),
    );
  }

  /// Seed barcode label templates with various designs
  Future<void> _seedBarcodeTemplates() async {
    // ──────────────────────────────────────────────────────────────
    // 1. باركود قياسي - Standard Barcode (50x25mm)
    //    Compact label with product name + barcode
    // ──────────────────────────────────────────────────────────────
    final id1 = await into(invoiceTemplates).insert(
      InvoiceTemplatesCompanion.insert(
        name: 'باركود قياسي',
        type: const Value('thermal'),
        templateCategory: const Value('barcode'),
        paperSize: const Value('50x25'),
        paperWidth: const Value(50),
        paperHeight: const Value(25),
        isDefault: const Value(true),
      ),
    );
    // Product name at top
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id1,
        elementType: 'product_name',
        sortOrder: const Value(0),
        xPosition: const Value(2),
        yPosition: const Value(1),
        width: const Value(46),
        height: const Value(8),
        fontSize: const Value(7),
        isBold: const Value(true),
        textAlign: const Value('center'),
        labelAr: const Value('اسم المنتج'),
      ),
    );
    // Barcode image
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id1,
        elementType: 'barcode_image',
        sortOrder: const Value(1),
        xPosition: const Value(3),
        yPosition: const Value(9),
        width: const Value(44),
        height: const Value(14),
        fontSize: const Value(5),
        textAlign: const Value('center'),
        content: const Value('code128'),
      ),
    );

    // ──────────────────────────────────────────────────────────────
    // 2. بطاقة سعر - Price Tag (50x30mm)
    //    Name + Barcode + Price
    // ──────────────────────────────────────────────────────────────
    final id2 = await into(invoiceTemplates).insert(
      InvoiceTemplatesCompanion.insert(
        name: 'بطاقة سعر',
        type: const Value('thermal'),
        templateCategory: const Value('barcode'),
        paperSize: const Value('50x30'),
        paperWidth: const Value(50),
        paperHeight: const Value(30),
        isDefault: const Value(false),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id2,
        elementType: 'product_name',
        sortOrder: const Value(0),
        xPosition: const Value(2),
        yPosition: const Value(1),
        width: const Value(46),
        height: const Value(8),
        fontSize: const Value(7),
        isBold: const Value(true),
        textAlign: const Value('center'),
        labelAr: const Value('اسم المنتج'),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id2,
        elementType: 'barcode_image',
        sortOrder: const Value(1),
        xPosition: const Value(3),
        yPosition: const Value(9),
        width: const Value(44),
        height: const Value(12),
        fontSize: const Value(5),
        textAlign: const Value('center'),
        content: const Value('code128'),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id2,
        elementType: 'product_price',
        sortOrder: const Value(2),
        xPosition: const Value(2),
        yPosition: const Value(22),
        width: const Value(46),
        height: const Value(7),
        fontSize: const Value(9),
        isBold: const Value(true),
        textAlign: const Value('center'),
        labelAr: const Value('السعر'),
      ),
    );

    // ──────────────────────────────────────────────────────────────
    // 3. ملصق كامل - Full Product Label (60x40mm)
    //    Name + Code + Barcode + Price
    // ──────────────────────────────────────────────────────────────
    final id3 = await into(invoiceTemplates).insert(
      InvoiceTemplatesCompanion.insert(
        name: 'ملصق كامل',
        type: const Value('thermal'),
        templateCategory: const Value('barcode'),
        paperSize: const Value('60x40'),
        paperWidth: const Value(60),
        paperHeight: const Value(40),
        isDefault: const Value(false),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id3,
        elementType: 'product_name',
        sortOrder: const Value(0),
        xPosition: const Value(2),
        yPosition: const Value(1),
        width: const Value(56),
        height: const Value(9),
        fontSize: const Value(8),
        isBold: const Value(true),
        textAlign: const Value('center'),
        labelAr: const Value('اسم المنتج'),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id3,
        elementType: 'product_code',
        sortOrder: const Value(1),
        xPosition: const Value(2),
        yPosition: const Value(10),
        width: const Value(56),
        height: const Value(6),
        fontSize: const Value(6),
        textAlign: const Value('center'),
        labelAr: const Value('كود المنتج'),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id3,
        elementType: 'barcode_image',
        sortOrder: const Value(2),
        xPosition: const Value(5),
        yPosition: const Value(16),
        width: const Value(50),
        height: const Value(14),
        fontSize: const Value(5),
        textAlign: const Value('center'),
        content: const Value('code128'),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id3,
        elementType: 'product_price',
        sortOrder: const Value(3),
        xPosition: const Value(2),
        yPosition: const Value(31),
        width: const Value(56),
        height: const Value(8),
        fontSize: const Value(10),
        isBold: const Value(true),
        textAlign: const Value('center'),
        labelAr: const Value('السعر'),
      ),
    );

    // ──────────────────────────────────────────────────────────────
    // 4. ملصق رف - Compact Shelf Label (40x20mm)
    //    Small label: Name + Barcode only
    // ──────────────────────────────────────────────────────────────
    final id4 = await into(invoiceTemplates).insert(
      InvoiceTemplatesCompanion.insert(
        name: 'ملصق رف مضغوط',
        type: const Value('thermal'),
        templateCategory: const Value('barcode'),
        paperSize: const Value('40x20'),
        paperWidth: const Value(40),
        paperHeight: const Value(20),
        isDefault: const Value(false),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id4,
        elementType: 'product_name',
        sortOrder: const Value(0),
        xPosition: const Value(1),
        yPosition: const Value(0),
        width: const Value(38),
        height: const Value(6),
        fontSize: const Value(5),
        isBold: const Value(true),
        textAlign: const Value('center'),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id4,
        elementType: 'barcode_image',
        sortOrder: const Value(1),
        xPosition: const Value(2),
        yPosition: const Value(6),
        width: const Value(36),
        height: const Value(13),
        fontSize: const Value(4),
        textAlign: const Value('center'),
        content: const Value('code128'),
      ),
    );

    // ──────────────────────────────────────────────────────────────
    // 5. ملصق مجوهرات - Jewelry/Small Item (30x15mm)
    //    Very compact: Barcode only with tiny text
    // ──────────────────────────────────────────────────────────────
    final id5 = await into(invoiceTemplates).insert(
      InvoiceTemplatesCompanion.insert(
        name: 'ملصق مجوهرات',
        type: const Value('thermal'),
        templateCategory: const Value('barcode'),
        paperSize: const Value('30x15'),
        paperWidth: const Value(30),
        paperHeight: const Value(15),
        isDefault: const Value(false),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id5,
        elementType: 'barcode_image',
        sortOrder: const Value(0),
        xPosition: const Value(1),
        yPosition: const Value(1),
        width: const Value(28),
        height: const Value(9),
        fontSize: const Value(4),
        textAlign: const Value('center'),
        content: const Value('code128'),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id5,
        elementType: 'product_price',
        sortOrder: const Value(1),
        xPosition: const Value(1),
        yPosition: const Value(10),
        width: const Value(28),
        height: const Value(5),
        fontSize: const Value(6),
        isBold: const Value(true),
        textAlign: const Value('center'),
      ),
    );

    // ──────────────────────────────────────────────────────────────
    // 6. ملصق كرتون كبير - Large Box Label (100x50mm)
    //    Name + Code + Large Barcode + Price + Company Name
    // ──────────────────────────────────────────────────────────────
    final id6 = await into(invoiceTemplates).insert(
      InvoiceTemplatesCompanion.insert(
        name: 'ملصق كرتون كبير',
        type: const Value('thermal'),
        templateCategory: const Value('barcode'),
        paperSize: const Value('100x50'),
        paperWidth: const Value(100),
        paperHeight: const Value(50),
        isDefault: const Value(false),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id6,
        elementType: 'company_name',
        sortOrder: const Value(0),
        xPosition: const Value(5),
        yPosition: const Value(1),
        width: const Value(90),
        height: const Value(8),
        fontSize: const Value(8),
        isBold: const Value(true),
        textAlign: const Value('center'),
        labelAr: const Value('اسم الشركة'),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id6,
        elementType: 'product_name',
        sortOrder: const Value(1),
        xPosition: const Value(5),
        yPosition: const Value(10),
        width: const Value(90),
        height: const Value(9),
        fontSize: const Value(10),
        isBold: const Value(true),
        textAlign: const Value('center'),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id6,
        elementType: 'product_code',
        sortOrder: const Value(2),
        xPosition: const Value(5),
        yPosition: const Value(19),
        width: const Value(90),
        height: const Value(6),
        fontSize: const Value(7),
        textAlign: const Value('center'),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id6,
        elementType: 'barcode_image',
        sortOrder: const Value(3),
        xPosition: const Value(10),
        yPosition: const Value(25),
        width: const Value(80),
        height: const Value(16),
        fontSize: const Value(6),
        textAlign: const Value('center'),
        content: const Value('code128'),
      ),
    );
    await into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: id6,
        elementType: 'product_price',
        sortOrder: const Value(4),
        xPosition: const Value(5),
        yPosition: const Value(42),
        width: const Value(90),
        height: const Value(7),
        fontSize: const Value(11),
        isBold: const Value(true),
        textAlign: const Value('center'),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DEFAULT TEMPLATE SEEDING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Seed default elements for a new template
  Future<void> _seedDefaultElements(int templateId, String type) async {
    final elements = type == 'thermal'
        ? _thermalDefaultElements
        : _a4DefaultElements;

    double currentY = 10; // Start Y position
    const double elementHeight = 25; // Default element height
    const double spacing = 5; // Space between elements
    final double paperWidth = type == 'thermal' ? 220.0 : 500.0;

    for (int i = 0; i < elements.length; i++) {
      final el = elements[i];

      // Calculate element dimensions
      double width = paperWidth - 20; // Full width minus margins
      double height = el['type'] == 'line' ? 5 : elementHeight;

      final (elType, elContent) = _normalizeSeedElement(
          el['type'] as String, el['content'] as String?);

      await into(invoiceTemplateElements).insert(
        InvoiceTemplateElementsCompanion.insert(
          templateId: templateId,
          elementType: elType,
          sortOrder: Value(i),
          xPosition: const Value(10), // Left margin
          yPosition: Value(currentY),
          width: Value(width),
          height: Value(height),
          textAlign: Value(el['alignment'] as String? ?? 'center'),
          fontSize: Value(el['fontSize'] as double? ?? 12.0),
          isBold: Value(el['fontWeight'] == 'bold'),
          fontColor: Value(el['fontColor'] as String? ?? '#000000'),
          labelAr: Value(el['labelAr'] as String?),
          labelEn: Value(el['labelEn'] as String?),
          content: Value(elContent),
        ),
      );

      // Move to next Y position
      currentY += height + spacing;
    }

    // Seed default table settings with calculated position
    await into(invoiceTableSettings).insert(
      InvoiceTableSettingsCompanion.insert(
        templateId: templateId,
        xPosition: const Value(10),
        yPosition: Value(currentY),
        width: Value(paperWidth - 20),
      ),
    );
  }

  /// Default elements for thermal receipts — NEW FORMAT
  /// elementType must be one of: variable, text, line, image, rectangle
  /// The 'content' field holds the variable key (e.g. 'company_name')
  List<Map<String, dynamic>> get _thermalDefaultElements => [
    {'type': 'image', 'content': 'logo', 'alignment': 'center'},
    {'type': 'variable', 'content': 'company_name', 'alignment': 'center', 'fontSize': 16.0, 'fontWeight': 'bold'},
    {'type': 'variable', 'content': 'company_address', 'alignment': 'center', 'fontSize': 10.0},
    {'type': 'variable', 'content': 'company_phone', 'alignment': 'center', 'fontSize': 10.0},
    {'type': 'line'},
    {'type': 'variable', 'content': 'invoice_number', 'alignment': 'right', 'labelAr': 'رقم الفاتورة', 'labelEn': 'Invoice #'},
    {'type': 'variable', 'content': 'order_number', 'alignment': 'right', 'labelAr': 'رقم الطلب', 'labelEn': 'Order #'},
    {'type': 'variable', 'content': 'date', 'alignment': 'right', 'labelAr': 'التاريخ', 'labelEn': 'Date'},
    {'type': 'variable', 'content': 'sale_type', 'alignment': 'right', 'labelAr': 'نوع البيع', 'labelEn': 'Sale Type'},
    {'type': 'variable', 'content': 'customer_name', 'alignment': 'right', 'labelAr': 'العميل', 'labelEn': 'Customer'},
    {'type': 'variable', 'content': 'customer_phone', 'alignment': 'right', 'labelAr': 'الهاتف', 'labelEn': 'Phone'},
    {'type': 'line'},
    // الخيار (ب) 2026-08-12: للجدول عنصرٌ في القالب — موضعُه ملكُ المصمّم
    // لا أثرٌ جانبيٌّ لاستدلالٍ في المُصيِّر.
    {'type': 'variable', 'content': 'items_table', 'labelAr': 'جدول الأصناف'},
    {'type': 'variable', 'content': 'subtotal', 'alignment': 'right', 'labelAr': 'المجموع', 'labelEn': 'Subtotal'},
    {'type': 'variable', 'content': 'discount', 'alignment': 'right', 'labelAr': 'الخصم', 'labelEn': 'Discount'},
    {'type': 'variable', 'content': 'tax_amount', 'alignment': 'right', 'labelAr': 'الضريبة', 'labelEn': 'Tax'},
    {'type': 'variable', 'content': 'total_amount', 'alignment': 'right', 'fontSize': 14.0, 'fontWeight': 'bold', 'labelAr': 'الإجمالي', 'labelEn': 'Total'},
    {'type': 'variable', 'content': 'paid', 'alignment': 'right', 'labelAr': 'المدفوع', 'labelEn': 'Paid'},
    {'type': 'variable', 'content': 'remaining', 'alignment': 'right', 'labelAr': 'المتبقي', 'labelEn': 'Remaining'},
    {'type': 'line'},
    {'type': 'variable', 'content': 'qr_code', 'alignment': 'center'},
    {'type': 'text', 'content': 'شكراً لتعاملكم معنا', 'alignment': 'center', 'fontSize': 10.0},
  ];

  /// Default elements for A4 invoices — NEW FORMAT
  List<Map<String, dynamic>> get _a4DefaultElements => [
    {'type': 'image', 'content': 'logo', 'alignment': 'left'},
    {'type': 'variable', 'content': 'company_name', 'alignment': 'left', 'fontSize': 24.0, 'fontWeight': 'bold'},
    {'type': 'variable', 'content': 'company_address', 'alignment': 'left', 'fontSize': 12.0},
    {'type': 'variable', 'content': 'company_phone', 'alignment': 'left', 'fontSize': 12.0},
    {'type': 'variable', 'content': 'company_tax_number', 'alignment': 'left', 'fontSize': 12.0, 'labelAr': 'الرقم الضريبي', 'labelEn': 'Tax ID'},
    {'type': 'text', 'content': 'فاتورة مبيعات', 'alignment': 'center', 'fontSize': 20.0, 'fontWeight': 'bold'},
    {'type': 'variable', 'content': 'invoice_number', 'alignment': 'right', 'labelAr': 'رقم الفاتورة', 'labelEn': 'Invoice #'},
    {'type': 'variable', 'content': 'order_number', 'alignment': 'right', 'labelAr': 'رقم الطلب', 'labelEn': 'Order #'},
    {'type': 'variable', 'content': 'date', 'alignment': 'right', 'labelAr': 'التاريخ', 'labelEn': 'Date'},
    {'type': 'variable', 'content': 'sale_type', 'alignment': 'right', 'labelAr': 'نوع البيع', 'labelEn': 'Sale Type'},
    {'type': 'variable', 'content': 'customer_name', 'alignment': 'left', 'labelAr': 'العميل', 'labelEn': 'Customer'},
    {'type': 'variable', 'content': 'customer_address', 'alignment': 'left', 'labelAr': 'العنوان', 'labelEn': 'Address'},
    {'type': 'variable', 'content': 'customer_phone', 'alignment': 'left', 'labelAr': 'الهاتف', 'labelEn': 'Phone'},
    {'type': 'line'},
    // الخيار (ب) 2026-08-12: للجدول عنصرٌ في القالب — موضعُه ملكُ المصمّم
    // لا أثرٌ جانبيٌّ لاستدلالٍ في المُصيِّر.
    {'type': 'variable', 'content': 'items_table', 'labelAr': 'جدول الأصناف'},
    {'type': 'variable', 'content': 'subtotal', 'alignment': 'right', 'labelAr': 'المجموع', 'labelEn': 'Subtotal'},
    {'type': 'variable', 'content': 'discount', 'alignment': 'right', 'labelAr': 'الخصم', 'labelEn': 'Discount'},
    {'type': 'variable', 'content': 'tax_amount', 'alignment': 'right', 'labelAr': 'الضريبة', 'labelEn': 'Tax'},
    {'type': 'variable', 'content': 'total_amount', 'alignment': 'right', 'fontSize': 16.0, 'fontWeight': 'bold', 'labelAr': 'الإجمالي', 'labelEn': 'Total'},
    {'type': 'variable', 'content': 'paid', 'alignment': 'right', 'labelAr': 'المدفوع', 'labelEn': 'Paid'},
    {'type': 'variable', 'content': 'remaining', 'alignment': 'right', 'labelAr': 'المتبقي', 'labelEn': 'Remaining'},
    {'type': 'line'},
    {'type': 'variable', 'content': 'notes', 'alignment': 'left', 'labelAr': 'ملاحظات', 'labelEn': 'Notes'},
    {'type': 'variable', 'content': 'qr_code', 'alignment': 'right'},
    {'type': 'text', 'content': 'شكراً لتعاملكم معنا', 'alignment': 'center', 'fontSize': 10.0},
  ];
}

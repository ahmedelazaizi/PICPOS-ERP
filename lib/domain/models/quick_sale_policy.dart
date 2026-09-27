// سياسةُ «البيع السريع» — نموذجٌ خالصٌ لشاشةِ §٤.
//
// المصدرُ `invoice_templates/design/PicPos Quick Sale Settings.dc.html`،
// وهو المعتمَدُ بأمر المالك 2026-08-28.
//
// ═══ لماذا هنا لا في ملفّ الشاشة ═══
//
// ٢٩ إعداداً لكلٍّ مفتاحٌ وقيمةٌ افتراضيّةٌ ومدىً وخيارات. وضعُها في الواجهة
// يجعلها غيرَ قابلةٍ للقياس إلّا بضخِّ الشاشة، وحارسُ المستودع يطلب أن يعيش
// الحسابُ الخالصُ في `domain/models`.
//
// ولا أيقوناتٍ ولا ألوانَ هنا عمداً: تلك عرضٌ، وتعيش في ملفّ الشاشة مفهرسةً
// بـ[QuickSaleRow.id].

/// نوعُ الضابط كما في التصميم.
enum QuickSaleControl {
  /// `toggle` — مِزلاجٌ ثنائيّ.
  toggle,

  /// `seg` — ثلاثةُ خياراتٍ متجاورةٍ لكلٍّ شرحٌ تحته.
  segmented,

  /// `pill` — أربعةُ خياراتٍ (أو ثلاثة) في شرائحَ مستديرة.
  pill,

  /// `step` — رقمٌ بمدىً ووحدة.
  number,
}

/// صفُّ إعدادٍ واحد.
class QuickSaleRow {
  /// مفتاحُ التصميم (`focus` · `negstock` …) — يربط الصفَّ بأيقونته ولونه
  /// في طبقة العرض، ويُستعمل في الاختبارات.
  final String id;

  /// مفتاحُ القاعدة الذي يُحفَظ ويُقرأ.
  final String settingKey;

  final QuickSaleControl kind;
  final String title;
  final String? sub;

  /// تسمياتُ الخيارات — فارغةٌ للمِزلاج والرقم.
  final List<String> options;

  /// شرحُ كلِّ خيارٍ في `seg` — فارغٌ فيما عداه.
  final List<String> optionSubs;

  /// الفهرسُ الافتراضيّ. للمِزلاج: ٠ مطفأٌ و١ مضاء.
  final int defaultIndex;

  final double? min;
  final double? max;
  final double? defaultNumber;
  final String? unit;

  /// هل يقرأ المحرّكُ هذا المفتاحَ فعلاً اليوم؟
  ///
  /// ⚠️ **إعدادٌ يُحفَظ ولا يُقرأ ميزةٌ ميّتةٌ صامتة**: المديرُ يظنّه مفعَّلاً
  /// والسلوكُ لا يتغيّر. ولهذا يُصرَّح بالحالة هنا ويحرسها
  /// `quick_sale_policy_test`، ويعرضها الصفُّ للمستخدم بوسمٍ ظاهر.
  final bool enforced;

  /// سببُ عدمِ الإنفاذ — إلزاميٌّ حين [enforced] خطأ.
  final String? notEnforcedReason;

  /// تحفّظٌ على الإنفاذ القائم (‏منفَّذٌ لكن ليس بكلِّ تفاصيله).
  final String? caveat;

  /// المفتاحُ المشحونُ يحمل **عكسَ** معنى العنوان.
  ///
  /// `pos_prevent_item_stacking` يعني «امنع التجميع»، وعنوانُ التصميم
  /// «تجميع الصنف المتكرر». فحفظُ القيمة كما هي يقلب الإعداد.
  final bool invertedBinding;

  /// مفتاحٌ ثانٍ يُكتب مع [settingKey] في نفس الحفظ ليبقى المحرّكُ صحيحاً.
  final String? mirrorKey;

  /// قيمةُ [mirrorKey] المشتقّةُ من الفهرس المختار.
  final String Function(int)? mirrorFor;

  /// إعدادٌ يفتح باباً محاسبيّاً — يُعرَض بوسمِ خطرٍ في التصميم.
  final bool risky;

  const QuickSaleRow({
    required this.id,
    required this.settingKey,
    required this.kind,
    required this.title,
    this.sub,
    this.options = const [],
    this.optionSubs = const [],
    this.defaultIndex = 0,
    this.min,
    this.max,
    this.defaultNumber,
    this.unit,
    this.enforced = false,
    this.notEnforcedReason,
    this.caveat,
    this.invertedBinding = false,
    this.mirrorKey,
    this.mirrorFor,
    this.risky = false,
  });
}

/// مجموعةُ صفوفٍ داخلَ خطوة.
class QuickSaleGroup {
  final String title;
  final String sub;

  /// ملاحظةٌ أسفلَ المجموعة — `note` في التصميم.
  final String? note;

  final List<QuickSaleRow> rows;

  const QuickSaleGroup({
    required this.title,
    required this.sub,
    required this.rows,
    this.note,
  });
}

/// مجموعةُ اختيارٍ متعدّد (‏`kind:'pick'`) — الطرقُ وطرقُ المصادقة.
class QuickSalePick {
  final String id;
  final String title;
  final String sub;
  final String? note;

  /// مفتاحُ القاعدة — تُحفَظ المُختاراتُ مفصولةً بفواصل، والترتيبُ يُحفَظ معها.
  final String settingKey;

  final List<QuickSalePickItem> items;

  /// هل يقرأ المحرّكُ هذا المفتاحَ فعلاً؟
  ///
  /// ⚠️ **كان الحقلُ غائباً عن `QuickSalePick` وحدَها** بينما تُلزم به
  /// `QuickSaleRow` — فلم يكن ثمّةَ سبيلٌ لوسمِ مجموعةِ اختيارٍ بأنّها
  /// عرضٌ لا إنفاذ، ومرّت مجموعتان بلا وسمٍ وإحداهما بلا قارئٍ أصلاً.
  final bool enforced;

  /// سببُ عدمِ الإنفاذ — إلزاميٌّ حين [enforced] خطأ.
  final String? notEnforcedReason;

  const QuickSalePick({
    required this.id,
    required this.title,
    required this.sub,
    required this.settingKey,
    required this.items,
    this.note,
    this.enforced = false,
    this.notEnforcedReason,
  });
}

class QuickSalePickItem {
  final String id;
  final String label;
  final String sub;
  final bool onByDefault;

  const QuickSalePickItem({
    required this.id,
    required this.label,
    required this.sub,
    this.onByDefault = true,
  });
}

/// خطوةٌ من الخمس.
class QuickSaleStep {
  final String id;
  final String label;
  final String sub;

  /// جملةُ الافتتاح — `lede` في التصميم، تشرح لماذا تهمُّ هذه الخطوة.
  final String lede;

  final List<QuickSaleGroup> groups;

  /// مجموعةُ الاختيار إن وُجدت.
  final QuickSalePick? pick;

  const QuickSaleStep({
    required this.id,
    required this.label,
    required this.sub,
    required this.lede,
    required this.groups,
    this.pick,
  });

  /// صفوفُ الإعداد في الخطوة — لا تشمل [pick].
  List<QuickSaleRow> get rows => [for (final g in groups) ...g.rows];
}

// ═══════════════════════════════════════════════════════════════════════════
// أسبابُ عدمِ الإنفاذ — نصوصٌ مشتركةٌ كي لا تتكرّر
// ═══════════════════════════════════════════════════════════════════════════

  // ignore: unused_element
const _newBehaviour =
    'سلوكٌ جديدٌ لا يقرأه المحرّكُ بعد — يُحفَظ ويُعرَض، ويبقى بلا أثرٍ حتّى '
    'يُوصَّل في مساره.';

const List<QuickSaleStep> kQuickSaleSteps = [
  // ── ١. مسح الصنف ───────────────────────────────────────────────────────
  QuickSaleStep(
    id: 'scan',
    label: 'مسح الصنف',
    sub: 'الباركود والكمية',
    lede: 'هذه اللحظة تحدد سرعة الكاشير أكثر من أي شيء آخر — كل نقرة إضافية '
        'بين مسحتين تتضاعف بعدد أصناف اليوم.',
    groups: [
      QuickSaleGroup(
        title: 'المسح والإدخال',
        sub: 'سلوك حقل الباركود ولوحة الأرقام',
        rows: [
          QuickSaleRow(
            id: 'focus',
            settingKey: 'pos_focus_barcode_always',
            kind: QuickSaleControl.toggle,
            title: 'التركيز الدائم على حقل الباركود',
            sub: 'يرجع المؤشر لحقل المسح بعد كل إضافة أو إغلاق نافذة',
            defaultIndex: 1,
            enforced: true,
          ),
          QuickSaleRow(
            id: 'askqty',
            settingKey: 'pos_ask_quantity_before_add',
            kind: QuickSaleControl.toggle,
            title: 'سؤال عن الكمية قبل الإضافة',
            sub: 'يفتح لوحة أرقام — أطفئه إذا كانت أغلب المبيعات وحدة واحدة',
            enforced: true,
          ),
          QuickSaleRow(
            id: 'scale',
            settingKey: 'pos_read_scale_barcode',
            kind: QuickSaleControl.toggle,
            title: 'قراءة باركود الميزان',
            sub: 'يفصل رمز الصنف والوزن من الباركود المركّب تلقائياً',
            defaultIndex: 1,
            notEnforcedReason:
                'قراءةُ باركود الميزان تعمل دائماً اليوم عبر '
                '`scale_barcode_handler` — فالإطفاءُ لا يوقفها.',
          ),
          QuickSaleRow(
            id: 'unknown',
            settingKey: 'pos_unknown_barcode_action',
            kind: QuickSaleControl.segmented,
            title: 'عند باركود غير معروف',
            sub: 'ما يحدث حين لا يطابق الباركود أي صنف',
            options: ['صنف سريع', 'بحث بالاسم', 'تحذير ورفض'],
            optionSubs: [
              'يفتح نافذة إضافة باسم وسعر فقط',
              'يتحول الحقل لبحث نصي',
              'صوت تنبيه ولا شيء يُضاف',
            ],
            enforced: true,
          ),
        ],
      ),
      QuickSaleGroup(
        title: 'الأصناف والمخزون',
        sub: 'ما يُسمح به عند نقص الرصيد',
        note: 'حالة «السماح» تُنشئ رصيداً سالباً يظهر في تقرير الفروقات '
            'ويحتاج تسوية جرد لاحقاً.',
        rows: [
          QuickSaleRow(
            id: 'negstock',
            settingKey: 'pos_negative_stock_policy',
            kind: QuickSaleControl.segmented,
            title: 'البيع بأقل من الرصيد',
            sub: 'عند بيع صنف رصيده صفر أو أقل من الكمية المطلوبة',
            options: ['منع', 'تحذير', 'السماح'],
            optionSubs: [
              'لا يمكن إضافة الصنف',
              'تنبيه مع السماح بالمتابعة',
              'يمرّ بلا أي تنبيه',
            ],
            defaultIndex: 1,
            enforced: true,
            mirrorKey: 'enable_negative_sales',
            mirrorFor: _negativeStockMirror,
            caveat: '«تحذير» و«السماح» يمرّان معاً في المحرّك اليوم — '
                'المنعُ وحدَه هو المنفَّذ، والتنبيهُ بينهما لم يُوصَّل بعد.',
          ),
          QuickSaleRow(
            id: 'merge',
            settingKey: 'pos_prevent_item_stacking',
            kind: QuickSaleControl.toggle,
            title: 'تجميع الصنف المتكرر في سطر واحد',
            sub: 'المسح الثاني يزيد الكمية بدلاً من إضافة سطر — أصناف الميزان '
                'تبقى منفصلة',
            defaultIndex: 1,
            enforced: true,
            invertedBinding: true,
          ),
          QuickSaleRow(
            id: 'maxqty',
            settingKey: 'pos_max_line_quantity',
            kind: QuickSaleControl.pill,
            title: 'أقصى كمية في السطر الواحد',
            sub: 'حاجز أمان ضد الأخطاء المطبعية في لوحة الأرقام',
            options: ['٩٩', '٩٩٩', '٩,٩٩٩', 'بلا حد'],
            defaultIndex: 1,
            enforced: true,
          ),
        ],
      ),
    ],
  ),

  // ── ٢. السلة ───────────────────────────────────────────────────────────
  QuickSaleStep(
    id: 'cart',
    label: 'السلة',
    sub: 'الخصم والتعليق',
    lede: 'كل ما يُفتح للكاشير هنا يجب أن يُقابله سقف رقمي — الصلاحية بلا حد '
        'تفتح باباً لا يُراجَع إلا في نهاية الشهر.',
    groups: [
      QuickSaleGroup(
        title: 'الخصم والتسعير',
        sub: 'حدود التصرف في السعر داخل السلة',
        rows: [
          QuickSaleRow(
            id: 'disccap',
            settingKey: 'pos_manual_discount_cap',
            kind: QuickSaleControl.number,
            title: 'الحد الأقصى للخصم اليدوي',
            sub: 'يسري على الفاتورة والسطر معاً',
            min: 0,
            max: 50,
            defaultNumber: 15,
            unit: '٪',
            enforced: true,
          ),
          QuickSaleRow(
            id: 'discappr',
            settingKey: 'pos_discount_requires_manager',
            kind: QuickSaleControl.toggle,
            title: 'يتطلب موافقة مدير فوق الحد',
            sub: 'بدون الموافقة يُرفض الخصم بدلاً من تسجيله',
            defaultIndex: 1,
            enforced: true,
          ),
          QuickSaleRow(
            id: 'priceedit',
            settingKey: 'pos_price_edit_policy',
            kind: QuickSaleControl.segmented,
            title: 'تعديل سعر البيع في السلة',
            sub: 'تغيير سعر السطر أثناء العملية',
            options: ['ممنوع', 'بموافقة', 'مسموح'],
            optionSubs: [
              'السعر من كارت الصنف فقط — ولو كان معك التصريح',
              'يتطلب مصادقة مشرف',
              'بحسب صلاحية الكاشير',
            ],
            defaultIndex: 1,
            enforced: true,
            caveat: 'السياسةُ تضيّق ولا توسّع: «ممنوع» يمنع الجميعَ حتّى مالكَ '
                'الصلاحية، أمّا «بموافقة» و«مسموح» فيتركان القرارَ لصلاحية '
                '`pos_price_edit` كما هو اليوم — فإعدادُ شاشةٍ لا يمنح ما '
                'تمنعه الصلاحيات. (قرارُ المالك 2026-08-30)',
          ),
        ],
      ),
      QuickSaleGroup(
        title: 'إجراءات السلة',
        sub: 'الأزرار المتاحة للكاشير أثناء العملية',
        rows: [
          QuickSaleRow(
            id: 'hold',
            settingKey: 'show_hold_button_pos',
            kind: QuickSaleControl.toggle,
            title: 'تعليق الفاتورة (Hold)',
            sub: 'يحفظ السلة ويفتح فاتورة جديدة — للطوابير المزدوجة',
            defaultIndex: 1,
            enforced: true,
          ),
          QuickSaleRow(
            id: 'holdmax',
            settingKey: 'pos_hold_max_orders',
            kind: QuickSaleControl.pill,
            title: 'أقصى عدد فواتير معلّقة',
            sub: 'الوصول للحد يمنع تعليق فاتورة جديدة',
            options: ['٥', '١٠', '٢٠', 'بلا حد'],
            defaultIndex: 1,
            enforced: true,
          ),
          QuickSaleRow(
            id: 'delauth',
            settingKey: 'pos_delete_line_requires_auth',
            kind: QuickSaleControl.toggle,
            title: 'حذف سطر يتطلب مصادقة',
            sub: 'يُسجَّل كل حذف في سجل الوردية باسم من صادق عليه',
            risky: true,
            enforced: true,
            caveat: 'طبقةٌ **فوق** صلاحية `pos_remove_item` لا بديلٌ عنها: '
                'الصلاحيةُ تقول من يملك الحذف، وهذا يقول إنّ المالكَ نفسَه '
                'يُصادَق عليه في كلِّ مرّة.',
          ),
          QuickSaleRow(
            id: 'reqcust',
            settingKey: 'pos_require_customer',
            kind: QuickSaleControl.toggle,
            title: 'إلزام اختيار عميل قبل الدفع',
            sub: 'الآجل يطلب عميلاً دائماً بغضّ النظر عن هذا الإعداد',
            enforced: true,
          ),
        ],
      ),
    ],
  ),

  // ── ٣. الدفع ───────────────────────────────────────────────────────────
  QuickSaleStep(
    id: 'pay',
    label: 'الدفع',
    sub: 'الطرق والحوار',
    lede: 'الطرق المؤشَّرة هي وحدها ما يظهر للكاشير مهما كانت صلاحيته — '
        'وطريقة واحدة مؤشَّرة تُلغي حوار الدفع من أساسه.',
    pick: QuickSalePick(
      id: 'methods',
      title: 'الطرق المؤشَّرة',
      sub: 'الترتيب هو ترتيب الأزرار على الشاشة',
      // ⚠️ **الكلمتان كانتا مقلوبتَين**: كانت الشاشةُ تكتب
      // `pos_enabled_payment_methods` والمحرّكُ يقرأ
      // `pos_payment_methods_enabled` — فصفرُ قرّاءٍ للمفتاح المكتوب.
      // المديرُ يُلغي تأشيرَ «آجل»، والمعاينةُ تُسقطه أمام عينَيه، ويحفظ —
      // ثمّ يجده الكاشيرُ في حوار الدفع. مبيعاتٌ آجلةٌ من تِلٍّ ظُنَّ
      // مغلقاً. (‏وجده تدقيقا المزامنة وسلامةِ القاعدة معاً 2026-08-30)
      //
      // ويحرسه `quick_sale_keys_have_readers_test` فلا يعود.
      settingKey: 'pos_payment_methods_enabled',
      enforced: true,
      items: [
        QuickSalePickItem(
            id: 'cash', label: 'نقدي', sub: 'الخزينة الرئيسية · بلا مصادقة'),
        QuickSalePickItem(
            id: 'card', label: 'بطاقة', sub: 'شبكة المدفوعات · حساب بنك'),
        QuickSalePickItem(
            id: 'click', label: 'محفظة / كليك', sub: 'المحافظ الإلكترونية'),
        QuickSalePickItem(
            id: 'credit', label: 'آجل', sub: 'يتطلب عميلاً وحد ائتمان'),
        QuickSalePickItem(
            // `multiple` لا `split`: هو رمزُ المحرّك في
            // `paymentMethodPermissionCodes`، و`parseEnabledPaymentMethods`
            // تُسقط أيَّ رمزٍ غيرِ معروفٍ صامتاً — فكان الخيارُ لا يُفعَّل أبداً.
            id: 'multiple',
            label: 'دفع متعدّد',
            sub: 'تقسيم المبلغ على أكثر من طريقة',
            onByDefault: false),
      ],
    ),
    groups: [
      QuickSaleGroup(
        title: 'سلوك حوار الدفع',
        sub: 'ما يحدث بين آخر صنف وإتمام الفاتورة',
        rows: [
          QuickSaleRow(
            id: 'skipdlg',
            settingKey: 'pos_skip_payment_dialog_single_method',
            kind: QuickSaleControl.toggle,
            title: 'تخطّي الحوار عند طريقة واحدة',
            sub: 'يُحصَّل المبلغ مباشرة بلا نافذة — أسرع مسار ممكن',
            defaultIndex: 1,
            enforced: true,
          ),
          QuickSaleRow(
            id: 'defmethod',
            settingKey: 'pos_default_payment_method',
            kind: QuickSaleControl.pill,
            title: 'الطريقة الافتراضية',
            sub: 'المحدّدة مسبقاً عند فتح الحوار',
            options: ['نقدي', 'بطاقة', 'محفظة / كليك', 'آجل'],
            enforced: true,
          ),
          QuickSaleRow(
            id: 'round',
            settingKey: 'pos_total_rounding',
            kind: QuickSaleControl.pill,
            title: 'تقريب الإجمالي',
            sub: 'لأقرب وحدة عملة متاحة فعلاً في الدرج',
            options: ['بلا تقريب', 'لأقرب ٥ قروش', 'لأقرب ٢٥ قرش', 'لأقرب جنيه'],
            // ⚠️ **الافتراضُ «بلا تقريب» عمداً — ولا يُرفَع.**
            //
            // المفتاحُ غائبٌ عن كلِّ قاعدةٍ قائمة، فالافتراضُ هو ما ستقرؤه
            // كلُّ تنصيبةٍ لحظةَ الترقية. وافتراضٌ غيرُ الصفر كان سيبدأ
            // تقريبَ فواتيرِ كلِّ فرعٍ في العالم بلا أن يطلبه أحد، ويقلب
            // دفاترَهم بأثرٍ فوريّ. التقريبُ قرارُ مالكٍ يُفعَّل صراحةً.
            defaultIndex: 0,
            enforced: true,
          ),
          QuickSaleRow(
            id: 'mgrlimit',
            settingKey: 'pos_manager_confirm_above',
            kind: QuickSaleControl.pill,
            title: 'تأكيد مدير للمبالغ فوق',
            sub: 'حاجز أمان على الفواتير الكبيرة',
            options: ['١,٠٠٠ ج.م', '٢,٥٠٠ ج.م', '٥,٠٠٠ ج.م', 'بلا حد'],
            defaultIndex: 2,
            enforced: true,
          ),
          QuickSaleRow(
            id: 'quickamt',
            settingKey: 'pos_quick_amounts_enabled',
            kind: QuickSaleControl.toggle,
            title: 'لوحة مبالغ سريعة',
            sub: 'أزرار ٥٠ / ١٠٠ / ٢٠٠ / ٥٠٠ لحساب الباقي بنقرة',
            defaultIndex: 1,
            enforced: true,
          ),
        ],
      ),
    ],
  ),

  // ── ٤. الطباعة ─────────────────────────────────────────────────────────
  QuickSaleStep(
    id: 'print',
    label: 'الطباعة',
    sub: 'الإيصال والدرج',
    lede: 'الطباعة التلقائية توفّر نقرة في كل فاتورة، لكنها تستهلك ورقاً في '
        'المبيعات التي لا يطلب فيها العميل إيصالاً.',
    groups: [
      QuickSaleGroup(
        title: 'الإيصال',
        sub: 'ما يُطبع تلقائياً وبكم نسخة',
        rows: [
          QuickSaleRow(
            id: 'autoprint',
            settingKey: 'auto_print_receipt',
            kind: QuickSaleControl.toggle,
            title: 'طباعة تلقائية عند الإتمام',
            sub: 'بلا نافذة تأكيد — الإيصال يخرج مع إغلاق الفاتورة',
            enforced: true,
            caveat: 'الافتراضُ هنا **مطفأٌ** كما في المستودع وتصميمِ الديالوج، '
                'لا مضاءً كما في تصميم هذه الشاشة — والمفتاحُ مشحونٌ فلا '
                'يُقلَب افتراضُه من شاشةٍ جديدة.',
          ),
          QuickSaleRow(
            id: 'copies',
            settingKey: 'pos_receipt_copies',
            kind: QuickSaleControl.pill,
            title: 'عدد النسخ',
            sub: 'النسخة الثانية للأرشيف أو لتوقيع العميل',
            options: ['نسخة واحدة', 'نسختان', '٣ نسخ'],
            enforced: true,
          ),
          QuickSaleRow(
            id: 'tpl',
            settingKey: 'pos_receipt_template',
            kind: QuickSaleControl.pill,
            title: 'القالب المستخدم',
            sub: 'يُرجَّح عند غياب ربطٍ صريحٍ للفرع أو الطابعة',
            options: [
              'thermal80_quick_sale',
              'thermal58_quick_sale',
              'a4_sales_tax_invoice',
            ],
            enforced: true,
          ),
          QuickSaleRow(
            id: 'drawer',
            settingKey: 'pos_open_drawer_on_print',
            kind: QuickSaleControl.toggle,
            title: 'فتح درج النقدية مع الطباعة',
            sub: 'يفتح في الدفع النقدي فقط',
            defaultIndex: 1,
            enforced: true,
          ),
        ],
      ),
      QuickSaleGroup(
        title: 'بعد الإتمام',
        sub: 'إلى أين تذهب الشاشة، وما يُعرض للعميل',
        rows: [
          QuickSaleRow(
            id: 'after',
            settingKey: 'pos_after_print_action',
            kind: QuickSaleControl.segmented,
            title: 'بعد الطباعة',
            sub: 'وجهة الشاشة مباشرة بعد إغلاق الفاتورة',
            options: ['فاتورة جديدة', 'البقاء عليها', 'شاشة الانتظار'],
            optionSubs: [
              'سلة فارغة والمؤشر على المسح',
              'للمراجعة أو إعادة الطباعة',
              'تتطلب دخول كاشير من جديد',
            ],
            enforced: true,
          ),
          QuickSaleRow(
            id: 'digital',
            settingKey: 'pos_digital_receipt_enabled',
            kind: QuickSaleControl.toggle,
            title: 'إرسال الإيصال رقمياً',
            sub: 'زر واتساب / بريد بجانب الطباعة',
            notEnforcedReason:
                'لا يوجد مسارُ إرسالٍ رقميٍّ في المستودع بعد — المفتاحُ يسبق '
                'الميزةَ نفسَها.',
          ),
        ],
      ),
    ],
  ),

  // ── ٥. الوردية ─────────────────────────────────────────────────────────
  QuickSaleStep(
    id: 'shift',
    label: 'الوردية',
    sub: 'الإغلاق والمصادقة',
    lede: 'الإغلاق السريع أخطر إعداد في هذه الشاشة — يجعل الفرق صفراً بلا '
        'مصادقة، فيضيع الدليل على أي نقص في الدرج.',
    pick: QuickSalePick(
      id: 'auth',
      title: 'طرق المصادقة على الإغلاق',
      sub: 'الطريقة الواحدة تكفي — التعدد يعطي بديلاً وقت الأعطال',
      settingKey: 'pos_close_auth_methods',
      notEnforcedReason: 'حوارُ الإغلاق يعرض شرائحَ المصادقة ثابتةً ولا يستشير '
          'هذا المفتاح — فهو يُحفَظ ويُعرَض بلا أثر.',
      note: 'إطفاء كل الطرق مع إخفاء الإغلاق السريع يمنع إغلاق الوردية '
          'تماماً — النظام يُبقي «كلمة المرور» مفعّلة قسراً في هذه الحالة.',
      items: [
        QuickSalePickItem(
            id: 'card', label: 'بطاقة مشرف', sub: 'مسح بطاقة على القارئ'),
        QuickSalePickItem(
            id: 'pass', label: 'كلمة مرور', sub: 'حساب مشرف أو مدير'),
        QuickSalePickItem(
            id: 'pin',
            label: 'PIN رقمي',
            sub: '٤ أرقام على لوحة الأرقام',
            onByDefault: false),
      ],
    ),
    groups: [
      QuickSaleGroup(
        title: 'الإغلاق',
        sub: 'كيف تُقفل الوردية ومن يصادق عليها',
        rows: [
          QuickSaleRow(
            id: 'quickclose',
            settingKey: 'pos_quick_close_enabled',
            kind: QuickSaleControl.toggle,
            title: 'إظهار «إغلاق سريع»',
            sub: 'إغلاق بلا مصادقة يُسجّل الفرق صفراً — أطفئه ليمرّ كل إغلاق '
                'بمصادقة',
            defaultIndex: 1,
            risky: true,
            enforced: true,
          ),
          QuickSaleRow(
            id: 'blind',
            settingKey: 'pos_blind_close',
            kind: QuickSaleControl.toggle,
            title: 'إغلاق أعمى',
            sub: 'لا يعرض المتوقع للكاشير قبل إدخال العدّة الفعلية',
            defaultIndex: 1,
            enforced: true,
          ),
          QuickSaleRow(
            id: 'diffmax',
            settingKey: 'pos_shift_diff_threshold',
            kind: QuickSaleControl.pill,
            title: 'أقصى فرق مسموح بلا سبب',
            sub: 'فوقه يُطلب سبب مكتوب يُرفق بمحضر الوردية',
            options: ['٥ ج.م', '٢٠ ج.م', '٥٠ ج.م', 'بلا حد'],
            defaultIndex: 1,
            enforced: true,
          ),
          QuickSaleRow(
            id: 'xrep',
            settingKey: 'pos_print_x_report_on_close',
            kind: QuickSaleControl.toggle,
            title: 'طباعة تقرير X عند الإغلاق',
            sub: 'ملخّص الوردية على الطابعة الحرارية مباشرة',
            defaultIndex: 1,
            enforced: true,
          ),
        ],
      ),
    ],
  ),
];

/// المرآةُ الثنائيّةُ لسياسة البيع بالسالب — «منع» وحدَها تمنع.
String _negativeStockMirror(int index) => index == 0 ? 'false' : 'true';

/// كلُّ الصفوف مسطَّحةً — للاختبارات وللحفظ.
final List<QuickSaleRow> kQuickSaleRows = [
  for (final step in kQuickSaleSteps) ...step.rows,
];

/// مجموعاتُ الاختيار المتعدّد.
final List<QuickSalePick> kQuickSalePicks = [
  for (final step in kQuickSaleSteps)
    if (step.pick != null) step.pick!,
];

// ═══════════════════════════════════════════════════════════════════════════
// فكُّ القيم وحفظُها
// ═══════════════════════════════════════════════════════════════════════════

/// قيمُ السياسة كما هي في القاعدة — نصوصٌ خام، وحولها فكٌّ آمن.
///
/// ⚠️ **كلُّ فكٍّ يعود للافتراض عند الغياب أو الفساد.** قاعدةُ تنصيبةٍ جديدةٍ
/// لا تحمل أيّاً من هذه المفاتيح، وقيمةٌ فاسدةٌ (نصٌّ ليس رقماً) واردةٌ من
/// تحريرٍ يدويٍّ أو مزامنةٍ قديمة. والسقوطُ في `build` يُفقد الشاشةَ كلَّها،
/// فالفكُّ متسامحٌ والافتراضُ من التصميم.
class QuickSalePolicyValues {
  final Map<String, String> raw;

  const QuickSalePolicyValues(this.raw);

  /// هل المِزلاجُ مضاء؟ — يراعي [QuickSaleRow.invertedBinding].
  bool isOn(QuickSaleRow row) {
    final stored = raw[row.settingKey];

    // ⚠️ **الغيابُ يعطي افتراضَ العرض مباشرةً — بلا عكس.**
    //
    // `defaultIndex` يصف ما **يراه** المديرُ في التصميم، لا ما هو مخزَّن.
    // وعكسُه مع `invertedBinding` كان يقلبه مرّتين: «تجميع الصنف» افتراضُه
    // ١ (مضاء) فكان يُعرَض **مطفأً** على تنصيبةٍ نظيفة، بينما
    // `preventItemStackingProvider` يقرأ غيابَ المفتاح `false` أي
    // «التجميعُ يعمل». فالشاشةُ كانت تصف عكسَ المحرّك.
    // (‏بلاغُ تدقيق المخزون 2026-08-30)
    if (stored == null) return row.defaultIndex == 1;

    final storedOn = stored.toLowerCase() == 'true';
    return row.invertedBinding ? !storedOn : storedOn;
  }

  /// فهرسُ الخيار المختار في `seg` و`pill`.
  int indexOf(QuickSaleRow row) {
    final stored = raw[row.settingKey];
    final parsed = stored == null ? null : int.tryParse(stored);
    if (parsed == null || parsed < 0 || parsed >= row.options.length) {
      return row.defaultIndex;
    }
    return parsed;
  }

  /// قيمةُ صفِّ الرقم.
  double numberOf(QuickSaleRow row) {
    final parsed = double.tryParse(raw[row.settingKey] ?? '');
    if (parsed == null) return row.defaultNumber ?? 0;
    final lo = row.min ?? double.negativeInfinity;
    final hi = row.max ?? double.infinity;
    if (parsed < lo || parsed > hi) return row.defaultNumber ?? 0;
    return parsed;
  }

  /// المُختاراتُ **بترتيبها** — الترتيبُ هو ترتيبُ الأزرار على شاشة الكاشير.
  List<String> pickOf(QuickSalePick pick) {
    final stored = raw[pick.settingKey];
    if (stored == null || stored.trim().isEmpty) {
      return [
        for (final i in pick.items)
          if (i.onByDefault) i.id,
      ];
    }
    final known = {for (final i in pick.items) i.id};
    return stored
        .split(',')
        .map((e) => e.trim())
        .where(known.contains)
        .toList();
  }

  /// ما يُكتب في القاعدة لصفٍّ واحد — ومعه مرآتُه إن وُجدت.
  ///
  /// [index] فهرسُ الخيار، أو ٠/١ للمِزلاج.
  static Map<String, String> write(QuickSaleRow row, int index) {
    final out = <String, String>{};

    if (row.kind == QuickSaleControl.toggle) {
      final on = index == 1;
      final stored = row.invertedBinding ? !on : on;
      out[row.settingKey] = stored.toString();
    } else {
      out[row.settingKey] = '$index';
    }

    final mirror = row.mirrorFor;
    if (row.mirrorKey != null && mirror != null) {
      out[row.mirrorKey!] = mirror(index);
    }
    return out;
  }

  /// ما يُكتب لصفِّ الرقم.
  static Map<String, String> writeNumber(QuickSaleRow row, double value) =>
      {row.settingKey: value.toString()};

  /// ما يُكتب لمجموعةِ اختيارٍ — بالترتيب.
  static Map<String, String> writePick(
          QuickSalePick pick, List<String> selected) =>
      {pick.settingKey: selected.join(',')};
}

// ═══════════════════════════════════════════════════════════════════════════
// أثرُ الإعدادات الحالية
// ═══════════════════════════════════════════════════════════════════════════
//
// `buildPreview()` في التصميم: ثلاثةُ أسطرٍ لكلِّ خطوة، نصُّها **مشتقٌّ من
// القيم** لا ثابت. وهي أثمنُ ما في الشاشة: لا أحدَ يقرأ ٢٩ مِزلاجاً ليعرف
// ماذا فعل، لكنّ جملةً واحدةً — «أي كاشير يقفل بلا مصادقة والفرق يُسجَّل
// صفراً» — تجعل الإعدادَ قراراً لا مِزلاجاً.

/// نبرةُ سطر الأثر — جزءٌ من المعنى لا زينة.
///
/// ⚠️ **رمزٌ لا لون.** ترجمتُها إلى لونٍ تقع في طبقة العرض، وإلّا استورد
/// `domain/models` حزمةَ `material`.
enum QuickSaleImpactTone { good, neutral, warn, danger }

class QuickSaleImpactLine {
  final QuickSaleImpactTone tone;
  final String text;

  const QuickSaleImpactLine(this.tone, this.text);
}

/// أرقامٌ عربيّةٌ داخلَ الجملة — «٢٥٪» لا «25%».
String _arDigits(Object n) =>
    '$n'.replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)]);

QuickSaleRow _rowById(String id) =>
    kQuickSaleRows.firstWhere((r) => r.id == id);

/// أسطرُ الأثر لخطوةٍ بعينها.
List<QuickSaleImpactLine> quickSaleImpact(
  String stepId,
  QuickSalePolicyValues values,
) {
  bool on(String id) => values.isOn(_rowById(id));
  int idx(String id) => values.indexOf(_rowById(id));
  String opt(String id) {
    final row = _rowById(id);
    return row.options[values.indexOf(row)];
  }

  switch (stepId) {
    case 'scan':
      final askQty = on('askqty');
      return [
        QuickSaleImpactLine(
          askQty ? QuickSaleImpactTone.neutral : QuickSaleImpactTone.good,
          askQty
              ? 'كل مسحة تفتح لوحة أرقام — أبطأ، لكن أدق في أصناف الكمية.'
              : 'المسح يضيف وحدة واحدة فوراً — أقصر مسار للطابور.',
        ),
        QuickSaleImpactLine(
          on('scale') ? QuickSaleImpactTone.good : QuickSaleImpactTone.warn,
          on('scale')
              ? 'باركود الميزان يُفكّ تلقائياً — لا إدخال وزن يدوي.'
              : 'وزن الميزان يُدخَل يدوياً، وهو أكثر مصادر الخطأ في الجرد.',
        ),
        QuickSaleImpactLine(
          QuickSaleImpactTone.neutral,
          const [
            'الباركود غير المعروف يفتح صنفاً سريعاً — راجع «الأصناف المؤقتة» أسبوعياً.',
            'الباركود غير المعروف يتحول لبحث بالاسم.',
            'الباركود غير المعروف يُرفض — لا تسريب أصناف بلا كارت.',
          ][idx('unknown')],
        ),
      ];

    case 'cart':
      final cap = _arDigits(values.numberOf(_rowById('disccap')).round());
      final hold = on('hold');
      final delAuth = on('delauth');
      return [
        QuickSaleImpactLine(
          QuickSaleImpactTone.warn,
          'الكاشير يخصم حتى $cap٪ '
              '${on('discappr') ? 'وما فوقه يحتاج موافقة مدير.' : 'وما فوقه يُرفض بلا مسار موافقة.'}',
        ),
        QuickSaleImpactLine(
          hold ? QuickSaleImpactTone.good : QuickSaleImpactTone.neutral,
          hold
              ? 'التعليق مفعّل — الكاشير يخدم عميلاً ثانياً بلا فقد السلة.'
              : 'التعليق مطفأ — أي انقطاع يعني إعادة إدخال السلة كاملة.',
        ),
        QuickSaleImpactLine(
          delAuth ? QuickSaleImpactTone.good : QuickSaleImpactTone.danger,
          delAuth
              ? 'كل حذف سطر يُصادق عليه ويُسجَّل باسم المصادق.'
              : 'حذف السطر حر — لا أثر يربط الحذف بشخص.',
        ),
      ];

    case 'pay':
      final methods = values.pickOf(
          kQuickSalePicks.firstWhere((p) => p.id == 'methods'));
      final fast = on('skipdlg') && methods.length == 1;
      return [
        QuickSaleImpactLine(
          fast ? QuickSaleImpactTone.good : QuickSaleImpactTone.neutral,
          fast
              ? 'مسار سريع: طريقة واحدة مؤشَّرة والحوار مُتخطّى تماماً.'
              : '${_arDigits(methods.length)} طرق مؤشَّرة — الكاشير يختار من حوار الدفع.',
        ),
        QuickSaleImpactLine(
          QuickSaleImpactTone.neutral,
          'التقريب: ${opt('round')} · الافتراضي: ${opt('defmethod')}.',
        ),
        QuickSaleImpactLine(
          QuickSaleImpactTone.warn,
          'ما فوق ${opt('mgrlimit')} يحتاج تأكيد مدير.',
        ),
      ];

    case 'print':
      final autoPrint = on('autoprint');
      final drawer = on('drawer');
      final digital = on('digital');
      return [
        QuickSaleImpactLine(
          autoPrint ? QuickSaleImpactTone.good : QuickSaleImpactTone.neutral,
          autoPrint
              ? '${opt('copies')} تُطبع تلقائياً على قالب ${opt('tpl')}.'
              : 'لا طباعة تلقائية — الكاشير يطبع بنقرة عند الطلب فقط.',
        ),
        QuickSaleImpactLine(
          QuickSaleImpactTone.neutral,
          drawer
              ? 'الدرج يُفتح مع الطباعة في الدفع النقدي فقط.'
              : 'الدرج لا يُفتح آلياً — فتحه اليدوي يُسجَّل في الوردية.',
        ),
        QuickSaleImpactLine(
          digital ? QuickSaleImpactTone.good : QuickSaleImpactTone.neutral,
          digital
              ? 'زر الإرسال الرقمي ظاهر بجانب الطباعة.'
              : 'لا إرسال رقمي — الإيصال ورقي فقط.',
        ),
      ];

    default:
      final quickClose = on('quickclose');
      final blind = on('blind');
      final auth = values
          .pickOf(kQuickSalePicks.firstWhere((p) => p.id == 'auth'));
      final authLabels = [
        for (final id in auth)
          kQuickSalePicks
              .firstWhere((p) => p.id == 'auth')
              .items
              .firstWhere((i) => i.id == id)
              .label,
      ];
      return [
        QuickSaleImpactLine(
          quickClose ? QuickSaleImpactTone.danger : QuickSaleImpactTone.good,
          quickClose
              ? 'الإغلاق السريع ظاهر — أي كاشير يقفل بلا مصادقة والفرق يُسجَّل صفراً.'
              : 'كل إغلاق يمرّ بمصادقة، والفرق يُسجَّل كما هو.',
        ),
        QuickSaleImpactLine(
          QuickSaleImpactTone.neutral,
          blind
              ? 'إغلاق أعمى — الكاشير لا يرى المتوقع قبل العدّ.'
              : 'المتوقع معروض قبل العدّ، وهو ما يجعل الفرق دائماً صفراً على الورق.',
        ),
        QuickSaleImpactLine(
          authLabels.isEmpty
              ? QuickSaleImpactTone.danger
              : QuickSaleImpactTone.good,
          authLabels.isEmpty
              ? 'لا طريقة مصادقة مفعّلة — النظام سيُبقي كلمة المرور قسراً.'
              : 'طرق المصادقة المتاحة: ${authLabels.join(' · ')}.',
        ),
      ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ترجمةُ الخيارات إلى حدودٍ رقميّة — الجسرُ بين الشاشة والمحرّك
// ═══════════════════════════════════════════════════════════════════════════
//
// خيارُ الشاشة نصٌّ («٩,٩٩٩» · «بلا حد») والمحرّكُ يحتاج رقماً. وهذه الترجمةُ
// موضعُ عطبٍ حقيقيّ: فهرسٌ يُقرأ خطأً يعني سقفاً مختلفاً تماماً.
//
// ⚠️ **و`null` تعني «بلا حد» لا صفراً.** الخلطُ بينهما يقلب أكثرَ الإعدادات
// تساهلاً إلى أشدِّها تقييداً — «بلا حدٍّ للتعليق» تصير «ممنوعُ التعليق».

/// سقفُ الفواتير المعلّقة — `null` بلا حد.
int? quickSaleHoldCap(QuickSalePolicyValues v) =>
    const [5, 10, 20, null][v.indexOf(_rowById('holdmax'))];

/// هل يُسمح بتعليق فاتورةٍ جديدة؟ — الوصولُ للحدّ يمنع، لا تجاوزُه.
bool quickSaleCanHoldMore({required int current, required int? cap}) =>
    cap == null || current < cap;

/// أقصى كميّةٍ في السطر — `null` بلا حد.
double? quickSaleMaxLineQty(QuickSalePolicyValues v) =>
    const <double?>[99, 999, 9999, null][v.indexOf(_rowById('maxqty'))];

/// المبلغُ الذي فوقه يُطلَب تأكيدُ مدير — `null` بلا حد.
double? quickSaleManagerConfirmAbove(QuickSalePolicyValues v) =>
    const <double?>[1000, 2500, 5000, null]
        [v.indexOf(_rowById('mgrlimit'))];

/// سقفُ الخصم اليدويّ نسبةً مئويّة.
double quickSaleDiscountCap(QuickSalePolicyValues v) =>
    v.numberOf(_rowById('disccap'));

/// هل تقع نسبةُ الخصم داخلَ السقف؟ — المساواةُ مسموحة.
bool quickSaleDiscountAllowed({
  required double percent,
  required double cap,
}) =>
    percent <= cap;

/// خطوةُ تقريب الإجماليّ بالعملة — **صفرٌ يعني «بلا تقريب»**.
///
/// الخياراتُ الأربعةُ بترتيب الشاشة: بلا · ٥ قروش · ٢٥ قرشاً · جنيه.
double quickSaleRoundingStep(QuickSalePolicyValues v) =>
    const <double>[0, 0.05, 0.25, 1.00][v.indexOf(_rowById('round'))];

/// الإجماليُّ **المقبوض** بعد التقريب لأقرب [step].
///
/// ⚠️ **ولا يمسّ `total` المحفوظ.** الإيرادُ والوعاءُ الضريبيُّ يُشتقّان من
/// الإجماليِّ الحقيقيّ؛ وتقريبُ `total` نفسِه كان **يتّزن ويكذب**: أطرافُ
/// القيد تُشتقّ منه فتتوازن بالبناء مهما كان الرقم، فيُبتلَع الفرقُ في
/// المبيعات أو في الخصم بلا سطرٍ ولا تشخيص. (‏تدقيقٌ محاسبيٌّ 2026-08-30)
///
/// `step <= 0` ⇒ يعود الإجماليُّ كما هو، فخيارُ «بلا تقريب» لا يمرّ بحساب.
double quickSaleRoundedTotal({required double total, required double step}) {
  if (step <= 0) return total;
  // نصفٌ لأعلى بوحداتٍ صحيحةٍ من الخطوة — لا حسابَ عائمٍ مباشرٍ على العملة.
  return (total / step).roundToDouble() * step;
}

/// فرقُ التقريب = `total - roundedTotal` — بإشارته.
///
/// موجبٌ = قُرِّب هبوطاً (‏قُبض أقلّ) ⇒ `Dr 4319 فروق تقريب`.
/// سالبٌ = قُرِّب صعوداً (‏قُبض أكثر) ⇒ `Cr 4319`.
///
/// ⚠️ **والفتاتُ العائمُ يُقصّ**: `(114.08/0.05).round()*0.05` تعطي
/// `114.05000000000001`، فالفرقُ بلا تقريبٍ للخانات يصير `-0.0000000000001`
/// ويولّد سطرَ قيدٍ بقيمةٍ لا تُرى — يُرفض في الترحيل أو يلوّث الأستاذ.
double quickSaleRoundingDelta({
  required double total,
  required double step,
  required int decimals,
}) {
  if (step <= 0) return 0;
  final rounded = quickSaleRoundedTotal(total: total, step: step);
  return double.parse((total - rounded).toStringAsFixed(decimals));
}

/// أقصى فرقٍ في الوردية يُقبل بلا سببٍ مكتوب — `null` بلا حد.
double? quickSaleShiftDiffLimit(QuickSalePolicyValues v) =>
    const <double?>[5, 20, 50, null][v.indexOf(_rowById('diffmax'))];

/// الفرقُ الحاكمُ لسياسة «سبب الفرق» — أكبرُ القنوات بالقيمة المطلقة.
///
/// ⚠️ **لا مجموعُ القنوات.** المجموعُ يُقاصّ: عجزٌ نقديٌّ −٣٠٠ وفائضُ بنكٍ
/// +٣٠٠ يعطيان صفراً فلا يُسأل الكاشيرُ عن شيء — بينما قيدُ الفرق يُرحّل
/// **النقديَّ وحدَه** ()، فتخرج ٣٠٠ من
/// الدرج ومن الدفاتر بلا سطرِ تفسيرٍ واحد.
/// (‏بلاغُ التدقيق المحاسبيّ 2026-08-30)
double quickSaleGoverningShiftDiff({
  required double cash,
  required double bank,
  required double click,
}) {
  final a = cash.abs(), b = bank.abs(), c = click.abs();
  return a >= b ? (a >= c ? a : c) : (b >= c ? b : c);
}

/// هل يحتاج فرقُ الوردية سبباً مكتوباً؟
///
/// ⚠️ **بالقيمة المطلقة**: العجزُ ٢٥ يحتاج سبباً كما تحتاجه الزيادةُ ٢٥،
/// وإهمالُ الإشارة يُعفي العجزَ — وهو الأخطرُ محاسبيّاً.
bool quickSaleShiftDiffNeedsReason({
  required double difference,
  required double? limit,
}) =>
    limit != null && difference.abs() > limit;

/// سياسةُ تعديل سعر البيع في السلة — §٤ `priceedit`.
///
/// ⚠️ **لا تمنح صلاحيةً أبداً** (‏قرارُ المالك 2026-08-30). صلاحيةُ
/// `pos_price_edit` تبقى الحاكمةَ، والسياسةُ **تضيّق ولا توسّع**:
///
///   • [blocked] — تمنع الجميعَ، حتّى مالكَ الصلاحية. وهي التضييقُ
///     الحقيقيُّ الذي تضيفه هذه السياسة: «الأسعارُ ثابتةٌ في هذا المحلّ».
///   • [needsApproval] و[allowed] — كلتاهما تتركان القرارَ لنظام
///     الصلاحيات كما هو اليوم. وجعلُ [allowed] تفتح للجميع كان يعني
///     إعداداً يمنح ما تمنعه الصلاحيات، وهو تراجعٌ أمنيٌّ لا ميزة.
enum QuickSalePriceEditPolicy { blocked, needsApproval, allowed }

QuickSalePriceEditPolicy quickSalePriceEditPolicy(
  QuickSalePolicyValues v,
) =>
    QuickSalePriceEditPolicy.values[v.indexOf(_rowById('priceedit'))];

/// عددُ نسخ الإيصال — لا يكون صفراً أبداً.
int quickSaleReceiptCopies(QuickSalePolicyValues v) =>
    const [1, 2, 3][v.indexOf(_rowById('copies'))];

/// مفتاحُ «القالب المستخدم» — يقرؤه الحاسمُ من القاعدة مباشرةً بلا Riverpod.
const kQuickSaleReceiptTemplateKey = 'pos_receipt_template';

/// اسمُ ملفِّ القالب المختار في «القالب المستخدم» — من **القيمة المخزَّنة**.
///
/// يرجع `null` حين لا رأيَ للمِزلاج، وهي الحالةُ الافتراضيّة.
///
/// ⚠️ **ولا يُستعمل [QuickSalePolicyValues.indexOf] هنا**: هي تسقط إلى
/// `defaultIndex` (صفر) عند غياب المفتاح — وهو الصوابُ لعرضِ شاشةٍ، وخطأٌ
/// قاتلٌ لحسمِ قالب. فمفتاحٌ غائبٌ كان سيعني «اختار المديرُ
/// `thermal80_quick_sale`»، فيتقدّم على القالب الافتراضيِّ للفئة في **كلِّ**
/// تركيبٍ لم يلمس هذا المِزلاجَ قطّ — انقلابُ مطبوعٍ صامتٌ للجميع.
///
/// فالقاعدةُ: **مِزلاجٌ لم يُلمَس لا يقرّر شيئاً.** والفهرسُ الشاذُّ (قيمةٌ
/// فاسدةٌ أو خارجُ المدى) يُعامَل مثلَه — سقوطٌ للمستوى التالي لا حَزْرٌ.
String? quickSaleReceiptTemplateFile(String? storedIndex) {
  if (storedIndex == null) return null;
  final row = _rowById('tpl');
  final idx = int.tryParse(storedIndex.trim());
  if (idx == null || idx < 0 || idx >= row.options.length) return null;
  return row.options[idx];
}

/// ما يحدث حين لا يطابق الباركودُ أيَّ صنف.
///
/// ⚠️ **الترتيبُ هو ترتيبُ خيارات التصميم** — فهرسٌ يُقرأ خطأً يقلب
/// «ارفض» إلى «أنشئ صنفاً»، وهو أوسعُ بابٍ في هذه الشاشة: صنفٌ يُخلَق
/// بسعرٍ يكتبه الكاشير بلا كارتٍ ولا تكلفة.
enum QuickSaleUnknownBarcodeAction {
  /// يفتح `QuickAddProductDialog` — السلوكُ القائم قبل التوصيل.
  quickAdd,

  /// يحوّل الحقلَ إلى بحثٍ نصّيٍّ بالاسم.
  nameSearch,

  /// صوتُ تنبيهٍ ورفضٌ — لا شيءَ يُضاف ولا صنفَ يُخلَق.
  reject,
}

QuickSaleUnknownBarcodeAction quickSaleUnknownBarcodeAction(
  QuickSalePolicyValues v,
) =>
    QuickSaleUnknownBarcodeAction
        .values[v.indexOf(_rowById('unknown'))];

/// الطريقةُ المؤشَّرةُ مسبقاً عند فتح حوار الدفع.
///
/// ⚠️ **الرموزُ هي رموزُ المحرّك** (`cash` · `card` · `click` · `credit`)
/// كما في `_methodOrder` بـ`pos_payment_dialogs.dart` — لا تسمياتُ الشاشة.
/// وهي **تأشيرٌ لا إلزام**: الكاشيرُ يبدّلها في الحوار، وطريقةٌ غيرُ
/// مسموحةٍ في هذا الفرع يتجاهلها الحوارُ ويؤشّر أوّلَ المسموح.
String quickSaleDefaultPaymentMethod(QuickSalePolicyValues v) =>
    const ['cash', 'card', 'click', 'credit']
        [v.indexOf(_rowById('defmethod'))];

/// وجهةُ الشاشة مباشرةً بعد إغلاق الفاتورة.
enum QuickSaleAfterPrintAction {
  /// سلّةٌ فارغةٌ والمؤشّرُ على المسح — السلوكُ القائم قبل التوصيل.
  newInvoice,

  /// البقاءُ على الفاتورة للمراجعة أو إعادة الطباعة.
  stay,

  /// شاشةُ الانتظار — تتطلّب دخولَ كاشيرٍ من جديد.
  lockScreen,
}

QuickSaleAfterPrintAction quickSaleAfterPrintAction(
  QuickSalePolicyValues v,
) =>
    QuickSaleAfterPrintAction.values[v.indexOf(_rowById('after'))];

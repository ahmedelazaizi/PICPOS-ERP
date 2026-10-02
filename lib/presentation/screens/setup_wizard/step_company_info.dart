part of '../setup_wizard_screen.dart';

/// أنواعُ النشاط الستّة — `BLOCKS` في `PicPos Setup Wizard.dc.html`.
///
/// ⚠️ **المفاتيحُ هي ما يُحفَظ** (`_businessType`)، فلا تُعدَّل: تبديلُ مفتاحٍ
/// يجعل تنصيباً قائماً يقرأ نوعاً لا يعرفه فيسقط على الافتراضيّ صامتاً.
///
/// ⚠️ **وهذا غيرُ «ملفّ النشاط»** في الخطوة ٨ (`BusinessProfile`). ذاك يقرّر
/// أيَّ **شاشاتٍ** تظهر وهو محميٌّ بكلمة مرور المطوّر؛ وهذا وسمٌ وصفيٌّ
/// للمنشأة. واسماهما متقاربان والأثرُ مختلفٌ تماماً.
List<(String, String, String, IconData)> get _businessTypeCards => <(String, String, String, IconData)>[
  (
    'retail',
    tr('تجزئة'),
    tr('سوبر ماركت وبقالة — بيعٌ بالباركود والميزان'),
    PhosphorIconsBold.shoppingCart,
  ),
  (
    'restaurant',
    tr('مطعم / كافيه'),
    tr('طاولاتٌ وطلباتٌ وحجوزات'),
    PhosphorIconsBold.forkKnife,
  ),
  (
    'wholesale',
    tr('جملة وتوزيع'),
    tr('عملاءُ آجلون ومندوبو توزيع'),
    PhosphorIconsBold.truck,
  ),
  (
    'manufacturing',
    tr('تصنيع'),
    tr('أوامرُ إنتاجٍ ومكوّناتٌ وتكلفةُ وحدة'),
    PhosphorIconsBold.factory,
  ),
  (
    'services',
    tr('خدمات'),
    tr('فواتيرُ خدماتٍ بلا مخزون'),
    PhosphorIconsBold.wrench,
  ),
  (
    'other',
    tr('أخرى'),
    tr('نشاطٌ لا يطابق ما سبق'),
    PhosphorIconsBold.dotsThreeCircle,
  ),
];

/// العملاتُ الستُّ — `BLOCKS` في التصميم، والمفتاحُ رمزُ ISO.
List<(String, String)> get _currencyChips => <(String, String)>[
  ('EGP', tr('جنيه مصري')),
  ('SAR', tr('ريال سعودي')),
  ('AED', tr('درهم إماراتي')),
  ('JOD', tr('دينار أردني')),
  ('KWD', tr('دينار كويتي')),
  ('USD', tr('دولار أمريكي')),
];

extension _SetupWizardCompanyInfoExt on _SetupWizardScreenState {
  // ═══════════════════════════════════════════════════════════════════════
  // STEP 1: Company Info
  // ═══════════════════════════════════════════════════════════════════════
  //
  // بندُ المالك ٦: «الشركة والنشاط» — الهويّةُ كاملةً (‏اسمان · ضريبيّ · سجلّ
  // تجاريّ · هاتف · عنوان · شعار) ثمّ ملفُّ النشاط الذي يقرّر الشاشات، ثمّ
  // تصنيفُ النشاط الوصفيّ. والعملةُ انتقلت إلى خطوتها مع الضريبة.
  Widget _buildCompanyInfoStep() {
    final isClient = _networkMode == NetworkMode.client;
    Widget pair(Widget a, Widget b) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isClient) ...[
          _inlineNote(
            context,
            icon: PhosphorIconsBold.info,
            tone: AppColors.info,
            title: tr('بيانات الشركة من السيرفر'),
            body: tr('في وضع العميل تصل بيانات الشركة بالمزامنة — الحقول هنا اختيارية.'),
          ),
          const SizedBox(height: 14),
        ],
        pair(
          _buildTextField(
            key: const Key('setup_company_name'),
            controller: _companyNameController,
            label: tr('اسم الشركة / المحل'),
            hint: tr('مثال: سوبر ماركت النيل'),
            icon: PhosphorIconsBold.storefront,
            isRequired: !isClient,
            onChanged: (_) => setState(() {}),
          ),
          _buildTextField(
            key: const Key('setup_company_name_en'),
            controller: _companyNameEnController,
            label: tr('الاسم بالإنجليزية'),
            hint: 'Nile Supermarket',
            icon: PhosphorIconsBold.textAa,
          ),
        ),
        const SizedBox(height: 12),
        pair(
          _buildTextField(
            key: const Key('setup_tax_number'),
            controller: _taxNumberController,
            label: tr('الرقم الضريبي'),
            icon: PhosphorIconsBold.receipt,
          ),
          _buildTextField(
            key: const Key('setup_cr_number'),
            controller: _commercialRegisterController,
            label: tr('السجل التجاري'),
            icon: PhosphorIconsBold.identificationCard,
          ),
        ),
        const SizedBox(height: 12),
        pair(
          _buildTextField(
            controller: _companyPhoneController,
            label: tr('رقم الهاتف'),
            hint: '01xxxxxxxxx',
            icon: PhosphorIconsBold.phone,
          ),
          _buildTextField(
            controller: _companyAddressController,
            label: tr('العنوان'),
            hint: tr('القاهرة، مصر'),
            icon: PhosphorIconsBold.mapPin,
          ),
        ),
        const SizedBox(height: 12),
        _buildLogoPicker(),
        const SizedBox(height: 20),

        // ── ملفّ النشاط — يقرّر الشاشات ──
        _stepFieldLabel(tr('ملف النشاط التجاري')),
        const SizedBox(height: 4),
        Text(
          tr('يحدد هذا الاختيار الشاشات والميزات الظاهرة للمستخدم. يمكن تعديله لاحقًا من "أدوات المطوّر" فقط (محمية بكلمة مرور مطوّر منفصلة).'),
          style: TextStyle(fontSize: 12, color: _mutedInk(context)),
        ),
        const SizedBox(height: 8),
        _buildBusinessProfileSection(),
        const SizedBox(height: 20),

        // ── نوع النشاط — وسمٌ وصفيٌّ يتبع الملفَّ افتراضيّاً ────────────
        //
        // كان ستَّ بطاقاتٍ بوصفٍ لكلٍّ منها. وبعد أن صار «ملفُّ النشاط»
        // بجوارها ببطاقاتٍ موصوفة، صارت بطاقاتٌ ثانيةٌ بأوصافٍ تكراراً يُربك
        // («هل أجبتُ هذا السؤال؟») — فهي رقاقاتٌ تتبع الملفَّ افتراضيّاً،
        // والوصفُ تلميحٌ عند المرور.
        _stepFieldLabel(tr('نوع النشاط')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (id, title, sub, icon) in _businessTypeCards)
              Tooltip(
                message: sub,
                child: ChoiceChip(
                  key: Key('setup_business_type_$id'),
                  avatar: Icon(icon, size: 15),
                  selected: _businessType == id,
                  onSelected: (_) => setState(() {
                    _businessType = id;
                    _businessTypeTouched = true;
                  }),
                  label: Text(title),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// الشعارُ — يُطبَع في ترويسة الفاتورة (`company_logo`).
  Widget _buildLogoPicker() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: _logo != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(_logo!, fit: BoxFit.cover),
                  )
                : Icon(PhosphorIconsBold.image, color: _brandInk(context)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('شعار الشركة'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  _logo != null
                      ? tr('تم اختيار الشعار')
                      : tr('اختياري — يظهر في ترويسة الفواتير المطبوعة'),
                  style: TextStyle(fontSize: 12, color: _mutedInk(context)),
                ),
              ],
            ),
          ),
          if (_logo != null)
            TextButton(
              onPressed: () => setState(() => _logo = null),
              child: Text(tr('إزالة')),
            ),
          OutlinedButton.icon(
            key: const Key('setup_pick_logo'),
            onPressed: _pickLogo,
            icon: const Icon(PhosphorIconsBold.upload, size: 16),
            label: Text(tr('اختيار صورة')),
          ),
        ],
      ),
    );
  }
}

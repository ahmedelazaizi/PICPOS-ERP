part of '../setup_wizard_screen.dart';

/// أنواعُ النشاط الستّة — `BLOCKS` في `PicPos Setup Wizard.dc.html`.
///
/// ⚠️ **المفاتيحُ هي ما يُحفَظ** (`_businessType`)، فلا تُعدَّل: تبديلُ مفتاحٍ
/// يجعل تنصيباً قائماً يقرأ نوعاً لا يعرفه فيسقط على الافتراضيّ صامتاً.
///
/// ⚠️ **وهذا غيرُ «ملفّ النشاط»** في الخطوة ٨ (`BusinessProfile`). ذاك يقرّر
/// أيَّ **شاشاتٍ** تظهر وهو محميٌّ بكلمة مرور المطوّر؛ وهذا وسمٌ وصفيٌّ
/// للمنشأة. واسماهما متقاربان والأثرُ مختلفٌ تماماً.
const _businessTypeCards = <(String, String, String, IconData)>[
  (
    'retail',
    'تجزئة',
    'سوبر ماركت وبقالة — بيعٌ بالباركود والميزان',
    PhosphorIconsBold.shoppingCart,
  ),
  (
    'restaurant',
    'مطعم / كافيه',
    'طاولاتٌ وطلباتٌ وحجوزات',
    PhosphorIconsBold.forkKnife,
  ),
  (
    'wholesale',
    'جملة وتوزيع',
    'عملاءُ آجلون ومندوبو توزيع',
    PhosphorIconsBold.truck,
  ),
  (
    'manufacturing',
    'تصنيع',
    'أوامرُ إنتاجٍ ومكوّناتٌ وتكلفةُ وحدة',
    PhosphorIconsBold.factory,
  ),
  (
    'services',
    'خدمات',
    'فواتيرُ خدماتٍ بلا مخزون',
    PhosphorIconsBold.wrench,
  ),
  (
    'other',
    'أخرى',
    'نشاطٌ لا يطابق ما سبق',
    PhosphorIconsBold.dotsThreeCircle,
  ),
];

/// العملاتُ الستُّ — `BLOCKS` في التصميم، والمفتاحُ رمزُ ISO.
const _currencyChips = <(String, String)>[
  ('EGP', 'جنيه مصري'),
  ('SAR', 'ريال سعودي'),
  ('AED', 'درهم إماراتي'),
  ('JOD', 'دينار أردني'),
  ('KWD', 'دينار كويتي'),
  ('USD', 'دولار أمريكي'),
];

extension _SetupWizardCompanyInfoExt on _SetupWizardScreenState {
  // ═══════════════════════════════════════════════════════════════════════
  // STEP 1: Company Info
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildCompanyInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'معلومات الشركة',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'أدخل بيانات شركتك الأساسية — ستظهر في الفواتير والتقارير.',
          style: TextStyle(color: _mutedInk(context)),
        ),
        const SizedBox(height: 32),
        _buildTextField(
          controller: _companyNameController,
          label: 'اسم الشركة / المحل',
          hint: 'مثال: سوبر ماركت النيل',
          icon: PhosphorIconsBold.storefront,
          isRequired: true,
        ),
        const SizedBox(height: 20),
        _buildTextField(
          controller: _companyPhoneController,
          label: 'رقم الهاتف',
          hint: '01xxxxxxxxx',
          icon: PhosphorIconsBold.phone,
        ),
        const SizedBox(height: 20),
        _buildTextField(
          controller: _companyAddressController,
          label: 'العنوان',
          hint: 'القاهرة، مصر',
          icon: PhosphorIconsBold.mapPin,
        ),
        const SizedBox(height: 28),

        // ── نوع النشاط — بطاقاتٌ لا قائمةٌ منسدلة ────────────────────────
        //
        // التصميمُ يجعلها ستَّ بطاقاتٍ داخلَ هذه الخطوة. والقائمةُ المنسدلةُ
        // تُخفي الوصفَ الذي يفرّق بينها خلفَ نقرة — والفرقُ بين «تجزئة»
        // و«جملة وتوزيع» ليس بديهيّاً لمن يُنصّب أوّلَ مرّة.
        _stepFieldLabel('نوع النشاط'),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            // ⚠️ عمودان تحت ٧٢٠px: ثلاثةٌ تسحق البطاقةَ إلى عرضٍ يلتفّ فيه
            //    السطرُ الوصفيُّ حرفاً حرفاً.
            final cols = c.maxWidth < 720 ? 2 : 3;
            const gap = 12.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (id, title, sub, icon) in _businessTypeCards)
                  SizedBox(
                    width: w,
                    child: _choiceCard(
                      icon: icon,
                      title: title,
                      subtitle: sub,
                      selected: _businessType == id,
                      onTap: () => setState(() => _businessType = id),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 28),

        // ── العملة — رقاقاتٌ وتحذيرٌ ─────────────────────────────────────
        _stepFieldLabel('العملة'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (code, name) in _currencyChips)
              ChoiceChip(
                selected: _currency == code,
                onSelected: (_) => setState(() => _currency = code),
                label: Text('$name ($code)'),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      _currency == code ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // ⚠️ **تحذيرٌ لا زينة.** العملةُ تدخل كلَّ فاتورةٍ وكلَّ قيدٍ
        //    محاسبيّ، ولا يوجد في النظام تحويلُ أرصدةٍ بأثرٍ رجعيّ. فتبديلُها
        //    بعد أوّل فاتورةٍ يترك دفتراً بعملتَين لا يُفرَّق بينهما.
        _inlineNote(
          context,
          icon: PhosphorIconsBold.warningCircle,
          tone: AppColors.error,
          title: 'العملة قرار نهائي',
          body: 'تدخل كلَّ فاتورةٍ وكلَّ قيدٍ محاسبيّ، ولا تحويلَ بأثرٍ '
              'رجعيّ. تبديلُها بعد أوّل فاتورةٍ يترك دفتراً بعملتَين.',
        ),
      ],
    );
  }
}

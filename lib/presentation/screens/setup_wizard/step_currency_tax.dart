// خطوةُ «العملة والضريبة» — بندُ المالك ٦، الخطوة ٣.
//
// العملةُ (‏ومعها دقّتُها) والضريبةُ والفوترةُ الإلكترونيّة معاً: هي ما يدخل
// حسابَ كلِّ فاتورة. والعملةُ تضبط افتراضيّاً النسبةَ وبلدَ الفوترة (‏JOD ⇒
// ١٦٪ وJoFotara، EGP ⇒ ١٤٪ وETA) ما لم يغيّرهما المستخدمُ بيده.
part of '../setup_wizard_screen.dart';

/// النسبُ المسموحة — المعتمدةُ في الأردن (‏١٦ العامّة و١٠ و٥ و٤ و٢ و١ و٠)
/// ومصر (‏١٤ و٥ و٠). وقرارُ المالك: القائمةُ بالضبط ٠ · ١ · ٢ · ٤ · ٥ · ١٠ ·
/// ١٤ · ١٥ · ١٦ — وهي نفسُها سلّمُ `TaxRatePolicy.defaultAllowedRates`، فلا
/// تُختار في المعالج نسبةٌ يرفضها الصنفُ أو الاستيرادُ أو الـAPI.
const List<double> kSetupAllowedVatRates = [0, 1, 2, 4, 5, 10, 14, 15, 16];

extension _SetupWizardCurrencyTaxExt on _SetupWizardScreenState {
  Widget _buildCurrencyTaxStep() {
    final decimals = CurrencyInfo.fromCode(_currency).decimals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── العملة — رقاقاتٌ وتحذيرٌ ─────────────────────────────────────
        _stepFieldLabel(tr('العملة الأساسية')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (code, name) in _currencyChips)
              ChoiceChip(
                key: Key('setup_currency_$code'),
                selected: _currency == code,
                onSelected: (_) => _selectCurrency(code),
                label: Text('$name ($code)'),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      _currency == code ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          tr('الخانات العشرية: {p0} — تتبع العملة تلقائياً', {'p0': decimals}),
          key: const Key('setup_currency_decimals'),
          style: TextStyle(fontSize: 12, color: _mutedInk(context)),
        ),
        const SizedBox(height: 10),
        // ⚠️ **تحذيرٌ لا زينة.** العملةُ تدخل كلَّ فاتورةٍ وكلَّ قيدٍ
        //    محاسبيّ، ولا يوجد في النظام تحويلُ أرصدةٍ بأثرٍ رجعيّ. فتبديلُها
        //    بعد أوّل فاتورةٍ يترك دفتراً بعملتَين لا يُفرَّق بينهما.
        _inlineNote(
          context,
          icon: PhosphorIconsBold.warningCircle,
          tone: AppColors.error,
          title: tr('العملة قرار نهائي'),
          body: tr('تدخل كلَّ فاتورةٍ وكلَّ قيدٍ محاسبيّ، ولا تحويلَ بأثرٍ رجعيّ. تبديلُها بعد أوّل فاتورةٍ يترك دفتراً بعملتَين.'),
        ),
        const SizedBox(height: 20),

        // ── الضريبة ──
        _stepFieldLabel(tr('ضريبة القيمة المضافة')),
        const SizedBox(height: 4),
        SwitchListTile(
          key: const Key('setup_tax_enabled'),
          contentPadding: EdgeInsets.zero,
          title: Text(tr('تفعيل ضريبة القيمة المضافة')),
          subtitle: Text(tr('إضافة الضريبة تلقائياً على الفواتير')),
          value: _enableTax,
          activeThumbColor: AppColors.primary,
          onChanged: (v) => setState(() => _enableTax = v),
        ),
        if (_enableTax) ...[
          const SizedBox(height: 4),
          Text(
            tr('النسبة الافتراضية'),
            style: TextStyle(fontSize: 12.5, color: _mutedInk(context)),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final rate in kSetupAllowedVatRates)
                ChoiceChip(
                  key: Key('setup_vat_${rate.toInt()}'),
                  selected: _taxRate == rate,
                  onSelected: (_) => setState(() {
                    _taxRate = rate;
                    _taxRateTouched = true;
                  }),
                  label: Text('${rate.toInt()}%'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            key: const Key('setup_prices_include_tax'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('الأسعار شاملة الضريبة')),
            subtitle: Text(_pricesIncludeTax
                ? tr('سعر البيع المُدخَل يتضمّن الضريبة — المعتاد في البيع للمستهلك')
                : tr('الضريبة تُضاف فوق سعر البيع — المعتاد في الجملة')),
            value: _pricesIncludeTax,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() {
              _pricesIncludeTax = v;
              _pricesIncludeTaxTouched = true;
            }),
          ),
        ],
        const SizedBox(height: 16),

        // ── الفوترة الإلكترونيّة ──
        _stepFieldLabel(tr('الفوترة الإلكترونية')),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (country, title, sub) in _eInvoiceCards) ...[
              Expanded(
                child: _choiceCard(
                  key: Key('setup_einvoice_${country.name}'),
                  icon: country == SetupEInvoiceCountry.none
                      ? PhosphorIconsBold.prohibit
                      : PhosphorIconsBold.qrCode,
                  title: title,
                  subtitle: sub,
                  selected: _eInvoiceCountry == country,
                  onTap: () => setState(() {
                    _eInvoiceCountry = country;
                    _eInvoiceTouched = true;
                  }),
                ),
              ),
              if (country != SetupEInvoiceCountry.none)
                const SizedBox(width: 10),
            ],
          ],
        ),
      ],
    );
  }

  List<(SetupEInvoiceCountry, String, String)> get _eInvoiceCards => [
        (
          SetupEInvoiceCountry.jordan,
          tr('الأردن — JoFotara'),
          tr('نظام الفوترة الوطني الأردني'),
        ),
        (
          SetupEInvoiceCountry.egypt,
          tr('مصر — ETA'),
          tr('منظومة الفاتورة الإلكترونية المصرية'),
        ),
        (
          SetupEInvoiceCountry.none,
          tr('بدون'),
          tr('يمكن تفعيلها لاحقاً من الإعدادات'),
        ),
      ];
}

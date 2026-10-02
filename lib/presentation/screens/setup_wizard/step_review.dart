// خطوةُ «المراجعة والبدء» — بندُ المالك ٦، الخطوة الأخيرة.
//
// ملخّصٌ لكلّ اختيارٍ برابط «تعديل» يفتح خطوتَه (‏ويعود إليها بزرٍّ واحد)، ثمّ
// تشغيلُ الإعداد بمراحله ظاهرةً. وعند الفشل: المرحلةُ التي فشلت وسببُها، و
// «إعادة المحاولة من البداية» — ولا دخولَ إلى النظام على قاعدةٍ نصفِ مهيّأة.
part of '../setup_wizard_screen.dart';

extension _SetupWizardReviewExt on _SetupWizardScreenState {
  Widget _buildReviewStep() {
    final steps = _activeSteps;
    final running = _runStage != null;
    final result = _runResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (running || result != null) ...[
          _buildRunProgress(),
          const SizedBox(height: 14),
        ],
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth < 760 ? 1 : 2;
            const gap = 12.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final s in steps)
                  if (s != SetupStepIds.review)
                    SizedBox(width: w, child: _reviewCard(s)),
              ],
            );
          },
        ),
      ],
    );
  }

  /// بطاقةُ خطوةٍ في الملخّص.
  Widget _reviewCard(int step) {
    final meta = kSetupSteps[step];
    final theme = Theme.of(context);
    final rows = _reviewRows(step);
    return Container(
      key: Key('setup_review_card_$step'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(meta?.icon ?? PhosphorIconsBold.circle,
                  size: 17, color: _brandInk(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  meta?.label ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                key: Key('setup_review_edit_$step'),
                onPressed: _runStage != null ? null : () => _editFromReview(step),
                icon: const Icon(PhosphorIconsBold.pencilSimple, size: 14),
                label: Text(tr('تعديل')),
              ),
            ],
          ),
          const Divider(height: 10),
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      k,
                      style:
                          TextStyle(fontSize: 12, color: _mutedInk(context)),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      v.isEmpty ? '—' : v,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _yesNo(bool v) => v ? tr('نعم') : tr('لا');

  String get _modeLabel =>
      _modeCards.firstWhere((m) => m.$1 == _networkMode).$2;

  /// صفوفُ الملخّص لكلّ خطوة — ما سيُكتَب لا ما في الحقول وحدَها.
  List<(String, String)> _reviewRows(int step) {
    switch (step) {
      case SetupStepIds.welcome:
        return [
          (
            tr('اللغة'),
            I18nCatalog.activeLocale.languageCode == 'en' ? 'English' : 'العربية',
          ),
          (tr('طريقة التشغيل'), _modeLabel),
          (
            tr('نمط الإدخال'),
            _touchMode ? tr('جهاز لمسي / POS') : tr('جهاز عادي (لوحة مفاتيح)'),
          ),
        ];
      case SetupStepIds.company:
        final profile = BusinessProfileCatalog.all()
            .where((m) => m.profile == _selectedProfile)
            .map((m) => m.arabicName)
            .firstOrNull;
        final type = _businessTypeCards
            .where((c) => c.$1 == _businessType)
            .map((c) => c.$2)
            .firstOrNull;
        return [
          (tr('اسم الشركة'), _companyNameController.text.trim()),
          (tr('الاسم بالإنجليزية'), _companyNameEnController.text.trim()),
          (tr('الرقم الضريبي'), _taxNumberController.text.trim()),
          (tr('السجل التجاري'), _commercialRegisterController.text.trim()),
          (tr('رقم الهاتف'), _companyPhoneController.text.trim()),
          (tr('العنوان'), _companyAddressController.text.trim()),
          (tr('الشعار'), _logo != null ? tr('تم اختيار الشعار') : ''),
          (tr('ملف النشاط'), profile ?? _selectedProfile.name),
          (tr('نوع النشاط'), type ?? _businessType),
        ];
      case SetupStepIds.currencyTax:
        final country = _eInvoiceCards
            .firstWhere((c) => c.$1 == _eInvoiceCountry)
            .$2;
        return [
          (tr('العملة الأساسية'), _currency),
          (
            tr('الخانات العشرية'),
            '${CurrencyInfo.fromCode(_currency).decimals}',
          ),
          (tr('ضريبة القيمة المضافة'), _enableTax ? '${_taxRate.toInt()}%' : tr('لا')),
          if (_enableTax)
            (tr('الأسعار شاملة الضريبة'), _yesNo(_pricesIncludeTax)),
          (tr('الفوترة الإلكترونية'), country),
        ];
      case SetupStepIds.branchAndMode:
        if (_networkMode == NetworkMode.client) {
          final branch = _syncedBranches
              .where((b) => b.id == _selectedBranchId)
              .map((b) => b.name)
              .firstOrNull;
          return [
            (tr('عنوان السيرفر'), _serverAddressController.text.trim()),
            (tr('فرع هذا الجهاز'), branch ?? tr('غير محدد')),
          ];
        }
        if (_networkMode == NetworkMode.mirror) {
          return [
            (tr('عنوان HQ-Server'), _serverAddressController.text.trim()),
            (
              tr('المصافحة'),
              MirrorState.instance.isConfigured ? tr('تمت') : tr('لم تتم'),
            ),
          ];
        }
        return [
          (tr('اسم الفرع'), _branchNameController.text.trim()),
          (tr('رمز الفرع'), _branchCodeController.text.trim()),
          (tr('عنوان الفرع'), _branchAddressController.text.trim()),
          (tr('اسم المخزن'), _warehouseNameController.text.trim()),
        ];
      case SetupStepIds.cashBanks:
        return [
          (tr('صندوق الكاشير'), _cashBoxNameController.text.trim()),
          (tr('الحساب البنكي'), _bankSafeNameController.text.trim()),
          (tr('اسم البنك'), _bankNameController.text.trim()),
          (tr('رقم الحساب / IBAN'), _bankAccountController.text.trim()),
          (tr('صندوق تحويل كليك'), _cliqSafeNameController.text.trim()),
        ];
      case SetupStepIds.chartOfAccounts:
        return [
          (tr('دليل الحسابات'), tr('الدليل القياسي (IFRS)')),
        ];
      case SetupStepIds.users:
        return [
          if (_asksAdminPassword)
            (
              tr('كلمة مرور المدير'),
              _adminPasswordOk ? tr('تم ضبطها') : tr('لم تُضبط'),
            ),
          (
            tr('كلمة مرور المطوّر'),
            _developerPasswordOk ? tr('تم ضبطها') : tr('لم تُضبط'),
          ),
          if (_networkMode != NetworkMode.server)
            (
              tr('مستخدمون إضافيون'),
              _wizardUsers.isEmpty
                  ? tr('لا')
                  : _wizardUsers
                      .map((u) => '${u['displayName']} (${u['roleName'] ?? ''})')
                      .join(tr('، ')),
            ),
        ];
      case SetupStepIds.products:
        return [
          (
            tr('المنتجات الأولى'),
            _sampleProducts.isEmpty
                ? tr('لا')
                : _sampleProducts.map((p) => p['name']).join(tr('، ')),
          ),
        ];
      case SetupStepIds.postgres:
        return [
          (tr('المضيف (Host)'), _pgHostController.text.trim()),
          (tr('اسم القاعدة'), _pgDatabaseController.text.trim()),
          (tr('اختبار الاتصال'), _pgConnectionOk ? tr('تم') : tr('لم يتم')),
        ];
      case SetupStepIds.provisioning:
        return [
          (tr('تهيئة القاعدة'), _provisioningDone ? tr('تمت') : tr('لم تتم')),
        ];
      default:
        return const [];
    }
  }

  /// مراحلُ التشغيل — منجزةٌ ✓ وجاريةٌ ⟳ وفاشلةٌ ✗ بسببها.
  Widget _buildRunProgress() {
    final result = _runResult;
    final failed = result != null && !result.ok ? result.failedStage : null;
    final current = _runStage;
    final theme = Theme.of(context);
    return Container(
      key: const Key('setup_run_progress'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(
          color: failed != null ? AppColors.error : theme.dividerColor,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failed != null ? tr('تعذّر إكمال الإعداد') : tr('جاري إعداد النظام…'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: failed != null ? AppColors.error : null,
            ),
          ),
          const SizedBox(height: 8),
          for (final s in SetupRunStage.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: s == current
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : Icon(
                            s == failed
                                ? PhosphorIconsBold.xCircle
                                : _stageDone(s, current, failed, result)
                                    ? PhosphorIconsBold.checkCircle
                                    : PhosphorIconsBold.circle,
                            size: 18,
                            color: s == failed
                                ? AppColors.error
                                : _stageDone(s, current, failed, result)
                                    ? AppColors.success
                                    : _mutedInk(context),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            s == current || s == failed ? FontWeight.w800 : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (failed != null) ...[
            const SizedBox(height: 10),
            Container(
              key: const Key('setup_run_error'),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('فشلت مرحلة: {p0}', {'p0': failed.label}),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    result?.error ?? '',
                    style: const TextStyle(fontSize: 12, color: AppColors.error),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr('لم يُعلَّم الإعداد مكتملاً — أصلح السبب ثم أعد المحاولة من البداية.'),
                    style: TextStyle(fontSize: 12, color: _mutedInk(context)),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: OutlinedButton.icon(
                      key: const Key('setup_retry'),
                      onPressed: _isSaving ? null : _finishSetup,
                      icon: const Icon(PhosphorIconsBold.arrowsClockwise,
                          size: 16),
                      label: Text(tr('إعادة المحاولة من البداية')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _stageDone(
    SetupRunStage s,
    SetupRunStage? current,
    SetupRunStage? failed,
    SetupRunResult? result,
  ) {
    if (result?.ok == true) return true;
    final pivot = current ?? failed;
    if (pivot == null) return false;
    return s.index < pivot.index;
  }
}

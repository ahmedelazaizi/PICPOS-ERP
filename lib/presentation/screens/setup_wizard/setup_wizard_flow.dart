// تدفّقُ المعالج — التحقّقُ لكلّ خطوة والتنقّلُ ولوحةُ المفاتيح والتشغيل.
//
// ═══ بندُ المالك ٦ ═══
//
// • **«التالي» محروسٌ بالتحقّق**: الحقولُ الإلزاميّةُ لكلّ خطوةٍ هنا وحدَها
//   (`_isStepValid`)، والعمودُ الجانبيُّ ورابطُ «تعديل» في المراجعة يمرّان
//   بها أيضاً — فلا طريقَ إلى المراجعة يتخطّى حقلاً إلزاميّاً.
// • **Enter = التالي** — إلّا على زرٍّ أو رقاقة (‏هناك Enter يضغطها)، وفي
//   نموذجَي «إضافة مستخدم» و«إضافة منتج» يُضيف بدل أن يغادر الخطوة.
// • **التشغيلُ** عبر `SetupFinishRunner` — والفشلُ يبقى على المراجعة بمرحلته
//   وسببه، ويُعاد من البداية.
part of '../setup_wizard_screen.dart';

/// حبرُ العلامة للنصّ والأيقونات — يفتح في الوضع الداكن لـPicPos.
///
/// ⚠️ UralCash يبقى على `AppColors.primary` كما كان (‏تنسيقٌ واعٍ بالعلامة لا
/// تبديلُ سلوك).
Color _brandInk(BuildContext context) =>
    Brand.isPicPos ? context.picposBrandInk : AppColors.primary;

/// قوّةُ كلمة المرور ٠–٣ — تلميحٌ لا شرط (‏الشرطُ الطولُ وحدَه).
int _passwordStrength(String p) {
  if (p.length < 6) return 0;
  var score = 1;
  if (p.length >= 10) score++;
  final mixed = RegExp(r'[0-9]').hasMatch(p) &&
      RegExp(r'[A-Za-z\u0600-\u06FF]').hasMatch(p);
  if (mixed) score++;
  return score.clamp(0, 3);
}

/// أدنى طولٍ لكلمة مرور المدير.
const int _kAdminPasswordMin = 6;

extension _SetupWizardFlowExt on _SetupWizardScreenState {
  bool get _isStandalone => _networkMode == NetworkMode.standalone;

  /// المديرُ المحلّيُّ يُضبط هنا في المستقلّ وحدَه — العميلُ يأخذ مستخدميه من
  /// الخادم، والخادمُ والمرآةُ قاعدتُهما على السيرفر.
  bool get _asksAdminPassword => _isStandalone;

  bool get _adminPasswordOk {
    final p = _adminPasswordController.text;
    return p.length >= _kAdminPasswordMin &&
        p != 'admin' &&
        p == _adminPasswordConfirmController.text;
  }

  bool get _developerPasswordOk {
    final pwd = _developerPasswordController.text.trim();
    final cnf = _developerPasswordConfirmController.text.trim();
    return pwd.length >= 4 && pwd == cnf;
  }

  /// هل الخطوةُ مكتملةُ الحقول الإلزاميّة؟
  bool _isStepValid(int step) {
    switch (step) {
      case SetupStepIds.company:
        // العميلُ يأخذ بيانات الشركة من الخادم بالمزامنة.
        return _networkMode == NetworkMode.client ||
            _companyNameController.text.trim().isNotEmpty;
      case SetupStepIds.branchAndMode:
        // المرآةُ لا تُكمل قبل المصافحة مع HQ-Server (‏كما كان).
        if (_networkMode == NetworkMode.mirror) {
          return MirrorState.instance.isConfigured;
        }
        if (_networkMode == NetworkMode.client) return true;
        // ورمزُ الفرع ≤ ١٠ — حدُّ عمود `branches.code`، وتجاوزُه يُسقط
        // التشغيلَ في منتصفه بدل أن يُمنع هنا.
        return _branchNameController.text.trim().isNotEmpty &&
            _warehouseNameController.text.trim().isNotEmpty &&
            _branchCodeController.text.trim().length <= 10;
      case SetupStepIds.users:
        return _developerPasswordOk &&
            (!_asksAdminPassword || _adminPasswordOk);
      case SetupStepIds.postgres:
        return _pgConnectionOk;
      case SetupStepIds.provisioning:
        return _provisioningDone;
      default:
        return true;
    }
  }

  /// كلُّ خطوات المسار قبل [step] صحيحة؟
  bool _allValidBefore(int step) {
    final order = _activeSteps;
    final end = order.indexOf(step);
    for (var i = 0; i < end; i++) {
      if (!_isStepValid(order[i])) return false;
    }
    return true;
  }

  /// قفزٌ من العمود الجانبيّ: الخلفُ مفتوحٌ دائماً، والأمامُ حين تصحّ كلُّ
  /// خطوةٍ قبله.
  void _jumpTo(int step) {
    if (!_activeSteps.contains(step)) return;
    final forward = _activeSteps.indexOf(step) > _activeStepIndex;
    if (forward && !_allValidBefore(step)) {
      AppToast.show(
        context,
        tr('أكمل الحقول المطلوبة في الخطوات السابقة أولاً'),
        type: ToastType.warning,
      );
      return;
    }
    setState(() {
      _returnToReview = false;
      _currentStep = step;
    });
  }

  /// رابطُ «تعديل» في المراجعة — يفتح الخطوةَ ويُبقي طريقَ العودة إليها.
  void _editFromReview(int step) {
    setState(() {
      _currentStep = step;
      _returnToReview = true;
    });
  }

  void _goNext() {
    if (!_canAdvance()) return;
    setState(() {
      if (_returnToReview && _allValidBefore(SetupStepIds.review)) {
        _currentStep = SetupStepIds.review;
      } else {
        _currentStep = _nextStep;
      }
      _returnToReview = false;
    });
  }

  /// «تخطي هذه الخطوة» — يمضي **بلا** تعديلات الخطوة.
  void _skipOptionalStep() {
    setState(() {
      if (_currentStep == SetupStepIds.products) {
        _sampleProducts.clear();
        _productNameController.clear();
        _productPriceController.clear();
        _productCostController.clear();
      } else if (_currentStep == SetupStepIds.cashBanks) {
        for (final e in _safeOriginals.entries) {
          e.key.text = e.value;
        }
      }
    });
    _goNext();
  }

  /// Enter = التالي.
  ///
  /// ⚠️ **لا على زرٍّ ولا رقاقة**: هذا المستمعُ أقربُ إلى البؤرة من
  /// `Shortcuts` التطبيق، فلو أخذ Enter هناك لما ضُغط زرٌّ بلوحة المفاتيح
  /// أبداً. فلا يعمل إلّا والبؤرةُ في حقلِ نصٍّ أو على الشاشة نفسِها.
  KeyEventResult _onWizardKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final focus = FocusManager.instance.primaryFocus;
    final inText = focus?.context?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
    if (focus != null && focus != node && !inText) {
      return KeyEventResult.ignored;
    }
    // نموذجا الإضافة: Enter يُضيف الصفَّ المكتوب ولا يغادر الخطوة.
    if (_currentStep == SetupStepIds.users &&
        _userUsernameController.text.trim().isNotEmpty) {
      _addWizardUser();
      return KeyEventResult.handled;
    }
    if (_currentStep == SetupStepIds.products &&
        _productNameController.text.trim().isNotEmpty) {
      _addProduct();
      return KeyEventResult.handled;
    }
    if (_isLastStep || _runStage != null || !_canAdvance()) {
      return KeyEventResult.ignored;
    }
    _goNext();
    return KeyEventResult.handled;
  }

  // ── افتراضاتٌ معقولةٌ تتبع الاختيار — ولا تدوس ما اختاره المستخدمُ بيده ──

  String _businessTypeForProfile(BusinessProfile p) => switch (p) {
        BusinessProfile.restaurant || BusinessProfile.cafe => 'restaurant',
        BusinessProfile.commercial => 'wholesale',
        _ => 'retail',
      };

  void _selectProfile(BusinessProfile p) {
    setState(() {
      _selectedProfile = p;
      if (!_businessTypeTouched) _businessType = _businessTypeForProfile(p);
      // الجملةُ تُسعَّر قبل الضريبة عادةً، والبيعُ للمستهلك شاملاً لها.
      if (!_pricesIncludeTaxTouched) {
        _pricesIncludeTax = p != BusinessProfile.commercial;
      }
    });
  }

  void _selectCurrency(String code) {
    setState(() {
      _currency = code;
      if (!_taxRateTouched) {
        if (code == 'JOD') _taxRate = 16.0;
        if (code == 'EGP') _taxRate = 14.0;
      }
      if (!_eInvoiceTouched) {
        _eInvoiceCountry = switch (code) {
          'JOD' => SetupEInvoiceCountry.jordan,
          'EGP' => SetupEInvoiceCountry.egypt,
          _ => SetupEInvoiceCountry.none,
        };
      }
    });
  }

  /// اللغةُ تُطبَّق فوراً وتُحفَظ افتراضيّاً للجهاز (`device_locale`).
  Future<void> _setLanguage(String code) async {
    final locale = localeForCode(code);
    I18nCatalog.setLocale(locale);
    setState(() {});
    try {
      await ref.read(userLocaleProvider.notifier).setLocale(locale);
      await UserLocalePreference.saveDevice(
        ref.read(settingsRepositoryProvider),
        locale,
      );
    } catch (e) {
      debugPrint('[SetupWizard] locale save failed: $e');
    }
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    if (mounted) setState(() => _logo = bytes);
  }

  /// يقرأ الصناديقَ المزروعةَ مرّةً واحدةً — أسماؤها الحاليّةُ قيمُ الحقول.
  void _ensureSafesLoaded() {
    _safesLoad ??= () async {
      final repo = ref.read(treasuryRepositoryProvider);
      Future<void> fill(
        String type,
        TextEditingController name, {
        TextEditingController? bank,
        TextEditingController? account,
      }) async {
        final s = await repo.getDefaultSafeByType(type);
        if (s == null) return;
        name.text = s.name;
        _safeOriginals[name] = s.name;
        if (bank != null) {
          bank.text = s.bankName ?? '';
          _safeOriginals[bank] = bank.text;
        }
        if (account != null) {
          account.text = s.accountNumber ?? '';
          _safeOriginals[account] = account.text;
        }
      }

      try {
        await fill('cash', _cashBoxNameController);
        await fill(
          'bank',
          _bankSafeNameController,
          bank: _bankNameController,
          account: _bankAccountController,
        );
        await fill('click', _cliqSafeNameController);
      } catch (e) {
        debugPrint('[SetupWizard] safes load failed: $e');
      }
    }();
  }

  SetupDraft _buildDraft() {
    final cashVisited = _isStandalone && _safesLoad != null;
    return SetupDraft(
      profile: _selectedProfile,
      developerPassword: _developerPasswordController.text,
      companyName: _companyNameController.text,
      companyPhone: _companyPhoneController.text,
      companyAddress: _companyAddressController.text,
      businessType: _businessType,
      currency: _currency,
      branchName: _branchNameController.text,
      warehouseName: _warehouseNameController.text,
      products: _sampleProducts,
      users: _wizardUsers,
      enableTax: _enableTax,
      taxRate: _taxRate,
      networkMode: _networkMode,
      serverPortText: _serverPortController.text,
      selectedClientBranchId: _selectedBranchId,
      syncedBranches: _syncedBranches,
      companyNameEn: _companyNameEnController.text,
      taxNumber: _taxNumberController.text,
      commercialRegister: _commercialRegisterController.text,
      logo: _logo,
      branchCode: _branchCodeController.text,
      branchAddress: _branchAddressController.text,
      pricesIncludeTax: _pricesIncludeTax,
      eInvoiceCountry: _eInvoiceCountry,
      cashBoxName: cashVisited ? _cashBoxNameController.text : null,
      bankSafeName: cashVisited ? _bankSafeNameController.text : null,
      bankName: cashVisited ? _bankNameController.text : null,
      bankAccountNumber: cashVisited ? _bankAccountController.text : null,
      cliqSafeName: cashVisited ? _cliqSafeNameController.text : null,
      adminPassword: _asksAdminPassword ? _adminPasswordController.text : null,
    );
  }

  /// يشغّل الإعدادَ بمراحله — وعند الفشل يبقى على المراجعة بالسبب.
  ///
  /// ⚠️ **لا متابعةَ على قاعدةٍ نصفِ مهيّأة**: `setup_completed` آخرُ ما يُكتَب
  /// في المشغّل، فالفشلُ قبله يُبقي المعالجَ ظاهراً، والإعادةُ من البداية.
  Future<void> _finishSetup() async {
    if (!_allValidBefore(SetupStepIds.review)) {
      AppToast.show(
        context,
        tr('أكمل الحقول المطلوبة في الخطوات السابقة أولاً'),
        type: ToastType.warning,
      );
      return;
    }
    setState(() {
      _isSaving = true;
      _runResult = null;
      _runStage = SetupRunStage.settings;
    });
    final result = await _runner.run(
      _buildDraft(),
      ref.read(setupPersistenceProvider),
      onStage: (s) {
        if (mounted) setState(() => _runStage = s);
      },
    );
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _runStage = null;
      _runResult = result;
    });
    if (!result.ok) return;

    // ⚠️ كان يُعرَض فورَ الفشل؛ والمستخدمُ يرى الآن القائمةَ كاملةً مرّةً.
    if (result.failedUsers.isNotEmpty) {
      AppToast.show(
        context,
        tr('تعذّر إنشاءُ {p0} مستخدم:\n{p1}', {
          'p0': result.failedUsers.length,
          'p1': result.failedUsers.join('\n'),
        }),
        type: ToastType.error,
      );
    }
    if (result.warnings.isEmpty) {
      AppToast.show(
        context,
        tr('تم إعداد النظام بنجاح! مرحباً بك 🎉'),
        type: ToastType.success,
      );
    } else {
      AppToast.show(
        context,
        tr('اكتمل الإعداد، لكن مع تحذيرات: {p0}. يُفضَّل إعادة تشغيل التطبيق.',
            {'p0': result.warnings.join(tr('، '))}),
        type: ToastType.warning,
      );
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen()),
      (r) => false,
    );
  }
}

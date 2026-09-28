part of '../setup_wizard_screen.dart';

// ═══════════════════════════════════════════════════════════════════════
// Supporting types for the provisioning step
// ═══════════════════════════════════════════════════════════════════════

/// Per-row state for the provisioning progress list.
enum _ProvisionState { pending, running, ok, failed }

class _ProvisionStep {
  final String label;
  _ProvisionState state = _ProvisionState.pending;
  String? detail;
  _ProvisionStep(this.label);
}

extension _SetupWizardProvisioningExt on _SetupWizardScreenState {
  // ═══════════════════════════════════════════════════════════════════════
  // STEP 5: PostgreSQL config (server mode only)
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildPgConfigStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'إعدادات PostgreSQL',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'أدخل بيانات السيرفر. سيتم اختبار الاتصال قبل الانتقال للخطوة التالية.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildTextField(
                controller: _pgHostController,
                label: 'المضيف (Host)',
                hint: 'localhost أو 192.168.1.50',
                icon: PhosphorIconsBold.globeSimple,
                isRequired: true,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: _buildTextField(
                controller: _pgPortController,
                label: 'المنفذ',
                hint: '5432',
                icon: PhosphorIconsBold.hash,
                isNumber: true,
                isRequired: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _pgDatabaseController,
          label: 'اسم القاعدة',
          hint: Brand.pgIdentifier,
          icon: PhosphorIconsBold.database,
          isRequired: true,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _pgUserController,
                label: 'اسم المستخدم',
                hint: 'postgres',
                icon: PhosphorIconsBold.user,
                isRequired: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _pgPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور *',
                  prefixIcon: const Icon(PhosphorIconsBold.lock, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _pgTestInProgress ? null : _testPgConnection,
              icon: _pgTestInProgress
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(PhosphorIconsBold.plugsConnected, size: 18),
              label: Text(
                  _pgTestInProgress ? 'جاري الاختبار...' : 'اختبار الاتصال'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
              ),
            ),
            const SizedBox(width: 16),
            if (_pgTestMessage != null)
              Expanded(
                child: Text(
                  _pgTestMessage!,
                  style: TextStyle(
                    color: _pgConnectionOk
                        ? AppColors.success
                        : AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (!_pgConnectionOk)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(PhosphorIconsBold.warning,
                    color: AppColors.warning, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'اختبر الاتصال بنجاح قبل الانتقال لخطوة التهيئة.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _testPgConnection() async {
    setState(() {
      _pgTestInProgress = true;
      _pgTestMessage = null;
      _pgConnectionOk = false;
    });
    try {
      final cfg = _currentPgConfig();
      final err = await testPostgresConnection(cfg);
      if (!mounted) return;
      setState(() {
        _pgTestInProgress = false;
        if (err == null) {
          _pgConnectionOk = true;
          _pgTestMessage = '✅ تم الاتصال بنجاح';
        } else {
          _pgConnectionOk = false;
          _pgTestMessage = '❌ فشل الاتصال: $err';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pgTestInProgress = false;
        _pgConnectionOk = false;
        _pgTestMessage = '❌ خطأ: $e';
      });
    }
  }

  PostgresConfig _currentPgConfig() => PostgresConfig(
        host: _pgHostController.text.trim(),
        port: int.tryParse(_pgPortController.text.trim()) ?? 5432,
        database: _pgDatabaseController.text.trim(),
        username: _pgUserController.text.trim(),
        password: _pgPasswordController.text,
      );

  // ═══════════════════════════════════════════════════════════════════════
  // STEP 6: Provisioning (server mode only)
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildProvisioningStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'تهيئة قاعدة البيانات',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'سيتم إنشاء كل الجداول وزرع البيانات الأساسية تلقائياً. لا تُغلق التطبيق حتى تكتمل العملية.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (int i = 0; i < _provisionSteps.length; i++)
                  _buildProvisionRow(_provisionSteps[i]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (_provisioningError != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(PhosphorIconsBold.xCircle,
                    color: AppColors.error, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    _provisioningError!,
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            if (!_provisioningDone)
              ElevatedButton.icon(
                onPressed: _provisioningInProgress ? null : _runProvisioning,
                icon: _provisioningInProgress
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(_provisioningError != null
                        ? PhosphorIconsBold.arrowsClockwise
                        : PhosphorIconsBold.play),
                label: Text(_provisioningInProgress
                    ? 'جاري التنفيذ...'
                    : _provisioningError != null
                        ? 'إعادة المحاولة'
                        : 'بدء التهيئة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                ),
              ),
            if (_provisioningDone) ...[
              ElevatedButton.icon(
                onPressed: _finishServerSetup,
                icon: const Icon(PhosphorIconsBold.checkCircle),
                label: const Text('إكمال وإعادة تشغيل التطبيق'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildProvisionRow(_ProvisionStep step) {
    IconData icon;
    Color color;
    switch (step.state) {
      case _ProvisionState.pending:
        icon = PhosphorIconsBold.circle;
        color = AppColors.textMuted;
        break;
      case _ProvisionState.running:
        icon = PhosphorIconsBold.spinner;
        color = AppColors.primary;
        break;
      case _ProvisionState.ok:
        icon = PhosphorIconsBold.checkCircle;
        color = AppColors.success;
        break;
      case _ProvisionState.failed:
        icon = PhosphorIconsBold.xCircle;
        color = AppColors.error;
        break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: step.state == _ProvisionState.running
                ? const CircularProgressIndicator(strokeWidth: 2)
                : Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              step.label,
              style: TextStyle(
                color: color,
                fontWeight: step.state == _ProvisionState.running
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
          if (step.detail != null)
            Text(
              step.detail!,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Future<void> _runProvisioning() async {
    setState(() {
      _provisioningInProgress = true;
      _provisioningError = null;
      for (final s in _provisionSteps) {
        s.state = _ProvisionState.pending;
        s.detail = null;
      }
    });

    AppDatabase? db;
    try {
      // Step 1: test connection
      await _runProvisionStep(0, () async {
        final err = await testPostgresConnection(_currentPgConfig());
        if (err != null) {
          throw Exception('فشل الاتصال: $err');
        }
      });

      // Open the actual Drift-wrapped PG connection for steps 2–5.
      final cfg = _currentPgConfig();
      final executor = openPostgresConnection(cfg);
      db = AppDatabase.withExecutor(executor, isPostgres: true);

      // Step 2: create all tables (m.createAll via beforeOpen flow)
      await _runProvisionStep(1, () async {
        // Touch the database to trigger onCreate / beforeOpen.
        await db!.customSelect('SELECT 1').get();
      });

      // Step 3: roles + branch + warehouse + units + safes + settings + delivery parties
      // Steps 4, 5 are part of the same atomic seeder call, but we drive the
      // UI by calling sub-helpers directly. For simplicity we run the full
      // atomic seeder once (beforeOpen may have already run it — that's fine,
      // it's idempotent) and then verify.
      SeedResult? result;
      await _runProvisionStep(2, () async {
        result = await db!.seedInitialDataPostgresAtomic();
      });

      // Step 4: accounts — already inserted in the atomic seed, just report.
      await _runProvisionStep(3, () async {
        if (result == null) throw Exception('الخطوة السابقة لم تُنفذ');
        _provisionSteps[3].detail = '${result!.accounts} حساب جديد';
      });

      // Step 5: fiscal year
      await _runProvisionStep(4, () async {
        if (result == null) throw Exception('الخطوة السابقة لم تُنفذ');
        _provisionSteps[4].detail = result!.fiscalYear > 0
            ? 'تم إنشاء السنة المالية'
            : 'موجودة مسبقاً';
      });

      // Step 6: verify baseline
      await _runProvisionStep(5, () async {
        final check = await db!.verifyPostgresBaseline();
        _provisionSteps[5].detail =
            '${check.counts['accounts'] ?? 0} حساب، '
            '${check.counts['roles'] ?? 0} أدوار';
        if (!check.ok) {
          throw Exception('باقية جداول ناقصة: ${check.missing.join(', ')}');
        }
      });

      if (!mounted) return;
      setState(() {
        _provisioningInProgress = false;
        _provisioningDone = true;
      });
    } catch (e, st) {
      debugPrint('[Provisioning] FAILED: $e\n$st');
      if (!mounted) return;
      // Mark first non-ok step as failed if we didn't reach the catch inside
      // _runProvisionStep.
      for (final s in _provisionSteps) {
        if (s.state == _ProvisionState.running) {
          s.state = _ProvisionState.failed;
          break;
        }
      }
      setState(() {
        _provisioningInProgress = false;
        _provisioningError = e.toString();
      });
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
  }

  /// Runs a single provisioning step, marking it running → ok/failed and
  /// updating the UI between states.
  Future<void> _runProvisionStep(int index, Future<void> Function() body) async {
    setState(() {
      _provisionSteps[index].state = _ProvisionState.running;
    });
    try {
      await body();
      if (!mounted) return;
      setState(() {
        _provisionSteps[index].state = _ProvisionState.ok;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _provisionSteps[index].state = _ProvisionState.failed;
          _provisionSteps[index].detail = e.toString();
        });
      }
      rethrow;
    }
  }

  /// Invoked when the user clicks "إكمال وإعادة تشغيل التطبيق" on the
  /// provisioning screen. Persists the PG config, switches the runtime DB
  /// mode, marks setup complete, and exits so the next launch reads the new
  /// config cleanly (see plan Session 3).
  Future<void> _finishServerSetup() async {
    try {
      final cfg = _currentPgConfig();
      await cfg.save();
      await PostgresConfig.saveMode(DatabaseMode.postgres);
      // Arm the boot-gate: main.dart's startup flow requires this flag to
      // be true before it attempts a PG connection. Without it, a saved
      // `deployment_mode=postgres` alone won't trigger PG — the app
      // defaults to SQLite. We set the flag here, at the end of the
      // provisioning step, because at this point the server has been
      // tested + schema created + baseline verified successfully.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('pg_provisioned_ok', true);
      } catch (_) {}

      // Company info + network mode still need persisting.
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final companyName = _companyNameController.text.trim();
      if (companyName.isNotEmpty) {
        // Settings repo writes to the CURRENT (SQLite) DB. That's fine — the
        // PG DB already has `settings` seeded with default values. On restart
        // the app reads from PG so the company_name written here is only for
        // the bootstrap SQLite; we also write it via direct PG insert below
        // so the user sees it after restart.
        await settingsRepo.saveSetting('company_name', companyName);
      }
      // ─── Spec 125 (US1): atomic deployment-mode commit ─────────────
      // Replaces the previous direct saveSetting('network_mode', 'server')+setMode
      // pair. Routes through DeploymentModeCommitter so the server finish
      // path is symmetric with standalone/client/mirror in _finishSetup,
      // and writes go through the single owner-of-network_mode (FR-004).
      // Note: setup_completed is still written here (not owned by committer).
      final dbForCommit = ref.read(databaseProvider);
      final committerServer = DeploymentModeCommitter(db: dbForCommit);
      final serverContract = committerServer.buildContract(
        target: NetworkMode.server,
        serverPort: int.tryParse(_serverPortController.text) ?? 8080,
      );
      final serverCommitResult =
          await committerServer.commit(contract: serverContract);
      if (serverCommitResult is CommitFailed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(serverCommitResult.reasonAr),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 6),
            ),
          );
        }
        return;
      }
      await settingsRepo.saveSetting('setup_completed', 'true');

      // Also persist company_name into the freshly provisioned PG DB so the
      // user sees their entered value after restart.
      try {
        final executor = openPostgresConnection(cfg);
        final pgDb = AppDatabase.withExecutor(executor, isPostgres: true);
        if (companyName.isNotEmpty) {
          await pgDb.customStatement(
            "UPDATE settings SET value = ? WHERE key = 'company_name'",
            [companyName],
          );
        }
        // UPDATE-then-INSERT-if-zero: avoids `ON CONFLICT (key)` which would
        // raise 42P10 on a PG install whose `settings` table was created by
        // an older migration without the PK constraint emitted correctly.
        // This pattern is target-free and works on any dialect.
        await pgDb.customStatement(
          "UPDATE settings SET value = 'true' WHERE key = 'setup_completed'",
        );
        final existing = await pgDb.customSelect(
          "SELECT 1 AS x FROM settings WHERE key = 'setup_completed'",
        ).get();
        if (existing.isEmpty) {
          await pgDb.customStatement(
            "INSERT INTO settings (key, value) VALUES ('setup_completed', 'true')",
          );
        }
        await pgDb.customStatement(
          "UPDATE settings SET value = 'server' WHERE key = 'network_mode'",
        );
        final existingNetworkMode = await pgDb.customSelect(
          "SELECT 1 AS x FROM settings WHERE key = 'network_mode'",
        ).get();
        if (existingNetworkMode.isEmpty) {
          await pgDb.customStatement(
            "INSERT INTO settings (key, value) VALUES ('network_mode', 'server')",
          );
        }
        await pgDb.close();
      } catch (e) {
        debugPrint('[SetupWizard] persist company_name to PG: $e');
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('اكتملت التهيئة'),
          content: const Text(
            'تم حفظ إعدادات السيرفر بنجاح.\n'
            'سيتم إغلاق التطبيق الآن — افتحه مجدداً ليتصل بـ PostgreSQL '
            'وتظهر شاشة POS جاهزة للعمل.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Exit so main.dart re-reads dbMode on next launch.
                //
                // #B2 (cart-close guard, 2026-08-17): مخرجُ إنهاءٍ خامسٌ،
                // مستثنىً عمداً من `shouldBlockAppCloseForCart`. السببُ
                // مُتحقَّقٌ لا مفترَض: هذه الشاشةُ (`SetupWizardScreen`)
                // لا تُبنى إلا من `_SetupGate` في `main.dart`، وهي الموضعُ
                // الوحيدُ في `lib/` الذي يُنشئها (بحثٌ نصّيٌّ عن
                // `SetupWizardScreen(` أكّد ذلك). `_SetupGate` نفسُها لا
                // تُعرَض إلا بعد المصادقة **و**`setup_completed != 'true'`؛
                // وكلُّ نقاط الكتابة الأخرى لِـ`setup_completed=''`
                // (‏`main.dart` — مسارا `onResetWizard` في شاشة الفشل
                // القاتل) تقع **قبل** `runApp()` الشجرةِ العاديّة وتتطلّب
                // إعادةَ تشغيل التطبيق فعلياً (معلَّقٌ في تعليق الكود
                // هناك: «restart app to re-run wizard»). و`cartControllerProvider`
                // حالةٌ في الذاكرة فقط بلا أيّ تخزينٍ دائم، فإعادةُ تشغيل
                // العمليةِ تعني سلّةً فارغةً وجوباً. خلاصةً: هذه الشاشةُ
                // تسبق تسجيلَ الدخول إلى نقطة البيع دوماً في كلّ مسارٍ
                // موجودٍ فعلياً — فلا سلّةَ بيعٍ قائمةً يمكن أن تُفقَد هنا.
                // إن أُضيف مستقبلاً مسارٌ يعيد فتح هذه الشاشةَ **من داخل**
                // جلسةٍ نشطة (بلا إعادة تشغيل عمليةٍ)، فيجب حراسةُ هذا
                // الزرّ بنفس نمط `onWindowClose`.
                exit(0);
              },
              child: const Text('إغلاق التطبيق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // STEP 8: Business profile selection (Phase B)
  //
  // Drives the runtime feature-flag system. The admin picks one of the
  // seven profiles registered in `BusinessProfileCatalog`; the wizard
  // saves the choice to settings.business_profile and the app's feature
  // providers read it on next boot.
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildBusinessProfileStep() {
    final metas = BusinessProfileCatalog.all();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ملف النشاط التجارى',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'يحدد هذا الاختيار الشاشات والميزات الظاهرة للمستخدم. يمكن تعديله '
          'لاحقًا من "أدوات المطوّر" فقط (محمية بكلمة مرور مطوّر منفصلة).',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        ...metas.map((m) {
          final isSelected = m.profile == _selectedProfile;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _selectedProfile = m.profile),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isSelected
                              ? PhosphorIconsBold.checkCircle
                              : PhosphorIconsBold.circle,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textMuted,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          m.arabicName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 30),
                      child: Text(
                        m.arabicDescription,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    if (isSelected && m.enabledByDefault.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 30),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final k in m.enabledByDefault.take(8))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.success
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  k.settingKey.split('.').last,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                            if (m.enabledByDefault.length > 8)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.textMuted
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '+${m.enabledByDefault.length - 8}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // STEP 7: Developer password (Phase B)
  //
  // Persisted as PBKDF2-SHA256 (salt, hash) via `DeveloperAuthService`.
  // Distinct from admin password; required to change profile / mode /
  // feature overrides post-install. Recovery: CLI `--reset-dev-password`
  // or env `URAL_RESET_DEV_PASSWORD=1`.
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildDeveloperPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'كلمة مرور المطوّر',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'كلمة مرور منفصلة عن الأدمن — تتحكم فى تغيير ملف النشاط ونمط '
          'التشغيل والميزات بعد التثبيت. لا يُفترض مشاركتها مع العميل. '
          'لو نسيتها، استخدم التشغيل مع --reset-dev-password.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _developerPasswordController,
          obscureText: !_developerPasswordVisible,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'كلمة مرور جديدة *',
            hintText: '4 أحرف كحد أدنى',
            prefixIcon: const Icon(PhosphorIconsBold.lock),
            suffixIcon: IconButton(
              icon: Icon(_developerPasswordVisible
                  ? PhosphorIconsBold.eyeSlash
                  : PhosphorIconsBold.eye),
              onPressed: () => setState(() =>
                  _developerPasswordVisible = !_developerPasswordVisible),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _developerPasswordConfirmController,
          obscureText: !_developerPasswordVisible,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'تأكيد كلمة المرور *',
            prefixIcon: const Icon(PhosphorIconsBold.lockKey),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            errorText: _developerPasswordConfirmController.text.isNotEmpty &&
                    _developerPasswordConfirmController.text !=
                        _developerPasswordController.text
                ? 'كلمة المرور غير متطابقة'
                : null,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                PhosphorIconsBold.warning,
                color: AppColors.warning,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'احفظ كلمة المرور فى مكان آمن — لا يمكن استردادها من '
                  'داخل النظام. استخدم تشغيل الـ exe بـ --reset-dev-password '
                  'لإعادة التعيين فى حالة الضرورة.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.warning.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Controls whether the "Next" button is enabled on the current step.
  /// Normally true; blocked on PG config step until connection test passes,
  /// and on provisioning step until it completes successfully.
  bool _canAdvance() {
    if (_currentStep == 5) return _pgConnectionOk;
    if (_currentStep == 6) return _provisioningDone;
    // Step 7 — developer password: require a non-empty password of at
    // least 4 chars AND a matching confirmation. The confirmation is
    // what guarantees the developer typed exactly what they meant.
    if (_currentStep == 7) {
      final pwd = _developerPasswordController.text.trim();
      final cnf = _developerPasswordConfirmController.text.trim();
      return pwd.length >= 4 && pwd == cnf;
    }
    // Step 1 (network/branch) — for mirror mode, block until the
    // foundational handshake against HQ-Server has succeeded. For other
    // modes the step is purely informational and stays unconditionally
    // enabled.
    if (_currentStep == 1 && _networkMode == NetworkMode.mirror) {
      return MirrorState.instance.isConfigured;
    }
    // Step 8 — business profile: always valid (defaults to unified).
    return true;
  }
}

part of '../setup_wizard_screen.dart';

extension _SetupWizardBranchExt on _SetupWizardScreenState {
  // ═══════════════════════════════════════════════════════════════════════
  // STEP 2: Branch & Warehouse
  // ═══════════════════════════════════════════════════════════════════════
  //
  // بندُ المالك ٦: «الفرع والمخزن». مبدّلُ نمط التشغيل انتقل إلى خطوة
  // الترحيب (‏هو الذي يقرّر بقيّةَ المسار)، وبقي هنا ما يتبعه: اسمُ الفرع
  // ورمزُه وعنوانُه والمخزنُ للمستقلّ والسيرفر، والاتّصالُ للعميل، والمصافحةُ
  // للمرآة.
  Widget _buildBranchStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Conditional content based on mode
        if (_networkMode == NetworkMode.client)
          _buildClientSetupSection()
        else if (_networkMode == NetworkMode.mirror)
          _buildMirrorSetupSection()
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _buildTextField(
                  key: const Key('setup_branch_name'),
                  controller: _branchNameController,
                  label: tr('اسم الفرع'),
                  hint: tr('الفرع الرئيسي'),
                  icon: PhosphorIconsBold.buildings,
                  isRequired: true,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  key: const Key('setup_branch_code'),
                  controller: _branchCodeController,
                  label: tr('رمز الفرع'),
                  hint: 'MAIN',
                  icon: PhosphorIconsBold.hash,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr('رمز الفرع بادئةٌ لأرقام فواتيره — حتى ١٠ أحرف.'),
            style: TextStyle(fontSize: 12, color: _mutedInk(context)),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            key: const Key('setup_branch_address'),
            controller: _branchAddressController,
            label: tr('عنوان الفرع'),
            icon: PhosphorIconsBold.mapPin,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            key: const Key('setup_warehouse_name'),
            controller: _warehouseNameController,
            label: tr('اسم المخزن'),
            hint: tr('المخزن الرئيسي'),
            icon: PhosphorIconsBold.warehouse,
            isRequired: true,
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: 18),
        _inlineNote(
          context,
          icon: PhosphorIconsBold.info,
          tone: AppColors.info,
          title: tr('فروعٌ ومخازنُ إضافية'),
          body: _networkMode == NetworkMode.client
              ? tr('في وضع العميل: أنشئ الفروع على السيرفر، ثم اتصل وزامن واختر الفرع المعين لهذا الجهاز.')
              : _networkMode == NetworkMode.mirror
                  ? tr('في وضع المرآة: لاب توب المدير يعمل كأنه HQ-Server — صلاحيات كاملة على كل الفروع والكتابات تذهب للسيرفر مباشرة.')
                  : tr('يمكنك إضافة فروع ومخازن إضافية من شاشة "الفروع والمخازن" بعد إتمام الإعداد.'),
        ),
      ],
    );
  }

  /// Mirror-mode setup section. Reuses the client connection inputs
  /// (`_serverAddressController` / `_serverPortController`) since mirror
  /// shares the underlying server URL/token with client mode — the
  /// difference is in branch scope and write routing, not connectivity.
  ///
  /// MM.A scope: server-identity handshake only (validates reachability,
  /// captures API token). Admin-credential verification lands in MM.C
  /// alongside the MirrorWriteInterceptor.
  Widget _buildMirrorSetupSection() {
    final paired = MirrorState.instance.isConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Row(
                children: [
                  const Icon(PhosphorIconsBold.crown,
                      color: AppColors.warning, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr('وضع المرآة — صلاحيات كاملة على كل الفروع'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _bullet(tr('كل التعديلات تذهب لـ HQ-Server مباشرة')),
              _bullet(tr('Read-only عند فقد الاتصال')),
              _bullet(tr('يلزم حساب مدير على HQ-Server للتفعيل')),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Server URL — reuses client mode's controllers so persistence
        // converges on the same SharedPreferences keys.
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildTextField(
                controller: _serverAddressController,
                label: tr('عنوان HQ-Server'),
                hint: tr('192.168.1.100 أو hq.example.com'),
                icon: PhosphorIconsBold.globeSimple,
                isRequired: true,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: _buildTextField(
                controller: _serverPortController,
                label: tr('المنفذ'),
                hint: '8080',
                icon: PhosphorIconsBold.hash,
                isNumber: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // HQ admin credentials — verified against `/api/auth/verify-admin`
        // before MirrorState.adminUserId is set. The password controller
        // is cleared immediately after a successful pairing.
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _mirrorAdminUsernameController,
                label: tr('اسم مدير HQ'),
                hint: 'admin',
                icon: PhosphorIconsBold.userCircle,
                isRequired: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                controller: _mirrorAdminPasswordController,
                label: tr('كلمة مرور المدير'),
                hint: '••••••••',
                icon: PhosphorIconsBold.lock,
                isRequired: true,
                isPassword: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _isConnecting ? null : _pairMirror,
          icon: _isConnecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(PhosphorIconsBold.link, size: 18),
          label: Text(_isConnecting
              ? tr('جاري التحقق من الاتصال...')
              : paired
                  ? tr('إعادة المصافحة مع السيرفر')
                  : tr('اختبار الاتصال وتفعيل المرآة')),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        if (_connectionResult != null) ...[
          const SizedBox(height: 8),
          Text(
            _connectionResult!,
            style: TextStyle(
              color: _connectionResult!.startsWith('✅')
                  ? AppColors.success
                  : AppColors.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        if (paired) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.checkCircle,
                    size: 16, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('تمت المصافحة — متصل بـ {p0}', {'p0': MirrorState.instance.serverDisplayName}),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.success),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Icon(PhosphorIconsBold.dot, size: 8),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  Widget _buildClientSetupSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Server address
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildTextField(
                controller: _serverAddressController,
                label: tr('عنوان السيرفر'),
                hint: tr('192.168.1.100 أو 100.x.x.x (Tailscale)'),
                icon: PhosphorIconsBold.globeSimple,
                isRequired: true,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: _buildTextField(
                controller: _serverPortController,
                label: tr('المنفذ'),
                hint: '8080',
                icon: PhosphorIconsBold.hash,
                isNumber: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Connect & Sync button
        ElevatedButton.icon(
          onPressed: _isConnecting ? null : _connectAndSync,
          icon: _isConnecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(PhosphorIconsBold.arrowsClockwise, size: 18),
          label: Text(_isConnecting ? tr('جاري الاتصال والمزامنة...') : tr('اتصال ومزامنة')),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        if (_connectionResult != null) ...[
          const SizedBox(height: 8),
          Text(
            _connectionResult!,
            style: TextStyle(
              color: _connectionResult!.startsWith('✅')
                  ? AppColors.success
                  : AppColors.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        // Branch assignment dropdown (only after sync)
        if (_syncedBranches.isNotEmpty) ...[
          const SizedBox(height: 20),
           Text(
            tr('اختر الفرع المعين لهذا الجهاز:'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            initialValue: _selectedBranchId,
            decoration: InputDecoration(
              prefixIcon: const Icon(PhosphorIconsBold.buildings),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            items: [
               DropdownMenuItem<int?>(value: null, child: Text(tr('غير محدد'))),
              ..._syncedBranches.map(
                (b) => DropdownMenuItem<int?>(value: b.id, child: Text(b.name)),
              ),
            ],
            onChanged: (v) => setState(() => _selectedBranchId = v),
          ),
        ],
      ],
    );
  }
}

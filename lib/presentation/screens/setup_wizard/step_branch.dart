part of '../setup_wizard_screen.dart';

extension _SetupWizardBranchExt on _SetupWizardScreenState {
  // ═══════════════════════════════════════════════════════════════════════
  // STEP 2: Branch & Warehouse
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildBranchStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'وضع التشغيل والفرع',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'حدد وضع التشغيل: مستقل، سيرفر، عميل، أو مرآة (لاب توب المدير).',
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        // Network mode selector
        Row(
          children: [
            _buildModeChip(
                NetworkMode.standalone, 'مستقل', PhosphorIconsBold.desktop),
            const SizedBox(width: 12),
            _buildModeChip(
                NetworkMode.server, 'سيرفر', PhosphorIconsBold.hardDrives),
            const SizedBox(width: 12),
            _buildModeChip(
                NetworkMode.client, 'عميل', PhosphorIconsBold.monitor),
            const SizedBox(width: 12),
            _buildModeChip(
                NetworkMode.mirror, 'مرآة', PhosphorIconsBold.crown),
          ],
        ),
        const SizedBox(height: 24),
        // Conditional content based on mode
        if (_networkMode == NetworkMode.client)
          _buildClientSetupSection()
        else if (_networkMode == NetworkMode.mirror)
          _buildMirrorSetupSection()
        else ...[
          _buildTextField(
            controller: _branchNameController,
            label: 'اسم الفرع',
            hint: 'الفرع الرئيسي',
            icon: PhosphorIconsBold.buildings,
            isRequired: true,
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _warehouseNameController,
            label: 'اسم المخزن',
            hint: 'المخزن الرئيسي',
            icon: PhosphorIconsBold.warehouse,
            isRequired: true,
          ),
        ],
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.info, color: AppColors.info, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _networkMode == NetworkMode.client
                      ? 'في وضع العميل: أنشئ الفروع على السيرفر، ثم اتصل وزامن واختر الفرع المعين لهذا الجهاز.'
                      : _networkMode == NetworkMode.mirror
                          ? 'في وضع المرآة: لاب توب المدير يعمل كأنه HQ-Server — صلاحيات كاملة على كل الفروع والكتابات تذهب للسيرفر مباشرة.'
                          : 'يمكنك إضافة فروع ومخازن إضافية من شاشة "الفروع والمخازن" بعد إتمام الإعداد.',
                  style: const TextStyle(color: AppColors.info, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeChip(NetworkMode mode, String label, IconData icon) {
    final isSelected = _networkMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _networkMode = mode),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: isSelected ? AppColors.primary : AppColors.textMuted,
                  size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.primary : null,
                ),
              ),
            ],
          ),
        ),
      ),
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
              const Row(
                children: [
                  Icon(PhosphorIconsBold.crown,
                      color: AppColors.warning, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'وضع المرآة — صلاحيات كاملة على كل الفروع',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _bullet('كل التعديلات تذهب لـ HQ-Server مباشرة'),
              _bullet('Read-only عند فقد الاتصال'),
              _bullet('يلزم حساب مدير على HQ-Server للتفعيل'),
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
                label: 'عنوان HQ-Server',
                hint: '192.168.1.100 أو hq.example.com',
                icon: PhosphorIconsBold.globeSimple,
                isRequired: true,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: _buildTextField(
                controller: _serverPortController,
                label: 'المنفذ',
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
                label: 'اسم مدير HQ',
                hint: 'admin',
                icon: PhosphorIconsBold.userCircle,
                isRequired: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                controller: _mirrorAdminPasswordController,
                label: 'كلمة مرور المدير',
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
              ? 'جاري التحقق من الاتصال...'
              : paired
                  ? 'إعادة المصافحة مع السيرفر'
                  : 'اختبار الاتصال وتفعيل المرآة'),
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
                    'تمت المصافحة — متصل بـ ${MirrorState.instance.serverDisplayName}',
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
                label: 'عنوان السيرفر',
                hint: '192.168.1.100 أو 100.x.x.x (Tailscale)',
                icon: PhosphorIconsBold.globeSimple,
                isRequired: true,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: _buildTextField(
                controller: _serverPortController,
                label: 'المنفذ',
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
          label: Text(_isConnecting ? 'جاري الاتصال والمزامنة...' : 'اتصال ومزامنة'),
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
          const Text(
            'اختر الفرع المعين لهذا الجهاز:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              const DropdownMenuItem<int?>(value: null, child: Text('غير محدد')),
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

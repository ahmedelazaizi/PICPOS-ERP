part of '../setup_wizard_screen.dart';

extension _SetupWizardUsersExt on _SetupWizardScreenState {
  // ═══════════════════════════════════════════════════════════════════════
  // STEP 3: Users
  // ═══════════════════════════════════════════════════════════════════════
  //
  // بندُ المالك ٦: «المستخدمون والأمان» — كلمةُ مرور المدير (‏إلزاميّةٌ في
  // المستقلّ، بتلميح قوّة) وكلمةُ مرور المطوّر (‏كانت خطوةً مستقلّة) ثمّ
  // مستخدمون إضافيّون اختياريّون. والخادمُ يبقى بلا مستخدمين (‏قرارُ 2026-08-28)
  // فيرى قسمَ الأمان وحدَه.
  Widget _buildUsersStep() {
    final isServer = _networkMode == NetworkMode.server;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_asksAdminPassword) ...[
          _buildAdminPasswordSection(),
          const SizedBox(height: 18),
        ],
        _buildDeveloperPasswordSection(),
        if (!isServer) ...[
          const SizedBox(height: 22),
          _stepFieldLabel(tr('مستخدمون إضافيون (اختياري)')),
          const SizedBox(height: 4),
          Text(
            tr('أضف مستخدمي النظام وحدد أدوارهم (يمكنك التخطي والإضافة لاحقاً)'),
            style: TextStyle(color: _mutedInk(context), fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          _buildExtraUsersSection(),
        ],
      ],
    );
  }

  Widget _buildAdminPasswordSection() {
    final pwd = _adminPasswordController.text;
    final strength = _passwordStrength(pwd);
    final (label, tone) = switch (strength) {
      0 => (tr('ضعيفة — {p0} أحرف على الأقل', {'p0': _kAdminPasswordMin}), AppColors.error),
      1 => (tr('مقبولة'), AppColors.warning),
      2 => (tr('جيدة'), AppColors.info),
      _ => (tr('قوية'), AppColors.success),
    };
    final confirm = _adminPasswordConfirmController.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepFieldLabel(tr('كلمة مرور المدير (admin)')),
        const SizedBox(height: 4),
        Text(
          tr('تحلّ محلّ كلمة المرور الافتراضية لحساب المدير. أرقامٌ وحروفٌ معاً أقوى.'),
          style: TextStyle(fontSize: 12.5, color: _mutedInk(context)),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('setup_admin_password'),
                controller: _adminPasswordController,
                obscureText: !_adminPasswordVisible,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: tr('كلمة المرور *'),
                  prefixIcon: const Icon(PhosphorIconsBold.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_adminPasswordVisible
                        ? PhosphorIconsBold.eyeSlash
                        : PhosphorIconsBold.eye),
                    onPressed: () => setState(
                        () => _adminPasswordVisible = !_adminPasswordVisible),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('setup_admin_password_confirm'),
                controller: _adminPasswordConfirmController,
                obscureText: !_adminPasswordVisible,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: tr('تأكيد كلمة المرور *'),
                  prefixIcon: const Icon(PhosphorIconsBold.lockKey),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  errorText: confirm.isNotEmpty && confirm != pwd
                      ? tr('كلمة المرور غير متطابقة')
                      : null,
                ),
              ),
            ),
          ],
        ),
        if (pwd.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsetsDirectional.only(end: 4),
                    decoration: BoxDecoration(
                      color: i < strength
                          ? tone
                          : Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                pwd == 'admin' ? tr('لا تستعمل كلمة المرور الافتراضية') : label,
                key: const Key('setup_admin_strength'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: pwd == 'admin' ? AppColors.error : tone,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildExtraUsersSection() {
    final rolesAsync = ref.watch(allRolesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Add user form
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text(
                tr('مستخدم جديد'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _userDisplayNameController,
                      decoration: InputDecoration(
                        labelText: tr('الاسم الكامل *'),
                        prefixIcon: const Icon(PhosphorIconsBold.user),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _userUsernameController,
                      decoration: InputDecoration(
                        labelText: tr('اسم المستخدم *'),
                        prefixIcon: const Icon(PhosphorIconsBold.at),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _userPasswordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: tr('كلمة المرور *'),
                        prefixIcon: const Icon(PhosphorIconsBold.lock),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: rolesAsync.when(
                      data: (roles) => DropdownButtonFormField<int>(
                        value: _userSelectedRoleId,
                        decoration: InputDecoration(
                          labelText: tr('الدور *'),
                          prefixIcon: const Icon(PhosphorIconsBold.shieldCheck),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        items: roles.map((r) => DropdownMenuItem(
                          value: r.id,
                          child: Text(r.name),
                        )).toList(),
                        onChanged: (v) => setState(() => _userSelectedRoleId = v),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (_, _) =>  Text(tr('خطأ في تحميل الأدوار')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: ElevatedButton.icon(
                  onPressed: _addWizardUser,
                  icon: const Icon(PhosphorIconsBold.plus, size: 18),
                  label:  Text(tr('إضافة المستخدم')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),

        if (_wizardUsers.isNotEmpty) ...[
          const SizedBox(height: 20),
           Text(
            tr('المستخدمون المضافون:'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ...List.generate(_wizardUsers.length, (i) {
            final u = _wizardUsers[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: const Icon(PhosphorIconsBold.user, color: AppColors.primary, size: 20),
                ),
                title: Text(u['displayName'] as String),
                subtitle: Text('${u['username']} — ${u['roleName'] ?? ''}'),
                trailing: IconButton(
                  icon: const Icon(PhosphorIconsBold.trash, color: AppColors.error, size: 18),
                  onPressed: () => setState(() => _wizardUsers.removeAt(i)),
                ),
              ),
            );
          }),
        ],

        if (_networkMode == NetworkMode.client) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child:  Row(
              children: [
                const Icon(PhosphorIconsBold.info, color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('المستخدمون الموجودون على السيرفر ستتم مزامنتهم تلقائياً'),
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

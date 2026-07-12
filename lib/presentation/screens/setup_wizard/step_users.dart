part of '../setup_wizard_screen.dart';

extension _SetupWizardUsersExt on _SetupWizardScreenState {
  // ═══════════════════════════════════════════════════════════════════════
  // STEP 3: Users
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildUsersStep() {
    final rolesAsync = ref.watch(allRolesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(PhosphorIconsBold.users, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إنشاء المستخدمين',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  'أضف مستخدمي النظام وحدد أدوارهم (يمكنك التخطي والإضافة لاحقاً)',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Add user form
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'مستخدم جديد',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _userDisplayNameController,
                      decoration: InputDecoration(
                        labelText: 'الاسم الكامل *',
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
                        labelText: 'اسم المستخدم *',
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
                        labelText: 'كلمة المرور *',
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
                          labelText: 'الدور *',
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
                      error: (_, _) => const Text('خطأ في تحميل الأدوار'),
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
                  label: const Text('إضافة المستخدم'),
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
          const Text(
            'المستخدمون المضافون:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
            child: const Row(
              children: [
                Icon(PhosphorIconsBold.info, color: Colors.amber, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'المستخدمون الموجودون على السيرفر ستتم مزامنتهم تلقائياً',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
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

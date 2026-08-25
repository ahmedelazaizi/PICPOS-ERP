import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/config/brand.dart';
import '../../../../core/permissions/permission_codes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/uuid_v7.dart';
import '../../../../services/security_service.dart';
import '../../../../services/network_service.dart';
import '../../../../data/providers/providers.dart';
import '../../../../data/database/sync_interceptor.dart';
import '../../../../domain/models/branch_assignment_scope.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import '../../../picpos_shell/picpos_dialog.dart';
import '../../../picpos_shell/picpos_panel_groups.dart';
import '../../../settings_picpos/widgets/settings_blocks.dart';
import 'package:ural_erp/l10n/app_localizations.dart';
import 'add_role_dialog.dart';

class AddUserDialog extends AppFormDialog<bool> {
  const AddUserDialog({super.key});

  @override
  AppFormDialogState<bool, AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends AppFormDialogState<bool, AddUserDialog> {
  late final nameController = registerController();
  late final usernameController = registerController();
  late final passwordController = registerController();
  late final confirmController = registerController();
  late final cardCodeController = registerController();
  int? selectedRoleId;
  bool forcePasswordChange = true;

  /// «الحساب نشط» في `PANELS.user` — عمودٌ قائمٌ (`Users.isActive`) يضبطه
  /// `toggleUserActive`. والإنشاءُ يبدأ نشطاً كما في التصميم.
  bool isActive = true;
  bool _allBranches = true;
  final List<int> selectedBranchIds = [];

  @override
  String get dialogTitle => 'إضافة مستخدم جديد';

  @override
  IconData get dialogIcon => PhosphorIconsBold.userPlus;

  @override
  String? get dialogSubtitle => 'أنشئ حساباً واربطه بدورٍ وفروعٍ ومخازنَ محدّدة';

  @override
  String? get dialogSaveLabel => 'حفظ المستخدم';

  // ── حقولٌ يتشاركها الفرعان ────────────────────────────────────────────
  //
  // نسخةٌ واحدةٌ من كلِّ حقلٍ يستعملها جسمُ UralCash وجسمُ PicPos معاً: الفرقُ
  // بينهما التجميعُ والترتيبُ، لا الحقول.

  Widget _nameField() => TextField(
        controller: nameController,
        decoration: const InputDecoration(
          labelText: 'الاسم الكامل *',
          prefixIcon: Icon(PhosphorIconsLight.user),
        ),
      );

  Widget _usernameField() => TextField(
        controller: usernameController,
        decoration: const InputDecoration(
          // نصُّ التصميم: «اسم الدخول». وهو أدقُّ ممّا كان («اسم المستخدم»)
          // لأنّ الحقلَ الآخرَ «الاسم الكامل» هو اسمُ المستخدم فعلاً.
          labelText: 'اسم الدخول *',
          prefixIcon: Icon(PhosphorIconsLight.at),
        ),
      );

  /// «تأكيد كلمة المرور» في `PANELS.user`.
  ///
  /// ⚠️ **حقلٌ بلا عمودٍ — وهذا مشروعٌ هنا خلافاً للهاتف والبريد.** لا يُحفَظ
  /// التأكيدُ في القاعدة أصلاً؛ عملُه أن يمنع خطأً مطبعيّاً يقفل الحسابَ على
  /// صاحبه قبل أن يدخل مرّة. فهو تحقّقٌ لا حقلُ بيانات.
  Widget _confirmField() => TextField(
        controller: confirmController,
        obscureText: true,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'تأكيد كلمة المرور *',
          prefixIcon: const Icon(PhosphorIconsLight.lock),
          errorText: confirmController.text.isNotEmpty &&
                  confirmController.text != passwordController.text
              ? 'لا تطابق كلمةَ المرور'
              : null,
        ),
      );

  Widget _passwordField() => TextField(
        controller: passwordController,
        obscureText: true,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'كلمة المرور *',
          prefixIcon: Icon(PhosphorIconsLight.lock),
        ),
      );

  // Issue 4 (Feature 018): MSR card code field — admins can either swipe
  // a card (the MSR keyboard-emulation feeds the field naturally) or
  // type the code manually. Stored on Users.cardCode and used by
  // user_dao.authenticateByCardCode at the login screen.
  Widget _cardCodeField() => TextField(
        controller: cardCodeController,
        decoration: const InputDecoration(
          labelText: 'كود كارت MSR (اختياري)',
          hintText: 'مرر الكارت أو اكتب الكود يدوياً',
          prefixIcon: Icon(PhosphorIconsLight.identificationCard),
        ),
      );

  /// لوحةُ `PANELS.user` — أربعُ مجموعاتٍ من خمسٍ في التصميم.
  ///
  /// ⚠️ **ومجموعةُ «المخازن المسموحة» غائبةٌ عن عمد**: هذا الحوارُ يُنشئ
  /// الحساب، ونطاقُ المخازن يُضبَط من حوارٍ مستقلٍّ (`WarehouseAccessDialog`)
  /// يكتب في `user_warehouse_access`. ومجموعةٌ هنا لن يقرأها الحفظُ وعدٌ
  /// كاذب.
  ///
  /// ⚠️ **و«الهاتف» و«البريد» وحدَهما بلا أعمدةٍ** في `Users` — فلم تُرسَما.
  /// أمّا «تأكيدُ كلمة المرور» فرُسم: هو تحقّقٌ لا عمودٌ، ولا يحتاج قاعدةً كي
  /// يمنع خطأً مطبعيّاً يقفل الحسابَ على صاحبه قبل أوّل دخول.
  ///
  /// ⚠️ **وتحذيرُ «كل الفروع» بقي**: كان سطراً أحمرَ تحت زرِّ الاختيار، وصار
  /// لافتةَ هويّةٍ تظهر بنفس الشرط. حذفُه عند النقل كان سيُخفي أنّ المستخدمَ
  /// قد يخرج بلا فرعٍ فلا يرى فاتورةً أصدرها بنفسه.
  @override
  List<PicPosPanelGroup> buildPicposGroups(BuildContext context) {
    final roles = ref.watch(allRolesProvider).value ?? [];
    final branches = ref.watch(allBranchesProvider).value ?? [];
    final pwd = passwordController.text;
    final check = SecurityService.validatePassword(pwd);
    final roleName =
        roles.where((r) => r.id == selectedRoleId).firstOrNull?.name;
    final allBranchesAllowed = fullBranchAccessRoleNames.contains(roleName);

    return [
      PicPosPanelGroup(
        label: 'بيانات الحساب',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PicPosDialogRow(children: [_nameField(), _usernameField()]),
            const SizedBox(height: 12),
            PicPosPanelStrength(
              field: _passwordField(),
              strength: pwd.isEmpty ? 0 : check.strength,
              strengthLabel: pwd.isEmpty
                  ? ''
                  : SecurityService.getPasswordStrengthLabel(check.strength),
              rules: pwd.isEmpty
                  ? const []
                  : [
                      for (final r in SecurityService.passwordRules(pwd))
                        (label: r.label, ok: r.ok),
                    ],
            ),
            const SizedBox(height: 12),
            _confirmField(),
            const SizedBox(height: 12),
            _cardCodeField(),
          ],
        ),
      ),
      PicPosPanelGroup(
        label: 'الدور',
        hint: 'دورٌ واحدٌ لكلّ مستخدم',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PicPosPanelChips(
              children: [
                PicPosPanelChip(
                  label: 'بدون دور',
                  selected: selectedRoleId == null,
                  onTap: () => setState(() => selectedRoleId = null),
                ),
                for (final r in roles)
                  PicPosPanelChip(
                    label: r.name,
                    tooltip: r.isSystemRole ? 'دورُ نظامٍ مبنيٌّ مسبقاً' : null,
                    selected: selectedRoleId == r.id,
                    onTap: () => setState(() => selectedRoleId = r.id),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(PhosphorIconsBold.plus, size: 15),
              label: const Text('دور جديد بصلاحيات مخصّصة'),
              onPressed: () async {
                final added = await showDialog<bool>(
                  context: context,
                  builder: (_) => const AddRoleDialog(),
                );
                if (added == true && mounted) setState(() {});
              },
            ),
          ],
        ),
      ),
      if (branches.isNotEmpty)
        PicPosPanelGroup(
          label: 'الفروع المسموحة',
          hint: 'اختر فرعاً أو أكثر',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PicPosPanelChips(
                children: [
                  for (final b in branches)
                    PicPosPanelChip(
                      label: b.name,
                      tooltip: b.address,
                      selected:
                          !_allBranches && selectedBranchIds.contains(b.id),
                      onTap: () => setState(() {
                        _allBranches = false;
                        if (!selectedBranchIds.remove(b.id)) {
                          selectedBranchIds.add(b.id);
                        }
                      }),
                    ),
                  PicPosPanelChip(
                    label: 'كل الفروع (مدير / إدارة)',
                    selected: _allBranches,
                    onTap: () => setState(() {
                      _allBranches = true;
                      selectedBranchIds.clear();
                    }),
                  ),
                ],
              ),
              if (_allBranches && !allBranchesAllowed) ...[
                const SizedBox(height: 12),
                const PicPosDialogBanner(
                  icon: PhosphorIconsBold.warning,
                  color: AppColors.warning,
                  text: 'غيرُ متاحٍ لهذا الدور — وبلا إسنادِ فرعٍ لن يرى '
                      'المستخدمُ أيَّ فاتورةٍ ولو أصدرها بنفسه.',
                ),
              ],
            ],
          ),
        ),
      PicPosPanelGroup(
        label: 'خيارات الحساب',
        child: PicPosPanelBox(
          children: [
            SettingsSwitchRow(
              first: true,
              icon: PhosphorIconsBold.checkCircle,
              title: 'الحساب نشط',
              sub: 'يمكنه تسجيل الدخول فوراً',
              value: isActive,
              onChanged: (v) => setState(() => isActive = v),
            ),
            SettingsSwitchRow(
              icon: PhosphorIconsBold.arrowsClockwise,
              title: 'تغيير كلمة المرور أول دخول',
              sub: 'سيُطلب منه تغييرُها فورَ تسجيل الدخول',
              value: forcePasswordChange,
              onChanged: (v) => setState(() => forcePasswordChange = v),
            ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget buildFormContent(BuildContext context, AppLocalizations localizations) {
    final roles = ref.watch(allRolesProvider).value ?? [];
    final branches = ref.watch(allBranchesProvider).value ?? [];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // الحقولُ نفسُها التي تجمّعها لوحةُ PicPos — نسخةٌ واحدةٌ لا اثنتان.
        _nameField(),
        const SizedBox(height: 12),
        _usernameField(),
        const SizedBox(height: 12),
        _passwordField(),
        if (passwordController.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildPasswordStrength(),
        ],
        const SizedBox(height: 12),
        _cardCodeField(),
        const SizedBox(height: 12),
        // Role dropdown + action buttons
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                decoration: const InputDecoration(
                  labelText: 'الدور / الصلاحية',
                  prefixIcon: Icon(PhosphorIconsLight.shieldCheck),
                ),
                value: selectedRoleId,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('— بدون دور —', style: TextStyle(color: Colors.grey)),
                  ),
                  ...roles.map(
                    (role) => DropdownMenuItem(
                      value: role.id,
                      child: Row(
                        children: [
                          Icon(
                            role.isSystemRole
                                ? PhosphorIconsFill.shieldStar
                                : PhosphorIconsLight.shield,
                            size: 14,
                            color: role.isSystemRole ? AppColors.primary : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(role.name),
                        ],
                      ),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => selectedRoleId = v),
              ),
            ),
            const SizedBox(width: 6),
            // Add new role
            Tooltip(
              message: 'إضافة دور جديد',
              child: IconButton.outlined(
                icon: const Icon(PhosphorIconsBold.plus, size: 18),
                style: IconButton.styleFrom(
                  side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                  foregroundColor: AppColors.primary,
                ),
                onPressed: () async {
                  final added = await showDialog<bool>(
                    context: context,
                    builder: (_) => const AddRoleDialog(),
                  );
                  if (added == true) {
                    // allRolesProvider refreshes automatically (StreamProvider)
                    setState(() {});
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Hint under the role row
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Text(
            'لإنشاء دور جديد بصلاحيات مخصصة اضغط +',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ),
        if (branches.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('الفرع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          // ⚠️ «كل الفروع» لا يكتب إسناداً، والفراغُ يعني «الكلَّ» للأدوار
          // المميَّزة وحدَها. فيُقال ذلك **قبل** الحفظ لا بعده: الحارسُ في
          // `onSave` يمنع، وهذا السطرُ يشرح لماذا قبل أن يُمنَع أحد.
          RadioListTile<bool>(
            title: const Text('كل الفروع (مدير / إدارة)'),
            subtitle: fullBranchAccessRoleNames.contains(
              roles.where((r) => r.id == selectedRoleId).firstOrNull?.name,
            )
                ? null
                : const Text(
                    'غيرُ متاحٍ لهذا الدور — بلا إسنادِ فرعٍ لن يرى '
                    'المستخدمُ أيَّ فاتورةٍ ولو أصدرها بنفسه.',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.warning),
                  ),
            value: true,
            groupValue: _allBranches,
            onChanged: (v) => setState(() { _allBranches = true; selectedBranchIds.clear(); }),
            dense: true,
          ),
          RadioListTile<bool>(
            title: const Text('فرع محدد'),
            value: false,
            groupValue: _allBranches,
            onChanged: (v) => setState(() => _allBranches = false),
            dense: true,
          ),
          if (!_allBranches)
            ...branches.map((branch) => CheckboxListTile(
              title: Text(branch.name),
              value: selectedBranchIds.contains(branch.id),
              onChanged: (v) => setState(() {
                if (v == true) selectedBranchIds.add(branch.id);
                else selectedBranchIds.remove(branch.id);
              }),
              dense: true,
              contentPadding: const EdgeInsets.only(right: 32),
            )),
          const SizedBox(height: 12),
        ],
        CheckboxListTile(
          title: const Text('فرض تغيير كلمة المرور عند أول دخول'),
          subtitle: const Text('سيُطلب من المستخدم تغيير كلمة المرور فور تسجيل الدخول'),
          value: forcePasswordChange,
          onChanged: (v) => setState(() => forcePasswordChange = v ?? true),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppColors.primary,
        ),
      ],
    );
  }

  Widget _buildPasswordStrength() {
    final result = SecurityService.validatePassword(passwordController.text);
    final strengthLabel = SecurityService.getPasswordStrengthLabel(result.strength);
    final strengthColor = result.strength < 30
        ? Colors.red
        : result.strength < 50
            ? Colors.orange
            : result.strength < 70
                ? Colors.amber
                : result.strength < 90
                    ? Colors.lightGreen
                    : Colors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: result.strength / 100,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(strengthColor),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              strengthLabel,
              style: TextStyle(fontSize: 11, color: strengthColor, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        if (!result.isValid) ...[
          const SizedBox(height: 6),
          ...result.errors.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    const Icon(Icons.close, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(e, style: const TextStyle(fontSize: 11, color: Colors.red)),
                    ),
                  ],
                ),
              )),
        ],
      ],
    );
  }

  @override
  Future<bool> onSave() async {
    // P5 (Issue #6): Removed the client-mode hard-block. The original guard
    // assumed users couldn't be created on a client — but the code below
    // (lines ~280-287) already routes the create through
    // SyncInterceptor.createUser, which:
    //   1. Mints a stable globalId on the client.
    //   2. POSTs to /api/users on the server.
    //   3. Returns the server-assigned id so the local row uses the same id.
    //   4. Falls back to outbox queue when the server is unreachable.
    // Symptom of the old guard: admin couldn't create cashier accounts on a
    // client machine; new staff had to be added at the server console. When
    // they bypassed the guard via the setup wizard, the cashier user lived
    // ONLY on the client — every sale they rang up failed userId
    // resolution on the server. The interceptor path is the correct fix.
    final name = nameController.text.trim();
    final username = usernameController.text.trim();
    final password = passwordController.text;
    final cardCode = cardCodeController.text.trim().isEmpty
        ? null
        : cardCodeController.text.trim();

    if (name.isEmpty || username.isEmpty || password.isEmpty) {
      throw 'يجب ملء جميع الحقول المطلوبة';
    }

    // ⚠️ **يُفحَص التأكيدُ في فرع PicPos وحدَه** — لأنّ حقلَه يُرسَم هناك
    //    وحدَه. وفرضُه على جسم UralCash يمنع كلَّ إنشاءٍ فيه بحقلٍ لا يراه
    //    المشغّل: الشرطُ يقرأ متحكّماً فارغاً أبداً فيرفض دوماً.
    if (Brand.isPicPos && confirmController.text != password) {
      throw 'تأكيدُ كلمة المرور لا يطابقها';
    }

    if (selectedRoleId == null) {
      throw 'يجب اختيار دور للمستخدم';
    }

    // ── لا تُولَد تجهيزةٌ بنطاقٍ فارغ (‏قرارُ المالك 2026-08-23) ──────────
    // «كل الفروع» لا يكتب صفَّ إسنادٍ واحد، والفراغُ يعني «الكلَّ» للأدوار
    // المميَّزة وحدَها؛ ولغيرِها يعني `no-assignments-fail-closed`. فكاشيرٌ
    // أُنشئ على الافتراضِ كان يبيع ولا يرى ما باع (وقع فعلاً لـ`userId=2`).
    //
    // ⚠️ ولا يُحرَس إلّا حين تكون هناك فروعٌ أصلاً: تنصيبةٌ بلا فروعٍ لا
    // تعرض المنتقي، فحراستُها كانت ستمنع إنشاءَ أيِّ مستخدم.
    final branchesNow = ref.read(allBranchesProvider).value ?? [];
    if (branchesNow.isNotEmpty) {
      final roleName = (ref.read(allRolesProvider).value ?? [])
          .where((r) => r.id == selectedRoleId)
          .firstOrNull
          ?.name;
      final blocker = branchAssignmentBlocker(
        roleHasFullBranchAccess: fullBranchAccessRoleNames.contains(roleName),
        allBranchesChosen: _allBranches,
        selectedBranchCount: selectedBranchIds.length,
      );
      if (blocker != null) throw blocker;
    }

    // Password strength is shown as guidance only — not enforced

    final authRepo = ref.read(authRepositoryProvider);

    // ── Cross-branch user creation gate ─────────────────────────────────
    // On a paired client, creating a user effectively pushes a new identity
    // to the server's authoritative users table. Restrict that to operators
    // who explicitly hold `users_manage_cross_branch`. Standalone and server
    // installations are always allowed (no network propagation concern).
    if (NetworkService.instance.isClient) {
      final auth = ref.read(authProvider);
      final actorId = auth.user?.id;
      final allowed = actorId != null &&
          await authRepo.userHasPermission(
            actorId,
            PermissionCodes.usersManageCrossBranch,
          );
      if (!allowed) {
        throw 'لا تملك صلاحية إنشاء المستخدمين من جهاز فرع. يرجى '
            'إنشاء المستخدم من المقر الرئيسى أو طلب تفعيل صلاحية '
            '"إدارة المستخدمين عبر-فروع" لحسابك.';
      }
    }

    // UUID-First (Phase 1): mint ONE globalId up-front so the same identity
    // lands on both server (via interceptor) and local row.
    final userGlobalId = UuidV7.generate();

    // In client mode: send to server first and capture the server-assigned ID.
    // Using the server ID locally keeps client and server IDs in perfect sync,
    // preventing "User ID not found on server" errors on future invoice syncs.
    int? serverId;
    if (SyncInterceptor.instance != null) {
      serverId = await SyncInterceptor.instance!.createUser(
        username: username,
        password: password,
        displayName: name,
        roleId: selectedRoleId,
        branchIds: selectedBranchIds,
        globalId: userGlobalId,
        cardCode: cardCode,
      );
    }

    // Always create locally so the user can authenticate immediately.
    // If online: use server-returned ID so IDs stay in sync.
    // If offline: auto-increment (reconciled on next fullSync).
    final newUserId = await authRepo.createUser(
      id: serverId,
      username: username,
      password: password,
      displayName: name,
      roleId: selectedRoleId,
      forcePasswordChange: forcePasswordChange,
      globalId: userGlobalId,
      cardCode: cardCode,
    );
    if (!_allBranches && selectedBranchIds.isNotEmpty) {
      await authRepo.setUserBranchAccess(newUserId, selectedBranchIds);
    }

    // «الحساب نشط» — الإنشاءُ ينشئ نشطاً (‏`Users.isActive` افتراضُها `true`)،
    // فلا يُنادى المبدِّلُ إلّا حين يُطفئه المشغّلُ صراحةً.
    if (!isActive) {
      await authRepo.toggleUserActive(userId: newUserId, isActive: false);
    }

    // #Forensic Log: User create
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserCreate(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        name,
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }

    return true;
  }
}

part of 'loyalty_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOMER POINTS TAB
// ═══════════════════════════════════════════════════════════════════════════

/// هل [permissions] تسمح بتعديل رصيد نقاط عميل (إضافة/خصم يدوي)؟
///
/// مستخرجة top-level — نفس وضع `canEditOffer`/`canDeleteOffer` في
/// `offer_cards.dart`: الفعل بينده عليه `PopupMenuButton.onSelected` لكل
/// صف عميل، والـ`PopupMenuItem` نفسه بيمسك الضغطة ويقفل الميني قبل ما أي
/// `PermissionGuard` جواه يشتغل، فمفيش ودجت واحد يتلف بيه.
///
/// ── فيكس المراجعة (Task 6b) ──────────────────────────────────────────────
/// ده كان الثغرة الحرجة التانية: `_showAdjustPointsDialog` (إضافة/خصم نقاط
/// على رصيد أي عميل) في نفس الشاشة اللي فيها `loyalty_programs_tab.dart`
/// (تبويب شقيق، جوه نفس `part of 'loyalty_screen.dart'`)، محمي بنفس كود
/// العرض الخشن `loyalty_view` بس — مفيش فحص على الكتابة نفسها أصلاً.
bool canAdjustLoyaltyPoints(List<String> permissions) {
  final isAdmin =
      permissions.contains('system_admin') || permissions.contains('*');
  return isAdmin || permissions.contains(PermissionCodes.loyaltyManage);
}

/// قائمة «إضافة/خصم نقاط» لصف عميل واحد.
///
/// مستخرجة top-level (نفس نمط `OfferCardActionsMenu` في `offer_cards.dart`،
/// نفس السبب): لو الفحص اتحط جوه `onSelected` بتاع الشاشة نفسها بس، اختبار
/// بيفحص `canAdjustLoyaltyPoints` لوحدها ما كانش هيثبت إن السلك فعلاً بينده
/// عليها — استخراج القائمة كلها كودجت مستقل بياخد `onAdd`/`onSubtract`
/// كبارامترات بسيطة بيخلّي فتح الميني واختيار عنصر واختبار حقيقي من غير
/// شاشة `LoyaltyScreen`/قاعدة بيانات.
@visibleForTesting
class LoyaltyPointsAdjustMenu extends ConsumerWidget {
  final VoidCallback onAdd;
  final VoidCallback onSubtract;

  const LoyaltyPointsAdjustMenu({
    super.key,
    required this.onAdd,
    required this.onSubtract,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `ref.watch` (مش `ref.read`) مقصودة — نفس فيكس `OfferCardActionsMenu`:
    // بتخلّي الـFutureProvider يبدأ يتحلّ من أول ما الودجت يتبني، فمفيش
    // سباق زمني بين أول تاب على القائمة وأول قراءة للصلاحيات.
    final perms = ref.watch(currentUserPermissionsProvider).asData?.value ??
        const <String>[];
    return PopupMenuButton<String>(
      icon: const Icon(PhosphorIconsBold.dotsThreeVertical),
      tooltip: 'خيارات',
      onSelected: (action) {
        if (!canAdjustLoyaltyPoints(perms)) {
          AppToast.show(context, 'ليس لديك صلاحية تعديل نقاط الولاء',
              type: ToastType.error);
          return;
        }
        if (action == 'add') {
          onAdd();
        } else if (action == 'subtract') {
          onSubtract();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'add',
          child: Row(
            children: [
              Icon(PhosphorIconsBold.plusCircle, color: Colors.green, size: 18),
              SizedBox(width: 8),
              Text('إضافة نقاط'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'subtract',
          child: Row(
            children: [
              Icon(PhosphorIconsBold.minusCircle, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Text('خصم نقاط'),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomerPointsTab extends StatefulWidget {
  final WidgetRef ref;
  final String searchQuery;
  const _CustomerPointsTab({required this.ref, this.searchQuery = ''});
  @override
  State<_CustomerPointsTab> createState() => _CustomerPointsTabState();
}

class _CustomerPointsTabState extends State<_CustomerPointsTab> {
  int? _selectedProgramId;

  @override
  Widget build(BuildContext context) {
    final repo = widget.ref.watch(loyaltyRepositoryProvider);
    final partiesRepo = widget.ref.watch(partiesRepositoryProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                PhosphorIconsBold.usersThree,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                'أرصدة نقاط العملاء',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              StreamBuilder<List<LoyaltyProgram>>(
                stream: repo.watchLoyaltyPrograms(),
                builder: (context, snapshot) {
                  final programs = snapshot.data ?? [];
                  if (programs.isEmpty) {
                    // BUG-U21: tell the user a loyalty program must be created
                    // first instead of rendering nothing.
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'لا يوجد برنامج ولاء. أنشئ برنامجاً أولاً لتفعيل النقاط.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    );
                  }
                  _selectedProgramId ??= programs.first.id;
                  return DropdownButton<int>(
                    value: _selectedProgramId,
                    items: programs
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedProgramId = v),
                  );
                },
              ),
            ],
          ),
        ),
        if (_selectedProgramId != null)
          Expanded(
            child: StreamBuilder<List<CustomerLoyaltyPoint>>(
              stream: repo.watchAllCustomerPointsByProgram(_selectedProgramId!),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final points = snapshot.data!;
                if (points.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PhosphorIconsBold.star,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد أرصدة بعد',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ستظهر الأرصدة تلقائياً عند كسب العملاء للنقاط',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Summary row
                final totalEarned =
                    points.fold(0, (sum, p) => sum + p.totalEarned);
                final totalRedeemed =
                    points.fold(0, (sum, p) => sum + p.totalRedeemed);
                final totalBalance =
                    points.fold(0, (sum, p) => sum + p.currentBalance);

                return Column(
                  children: [
                    // Stats bar
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statChip('مكتسب', '$totalEarned', Colors.green),
                          _statChip('مستبدل', '$totalRedeemed', Colors.orange),
                          _statChip(
                            'الرصيد',
                            '$totalBalance',
                            AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: points.length,
                        itemBuilder: (context, index) {
                          final pt = points[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withValues(
                                  alpha: 0.1,
                                ),
                                child: const Icon(
                                  PhosphorIconsBold.user,
                                  color: AppColors.primary,
                                ),
                              ),
                              title: FutureBuilder<Party?>(
                                future: partiesRepo.getPartyById(pt.customerId),
                                builder: (ctx, snap) => Text(
                                  snap.data?.name ??
                                      'عميل #${pt.customerId}',
                                ),
                              ),
                              subtitle: Text(
                                'مكتسب: ${pt.totalEarned} | مستبدل: ${pt.totalRedeemed}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${pt.currentBalance} نقطة',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  LoyaltyPointsAdjustMenu(
                                    onAdd: () => _showAdjustPointsDialog(
                                      context,
                                      repo,
                                      pt,
                                      isPositive: true,
                                    ),
                                    onSubtract: () => _showAdjustPointsDialog(
                                      context,
                                      repo,
                                      pt,
                                      isPositive: false,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  void _showAdjustPointsDialog(
    BuildContext context,
    ILoyaltyRepository repo,
    CustomerLoyaltyPoint pt, {
    required bool isPositive,
  }) {
    final pointsCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isPositive ? 'إضافة نقاط' : 'خصم نقاط'),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pointsCtrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'عدد النقاط',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(
                      isPositive
                          ? PhosphorIconsBold.plusCircle
                          : PhosphorIconsBold.minusCircle,
                      color: isPositive ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final points = int.tryParse(pointsCtrl.text) ?? 0;
                      if (points <= 0) return;
                      setDialogState(() => saving = true);
                      try {
                        final adjustValue = isPositive ? points : -points;
                        await repo.adjustPoints(
                          customerId: pt.customerId,
                          programId: pt.programId,
                          points: adjustValue,
                          notes: notesCtrl.text.isNotEmpty
                              ? notesCtrl.text
                              : (isPositive ? 'تعديل يدوي +$points' : 'تعديل يدوي -$points'),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          AppToast.show(
                            context,
                            isPositive
                                ? 'تمت إضافة $points نقطة'
                                : 'تم خصم $points نقطة',
                          );
                        }
                      } finally {
                        if (ctx.mounted) setDialogState(() => saving = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: isPositive ? Colors.green : Colors.orange,
              ),
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(isPositive ? 'إضافة' : 'خصم'),
            ),
          ],
        ),
      ),
    );
  }
}

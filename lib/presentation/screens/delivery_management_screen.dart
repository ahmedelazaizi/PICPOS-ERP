import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/utils/friendly_error.dart';
import 'package:ural_erp/presentation/widgets/dialogs/app_confirm_dialog.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:drift/drift.dart' show Value;
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../core/permissions/permission_codes.dart';
import '../picpos_shell/picpos_body_handle.dart';
import '../widgets/permission_guard.dart';
import 'party_statement_screen.dart';

class DeliveryManagementScreen extends StatefulWidget {
  const DeliveryManagementScreen({super.key});

  @override
  State<DeliveryManagementScreen> createState() =>
      _DeliveryManagementScreenState();
}

class _DeliveryManagementScreenState extends State<DeliveryManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// تُملَك هنا لا في `build` — انظر توثيق [PicPosBodyHandle].
  final _addCourierHandle = PicPosBodyHandle();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _addCourierHandle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title:  Text(tr('إدارة الشركات والمناديب')),
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            tabs:  [
              Tab(
                icon: const Icon(PhosphorIconsBold.buildings),
                text: tr('شركات التوصيل'),
              ),
              Tab(icon: const Icon(PhosphorIconsBold.moped), text: tr('المناديب')),
            ],
          ),
        ),
        body: DeliveryManagementBody(
          tabController: _tabController,
          addCourierHandle: _addCourierHandle,
        ),
        floatingActionButton: _tabController.index == 1
            ? PermissionGuard(
                permission: PermissionCodes.deliveryCourierManage,
                child: FloatingActionButton(
                  onPressed: _addCourierHandle.invoke,
                  backgroundColor: AppColors.primary,
                  child: const Icon(PhosphorIconsBold.plus, color: Colors.white),
                ),
              )
            : null,
      ),
    );
  }
}

/// جسمُ شاشة التوصيل بلا قشرة: `TabBarView` وحدَه بتبويبَيه.
///
/// استُخرج ليركب عليه إطارُ العلامتَين معاً بلا نسخِ منطق:
/// `DeliveryManagementScreen` أعلاه (‏قشرةُ UralCash — حرفاً بحرفٍ ما كانت
/// عليه: `AppBar` أزرقُ بـ`TabBar` في ذيله و`FAB`) و
/// `DeliveryManagementPicposScreen` (‏قشرةُ PicPos: ترويسةٌ موحّدةٌ و`TabBar`
/// في `subHeader` وزرُّ CTA في الترويسة).
///
/// ⚠️ **الـ`TabController` تملكه القشرةُ لا الجسم** — وذلك مقصود: لو انتقل
/// إلى الجسم لوجب أن ينتقل معه الـ`TabBar`، فيخرج من ذيلِ `AppBar` الأزرقِ
/// في UralCash ويفقد بياضَه — أي تبدُّلٌ في شاشةِ UralCash، وهو ما يمنعه
/// شرطُ الاستخراج. فكلُّ قشرةٍ ترسم `TabBar`ها في موضعها وتشتركان في المتحكّم.
///
/// [addCourierHandle] يسجّل الجسمُ فيه «إضافة مندوب» **فقط** حين يكون تبويبُ
/// المناديب هو النشط — فيتبع زرُّ القشرة التبويبَ من غير أن تعرف القشرةُ
/// شيئاً عن دواخل الجسم.
class DeliveryManagementBody extends ConsumerStatefulWidget {
  final TabController tabController;
  final PicPosBodyHandle? addCourierHandle;

  const DeliveryManagementBody({
    super.key,
    required this.tabController,
    this.addCourierHandle,
  });

  @override
  ConsumerState<DeliveryManagementBody> createState() =>
      _DeliveryManagementBodyState();
}

class _DeliveryManagementBodyState
    extends ConsumerState<DeliveryManagementBody> {
  bool _savingCompany = false;
  bool _savingCourier = false;
  bool _deletingCompany = false;
  bool _deletingCourier = false;

  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_syncCourierHandle);
    _syncCourierHandle();
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_syncCourierHandle);
    widget.addCourierHandle?.register(null);
    super.dispose();
  }

  /// «إضافة مندوب» متاحةٌ في تبويب المناديب وحدَه — تماماً كما كان الـ`FAB`
  /// يظهر عند `index == 1` فقط.
  void _syncCourierHandle() {
    widget.addCourierHandle
        ?.register(widget.tabController.index == 1 ? _showAddCourierDialog : null);
  }

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: widget.tabController,
      children: [_buildCompaniesTab(), _buildCouriersTab()],
    );
  }

  Widget _buildCompaniesTab() {
    // Show Parties flagged as delivery companies (from العملاء والموردين).
    // P5 (Issue #6.3): Each card now shows the party's balance prominently
    // and is tappable — opens the existing PartyStatementScreen which already
    // handles "Record Payment" / "Record Receipt" voucher creation. This
    // gives operators a single screen to settle all delivery-company
    // accounts without hopping between the customers list and the statement.
    final partiesAsync = ref.watch(allDeliveryPartiesProvider);

    return partiesAsync.when(
      data: (parties) => parties.isEmpty
          ? _buildEmptyState(tr('لا توجد شركات توصيل\nأضف شركة من شاشة العملاء والموردين وفعّل خيار "شركة توصيل"'))
          : Column(
              children: [
                // Summary banner: total receivable across all delivery companies
                Container(
                  margin: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.85),
                        AppColors.primary,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        PhosphorIconsBold.wallet,
                        color: Colors.white,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             Text(
                              tr('إجمالى المستحَق على شركات التوصيل'),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              parties
                                  .map((p) => p.balance)
                                  .fold<double>(0, (a, b) => a + b)
                                  .toStringAsFixed(2),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        tr('{p0} شركة', {'p0': parties.length}),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: parties.length,
                    itemBuilder: (context, index) {
                      final party = parties[index];
                      final balance = party.balance;
                      final balColor = balance > 0
                          ? AppColors.error
                          : balance < 0
                              ? AppColors.success
                              : AppColors.textMuted;
                      final balLabel = balance > 0
                          ? tr('مستحَق علينا')
                          : balance < 0
                              ? tr('مدفوع زائد')
                              : tr('مسوّى');
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PartyStatementScreen(
                                partyId: party.id,
                                partyName: party.name,
                                isCustomer: true,
                              ),
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.1),
                              child: const Icon(
                                PhosphorIconsBold.buildings,
                                color: AppColors.primary,
                              ),
                            ),
                            title: Text(
                              party.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(party.phone ?? tr('لا يوجد هاتف')),
                            trailing: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  balance.abs().toStringAsFixed(2),
                                  style: TextStyle(
                                    color: balColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  balLabel,
                                  style: TextStyle(
                                    color: balColor,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
    );
  }

  Widget _buildCouriersTab() {
    final couriersAsync = ref.watch(allCouriersProvider);
    final companiesAsync = ref.watch(allDeliveryCompaniesProvider);

    return couriersAsync.when(
      data: (couriers) => couriers.isEmpty
          ? _buildEmptyState(tr('لا يوجد مناديب'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: couriers.length,
              itemBuilder: (context, index) {
                final courier = couriers[index];
                final company = companiesAsync.maybeWhen(
                  data: (list) => list.firstWhere(
                    (c) => c.id == courier.companyId,
                    orElse: () => DeliveryCompany(
                      id: 0,
                      name: tr('توصيل داخلي'),
                      isActive: true,
                      createdAt: DateTime.now(),
                      rowVersion: 0, // v173
                    ),
                  ),
                  orElse: () => null,
                );
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.success.withValues(alpha: 0.1),
                      child: const Icon(
                        PhosphorIconsBold.moped,
                        color: AppColors.success,
                      ),
                    ),
                    title: Text(
                      courier.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      tr('{p0} | {p1}', {'p0': courier.phone ?? "-", 'p1': company?.name ?? "توصيل داخلي"}),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            PhosphorIconsBold.pencil,
                            color: AppColors.primary,
                          ),
                          onPressed: () => _showEditCourierDialog(courier),
                        ),
                        IconButton(
                          icon: const Icon(
                            PhosphorIconsBold.trash,
                            color: AppColors.error,
                          ),
                          onPressed: () =>
                              _deleteCourier(courier.id, courier.name),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(PhosphorIconsLight.info, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
        ],
      ),
    );
  }

  // Dialogs
  // ignore: unused_element
  void _showAddCompanyDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title:  Text(tr('إضافة شركة توصيل')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration:  InputDecoration(labelText: tr('اسم الشركة *')),
              ),
              TextField(
                controller: phoneController,
                decoration:  InputDecoration(labelText: tr('الهاتف')),
              ),
              TextField(
                controller: addressController,
                decoration:  InputDecoration(labelText: tr('العنوان')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _savingCompany ? null : () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: _savingCompany
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) {
                        // BUG-U12: explain the no-op instead of failing silently.
                        ScaffoldMessenger.of(ctx).showSnackBar(
                           SnackBar(content: Text(tr('أدخل اسم الشركة أولاً'))),
                        );
                        return;
                      }
                      setDialogState(() => _savingCompany = true);
                      try {
                        final repo = ref.read(deliveryRepositoryProvider);
                        await repo.insertDeliveryCompany(
                          DeliveryCompaniesCompanion.insert(
                            name: nameController.text,
                            phone: Value(
                              phoneController.text.isEmpty ? null : phoneController.text,
                            ),
                            address: Value(
                              addressController.text.isEmpty
                                  ? null
                                  : addressController.text,
                            ),
                          ),
                        );
                        final user = ref.read(authProvider).user;
                        final activityLogRepo = ref.read(activityLogRepositoryProvider);
                        await activityLogRepo.logActivity(
                          userId: user?.id,
                          userName: user?.displayName ?? tr('مجهول'),
                          action: 'add_delivery_company',
                          entityType: 'delivery_company',
                          description: tr('إضافة شركة توصيل: {p0}', {'p0': nameController.text}),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } finally {
                        if (ctx.mounted) setDialogState(() => _savingCompany = false);
                      }
                    },
              child: _savingCompany
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  :  Text(tr('حفظ')),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  void _showEditCompanyDialog(DeliveryCompany company) {
    final nameController = TextEditingController(text: company.name);
    final phoneController = TextEditingController(text: company.phone ?? '');
    final addressController = TextEditingController(
      text: company.address ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title:  Text(tr('تعديل شركة توصيل')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration:  InputDecoration(labelText: tr('اسم الشركة *')),
              ),
              TextField(
                controller: phoneController,
                decoration:  InputDecoration(labelText: tr('الهاتف')),
              ),
              TextField(
                controller: addressController,
                decoration:  InputDecoration(labelText: tr('العنوان')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _savingCompany ? null : () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: _savingCompany
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) {
                        // BUG-U12: explain the no-op instead of failing silently.
                        ScaffoldMessenger.of(ctx).showSnackBar(
                           SnackBar(content: Text(tr('أدخل اسم الشركة أولاً'))),
                        );
                        return;
                      }
                      setDialogState(() => _savingCompany = true);
                      try {
                        final repo = ref.read(deliveryRepositoryProvider);
                        await repo.updateDeliveryCompany(
                          company.copyWith(
                            name: nameController.text,
                            phone: Value(
                              phoneController.text.isEmpty ? null : phoneController.text,
                            ),
                            address: Value(
                              addressController.text.isEmpty
                                  ? null
                                  : addressController.text,
                            ),
                          ),
                        );
                        final user = ref.read(authProvider).user;
                        final activityLogRepo = ref.read(activityLogRepositoryProvider);
                        await activityLogRepo.logActivity(
                          userId: user?.id,
                          userName: user?.displayName ?? tr('مجهول'),
                          action: 'update_delivery_company',
                          entityType: 'delivery_company',
                          entityId: company.id,
                          description: tr('تعديل شركة توصيل: {p0}', {'p0': nameController.text}),
                          oldValue: company.name,
                          newValue: nameController.text,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } finally {
                        if (ctx.mounted) setDialogState(() => _savingCompany = false);
                      }
                    },
              child: _savingCompany
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  :  Text(tr('حفظ')),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCourierDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    int? selectedCompanyPartyId;
    final deliveryParties = ref.read(allDeliveryPartiesProvider).value ?? [];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title:  Text(tr('إضافة مندوب جديد')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration:  InputDecoration(labelText: tr('اسم المندوب *')),
              ),
              TextField(
                controller: phoneController,
                decoration:  InputDecoration(labelText: tr('الهاتف')),
              ),
              Autocomplete<Party>(
                optionsBuilder: (textValue) {
                  if (textValue.text.isEmpty) return deliveryParties;
                  return deliveryParties.where(
                    (c) => c.name.toLowerCase().contains(
                      textValue.text.toLowerCase(),
                    ),
                  );
                },
                displayStringForOption: (c) => c.name,
                fieldViewBuilder:
                    (ctx2, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: tr('شركة التوصيل'),
                          hintText: tr('ابحث عن الشركة...'),
                          suffixIcon: selectedCompanyPartyId != null
                              ? IconButton(
                                  icon: const Icon(
                                    PhosphorIconsBold.x,
                                    size: 16,
                                  ),
                                  onPressed: () {
                                    controller.clear();
                                    setDialogState(() => selectedCompanyPartyId = null);
                                  },
                                )
                              : null,
                        ),
                      );
                    },
                onSelected: (party) {
                  setDialogState(() => selectedCompanyPartyId = party.id);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _savingCourier ? null : () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: _savingCourier
                  ? null
                  : () async {
                      if (nameController.text.isEmpty) return;
                      setDialogState(() => _savingCourier = true);
                      try {
                        final repo = ref.read(deliveryRepositoryProvider);
                        await repo.insertCourier(
                          CouriersCompanion.insert(
                            name: nameController.text,
                            phone: Value(
                              phoneController.text.isEmpty
                                  ? null
                                  : phoneController.text,
                            ),
                            companyId: Value(selectedCompanyPartyId),
                          ),
                        );
                        final user = ref.read(authProvider).user;
                        final activityLogRepo = ref.read(activityLogRepositoryProvider);
                        await activityLogRepo.logActivity(
                          userId: user?.id,
                          userName: user?.displayName ?? tr('مجهول'),
                          action: 'add_courier',
                          entityType: 'courier',
                          description: tr('إضافة مندوب: {p0}', {'p0': nameController.text}),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } finally {
                        if (ctx.mounted) setDialogState(() => _savingCourier = false);
                      }
                    },
              child: _savingCourier
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  :  Text(tr('حفظ')),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditCourierDialog(Courier courier) {
    final nameController = TextEditingController(text: courier.name);
    final phoneController = TextEditingController(text: courier.phone ?? '');
    int? selectedCompanyPartyId = courier.companyId;
    final deliveryParties = ref.read(allDeliveryPartiesProvider).value ?? [];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title:  Text(tr('تعديل المندوب')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration:  InputDecoration(labelText: tr('اسم المندوب *')),
              ),
              TextField(
                controller: phoneController,
                decoration:  InputDecoration(labelText: tr('الهاتف')),
              ),
              Autocomplete<Party>(
                optionsBuilder: (textValue) {
                  if (textValue.text.isEmpty) return deliveryParties;
                  return deliveryParties.where(
                    (c) => c.name.toLowerCase().contains(
                      textValue.text.toLowerCase(),
                    ),
                  );
                },
                displayStringForOption: (c) => c.name,
                initialValue: selectedCompanyPartyId != null
                    ? TextEditingValue(
                        text:
                            deliveryParties
                                .where((c) => c.id == selectedCompanyPartyId)
                                .firstOrNull
                                ?.name ??
                            '',
                      )
                    : null,
                fieldViewBuilder:
                    (ctx2, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: tr('شركة التوصيل'),
                          hintText: tr('ابحث عن الشركة...'),
                          suffixIcon: selectedCompanyPartyId != null
                              ? IconButton(
                                  icon: const Icon(
                                    PhosphorIconsBold.x,
                                    size: 16,
                                  ),
                                  onPressed: () {
                                    controller.clear();
                                    setDialogState(() => selectedCompanyPartyId = null);
                                  },
                                )
                              : null,
                        ),
                      );
                    },
                onSelected: (party) {
                  setDialogState(() => selectedCompanyPartyId = party.id);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _savingCourier ? null : () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: _savingCourier
                  ? null
                  : () async {
                      if (nameController.text.isEmpty) return;
                      setDialogState(() => _savingCourier = true);
                      try {
                        final repo = ref.read(deliveryRepositoryProvider);
                        await repo.updateCourier(
                          courier.copyWith(
                            name: nameController.text,
                            phone: Value(
                              phoneController.text.isEmpty
                                  ? null
                                  : phoneController.text,
                            ),
                            companyId: Value(selectedCompanyPartyId),
                          ),
                        );
                        final user = ref.read(authProvider).user;
                        final activityLogRepo = ref.read(activityLogRepositoryProvider);
                        await activityLogRepo.logActivity(
                          userId: user?.id,
                          userName: user?.displayName ?? tr('مجهول'),
                          action: 'update_courier',
                          entityType: 'courier',
                          entityId: courier.id,
                          description: tr('تعديل مندوب: {p0}', {'p0': nameController.text}),
                          oldValue: courier.name,
                          newValue: nameController.text,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } finally {
                        if (ctx.mounted) setDialogState(() => _savingCourier = false);
                      }
                    },
              child: _savingCourier
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  :  Text(tr('حفظ')),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _deleteCompany(int id, String name) async {
    if (_deletingCompany) return;
    setState(() => _deletingCompany = true);
    try {
      final repo = ref.read(deliveryRepositoryProvider);
      await repo.deleteDeliveryCompany(id);
      final user = ref.read(authProvider).user;
      final activityLogRepo = ref.read(activityLogRepositoryProvider);
      await activityLogRepo.logActivity(
        userId: user?.id,
        userName: user?.displayName ?? tr('مجهول'),
        action: 'delete_delivery_company',
        entityType: 'delivery_company',
        entityId: id,
        description: tr('حذف شركة توصيل: {name}', {'name': name}),
      );
    } finally {
      if (mounted) setState(() => _deletingCompany = false);
    }
  }

  Future<void> _deleteCourier(int id, String name) async {
    if (_deletingCourier) return;
    // BUG-U05: confirm before the irreversible courier delete.
    final ok = await AppConfirmDialog.show(
      context,
      title: tr('حذف مندوب'),
      message: tr('هل تريد حذف المندوب "{name}"؟ لا يمكن التراجع عن هذا الإجراء.', {'name': name}),
      confirmLabel: tr('حذف'),
      isDangerous: true,
    );
    if (!ok || !mounted) return;
    setState(() => _deletingCourier = true);
    try {
      final repo = ref.read(deliveryRepositoryProvider);
      await repo.deleteCourier(id);
      final user = ref.read(authProvider).user;
      final activityLogRepo = ref.read(activityLogRepositoryProvider);
      await activityLogRepo.logActivity(
        userId: user?.id,
        userName: user?.displayName ?? tr('مجهول'),
        action: 'delete_courier',
        entityType: 'courier',
        entityId: id,
        description: tr('حذف مندوب: {name}', {'name': name}),
      );
    } finally {
      if (mounted) setState(() => _deletingCourier = false);
    }
  }
}

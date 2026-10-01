import 'package:ural_erp/core/i18n/tr.dart';
// حوارُ «إضافة طرف جديد» بهويّة PicPos — **فوركٌ بقرار المالك 2026-08-22**
// («انسخه إلى PicPos ولا تشارك تعديلاتِ PicPos على UralCash»).
//
// المصدر: `screens/parties/party_dialogs.dart` (`showAddPartyDialog`)،
// ويبقى بلا مساسٍ لشاشة UralCash.
//
// بلاغُ المالك: «ديالوج الإضافة مش منسّق بالتنسيق الجديد». والشاشةُ نفسُها
// كانت على التصميم منذ `ea87734c` — والحوارُ وحدَه بقي `AlertDialog` خاماً،
// فبدا غريباً فوق شاشةٍ منسَّقة.
//
// ═══ ⚠️ ما نُسخ حرفيّاً ولماذا ═══
//
// **منطقُ الحفظ منقولٌ بحرفه** — لا «تحسين» ولا اختصار. فهو مسارُ بياناتٍ
// يحمل قراراتٍ مقيسةً سابقاً:
//   • `SyncInterceptor.isClientMode` (لا `NetworkService.isClient`): الثاني
//     كاذبٌ في وضع المرآة فلا تصل أطرافُ مديرِ المرآة إلى المركز.
//   • `NumberUtils.tryParseLocale`: يقبل الأرقامَ العربيّةَ والفاصلة.
//   • الكودُ الفارغُ يُمرَّر `null` ليولّده الـDAO — لا يُخترَع هنا.
//   • فشلُ الحفظ **يُبقي الحوارَ مفتوحاً** ليصحّح المستخدم (سببُه الشائع
//     كودٌ مكرَّرٌ كُتب يدويّاً).
// فأيُّ انحرافٍ في هذه النسخة عطبٌ صامتٌ في بياناتِ عملاءَ وموردين.
//
// **والذي تبدّل هو الغلافُ وحدَه**: `PicPosDialog` بدل `AlertDialog`.
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:ural_erp/core/utils/number_utils.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
// ⚠️ **لا `import 'data/database/sync_interceptor.dart'` هنا.**
//
// `presentation_db_import_guard` يمنع أيَّ ملفِّ عرضٍ **جديد** من استيراد
// `data/database` وقائمتُه البيضاء مقفولة — والأصلُ المنسوخُ منه مُدرَجٌ فيها
// فسُمح له، وهذا الفوركُ جديدٌ فلا يُسمح. (‏سقطت البوّابةُ عليه فعلاً.)
//
// و`isClientModeProvider` موجودٌ سلفاً في طبقة المزوِّدات لهذا الغرض بعينه،
// فيُقرأ منه — والقيمةُ **هي هي** (`SyncInterceptor.isClientMode`)، فلا
// ينحرف السلوكُ عن الأصل: عميلٌ **ومرآةٌ** معاً.
//
// ويصل عبر `providers.dart` وحدَه (يعيد تصديرَ `inventory_providers`)،
// فاستيرادُه صراحةً يُنتج `unnecessary_import` ويكسر خطَّ الأساس ٦ info.
import '../../../data/providers/providers.dart';
import '../../../services/client_write_interceptor.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../screens/parties/party_helpers.dart';
import '../../screens/parties/providers/party_groups_controller.dart';

/// حوارُ إضافة طرفٍ بهويّة PicPos.
void showAddPartyDialogPicpos(
  BuildContext context,
  WidgetRef ref, {
  String initialType = 'customer',
}) => _showPartyDialogPicpos(context, ref, initialType: initialType);

/// نفسُ حوار PicPos، مع تهيئة بيانات الطرف ومسار التحديث القائم.
void showEditPartyDialogPicpos(
  BuildContext context,
  WidgetRef ref,
  Party party,
) => _showPartyDialogPicpos(context, ref, party: party);

void _showPartyDialogPicpos(
  BuildContext context,
  WidgetRef ref, {
  Party? party,
  String initialType = 'customer',
}) {
  final nameController = TextEditingController(text: party?.name ?? '');
  final codeController = TextEditingController(text: party?.code ?? '');
  final phoneController = TextEditingController(text: party?.phone ?? '');
  final addressController = TextEditingController(text: party?.address ?? '');
  final openingBalanceController = TextEditingController(text: '0');
  final creditLimitController = TextEditingController(
    text: party?.creditLimit.toString() ?? '0',
  );
  final paymentTermsController = TextEditingController(
    text: party?.paymentTermsDays.toString() ?? '0',
  );
  String selectedType = party == null
      ? initialType
      : party.isCustomer && party.isSupplier
      ? 'both'
      : party.isDeliveryCompany
      ? 'delivery'
      : party.isSupplier
      ? 'supplier'
      : 'customer';
  String selectedPriceLevel = party?.priceLevel ?? 'default';
  int? selectedGroupId = party?.groupId;
  final selectedBranchIds = party == null || party.isGlobal
      ? <int>[]
      : (party.branchIds ?? '')
            .split(',')
            .map((id) => int.tryParse(id.trim()))
            .whereType<int>()
            .toList();
  int? selectedCostCenterId = party?.costCenterId;

  // الكودُ يُقترَح من مولّد التسلسل في الـDAO، ويُعاد حسابُه كلّما تبدّل
  // النوعُ فتبقى البادئةُ متّسقةً (CUST-/SUP-/CS-/DLV-). وللمستخدم أن
  // يكتبَه بيده — والتفرّدُ يُنفَذ داخل `insertParty`.
  Future<void> refreshCodeSuggestion() async {
    try {
      final db = ref.read(databaseProvider);
      final next = await db.getNextPartyCode(
        isCustomer: selectedType == 'customer' || selectedType == 'both',
        isSupplier: selectedType == 'supplier' || selectedType == 'both',
        isDeliveryCompany: selectedType == 'delivery',
      );
      codeController.text = next;
    } catch (_) {
      // يسقط بصمتٍ إلى فارغ — والـDAO يولّده عند الحفظ.
    }
  }

  if (party == null) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => refreshCodeSuggestion(),
    );
  }

  var saving = false;

  showDialog<void>(
    context: context,
    builder: (context) => Directionality(
      textDirection: Directionality.of(context),
      child: StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> save() async {
            setDialogState(() => saving = true);
            if (nameController.text.isEmpty) {
              AppToast.show(
                context,
                tr('يرجى إدخال الاسم'),
                type: ToastType.error,
              );
              if (context.mounted) setDialogState(() => saving = false);
              return;
            }

            // BUG-U10/U14: تُقبَل الأرقامُ بصيغةٍ عربيّة (فاصلة / أرقام عربيّة).
            final openingBalance =
                NumberUtils.tryParseLocale(openingBalanceController.text) ?? 0;
            final creditLimit =
                NumberUtils.tryParseLocale(creditLimitController.text) ?? 0;
            // سالبٌ لا معنى له — مهلةٌ بالسالب تجعل الفاتورةَ مستحقّةً
            // قبل صدورها. فيُقصّ إلى صفرٍ لا يُرفَض الإدخال.
            final paymentTermsDays =
                (NumberUtils.tryParseLocale(paymentTermsController.text) ?? 0)
                .round()
                .clamp(0, 3650);

            final enteredCode = codeController.text.trim();
            final partyCode = enteredCode.isEmpty ? null : enteredCode;

            try {
              final isCustomer =
                  selectedType == 'customer' || selectedType == 'both';
              final isSupplier =
                  selectedType == 'supplier' || selectedType == 'both';
              final isGlobal = selectedBranchIds.isEmpty;
              final branchIds = isGlobal ? null : selectedBranchIds.join(',');

              if (party != null) {
                final updatedParty = party.copyWith(
                  name: nameController.text,
                  phone: Value(
                    phoneController.text.isEmpty ? null : phoneController.text,
                  ),
                  address: Value(
                    addressController.text.isEmpty
                        ? null
                        : addressController.text,
                  ),
                  isCustomer: isCustomer,
                  isSupplier: isSupplier,
                  isDeliveryCompany: selectedType == 'delivery',
                  creditLimit: creditLimit,
                  paymentTermsDays: paymentTermsDays,
                  priceLevel: selectedPriceLevel,
                  groupId: Value(selectedGroupId),
                  isGlobal: isGlobal,
                  branchIds: Value(branchIds),
                  costCenterId: Value(selectedCostCenterId),
                );
                final updated =
                    await ClientWriteInterceptor.updateParty(party.id, {
                      'name': nameController.text,
                      'phone': phoneController.text.isEmpty
                          ? null
                          : phoneController.text,
                      'address': addressController.text.isEmpty
                          ? null
                          : addressController.text,
                      'isCustomer': isCustomer,
                      'isSupplier': isSupplier,
                      'isDeliveryCompany': selectedType == 'delivery',
                      'creditLimit': creditLimit,
                      'paymentTermsDays': paymentTermsDays,
                      'priceLevel': selectedPriceLevel,
                      'groupId': selectedGroupId,
                      'isGlobal': isGlobal,
                      'branchIds': branchIds,
                      'costCenterId': selectedCostCenterId,
                    });
                if (!updated) {
                  await ref
                      .read(partiesRepositoryProvider)
                      .updateParty(updatedParty);
                }
              } else if (ref.read(isClientModeProvider)) {
                await ClientWriteInterceptor.createParty(
                  name: nameController.text,
                  code: partyCode,
                  phone: phoneController.text.isEmpty
                      ? null
                      : phoneController.text,
                  address: addressController.text.isEmpty
                      ? null
                      : addressController.text,
                  isCustomer: isCustomer,
                  isSupplier: isSupplier,
                  isDeliveryCompany: selectedType == 'delivery',
                  balance: openingBalance,
                  creditLimit: creditLimit,
                  paymentTermsDays: paymentTermsDays,
                  priceLevel: selectedPriceLevel,
                  groupId: selectedGroupId,
                  branchIds: selectedBranchIds,
                  costCenterId: selectedCostCenterId,
                );
              } else {
                await ref
                    .read(partiesRepositoryProvider)
                    .insertParty(
                  PartiesCompanion.insert(
                    name: nameController.text,
                    code: partyCode != null
                        ? Value(partyCode)
                        : const Value.absent(),
                        phone: Value(
                          phoneController.text.isEmpty
                        ? null
                              : phoneController.text,
                        ),
                        address: Value(
                          addressController.text.isEmpty
                              ? null
                              : addressController.text,
                        ),
                        isCustomer: Value(isCustomer),
                        isSupplier: Value(isSupplier),
                    isDeliveryCompany: Value(selectedType == 'delivery'),
                    isActive: const Value(true),
                    balance: Value(openingBalance),
                    creditLimit: Value(creditLimit),
                    paymentTermsDays: Value(paymentTermsDays),
                    priceLevel: Value(selectedPriceLevel),
                    groupId: selectedGroupId != null
                        ? Value(selectedGroupId)
                        : const Value.absent(),
                    isGlobal: Value(isGlobal),
                    branchIds: !isGlobal
                            ? Value(branchIds)
                        : const Value.absent(),
                    costCenterId: selectedCostCenterId != null
                        ? Value(selectedCostCenterId)
                        : const Value.absent(),
                  ),
                );
              }
            } catch (e) {
              // السببُ الشائع كودٌ مكرَّرٌ كُتب يدويّاً. **يبقى الحوارُ
              // مفتوحاً** ليصحّح المستخدمُ بدل أن يفقد ما كتبه.
              if (context.mounted) {
                setDialogState(() => saving = false);
                AppToast.show(
                  context,
                  tr('فشل حفظ الطرف: {e}', {'e': e}),
                  type: ToastType.error,
                );
              }
              return;
            }

            try {
              final auth = ref.read(authProvider);
              final actionKey = party != null
                  ? (party.isSupplier ? 'update_supplier' : 'update_customer')
                  : (selectedType == 'supplier'
                        ? 'add_supplier'
                        : 'add_customer');
              final activityLogRepo = ref.read(activityLogRepositoryProvider);
              await activityLogRepo.logActivity(
                userId: auth.user?.id,
                userName: auth.user?.displayName ?? tr('مستخدم'),
                action: actionKey,
                entityType: 'party',
                entityId: party?.id,
                description: party != null
                    ? tr('تعديل بيانات: {p0}', {'p0': party.name})
                    : tr('إضافة {p0}: {p1}', {
                        'p0': getTypeArabicName(selectedType),
                        'p1': nameController.text,
                      }),
              );
            } catch (_) {}

            if (context.mounted) {
              Navigator.pop(context);
              AppToast.show(
                context,
                party != null
                    ? tr('تم تحديث البيانات بنجاح')
                    : tr('تم إضافة {p0} بنجاح', {
                        'p0': getTypeArabicName(selectedType),
                      }),
                type: ToastType.success,
              );
            }
          }

          return PicPosDialog(
            icon: party == null
                ? PhosphorIconsBold.userPlus
                : PhosphorIconsBold.pencil,
            title: party == null
                ? tr('إضافة طرف جديد')
                : tr('تعديل بيانات {p0}', {'p0': party.name}),
            subtitle: tr('بيانات التعامل والتصنيف ونطاق الفروع'),
            width: 900,
            onCancel: () => Navigator.pop(context),
            primaryAction: PicPosDialogAction(
              label: tr('حفظ'),
              icon: PhosphorIconsBold.floppyDisk,
              busy: saving,
              onPressed: saving ? null : save,
            ),
            body: [
               _FieldLabel(tr('نوع الطرف *')),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments:  [
                  ButtonSegment(
                    value: 'customer',
                    label: Text(tr('عميل')),
                    icon: const Icon(PhosphorIconsBold.user, size: 16),
                  ),
                  ButtonSegment(
                    value: 'supplier',
                    label: Text(tr('مورد')),
                    icon: const Icon(PhosphorIconsBold.truck, size: 16),
                  ),
                  ButtonSegment(
                    value: 'delivery',
                    label: Text(tr('توصيل')),
                    icon: const Icon(PhosphorIconsBold.moped, size: 16),
                  ),
                  ButtonSegment(
                    value: 'both',
                    label: Text(tr('عميل مورد')),
                    icon: const Icon(PhosphorIconsBold.usersThree, size: 16),
                  ),
                ],
                selected: {selectedType},
                onSelectionChanged: (val) {
                  setDialogState(() => selectedType = val.first);
                  if (party == null) {
                  refreshCodeSuggestion().then((_) {
                    if (context.mounted) setDialogState(() {});
                  });
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: nameController,
                      decoration:  InputDecoration(
                        labelText: tr('الاسم *'),
                        prefixIcon: const Icon(
                          PhosphorIconsBold.identificationCard,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: codeController,
                      readOnly: party != null,
                      decoration:  InputDecoration(
                        labelText: tr('الكود'),
                        prefixIcon: const Icon(PhosphorIconsBold.hash),
                        helperText: tr('يُولَّد تلقائياً — قابل للتعديل'),
                        helperMaxLines: 2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration:  InputDecoration(
                  labelText: tr('رقم الهاتف'),
                  prefixIcon: const Icon(PhosphorIconsBold.phone),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: InputDecoration(
                  labelText: tr('العنوان / المنطقة'),
                  prefixIcon: const Icon(PhosphorIconsBold.mapPin),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (party == null) ...[
                  Expanded(
                    child: TextField(
                      controller: openingBalanceController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr('الرصيد الافتتاحي'),
                        prefixIcon: const Icon(PhosphorIconsBold.wallet),
                        suffixText: AppConstants.currencySymbolEn,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: TextField(
                      controller: creditLimitController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr('الحد الائتماني'),
                        prefixIcon: const Icon(PhosphorIconsBold.creditCard),
                        suffixText: AppConstants.currencySymbolEn,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: paymentTermsController,
                      keyboardType: TextInputType.number,
                      decoration:  InputDecoration(
                        labelText: tr('مهلة السداد'),
                        prefixIcon: const Icon(PhosphorIconsBold.calendarCheck),
                        suffixText: tr('يوم'),
                        helperText: tr('صفر = يستحق فور الإصدار'),
                      ),
                    ),
                  ),
                ],
              ),
              if (selectedType == 'customer' || selectedType == 'both') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedPriceLevel,
                  decoration:  InputDecoration(
                    labelText: tr('تصنيف السعر'),
                    prefixIcon: const Icon(PhosphorIconsBold.tag),
                  ),
                  items: kPriceLevels.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(
                    () => selectedPriceLevel = value ?? 'default',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // المجموعةُ تُرشَّح بالدور المختار: مجموعةُ «موردي الجملة» لا
              // تظهر لعميل. و`type == 'both'` تظهر دائماً.
              Consumer(
                builder: (ctx, ref, _) {
                final groupsAsync = ref.watch(activePartyGroupsProvider);
                return groupsAsync.maybeWhen(
                  data: (groups) {
                    final filtered = groups.where((g) {
                      if (g.type == 'both') return true;
                      if (selectedType == 'both') return true;
                      return g.type == selectedType ||
                          (selectedType == 'delivery' &&
                              g.type == 'supplier');
                    }).toList();
                    return DropdownButtonFormField<int?>(
                      initialValue: selectedGroupId,
                      decoration:  InputDecoration(
                        labelText: tr('المجموعة'),
                        prefixIcon: const Icon(PhosphorIconsBold.usersThree),
                        helperText: tr('اختيارى — يمكن تركها فارغة'),
                      ),
                      items: [
                         DropdownMenuItem<int?>(
                          value: null,
                          child: Text(tr('— بدون مجموعة —')),
                        ),
                          ...filtered.map(
                            (g) => DropdownMenuItem<int?>(
                              value: g.id,
                              child: Text(g.name),
                            ),
                          ),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => selectedGroupId = v),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                );
                },
              ),
              const SizedBox(height: 12),
              // الفروعُ تُعرض دائماً ليقرّر المسؤولُ «عامّ» أو «مقصورٌ على
              // فرع» من البداية — وتُخفى فقط حين لا فرعَ أصلاً (قبل التهيئة).
              Consumer(
                builder: (ctx, ref, _) {
                final branchesAsync = ref.watch(allBranchesProvider);
                return branchesAsync.maybeWhen(
                  data: (branches) {
                    if (branches.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         _FieldLabel(tr('تحديد الفروع')),
                        const SizedBox(height: 2),
                        Text(
                          tr('اتركها فارغة لإتاحة الطرف لكل الفروع'),
                          style: TextStyle(
                            fontSize: 11,
                            color: picposDialogMuted(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: branches.map((b) {
                            final sel = selectedBranchIds.contains(b.id);
                            return FilterChip(
                                label: Text(
                                  b.name,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              selected: sel,
                              onSelected: (v) => setDialogState(() {
                                if (v) {
                                  selectedBranchIds.add(b.id);
                                } else {
                                  selectedBranchIds.remove(b.id);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                      ],
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                );
                },
              ),
              const SizedBox(height: 12),
              // مركزُ التكلفة يُرسم دائماً بخيار «— بدون —» ليتركه المسؤولُ
              // فارغاً **عن قصد** لا أن يرثَ فراغاً بصمت.
              Consumer(
                builder: (ctx, ref, _) {
                  final accountingRepo = ref.watch(
                    accountingRepositoryProvider,
                  );
                return FutureBuilder<List<CostCenter>>(
                  future: accountingRepo.getActiveCostCenters(),
                  builder: (context, snap) {
                    final ccList = snap.data ?? const <CostCenter>[];
                    return DropdownButtonFormField<int?>(
                      initialValue: selectedCostCenterId,
                      decoration:  InputDecoration(
                        labelText: tr('مركز التكلفة (اختياري)'),
                          prefixIcon: const Icon(
                            PhosphorIconsBold.treeStructure,
                          ),
                      ),
                      items: [
                         DropdownMenuItem<int?>(
                            value: null,
                            child: Text(tr('— بدون —')),
                          ),
                          ...ccList.map(
                            (cc) => DropdownMenuItem<int?>(
                              value: cc.id,
                              child: Text(trData(cc.name)),
                            ),
                          ),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => selectedCostCenterId = v),
                    );
                  },
                );
                },
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// عنوانُ حقلٍ بخطّ الحوار — بديلُ `Text` عاريةٍ تُكرَّر بمقاسٍ مختلف.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
        ),
      );
}

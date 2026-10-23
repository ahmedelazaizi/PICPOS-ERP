import 'package:picpos_erp/core/i18n/tr.dart';
// شاشةُ العروض بهويّة PicPos — فوركٌ لا تعديلٌ للمشترك.
//
// بلاغُ المالك 2026-08-23: «شاشة العروض مش بهوية picpos عاوزه تتظبط الوانها».
//
// ⚠️ والنسخُ سياسةُ المستودع منذ 2026-08-22: الودجتُ المشتركةُ **تُنسَخ** إلى
// `*_picpos/` وتُعدَّل النسخة. فـ`lib/presentation/screens/offers_screen.dart`
// يبقى كما هو ليخدم UralCash والملفَّاتِ الأخرى، واختباراتُه الأربعةُ القائمةُ
// تظلّ تقيسه هو.
//
// ⚠️ **وليست تبديلَ ألوان**: الشاشاتُ المحوَّلةُ تُعاد على `picpos_shell` —
// `PicPosScreenScaffold` للترويسة والبحث، و`PicPosKpiRow` للعدّادات،
// و`PicPosToolbar` لشريط الترشيح، و`PicPosEmptyState` للفراغ. وهذا ما يجعلها
// **تُشبه** أخواتِها لا مجرّد أن تحمل لونَها.
import 'package:flutter/material.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shimmer_loading.dart';

import '../../data/providers/providers.dart';
import '../../domain/repositories/offers_repository.dart';
import '../../domain/repositories/i_products_repository.dart';
import '../../domain/entities/product_entity.dart';
import '../../services/invoice_generator.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/constants/app_constants.dart';
import '../../core/permissions/permission_codes.dart';
import '../widgets/permission_guard.dart';
import '../picpos_shell/picpos_dialog.dart';
import '../picpos_shell/picpos_empty_state.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import '../picpos_shell/picpos_kpi_row.dart';
import '../picpos_shell/picpos_toolbar.dart';

// ── Part files (mixin-based extraction) ─────────────────────────────────
part 'offer_cards_picpos.dart';
part 'offer_dialogs_picpos.dart';

/// زرُّ «إضافة عرض» بهويّة PicPos.
///
/// ⚠️ الحارسُ `offersCreate` **لا يُنزَع مع الشكل**: الزرُّ كان محميّاً بـ
/// `offers_view` الخشن وحدَه قبل Task 6b، وإعادةُ التنسيق أسهلُ مكانٍ يسقط
/// فيه فحصٌ دقيقٌ سهواً.
@visibleForTesting
Widget buildOffersPicPosCreateButton({required VoidCallback onPressed}) {
  return PermissionGuard(
    permission: PermissionCodes.offersCreate,
    allowManagerOverride: true,
    actionName: tr('إضافة عرض'),
    onGranted: onPressed,
    child: ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(PhosphorIconsBold.plus, size: 16),
      label:  Text(tr('إضافة عرض')),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

/// شاشةُ العروض — باقاتٌ وخصوماتٌ موقّتة، بهويّة PicPos.
class OffersPicPosScreen extends ConsumerStatefulWidget {
  const OffersPicPosScreen({super.key});

  @override
  ConsumerState<OffersPicPosScreen> createState() => _OffersPicPosScreenState();
}

class _OffersPicPosScreenState extends ConsumerState<OffersPicPosScreen>
    with _OfferCardsMixin, _OfferDialogsMixin {
  final _searchController = TextEditingController();
  bool _showActiveOnly = true;
  late Stream<List<Offer>> _offersStream;

  @override
  void initState() {
    super.initState();
    _offersStream = ref.read(offersRepositoryProvider).watchOffers();
  }

  /// Re-subscribe to the stream after a mutation (add/edit/delete)
  @override
  void refreshOffers() {
    setState(() {
      _offersStream = ref.read(offersRepositoryProvider).watchOffers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Shared helpers (used by both mixins) ──────────────────────────────
  @override
  String offerTypeLabel(String type) {
    switch (type) {
      case 'buy_x_get_y':
        return tr('اشترِ X واحصل Y');
      case 'percentage':
        return tr('خصم نسبة');
      case 'fixed_discount':
        return tr('خصم مبلغ');
      case 'bundle':
      default:
        return 'باقة';
    }
  }

  /// ⚠️ ألوانُ الأنواع من لوح PicPos لا من `Colors.*` الخام: `Colors.purple`
  /// و`Colors.teal` و`Colors.orange` ليست ألوانَ أيّ علامة — وهي بعينها
  /// الملاحظةُ التي أُصلحت في هويّة التصنيع.
  @override
  Color offerTypeColor(String type) {
    switch (type) {
      case 'buy_x_get_y':
        return AppColors.info;
      case 'percentage':
        return AppColors.success;
      case 'fixed_discount':
        return AppColors.warning;
      case 'bundle':
      default:
        return AppColors.primary;
    }
  }

  /// الترشيحُ كلُّه في موضعٍ واحد — تقرأه العدّاداتُ والشبكةُ معاً فلا
  /// يفترقان.
  List<Offer> _visible(List<Offer> all) {
    final now = DateTime.now();
    var offers = all;
    if (_showActiveOnly) {
      offers = offers.where((o) {
        if (!o.isActive) return false;
        if (o.endDate != null && o.endDate!.isBefore(now)) return false;
        return true;
      }).toList();
    }
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      offers = offers.where((o) => o.name.toLowerCase().contains(q)).toList();
    }
    return offers;
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(offersRepositoryProvider);
    final productRepo = ref.read(productRepositoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: StreamBuilder<List<Offer>>(
        stream: _offersStream,
        builder: (context, snapshot) {
          final loading =
              snapshot.connectionState == ConnectionState.waiting;
          final all = snapshot.data ?? const <Offer>[];
          final offers = _visible(all);

          // ⚠️ العدّاداتُ تُقاس من الصفوف لا تُخترَع: «المنتهية» تُحسب
          //    بتاريخٍ فعليٍّ مضى، و«الموقوفة» بعلَمها — لا بفرقٍ حسابيّ
          //    يبدو صحيحاً ويكذب عند تداخل الحالتين.
          final now = DateTime.now();
          final active = all
              .where((o) =>
                  o.isActive &&
                  (o.endDate == null || !o.endDate!.isBefore(now)))
              .length;
          final expired = all
              .where((o) => o.endDate != null && o.endDate!.isBefore(now))
              .length;
          final paused = all.where((o) => !o.isActive).length;

          return PicPosScreenScaffold(
            title: tr('العروض'),
            subtitle: tr('إدارة عروض الباقات والأسعار الخاصة'),
            icon: PhosphorIconsBold.tag,
            headerSearch: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                hintText: tr('بحث في العروض...'),
                prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass,
                    size: 16),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(PhosphorIconsBold.x, size: 14),
                        onPressed: () =>
                            setState(() => _searchController.clear()),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            headerActions: [
              buildOffersPicPosCreateButton(
                onPressed: () => showAddOfferDialog(context, repo),
              ),
            ],
            subHeader: PicPosKpiRow(
              kpis: [
                PicPosKpi(
                  label: tr('إجمالي العروض'),
                  value: '${all.length}',
                  icon: PhosphorIconsBold.tag,
                  tint: AppColors.primary,
                ),
                PicPosKpi(
                  label: tr('فعّالة الآن'),
                  value: '$active',
                  icon: PhosphorIconsBold.checkCircle,
                  tint: AppColors.success,
                ),
                PicPosKpi(
                  label: tr('منتهية'),
                  value: '$expired',
                  icon: PhosphorIconsBold.clockCountdown,
                  tint: AppColors.warning,
                ),
                PicPosKpi(
                  label: tr('موقوفة'),
                  value: '$paused',
                  icon: PhosphorIconsBold.pauseCircle,
                  tint: AppColors.textMuted,
                ),
              ],
            ),
            toolbar: PicPosToolbar(
              children: [
                FilterChip(
                  label:  Text(tr('العروض الفعالة فقط')),
                  selected: _showActiveOnly,
                  onSelected: (v) => setState(() => _showActiveOnly = v),
                  avatar: Icon(
                    _showActiveOnly
                        ? PhosphorIconsBold.checkCircle
                        : PhosphorIconsBold.circle,
                    size: 16,
                  ),
                  labelStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                // ⚠️ لا `Spacer` هنا: `PicPosToolbar` هو `Wrap` لا `Row`،
                //    و`Spacer` ودجتُ بياناتِ أبٍ لـ`Flex` وحدَه — فيرمي
                //    «Incorrect use of ParentDataWidget». أمسكه اختبارُ
                //    التركيب، ولم يكن ليظهر في اختبار قطعة.
                Text(
                  tr('المعروض: {p0} من {p1}', {'p0': offers.length, 'p1': all.length}),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            body: loading
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: ShimmerLoading.list(itemCount: 6),
                  )
                : offers.isEmpty
                    ? PicPosEmptyState(
                        icon: PhosphorIconsBold.tag,
                        title: all.isEmpty
                            ? tr('لا توجد عروض')
                            : tr('لا عرضَ يطابق الترشيح'),
                        hint: all.isEmpty
                            ? tr('أنشئ باقةً أو خصماً موقّتاً يظهر في نقطة البيع.')
                            : tr('جرّب مسحَ البحث أو إظهارَ غير الفعّالة.'),
                        action: all.isEmpty
                            ? buildOffersPicPosCreateButton(
                                onPressed: () =>
                                    showAddOfferDialog(context, repo),
                              )
                            : null,
                      )
                    : GridView.builder(
                        padding: EdgeInsets.zero,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 400,
                          mainAxisExtent: 280,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: offers.length,
                        itemBuilder: (ctx, index) =>
                            buildOfferCard(offers[index], repo, productRepo),
                      ),
          );
        },
      ),
    );
  }
}

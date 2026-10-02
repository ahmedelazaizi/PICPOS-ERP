import 'package:ural_erp/core/i18n/tr.dart';
// منطق منسوخ من unified_parties_screen.dart (monolith) — أي إصلاح منطقي
// يتصلّح في المصدر أولاً ثم patch (مصيدة النسخ §٥.٨).
//
// الشاشة الأصل (lib/presentation/screens/unified_parties_screen.dart)
// مونوليث ~500 سطر بلا `part of` files. الـ State (_UnifiedPartiesScreenState)
// بما فيها منطق الفلاتر (`_buildFilters` بـ SegmentedButton لنوع الطرف) وبناء
// القائمة (`_buildPartiesList`) وبطاقة الطرف (`_buildPartyTile` بأزرار سند
// مالي/كشف حساب/تعديل/حذف مع سجلات DiagnosticLogger) كل ده مكتوب inline.
// بما إنه مفيش part نقدر نستوردها، فالفورك هنا بينسخ جسم الدوال دي حرفياً
// بلا أي تعديل منطقي — يتغيّر بس اسم الكلاس وطبقة العرض (تستخدم picpos_shell
// بدل Scaffold+Padding يدوي). عداد إعادة البناء التشخيصي (`_buildCount` /
// DiagnosticLogger('PARTIES-BUILD', ...)) في `build()` الأصلي هو تشخيص
// خاص بمشكلة إعادة بناء الـ Scaffold كامل في الأصل (Spec 115) — الأصل أصلاً
// عالجها بنقل الـ watch لـ Consumer داخلي حول الكارت بس، وهو نفس الهيكل اللي
// الفورك ده بيستخدمه من الأول، فمفيش داعي لعداد التشخيص في طبقة العرض الجديدة.
// `allPartiesProvider` (داخل Consumer يلفّ الكارت فقط)، الحوارات
// (`showAddPartyDialog`/`showEditPartyDialog`/`showDeletePartyDialog`/
// `showExcelOptionsDialog`) من `parties/party_dialogs.dart`، الـ helpers
// (`getPartyTypeLabel`/`getPartyTypeColor`/`getPartyIcon`) من
// `parties/party_helpers.dart`، و`ReceiptVoucherDialog`/`PaymentVoucherDialog`
// و`PartyGroupsScreen` مُعاد استخدامهم من UralCash زي ما هم (import، مش نسخ).
//
// أمّا كشفُ الحساب فبقى له نسخةُ PicPos المستقلّة `PartyStatementPicposScreen`
// (تصميمُ 2026-08-26): خمسُ تبويباتٍ لا شاشةٌ واحدة، وشاشةُ UralCash بلا مساس.
import 'dart:async' show unawaited;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/picpos_party_view.dart';
import '../dialogs/add_party_dialog_picpos.dart';
// كشفُ الحساب صار نسخةَ PicPos المستقلّة (تصميمُ 2026-08-26): خمسُ تبويباتٍ
// على لبنات `picpos_shell` بدل الشاشة الواحدة. وشاشةُ UralCash تبقى بلا مساس
// وتُفتَح من مساراتها هي.
import '../../party_statement_picpos/screens/party_statement_picpos_screen.dart';
import '../../treasury/widgets/receipt_voucher_dialog.dart';
import '../../treasury/widgets/payment_voucher_dialog.dart';
import '../../screens/parties/party_dialogs.dart';
import '../../screens/parties/party_groups_screen.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_kpi_row.dart';
import '../../shared_widgets/whatsapp_send_dialog.dart';
import '../../../domain/models/whatsapp_message.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../domain/models/distribution_model.dart';
import '../../distribution_picpos/distribution_picpos_providers.dart';
import '../../distribution_picpos/screens/dm_routes_tab.dart'
    show showDmAssignCustomerDialog;
import 'party_route_row.dart';

part 'parties_summary_cards.dart';
part 'parties_filter_bar.dart';
part 'parties_card_grid.dart';

/// شاشة العملاء والموردين بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). تعيد استخدام نفس `allPartiesProvider` (عبر Consumer
/// يلفّ الكارت فقط، مش على مستوى الشاشة كلها) والحوارات من
/// `parties/party_dialogs.dart` وHelpers من `parties/party_helpers.dart`
/// و`ReceiptVoucherDialog`/`PaymentVoucherDialog` و`PartyGroupsScreen` من
/// UralCash — فقط طبقة العرض تبدّلت لـ picpos_shell (هيدر PicPosScreenScaffold
/// بدل Row يدوي، وPicPosContentCard حول القائمة بدل Card+elevation).
///
/// وأزرار كشف الحساب الثلاثة تفتح `PartyStatementPicposScreen` — نسخة PicPos
/// المستقلة بتبويباتها الخمس، مش شاشة UralCash.
///
/// FULL PARITY مع الأصل: فلتر نوع الطرف (الكل/عملاء/موردين/توصيل/عميل مورد
/// عبر SegmentedButton)، البحث بالاسم أو الهاتف، قائمة الأطراف مع بطاقة كل
/// طرف (الرصيد + حد الائتمان + أزرار سند مالي/كشف حساب/تعديل/حذف)، إضافة/
/// تعديل/حذف طرف، تصدير/استيراد إكسل، التنقّل لكشف حساب عميل/مورد وشاشة
/// المجموعات.
///
/// راجع lib/presentation/screens/unified_parties_screen.dart (الأصل).
class PartiesPicposScreen extends ConsumerStatefulWidget {
  const PartiesPicposScreen({
    super.key,
    this.scope = PicPosPartyFilter.all,
    this.title = 'العملاء والموردين',
    this.subtitle = 'إدارة الأطراف والأرصدة',
  });

  const PartiesPicposScreen.customers({super.key})
      : scope = PicPosPartyFilter.customer,
        title = 'العملاء',
        subtitle = 'إدارة العملاء والأرصدة';

  const PartiesPicposScreen.suppliers({super.key})
      : scope = PicPosPartyFilter.supplier,
        title = 'الموردون',
        subtitle = 'إدارة الموردين والأرصدة';

  final PicPosPartyFilter scope;
  final String title;
  final String subtitle;

  @override
  ConsumerState<PartiesPicposScreen> createState() =>
      _PartiesPicposScreenState();
}


class _PartiesPicposScreenState extends ConsumerState<PartiesPicposScreen> {
  final _searchController = TextEditingController();
  late PicPosPartyFilter _typeFilter;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.scope;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// تحويلُ صفِّ القاعدة إلى صورةِ العرض.
  ///
  /// هنا — وهنا وحدَه — يلتقي `Party` بـ[PicPosPartyCard]. الملفّاتُ الثلاثةُ
  /// الأخرى (البطاقات · الشريط · الشبكة) لا تعرف القاعدةَ إطلاقاً، فتُختبَر
  /// بلا فتحِ قاعدةٍ ولا حقنِ مزوِّد.
  PicPosPartyCard _toCard(Party p, [CustomerRouteInfo? route]) =>
      PicPosPartyCard(
        routeName: route?.routeName,
        areaName: route?.areaName,
        repName: route?.repName,
        id: p.id,
        name: p.name,
        balance: p.balance,
        creditLimit: p.creditLimit,
        phone: p.phone,
        address: p.address,
        isCustomer: p.isCustomer,
        isSupplier: p.isSupplier,
        isDeliveryCompany: p.isDeliveryCompany == true,
      );

  @override
  Widget build(BuildContext context) {
    return PicPosScreenScaffold(
      title: tr(widget.title),
      subtitle: tr(widget.subtitle),
      icon: PhosphorIconsBold.usersThree,
      headerActions: [
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PartyStatementPicposScreen(),
            ),
          ),
          icon: const Icon(PhosphorIconsBold.user, size: 18),
          label:  Text(tr('كشف حساب عميل')),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PartyStatementPicposScreen(isSupplier: true),
            ),
          ),
          icon: const Icon(PhosphorIconsBold.truck, size: 18),
          label:  Text(tr('كشف حساب مورد')),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.warning,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => showExcelOptionsDialog(context, ref, isExport: true),
          icon: const Icon(PhosphorIconsBold.fileArrowUp, size: 18),
          label:  Text(tr('تصدير')),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => showExcelOptionsDialog(context, ref, isExport: false),
          icon: const Icon(PhosphorIconsBold.fileArrowDown, size: 18),
          label:  Text(tr('استيراد')),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          // فوركُ الحوار بهويّة PicPos — بلاغُ المالك 2026-08-22: الشاشةُ
          // كانت على التصميم والحوارُ وحدَه بقي `AlertDialog` خاماً.
          onPressed: () => showAddPartyDialogPicpos(
            context,
            ref,
            initialType: widget.scope == PicPosPartyFilter.supplier
                ? 'supplier'
                : 'customer',
          ),
          icon: const Icon(PhosphorIconsBold.plus),
          label:  Text(tr('إضافة')),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
          ),
        ),
      ],
      body: RepaintBoundary(
        child: Consumer(
          builder: (context, ref, _) {
            final partiesAsync = ref.watch(allPartiesProvider);
            return partiesAsync.when(
              data: _buildLoaded,
              loading: () => Padding(
                padding: const EdgeInsets.all(16),
                child: ShimmerLoading.list(itemCount: 6),
              ),
              error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoaded(List<Party> rows) {
    // المرحلة و — قائمةُ العملاء تعرض المسارَ والمنطقةَ والمندوبَ المشتقّ.
    final showRoute = widget.scope == PicPosPartyFilter.customer;
    final routes = showRoute
        ? ref.watch(dmCustomerRouteInfoProvider).value ??
            const <int, CustomerRouteInfo>{}
        : const <int, CustomerRouteInfo>{};
    final canAssign = showRoute &&
        (ref
                .watch(hasPermissionProvider(PermissionCodes.distributionManage))
                .value ??
            false);
    final cards = [for (final p in rows) _toCard(p, routes[p.id])];
    final scoped = widget.scope == PicPosPartyFilter.all
        ? cards
        : cards.where((card) => card.matches(widget.scope, '')).toList();
    final kpis = PicPosPartyKpis.from(scoped);
    final filtered =
        scoped.where((card) => card.matches(_typeFilter, _query)).toList();

    // خريطةُ الرجوع إلى صفِّ القاعدة: الحوارُ والسندُ يحتاجان `Party` كاملاً،
    // والبطاقةُ لا تحمله. البحثُ بالمعرّف لا بالفهرس — الترشيحُ يُزيح
    // الفهارسَ فيُفتَح حوارُ طرفٍ غيرِ الذي نُقر.
    final byId = {for (final p in rows) p.id: p};
    Party? lookup(PicPosPartyCard c) => byId[c.id];

    final actions = PartyCardActions(
      onStatement: (c) => _openStatement(lookup(c)),
      onEdit: (c) => _openEdit(lookup(c)),
      onVoucher: (c) => _openVoucher(lookup(c)),
      onDelete: (c) => _openDelete(lookup(c)),
      onWhatsApp: (c) => _openWhatsApp(lookup(c)),
      onAssignRoute: canAssign
          ? (c) => showDmAssignCustomerDialog(context, ref, customerId: c.id)
          : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PartiesSummaryCards(kpis: kpis),
        const SizedBox(height: 12),
        PartiesFilterBar(
          controller: _searchController,
          filter: _typeFilter,
          onFilterChanged: (f) => setState(() => _typeFilter = f),
          onSearchChanged: (v) => setState(() => _query = v),
          showTypeFilters: widget.scope == PicPosPartyFilter.all,
          onGroupsPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PartyGroupsScreen()),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: PicPosContentCard(
            child: PartiesCardGrid(
                parties: filtered, actions: actions, showRoute: showRoute),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ACTIONS — أجسامُها منقولةٌ كما هي من الشاشة قبل إعادة التصميم، بما فيها
  // سجلّاتُ `DiagnosticLogger` (Spec 115): هي تشخيصُ عطبٍ ميدانيٍّ قائم،
  // وحذفُها مع تبديل الشكل كان سيُعمي التشخيصَ بلا سبب.
  //
  // والحارسُ `party == null` جديدٌ: خريطةُ المعرّفات قد لا تجد صفّاً لو بُثّت
  // قائمةٌ أحدثُ بين الرسم والنقر. الصمتُ هنا أصحُّ من `!` تنهار.
  // ═══════════════════════════════════════════════════════════════════════

  void _openStatement(Party? party) {
    if (party == null) return;
    unawaited(DiagnosticLogger.log(
        'PARTIES-ACTION',
        'statement tap partyId=${party.id} name="${party.name}" '
            'isSupplier=${party.isSupplier}'));
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PartyStatementPicposScreen(
            isSupplier: party.isSupplier,
            partyId: party.id,
            partyName: party.name,
          ),
        ),
      ).then((_) => unawaited(DiagnosticLogger.log(
          'PARTIES-ACTION', 'statement route popped partyId=${party.id}')));
    } catch (e, st) {
      unawaited(DiagnosticLogger.log('PARTIES-ACTION',
          'statement route threw partyId=${party.id}: $e\n$st'));
    }
  }

  void _openEdit(Party? party) {
    if (party == null) return;
    unawaited(DiagnosticLogger.log('PARTIES-ACTION',
        'edit tap partyId=${party.id} name="${party.name}"'));
    try {
      showEditPartyDialogPicpos(context, ref, party);
    } catch (e, st) {
      unawaited(DiagnosticLogger.log(
          'PARTIES-ACTION', 'edit dialog threw partyId=${party.id}: $e\n$st'));
    }
  }

  /// إرسالُ كشفِ حسابٍ أو مطالبةٍ على واتساب.
  ///
  /// ⚠️ **والاختيارُ بينهما يُشتقّ من الرصيد لا يُسأل عنه عبثاً**: مطالبةٌ لا
  /// تُبنى إلّا على مستحقٍّ موجب، فعميلٌ مسدَّدٌ أو دائنٌ لا يُعرَض له خيارُ
  /// مطالبةٍ يُنتج نصّاً بصفر — و`composeDueReminderMessage` ترفضه أصلاً.
  Future<void> _openWhatsApp(Party? party) async {
    if (party == null) return;

    final shopName =
        await ref.read(databaseProvider).getSettingValue('company_name') ?? '';
    if (!mounted) return;

    // الإشارةُ في هذا المستودع `+debit / -credit`: الموجبُ مستحقٌّ على العميل.
    final owes = NumberUtils.roundCurrency(party.balance) > 0;
    final choice = owes
        ? await showDialog<String>(
            context: context,
            builder: (ctx) => Directionality(
              textDirection: TextDirection.rtl,
              child: SimpleDialog(
                title:  Text(tr('ماذا تُرسل؟')),
                children: [
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, 'statement'),
                    child:  Text(tr('كشف حساب')),
                  ),
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, 'due'),
                    child:  Text(tr('مطالبة بالمستحقّ')),
                  ),
                ],
              ),
            ),
          )
        : 'statement';
    if (choice == null || !mounted) return;

    final isDue = choice == 'due';
    final message = isDue
        ? composeDueReminderMessage(
            shopName: shopName,
            customerName: party.name,
            dueAmount: party.balance,
          )
        : composeStatementMessage(
            shopName: shopName,
            customerName: party.name,
            balance: party.balance,
            asOf: DateTime.now(),
          );
    // `null` يقع على المطالبة وحدَها — ولا يُفتَح حوارٌ بنصٍّ معدوم.
    if (message == null) return;

    await WhatsAppSendDialog.show(
      context,
      ref,
      title: isDue ? tr('مطالبة بالمستحقّ') : tr('إرسال كشف الحساب'),
      rawPhone: party.phone,
      message: message,
      actionLogLabel: tr('{p0} — {p1}', {'p0': isDue ? tr('مطالبة') : tr('كشف حساب'), 'p1': party.name}),
    );
  }

  void _openVoucher(Party? party) {
    if (party == null) return;
    unawaited(DiagnosticLogger.log(
        'PARTIES-ACTION',
        'voucher tap partyId=${party.id} name="${party.name}" '
            'isSupplier=${party.isSupplier} '
            'isCustomer=${party.isCustomer}'));
    try {
      showDialog(
        context: context,
        builder: (context) {
          if (party.isSupplier && !party.isCustomer) {
            return PaymentVoucherDialog(initialParty: party);
          } else {
            return ReceiptVoucherDialog(initialParty: party);
          }
        },
      ).then((_) => unawaited(DiagnosticLogger.log(
          'PARTIES-ACTION', 'voucher dialog closed partyId=${party.id}')));
    } catch (e, st) {
      unawaited(DiagnosticLogger.log('PARTIES-ACTION',
          'voucher dialog threw partyId=${party.id}: $e\n$st'));
    }
  }

  void _openDelete(Party? party) {
    if (party == null) return;
    unawaited(DiagnosticLogger.log('PARTIES-ACTION',
        'delete tap partyId=${party.id} name="${party.name}"'));
    try {
      showDeletePartyDialog(context, ref, party);
    } catch (e, st) {
      unawaited(DiagnosticLogger.log('PARTIES-ACTION',
          'delete dialog threw partyId=${party.id}: $e\n$st'));
    }
  }
}

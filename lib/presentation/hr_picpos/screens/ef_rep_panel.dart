// J4 — لوحةُ «المندوب» في ملفّ الموظف: مخزنُ السيارة وخزنةُ العهدة
// (‏`rep_resources`)، ومساراتُه (‏`sales_routes.sales_rep_id` مع
// `route_rep_history`)، ودفاترُ سنداته (‏`voucher_books.holder_employee_id`)،
// ورمزُ اقتران تطبيق المندوب من الربط السحابيّ القائم.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/distribution_model.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../../services/cloud_sync/cloud_link_controller.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_picpos_providers.dart';
import '../widgets/hr_form_kit.dart';

class EfRepPanel extends ConsumerStatefulWidget {
  const EfRepPanel({super.key, required this.profile, required this.canManage});
  final EmployeeProfile profile;
  final bool canManage;

  @override
  ConsumerState<EfRepPanel> createState() => _EfRepPanelState();
}

class _EfRepPanelState extends ConsumerState<EfRepPanel> {
  int? _van;
  int? _safe;
  bool _loaded = false;
  int? _routeToAdd;
  int? _bookToAdd;

  int get _id => widget.profile.id!;

  Future<void> _act(Future<void> Function() action, String success) async {
    try {
      await action();
      refreshHr(ref, _id);
      if (mounted) AppToast.show(context, success);
    } catch (e, st) {
      if (!mounted) return;
      if (e is DistributionException || e is HrException) {
        AppToast.show(context, '$e', type: ToastType.error);
      } else {
        AppErrorHandler.handle(context, e, st);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(hrRepAssetsProvider(_id)).value;
    if (assets == null) return const SizedBox.shrink();
    if (!_loaded) {
      _van = assets.resources?.vanWarehouseId;
      _safe = assets.resources?.custodySafeId;
      _loaded = true;
    }
    final canDistribution = widget.canManage &&
        (ref.watch(hasPermissionProvider(PermissionCodes.distributionManage))
                .value ??
            false);
    final otherRoutes = [
      for (final r in assets.allRoutes)
        if (r.repEmployeeId != _id && r.isActive) r,
    ];
    final freeBooks = [
      for (final b in assets.allBooks)
        if (b.holderEmployeeId != _id && b.status == 'active') b,
    ];
    return HrSection(
      title: tr('المندوب'),
      icon: PhosphorIconsBold.truck,
      actions: [
        OutlinedButton.icon(
          key: const Key('ef_rep_pairing'),
          onPressed: widget.canManage ? () => _pairingCode(context) : null,
          icon: const Icon(PhosphorIconsBold.deviceMobile, size: 16),
          label: Text(tr('إصدار رمز اقتران')),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _subTitle(context, tr('العهدة')),
          HrFieldGrid(children: [
            HrDropdown<int>(
              fieldKey: const Key('ef_rep_van'),
              label: tr('مخزن السيارة'),
              value: _van,
              emptyLabel: tr('غير محدد'),
              items: {for (final w in assets.warehouses) w.id: trData(w.name)},
              onChanged: (v) => setState(() => _van = v),
            ),
            HrDropdown<int>(
              fieldKey: const Key('ef_rep_safe'),
              label: tr('خزنة العهدة'),
              value: _safe,
              emptyLabel: tr('غير محدد'),
              items: {for (final s in assets.safes) s.id: trData(s.name)},
              onChanged: (v) => setState(() => _safe = v),
            ),
            Align(
              alignment: AlignmentDirectional.bottomStart,
              child: Padding(
                padding: const EdgeInsets.only(top: 22),
                child: FilledButton.icon(
                  key: const Key('ef_rep_resources_save'),
                  onPressed: !canDistribution
                      ? null
                      : () => _act(
                          () => ref.read(databaseProvider).saveRepResources(
                              employeeId: _id,
                              vanWarehouseId: _van,
                              custodySafeId: _safe),
                          tr('تم حفظ عهدة المندوب')),
                  icon: const Icon(PhosphorIconsBold.check, size: 16),
                  label: Text(tr('حفظ العهدة')),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          _subTitle(context, tr('خطوط السير')),
          if (assets.routes.isEmpty)
            _muted(context, tr('لا خطوط سير لهذا المندوب'))
          else
            for (final r in assets.routes)
              _ItemRow(
                key: Key('ef_rep_route_${r.id}'),
                icon: PhosphorIconsBold.path,
                title: r.name,
                subtitle: tr('{p0} عميل', {'p0': r.customerCount}),
                onRemove: !canDistribution
                    ? null
                    : () => _act(
                        () => ref.read(databaseProvider).setRouteRep(r.id, null),
                        tr('تم فك المسار عن المندوب')),
              ),
          const SizedBox(height: 6),
          _assignRow(
            context,
            dropdown: HrDropdown<int>(
              fieldKey: const Key('ef_rep_route_add'),
              label: tr('إسناد خط سير'),
              value: _routeToAdd,
              emptyLabel: tr('اختر خط سير'),
              items: {
                for (final r in otherRoutes)
                  r.id: [r.name, if (r.repName != null) r.repName!].join(' — '),
              },
              onChanged: (v) => setState(() => _routeToAdd = v),
            ),
            button: FilledButton.icon(
              key: const Key('ef_rep_route_assign'),
              onPressed: !canDistribution || _routeToAdd == null
                  ? null
                  : () {
                      final routeId = _routeToAdd!;
                      setState(() => _routeToAdd = null);
                      _act(
                          () => ref
                              .read(databaseProvider)
                              .setRouteRep(routeId, _id),
                          tr('تم إسناد خط السير للمندوب'));
                    },
              icon: const Icon(PhosphorIconsBold.plus, size: 16),
              label: Text(tr('إسناد')),
            ),
          ),
          const SizedBox(height: 14),
          _subTitle(context, tr('دفاتر السندات')),
          if (assets.books.isEmpty)
            _muted(context, tr('لا دفاتر سندات في عهدته'))
          else
            for (final b in assets.books)
              _ItemRow(
                key: Key('ef_rep_book_${b.id}'),
                icon: PhosphorIconsBold.books,
                title: b.displayName,
                subtitle: '${b.rangeFrom} – ${b.rangeTo}',
                onRemove: !widget.canManage
                    ? null
                    : () => _act(
                        () => ref
                            .read(databaseProvider)
                            .setVoucherBookHolder(b.id, null),
                        tr('تم سحب الدفتر من المندوب')),
              ),
          const SizedBox(height: 6),
          _assignRow(
            context,
            dropdown: HrDropdown<int>(
              fieldKey: const Key('ef_rep_book_add'),
              label: tr('تسليم دفتر سندات'),
              value: _bookToAdd,
              emptyLabel: tr('اختر دفتراً'),
              items: {for (final b in freeBooks) b.id: b.displayName},
              onChanged: (v) => setState(() => _bookToAdd = v),
            ),
            button: FilledButton.icon(
              key: const Key('ef_rep_book_assign'),
              onPressed: !widget.canManage || _bookToAdd == null
                  ? null
                  : () {
                      final bookId = _bookToAdd!;
                      setState(() => _bookToAdd = null);
                      _act(
                          () => ref
                              .read(databaseProvider)
                              .setVoucherBookHolder(bookId, _id),
                          tr('تم تسليم الدفتر للمندوب'));
                    },
              icon: const Icon(PhosphorIconsBold.plus, size: 16),
              label: Text(tr('تسليم')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _assignRow(BuildContext context,
          {required Widget dropdown, required Widget button}) =>
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: dropdown),
        const SizedBox(width: 10),
        button,
      ]);

  Widget _subTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.picposText)),
      );

  Widget _muted(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: TextStyle(fontSize: 12.5, color: context.picposMuted)),
      );

  Future<String?> _pairingPin(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    String pin = '';
    bool keepCurrent = false;
    return showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => PicPosDialog(
            icon: PhosphorIconsBold.deviceMobile,
            title: tr('إصدار رمز اقتران'),
            width: 520,
            onCancel: () => Navigator.pop(ctx),
            primaryAction: PicPosDialogAction(
              label: tr('إصدار رمز اقتران'),
              onPressed: () {
                if (keepCurrent || formKey.currentState!.validate()) {
                  Navigator.pop(ctx, keepCurrent ? '' : pin);
                }
              },
            ),
            body: [
              Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      key: const Key('ef_rep_pin'),
                      onChanged: (value) => pin = value,
                      obscureText: true,
                      enabled: !keepCurrent,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(labelText: tr('الرمز السري للمندوب')),
                      validator: (value) => value == null ||
                              !RegExp(r'^\d{4,8}$').hasMatch(value)
                          ? tr('الرمز السري يجب أن يتكون من 4 إلى 8 أرقام')
                          : null,
                    ),
                    TextFormField(
                      key: const Key('ef_rep_pin_confirmation'),
                      obscureText: true,
                      enabled: !keepCurrent,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(labelText: tr('تأكيد الرمز')),
                      validator: (value) => value != pin
                          ? tr('الرمزان غير متطابقين')
                          : null,
                    ),
                    CheckboxListTile(
                      key: const Key('ef_rep_keep_pin'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('الإبقاء على الرمز الحالي')),
                      value: keepCurrent,
                      onChanged: (value) => setDialogState(() {
                        keepCurrent = value ?? false;
                        if (keepCurrent) {
                          pin = '';
                          formKey.currentState!.reset();
                        }
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  /// رمزُ اقترانٍ لتطبيق المندوب عبر الربط السحابيّ القائم (I-3).
  Future<void> _pairingCode(BuildContext context) async {
    final gid = widget.profile.globalId;
    if (gid == null) return;
    final selectedPin = await _pairingPin(context);
    if (selectedPin == null || !context.mounted) return;
    final keepCurrent = selectedPin.isEmpty;
    try {
      final res = await ref.read(cloudLinkControllerProvider).issueRepPairingCode(
          gid, pin: keepCurrent ? null : selectedPin);
      if (!context.mounted) return;
      if (res == null) {
        AppToast.show(context,
            tr('الربط السحابي غير مُفعَّل — فعّله من إعدادات الربط السحابي أولاً'),
            type: ToastType.warning);
        return;
      }
      final code = '${res['code'] ?? ''}';
      await showDialog<void>(
        context: context,
        builder: (ctx) => PicPosDialog(
          icon: PhosphorIconsBold.deviceMobile,
          title: tr('رمز اقتران تطبيق المندوب'),
          width: 520,
          onCancel: () => Navigator.pop(ctx),
          cancelLabel: tr('إغلاق'),
          primaryAction: PicPosDialogAction(
            label: tr('نسخ'),
            icon: PhosphorIconsBold.copy,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(ctx);
            },
          ),
          body: [
            SelectableText(code,
                key: const Key('ef_rep_pairing_code'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    fontFeatures: [FontFeature.tabularFigures()])),
            Text(
                tr(keepCurrent ? 'لم يتغيّر الرمز السري' : 'الرمز السري: تم ضبطه'),
                textAlign: TextAlign.center),
            Text(tr('رمز الاقتران صالح لمدة 10 دقائق ويُستخدم مرة واحدة.'),
                textAlign: TextAlign.center),
            Text(
                tr('أدخل الرمز في تطبيق المندوب على الموبايل لربطه بهذا الموظف.'),
                textAlign: TextAlign.center),
          ],
        ),
      );
    } catch (e, st) {
      if (context.mounted) AppErrorHandler.handle(context, e, st);
    }
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRemove,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: context.picposBrandInk),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.picposText)),
        ),
        Text(subtitle,
            style: TextStyle(
                fontSize: 12,
                color: context.picposMuted,
                fontFeatures: const [FontFeature.tabularFigures()])),
        IconButton(
          tooltip: tr('إزالة'),
          onPressed: onRemove,
          icon: const Icon(PhosphorIconsBold.x, size: 16),
        ),
      ]),
    );
  }
}

// J4 — مسارُ «إصدار رمز اقتران» لتطبيق المندوب: حوارُ الرمز السري (أو
// الإبقاء عليه) ثمّ حوارُ الرمز الصادر. مستخرَجٌ من لوحة المندوب في ملفّ
// الموظف (`ef_rep_panel.dart`) كي تناديه أيضاً «الإعدادات › الأجهزة
// المرتبطة» بلا نسخةٍ ثانية — السلوكُ والمفاتيحُ (`ef_rep_*`) كما كانت.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../services/cloud_sync/cloud_link_controller.dart';
import '../../picpos_shell/picpos_dialog.dart';

/// Asks for the rep's app PIN, issues a pairing code for [employeeGlobalId]
/// over the cloud link and shows it. A `null` result from the controller
/// means the link is not enabled — the user is pointed to its settings.
Future<void> showRepPairingCodeFlow(BuildContext context,
    CloudLinkController controller, String employeeGlobalId) async {
  final selectedPin = await _pairingPin(context);
  if (selectedPin == null || !context.mounted) return;
  final keepCurrent = selectedPin.isEmpty;
  try {
    final res = await controller.issueRepPairingCode(employeeGlobalId,
        pin: keepCurrent ? null : selectedPin);
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

/// The new PIN, `''` to keep the current one, or `null` when cancelled.
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

import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/feature_settings_providers.dart';
import '../../../data/providers/providers.dart';
import '../../../services/api/table_bill_token.dart';
import '../../../services/generators/base_generator.dart';
import '../../../services/network_service.dart';
import '../../../services/printing/pdf_compute_helper.dart';

/// أكوادُ حسابِ الطاولات — ورقةٌ تُطبَع وتُلصَق على كلّ طاولة.
///
/// ⚠️ **وهذا غيرُ «المنيو الرقمي»** (‏`QrMenuDialog`): ذاك يعرض الأصنافَ
/// للطلب، وهذا يعرض **حسابَ الطاولة الجاري** لمن يجلس عليها.
///
/// ⚠️ **ولا يُرسَم رمزٌ من خدمةٍ على الإنترنت.** الحوارُ الأخُ يبني صورةَ
/// المعاينة من `api.qrserver.com`، فمطعمٌ بلا إنترنت — وهو الحالُ الشائع على
/// شبكةٍ محلّيّةٍ مغلقة — يرى مربّعاتٍ مكسورة. والرمزُ هنا يُولَّد **داخل
/// الورقة** بـ`pw.BarcodeWidget` بلا شبكةٍ أصلاً، والشاشةُ تعرض الرابطَ نصّاً.
class TableBillQrDialog extends ConsumerWidget {
  const TableBillQrDialog({super.key, required this.tables});

  final List<RestaurantTable> tables;

  static Future<void> show(
    BuildContext context,
    List<RestaurantTable> tables,
  ) =>
      showDialog<void>(
        context: context,
        builder: (_) => TableBillQrDialog(tables: tables),
      );

  /// رابطُ حسابِ الطاولة كما يُوضَع في الرمز.
  ///
  /// ⚠️ **[publicBaseUrl] يسبق عنوانَ الشبكة المحلّيّة.** الرمزُ يُطبَع ويُلصَق
  /// على الخشب سنةً، وعنوانُ الشبكة المحلّيّة (`192.168.x.y`) لا يفتح من خارج
  /// المحلّ. فمن نشر خادمَه على دومينٍ يجب أن تحمل ورقتُه الدومين، وإلّا
  /// طُبعت أوراقٌ تعمل داخلَ المحلّ وحدَه وهو يظنّها تعمل من الخارج.
  ///
  /// ⚠️ وبلا [publicBaseUrl] يُبنى بمخطَّط **هذا** الخادم لا بمخطَّط خادمٍ
  /// بعيد: `remoteHttpScheme` على جهاز خادمٍ يساوي `http` دائماً لأن لا
  /// خادمَ بعيداً عنده — فيُطبَع رابطٌ لا يفتح على TLS.
  static String? urlFor(RestaurantTable table, {String? publicBaseUrl}) {
    if (!TableBillToken.isReady) return null;
    final token = TableBillToken.mintTable(table.id);

    final public = normalizeTableBillBaseUrl(publicBaseUrl);
    if (public != null) return '$public/t/$token';

    final ns = NetworkService.instance;
    final host = ns.serverAddress;
    if (host == null || host.isEmpty) return null;
    return '${ns.httpScheme}://$host:${ns.serverPort}/t/$token';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(tableBillQrEnabledProvider);
    final publicBase = ref.watch(tableBillPublicBaseUrlProvider).asData?.value;
    final ns = NetworkService.instance;
    final serving = ns.isServer && ns.isServerRunning;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title:  Row(
          children: [
            const Icon(PhosphorIconsBold.qrCode, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(tr('أكواد حساب الطاولات')),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ⚠️ **ثلاثةُ شروطٍ تُعرَض صراحةً ولا يُترَك فشلُها للتخمين.**
              // ورقةٌ تُطبَع والميزةُ مطفأةٌ أو الخادمُ لا يعمل هي ورقةٌ
              // تُلصَق على الطاولات ولا تفتح شيئاً — ولا يكتشف ذلك إلّا ضيف.
              if (!serving)
                _banner(
                  icon: PhosphorIconsBold.wifiSlash,
                  color: AppColors.error,
                  text: tr('الجهازُ ليس خادماً يعمل — الرابطُ لن يفتح على هواتف الضيوف. شغّل وضعَ الخادم أوّلاً.'),
                ),
              // ⚠️ **المفتاحُ هنا لا في شاشة الإعدادات.** هذا هو الموضعُ
              // الذي يُطبَع منه الرمز؛ ومفتاحٌ في شاشةٍ أخرى يعني ورقةً
              // تُطبَع وتُلصَق ثمّ يُكتشَف أن الميزةَ مطفأة. وحارسُه هو
              // حارسُ فتح هذا الحوار نفسُه (`tables_manage`).
              if (serving)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: enabled.asData?.value ?? false,
                  title:  Text(
                    tr('تفعيل رمز حساب الطاولة'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle:  Text(
                    tr('يفتح مساراً على شبكة المحلّ يقرأ منه الضيفُ حسابَ طاولته بلا تسجيل دخول. أطفِئه إن لم تكن تستعمله.'),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onChanged: enabled.isLoading
                      ? null
                      : (v) async {
                          await writeFeatureSetting(
                            ref,
                            kTableBillQrEnabledKey,
                            '$v',
                          );
                        },
                ),
              if (serving && enabled.asData?.value == true)
                _PublicBaseUrlField(current: publicBase),
              if (publicBase != null)
                _banner(
                  icon: PhosphorIconsBold.globe,
                  color: AppColors.warning,
                  text: tr('الخادمُ منشورٌ على دومين — الرمزُ يفتح من خارج المحلّ. ولذلك يُطلَب من الضيف **رقمُ الطاولة** قبل أن يطلب الحساب أو يضيف أصنافاً، ويقوله له النادل.'),
                ),
              const SizedBox(height: 8),
              Flexible(
                child: tables.isEmpty
                    ?  Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(tr('لا طاولات في النطاق المعروض')),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: tables.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final table = tables[i];
                          final url =
                              urlFor(table, publicBaseUrl: publicBase);
                          return ListTile(
                            dense: true,
                            title: Text(
                              table.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              url ?? tr('لا رابط — الخادمُ غيرُ مهيّأ'),
                              style: TextStyle(
                                fontSize: 11,
                                color: url == null
                                    ? AppColors.error
                                    : AppColors.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: url == null
                                ? null
                                : IconButton(
                                    icon: const Icon(PhosphorIconsBold.copy,
                                        size: 16),
                                    tooltip: tr('نسخ الرابط'),
                                    onPressed: () async {
                                      await Clipboard.setData(
                                          ClipboardData(text: url));
                                      if (context.mounted) {
                                        AppToast.show(context, tr('نُسخ الرابط'));
                                      }
                                    },
                                  ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إغلاق')),
          ),
          ElevatedButton.icon(
            onPressed: tables.isEmpty
                ? null
                : () => _printSheets(context, publicBase),
            icon: const Icon(PhosphorIconsBold.printer),
            label:  Text(tr('طباعة الأكواد')),
          ),
        ],
      ),
    );
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }

  Future<void> _printSheets(BuildContext context, String? publicBase) async {
    final withUrls = <(RestaurantTable, String)>[
      for (final t in tables)
        if (urlFor(t, publicBaseUrl: publicBase) case final url?) (t, url),
    ];
    if (withUrls.isEmpty) {
      AppToast.show(context, tr('لا رابطَ يُطبَع — الخادمُ غيرُ مهيّأ'));
      return;
    }

    final pdf = await BaseGenerator.newDocument();
    for (final (table, url) in withUrls) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          // بدونه تؤول الصفحةُ إلى LTR فلا تُشكَّل «طاولة …» ولا يُعاد ترتيبُها.
          textDirection: pw.TextDirection.rtl,
          build: (context) => pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  tr('طاولة {p0}', {'p0': table.name}),
                  style: pw.TextStyle(
                    fontSize: 30,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(tr('امسح الرمز لترى حسابك'), style: const pw.TextStyle(fontSize: 15)),
                pw.SizedBox(height: 22),
                pw.BarcodeWidget(
                  data: url,
                  barcode: pw.Barcode.qrCode(),
                  width: 230,
                  height: 230,
                ),
                pw.SizedBox(height: 18),
                // ⚠️ والسطرُ يتبع الواقعَ لا يُكتَب مرّةً: ورقةٌ تقول
                // «لا بدّ من شبكة المحلّ» على خادمٍ منشورٍ تُخيف الضيفَ
                // من رمزٍ يعمل، وعكسُها يَعِده بما لا يقع.
                pw.Text(
                  publicBase == null
                      ? tr('الاتّصالُ بشبكة المحلّ شرطٌ لفتح الرابط')
                      : tr('يفتح من أيّ مكان — والرقمُ يُطلَب من النادل'),
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      );
    }
    await PdfComputeHelper.layoutPdf(pdf);
  }
}

/// هل الميزةُ مُشعَلة؟ يُقرأ من القاعدة مباشرةً.
///
/// ⚠️ **ولا يمرّ بالإعدادات المخزَّنة**: تلك تُرجع `null` عند إخفاق الكاش لا
/// عند غياب المفتاح، ومفتاحٌ غيرُ مسجَّلٍ في `preloadKeys` يُقرأ فارغاً دوماً
/// — فتبدو الميزةُ مطفأةً وهي مُشعَلة، والمستخدمُ يُشعلها مرّتين.
/// حقلُ الدومين العامّ.
///
/// ⚠️ **والتحقّقُ عند الحفظ لا عند الطباعة.** عنوانٌ فيه مسارٌ أو بلا مخطَّطٍ
/// يُرفَض هنا بكلمةٍ يقرؤها المشغّل؛ ولو قُبل لطُبعت أوراقٌ ولُصقت ثمّ اكتُشف
/// من ضيفٍ أنّ الرمزَ لا يفتح.
class _PublicBaseUrlField extends ConsumerStatefulWidget {
  const _PublicBaseUrlField({required this.current});

  final String? current;

  @override
  ConsumerState<_PublicBaseUrlField> createState() =>
      _PublicBaseUrlFieldState();
}

class _PublicBaseUrlFieldState extends ConsumerState<_PublicBaseUrlField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.current ?? '');
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _ctrl.text.trim();
    if (raw.isNotEmpty && normalizeTableBillBaseUrl(raw) == null) {
      setState(() => _error = tr('عنوانٌ غيرُ صالح — مثال: https://shop.com'));
      return;
    }
    setState(() => _error = null);
    await writeFeatureSetting(ref, kTableBillPublicBaseUrlKey, raw);
    if (mounted) AppToast.show(context, raw.isEmpty ? tr('أُلغي النشر') : tr('حُفظ'));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                isDense: true,
                labelText: tr('دومين الخادم العامّ (اختياريّ)'),
                labelStyle: const TextStyle(fontSize: 12),
                hintText: 'https://shop.example.com',
                hintStyle: const TextStyle(fontSize: 11.5),
                helperText: tr('اتركه فارغاً إن كان الخادمُ على شبكة المحلّ فقط'),
                helperStyle: const TextStyle(fontSize: 10.5),
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton(
              onPressed: _save,
              child:  Text(tr('حفظ')),
            ),
          ),
        ],
      ),
    );
  }
}


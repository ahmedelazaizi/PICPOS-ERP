import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/design_system/typography.dart';
// شاشةُ «الفوترة الإلكترونية» بهويّة PicPos — على تصميم
// `PicPos E-Invoicing.dc.html`.
//
// ═══ إعادةُ تنسيقٍ لا بناء ═══
//
// الجداولُ الخمسةُ مشحونةٌ سلفاً: `EInvoiceConfigs` (‏بالتسجيل والنشاط والفرع
// والإصدار والترميز وراية الإنتاج والتفعيل) و`EInvoiceSubmissions` (‏بالمعرّفات
// والهاش والحِمل والردّ وعدّاد الإعادة) و`TaxTypes`/`TaxSubtypes`
// و`EInvoiceStatusLog`. فلا جدولَ جديدَ هنا ولا `build_runner`.
//
// ═══ ⚠️ وقراءتان كانتا مبنيّتين وغيرَ مكشوفتَين ═══
//
// `getStatusAuditTrail` موجودةٌ في الـDAO منذ زمنٍ ولم تكن على واجهة
// المستودع إطلاقاً — فسجلُّ الحالات الذي يصفه التصميم كان مكتوباً ولا يُقرأ.
// كُشفت كما هي بلا تغيير سلوك.
//
// و`watchSubmissionsWithInvoice` أُضيفت: الطابورُ يعرض رقمَ الفاتورة واسمَ
// العميل وقيمتَها، و`EInvoiceSubmissions` تحمل `saleId` وحدَه. فإمّا وصلٌ في
// SQL مرّةً واحدة أو N+1 على طابورٍ قد يبلغ مئاتِ المستندات.
//
// ═══ 🔴 والسجلُّ إضافةٌ فقط ═══
//
// «سجل إضافة فقط — لا تعديل ولا حذف لأي سطر» مكتوبٌ في التصميم نصّاً،
// و`logStatusChange` تُدخِل ولا تُحدِّث. فلا تُعرَض هنا أزرارُ تحرير ولا حذفٍ
// لسطرٍ من السجلّ — وغيابُها مقصودٌ لا سهو، ويحرسه فحصٌ صريح.
//
// ═══ ⚠️ وما لم يُنقَل من التصميم ═══
//
// ١) **الضرائبُ المطبَّقةُ على المستند**: التصميمُ يعرضها صفوفاً بكودٍ ونسبةٍ
//    ومبلغ. و`TaxTypes`/`TaxSubtypes` جدولا **تعريفٍ** لا ربطَ بينهما وبين
//    مستندٍ بعينه؛ والمبالغُ الفعليّةُ تعيش داخلَ `rawRequest` نصّاً. فتُقرأ
//    من `taxTotals` في الحِمل المُرسَل إن وُجد، ويُقال صراحةً حين لا حِملَ
//    بعد — بدل اختراع صفوفٍ من جدول التعريف.
//
// ٢) **«مُرسَلة اليوم» على بطاقة المنصّة**: تُحسَب من `submittedAt` لهذا
//    اليوم لا من عدّادٍ مخزَّن.
//
// ٣) ✅ **زرُّ «إلغاء المستند»** — كان مكتوباً هنا أنّ الغلافَ «لا يكشف
//    إلغاءً» وهو **باطل**: `EInvoiceServiceWrapper.cancelDocument` موجودةٌ
//    وتنادي `EtaService.cancelDocument` (‏PUT إلى
//    `/documents/state/{uuid}/state`). فالقدرةُ كانت مبنيّةً وغيرَ مكشوفة،
//    ووُصِّلت 2026-09-03 بثلاثة شروط: صلاحيّةُ `einvoice_cancel` · واعتمادُ
//    البوّابة على هذا الجهاز (الأجهزةُ لا تبلغ البوّابة) · والمستندُ معتمَدٌ
//    (‏لا يُلغى ما لم يُقبل).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/e_invoicing_providers.dart';
import '../../../data/providers/providers.dart';
import '../../../services/e_invoicing/e_invoice_service_wrapper.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../widgets/permission_guard.dart';

final _money = NumberFormat('#,##0.00', 'en');
final _money0 = NumberFormat('#,##0', 'en');
final _stamp = DateFormat('yyyy-MM-dd HH:mm');

const _ok = AppColors.success;
const _warn = AppColors.warning;
const _err = AppColors.error;
const _purple = AppColors.booking;
const _idle = AppColors.textMuted;
const _blue = AppColors.info;

String _ar(Object n) =>
    '$n'.replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)]);

/// الحالاتُ الستّ — نفسُ الرموز التي يكتبها عمودُ `status`.
Map<String, ({String label, IconData icon, Color tint})> get _kStatuses => {
  'pending': (label: tr('معلَّقة'), icon: PhosphorIconsBold.clock, tint: _warn),
  'submitted': (
    label: tr('مُرسَلة'),
    icon: PhosphorIconsBold.paperPlaneTilt,
    tint: _blue
  ),
  'valid': (label: tr('مقبولة'), icon: PhosphorIconsBold.sealCheck, tint: _ok),
  'invalid': (
    label: tr('غير صحيحة'),
    icon: PhosphorIconsBold.warningOctagon,
    tint: _err
  ),
  'rejected': (label: tr('مرفوضة'), icon: PhosphorIconsBold.xCircle, tint: _err),
  'cancelled': (label: tr('ملغاة'), icon: PhosphorIconsBold.prohibit, tint: _idle),
};

/// ترتيبُ المراحل في شريط العدّادات — نفسُ ترتيب التصميم.
const _kStageOrder = [
  'pending',
  'submitted',
  'valid',
  'invalid',
  'rejected',
  'cancelled'
];

/// أنواعُ المستندات الخمسة.
Map<String, ({String label, IconData icon, Color tint})> get _kDocTypes => {
  'invoice': (label: tr('فاتورة'), icon: PhosphorIconsBold.receipt, tint: AppColors.primary),
  'credit_note': (
    label: tr('إشعار دائن'),
    icon: PhosphorIconsBold.arrowUUpLeft,
    tint: _ok
  ),
  'debit_note': (
    label: tr('إشعار مدين'),
    icon: PhosphorIconsBold.arrowUUpRight,
    tint: _warn
  ),
  'export_invoice': (
    label: tr('فاتورة تصدير'),
    icon: PhosphorIconsBold.airplaneTilt,
    tint: _purple
  ),
  'receipt': (label: tr('إيصال'), icon: PhosphorIconsBold.note, tint: _idle),
};

/// المنصّتان اللتان يعرفهما التصميمُ والعمودُ `platform` معاً.
Map<String, ({String name, IconData icon, Color tint})> get _kPlatforms => {
  'eta': (
    name: tr('منظومة الضرائب المصرية — ETA'),
    icon: PhosphorIconsBold.shieldCheck,
    tint: AppColors.primary
  ),
  'jofotara': (
    name: tr('JOFOTARA — الأردن'),
    icon: PhosphorIconsBold.globeHemisphereEast,
    tint: _purple
  ),
};

// ═══════════════════════════════════════════════════════════════════════════
// المجاري
// ═══════════════════════════════════════════════════════════════════════════

final _queueProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) =>
        ref.watch(eInvoiceRepositoryProvider).watchSubmissionsWithInvoice());

/// إعدادُ المنصّة. النوعُ صريحٌ لا `dynamic`: `EInvoiceConfigData` يصل عبر
/// `domain/repositories/e_invoice_repository.dart` (‏يستورد طبقةَ القاعدة بلا
/// بادئة)، فلا يحتاج هذا الملفُّ استيرادَ `data/database` ولا يُطفئ المحلّل.
final _configProvider = FutureProvider.autoDispose
    .family<EInvoiceConfigData?, String>((ref, platform) =>
        ref.watch(eInvoiceRepositoryProvider).getEInvoiceConfig(platform));

/// سجلُّ حالاتِ مستندٍ واحد — يُقرأ عند اختياره لا لكلّ صفٍّ في الطابور.
final _auditProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, submissionId) =>
        ref.watch(eInvoiceRepositoryProvider).getStatusAuditTrail(submissionId));

/// صفٌّ في الطابور مُسطَّحاً — الوصلُ يعطي `Map` فتُقرأ مفاتيحُه هنا مرّةً.
class _Row {
  const _Row({
    required this.id,
    required this.saleId,
    required this.platform,
    required this.documentType,
    required this.status,
    required this.internalId,
    required this.documentUuid,
    required this.longId,
    required this.submissionId,
    required this.hashKey,
    required this.qrCode,
    required this.errorMessage,
    required this.rawRequest,
    required this.rawResponse,
    required this.retryCount,
    required this.submittedAt,
    required this.lastCheckedAt,
    required this.invoiceNumber,
    required this.customerName,
    required this.invoiceTotal,
  });

  final int id;
  final int saleId;
  final String platform;
  final String documentType;
  final String status;
  final String? internalId;
  final String? documentUuid;
  final String? longId;
  final String? submissionId;
  final String? hashKey;
  final String? qrCode;
  final String? errorMessage;
  final String? rawRequest;
  final String? rawResponse;
  final int retryCount;
  final DateTime? submittedAt;
  final DateTime? lastCheckedAt;
  final String? invoiceNumber;
  final String? customerName;
  final double invoiceTotal;

  static DateTime? _date(Object? v) {
    if (v == null) return null;
    // drift يخزّن `DateTime` عدداً بالثواني افتراضاً، و`customSelect` يعيده
    // خاماً — فالتحويلُ هنا لا في العرض.
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v * 1000);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static _Row from(Map<String, dynamic> r) => _Row(
        id: r['id'] as int,
        saleId: (r['sale_id'] as int?) ?? 0,
        platform: (r['platform'] as String?) ?? 'eta',
        documentType: (r['document_type'] as String?) ?? 'invoice',
        status: (r['status'] as String?) ?? 'pending',
        internalId: r['internal_id'] as String?,
        documentUuid: r['document_uuid'] as String?,
        longId: r['long_id'] as String?,
        submissionId: r['submission_id'] as String?,
        hashKey: r['hash_key'] as String?,
        qrCode: r['qr_code'] as String?,
        errorMessage: r['error_message'] as String?,
        rawRequest: r['raw_request'] as String?,
        rawResponse: r['raw_response'] as String?,
        retryCount: (r['retry_count'] as int?) ?? 0,
        submittedAt: _date(r['submitted_at']),
        lastCheckedAt: _date(r['last_checked_at']),
        invoiceNumber: r['invoice_number'] as String?,
        customerName: r['customer_name'] as String?,
        invoiceTotal: (r['invoice_total'] as num?)?.toDouble() ?? 0,
      );

  String get reference =>
      (internalId ?? '').trim().isEmpty ? '#$id' : internalId!;
}

/// بندُ ضريبةٍ مقروءٌ من `taxTotals` في الحِمل المُرسَل.
typedef _TaxLine = ({String code, double amount});

/// يقرأ `taxTotals` من الحِمل — ويعيد فارغاً حين لا حِملَ أو حين يخالف الشكل.
///
/// ⚠️ لا يُرمى الاستثناءُ للأعلى: الحِملُ نصٌّ حرٌّ كتبه مسارُ إرسالٍ آخر،
/// وانهيارُ الشاشة لأنّ مستنداً واحداً حمل JSON معطوباً ثمنٌ غيرُ مقبول.
List<_TaxLine> _taxesOf(String? rawRequest) {
  if (rawRequest == null || rawRequest.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(rawRequest);
    if (decoded is! Map) return const [];
    final totals = decoded['taxTotals'];
    if (totals is! List) return const [];
    return [
      for (final t in totals)
        if (t is Map)
          (
            code: '${t['taxType'] ?? '—'}',
            amount: (t['amount'] as num?)?.toDouble() ?? 0,
          ),
    ];
  } catch (_) {
    return const [];
  }
}

class EInvoicingPicposScreen extends ConsumerStatefulWidget {
  const EInvoicingPicposScreen({super.key});

  @override
  ConsumerState<EInvoicingPicposScreen> createState() =>
      _EInvoicingPicposScreenState();
}

class _EInvoicingPicposScreenState
    extends ConsumerState<EInvoicingPicposScreen> {
  String? _stage;
  String? _docType;
  int? _selectedId;
  bool _showResponse = false;

  /// الفحصُ الجماعيُّ جارٍ — يُعطّل الزرَّ ويُظهر دوّارة.
  ///
  /// ⚠️ حالةُ بناءٍ لا حارسُ إعادةِ دخولٍ وحدَه: الفحصُ نداءاتُ شبكةٍ
  /// متتاليةٌ قد تطول، وزرٌّ لا يقول إنّه يعمل يُضغَط مرّتَين فتنطلق
  /// جولتان متوازيتان على نفس المستندات.
  bool _refreshingAll = false;

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(_queueProvider);
    final rows = (queue.value ?? const <Map<String, dynamic>>[])
        .map(_Row.from)
        .toList();

    final visible = rows.where((r) {
      if (_stage != null && r.status != _stage) return false;
      if (_docType != null && r.documentType != _docType) return false;
      return true;
    }).toList();

    final selected = visible.isEmpty
        ? null
        : visible.firstWhere((r) => r.id == _selectedId,
            orElse: () => visible.first);

    final pending = rows.where((r) => r.status == 'pending').length;

    // ⚠️ «تحديث الحالات» يخصّ **المُرسَلَ المنتظِرَ حكماً** وحدَه.
    //
    //    `pending` لم يُرسَل فلا معرّفَ له يُفحَص؛ و`valid` و`rejected`
    //    و`cancelled` أحكامٌ نهائيّةٌ لا تنقلب بفحص؛ و`invalid` لا يتغيّر
    //    إلّا بإعادة إرسالٍ لا بسؤال. فالباقي `submitted` — وهو بالضبط ما
    //    ينتظر المشغّلُ معرفتَه.
    //
    //    ولا معرّفَ ⇒ لا فحص: صفٌّ بلا `documentUuid` يُعدّ خارجَ العدّ
    //    كيلا يَعِد الزرُّ بعملٍ يرتدّ صامتاً.
    final awaiting = rows
        .where((r) => r.status == 'submitted' && r.documentUuid != null)
        .toList();

    return PicPosScreenScaffold(
      title: tr('الفوترة الإلكترونية'),
      subtitle:
          tr('إرسال الفواتير لمنظومة الضرائب ومتابعة حالتها — كل تغيير حالة يُسجَّل ولا يُحذف'),
      icon: PhosphorIconsBold.broadcast,
      headerActions: [
        // «تحديث الحالات» — الفعلُ الثاني في رأس التصميم، وكان غائباً.
        //
        // ⚠️ **وهو غيرُ محروسٍ عمداً**: نظيرُه لكلِّ صفٍّ («فحص الحالة»)
        //    غيرُ محروس، والمساران واحد. فحراسةُ الجماعيِّ وحدَه كانت
        //    تُعطي أماناً ظاهريّاً يُلتَفّ عليه بصفٍّ صفّاً.
        OutlinedButton.icon(
          onPressed: awaiting.isEmpty || _refreshingAll
              ? null
              : () => _refreshAllStatuses(awaiting),
          icon: _refreshingAll
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(PhosphorIconsBold.arrowsClockwise, size: 15),
          label: Text(tr('تحديث الحالات ({p0})', {'p0': _ar(awaiting.length)})),
        ),
        const SizedBox(width: 8),
        // 🔴 **حارسُ `einvoiceSubmit` واجب.** الإرسالُ فعلٌ خارجيٌّ قانونيّ:
        //    يبعث المستندَ لمنظومة الضرائب ويُنشئ له معرّفاً لا يُلغى إلّا
        //    بمسارٍ آخر. والشاشةُ الأصلُ تحرسه (`buildEinvoiceSubmitButton`)،
        //    وأوّلُ صيغةٍ لهذا الفورك أسقطت الحارسَ — وحصرُ التنقّل
        //    (`einvoice_view`) يفتح الشاشةَ للقراءة لا للإرسال.
        //
        // ⚠️ والعدّادُ مقيسٌ من الصفوف، فالزرُّ يُعطَّل حين لا معلَّقَ — بدل
        //    أن يَعِد بإرسالٍ لا شيءَ فيه.
        PermissionGuard(
          permission: PermissionCodes.einvoiceSubmit,
          child: FilledButton.icon(
            onPressed: pending == 0 ? null : () => _submitPending(pending),
            icon: const Icon(PhosphorIconsBold.paperPlaneTilt, size: 15),
            label: Text(tr('إرسال المعلَّقة ({p0})', {'p0': _ar(pending)})),
          ),
        ),
      ],
      bodyPadding: EdgeInsets.zero,
      body: queue.isLoading && rows.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _platformStrip(rows),
                _stageStrip(rows),
                Expanded(
                  child: LayoutBuilder(builder: (context, box) {
                    // لوحةُ التفصيل ٦٠٠px في التصميم. ودونَ ١٤٠٠ لا يبقى
                    // للطابور عرضٌ معقولٌ فتُطوى إلى حوارٍ عند الاختيار.
                    final wide = box.maxWidth >= 1400;
                    final queuePane = _queuePane(rows, visible, selected, wide);
                    if (!wide) return queuePane;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: queuePane),
                        Container(width: 1, color: context.picposHairline),
                        SizedBox(
                          width: 600,
                          child: selected == null
                              ?  PicPosEmptyState(
                                  icon: PhosphorIconsBold.broadcast,
                                  title: tr('اختر مستنداً من الطابور'),
                                )
                              : _detailPane(selected),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // شريطُ المنصّات
  // ═════════════════════════════════════════════════════════════════════════

  Widget _platformStrip(List<_Row> rows) {
    final today = DateTime.now();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in _kPlatforms.entries) ...[
              SizedBox(
                width: 420,
                child: _platformCard(
                  entry.key,
                  entry.value,
                  rows
                      .where((r) =>
                          r.platform == entry.key &&
                          r.submittedAt != null &&
                          r.submittedAt!.year == today.year &&
                          r.submittedAt!.month == today.month &&
                          r.submittedAt!.day == today.day)
                      .length,
                ),
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _platformCard(
    String id,
    ({String name, IconData icon, Color tint}) meta,
    int sentToday,
  ) {
    final config = ref.watch(_configProvider(id));

    return config.when(
      loading: () => _platformShell(meta, null, sentToday, tr('يُقرأ الإعداد…')),
      // العارضُ يبتلع رمْيَ SQL في بطاقة — فالإخفاقُ يُقال صراحةً.
      error: (_, _) =>
          _platformShell(meta, null, sentToday, tr('تعذّرت قراءةُ إعداد المنصّة')),
      data: (cfg) {
        if (cfg == null) {
          return _platformShell(meta, null, sentToday, tr('لم تُعَدَّ بعد'));
        }
        return _platformShell(
          meta,
          cfg,
          sentToday,
          tr('تسجيل {p0} · نشاط {p1} · فرع {p2} · إصدار {p3} · ترميز {p4}', {'p0': cfg.registrationNumber, 'p1': cfg.activityCode ?? '—', 'p2': cfg.branchId ?? '—', 'p3': cfg.documentVersion, 'p4': cfg.codingSystem}),
          platformId: id,
        );
      },
    );
  }

  Widget _platformShell(
    ({String name, IconData icon, Color tint}) meta,
    EInvoiceConfigData? cfg,
    int sentToday,
    String metaLine, {
    String platformId = 'eta',
  }) {
    final isProduction = cfg?.isProduction ?? false;
    final isEnabled = cfg?.isEnabled ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: Border.all(color: context.picposHairline, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: meta.tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(meta.icon, size: 18, color: meta.tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(meta.name,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 7),
                    _pill(isProduction ? tr('إنتاج') : tr('تجريبي'),
                        isProduction ? _err : _warn),
                    const SizedBox(width: 5),
                    _pill(isEnabled ? tr('مُفعَّل') : tr('موقوف'),
                        isEnabled ? _ok : _idle),
                  ],
                ),
                const SizedBox(height: 3),
                Text(metaLine,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppTypography.mono,
                        color: context.picposMuted),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_ar(sentToday),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: meta.tint)),
              Text(tr('مُرسَلة اليوم'),
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: context.picposMuted)),
            ],
          ),
          // ⚠️ الإعدادُ يحمل `clientSecret` — اعتمادَ البوّابة. وحملُ السرِّ
          //    أخطرُ من الإرسال، فالبوّابةُ `settings_tax` لا `einvoice_submit`.
          //
          //    وبلا هذا الزرّ كان `EInvoiceConfigs` **لا يُكتَب من PicPos
          //    إطلاقاً**: الميزةُ لا تُفعَّل من داخل المنتج، ولا تُكتب رايةُ
          //    `einvoice_enabled` — فيبقى كلُّ جهازٍ «غيرَ مُفعَّل» ويطبع
          //    الرمزَ غيرَ الضريبيّ مهما كانت المنشأةُ مسجَّلة.
          PermissionGuard(
            permission: PermissionCodes.settingsTax,
            child: IconButton(
              tooltip: tr('إعداد المنصّة'),
              iconSize: 17,
              visualDensity: VisualDensity.compact,
              icon: const Icon(PhosphorIconsBold.gearSix),
              onPressed: () => _openConfigForm(platformId, cfg),
            ),
          ),
        ],
      ),
    );
  }

  /// نموذجُ اعتماد المنصّة — يكتب `EInvoiceConfigs` ثمّ يضبط المحرّك.
  ///
  /// ⚠️ وضبطُ المحرّك بعد الحفظ **ليس تجميلاً**: `EInvoiceServiceWrapper` لم
  /// يكن يُضبَط في PicPos إطلاقاً، فكلُّ «إرسال الآن» ينتهي بـ
  /// `StateError: not configured` مبتلَعاً في `catch`.
  Future<void> _openConfigForm(String platform, EInvoiceConfigData? cfg) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EInvoiceConfigDialog(platform: platform, existing: cfg),
    );
    if (saved != true || !mounted) return;

    // المحرّكُ يُضبَط من الإعداد المحفوظ، ثمّ تُبرَّد القراءاتُ المخزَّنة.
    await initializeEInvoiceService(ref, platform);
    if (!mounted) return;
    ref.invalidate(_configProvider(platform));
    _toast(tr('حُفظ إعدادُ المنصّة'));
  }

  // ═════════════════════════════════════════════════════════════════════════
  // شريطُ المراحل
  // ═════════════════════════════════════════════════════════════════════════

  Widget _stageStrip(List<_Row> rows) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final perRow = box.maxWidth < 760 ? 3 : _kStageOrder.length;
        final w = (box.maxWidth - (perRow - 1) * 7) / perRow;
        return Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final key in _kStageOrder)
              SizedBox(
                width: w,
                child: _stageCard(
                    key, rows.where((r) => r.status == key).length),
              ),
          ],
        );
      }),
    );
  }

  Widget _stageCard(String key, int count) {
    final st = _kStatuses[key]!;
    final on = _stage == key;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() {
        _stage = on ? null : key;
        _selectedId = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: on ? st.tint.withValues(alpha: 0.10) : Colors.transparent,
          border: Border.all(
              color: on ? st.tint : context.picposHairline, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(st.icon, size: 14, color: st.tint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(st.label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color:
                              on ? context.picposText : context.picposMuted),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(_ar(count),
                style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800, color: st.tint)),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // الطابور
  // ═════════════════════════════════════════════════════════════════════════

  Widget _queuePane(
    List<_Row> all,
    List<_Row> visible,
    _Row? selected,
    bool wide,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: context.picposCard,
            border: Border(bottom: BorderSide(color: context.picposHairline)),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsBold.queue,
                  size: 16, color: context.picposBrandInk),
              const SizedBox(width: 9),
               Text(tr('طابور الإرسال'),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _stage == null
                      ? tr('{p0} مستنداً', {'p0': _ar(all.length)})
                      : tr('مُصفّى على «{p0}» — {p1} مستنداً', {'p0': _kStatuses[_stage]!.label, 'p1': _ar(visible.length)}),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.picposMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        _docTypeStrip(all),
        Expanded(
          child: visible.isEmpty
              ? PicPosEmptyState(
                  icon: PhosphorIconsBold.queue,
                  title: all.isEmpty
                      ? tr('لا مستنداتٍ في الطابور')
                      : tr('لا مستندَ يطابق الترشيح'),
                  hint: all.isEmpty
                      ? tr('المستندُ يُنشأ من فاتورة البيع بعد ترحيلها، ثمّ يُرسَل للمنظومة ويُتابَع حتّى يُقبَل.')
                      : null,
                )
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, i) =>
                      _queueRow(visible[i], selected?.id == visible[i].id, wide),
                ),
        ),
      ],
    );
  }

  Widget _docTypeStrip(List<_Row> all) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final e in _kDocTypes.entries) ...[
              () {
                final n = all.where((r) => r.documentType == e.key).length;
                final on = _docType == e.key;
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() {
                    _docType = on ? null : e.key;
                    _selectedId = null;
                  }),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: on
                          ? e.value.tint.withValues(alpha: 0.10)
                          : Colors.transparent,
                      border: Border.all(
                          color: on ? e.value.tint : context.picposHairline,
                          width: 1.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(e.value.icon,
                            size: 12,
                            color: on ? e.value.tint : context.picposMuted),
                        const SizedBox(width: 5),
                        Text(e.value.label,
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: on
                                    ? e.value.tint
                                    : context.picposMuted)),
                        const SizedBox(width: 5),
                        Text(_ar(n),
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: (on ? e.value.tint : context.picposMuted)
                                    .withValues(alpha: 0.65))),
                      ],
                    ),
                  ),
                );
              }(),
              const SizedBox(width: 7),
            ],
          ],
        ),
      ),
    );
  }

  Widget _queueRow(_Row r, bool on, bool wide) {
    final st = _kStatuses[r.status] ?? _kStatuses['pending']!;
    final doc = _kDocTypes[r.documentType] ?? _kDocTypes['invoice']!;

    return InkWell(
      onTap: () {
        setState(() => _selectedId = r.id);
        if (!wide) _openDetailSheet(r);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: on
              ? context.picposBrandInk.withValues(alpha: 0.06)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: context.picposHairline),
            right: BorderSide(
                color: on ? context.picposBrandInk : Colors.transparent,
                width: 3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: st.tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(st.icon, size: 14, color: st.tint),
            ),
            const SizedBox(width: 9),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.reference,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          fontFamily: AppTypography.mono),
                      overflow: TextOverflow.ellipsis),
                  Text(r.invoiceNumber ?? tr('فاتورة #{p0}', {'p0': r.saleId}),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: context.picposMuted),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Text(r.customerName ?? '—',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            _pill(doc.label, doc.tint),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Text(_money0.format(r.invoiceTotal),
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _pill(st.label, st.tint),
                  if (r.retryCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(tr('أُعيدت {p0} مرات', {'p0': _ar(r.retryCount)}),
                          style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: _err)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 104,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    r.lastCheckedAt == null
                        ? '—'
                        : _stamp.format(r.lastCheckedAt!),
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: context.picposText),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    r.submittedAt == null
                        ? tr('لم تُرسَل')
                        : _stamp.format(r.submittedAt!),
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: context.picposMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetailSheet(_Row r) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
          child: _detailPane(r),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // لوحةُ التفصيل
  // ═════════════════════════════════════════════════════════════════════════

  Widget _detailPane(_Row r) {
    final st = _kStatuses[r.status] ?? _kStatuses['pending']!;
    final taxes = _taxesOf(r.rawRequest);

    return Container(
      color: context.picposCard,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: st.tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(st.icon, size: 20, color: st.tint),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(r.reference,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: AppTypography.mono),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        _pill(st.label, st.tint),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.invoiceNumber ?? 'فاتورة #${r.saleId}'} · '
                      '${r.customerName ?? '—'} · ${_money0.format(r.invoiceTotal)}',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.picposMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _detailActions(r),
          const SizedBox(height: 14),
          _idsPanel(r),
          if ((r.errorMessage ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _errorCard(r),
          ],
          const SizedBox(height: 14),
          _rawPanel(r),
          const SizedBox(height: 14),
          _logPanel(r),
          const SizedBox(height: 14),
          _taxPanel(taxes),
        ],
      ),
    );
  }

  /// أفعالُ المستند.
  ///
  /// ⚠️ «إلغاء المستند» في التصميم لا يُعرَض هنا — لا مسارَ إلغاءٍ في
  /// `EInvoiceServiceWrapper`، وزرٌّ يظهر ولا يفعل أسوأُ من زرٍّ غائب.
  Widget _detailActions(_Row r) {
    // 🔴 هل يملك **هذا الجهازُ** اعتمادَ البوّابة أصلاً؟
    //
    // قرارُ المالك: الخادمُ وحدَه يحمل السرَّ ويرسل، و`EInvoiceConfigs` خارجَ
    // المزامنة. فجهازُ الكاشير لا إعدادَ عنده ⇒ المحرّكُ غيرُ مضبوط ⇒ كلُّ
    // «إرسال الآن» كان ينتهي بـ`StateError: not configured` **مبتلَعاً** ثمّ
    // يُوسَم المستندُ «فاشلاً» بخطأٍ لا يفهمه أحد. والمستندُ يصل البوّابةَ من
    // الخادم بالمِكنسة، فالانتظارُ صحيحٌ لا عطب.
    final hasCredentials = ref.watch(_configProvider(r.platform)).maybeWhen(
          data: (c) => c != null,
          orElse: () => false,
        );

    final canSend = hasCredentials &&
        (r.status == 'pending' ||
            r.status == 'invalid' ||
            r.status == 'submitted');
    return Row(
      children: [
        if (!hasCredentials) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(PhosphorIconsBold.cloudArrowUp, size: 14),
              label:  Text(tr('الإرسال يتم من الخادم')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _refreshStatus(r),
              icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 14),
              label:  Text(tr('فحص الحالة')),
            ),
          ),
        ] else ...[
        // 🔴 نفسُ حارس زرِّ الإرسال الجماعيّ — والمسارُ واحدٌ فالحراسةُ واحدة.
        //    و`fallback` يشرح الغيابَ بدل أن يختفيَ الزرُّ بلا تفسير.
        Expanded(
          child: PermissionGuard(
            permission: PermissionCodes.einvoiceSubmit,
            fallback: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(PhosphorIconsBold.lockSimple, size: 14),
              label:  Text(tr('الإرسال يحتاج صلاحية')),
            ),
            child: FilledButton.icon(
              onPressed: canSend ? () => _submitOne(r) : null,
              icon: const Icon(PhosphorIconsBold.paperPlaneTilt, size: 14),
              label: Text(r.status == 'pending' ? tr('إرسال الآن') : tr('إعادة إرسال')),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _refreshStatus(r),
            icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 14),
            label:  Text(tr('فحص الحالة')),
          ),
        ),
        // ⚠️ **إلغاءُ المستند** — كان الرأسُ يقول إنّ الغلافَ «لا يكشف
        //    إلغاءً»، وهو **باطل**: `cancelDocument` موجودةٌ وتنادي
        //    `EtaService.cancelDocument` (‏PUT إلى
        //    `/documents/state/{uuid}/state`). فالقدرةُ مبنيّةٌ ولم تكن
        //    مكشوفة.
        //
        //    ولا يُعرَض إلّا لمستندٍ **معتمَد**: لا شيءَ لدى البوّابة يُلغى
        //    قبل القبول. وبصلاحيّةٍ خاصّةٍ — إلغاءُ مستندٍ ضريبيٍّ معتمَدٍ أثرٌ
        //    لا يُعطى لكلّ من يرسل.
        if (r.status == 'valid' && r.documentUuid != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: PermissionGuard(
              permission: PermissionCodes.einvoiceCancel,
              child: OutlinedButton.icon(
                onPressed: () => _cancelDocument(r),
                icon: const Icon(PhosphorIconsBold.prohibit, size: 14),
                label:  Text(tr('إلغاء المستند')),
              ),
            ),
          ),
        ],
        ],
      ],
    );
  }

  /// يلغي المستندَ لدى البوّابة — بسببٍ مكتوب.
  ///
  /// البوّابةُ تشترط سبباً، والإلغاءُ **لا رجعةَ فيه**: مستندٌ ضريبيٌّ معتمَدٌ
  /// يُسحَب من الإقرار. فيُستأذَن أوّلاً، ويُكتب الحكمُ بسجلّ تدقيقٍ لا بكتابةٍ
  /// عارية.
  Future<void> _cancelDocument(_Row r) async {
    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Text(tr('إلغاء المستند لدى المنظومة')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('سيُسحَب {p0} من الإقرار الضريبيّ. والإلغاءُ لا رجعةَ فيه.', {'p0': r.reference})),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtl,
              autofocus: true,
              decoration:  InputDecoration(
                labelText: tr('سبب الإلغاء'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text(tr('تراجع'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:  Text(tr('إلغاء المستند'))),
        ],
      ),
    );

    final reason = reasonCtl.text.trim();
    reasonCtl.dispose();
    if (ok != true || !mounted) return;

    if (reason.isEmpty) {
      _toast(tr('الإلغاء يحتاج سبباً — لم يُرسَل شيء'));
      return;
    }

    final repo = ref.read(eInvoiceRepositoryProvider);
    final wrapper = ref.read(eInvoiceServiceProvider);
    try {
      final done = await wrapper.cancelDocument(r.documentUuid!, reason);
      if (!done) {
        if (!mounted) return;
        _toast(tr('لم تقبل المنظومةُ الإلغاء'));
        return;
      }
      await repo.updateSubmissionStatus(r.id, 'cancelled');
      if (!mounted) return;
      _toast(tr('أُلغي {p0}', {'p0': r.reference}));
    } catch (e) {
      // الإخفاقُ يُقال — ولا يُوسَم المستندُ ملغىً وهو قائمٌ لدى البوّابة.
      if (!mounted) return;
      _toast(tr('تعذّر الإلغاء: {e}', {'e': e}));
    }
  }

  Widget _idsPanel(_Row r) {
    final ids = <({String label, String value})>[
      (label: tr('معرّف المستند'), value: r.documentUuid ?? tr('لم يصدر معرّف بعد')),
      (label: tr('المعرّف الطويل'), value: r.longId ?? '—'),
      (label: tr('معرّف الإرسال'), value: r.submissionId ?? '—'),
      (label: tr('هاش المستند'), value: r.hashKey ?? tr('يُحسب عند الإرسال')),
      (
        label: tr('كود QR'),
        value: (r.qrCode ?? '').trim().isEmpty
            ? tr('لا يصدر إلا بعد القبول')
            : r.qrCode!
      ),
    ];

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
           PicPosSectionHeader(
            title: tr('معرّفات المستند'),
            icon: PhosphorIconsBold.hash,
          ),
          for (final d in ids)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(d.label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: context.picposMuted)),
                  ),
                  Expanded(
                    child: SelectableText(d.value,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: AppTypography.mono,
                            color: context.picposText)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(PhosphorIconsBold.copy, size: 14),
                    tooltip: tr('نسخ'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: d.value));
                      if (!mounted) return;
                      _toast(tr('نُسخ «{p0}»', {'p0': d.label}));
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _errorCard(_Row r) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: _err.withValues(alpha: 0.07),
        border: Border.all(color: _err.withValues(alpha: 0.35), width: 1.5),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsBold.warningOctagon,
                  size: 16, color: _err),
              const SizedBox(width: 8),
               Expanded(
                child: Text(tr('رفضُ المنظومة'),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _err)),
              ),
              if (r.retryCount > 0)
                Text(tr('أُعيدت {p0} مرات', {'p0': _ar(r.retryCount)}),
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: context.picposMuted)),
            ],
          ),
          const SizedBox(height: 7),
          SelectableText(r.errorMessage!,
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.6,
                  fontWeight: FontWeight.w600,
                  color: context.picposText)),
        ],
      ),
    );
  }

  Widget _rawPanel(_Row r) {
    final body = _showResponse ? r.rawResponse : r.rawRequest;
    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
               Expanded(
                child: Text(tr('الحِمل المُرسَل والرد'),
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
              _rawTab(tr('الحِمل المُرسَل'), !_showResponse,
                  () => setState(() => _showResponse = false)),
              const SizedBox(width: 6),
              _rawTab(tr('رد المنظومة'), _showResponse,
                  () => setState(() => _showResponse = true)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            decoration: BoxDecoration(
              // كتلةُ الكود داكنةٌ في الوضعَين معاً — كما في التصميم.
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  (body ?? '').trim().isEmpty
                      ? (_showResponse
                          ? tr('// لا ردَّ بعد — لم يُرسَل المستند')
                          : tr('// لا حِملَ محفوظاً لهذا المستند'))
                      : body!,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.75,
                    fontFamily: AppTypography.mono,
                    color: Color(0xFFA5C4F7),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rawTab(String label, bool on, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on
                ? context.picposBrandInk.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border.all(
                color: on ? context.picposBrandInk : context.picposHairline,
                width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: on ? context.picposBrandInk : context.picposMuted)),
        ),
      );

  /// سجلُّ الحالات — إضافةٌ فقط.
  ///
  /// 🔴 لا زرَّ تحريرٍ ولا حذفٍ لسطر: `logStatusChange` تُدخِل ولا تُحدِّث،
  /// والتصميمُ يكتب «سجل إضافة فقط — لا تعديل ولا حذف لأي سطر». وغيابُ
  /// الأزرار مقصودٌ لا سهو.
  Widget _logPanel(_Row r) {
    final audit = ref.watch(_auditProvider(r.id));

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
           PicPosSectionHeader(
            title: tr('سجل الحالات'),
            subtitle: tr('سجل إضافة فقط — لا تعديل ولا حذف لأي سطر'),
            icon: PhosphorIconsBold.lockSimple,
          ),
          audit.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(tr('تعذّرت قراءةُ سجلّ الحالات'),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.picposMuted)),
            ),
            data: (rows) => rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(tr('لا تغييراتِ حالةٍ مسجَّلةً بعد'),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.picposMuted)),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [for (final e in rows) _logRow(e)],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _logRow(Map<String, dynamic> e) {
    final to = (e['new_status'] as String?) ?? '';
    final from = (e['old_status'] as String?) ?? '—';
    final meta = _kStatuses[to];
    final tint = meta?.tint ?? _idle;
    final changedAt = _Row._date(e['changed_at']);
    final who = (e['changed_by'] as String?) ?? 'system';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(meta?.icon ?? PhosphorIconsBold.dotOutline,
                size: 12, color: tint),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(_kStatuses[from]?.label ?? from,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: context.picposMuted)),
                    const SizedBox(width: 6),
                    Icon(PhosphorIconsBold.arrowLeft,
                        size: 11, color: context.picposMuted),
                    const SizedBox(width: 6),
                    Text(meta?.label ?? to,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: tint)),
                  ],
                ),
                if ((e['notes'] as String?)?.trim().isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(e['notes'] as String,
                        style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                            color: context.picposText)),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '${who == 'system' ? 'النظام' : who}'
                    '${changedAt == null ? '' : ' · ${_stamp.format(changedAt)}'}',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: context.picposMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// الضرائبُ — مقروءةٌ من `taxTotals` في الحِمل، لا من جدول التعريف.
  Widget _taxPanel(List<_TaxLine> taxes) {
    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
           PicPosSectionHeader(
            title: tr('الضرائب المطبَّقة على المستند'),
            subtitle: tr('مقروءة من الحِمل المُرسَل — لا من جدول أنواع الضرائب'),
            icon: PhosphorIconsBold.percent,
          ),
          if (taxes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                tr('لا ضرائبَ في الحِمل — أو لم يُبنَ الحِملُ بعد'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.picposMuted),
              ),
            )
          else
            for (final t in taxes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:
                            context.picposBrandInk.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(t.code,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              fontFamily: AppTypography.mono,
                              color: context.picposBrandInk)),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(child: SizedBox.shrink()),
                    Text(_money.format(t.amount),
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color tint) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: tint)),
      );

  // ═════════════════════════════════════════════════════════════════════════
  // الأفعال
  // ═════════════════════════════════════════════════════════════════════════

  /// إرسالُ المعلَّقة وفحصُ الحالات.
  ///
  /// ⚠️ **المنطقُ منقولٌ عن `_retryPending`/`_pollStatuses` في الشاشة الأصل**
  /// (`e_invoice_dashboard_screen.dart`) بلا تعديلٍ سلوكيّ — هما مكتوبتان
  /// inline في مونوليث بلا مزوِّدٍ يُستورَد، فلا سبيلَ لإعادة الاستعمال
  /// إلّا النسخ. وأيُّ إصلاحٍ منطقيٍّ يقع في الأصل أوّلاً ثمّ يُنقَل هنا.

  Future<void> _submitPending(int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(PhosphorIconsBold.paperPlaneTilt,
            color: AppColors.primary),
        title:  Text(tr('إرسال المستندات المعلَّقة')),
        content: Text(tr('سيُرسَل {p0} مستنداً للمنظومة، ويُسجَّل لكلٍّ تغييرُ حالته في سجلٍّ لا يُحذف.', {'p0': _ar(count)})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text(tr('إلغاء'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:  Text(tr('إرسال'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final repo = ref.read(eInvoiceRepositoryProvider);
    final wrapper = ref.read(eInvoiceServiceProvider);
    final pending = await repo.getPendingSubmissions();

    var success = 0, failed = 0;
    for (final sub in pending) {
      try {
        final payload = await repo.buildInvoicePayload(sub.saleId, sub.platform);
        final result =
            await wrapper.submitInvoice(UnifiedInvoice.fromPayload(payload));
        if (result.success) {
          await repo.markSubmissionSuccess(
            submissionId: sub.id,
            submissionUuid: result.submissionId ?? '',
            documentUuid: result.documentUuid,
            qrCode: result.qrCode,
          );
          success++;
        } else {
          await repo.markSubmissionFailed(
              sub.id, result.errorMessage ?? tr('إخفاقٌ بلا رسالة'));
          failed++;
        }
      } catch (e) {
        await repo.markSubmissionFailed(sub.id, '$e');
        failed++;
      }
    }

    if (!mounted) return;
    _toast(tr('من {p0}: نجح {p1} وأخفق {p2}', {'p0': _ar(pending.length), 'p1': _ar(success), 'p2': _ar(failed)}));
  }

  Future<void> _submitOne(_Row r) async {
    final repo = ref.read(eInvoiceRepositoryProvider);
    final wrapper = ref.read(eInvoiceServiceProvider);
    try {
      final payload = await repo.buildInvoicePayload(r.saleId, r.platform);
      final result =
          await wrapper.submitInvoice(UnifiedInvoice.fromPayload(payload));
      if (result.success) {
        await repo.markSubmissionSuccess(
          submissionId: r.id,
          submissionUuid: result.submissionId ?? '',
          documentUuid: result.documentUuid,
          qrCode: result.qrCode,
        );
        if (!mounted) return;
        _toast(tr('أُرسل {p0} — تابعْ حالتَه في السجلّ', {'p0': r.reference}));
      } else {
        await repo.markSubmissionFailed(
            r.id, result.errorMessage ?? tr('إخفاقٌ بلا رسالة'));
        if (!mounted) return;
        _toast(tr('رفضت المنظومةُ {p0}', {'p0': r.reference}));
      }
    } catch (e) {
      await repo.markSubmissionFailed(r.id, '$e');
      if (!mounted) return;
      _toast(tr('تعذّر الإرسال: {e}', {'e': e}));
    }
  }

  /// فحصٌ جماعيٌّ لكلّ مستندٍ مُرسَلٍ ينتظر حكماً.
  ///
  /// ⚠️ **يمرّ على الكلّ ولا يتوقّف عند أوّل إخفاق.** المنظومةُ تردّ لمستندٍ
  /// وتعجز عن آخر (‏انقطاعٌ · مهلة)، والتوقّفُ عند الأوّل يترك ما بعده
  /// بحالةٍ قديمةٍ بلا أن يعلم المشغّل. فيُعدّ الناجحُ والمتغيّرُ والمخفقُ
  /// ويُقال العددُ صراحةً.
  ///
  /// ⚠️ والتقريرُ يفصل **المفحوصَ** عن **المتغيّر**: «فُحص ٧ ولم يتغيّر
  /// شيء» خبرٌ مفيد، و«حُدِّثت ٧» عنه كذبٌ يُطمئِن على غير أساس.
  Future<void> _refreshAllStatuses(List<_Row> awaiting) async {
    setState(() => _refreshingAll = true);
    final repo = ref.read(eInvoiceRepositoryProvider);
    final wrapper = ref.read(eInvoiceServiceProvider);

    var changed = 0;
    var failed = 0;

    for (final r in awaiting) {
      try {
        final status = await wrapper.checkStatus(r.documentUuid!);
        if (status.isValid) {
          await repo.updateSubmissionStatus(r.id, 'valid');
          changed++;
        } else if (status.isRejected) {
          await repo.updateSubmissionStatus(
            r.id,
            'invalid',
            errorMessage: status.errors.isNotEmpty
                ? status.errors.first.toString()
                : tr('مرفوضة'),
          );
          changed++;
        }
        if (mounted) ref.invalidate(_auditProvider(r.id));
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() => _refreshingAll = false);
    final checked = awaiting.length - failed;
    _toast(
      failed == 0
          ? tr('فُحص {p0} — تغيّرت حالةُ {p1}', {'p0': _ar(checked), 'p1': _ar(changed)})
          : tr('فُحص {p0} — تغيّرت {p1} · تعذّر {p2}', {'p0': _ar(checked), 'p1': _ar(changed), 'p2': _ar(failed)}),
    );
  }

  Future<void> _refreshStatus(_Row r) async {
    if (r.documentUuid == null) {
      // لا معرّفَ ⇒ لا شيءَ يُفحَص. وقولُ ذلك أصدقُ من نداءٍ يعود صامتاً.
      _toast(tr('لا معرّفَ للمستند بعد — يصدر عند الإرسال'));
      return;
    }
    final repo = ref.read(eInvoiceRepositoryProvider);
    final wrapper = ref.read(eInvoiceServiceProvider);
    try {
      final status = await wrapper.checkStatus(r.documentUuid!);
      if (status.isValid) {
        await repo.updateSubmissionStatus(r.id, 'valid');
      } else if (status.isRejected) {
        await repo.updateSubmissionStatus(
          r.id,
          'invalid',
          errorMessage: status.errors.isNotEmpty
              ? status.errors.first.toString()
              : tr('مرفوضة'),
        );
      }
      if (!mounted) return;
      ref.invalidate(_auditProvider(r.id));
      _toast(tr('حُدِّثت حالةُ {p0}', {'p0': r.reference}));
    } catch (e) {
      if (!mounted) return;
      _toast(tr('تعذّر فحصُ الحالة: {e}', {'e': e}));
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// نموذجُ اعتماد المنصّة — الموضعُ الوحيدُ الذي يكتب `EInvoiceConfigs` في PicPos
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️ **السرُّ لا يُعرَض ولا يُمحى بالسهو**: حقلُ «سر العميل» يُفتح بالقيمة
// المحفوظة ويُحجب حرفُه، فحفظٌ لم يُغيّره يُبقيه كما هو. ونموذجٌ يفتح فارغاً
// كان سيمحو اعتمادَ البوّابة عند أوّل حفظ.
class _EInvoiceConfigDialog extends ConsumerStatefulWidget {
  final String platform;
  final EInvoiceConfigData? existing;

  const _EInvoiceConfigDialog({required this.platform, this.existing});

  @override
  ConsumerState<_EInvoiceConfigDialog> createState() =>
      _EInvoiceConfigDialogState();
}

class _EInvoiceConfigDialogState extends ConsumerState<_EInvoiceConfigDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _clientId;
  late final TextEditingController _secret;
  late final TextEditingController _registration;
  late final TextEditingController _activity;
  late final TextEditingController _branch;
  late String _version;
  late String _coding;
  late bool _production;
  late bool _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _clientId = TextEditingController(text: c?.clientId ?? '');
    _secret = TextEditingController(text: c?.clientSecret ?? '');
    _registration = TextEditingController(text: c?.registrationNumber ?? '');
    _activity = TextEditingController(text: c?.activityCode ?? '');
    _branch = TextEditingController(text: c?.branchId ?? '');
    _version = c?.documentVersion ?? '1.0';
    _coding = c?.codingSystem ?? 'EGS';
    _production = c?.isProduction ?? false;
    _enabled = c?.isEnabled ?? false;
  }

  @override
  void dispose() {
    _clientId.dispose();
    _secret.dispose();
    _registration.dispose();
    _activity.dispose();
    _branch.dispose();
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? tr('حقلٌ مطلوب') : null;

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(eInvoiceRepositoryProvider).saveEInvoiceConfig(
            platform: widget.platform,
            clientId: _clientId.text.trim(),
            clientSecret: _secret.text.trim(),
            registrationNumber: _registration.text.trim(),
            activityCode:
                _activity.text.trim().isEmpty ? null : _activity.text.trim(),
            branchId: _branch.text.trim().isEmpty ? null : _branch.text.trim(),
            documentVersion: _version,
            codingSystem: _coding,
            isProduction: _production,
            isEnabled: _enabled,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // الإخفاقُ يُقال — ولا يُبتلَع في حوارٍ يُغلَق كأنّ شيئاً حُفظ.
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('تعذّر الحفظ: {e}', {'e': e}))));
    }
  }

  Widget _field(TextEditingController c, String label,
          {bool obscure = false, bool required = true}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: c,
          obscureText: obscure,
          validator: required ? _required : null,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('إعداد {p0}', {'p0': widget.platform == 'eta' ? 'مصلحة الضرائب' : 'جوفوترة'})),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_registration, tr('الرقم الضريبي')),
                _field(_clientId, tr('معرّف العميل')),
                _field(_secret, tr('سر العميل'), obscure: true),
                _field(_activity, tr('كود النشاط'), required: false),
                _field(_branch, tr('كود الفرع'), required: false),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _version,
                        decoration:  InputDecoration(
                            labelText: tr('إصدار المستند'),
                            isDense: true,
                            border: const OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: '0.9', child: Text('0.9')),
                          DropdownMenuItem(value: '1.0', child: Text('1.0')),
                        ],
                        onChanged: (v) => setState(() => _version = v ?? '1.0'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _coding,
                        decoration:  InputDecoration(
                            labelText: tr('نظام الترميز'),
                            isDense: true,
                            border: const OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'EGS', child: Text('EGS')),
                          DropdownMenuItem(value: 'GPC', child: Text('GPC')),
                          DropdownMenuItem(value: 'GS1', child: Text('GS1')),
                        ],
                        onChanged: (v) => setState(() => _coding = v ?? 'EGS'),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  value: _production,
                  onChanged: (v) => setState(() => _production = v),
                  title:  Text(tr('بيئة الإنتاج')),
                  subtitle:  Text(tr('موقوفاً تُرسَل المستندات إلى البيئة التجريبية')),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                  title:  Text(tr('تفعيل الفوترة الإلكترونية')),
                  // الرايةُ المُزامَنةُ تُشتقّ من هذا الحقل — وهي التي تحكم
                  // رمزَ الإيصال على كلّ جهاز.
                  subtitle:  Text(
                      tr('يحكم أيضاً رمز الإيصال المطبوع على كل جهاز')),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child:  Text(tr('إلغاء')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child:  Text(tr('حفظ')),
        ),
      ],
    );
  }
}

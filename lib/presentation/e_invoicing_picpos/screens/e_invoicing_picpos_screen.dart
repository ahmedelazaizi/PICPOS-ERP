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
// ٣) **زرُّ «إلغاء المستند»**: التصميمُ يعرضه للمقبولة. والإلغاءُ في المنظومة
//    مسارُ شبكةٍ لا تملكه هذه الشاشة (‏`EInvoiceServiceWrapper` لا يكشف
//    إلغاءً)، فلا يُعرَض زرٌّ يظهر ولا يفعل.

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
import '../../../domain/repositories/e_invoice_repository.dart';
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

const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _err = Color(0xFFEF4444);
const _purple = Color(0xFF8B5CF6);
const _idle = Color(0xFF6B7280);
const _blue = Color(0xFF4A80E8);

String _ar(Object n) =>
    '$n'.replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)]);

/// الحالاتُ الستّ — نفسُ الرموز التي يكتبها عمودُ `status`.
const Map<String, ({String label, IconData icon, Color tint})> _kStatuses = {
  'pending': (label: 'معلَّقة', icon: PhosphorIconsBold.clock, tint: _warn),
  'submitted': (
    label: 'مُرسَلة',
    icon: PhosphorIconsBold.paperPlaneTilt,
    tint: _blue
  ),
  'valid': (label: 'مقبولة', icon: PhosphorIconsBold.sealCheck, tint: _ok),
  'invalid': (
    label: 'غير صحيحة',
    icon: PhosphorIconsBold.warningOctagon,
    tint: _err
  ),
  'rejected': (label: 'مرفوضة', icon: PhosphorIconsBold.xCircle, tint: _err),
  'cancelled': (label: 'ملغاة', icon: PhosphorIconsBold.prohibit, tint: _idle),
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
const Map<String, ({String label, IconData icon, Color tint})> _kDocTypes = {
  'invoice': (label: 'فاتورة', icon: PhosphorIconsBold.receipt, tint: AppColors.primary),
  'credit_note': (
    label: 'إشعار دائن',
    icon: PhosphorIconsBold.arrowUUpLeft,
    tint: _ok
  ),
  'debit_note': (
    label: 'إشعار مدين',
    icon: PhosphorIconsBold.arrowUUpRight,
    tint: _warn
  ),
  'export_invoice': (
    label: 'فاتورة تصدير',
    icon: PhosphorIconsBold.airplaneTilt,
    tint: _purple
  ),
  'receipt': (label: 'إيصال', icon: PhosphorIconsBold.note, tint: _idle),
};

/// المنصّتان اللتان يعرفهما التصميمُ والعمودُ `platform` معاً.
const Map<String, ({String name, IconData icon, Color tint})> _kPlatforms = {
  'eta': (
    name: 'منظومة الضرائب المصرية — ETA',
    icon: PhosphorIconsBold.shieldCheck,
    tint: AppColors.primary
  ),
  'jofotara': (
    name: 'JOFOTARA — الأردن',
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

    return PicPosScreenScaffold(
      title: 'الفوترة الإلكترونية',
      subtitle:
          'إرسال الفواتير لمنظومة الضرائب ومتابعة حالتها — كل تغيير حالة يُسجَّل ولا يُحذف',
      icon: PhosphorIconsBold.broadcast,
      headerActions: [
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
            label: Text('إرسال المعلَّقة (${_ar(pending)})'),
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
                              ? const PicPosEmptyState(
                                  icon: PhosphorIconsBold.broadcast,
                                  title: 'اختر مستنداً من الطابور',
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
      loading: () => _platformShell(meta, null, sentToday, 'يُقرأ الإعداد…'),
      // العارضُ يبتلع رمْيَ SQL في بطاقة — فالإخفاقُ يُقال صراحةً.
      error: (_, _) =>
          _platformShell(meta, null, sentToday, 'تعذّرت قراءةُ إعداد المنصّة'),
      data: (cfg) {
        if (cfg == null) {
          return _platformShell(meta, null, sentToday, 'لم تُعَدَّ بعد');
        }
        return _platformShell(
          meta,
          cfg,
          sentToday,
          'تسجيل ${cfg.registrationNumber} · نشاط ${cfg.activityCode ?? '—'}'
          ' · فرع ${cfg.branchId ?? '—'} · إصدار ${cfg.documentVersion}'
          ' · ترميز ${cfg.codingSystem}',
        );
      },
    );
  }

  Widget _platformShell(
    ({String name, IconData icon, Color tint}) meta,
    EInvoiceConfigData? cfg,
    int sentToday,
    String metaLine,
  ) {
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
                    _pill(isProduction ? 'إنتاج' : 'تجريبي',
                        isProduction ? _err : _warn),
                    const SizedBox(width: 5),
                    _pill(isEnabled ? 'مُفعَّل' : 'موقوف',
                        isEnabled ? _ok : _idle),
                  ],
                ),
                const SizedBox(height: 3),
                Text(metaLine,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
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
              Text('مُرسَلة اليوم',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: context.picposMuted)),
            ],
          ),
        ],
      ),
    );
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
              const Text('طابور الإرسال',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _stage == null
                      ? '${_ar(all.length)} مستنداً'
                      : 'مُصفّى على «${_kStatuses[_stage]!.label}» — ${_ar(visible.length)} مستنداً',
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
                      ? 'لا مستنداتٍ في الطابور'
                      : 'لا مستندَ يطابق الترشيح',
                  hint: all.isEmpty
                      ? 'المستندُ يُنشأ من فاتورة البيع بعد ترحيلها، ثمّ '
                          'يُرسَل للمنظومة ويُتابَع حتّى يُقبَل.'
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
                          fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis),
                  Text(r.invoiceNumber ?? 'فاتورة #${r.saleId}',
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
                      child: Text('أُعيدت ${_ar(r.retryCount)} مرات',
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
                        ? 'لم تُرسَل'
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
                                  fontFamily: 'monospace'),
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
    final canSend = r.status == 'pending' ||
        r.status == 'invalid' ||
        r.status == 'submitted';
    return Row(
      children: [
        // 🔴 نفسُ حارس زرِّ الإرسال الجماعيّ — والمسارُ واحدٌ فالحراسةُ واحدة.
        //    و`fallback` يشرح الغيابَ بدل أن يختفيَ الزرُّ بلا تفسير.
        Expanded(
          child: PermissionGuard(
            permission: PermissionCodes.einvoiceSubmit,
            fallback: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(PhosphorIconsBold.lockSimple, size: 14),
              label: const Text('الإرسال يحتاج صلاحية'),
            ),
            child: FilledButton.icon(
              onPressed: canSend ? () => _submitOne(r) : null,
              icon: const Icon(PhosphorIconsBold.paperPlaneTilt, size: 14),
              label: Text(r.status == 'pending' ? 'إرسال الآن' : 'إعادة إرسال'),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _refreshStatus(r),
            icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 14),
            label: const Text('فحص الحالة'),
          ),
        ),
      ],
    );
  }

  Widget _idsPanel(_Row r) {
    final ids = <({String label, String value})>[
      (label: 'معرّف المستند', value: r.documentUuid ?? 'لم يصدر معرّف بعد'),
      (label: 'المعرّف الطويل', value: r.longId ?? '—'),
      (label: 'معرّف الإرسال', value: r.submissionId ?? '—'),
      (label: 'هاش المستند', value: r.hashKey ?? 'يُحسب عند الإرسال'),
      (
        label: 'كود QR',
        value: (r.qrCode ?? '').trim().isEmpty
            ? 'لا يصدر إلا بعد القبول'
            : r.qrCode!
      ),
    ];

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PicPosSectionHeader(
            title: 'معرّفات المستند',
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
                            fontFamily: 'monospace',
                            color: context.picposText)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(PhosphorIconsBold.copy, size: 14),
                    tooltip: 'نسخ',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: d.value));
                      if (!mounted) return;
                      _toast('نُسخ «${d.label}»');
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
              const Expanded(
                child: Text('رفضُ المنظومة',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _err)),
              ),
              if (r.retryCount > 0)
                Text('أُعيدت ${_ar(r.retryCount)} مرات',
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
              const Expanded(
                child: Text('الحِمل المُرسَل والرد',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
              _rawTab('الحِمل المُرسَل', !_showResponse,
                  () => setState(() => _showResponse = false)),
              const SizedBox(width: 6),
              _rawTab('رد المنظومة', _showResponse,
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
                          ? '// لا ردَّ بعد — لم يُرسَل المستند'
                          : '// لا حِملَ محفوظاً لهذا المستند')
                      : body!,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.75,
                    fontFamily: 'monospace',
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
          const PicPosSectionHeader(
            title: 'سجل الحالات',
            subtitle: 'سجل إضافة فقط — لا تعديل ولا حذف لأي سطر',
            icon: PhosphorIconsBold.lockSimple,
          ),
          audit.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('تعذّرت قراءةُ سجلّ الحالات',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.picposMuted)),
            ),
            data: (rows) => rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text('لا تغييراتِ حالةٍ مسجَّلةً بعد',
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
          const PicPosSectionHeader(
            title: 'الضرائب المطبَّقة على المستند',
            subtitle: 'مقروءة من الحِمل المُرسَل — لا من جدول أنواع الضرائب',
            icon: PhosphorIconsBold.percent,
          ),
          if (taxes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'لا ضرائبَ في الحِمل — أو لم يُبنَ الحِملُ بعد',
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
                              fontFamily: 'monospace',
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
        title: const Text('إرسال المستندات المعلَّقة'),
        content: Text('سيُرسَل ${_ar(count)} مستنداً للمنظومة، ويُسجَّل لكلٍّ '
            'تغييرُ حالته في سجلٍّ لا يُحذف.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إرسال')),
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
        final result = await wrapper.submitInvoice(
          UnifiedInvoice(
            internalId: payload['internalId'] ?? '',
            issueDate: DateTime.now(),
            seller: (payload['seller'] as Map<String, dynamic>?) ?? {},
            items: [],
          ),
        );
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
              sub.id, result.errorMessage ?? 'إخفاقٌ بلا رسالة');
          failed++;
        }
      } catch (e) {
        await repo.markSubmissionFailed(sub.id, '$e');
        failed++;
      }
    }

    if (!mounted) return;
    _toast('من ${_ar(pending.length)}: نجح ${_ar(success)} وأخفق ${_ar(failed)}');
  }

  Future<void> _submitOne(_Row r) async {
    final repo = ref.read(eInvoiceRepositoryProvider);
    final wrapper = ref.read(eInvoiceServiceProvider);
    try {
      final payload = await repo.buildInvoicePayload(r.saleId, r.platform);
      final result = await wrapper.submitInvoice(
        UnifiedInvoice(
          internalId: payload['internalId'] ?? '',
          issueDate: DateTime.now(),
          seller: (payload['seller'] as Map<String, dynamic>?) ?? {},
          items: [],
        ),
      );
      if (result.success) {
        await repo.markSubmissionSuccess(
          submissionId: r.id,
          submissionUuid: result.submissionId ?? '',
          documentUuid: result.documentUuid,
          qrCode: result.qrCode,
        );
        if (!mounted) return;
        _toast('أُرسل ${r.reference} — تابعْ حالتَه في السجلّ');
      } else {
        await repo.markSubmissionFailed(
            r.id, result.errorMessage ?? 'إخفاقٌ بلا رسالة');
        if (!mounted) return;
        _toast('رفضت المنظومةُ ${r.reference}');
      }
    } catch (e) {
      await repo.markSubmissionFailed(r.id, '$e');
      if (!mounted) return;
      _toast('تعذّر الإرسال: $e');
    }
  }

  Future<void> _refreshStatus(_Row r) async {
    if (r.documentUuid == null) {
      // لا معرّفَ ⇒ لا شيءَ يُفحَص. وقولُ ذلك أصدقُ من نداءٍ يعود صامتاً.
      _toast('لا معرّفَ للمستند بعد — يصدر عند الإرسال');
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
              : 'مرفوضة',
        );
      }
      if (!mounted) return;
      ref.invalidate(_auditProvider(r.id));
      _toast('حُدِّثت حالةُ ${r.reference}');
    } catch (e) {
      if (!mounted) return;
      _toast('تعذّر فحصُ الحالة: $e');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

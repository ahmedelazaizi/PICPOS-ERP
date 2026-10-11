import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/i18n/tr.dart';

import '../../../core/theme/app_colors.dart';
import '../../../services/db_encryption_actions.dart';
import '../../../services/generators/base_generator.dart';
import '../../../services/printing/pdf_compute_helper.dart';
import '../../../services/db_key_boot.dart';
import '../../../services/db_key_portable_export.dart';
import '../../picpos_shell/picpos_dialog.dart';

/// أسماءُ الأحجام بالعربية للعرض فقط.
String formatBytes(int b) {
  const mb = 1024 * 1024;
  if (b >= 1024 * mb) return '${(b / (1024 * mb)).toStringAsFixed(1)} GB';
  if (b >= mb) return '${(b / mb).toStringAsFixed(1)} MB';
  return '${(b / 1024).toStringAsFixed(0)} KB';
}

/// طباعةُ رمز الاسترداد عبر قمع الطباعة المعتمد (`PdfComputeHelper`).
Future<void> printRecoveryCode(String code) async {
  final doc = await BaseGenerator.newDocument();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    textDirection: pw.TextDirection.rtl,
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(tr('رمز استرداد قاعدة البيانات'),
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 16),
        pw.Directionality(
          textDirection: pw.TextDirection.ltr,
          child: pw.Text(code, style: const pw.TextStyle(fontSize: 20)),
        ),
        pw.SizedBox(height: 16),
        pw.Text(tr(
            'احتفظ بهذه الورقة في مكان آمن؛ من يملك الرمز يستطيع فتح قاعدتك.')),
      ],
    ),
  ));
  await PdfComputeHelper.layoutPdf(doc, name: 'recovery-code');
}

/// حوارُ رمز الاسترداد: يُعرَض مرّةً واحدة ولا يُغلَق إلا بعد تأكيد «حفظتُ
/// الرمز». يعيد `true` عند التأكيد. لا يُخزَّن الرمزُ نصًّا في أيّ مكان من
/// هنا (يأتي من التخزين الآمن ويُحذف بعد التأكيد في المستدعي).
class RecoveryCodeDialog extends StatefulWidget {
  const RecoveryCodeDialog({super.key, required this.code, this.onPrint});

  final String code;

  /// الافتراضيّ: [printRecoveryCode]. يُحقَن في الاختبار.
  final Future<void> Function(String code)? onPrint;

  static Future<bool> show(BuildContext context, String code,
      {Future<void> Function(String code)? onPrint}) async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RecoveryCodeDialog(code: code, onPrint: onPrint),
    );
    return r == true;
  }

  @override
  State<RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<RecoveryCodeDialog> {
  bool _saved = false;
  String? _note;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: Dialog(
          key: const Key('dbenc_code_dialog'),
          insetPadding: const EdgeInsets.all(24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('رمز استرداد قاعدة البيانات'),
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(
                    tr('يظهر هذا الرمز مرة واحدة فقط. هو الطريقة الوحيدة لفتح قاعدتك إن فُقد مفتاح التشفير من هذا الحساب. احفظه خارج هذا الجهاز.'),
                    style: const TextStyle(height: 1.6),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      widget.code,
                      key: const Key('dbenc_code_text'),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      key: const Key('dbenc_code_copy'),
                      icon: const Icon(Icons.copy, size: 18),
                      label: Text(tr('نسخ')),
                      onPressed: () {
                        unawaited(Clipboard.setData(ClipboardData(text: widget.code))
                            .catchError((_) {}));
                        setState(() => _note = tr('تم النسخ'));
                      },
                    ),
                    OutlinedButton.icon(
                      key: const Key('dbenc_code_print'),
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: Text(tr('طباعة')),
                      onPressed: () async {
                        try {
                          await (widget.onPrint ?? printRecoveryCode)(
                              widget.code);
                        } catch (_) {
                          if (mounted) {
                            setState(() => _note = tr('تعذّرت الطباعة'));
                          }
                        }
                      },
                    ),
                  ]),
                  if (_note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_note!, style: const TextStyle(fontSize: 12)),
                    ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    key: const Key('dbenc_code_saved'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _saved,
                    onChanged: (v) => setState(() => _saved = v == true),
                    title: Text(tr('حفظتُ الرمز في مكان آمن')),
                  ),
                  const SizedBox(height: 4),
                  FilledButton(
                    key: const Key('dbenc_code_done'),
                    onPressed: _saved ? () => Navigator.pop(context, true) : null,
                    child: Text(tr('تم')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// قرارُ المدير في حوار الترقية.
class UpgradeDecision {
  const UpgradeDecision({required this.spaceConfirmed});
  final bool spaceConfirmed;
}

/// «ترقية التشفير»: شرحٌ + فحصٌ مسبق للمساحة + تأكيدٌ مزدوج (كتابة كلمة).
class UpgradeEncryptionDialog extends StatefulWidget {
  const UpgradeEncryptionDialog({super.key, required this.actions});

  final DbEncryptionActions actions;

  @override
  State<UpgradeEncryptionDialog> createState() =>
      _UpgradeEncryptionDialogState();
}

class _UpgradeEncryptionDialogState extends State<UpgradeEncryptionDialog> {
  final _controller = TextEditingController();
  late final String _word = tr('ترقية');
  MigrationSpaceCheck? _space;
  bool _failed = false;
  bool _spaceConfirmed = false;

  @override
  void initState() {
    super.initState();
    widget.actions.preflight().then((s) {
      if (mounted) setState(() => _space = s);
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _spaceOk {
    final s = _space;
    if (s == null) return false;
    return s.known ? s.ok : _spaceConfirmed;
  }

  bool get _ready => _spaceOk && _controller.text.trim() == _word;

  Widget _spaceBlock() {
    final s = _space;
    if (_failed) {
      return Text(tr('تعذّر فحص المساحة الحرة.'),
          style: const TextStyle(color: AppColors.error));
    }
    if (s == null) {
      return Text(tr('جارٍ الفحص المسبق…'), key: const Key('dbenc_preflight_wait'));
    }
    if (!s.known) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('تعذّر قياس المساحة الحرة. المطلوب {need} على الأقل.',
                {'need': formatBytes(s.requiredBytes)}),
            key: const Key('dbenc_space_unknown'),
          ),
          CheckboxListTile(
            key: const Key('dbenc_space_confirm'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _spaceConfirmed,
            onChanged: (v) => setState(() => _spaceConfirmed = v == true),
            title: Text(tr('أؤكد أن المساحة الحرة تكفي (3 أضعاف حجم القاعدة)')),
          ),
        ],
      );
    }
    return Text(
      s.ok
          ? tr('المساحة الحرة كافية: {free} (المطلوب {need}).', {
              'free': formatBytes(s.freeBytes!),
              'need': formatBytes(s.requiredBytes),
            })
          : tr('المساحة الحرة غير كافية: {free} والمطلوب {need}. حرّر مساحة ثم أعد المحاولة.', {
              'free': formatBytes(s.freeBytes!),
              'need': formatBytes(s.requiredBytes),
            }),
      key: const Key('dbenc_space_result'),
      style: TextStyle(
          color: s.ok ? AppColors.success : AppColors.error,
          fontWeight: FontWeight.w700),
    );
  }

  @override
  Widget build(BuildContext context) => PicPosDialog(
        icon: PhosphorIconsBold.lockKey,
        accent: AppColors.primary,
        title: tr('ترقية تشفير قاعدة البيانات'),
        width: 560,
        onCancel: () => Navigator.pop(context),
        primaryAction: PicPosDialogAction(
          label: tr('سجّل الطلب'),
          color: AppColors.primary,
          onPressed: _ready
              ? () => Navigator.pop(
                  context, UpgradeDecision(spaceConfirmed: _spaceConfirmed))
              : null,
        ),
        body: [
          Text(
            tr('ينقل هذا الإجراء القاعدة من مفتاح مشتق من معرّف الجهاز إلى مفتاح عشوائي قوي محفوظ في حساب ويندوز، مع رمز استرداد. لا يبدأ فورًا: يُسجَّل طلب ويُنفَّذ عند التشغيل التالي قبل فتح القاعدة، وتُؤخذ نسخة احتياطية قبل أي تغيير؛ وإن فشلت أي خطوة بقيت القاعدة كما هي.'),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, height: 1.6),
          ),
          _spaceBlock(),
          TextField(
            key: const Key('dbenc_upgrade_confirm_field'),
            controller: _controller,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr('اكتب «{word}» للتأكيد', {'word': _word}),
            ),
          ),
        ],
      );
}

/// كلمة مرور التصدير المحمول (12 حرفًا على الأقل + تأكيد).
class PortableExportDialog extends StatefulWidget {
  const PortableExportDialog({super.key});

  @override
  State<PortableExportDialog> createState() => _PortableExportDialogState();
}

class _PortableExportDialogState extends State<PortableExportDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  bool get _tooShort => _a.text.length < PortableExport.minPasswordLength;
  bool get _mismatch => _a.text != _b.text;

  @override
  Widget build(BuildContext context) => PicPosDialog(
        icon: PhosphorIconsBold.export,
        accent: AppColors.primary,
        title: tr('تصدير نسخة محمولة بكلمة مرور'),
        width: 520,
        onCancel: () => Navigator.pop(context),
        primaryAction: PicPosDialogAction(
          label: tr('اختيار المجلد وتصدير'),
          color: AppColors.primary,
          onPressed: (_tooShort || _mismatch)
              ? null
              : () => Navigator.pop(context, _a.text),
        ),
        body: [
          Text(
            tr('ينتج ملف قاعدة مشفّر بكلمة المرور وحدها، يُفتح على أي جهاز. احفظ الكلمة؛ لا يمكن استرجاعها.'),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, height: 1.6),
          ),
          TextField(
            key: const Key('dbenc_export_pw'),
            controller: _a,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr('كلمة المرور (12 حرفًا على الأقل)'),
              errorText: _a.text.isNotEmpty && _tooShort
                  ? tr('أقل من {n} حرفًا', {'n': '${PortableExport.minPasswordLength}'})
                  : null,
            ),
          ),
          TextField(
            key: const Key('dbenc_export_pw2'),
            controller: _b,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr('أعد كتابة كلمة المرور'),
              errorText:
                  _b.text.isNotEmpty && _mismatch ? tr('غير متطابقتين') : null,
            ),
          ),
        ],
      );
}

/// نصُّ آخر نتيجةٍ لطلبٍ مؤجَّل.
String outcomeText(DbKeyBootOutcome o) => switch (o.kind) {
      DbKeyBootOutcomeKind.migrated => tr('اكتمل الترحيل.'),
      DbKeyBootOutcomeKind.skipped =>
        tr('لم يبدأ الترحيل ولم تتغير القاعدة: {why}', {'why': o.detail ?? '-'}),
      DbKeyBootOutcomeKind.failed =>
        tr('فشل الترحيل وبقيت القاعدة كما كانت: {why}', {'why': o.detail ?? '-'}),
    };

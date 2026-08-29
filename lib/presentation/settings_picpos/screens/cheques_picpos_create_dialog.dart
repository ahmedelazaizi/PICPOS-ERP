// حوارُ «ورقة تجارية جديدة» بهويّة PicPos — فورك `DLGS.paper` في
// `PicPos Cheques.dc.html`.
//
// ═══ لماذا فورك ═══
//
// `CreatePaperDialog` القديمُ `AlertDialog` خامّ: رأسٌ بلا أيقونةٍ ملوّنة
// وتذييلٌ بأزرارٍ نصّيّة. وشاشةُ الشيكات منقولةٌ إلى الهويّة، فحوارٌ عارٍ
// فوقها يكسرها أظهرَ ما يكون.
//
// ⚠️ **والمُفرَك الواجهةُ وحدَها.** مسارُ الحفظ — سَكُّ `globalId` مرّةً ثمّ
// كتابتان به على الخادم والقاعدة — يبقى في `createCommercialPaper`
// المشتركة. ونسختان منه تنحرفان بأوّل تعديل، وعطبُ Cluster 030 / Bug D
// كان بالضبط هويّتَين لورقةٍ واحدة.
//
// ⚠️ **وعقدُ الخَرج نفسُه**: يُرجع خريطةَ الحوار القديم حرفاً (`confirmed`
// · `type` · `number` · …) فتقبلها الدالّةُ المشتركةُ بلا تبديل.
//
// ═══ وعيبٌ في القديم لا يُنقَل ═══
//
// زرُّ الحفظ هناك يرتدّ **صامتاً** حين ينقص حقلٌ إلزاميّ (‏تعليقٌ صريح:
// «Should show validation but handled in caller for now»). فالمستخدمُ يضغط
// ولا يحدث شيءٌ ولا يعرف السبب. وهنا يُعطَّل الزرُّ ويُقال النقصُ في
// التذييل.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
// ⚠️ **لا `data/database` مباشرةً.** حارسُ `presentation_db_import_guard`
//    يمنع كلَّ ملفِّ عرضٍ **جديد** من ذلك (‏D4-001 / Constitution §IV)،
//    والقائمةُ البيضاءُ مقفولة.
//
//    و`providers.dart` فيه `export '../database/database_barrel.dart'` —
//    فهو المسارُ الشرعيُّ الذي تصل به أنواعُ القاعدة إلى طبقة العرض، وهو ما
//    تستعمله الشاشةُ نفسُها وكلُّ الفوركات الأخرى. والنوعُ المطلوبُ هنا
//    `Party` وحدَه.
//    ويحمل `SafeData` أيضاً، فلا حاجةَ لاستيراد `treasury_repository`.
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_dialog.dart';

/// نوعُ الورقة كما يكتبه العمودُ `type`.
const _types = <(String, String, IconData, String)>[
  ('cheque', 'شيك', PhosphorIconsBold.note, 'له بنك وحساب وتاريخ استحقاق'),
  (
    'promissory_note',
    'كمبيالة',
    PhosphorIconsBold.scroll,
    'بلا بنك — التزام موثّق'
  ),
  (
    'bill_of_exchange',
    'سند لأمر',
    PhosphorIconsBold.receipt,
    'تعهّدٌ بالدفع لأمر المستفيد'
  ),
];

/// يفتح الحوارَ ويُرجع خريطةَ النموذج، أو `null` عند الإلغاء.
Future<Map<String, dynamic>?> showChequePicposCreateDialog(
  BuildContext context, {
  required String direction,
  required List<Party> parties,
  required List<SafeData> bankSafes,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CreatePaperPicposDialog(
      direction: direction,
      parties: parties,
      bankSafes: bankSafes,
    ),
  );
}

class _CreatePaperPicposDialog extends StatefulWidget {
  const _CreatePaperPicposDialog({
    required this.direction,
    required this.parties,
    required this.bankSafes,
  });

  /// `received` · `issued` — و`portfolio` تبويبةُ عرضٍ تُقرأ واردة.
  final String direction;
  final List<Party> parties;
  final List<SafeData> bankSafes;

  @override
  State<_CreatePaperPicposDialog> createState() =>
      _CreatePaperPicposDialogState();
}

class _CreatePaperPicposDialogState extends State<_CreatePaperPicposDialog> {
  final _numberCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _fmt = DateFormat('yyyy/MM/dd');

  late String _direction =
      widget.direction == 'portfolio' ? 'received' : widget.direction;
  String _type = 'cheque';
  int? _partyId;
  int? _bankSafeId;
  DateTime _issue = DateTime.now();
  DateTime _due = DateTime.now().add(const Duration(days: 30));

  @override
  void dispose() {
    _numberCtrl.dispose();
    _amountCtrl.dispose();
    _accountCtrl.dispose();
    _bankCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_amountCtrl.text.trim());

  /// ما ينقص الحفظَ — يُعرَض في التذييل بدل ارتدادٍ صامت.
  String? get _blocker {
    if (_numberCtrl.text.trim().isEmpty) return 'رقمُ الورقة مطلوب';
    final a = _amount;
    if (a == null || a <= 0) return 'المبلغُ مطلوبٌ وأكبرُ من صفر';
    if (_partyId == null) return 'اختر الطرف';
    // ⚠️ الكمبيالةُ بلا بنكٍ عمداً (‏نصُّ التصميم: «بلا بنك — التزام
    //    موثّق»)، فلا يُطلَب لها ما لا تحمله.
    if (_type == 'cheque' && _direction == 'issued' && _bankSafeId == null) {
      return 'اختر البنكَ المسحوبَ منه';
    }
    // ⚠️ استحقاقٌ قبل الإصدار يجعل الورقةَ مستحقّةً قبل وجودها، ويقلب
    //    ترتيبَ «جدول الاستحقاق» بلا أن يظهر خطأ.
    if (_due.isBefore(DateTime(_issue.year, _issue.month, _issue.day))) {
      return 'تاريخُ الاستحقاق قبل الإصدار';
    }
    return null;
  }

  Future<void> _pickDate({required bool issue}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: issue ? _issue : _due,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (d == null) return;
    setState(() => issue ? _issue = d : _due = d);
  }

  Widget _dateField(String label, DateTime value, {required bool issue}) {
    return InkWell(
      onTap: () => _pickDate(issue: issue),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          prefixIcon: Icon(
            issue
                ? PhosphorIconsBold.calendarBlank
                : PhosphorIconsBold.calendarCheck,
            size: 16,
          ),
        ),
        child: Text(_fmt.format(value), style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocker = _blocker;
    final isCheque = _type == 'cheque';
    final partyLabel =
        _direction == 'received' ? 'المسحوب عليه (العميل)' : 'المستفيد (المورد)';

    return PicPosDialog(
      icon: PhosphorIconsBold.note,
      title: 'ورقة تجارية جديدة',
      subtitle: 'شيك أو كمبيالة — وارد من عميل أو صادر لمورد',
      width: 880,
      onCancel: () => Navigator.pop(context),
      footerHint: blocker,
      primaryAction: PicPosDialogAction(
        label: 'حفظ الورقة',
        icon: PhosphorIconsBold.check,
        onPressed: blocker != null
            ? null
            : () => Navigator.pop(context, <String, dynamic>{
                  'confirmed': true,
                  // الاتّجاهُ يخرج مع النموذج: الحوارُ يسمح بتبديله،
                  // فقراءتُه من التبويبة تكتب غيرَ ما اختار المستخدم.
                  'direction': _direction,
                  'type': _type,
                  'number': _numberCtrl.text.trim(),
                  'amount': _amount,
                  'partyId': _partyId,
                  'bankName': _bankName(),
                  'bankSafeId': _bankSafeId,
                  'accountNumber': _accountCtrl.text.trim(),
                  'issueDate': _issue,
                  'dueDate': _due,
                  'notes': _notesCtrl.text.trim(),
                }),
      ),
      body: [
        _sectionLabel('النوع والاتجاه'),
        PicPosDialogRow(
          children: [
            PicPosDialogChoice(
              icon: PhosphorIconsBold.arrowCircleDown,
              label: 'وارد من عميل',
              selected: _direction == 'received',
              onTap: () => setState(() => _direction = 'received'),
            ),
            PicPosDialogChoice(
              icon: PhosphorIconsBold.arrowCircleUp,
              label: 'صادر لمورد',
              selected: _direction == 'issued',
              onTap: () => setState(() => _direction = 'issued'),
            ),
          ],
        ),
        PicPosDialogRow(
          children: [
            for (final (id, label, icon, _) in _types)
              PicPosDialogChoice(
                icon: icon,
                label: label,
                selected: _type == id,
                onTap: () => setState(() => _type = id),
              ),
          ],
        ),
        _sectionLabel('بيانات الورقة'),
        PicPosDialogRow(
          children: [
            TextField(
              controller: _numberCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'رقم الورقة *',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(PhosphorIconsBold.hash, size: 16),
              ),
            ),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'المبلغ *',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon:
                    Icon(PhosphorIconsBold.currencyCircleDollar, size: 16),
              ),
            ),
          ],
        ),
        DropdownButtonFormField<int>(
          initialValue: _partyId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: '$partyLabel *',
            border: const OutlineInputBorder(),
            isDense: true,
            prefixIcon: const Icon(PhosphorIconsBold.user, size: 16),
          ),
          items: [
            for (final p in widget.parties)
              DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: (v) => setState(() => _partyId = v),
        ),
        PicPosDialogRow(
          children: [
            _dateField('تاريخ الإصدار', _issue, issue: true),
            _dateField('تاريخ الاستحقاق', _due, issue: false),
          ],
        ),
        if (isCheque) ...[
          _sectionLabel('بيانات البنك'),
          PicPosDialogRow(
            children: [
              // ⚠️ الوارد: اسمُ البنك نصٌّ حرّ — بنكُ العميل ليس خزنةً
              //    عندنا. والصادر: خزنةٌ بنكيّةٌ **لنا** يُخصَم منها،
              //    فتُختار من القائمة لا تُكتَب.
              if (_direction == 'received')
                TextField(
                  controller: _bankCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'البنك المسحوب عليه',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(PhosphorIconsBold.bank, size: 16),
                  ),
                )
              else
                DropdownButtonFormField<int>(
                  initialValue: _bankSafeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'البنك المسحوب منه *',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(PhosphorIconsBold.bank, size: 16),
                  ),
                  items: [
                    for (final s in widget.bankSafes)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) => setState(() => _bankSafeId = v),
                ),
              TextField(
                controller: _accountCtrl,
                decoration: const InputDecoration(
                  labelText: 'رقم الحساب',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(PhosphorIconsBold.creditCard, size: 16),
                ),
              ),
            ],
          ),
        ],
        TextField(
          controller: _notesCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'ملاحظات',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        // نصُّ التنبيه من التصميم حرفاً — وهو قاعدةُ محاسبةٍ تشرح سلوكاً
        // يبدو خطأً للمشغّل: الرصيدُ لم ينقص بعد استلام الشيك.
        if (_direction == 'received')
          const PicPosDialogBanner(
            icon: PhosphorIconsBold.warning,
            color: AppColors.warning,
            text: 'استلام الشيك لا يُنقص ذمة العميل — الذمة تُنقص عند التحصيل '
                'الفعلي. حتى ذلك الحين تظهر الورقة في «شيكات تحت التحصيل».',
          )
        else
          const PicPosDialogBanner(
            icon: PhosphorIconsBold.warning,
            color: AppColors.warning,
            text: 'الشيك الصادر يُقيَّد كالتزام قائم حتى يُخصم من البنك فعلاً '
                '— لا عند تحريره.',
          ),
      ],
    );
  }

  String? _bankName() {
    if (_type != 'cheque') return null;
    if (_direction == 'received') return _bankCtrl.text.trim();
    final id = _bankSafeId;
    if (id == null) return null;
    final match = widget.bankSafes.where((s) => s.id == id).toList();
    return match.isEmpty ? null : match.first.name;
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
      );
}

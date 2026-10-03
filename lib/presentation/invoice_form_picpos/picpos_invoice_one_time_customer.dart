// J3 — «عميل نقدي»: اسمُ العميل لمرّةٍ واحدة (+ الهاتف) و«حفظ كعميل دائم».
//
// قرارُ المالك: حين يكون طرفُ الفاتورة هو العميلَ النقديَّ النظاميّ، تحمل
// الفاتورةُ اسماً حرّاً اختياريّاً (وهاتفاً) يُخزَّن عليها
// (`sales_invoices.adhoc_customer_name/phone`) ويُطبَع **بدل** «عميل نقدي».
// و«حفظ كعميل دائم» ينشئ عميلاً حقيقيّاً بهذه البيانات (على نهاية مسارٍ،
// حدُّ ائتمانه صفر) وينقل الفاتورةَ إليه **قبل** الحفظ.
//
// ⚠️ عرضٌ خالص: الإنشاءُ عند المنادي ([PicPosSavePermanentCustomer])، والاسمُ
// يُسلَّم بردّ نداءٍ منفصلٍ قبل `onSave` — نفسُ نمط «حساب المبيعات» — فلا
// يتغيّر عقدُ الحفظ المشترك بين المنادين.
part of 'picpos_invoice_form.dart';

/// يُنادى قبل الحفظ مباشرةً — `name`/`phone` فارغان ⇒ `null`.
typedef PicPosOneTimeCustomerCallback = void Function(
    ({String? name, String? phone}) customer);

/// ينشئ العميلَ الدائمَ (حواره وبياناته عند المنادي) ويُرجعه، أو `null`
/// حين يُلغى.
typedef PicPosSavePermanentCustomer = Future<PicPosPartyOption?> Function(
  BuildContext context, {
  required String name,
  String? phone,
});

extension _OneTimeCustomerState on _PicPosInvoiceFormState {
  bool get _showOneTimeCustomer =>
      widget.kind.isSales &&
      widget.onOneTimeCustomerChanged != null &&
      (_party?.isCashParty ?? false);

  void _publishOneTimeCustomer() {
    final cb = widget.onOneTimeCustomerChanged;
    if (cb == null) return;
    String? clean(String v) => v.trim().isEmpty ? null : v.trim();
    cb(_showOneTimeCustomer
        ? (name: clean(_oneTimeName), phone: clean(_oneTimePhone))
        : (name: null, phone: null));
  }

  Future<void> _saveAsPermanentCustomer(BuildContext context) async {
    final create = widget.onSaveAsPermanentCustomer;
    final name = _oneTimeName.trim();
    if (create == null || name.isEmpty) return;
    final phone = _oneTimePhone.trim();
    final created =
        await create(context, name: name, phone: phone.isEmpty ? null : phone);
    if (created == null || !mounted) return;
    setState(() {
      _createdParties.add(created);
      _partyId = created.id;
      _oneTimeName = '';
      _oneTimePhone = '';
    });
  }
}

/// صفُّ الحقلين وزرُّ «حفظ كعميل دائم» تحت شريط المستند.
class _PicPosOneTimeCustomerBar extends StatefulWidget {
  const _PicPosOneTimeCustomerBar({required this.state});
  final _PicPosInvoiceFormState state;

  @override
  State<_PicPosOneTimeCustomerBar> createState() =>
      _PicPosOneTimeCustomerBarState();
}

class _PicPosOneTimeCustomerBarState extends State<_PicPosOneTimeCustomerBar> {
  late final _name = TextEditingController(text: widget.state._oneTimeName);
  late final _phone = TextEditingController(text: widget.state._oneTimePhone);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.state;
    final canSave =
        s.widget.onSaveAsPermanentCustomer != null && _name.text.trim().isNotEmpty;
    InputDecoration deco(String label, IconData icon) => InputDecoration(
          isDense: true,
          labelText: label,
          prefixIcon: Icon(icon, size: 16),
          border: const OutlineInputBorder(),
        );
    return Container(
      key: const Key('picpos_one_time_customer'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: AppColors.info.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              key: const Key('picpos_one_time_name'),
              controller: _name,
              decoration: deco(
                  tr('اسم العميل (اختياري)'), PhosphorIconsBold.user),
              onChanged: (v) => setState(() => s._oneTimeName = v),
            ),
          ),
          SizedBox(
            width: 200,
            child: TextField(
              key: const Key('picpos_one_time_phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration:
                  deco(tr('الهاتف (اختياري)'), PhosphorIconsBold.phone),
              onChanged: (v) => setState(() => s._oneTimePhone = v),
            ),
          ),
          if (s.widget.onSaveAsPermanentCustomer != null)
            OutlinedButton.icon(
              key: const Key('picpos_save_permanent_customer'),
              onPressed:
                  canSave ? () => s._saveAsPermanentCustomer(context) : null,
              icon: const Icon(PhosphorIconsBold.userPlus, size: 16),
              label: Text(tr('حفظ كعميل دائم')),
            ),
          Text(
            tr('يُطبع الاسم على الفاتورة بدل «عميل نقدي»'),
            style: TextStyle(fontSize: 10.5, color: _fMuted(context)),
          ),
        ],
      ),
    );
  }
}

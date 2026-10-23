import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/i18n/tr.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/utils/phone_normalizer.dart';
import '../../../data/providers/customer_picker_providers.dart';
import '../../../data/providers/providers.dart' show Party;
import '../../parties_picpos/dialogs/add_party_dialog_picpos.dart';
import '../../widgets/permission_guard.dart';
import 'customer_picker_card.dart';
import 'customer_picker_results.dart';
import 'customer_picker_value.dart';

/// دالةُ الإضافة السريعة: تفتح حوارَ الإضافة وتُعيد معرّفَ الطرف (أو `null`).
typedef CustomerQuickAdd = Future<int?> Function(
  BuildContext context,
  WidgetRef ref, {
  String? initialName,
  String? initialPhone,
});

Future<int?> _defaultQuickAdd(
  BuildContext context,
  WidgetRef ref, {
  String? initialName,
  String? initialPhone,
}) =>
    showAddPartyDialogPicpos(context, ref,
        initialName: initialName, initialPhone: initialPhone);

/// منتقي العميل الموحَّد لكلّ واجهات الحجز (خدماتٌ وطاولات).
///
/// * بحثٌ واحدٌ بالاسم/الهاتف/الكود (debounce 250ms، أسهمٌ/Enter)، داخل نطاق
///   فرع المستخدم فقط.
/// * بعد الاختيار: بطاقةُ العميل ([CustomerPickerCard]).
/// * «+ عميل جديد» يعيد استعمال حوار الإضافة ويختار الطرفَ المُنشأ، ومنعُ
///   تكرار الهاتف داخل الحوار نفسه.
/// * «ضيف بلا تسجيل»: اسمٌ وهاتفٌ نصّاً (`partyId = null`) مع «ترقية إلى عميل».
class CustomerPickerField extends ConsumerStatefulWidget {
  const CustomerPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.debounce = const Duration(milliseconds: 250),
    this.quickAdd = _defaultQuickAdd,
    this.onOpenProfile,
  });

  final CustomerPickerValue value;
  final ValueChanged<CustomerPickerValue> onChanged;
  final String? label;
  final Duration debounce;
  final CustomerQuickAdd quickAdd;
  final ValueChanged<int>? onOpenProfile;

  @override
  ConsumerState<CustomerPickerField> createState() =>
      _CustomerPickerFieldState();
}

class _CustomerPickerFieldState extends ConsumerState<CustomerPickerField> {
  final _query = TextEditingController();
  late final _guestName = TextEditingController(text: widget.value.name);
  late final _guestPhone = TextEditingController(text: widget.value.phone);
  Timer? _timer;
  String _debounced = '';
  int _highlight = 0;
  late bool _guestMode = widget.value.isGuest && !widget.value.isEmpty;

  @override
  void didUpdateWidget(covariant CustomerPickerField old) {
    super.didUpdateWidget(old);
    final v = widget.value;
    if (v.isGuest) {
      if (_guestName.text != v.name) _guestName.text = v.name;
      if (_guestPhone.text != v.phone) _guestPhone.text = v.phone;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _query.dispose();
    _guestName.dispose();
    _guestPhone.dispose();
    super.dispose();
  }

  void _onQuery(String text) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () {
      if (mounted) {
        setState(() {
          _debounced = text.trim();
          _highlight = 0;
        });
      }
    });
    setState(() {});
  }

  void _pick(Party p) {
    _query.clear();
    _debounced = '';
    setState(() => _guestMode = false);
    widget.onChanged(
        CustomerPickerValue(partyId: p.id, name: p.name, phone: p.phone ?? ''));
  }

  void _enterGuest() {
    final q = _query.text.trim();
    final phoneLike = RegExp(r'^[\d\s+\-()]+$').hasMatch(q);
    _guestName.text = phoneLike ? '' : q;
    _guestPhone.text = phoneLike ? q : '';
    _query.clear();
    _debounced = '';
    setState(() => _guestMode = true);
    _emitGuest();
  }

  void _emitGuest() => widget.onChanged(CustomerPickerValue(
      name: _guestName.text.trim(), phone: _guestPhone.text.trim()));

  Future<void> _quickAdd({String? name, String? phone}) async {
    final id = await widget.quickAdd(context, ref,
        initialName: name, initialPhone: phone);
    if (id == null || !mounted) return;
    final p = await ref.read(customerPickerPartyProvider(id).future);
    if (p != null && mounted) _pick(p);
  }

  void _addFromQuery() {
    final q = _query.text.trim();
    final digits = normalizePhone(q);
    final phoneLike = digits.isNotEmpty && RegExp(r'^[\d\s+\-()]+$').hasMatch(q);
    _quickAdd(name: phoneLike ? null : q, phone: phoneLike ? q : null);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final scheme = Theme.of(context).colorScheme;
    Widget body;
    if (v.partyId != null) {
      body = CustomerPickerCard(
        partyId: v.partyId!,
        snapshotName: v.name,
        onOpenProfile: widget.onOpenProfile,
        onClear: () {
          setState(() => _guestMode = false);
          widget.onChanged(CustomerPickerValue.empty);
        },
      );
    } else if (_guestMode) {
      body = _guestForm(context);
    } else {
      // بلا customers_view: لا بحثَ في العملاء — ضيفٌ فقط.
      body = PermissionGuard(
        permission: PermissionCodes.customersView,
        fallback: _guestForm(context, searchEnabled: false),
        child: _searchForm(context),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
        ],
        body,
      ],
    );
  }

  // ───────────────────────── البحث ─────────────────────────

  Widget _searchForm(BuildContext context) {
    final results = _debounced.isEmpty
        ? null
        : ref.watch(customerPickerSearchProvider(_debounced));
    final list = results?.value ?? const <Party>[];
    final total = CustomerPickerResults.itemCount(list.length);

    void move(int delta) =>
        setState(() => _highlight = (_highlight + delta).clamp(0, total - 1));

    void activate() {
      if (_debounced.isEmpty) return;
      if (_highlight < list.length) {
        _pick(list[_highlight]);
      } else if (_highlight == list.length) {
        _addFromQuery();
      } else {
        _enterGuest();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => move(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => move(-1),
          },
          child: TextField(
            key: const ValueKey('customer_picker_query'),
            controller: _query,
            onChanged: _onQuery,
            onSubmitted: (_) => activate(),
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: tr('ابحث بالاسم أو الهاتف'),
              prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
            ),
          ),
        ),
        if (_debounced.isNotEmpty) ...[
          const SizedBox(height: 4),
          CustomerPickerResults(
            parties: list,
            query: _query.text,
            highlight: _highlight,
            loading: results?.isLoading ?? false,
            onPick: _pick,
            onAddNew: _addFromQuery,
            onGuest: _enterGuest,
          ),
        ],
      ],
    );
  }

  // ───────────────────────── الضيف ─────────────────────────

  Widget _guestForm(BuildContext context, {bool searchEnabled = true}) {
    final canUpgrade =
        _guestName.text.trim().isNotEmpty || _guestPhone.text.trim().isNotEmpty;
    InputDecoration deco(String label) => InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          labelText: label,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('customer_guest_name'),
                controller: _guestName,
                onChanged: (_) {
                  setState(() {});
                  _emitGuest();
                },
                decoration: deco(tr('اسم العميل')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const ValueKey('customer_guest_phone'),
                controller: _guestPhone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                onChanged: (_) {
                  setState(() {});
                  _emitGuest();
                },
                decoration: deco(tr('رقم الهاتف')),
              ),
            ),
          ],
        ),
        // Wrap لا Row: الشريط يضيق على اللوحات الضيّقة فتنزل الأزرار لسطرٍ ثانٍ.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(tr('ضيف بلا تسجيل'),
                style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            PermissionGuard(
              permission: PermissionCodes.customersAdd,
              showDisabled: true,
              child: TextButton.icon(
                key: const ValueKey('customer_guest_upgrade'),
                onPressed: canUpgrade
                    ? () => _quickAdd(
                          name: _guestName.text.trim(),
                          phone: _guestPhone.text.trim(),
                        )
                    : null,
                icon: const Icon(PhosphorIconsBold.userPlus, size: 15),
                label: Text(tr('ترقية إلى عميل')),
              ),
            ),
            if (searchEnabled)
              TextButton(
                key: const ValueKey('customer_guest_back'),
                onPressed: () {
                  setState(() => _guestMode = false);
                  widget.onChanged(CustomerPickerValue.empty);
                },
                child: Text(tr('بحث عن عميل')),
              ),
          ],
        ),
      ],
    );
  }
}

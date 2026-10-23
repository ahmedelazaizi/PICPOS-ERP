import 'package:picpos_erp/core/i18n/tr.dart';

import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_dialog.dart';

/// K-1 — the rep expense categories the van app offers (each mapped to an
/// expense account the desktop debits when it posts the field expense) and
/// what the cloud does with an expense beyond the rep's custody balance.
class FieldExpenseCategoriesScreen extends ConsumerStatefulWidget {
  const FieldExpenseCategoriesScreen({super.key});

  @override
  ConsumerState<FieldExpenseCategoriesScreen> createState() =>
      _FieldExpenseCategoriesScreenState();
}

class _FieldExpenseCategoriesScreenState
    extends ConsumerState<FieldExpenseCategoriesScreen> {
  List<FieldExpenseCategory> _items = const [];
  List<Account> _accounts = const [];
  String _policy = 'flag';

  AppDatabase get _db => ref.read(databaseProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _db.listFieldExpenseCategories();
    final accounts = await (_db.select(_db.accounts)
          ..where((a) =>
              a.accountType.equals('expense') &
              a.accountNature.equals('detail') &
              a.isActive.equals(true))
          ..orderBy([(a) => OrderingTerm(expression: a.code)]))
        .get();
    final policy = await _db.getSettingValue(kCloudExpenseOverCustodySetting);
    if (!mounted) return;
    setState(() {
      _items = items;
      _accounts = accounts;
      _policy = policy == 'reject' ? 'reject' : 'flag';
    });
  }

  String _accountLabel(String code) {
    final a = _accounts.where((a) => a.code == code).firstOrNull;
    return a == null ? code : '${a.code} — ${a.name}';
  }

  Future<void> _setPolicy(String? v) async {
    if (v == null) return;
    await _db.setSetting(kCloudExpenseOverCustodySetting, v);
    setState(() => _policy = v);
    if (mounted) AppToast.show(context, tr('تم الحفظ'));
  }

  Future<void> _edit([FieldExpenseCategory? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    final nameEn = TextEditingController(text: c?.nameEn ?? '');
    var code = c?.accountCode ?? _accounts.firstOrNull?.code;
    var active = c?.isActive ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => PicPosDialog(
          icon: Icons.receipt_long_outlined,
          title: c == null ? tr('فئة مصروف جديدة') : tr('تعديل فئة المصروف'),
          width: 460,
          cancelLabel: tr('إلغاء'),
          onCancel: () => Navigator.pop(ctx, false),
          primaryAction: PicPosDialogAction(
              label: tr('حفظ'), onPressed: () => Navigator.pop(ctx, true)),
          body: [
              TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: tr('الاسم'))),
              TextField(
                  controller: nameEn,
                  decoration:
                      InputDecoration(labelText: tr('الاسم بالإنجليزية'))),
              DropdownButtonFormField<String>(
                initialValue: _accounts.any((a) => a.code == code) ? code : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('حساب المصروف')),
                items: [
                  for (final a in _accounts)
                    DropdownMenuItem(
                        value: a.code, child: Text('${a.code} — ${a.name}')),
                ],
                onChanged: (v) => setLocal(() => code = v),
              ),
              SwitchListTile(
                value: active,
                onChanged: (v) => setLocal(() => active = v),
                title: Text(tr('نشطة')),
              ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty || code == null) {
      if (mounted) {
        AppToast.show(context, tr('الاسم والحساب مطلوبان'),
            type: ToastType.warning);
      }
      return;
    }
    await _db.saveFieldExpenseCategory(
      id: c?.id,
      name: name.text,
      nameEn: nameEn.text,
      accountCode: code!,
      sortOrder: c?.sortOrder ?? _items.length,
      isActive: active,
    );
    await _load();
  }

  Future<void> _delete(FieldExpenseCategory c) async {
    await _db.deleteFieldExpenseCategory(c.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('فئات مصروفات المندوب'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(tr('فئة مصروف جديدة')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
              tr('تظهر هذه الفئات في تطبيق المندوب، ويُرحَّل سند الصرف من عهدته على حساب الفئة')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _policy,
            decoration:
                InputDecoration(labelText: tr('مصروف يتجاوز رصيد العهدة')),
            items: [
              DropdownMenuItem(
                  value: 'flag', child: Text(tr('يُقبل ويُعلَّم «تجاوز العهدة»'))),
              DropdownMenuItem(value: 'reject', child: Text(tr('يُرفض'))),
            ],
            onChanged: _setPolicy,
          ),
          const Divider(height: 32),
          if (_items.isEmpty)
            ListTile(title: Text(tr('لا فئات بعد')))
          else
            for (final c in _items)
              ListTile(
                title: Text(c.nameEn == null ? c.name : '${c.name} · ${c.nameEn}'),
                subtitle: Text([
                  _accountLabel(c.accountCode),
                  if (!c.isActive) tr('غير نشطة'),
                ].join(' · ')),
                onTap: () => _edit(c),
                trailing: IconButton(
                  tooltip: tr('حذف'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(c),
                ),
              ),
        ],
      ),
    );
  }
}

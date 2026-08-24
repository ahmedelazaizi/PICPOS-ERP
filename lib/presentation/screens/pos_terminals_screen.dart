import 'dart:convert';
import 'package:drift/drift.dart' show Value, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../services/stock_shortage_policy_service.dart';

/// Feature 009 / T028b — POS terminals management screen.
///
/// Admin-only. Lists every registered terminal (one row per
/// `pos_terminals` entry), lets the admin rename / activate / deactivate
/// each one, and per-terminal override the stock-shortage policy
/// (FR-017 — wins over per-branch + global).
class PosTerminalsScreen extends StatelessWidget {
  const PosTerminalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.cashRegister),
            SizedBox(width: 8),
            Text('نقاط البيع'),
          ],
        ),
      ),
      body: const PosTerminalsBody(),
    );
  }
}

/// جسمُ الشاشة بلا قشرة (‏بلا `Scaffold` ولا `AppBar`) — كلُّ منطقِ نقاط
/// البيع يعيش هنا، والقشرةُ تُركَّب فوقه.
///
/// استُخرج ليركب عليه إطارُ العلامتَين معاً بلا نسخِ منطق: `PosTerminalsScreen`
/// أعلاه (‏قشرةُ UralCash: `Scaffold` + `AppBar`، وهي حرفاً بحرفٍ ما كانت
/// عليه قبل الاستخراج) و`PosTerminalsPicposScreen` في
/// `settings_picpos/screens/` (‏قشرةُ PicPos: `PicPosScreenScaffold`).
///
/// ولهذا لا تنطبق «مصيدةُ النسخ §٥.٨» هنا: لا نسخةَ ثانيةً من المنطق تُصان،
/// وشاشةُ UralCash لم يتبدّل فيها بايت — نفسُ الجسمِ ونفسُ الـ`AppBar`.
///
/// [searchQuery] ترشيحٌ اختياريٌّ بالاسم/الفرع/`device_id`. فارغاً (‏وهو
/// الافتراضيُّ الذي تمرّره قشرةُ UralCash) لا يُرشِّح شيئاً.
class PosTerminalsBody extends ConsumerStatefulWidget {
  final String searchQuery;

  const PosTerminalsBody({super.key, this.searchQuery = ''});

  @override
  ConsumerState<PosTerminalsBody> createState() => _PosTerminalsBodyState();
}

class _PosTerminalsBodyState extends ConsumerState<PosTerminalsBody> {
  late Future<_TerminalsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_TerminalsData> _load() async {
    final db = ref.read(databaseProvider);
    final terminals =
        await (db.select(db.posTerminals)..orderBy([(t) => OrderingTerm(expression: t.id)])).get();
    final branches = await db.select(db.branches).get();
    final repo = ref.read(settingsRepositoryProvider);
    final raw = await repo.getSetting('stock_shortage_policy_per_terminal');
    final perTerminal = <int, StockShortagePolicy>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            final id = int.tryParse(k.toString());
            final p = StockShortagePolicyService.fromName(v?.toString());
            if (id != null && p != null) perTerminal[id] = p;
          });
        }
      } catch (_) {/* corrupted JSON — start empty */}
    }
    return _TerminalsData(
      terminals: terminals,
      branches: {for (final b in branches) b.id: b.name},
      perTerminalPolicy: perTerminal,
    );
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  /// ترشيحٌ بالاسم أو اسمِ الفرع أو `device_id`. استعلامٌ فارغٌ يُرجع القائمةَ
  /// كما هي بالمرجع نفسِه — فقشرةُ UralCash (‏التي لا تمرّر استعلاماً) تبني
  /// عينَ ما كانت تبنيه.
  List<PosTerminalData> _filter(_TerminalsData data) {
    final q = widget.searchQuery.trim();
    if (q.isEmpty) return data.terminals;
    return data.terminals.where((t) {
      final branch = data.branches[t.branchId] ?? '';
      return t.name.contains(q) ||
          branch.contains(q) ||
          t.deviceId.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_TerminalsData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('خطأ فى التحميل: ${snap.error}'));
        }
        final data = snap.data!;
        if (data.terminals.isEmpty) {
          return _buildEmptyState();
        }
        final shown = _filter(data);
        if (shown.isEmpty) {
          return Center(
            child: Text(
              'لا توجد نقطة بيع تطابق «${widget.searchQuery.trim()}»',
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textMuted),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: shown.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _buildTerminalCard(shown[i], data),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(PhosphorIconsLight.cashRegister, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'لا توجد نقاط بيع مسجَّلة',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'تُسجَّل نقاط البيع تلقائياً أول مرة يفتح فيها كل جهاز جلسة بيع. لو لم تظهر بعد ساعة من التشغيل، تأكد من اتصال العميل بالسيرفر.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalCard(PosTerminalData t, _TerminalsData data) {
    final branchName = data.branches[t.branchId] ?? '#${t.branchId}';
    final policy = data.perTerminalPolicy[t.id];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  t.isActive
                      ? PhosphorIconsBold.cashRegister
                      : PhosphorIconsBold.prohibit,
                  color: t.isActive ? AppColors.primary : AppColors.textMuted,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'الفرع: $branchName',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: t.isActive,
                  onChanged: (v) => _setActive(t, v),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                const Icon(PhosphorIconsBold.fingerprint,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'device_id: ${t.deviceId}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  icon: const Icon(PhosphorIconsBold.copy, size: 16),
                  tooltip: 'نسخ device_id',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: t.deviceId));
                    if (mounted) {
                      AppToast.show(context, 'تم نسخ device_id');
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(PhosphorIconsBold.pencilSimple, size: 16),
                  tooltip: 'تعديل الاسم',
                  onPressed: () => _renameDialog(t),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(PhosphorIconsBold.warning,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'سياسة نقص الخامات لهذه الماكينة:',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                DropdownButton<StockShortagePolicy?>(
                  value: policy,
                  hint: const Text('افتراضى'),
                  isDense: true,
                  items: [
                    const DropdownMenuItem<StockShortagePolicy?>(
                      value: null,
                      child: Text('افتراضى'),
                    ),
                    for (final p in StockShortagePolicy.values)
                      DropdownMenuItem<StockShortagePolicy?>(
                        value: p,
                        child: Text(p.arabicLabel),
                      ),
                  ],
                  onChanged: (v) => _setPerTerminalPolicy(t.id, v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setActive(PosTerminalData t, bool active) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.posTerminals)..where((r) => r.id.equals(t.id)))
        .write(PosTerminalsCompanion(isActive: Value(active)));
    if (mounted) {
      AppToast.show(
        context,
        active ? 'تم تفعيل الماكينة' : 'تم إيقاف الماكينة',
        type: ToastType.info,
      );
    }
    _refresh();
  }

  Future<void> _renameDialog(PosTerminalData t) async {
    final controller = TextEditingController(text: t.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل اسم الماكينة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'الاسم'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == t.name) return;
    final db = ref.read(databaseProvider);
    await (db.update(db.posTerminals)..where((r) => r.id.equals(t.id)))
        .write(PosTerminalsCompanion(name: Value(newName)));
    _refresh();
  }

  Future<void> _setPerTerminalPolicy(
      int terminalId, StockShortagePolicy? policy) async {
    final data = await _future;
    final next = Map<int, StockShortagePolicy>.from(data.perTerminalPolicy);
    if (policy == null) {
      next.remove(terminalId);
    } else {
      next[terminalId] = policy;
    }
    await StockShortagePolicyService.savePerTerminal(
      ref.read(settingsRepositoryProvider),
      next,
    );
    _refresh();
  }
}

class _TerminalsData {
  final List<PosTerminalData> terminals;
  final Map<int, String> branches;
  final Map<int, StockShortagePolicy> perTerminalPolicy;

  _TerminalsData({
    required this.terminals,
    required this.branches,
    required this.perTerminalPolicy,
  });
}

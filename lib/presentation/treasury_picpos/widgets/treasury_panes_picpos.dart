// لوحا الخزينة (الصناديق · آخر الحركات) بهويّة PicPos.
//
// ═══ ودجتٌ واحدةٌ لثلاثة تبويبات — لا ثلاثُ نسخ ═══
//
// الأصلُ يكتب نفسَ التخطيط **ثلاثَ مرّات**: `TreasuryCashTab` و
// `TreasuryBankTab` و`_TreasuryClickTab` (داخل شاشة الخزينة نفسِها) —
// ثلاثُ نسخٍ لا يفرّقها إلّا `safeType` ونصُّ الفراغ. والتصميمُ نفسُه يقول
// ذلك صراحةً: `list = tab==='bank' ? bank : tab==='click' ? click : SAFES`
// — تخطيطٌ واحدٌ وقائمةٌ مرشَّحة.
//
// وقرارُ المالك يمنع مشاركةَ الفورك مع UralCash، **ولا يأمر بالنسخ ثلاثاً
// داخلَ PicPos**.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ural_erp/core/utils/friendly_error.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import 'treasury_movements_list_picpos.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'treasury_picpos_tokens.dart';
import 'treasury_safe_card_picpos.dart';

class TreasuryPanesPicpos extends ConsumerWidget {
  const TreasuryPanesPicpos({
    super.key,
    required this.safes,
    required this.transactions,
    required this.safeType,
    required this.emptyLabel,
    this.searchQuery = '',
  });

  final AsyncValue<List<SafeData>> safes;
  final AsyncValue<List<TransactionData>> transactions;

  /// نوعُ الصناديق التي يعرضها هذا التبويب — `cash` / `bank` / `click`.
  final String safeType;

  /// نصُّ «لا توجد صناديق…» الخاصُّ بالنوع.
  final String emptyLabel;

  /// بحثُ الشاشة الواحد.
  ///
  /// ⚠️ **كان يُكتَب ولا يُقرَأ.** حقلُ البحث في شاشة الخزينة (‏الفورك
  /// **والأصل** معاً) يضبط `_searchQuery` في `setState` ثمّ لا يستعمله أحد —
  /// صندوقُ بحثٍ يُكتب فيه فلا يترشّح شيء. والتصميمُ يضع بحثاً واحداً في
  /// شريط التبويبات يخدم اللوحَين، فوُصِّل هنا فعلاً.
  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // أسماءُ الفروع تُحلُّ **مرّةً واحدةً** هنا لا في كلّ بطاقة، والبطاقةُ
    // تبقى `StatelessWidget` بلا مزوِّد فتُختبَر بلا `ProviderScope`.
    final branches = ref.watch(allBranchesProvider).value;
    final branchNames = <int, String>{
      if (branches != null)
        for (final b in branches) b.id: b.name,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 440,
          child: _SafesPane(
            safes: safes,
            safeType: safeType,
            emptyLabel: emptyLabel,
            searchQuery: searchQuery,
            branchNames: branchNames,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TreasuryMovementsListPicpos(
            transactions: transactions,
            // الحركاتُ تُرشَّح بمعرِّفات صناديق **هذا التبويب** — نفسُ منطق
            // `safeIds` في الأصل، لكنّ الاسمَ يأتي معه فيملأ عمودَ الصندوق.
            safeNames: {
              for (final s in _visibleSafes(safes, safeType, searchQuery,
                  branchNames))
                s.id: s.name,
            },
            searchQuery: searchQuery,
          ),
        ),
      ],
    );
  }
}

/// الصناديقُ الظاهرةُ في هذا التبويب بعد النوع والبحث.
///
/// ⚠️ **البحثُ يرشّح اللوحَين معاً**: لو رُشّحت البطاقاتُ وحدَها لبقيت حركاتُ
/// صندوقٍ اختفت بطاقتُه معروضةً — لوحان يقولان شيئَين عن نفس الترشيح.
List<SafeData> _visibleSafes(
  AsyncValue<List<SafeData>> safes,
  String safeType,
  String searchQuery,
  Map<int, String> branchNames,
) {
  final list = safes.value ?? const <SafeData>[];
  return list.where((s) => s.safeType == safeType).where((s) {
    if (searchQuery.isEmpty) return true;
    if (s.name.toLowerCase().contains(searchQuery)) return true;
    final branch = s.branchId == null ? null : branchNames[s.branchId];
    return (branch ?? '').toLowerCase().contains(searchQuery);
  }).toList();
}

class _SafesPane extends StatefulWidget {
  const _SafesPane({
    required this.safes,
    required this.safeType,
    required this.emptyLabel,
    required this.searchQuery,
    required this.branchNames,
  });

  final AsyncValue<List<SafeData>> safes;
  final String safeType;
  final String emptyLabel;
  final String searchQuery;
  final Map<int, String> branchNames;

  @override
  State<_SafesPane> createState() => _SafesPaneState();
}

class _SafesPaneState extends State<_SafesPane> {
  // Issue UX-SCROLL — نفسُ سببِ الأصل: متحكّمٌ في الحالة كي لا يضيع موضعُ
  // التمرير مع كلّ بثٍّ جديدٍ للصناديق.
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleSafes(
      widget.safes,
      widget.safeType,
      widget.searchQuery,
      widget.branchNames,
    );

    final Widget body = switch (widget.safes) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError(:final error) => Center(child: Text(friendlyError(error))),
      _ when visible.isEmpty => Center(
          child: Text(
            widget.searchQuery.isNotEmpty
                ? 'لا توجد صناديق مطابقة'
                : widget.emptyLabel,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
      _ => ListView.separated(
          controller: _controller,
          padding: const EdgeInsets.all(8),
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            final s = visible[i];
            return TreasurySafeCardPicpos(
              name: s.name,
              safeType: s.safeType,
              balance: s.balance,
              isDefault: s.isDefault,
              branchName:
                  s.branchId == null ? null : widget.branchNames[s.branchId],
            );
          },
        ),
    };

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: TreasuryPicposTokens.hairlineOf(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              color: TreasuryPicposTokens.fieldOf(context),
              border: Border(
                bottom: BorderSide(color: TreasuryPicposTokens.hairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'الصناديق',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '${visible.length} صندوق',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
